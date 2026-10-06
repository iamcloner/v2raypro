use super::candidates::CandidateGenerator;
use super::models::{ScanResult, ScannerEvent, ScannerOptions};
use crate::networking::NetworkProbe;
use futures::stream::{self, StreamExt};
use rand::Rng;
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::mpsc::Sender;

pub struct ScannerEngine {
    probe: Arc<NetworkProbe>,
    is_cancelled: Arc<AtomicBool>,
}

impl ScannerEngine {
    pub fn new() -> Self {
        Self {
            probe: Arc::new(NetworkProbe::new()),
            is_cancelled: Arc::new(AtomicBool::new(false)),
        }
    }

    pub fn cancel(&self) {
        self.is_cancelled.store(true, Ordering::SeqCst);
    }

    pub async fn run_scan(&self, options: ScannerOptions, event_sender: Sender<ScannerEvent>) {
        self.is_cancelled.store(false, Ordering::SeqCst);

        if options.mock_mode {
            self.run_mock_scan(options, event_sender).await;
            return;
        }

        let candidates = CandidateGenerator::generate_candidates(
            options.candidate_count,
            options.custom_prefix.as_deref(),
        );

        let total = candidates.len();
        let _ = event_sender.send(ScannerEvent::Started { total_candidates: total }).await;

        let scanned_counter = Arc::new(AtomicUsize::new(0));
        let probe = self.probe.clone();
        let is_cancelled = self.is_cancelled.clone();

        let tcp_timeout = Duration::from_millis(options.tcp_timeout_ms);
        let tls_timeout = Duration::from_millis(options.tls_timeout_ms);
        let port = options.target_port;
        let sni = options.target_sni.clone();
        let host = options.target_host.clone();
        let path = options.target_path.clone();

        let mut best_result: Option<ScanResult> = None;
        let mut successful_count = 0;

        let scan_stream = stream::iter(candidates).map(|ip| {
            let probe = probe.clone();
            let is_cancelled = is_cancelled.clone();
            let sni = sni.clone();
            let host = host.clone();
            let path = path.clone();

            async move {
                if is_cancelled.load(Ordering::SeqCst) {
                    return None;
                }

                let res = probe.test_ip(
                    ip,
                    port,
                    sni.as_deref(),
                    host.as_deref(),
                    path.as_deref(),
                    tcp_timeout,
                    tls_timeout,
                ).await;

                // Calculate weighted rank score (lower is better; penalize failures)
                let rank_score = if res.tcp_success && res.tls_success {
                    res.total_latency_ms.unwrap_or(9999) as f64
                } else if res.tcp_success {
                    (res.tcp_latency_ms.unwrap_or(9999) as f64) + 500.0
                } else {
                    99999.0
                };

                Some(ScanResult {
                    ip: ip.to_string(),
                    port,
                    tcp_success: res.tcp_success,
                    tcp_latency_ms: res.tcp_latency_ms,
                    tls_success: res.tls_success,
                    tls_latency_ms: res.tls_latency_ms,
                    protocol_success: res.protocol_success,
                    total_latency_ms: res.total_latency_ms,
                    error: res.error,
                    rank_score,
                })
            }
        }).buffer_unordered(options.concurrent_workers);

        tokio::pin!(scan_stream);

        while let Some(item) = scan_stream.next().await {
            if self.is_cancelled.load(Ordering::SeqCst) {
                let _ = event_sender.send(ScannerEvent::Cancelled).await;
                return;
            }

            if let Some(res) = item {
                let current_scanned = scanned_counter.fetch_add(1, Ordering::SeqCst) + 1;

                if res.tcp_success && res.tls_success {
                    successful_count += 1;
                    if best_result.as_ref().map_or(true, |b| res.rank_score < b.rank_score) {
                        best_result = Some(res.clone());
                    }
                }

                let _ = event_sender.send(ScannerEvent::Progress {
                    scanned: current_scanned,
                    total,
                    current_ip: res.ip.clone(),
                }).await;

                let _ = event_sender.send(ScannerEvent::Result(res)).await;
            }
        }

        let _ = event_sender.send(ScannerEvent::Finished {
            total_tested: scanned_counter.load(Ordering::SeqCst),
            successful_count,
            best_ip: best_result,
        }).await;
    }

    async fn run_mock_scan(&self, options: ScannerOptions, event_sender: Sender<ScannerEvent>) {
        let total = options.candidate_count;
        let _ = event_sender.send(ScannerEvent::Started { total_candidates: total }).await;

        let mut rng = rand::thread_rng();
        let mut best_result: Option<ScanResult> = None;
        let mut successful_count = 0;

        for i in 1..=total {
            if self.is_cancelled.load(Ordering::SeqCst) {
                let _ = event_sender.send(ScannerEvent::Cancelled).await;
                return;
            }

            tokio::time::sleep(Duration::from_millis(50)).await;

            let ip = format!("104.16.{}.{}", rng.gen_range(1..250), rng.gen_range(1..254));
            let success = rng.gen_bool(0.75);
            let tcp_latency = if success { Some(rng.gen_range(28..120)) } else { None };
            let tls_latency = if success { Some(rng.gen_range(35..150)) } else { None };
            let total_latency = tcp_latency.zip(tls_latency).map(|(a, b)| a + b);

            let res = ScanResult {
                ip: ip.clone(),
                port: options.target_port,
                tcp_success: success,
                tcp_latency_ms: tcp_latency,
                tls_success: success,
                tls_latency_ms: tls_latency,
                protocol_success: success,
                total_latency_ms: total_latency,
                error: if success { None } else { Some("Handshake timeout".into()) },
                rank_score: total_latency.unwrap_or(9999) as f64,
            };

            if success {
                successful_count += 1;
                if best_result.as_ref().map_or(true, |b| res.rank_score < b.rank_score) {
                    best_result = Some(res.clone());
                }
            }

            let _ = event_sender.send(ScannerEvent::Progress {
                scanned: i,
                total,
                current_ip: ip,
            }).await;

            let _ = event_sender.send(ScannerEvent::Result(res)).await;
        }

        let _ = event_sender.send(ScannerEvent::Finished {
            total_tested: total,
            successful_count,
            best_ip: best_result,
        }).await;
    }
}

impl Default for ScannerEngine {
    fn default() -> Self {
        Self::new()
    }
}
