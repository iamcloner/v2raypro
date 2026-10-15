use std::net::{IpAddr, SocketAddr};
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::io::AsyncWriteExt;
use tokio::net::TcpStream;
use tokio::time::timeout;
use tokio_rustls::rustls::pki_types::ServerName;
use tokio_rustls::rustls::{ClientConfig, RootCertStore};
use tokio_rustls::TlsConnector;

pub struct NetworkProbe {
    tls_config: Arc<ClientConfig>,
}

pub struct ProbeResult {
    pub ip: IpAddr,
    pub tcp_success: bool,
    pub tcp_latency_ms: Option<u64>,
    pub tls_success: bool,
    pub tls_latency_ms: Option<u64>,
    pub protocol_success: bool,
    pub total_latency_ms: Option<u64>,
    pub error: Option<String>,
}

impl NetworkProbe {
    pub fn new() -> Self {
        let mut root_store = RootCertStore::empty();
        root_store.extend(webpki_roots::TLS_SERVER_ROOTS.iter().cloned());

        let mut config = ClientConfig::builder()
            .with_root_certificates(root_store)
            .with_no_client_auth();

        // Enable ALPN for http/1.1 and h2
        config.alpn_protocols = vec![b"h2".to_vec(), b"http/1.1".to_vec()];

        Self {
            tls_config: Arc::new(config),
        }
    }

    /// Perform a staged benchmark (TCP -> TLS Handshake -> Protocol Verification)
    pub async fn test_ip(
        &self,
        ip: IpAddr,
        port: u16,
        sni: Option<&str>,
        host: Option<&str>,
        path: Option<&str>,
        tcp_timeout: Duration,
        tls_timeout: Duration,
    ) -> ProbeResult {
        let addr = SocketAddr::new(ip, port);
        let start_total = Instant::now();

        // 1. TCP Connect stage
        let tcp_start = Instant::now();
        let tcp_stream = match timeout(tcp_timeout, TcpStream::connect(addr)).await {
            Ok(Ok(stream)) => stream,
            Ok(Err(e)) => {
                return ProbeResult {
                    ip,
                    tcp_success: false,
                    tcp_latency_ms: None,
                    tls_success: false,
                    tls_latency_ms: None,
                    protocol_success: false,
                    total_latency_ms: None,
                    error: Some(format!("TCP Connect failed: {}", e)),
                };
            }
            Err(_) => {
                return ProbeResult {
                    ip,
                    tcp_success: false,
                    tcp_latency_ms: None,
                    tls_success: false,
                    tls_latency_ms: None,
                    protocol_success: false,
                    total_latency_ms: None,
                    error: Some("TCP Connect timeout".into()),
                };
            }
        };
        let tcp_latency = tcp_start.elapsed().as_millis() as u64;

        // If no SNI is required or port is non-TLS (e.g., 80)
        let effective_sni = match sni {
            Some(s) if !s.is_empty() => s,
            _ => {
                return ProbeResult {
                    ip,
                    tcp_success: true,
                    tcp_latency_ms: Some(tcp_latency),
                    tls_success: false,
                    tls_latency_ms: None,
                    protocol_success: true,
                    total_latency_ms: Some(tcp_latency),
                    error: None,
                };
            }
        };

        // 2. TLS Handshake stage
        let connector = TlsConnector::from(self.tls_config.clone());
        let server_name = match ServerName::try_from(effective_sni.to_string()) {
            Ok(name) => name,
            Err(e) => {
                return ProbeResult {
                    ip,
                    tcp_success: true,
                    tcp_latency_ms: Some(tcp_latency),
                    tls_success: false,
                    tls_latency_ms: None,
                    protocol_success: false,
                    total_latency_ms: Some(tcp_latency),
                    error: Some(format!("Invalid SNI name: {}", e)),
                };
            }
        };

        let tls_start = Instant::now();
        let mut tls_stream = match timeout(tls_timeout, connector.connect(server_name, tcp_stream)).await {
            Ok(Ok(stream)) => stream,
            Ok(Err(e)) => {
                return ProbeResult {
                    ip,
                    tcp_success: true,
                    tcp_latency_ms: Some(tcp_latency),
                    tls_success: false,
                    tls_latency_ms: None,
                    protocol_success: false,
                    total_latency_ms: Some(tcp_latency),
                    error: Some(format!("TLS Handshake failed: {}", e)),
                };
            }
            Err(_) => {
                return ProbeResult {
                    ip,
                    tcp_success: true,
                    tcp_latency_ms: Some(tcp_latency),
                    tls_success: false,
                    tls_latency_ms: None,
                    protocol_success: false,
                    total_latency_ms: Some(tcp_latency),
                    error: Some("TLS Handshake timeout".into()),
                };
            }
        };
        let tls_latency = tls_start.elapsed().as_millis() as u64;

        // 3. Lightweight HTTP/WebSocket probe if host/path is provided
        let target_host = host.unwrap_or(effective_sni);
        let target_path = path.unwrap_or("/");
        let http_probe_req = format!(
            "GET {} HTTP/1.1\r\nHost: {}\r\nUser-Agent: Mozilla/5.0\r\nConnection: close\r\n\r\n",
            target_path, target_host
        );

        let proto_success = match timeout(Duration::from_millis(1500), tls_stream.write_all(http_probe_req.as_bytes())).await {
            Ok(Ok(_)) => true,
            _ => false,
        };

        let total_latency = start_total.elapsed().as_millis() as u64;

        ProbeResult {
            ip,
            tcp_success: true,
            tcp_latency_ms: Some(tcp_latency),
            tls_success: true,
            tls_latency_ms: Some(tls_latency),
            protocol_success: proto_success,
            total_latency_ms: Some(total_latency),
            error: None,
        }
    }
}

impl Default for NetworkProbe {
    fn default() -> Self {
        Self::new()
    }
}
