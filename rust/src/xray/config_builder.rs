use crate::config::models::{NetworkType, ProtocolType, ProxyNode, SecurityType};
use serde_json::{json, Value};

pub struct XrayConfigBuilder;

impl XrayConfigBuilder {
    /// Builds a full, runnable Xray JSON configuration for local proxy / TUN
    pub fn build(node: &ProxyNode, socks_port: u16, http_port: u16) -> Value {
        let outbound = Self::build_outbound(node);

        json!({
            "log": {
                "loglevel": "warning"
            },
            "inbounds": [
                {
                    "tag": "socks-in",
                    "port": socks_port,
                    "listen": "127.0.0.1",
                    "protocol": "socks",
                    "settings": {
                        "auth": "noauth",
                        "udp": true
                    },
                    "sniffing": {
                        "enabled": true,
                        "destOverride": ["http", "tls"]
                    }
                },
                {
                    "tag": "http-in",
                    "port": http_port,
                    "listen": "127.0.0.1",
                    "protocol": "http"
                }
            ],
            "outbounds": [
                outbound,
                {
                    "tag": "direct",
                    "protocol": "freedom"
                },
                {
                    "tag": "block",
                    "protocol": "blackhole"
                }
            ],
            "routing": {
                "domainStrategy": "IPIfNonMatch",
                "rules": [
                    {
                        "type": "field",
                        "outboundTag": "direct",
                        "ip": ["geoip:private"]
                    }
                ]
            }
        })
    }

    fn build_outbound(node: &ProxyNode) -> Value {
        match node.protocol {
            ProtocolType::Vless => Self::build_vless_outbound(node),
            ProtocolType::Vmess => Self::build_vmess_outbound(node),
            ProtocolType::Trojan => Self::build_trojan_outbound(node),
            ProtocolType::Shadowsocks => Self::build_ss_outbound(node),
            ProtocolType::CustomJson => json!({
                "tag": "proxy",
                "protocol": "freedom"
            }),
        }
    }

    fn build_vless_outbound(node: &ProxyNode) -> Value {
        let stream_settings = Self::build_stream_settings(node);

        json!({
            "tag": "proxy",
            "protocol": "vless",
            "settings": {
                "vnext": [
                    {
                        "address": node.address,
                        "port": node.port,
                        "users": [
                            {
                                "id": node.uuid_or_password,
                                "encryption": "none",
                                "level": 0
                            }
                        ]
                    }
                ]
            },
            "streamSettings": stream_settings
        })
    }

    fn build_vmess_outbound(node: &ProxyNode) -> Value {
        let stream_settings = Self::build_stream_settings(node);

        json!({
            "tag": "proxy",
            "protocol": "vmess",
            "settings": {
                "vnext": [
                    {
                        "address": node.address,
                        "port": node.port,
                        "users": [
                            {
                                "id": node.uuid_or_password,
                                "alterId": node.alter_id,
                                "security": node.cipher.as_deref().unwrap_or("auto"),
                                "level": 0
                            }
                        ]
                    }
                ]
            },
            "streamSettings": stream_settings
        })
    }

    fn build_trojan_outbound(node: &ProxyNode) -> Value {
        let stream_settings = Self::build_stream_settings(node);

        json!({
            "tag": "proxy",
            "protocol": "trojan",
            "settings": {
                "servers": [
                    {
                        "address": node.address,
                        "port": node.port,
                        "password": node.uuid_or_password,
                        "level": 0
                    }
                ]
            },
            "streamSettings": stream_settings
        })
    }

    fn build_ss_outbound(node: &ProxyNode) -> Value {
        json!({
            "tag": "proxy",
            "protocol": "shadowsocks",
            "settings": {
                "servers": [
                    {
                        "address": node.address,
                        "port": node.port,
                        "method": node.cipher.as_deref().unwrap_or("aes-256-gcm"),
                        "password": node.uuid_or_password,
                        "level": 0
                    }
                ]
            }
        })
    }

    fn build_stream_settings(node: &ProxyNode) -> Value {
        let network_str = match node.network {
            NetworkType::Xhttp | NetworkType::SplitHttp => "xhttp",
            NetworkType::Ws => "ws",
            NetworkType::Grpc => "grpc",
            NetworkType::H2 => "h2",
            NetworkType::HttpUpgrade => "httpupgrade",
            NetworkType::Tcp => "tcp",
        };

        let security_str = match node.security {
            SecurityType::Tls => "tls",
            SecurityType::Reality => "reality",
            SecurityType::None => "none",
        };

        let mut settings = json!({
            "network": network_str,
            "security": security_str
        });

        if let Some(sni) = &node.sni {
            if node.security == SecurityType::Tls {
                let mut tls_val = json!({
                    "serverName": sni,
                    "allowInsecure": node.allow_insecure,
                });
                if let Some(alpn) = &node.alpn {
                    tls_val["alpn"] = json!(alpn);
                }
                if let Some(fp) = &node.fingerprint {
                    tls_val["fingerprint"] = json!(fp);
                }
                settings["tlsSettings"] = tls_val;
            } else if node.security == SecurityType::Reality {
                let mut reality_val = json!({
                    "serverName": sni,
                    "publicKey": node.public_key.as_deref().unwrap_or(""),
                    "shortId": node.short_id.as_deref().unwrap_or(""),
                    "spiderX": node.spider_x.as_deref().unwrap_or("/")
                });
                if let Some(fp) = &node.fingerprint {
                    reality_val["fingerprint"] = json!(fp);
                }
                settings["realitySettings"] = reality_val;
            }
        }

        if node.network == NetworkType::Xhttp || node.network == NetworkType::SplitHttp {
            let mut xhttp_settings = json!({
                "path": node.path.as_deref().unwrap_or("/"),
                "host": node.host.as_deref().or(node.sni.as_deref()).unwrap_or(&node.address)
            });
            if let Some(mode) = &node.mode {
                xhttp_settings["mode"] = json!(mode);
            }
            if let Some(extra) = &node.extra {
                if let Ok(parsed_extra) = serde_json::from_str::<Value>(extra) {
                    xhttp_settings["extra"] = parsed_extra;
                } else {
                    xhttp_settings["extra"] = json!(extra);
                }
            }
            settings["xhttpSettings"] = xhttp_settings;
        } else if node.network == NetworkType::Ws {
            let mut ws_settings = json!({});
            if let Some(path) = &node.path {
                ws_settings["path"] = json!(path);
            }
            if let Some(host) = &node.host {
                ws_settings["headers"] = json!({ "Host": host });
            }
            settings["wsSettings"] = ws_settings;
        } else if node.network == NetworkType::Grpc {
            let mut grpc_settings = json!({});
            if let Some(service_name) = &node.service_name {
                grpc_settings["serviceName"] = json!(service_name);
            }
            settings["grpcSettings"] = grpc_settings;
        }

        settings
    }
}
