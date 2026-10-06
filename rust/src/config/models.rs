use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ProtocolType {
    Vless,
    Vmess,
    Trojan,
    Shadowsocks,
    CustomJson,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum NetworkType {
    Tcp,
    Ws,
    Grpc,
    H2,
    HttpUpgrade,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum SecurityType {
    None,
    Tls,
    Reality,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProxyNode {
    pub id: String,
    pub name: String,
    pub protocol: ProtocolType,
    pub address: String, // Server domain or IP
    pub port: u16,
    pub uuid_or_password: String, // UUID for VLESS/VMess, password for Trojan/SS
    
    // VMess specifics
    #[serde(default)]
    pub alter_id: u32,
    #[serde(default)]
    pub cipher: Option<String>,

    // Transport network settings
    #[serde(default = "default_network")]
    pub network: NetworkType,
    #[serde(default)]
    pub path: Option<String>,
    #[serde(default)]
    pub host: Option<String>,
    #[serde(default)]
    pub service_name: Option<String>, // gRPC

    // Security & TLS
    #[serde(default = "default_security")]
    pub security: SecurityType,
    #[serde(default)]
    pub sni: Option<String>,
    #[serde(default)]
    pub alpn: Option<Vec<String>>,
    #[serde(default)]
    pub allow_insecure: bool,
    #[serde(default)]
    pub fingerprint: Option<String>,

    // Reality specifics
    #[serde(default)]
    pub public_key: Option<String>,
    #[serde(default)]
    pub short_id: Option<String>,
    #[serde(default)]
    pub spider_x: Option<String>,

    // Metadata & Benchmarks
    #[serde(default)]
    pub subscription_id: Option<String>,
    #[serde(default)]
    pub latency_ms: Option<u64>,
    #[serde(default)]
    pub last_tested_at: Option<String>,
    #[serde(default)]
    pub is_active: bool,
    #[serde(default)]
    pub original_address: Option<String>, // For Cloudflare IP rollback
}

fn default_network() -> NetworkType {
    NetworkType::Tcp
}

fn default_security() -> SecurityType {
    SecurityType::None
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Subscription {
    pub id: String,
    pub name: String,
    pub url: String,
    pub auto_update: bool,
    pub last_updated_at: Option<String>,
    pub node_count: usize,
}
