import "dart:convert";
import "dart:io";
import "../models/proxy_node.dart";
import "../models/routing_rule.dart";

/// Unified generator for Xray and Sing-box configuration formats
class ConfigGenerator {
  static const List<String> defaultDns = ["1.1.1.1", "8.8.8.8", "https://1.1.1.1/dns-query"];

  /// Generates a complete, valid Xray JSON configuration Map
  static Map<String, dynamic> generateXrayConfig(
    ProxyNode node, {
    int socksPort = 10808,
    int httpPort = 10809,
    int apiPort = 10085,
    bool enableTun = false,
    bool enableUdp = true,
    bool enableMux = false,
    bool allowInsecure = false,
    bool allowLan = false,
    List<String> dnsServers = defaultDns,
    List<RoutingRule> routingRules = const [],
    AppRoutingMode appRoutingMode = AppRoutingMode.exclusive,
  }) {
    String? nonEmpty(String? s) {
      if (s == null) return null;
      final t = s.trim();
      return t.isNotEmpty ? t : null;
    }

    final effectiveSni = nonEmpty(node.sni) ?? nonEmpty(node.host) ?? node.address;
    final effectiveHost = nonEmpty(node.host) ?? nonEmpty(node.sni) ?? node.address;
    final rawPath = nonEmpty(node.path) ?? "/";
    final safePath = rawPath.startsWith("/") ? rawPath : "/$rawPath";

    final String netName;
    if (node.network == NetworkType.splithttp || node.network == NetworkType.xhttp) {
      netName = "xhttp";
    } else if (node.network == NetworkType.httpUpgrade) {
      netName = "httpupgrade";
    } else {
      netName = node.network.name;
    }

    final streamSettings = <String, dynamic>{
      "network": netName,
      "security": node.security.name,
    };

    if (node.security == SecurityType.tls) {
      final tls = <String, dynamic>{
        "serverName": effectiveSni,
      };
      if (node.fingerprint != null && node.fingerprint!.isNotEmpty) {
        tls["fingerprint"] = node.fingerprint;
      }
      if (node.alpn != null && node.alpn!.isNotEmpty) {
        tls["alpn"] = node.alpn;
      } else if (node.network == NetworkType.ws || node.network == NetworkType.httpUpgrade) {
        tls["alpn"] = ["http/1.1"];
      }
      if (node.echConfigList != null && node.echConfigList!.trim().isNotEmpty) {
        tls["echConfigList"] = node.echConfigList!.trim();
      }
      if (node.verifyPeerCertByName != null && node.verifyPeerCertByName!.trim().isNotEmpty) {
        tls["verifyPeerCertByName"] = node.verifyPeerCertByName!.trim();
      }
      if (node.certificatePinning != null && node.certificatePinning!.trim().isNotEmpty) {
        tls["pinnedPeerCertificatePublicKeySha256"] = node.certificatePinning!.trim();
        tls["pinnedPeerCertSha256"] = node.certificatePinning!.trim();
      }
      streamSettings["tlsSettings"] = tls;
    } else if (node.security == SecurityType.reality) {
      if (node.publicKey != null && node.publicKey!.trim().isNotEmpty) {
        final reality = <String, dynamic>{
          "serverName": effectiveSni,
          "publicKey": node.publicKey!.trim(),
          "shortId": node.shortId ?? "",
          "spiderX": nonEmpty(node.spiderX) ?? "/",
          "fingerprint": (node.fingerprint != null && node.fingerprint!.trim().isNotEmpty)
              ? node.fingerprint!.trim()
              : "chrome",
        };
        streamSettings["realitySettings"] = reality;
      } else {
        streamSettings["security"] = "none";
      }
    }

    if (node.network == NetworkType.xhttp || node.network == NetworkType.splithttp) {
      final xhttpMap = <String, dynamic>{
        "path": safePath,
        "host": effectiveHost,
      };
      if (node.mode != null && node.mode!.isNotEmpty) {
        xhttpMap["mode"] = node.mode;
      }
      if (node.extra != null && node.extra!.isNotEmpty) {
        try {
          xhttpMap["extra"] = jsonDecode(node.extra!);
        } catch (_) {
          xhttpMap["extra"] = node.extra;
        }
      }
      streamSettings["xhttpSettings"] = xhttpMap;
    } else if (node.network == NetworkType.ws) {
      streamSettings["wsSettings"] = {
        "path": safePath,
        "host": effectiveHost,
        "headers": {"Host": effectiveHost},
      };
    } else if (node.network == NetworkType.grpc) {
      streamSettings["grpcSettings"] = {
        "serviceName": node.serviceName ?? "",
        "multiMode": true,
      };
    } else if (node.network == NetworkType.h2) {
      streamSettings["httpSettings"] = {
        "path": safePath,
        "host": [effectiveHost],
      };
    } else if (node.network == NetworkType.httpUpgrade) {
      streamSettings["httpupgradeSettings"] = {
        "path": safePath,
        "host": effectiveHost,
      };
    }

    streamSettings["sockopt"] = {"tcpNoDelay": true};

    Map<String, dynamic> outbound;
    if (node.protocol == ProtocolType.vless) {
      final user = <String, dynamic>{
        "id": node.uuidOrPassword,
        "encryption": "none",
        "level": 0,
        "packetEncoding": "xudp",
      };
      // flow is only valid for tcp transport in VLESS
      if (node.flow != null &&
          node.flow!.trim().isNotEmpty &&
          node.network == NetworkType.tcp) {
        user["flow"] = node.flow!.trim();
      }
      outbound = {
        "tag": "proxy",
        "protocol": "vless",
        "settings": {
          "vnext": [
            {
              "address": node.address,
              "port": node.port,
              "users": [user]
            }
          ]
        },
        "streamSettings": streamSettings,
      };
    } else if (node.protocol == ProtocolType.trojan) {
      outbound = {
        "tag": "proxy",
        "protocol": "trojan",
        "settings": {
          "servers": [
            {
              "address": node.address,
              "port": node.port,
              "password": node.uuidOrPassword,
              "level": 0
            }
          ]
        },
        "streamSettings": streamSettings,
      };
    } else if (node.protocol == ProtocolType.vmess) {
      outbound = {
        "tag": "proxy",
        "protocol": "vmess",
        "settings": {
          "vnext": [
            {
              "address": node.address,
              "port": node.port,
              "users": [
                {
                  "id": node.uuidOrPassword,
                  "alterId": node.alterId,
                  "security": node.cipher ?? "auto",
                  "level": 0
                }
              ]
            }
          ]
        },
        "streamSettings": streamSettings,
      };
    } else {
      outbound = {
        "tag": "proxy",
        "protocol": "shadowsocks",
        "settings": {
          "servers": [
            {
              "address": node.address,
              "port": node.port,
              "method": (node.cipher ?? 'aes-256-gcm').toLowerCase().trim(),
              "password": node.uuidOrPassword,
              "level": 0
            }
          ]
        }
      };
    }

    if (node.enableMux || enableMux) {
      outbound["mux"] = {
        "enabled": true,
        "concurrency": 8,
      };
    }

    final listenAddr = allowLan ? "0.0.0.0" : "127.0.0.1";
    final inbounds = <Map<String, dynamic>>[
      {
        "tag": "socks-in",
        "port": socksPort,
        "listen": listenAddr,
        "protocol": "socks",
        "settings": {"auth": "noauth", "udp": enableUdp},
        "sniffing": {"enabled": true, "destOverride": ["http", "tls"]}
      },
      {
        "tag": "http-in",
        "port": httpPort,
        "listen": listenAddr,
        "protocol": "http",
        "sniffing": {"enabled": true, "destOverride": ["http", "tls"]}
      },
      {
        "tag": "api",
        "port": apiPort,
        "listen": "127.0.0.1",
        "protocol": "dokodemo-door",
        "settings": {"address": "127.0.0.1"}
      }
    ];

    if (enableTun) {
      inbounds.add({
        "tag": "tun-in",
        "protocol": "tun",
        "settings": {
          "name": "v2raypro-tun",
          "mtu": 1500,
          "gateway": ["172.19.0.1/30"],
          "dns": (() {
            final tunIps = dnsServers
                .where((s) => !s.startsWith("https://") && s.toLowerCase() != "localhost" && s.trim().isNotEmpty)
                .toList();
            return tunIps.isNotEmpty ? tunIps : ["1.1.1.1", "8.8.8.8"];
          })(),
          "autoSystemRoutingTable": ["0.0.0.0/0", "0.0.0.0/1", "128.0.0.0/1"],
          "autoOutboundsInterface": "auto"
        },
        "sniffing": {
          "enabled": true,
          "destOverride": ["http", "tls", "quic"],
          "metadataOnly": false
        }
      });
    }

    final effectiveDns = dnsServers.isNotEmpty
        ? [...dnsServers, if (!dnsServers.contains("localhost")) "localhost"]
        : ["8.8.8.8", "1.1.1.1", "https://1.1.1.1/dns-query", "localhost"];

    return {
      "log": {"loglevel": Platform.isAndroid ? "none" : "warning"},
      "api": {"tag": "api", "services": ["StatsService"]},
      "stats": {},
      "policy": {
        "levels": {
          "0": {
            "statsUserUplink": true,
            "statsUserDownlink": true,
            "uplinkOnly": 2,
            "downlinkOnly": 5
          }
        },
        "system": {
          "statsInboundUplink": true,
          "statsInboundDownlink": true,
          "statsOutboundUplink": true,
          "statsOutboundDownlink": true
        }
      },
      "dns": {"servers": effectiveDns},
      "inbounds": inbounds,
      "outbounds": [
        outbound,
        {"tag": "dns-out", "protocol": "dns"},
        {"tag": "direct", "protocol": "freedom"},
        {"tag": "block", "protocol": "blackhole"}
      ],
      "routing": {
        "domainStrategy": "IPIfNonMatch",
        "rules": [
          {"type": "field", "inboundTag": ["api"], "outboundTag": "api"},
          if (enableTun)
            {"type": "field", "inboundTag": ["tun-in"], "port": 53, "outboundTag": "dns-out"},
          {"type": "field", "outboundTag": "direct", "ip": ["geoip:private"]},
          ...(() {
            final custom = <Map<String, dynamic>>[];
            for (final r in routingRules.where((rule) => rule.enabled)) {
              if (r.values.isEmpty) continue;
              if (r.type == RoutingRuleType.address) {
                final expandedDomains = <String>[];
                for (final val in r.values) {
                  final trimmed = val.trim();
                  if (trimmed.toLowerCase() == "geosite:ir") {
                    expandedDomains.add("geosite:category-ir");
                    expandedDomains.add(r"regexp:.*\.ir$");
                  } else {
                    expandedDomains.add(trimmed);
                  }
                }
                custom.add({
                  "type": "field",
                  "outboundTag": r.action.name,
                  "domain": expandedDomains,
                });
              } else if (r.type == RoutingRuleType.ip) {
                custom.add({
                  "type": "field",
                  "outboundTag": r.action.name,
                  "ip": r.values,
                });
              } else if (r.type == RoutingRuleType.app && enableTun) {
                custom.add({
                  "type": "field",
                  "outboundTag": r.action.name,
                  "process": r.values,
                });
              }
            }
            return custom;
          })(),
        ]
      }
    };
  }

  /// Generates a Sing-box JSON configuration Map
  static Map<String, dynamic> generateSingboxConfig(
    ProxyNode node, {
    int socksPort = 10808,
    int httpPort = 10809,
    bool enableTun = false,
  }) {
    String? nonEmpty(String? s) {
      if (s == null) return null;
      final t = s.trim();
      return t.isNotEmpty ? t : null;
    }

    final effectiveSni = nonEmpty(node.sni) ?? nonEmpty(node.host) ?? node.address;
    final effectiveHost = nonEmpty(node.host) ?? nonEmpty(node.sni) ?? node.address;
    final rawPath = nonEmpty(node.path) ?? "/";
    final safePath = rawPath.startsWith("/") ? rawPath : "/$rawPath";

    final outbounds = <Map<String, dynamic>>[
      {
        "type": node.protocol.name,
        "tag": "proxy",
        "server": node.address,
        "server_port": node.port,
        "uuid": node.uuidOrPassword,
        if (node.security == SecurityType.tls)
          "tls": {
            "enabled": true,
            "server_name": effectiveSni,
            if (node.alpn != null && node.alpn!.isNotEmpty) "alpn": node.alpn,
          },
        if (node.network == NetworkType.ws)
          "transport": {
            "type": "ws",
            "path": safePath,
            "headers": {
              "Host": effectiveHost,
            },
          },
      },
      {"type": "direct", "tag": "direct"},
      {"type": "block", "tag": "block"},
      {"type": "dns", "tag": "dns-out"}
    ];

    final inbounds = <Map<String, dynamic>>[
      {
        "type": "mixed",
        "tag": "mixed-in",
        "listen": "127.0.0.1",
        "listen_port": socksPort,
      }
    ];

    if (enableTun) {
      inbounds.add({
        "type": "tun",
        "tag": "tun-in",
        "interface_name": "v2raypro-tun",
        "inet4_address": "172.19.0.1/30",
        "auto_route": true,
        "strict_route": true
      });
    }

    return {
      "log": {"level": "warn"},
      "inbounds": inbounds,
      "outbounds": outbounds,
      "route": {
        "rules": [
          {"protocol": "dns", "outbound": "dns-out"},
          {"geoip": "private", "outbound": "direct"}
        ]
      }
    };
  }
}
