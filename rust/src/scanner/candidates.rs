use crate::utils::cloudflare_ranges::{CloudflareDetector, CLOUDFLARE_IPV4_CIDRS};
use ipnet::Ipv4Net;
use rand::seq::SliceRandom;
use rand::Rng;
use std::net::{IpAddr, Ipv4Addr};

pub struct CandidateGenerator;

impl CandidateGenerator {
    /// Generate a sampled, diversified list of Cloudflare candidate IPs
    pub fn generate_candidates(
        count: usize,
        custom_prefix: Option<&str>,
    ) -> Vec<IpAddr> {
        let mut rng = rand::thread_rng();

        let subnets: Vec<Ipv4Net> = if let Some(prefix) = custom_prefix {
            if let Ok(net) = prefix.parse::<Ipv4Net>() {
                vec![net]
            } else {
                CloudflareDetector::new().get_ipv4_nets()
            }
        } else {
            CloudflareDetector::new().get_ipv4_nets()
        };

        if subnets.is_empty() {
            return Vec::new();
        }

        let mut candidates = Vec::with_capacity(count);

        // Stratified sampling across available subnets to ensure high variety
        for _ in 0..count {
            let subnet = subnets.choose(&mut rng).unwrap();
            let ip = Self::random_ip_in_subnet(subnet, &mut rng);
            candidates.push(IpAddr::V4(ip));
        }

        candidates
    }

    fn random_ip_in_subnet<R: Rng>(subnet: &Ipv4Net, rng: &mut R) -> Ipv4Addr {
        let net_addr = u32::from(subnet.network());
        let hostmask = !u32::from(subnet.netmask());
        
        // Avoid network address (0) and broadcast (last)
        let offset = if hostmask > 2 {
            rng.gen_range(1..hostmask)
        } else {
            1
        };

        Ipv4Addr::from(net_addr + offset)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_candidate_generation() {
        let detector = CloudflareDetector::new();
        let candidates = CandidateGenerator::generate_candidates(20, None);

        assert_eq!(candidates.len(), 20);
        for ip in &candidates {
            assert!(detector.is_cloudflare_ip(ip));
        }
    }
}
