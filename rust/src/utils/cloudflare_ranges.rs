use std::net::IpAddr;
use ipnet::IpNet;

/// Official Cloudflare IPv4 CIDR ranges
pub const CLOUDFLARE_IPV4_CIDRS: &[&str] = &[
    "173.245.48.0/20",
    "103.21.244.0/22",
    "103.22.200.0/22",
    "103.31.4.0/22",
    "141.101.64.0/18",
    "108.162.192.0/18",
    "190.93.240.0/20",
    "188.114.96.0/20",
    "197.234.240.0/22",
    "198.41.128.0/17",
    "162.158.0.0/15",
    "104.16.0.0/13",
    "104.24.0.0/14",
    "172.64.0.0/13",
    "131.0.72.0/22",
];

/// Official Cloudflare IPv6 CIDR ranges
pub const CLOUDFLARE_IPV6_CIDRS: &[&str] = &[
    "2400:cb00::/32",
    "2606:4700::/32",
    "2803:f800::/32",
    "2405:b500::/32",
    "2405:8100::/32",
    "2a06:98c0::/29",
    "2c0f:f248::/32",
];

pub struct CloudflareDetector {
    nets: Vec<IpNet>,
}

impl CloudflareDetector {
    pub fn new() -> Self {
        let mut nets = Vec::new();
        for cidr in CLOUDFLARE_IPV4_CIDRS.iter().chain(CLOUDFLARE_IPV6_CIDRS.iter()) {
            if let Ok(net) = cidr.parse::<IpNet>() {
                nets.push(net);
            }
        }
        Self { nets }
    }

    pub fn is_cloudflare_ip(&self, ip: &IpAddr) -> bool {
        self.nets.iter().any(|net| net.contains(ip))
    }

    pub fn get_ipv4_nets(&self) -> Vec<ipnet::Ipv4Net> {
        CLOUDFLARE_IPV4_CIDRS
            .iter()
            .filter_map(|cidr| cidr.parse::<ipnet::Ipv4Net>().ok())
            .collect()
    }
}

impl Default for CloudflareDetector {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::str::FromStr;

    #[test]
    fn test_cloudflare_ip_detection() {
        let detector = CloudflareDetector::new();
        let cf_ip = IpAddr::from_str("104.16.1.1").unwrap();
        let non_cf_ip = IpAddr::from_str("8.8.8.8").unwrap();

        assert!(detector.is_cloudflare_ip(&cf_ip));
        assert!(!detector.is_cloudflare_ip(&non_cf_ip));
    }
}
