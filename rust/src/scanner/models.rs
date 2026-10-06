use serde::{Deserialize, Serialize};
use std::net::IpAddr;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ScannerOptions {
    pub candidate_count: usize,
    pub concurrent_workers: usize,
    pub tcp_timeout_ms: u64,
    pub tls_timeout_ms: u64,
    pub target_port: u16,
    pub target_sni: Option<String>,
    pub target_host: Option<String>,
    pub target_path: Option<String>,
    pub custom_prefix: Option<String>,
    pub mock_mode: bool,
}

impl Default for ScannerOptions {
    fn default() -> Self {
        Self {
            candidate_count: 50,
            concurrent_workers: 20,
            tcp_timeout_ms: 2000,
            tls_timeout_ms: 3000,
            target_port: 443,
            target_sni: None,
            target_host: None,
            target_path: None,
            custom_prefix: None,
            mock_mode: false,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ScanResult {
    pub ip: String,
    pub port: u16,
    pub tcp_success: bool,
    pub tcp_latency_ms: Option<u64>,
    pub tls_success: bool,
    pub tls_latency_ms: Option<u64>,
    pub protocol_success: bool,
    pub total_latency_ms: Option<u64>,
    pub error: Option<String>,
    pub rank_score: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum ScannerEvent {
    Started { total_candidates: usize },
    Progress { scanned: usize, total: usize, current_ip: String },
    Result(ScanResult),
    Finished { total_tested: usize, successful_count: usize, best_ip: Option<ScanResult> },
    Cancelled,
    Error(String),
}
