use super::models::{NetworkType, ProtocolType, ProxyNode, SecurityType};
use crate::utils::{CoreError, Result};
use base64::Engine;
use std::collections::HashMap;
use url::Url;

pub struct ConfigParser;

impl ConfigParser {
    /// Parse any single URL or JSON configuration
    pub fn parse(input: &str) -> Result<ProxyNode> {
        let trimmed = input.trim();
        if trimmed.starts_with('{') {
            return Self::parse_json(trimmed);
        } else if trimmed.starts_with("vless://") {
            return Self::parse_vless(trimmed);
        } else if trimmed.starts_with("vmess://") {
            return Self::parse_vmess(trimmed);
        } else if trimmed.starts_with("trojan://") {
            return Self::parse_trojan(trimmed);
        } else if trimmed.starts_with("ss://") {
            return Self::parse_shadowsocks(trimmed);
        }
        Err(CoreError::InvalidConfig("Unsupported or invalid configuration format".into()))
    }

    /// Parse batch subscription or newline-separated configurations
    pub fn parse_batch(content: &str) -> Vec<ProxyNode> {
        let mut nodes = Vec::new();

        // Check if content is base64 encoded
        let decoded = if let Ok(bytes) = base64::engine::general_purpose::STANDARD.decode(content.trim()) {
            String::from_utf8(bytes).unwrap_or_else(|_| content.to_string())
        } else if let Ok(bytes) = base64::engine::general_purpose::URL_SAFE.decode(content.trim()) {
            String::from_utf8(bytes).unwrap_or_else(|_| content.to_string())
        } else {
            content.to_string()
        };

        for line in decoded.lines() {
            let line = line.trim();
            if line.is_empty() {
                continue;
            }
            if let Ok(node) = Self::parse(line) {
                nodes.push(node);
            }
        }
        nodes
    }

    pub fn parse_vless(uri: &str) -> Result<ProxyNode> {
        let url = Url::parse(uri).map_err(|e| CoreError::ParseError(e.to_string()))?;
        let uuid = url.username().to_string();
        if uuid.is_empty() {
            return Err(CoreError::InvalidConfig("Missing UUID in VLESS URL".into()));
        }
        let address = url.host_str().ok_or_else(|| CoreError::InvalidConfig("Missing server host".into()))?.to_string();
        let port = url.port().ok_or_else(|| CoreError::InvalidConfig("Missing server port".into()))?;

        let params: HashMap<String, String> = url.query_pairs().into_owned().collect();
        let name = url.fragment().map(|f| urlencoding::decode(f).unwrap_or_default().to_string())
            .unwrap_or_else(|| format!("{}:{}", address, port));

        let network_str = params.get("type").map(|s| s.as_str()).unwrap_or("tcp");
        let network = match network_str {
            "xhttp" => NetworkType::Xhttp,
            "splithttp" => NetworkType::SplitHttp,
            "ws" => NetworkType::Ws,
            "grpc" => NetworkType::Grpc,
            "h2" => NetworkType::H2,
            "httpupgrade" => NetworkType::HttpUpgrade,
            _ => NetworkType::Tcp,
        };

        let sec_str = params.get("security").map(|s| s.as_str()).unwrap_or("none");
        let security = match sec_str {
            "tls" => SecurityType::Tls,
            "reality" => SecurityType::Reality,
            _ => SecurityType::None,
        };

        Ok(ProxyNode {
            id: generate_id(),
            name,
            protocol: ProtocolType::Vless,
            address,
            port,
            uuid_or_password: uuid,
            alter_id: 0,
            cipher: None,
            network,
            path: params.get("path").cloned(),
            host: params.get("host").cloned(),
            service_name: params.get("serviceName").cloned(),
            security,
            sni: params.get("sni").cloned(),
            alpn: params.get("alpn").map(|a| a.split(',').map(|s| s.to_string()).collect()),
            allow_insecure: params.get("allowInsecure").map(|s| s == "1" || s == "true").unwrap_or(false),
            fingerprint: params.get("fp").cloned(),
            public_key: params.get("pbk").cloned(),
            short_id: params.get("sid").cloned(),
            spider_x: params.get("spx").cloned(),
            mode: params.get("mode").cloned(),
            extra: params.get("extra").cloned(),
            subscription_id: None,
            latency_ms: None,
            last_tested_at: None,
            is_active: false,
            original_address: None,
        })
    }

    pub fn parse_trojan(uri: &str) -> Result<ProxyNode> {
        let url = Url::parse(uri).map_err(|e| CoreError::ParseError(e.to_string()))?;
        let password = url.username().to_string();
        if password.is_empty() {
            return Err(CoreError::InvalidConfig("Missing password in Trojan URL".into()));
        }
        let address = url.host_str().ok_or_else(|| CoreError::InvalidConfig("Missing host".into()))?.to_string();
        let port = url.port().ok_or_else(|| CoreError::InvalidConfig("Missing port".into()))?;

        let params: HashMap<String, String> = url.query_pairs().into_owned().collect();
        let name = url.fragment().map(|f| urlencoding::decode(f).unwrap_or_default().to_string())
            .unwrap_or_else(|| format!("Trojan-{}:{}", address, port));

        let network_str = params.get("type").map(|s| s.as_str()).unwrap_or("tcp");
        let network = match network_str {
            "ws" => NetworkType::Ws,
            "grpc" => NetworkType::Grpc,
            _ => NetworkType::Tcp,
        };

        let sec_str = params.get("security").map(|s| s.as_str()).unwrap_or("tls");
        let security = match sec_str {
            "none" => SecurityType::None,
            _ => SecurityType::Tls,
        };

        Ok(ProxyNode {
            id: generate_id(),
            name,
            protocol: ProtocolType::Trojan,
            address,
            port,
            uuid_or_password: password,
            alter_id: 0,
            cipher: None,
            network,
            path: params.get("path").cloned(),
            host: params.get("host").cloned(),
            service_name: params.get("serviceName").cloned(),
            security,
            sni: params.get("sni").cloned(),
            alpn: params.get("alpn").map(|a| a.split(',').map(|s| s.to_string()).collect()),
            allow_insecure: params.get("allowInsecure").map(|s| s == "1" || s == "true").unwrap_or(false),
            fingerprint: params.get("fp").cloned(),
            public_key: None,
            short_id: None,
            spider_x: None,
            mode: None,
            extra: None,
            subscription_id: None,
            latency_ms: None,
            last_tested_at: None,
            is_active: false,
            original_address: None,
        })
    }

    pub fn parse_shadowsocks(uri: &str) -> Result<ProxyNode> {
        let url = Url::parse(uri).map_err(|e| CoreError::ParseError(e.to_string()))?;
        let name = url.fragment().map(|f| urlencoding::decode(f).unwrap_or_default().to_string())
            .unwrap_or_else(|| "Shadowsocks Node".into());

        let address = url.host_str().ok_or_else(|| CoreError::InvalidConfig("Missing host".into()))?.to_string();
        let port = url.port().ok_or_else(|| CoreError::InvalidConfig("Missing port".into()))?;

        // User info could be method:password or base64(method:password)
        let userinfo = url.username();
        let (cipher, password) = if userinfo.contains(':') {
            let parts: Vec<&str> = userinfo.splitn(2, ':').collect();
            (Some(parts[0].to_string()), parts[1].to_string())
        } else if let Ok(decoded) = base64::engine::general_purpose::STANDARD.decode(userinfo) {
            let str_val = String::from_utf8(decoded).unwrap_or_default();
            let parts: Vec<&str> = str_val.splitn(2, ':').collect();
            if parts.len() == 2 {
                (Some(parts[0].to_string()), parts[1].to_string())
            } else {
                (None, userinfo.to_string())
            }
        } else {
            (None, userinfo.to_string())
        };

        Ok(ProxyNode {
            id: generate_id(),
            name,
            protocol: ProtocolType::Shadowsocks,
            address,
            port,
            uuid_or_password: password,
            alter_id: 0,
            cipher,
            network: NetworkType::Tcp,
            path: None,
            host: None,
            service_name: None,
            security: SecurityType::None,
            sni: None,
            alpn: None,
            allow_insecure: false,
            fingerprint: None,
            public_key: None,
            short_id: None,
            spider_x: None,
            mode: None,
            extra: None,
            subscription_id: None,
            latency_ms: None,
            last_tested_at: None,
            is_active: false,
            original_address: None,
        })
    }

    pub fn parse_vmess(uri: &str) -> Result<ProxyNode> {
        let payload = uri.trim_start_matches("vmess://");
        let decoded_json = base64::engine::general_purpose::STANDARD
            .decode(payload)
            .map_err(|e| CoreError::ParseError(format!("Invalid base64 vmess: {}", e)))?;
        
        let json_str = String::from_utf8(decoded_json)
            .map_err(|e| CoreError::ParseError(format!("Invalid utf8 in vmess payload: {}", e)))?;

        let val: serde_json::Value = serde_json::from_str(&json_str)
            .map_err(|e| CoreError::ParseError(format!("Invalid JSON in vmess: {}", e)))?;

        let address = val["add"].as_str().ok_or_else(|| CoreError::InvalidConfig("Missing add in vmess".into()))?.to_string();
        let port = val["port"].as_u64().or_else(|| val["port"].as_str().and_then(|s| s.parse().ok()))
            .ok_or_else(|| CoreError::InvalidConfig("Missing port in vmess".into()))? as u16;
        let uuid = val["id"].as_str().ok_or_else(|| CoreError::InvalidConfig("Missing id in vmess".into()))?.to_string();
        let name = val["ps"].as_str().unwrap_or("VMess Node").to_string();

        let net_str = val["net"].as_str().unwrap_or("tcp");
        let network = match net_str {
            "xhttp" => NetworkType::Xhttp,
            "splithttp" => NetworkType::SplitHttp,
            "ws" => NetworkType::Ws,
            "grpc" => NetworkType::Grpc,
            "h2" => NetworkType::H2,
            _ => NetworkType::Tcp,
        };

        let tls_str = val["tls"].as_str().unwrap_or("");
        let security = if tls_str == "tls" {
            SecurityType::Tls
        } else {
            SecurityType::None
        };

        Ok(ProxyNode {
            id: generate_id(),
            name,
            protocol: ProtocolType::Vmess,
            address,
            port,
            uuid_or_password: uuid,
            alter_id: val["aid"].as_u64().unwrap_or(0) as u32,
            cipher: val["scy"].as_str().map(|s| s.to_string()),
            network,
            path: val["path"].as_str().map(|s| s.to_string()),
            host: val["host"].as_str().map(|s| s.to_string()),
            service_name: None,
            security,
            sni: val["sni"].as_str().map(|s| s.to_string()),
            alpn: val["alpn"].as_str().map(|s| s.split(',').map(|p| p.to_string()).collect()),
            allow_insecure: false,
            fingerprint: val["fp"].as_str().map(|s| s.to_string()),
            public_key: None,
            short_id: None,
            spider_x: None,
            mode: None,
            extra: None,
            subscription_id: None,
            latency_ms: None,
            last_tested_at: None,
            is_active: false,
            original_address: None,
        })
    }

    pub fn parse_json(json_str: &str) -> Result<ProxyNode> {
        let val: serde_json::Value = serde_json::from_str(json_str)
            .map_err(|e| CoreError::ParseError(format!("Malformed JSON: {}", e)))?;

        // If it's directly our ProxyNode structure:
        if let Ok(node) = serde_json::from_value::<ProxyNode>(val.clone()) {
            return Ok(node);
        }

        // Generic Xray Outbound fallback extraction
        let outbound = if val.is_array() {
            &val[0]
        } else if val.get("outbounds").is_some() {
            &val["outbounds"][0]
        } else {
            &val
        };

        let protocol_str = outbound["protocol"].as_str().unwrap_or("vless");
        let protocol = match protocol_str {
            "vless" => ProtocolType::Vless,
            "vmess" => ProtocolType::Vmess,
            "trojan" => ProtocolType::Trojan,
            "shadowsocks" => ProtocolType::Shadowsocks,
            _ => ProtocolType::CustomJson,
        };

        let tag = outbound["tag"].as_str().unwrap_or("Custom Outbound").to_string();

        Ok(ProxyNode {
            id: generate_id(),
            name: tag,
            protocol,
            address: "127.0.0.1".into(),
            port: 443,
            uuid_or_password: "".into(),
            alter_id: 0,
            cipher: None,
            network: NetworkType::Tcp,
            path: None,
            host: None,
            service_name: None,
            security: SecurityType::None,
            sni: None,
            alpn: None,
            allow_insecure: false,
            fingerprint: None,
            public_key: None,
            short_id: None,
            spider_x: None,
            subscription_id: None,
            latency_ms: None,
            last_tested_at: None,
            is_active: false,
            original_address: None,
        })
    }
}

fn generate_id() -> String {
    use rand::Rng;
    let mut rng = rand::thread_rng();
    let num: u64 = rng.gen();
    format!("{:016x}", num)
}

mod urlencoding {
    pub fn decode(input: &str) -> Option<String> {
        url::form_urlencoded::parse(input.as_bytes())
            .map(|(k, _)| k.into_owned())
            .next()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_vless_parsing() {
        let vless_url = "vless://b831381d-6324-4d53-ad4f-8cda48b30811@example.com:443?type=ws&security=tls&path=%2Fchat&host=example.com&sni=example.com#TestNode";
        let node = ConfigParser::parse(vless_url).unwrap();

        assert_eq!(node.name, "TestNode");
        assert_eq!(node.protocol, ProtocolType::Vless);
        assert_eq!(node.address, "example.com");
        assert_eq!(node.port, 443);
        assert_eq!(node.uuid_or_password, "b831381d-6324-4d53-ad4f-8cda48b30811");
        assert_eq!(node.network, NetworkType::Ws);
        assert_eq!(node.security, SecurityType::Tls);
        assert_eq!(node.host.as_deref(), Some("example.com"));
        assert_eq!(node.sni.as_deref(), Some("example.com"));
    }
}
