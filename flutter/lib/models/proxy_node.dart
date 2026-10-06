enum ProtocolType { vless, vmess, trojan, shadowsocks, customJson }
enum NetworkType { tcp, ws, grpc, h2, httpUpgrade, xhttp, splithttp }
enum SecurityType { none, tls, reality }

class ProxyNode {
  final String id;
  String name;
  final ProtocolType protocol;
  String address;
  int port;
  final String uuidOrPassword;
  final int alterId;
  final String? cipher;
  final NetworkType network;
  final String? path;
  final String? host;
  final String? serviceName;
  final SecurityType security;
  final String? sni;
  final List<String>? alpn;
  final bool allowInsecure;
  final String? fingerprint;
  final String? publicKey;
  final String? shortId;
  final String? spiderX;
  final String? mode;
  final String? extra;
  final String? subscriptionId;
  int? latencyMs;
  DateTime? lastTestedAt;
  bool isActive;
  String? originalAddress;

  ProxyNode({
    required this.id,
    required this.name,
    required this.protocol,
    required this.address,
    required this.port,
    required this.uuidOrPassword,
    this.alterId = 0,
    this.cipher,
    this.network = NetworkType.tcp,
    this.path,
    this.host,
    this.serviceName,
    this.security = SecurityType.none,
    this.sni,
    this.alpn,
    this.allowInsecure = false,
    this.fingerprint,
    this.publicKey,
    this.shortId,
    this.spiderX,
    this.mode,
    this.extra,
    this.subscriptionId,
    this.latencyMs,
    this.lastTestedAt,
    this.isActive = false,
    this.originalAddress,
  });

  Map<String, dynamic> toJson() => {
    "id": id,
    "name": name,
    "protocol": protocol.name,
    "address": address,
    "port": port,
    "uuid_or_password": uuidOrPassword,
    "alter_id": alterId,
    "cipher": cipher,
    "network": network.name,
    "path": path,
    "host": host,
    "service_name": serviceName,
    "security": security.name,
    "sni": sni,
    "alpn": alpn,
    "allow_insecure": allowInsecure,
    "fingerprint": fingerprint,
    "public_key": publicKey,
    "short_id": shortId,
    "spider_x": spiderX,
    "mode": mode,
    "extra": extra,
    "subscription_id": subscriptionId,
    "latency_ms": latencyMs,
    "last_tested_at": lastTestedAt?.toIso8601String(),
    "is_active": isActive,
    "original_address": originalAddress,
  };

  factory ProxyNode.fromJson(Map<String, dynamic> json) {
    return ProxyNode(
      id: json["id"] ?? "",
      name: json["name"] ?? "Node",
      protocol: ProtocolType.values.firstWhere(
        (e) => e.name.toLowerCase() == (json["protocol"] ?? "vless").toString().toLowerCase(),
        orElse: () => ProtocolType.vless,
      ),
      address: json["address"] ?? "",
      port: (json["port"] as num?)?.toInt() ?? 443,
      uuidOrPassword: json["uuid_or_password"] ?? "",
      alterId: (json["alter_id"] as num?)?.toInt() ?? 0,
      cipher: json["cipher"],
      network: NetworkType.values.firstWhere(
        (e) => e.name.toLowerCase() == (json["network"] ?? "tcp").toString().toLowerCase(),
        orElse: () => NetworkType.tcp,
      ),
      path: json["path"],
      host: json["host"],
      serviceName: json["service_name"],
      security: SecurityType.values.firstWhere(
        (e) => e.name.toLowerCase() == (json["security"] ?? "none").toString().toLowerCase(),
        orElse: () => SecurityType.none,
      ),
      sni: json["sni"],
      alpn: (json["alpn"] as List<dynamic>?)?.map((e) => e.toString()).toList(),
      allowInsecure: json["allow_insecure"] == true,
      fingerprint: json["fingerprint"],
      publicKey: json["public_key"],
      shortId: json["short_id"],
      spiderX: json["spider_x"],
      mode: json["mode"],
      extra: json["extra"],
      subscriptionId: json["subscription_id"],
      latencyMs: (json["latency_ms"] as num?)?.toInt(),
      lastTestedAt: json["last_tested_at"] != null ? DateTime.tryParse(json["last_tested_at"]) : null,
      isActive: json["is_active"] == true,
      originalAddress: json["original_address"],
    );
  }

  ProxyNode copyWith({
    String? name,
    String? address,
    int? port,
    int? latencyMs,
    bool? isActive,
    String? originalAddress,
    String? subscriptionId,
  }) {
    return ProxyNode(
      id: id,
      name: name ?? this.name,
      protocol: protocol,
      address: address ?? this.address,
      port: port ?? this.port,
      uuidOrPassword: uuidOrPassword,
      alterId: alterId,
      cipher: cipher,
      network: network,
      path: path,
      host: host,
      serviceName: serviceName,
      security: security,
      sni: sni,
      alpn: alpn,
      allowInsecure: allowInsecure,
      fingerprint: fingerprint,
      publicKey: publicKey,
      shortId: shortId,
      spiderX: spiderX,
      mode: mode,
      extra: extra,
      subscriptionId: subscriptionId ?? this.subscriptionId,
      latencyMs: latencyMs ?? this.latencyMs,
      lastTestedAt: lastTestedAt,
      isActive: isActive ?? this.isActive,
      originalAddress: originalAddress ?? this.originalAddress,
    );
  }
}
