use v2raypro_core::config::{ConfigParser, NetworkType, ProtocolType, SecurityType};
use v2raypro_core::scanner::{CandidateGenerator, ScannerEngine, ScannerOptions};
use v2raypro_core::utils::CloudflareDetector;
use std::net::IpAddr;
use std::str::FromStr;
use tokio::sync::mpsc;

#[test]
fn test_cloudflare_detector() {
    let detector = CloudflareDetector::new();
    assert!(detector.is_cloudflare_ip(&IpAddr::from_str("104.16.12.34").unwrap()));
    assert!(detector.is_cloudflare_ip(&IpAddr::from_str("172.64.100.1").unwrap()));
    assert!(!detector.is_cloudflare_ip(&IpAddr::from_str("1.1.1.1").unwrap())); // DNS, not proxy range
    assert!(!detector.is_cloudflare_ip(&IpAddr::from_str("8.8.8.8").unwrap()));
}

#[test]
fn test_vless_url_parser() {
    let uri = "vless://4f38e788-b7fb-4811-9a99-b13c77d0cf9b@example.org:443?type=ws&security=tls&path=%2Fchat&host=example.org&sni=example.org#MyNode";
    let node = ConfigParser::parse(uri).expect("Failed to parse VLESS URI");

    assert_eq!(node.name, "MyNode");
    assert_eq!(node.protocol, ProtocolType::Vless);
    assert_eq!(node.address, "example.org");
    assert_eq!(node.port, 443);
    assert_eq!(node.uuid_or_password, "4f38e788-b7fb-4811-9a99-b13c77d0cf9b");
    assert_eq!(node.network, NetworkType::Ws);
    assert_eq!(node.security, SecurityType::Tls);
    assert_eq!(node.sni.as_deref(), Some("example.org"));
}

#[test]
fn test_candidate_generation() {
    let detector = CloudflareDetector::new();
    let candidates = CandidateGenerator::generate_candidates(50, None);

    assert_eq!(candidates.len(), 50);
    for ip in candidates {
        assert!(detector.is_cloudflare_ip(&ip));
    }
}

#[tokio::test]
async fn test_mock_scanner() {
    let scanner = ScannerEngine::new();
    let (tx, mut rx) = mpsc::channel(100);

    let options = ScannerOptions {
        candidate_count: 10,
        mock_mode: true,
        ..Default::default()
    };

    tokio::spawn(async move {
        scanner.run_scan(options, tx).await;
    });

    let mut result_count = 0;
    while let Some(evt) = rx.recv().await {
        if let v2raypro_core::scanner::ScannerEvent::Result(_) = evt {
            result_count += 1;
        }
    }

    assert_eq!(result_count, 10);
}
