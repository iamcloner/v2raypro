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
  final String? flow;
  final String? headerType;
  final bool enableMux;
  final String? echConfigList;
  final String? verifyPeerCertByName;
  final String? certificatePinning;
  final String? subscriptionId;
  int? latencyMs;
  DateTime? lastTestedAt;
  bool isActive;
  String? originalAddress;
  String? countryCode;
  String? country;

  /// Whether this node has been tested and failed (timed out / no ping response)
  bool get hasTimedOut => lastTestedAt != null && (latencyMs == null || latencyMs! <= 0);

  /// Whether this node has a verified working latency
  bool get hasValidPing => latencyMs != null && latencyMs! > 0;

  /// Whether this node has never been tested
  bool get isUntested => lastTestedAt == null && latencyMs == null;

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
    this.flow,
    this.headerType,
    this.enableMux = false,
    this.echConfigList,
    this.verifyPeerCertByName,
    this.certificatePinning,
    this.subscriptionId,
    this.latencyMs,
    this.lastTestedAt,
    this.isActive = false,
    this.originalAddress,
    this.countryCode,
    this.country,
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
    "flow": flow,
    "header_type": headerType,
    "enable_mux": enableMux,
    "ech_config_list": echConfigList,
    "verify_peer_cert_by_name": verifyPeerCertByName,
    "certificate_pinning": certificatePinning,
    "subscription_id": subscriptionId,
    "latency_ms": latencyMs,
    "last_tested_at": lastTestedAt?.toIso8601String(),
    "is_active": isActive,
    "original_address": originalAddress,
    "country_code": countryCode,
    "country": country,
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
      flow: json["flow"],
      headerType: json["header_type"] ?? json["headerType"],
      enableMux: json["enable_mux"] == true || json["enableMux"] == true,
      echConfigList: json["ech_config_list"] ?? json["echConfigList"],
      verifyPeerCertByName: json["verify_peer_cert_by_name"] ?? json["verifyPeerCertByName"],
      certificatePinning: json["certificate_pinning"] ?? json["certificatePinning"],
      subscriptionId: json["subscription_id"],
      latencyMs: (json["latency_ms"] as num?)?.toInt(),
      lastTestedAt: json["last_tested_at"] != null ? DateTime.tryParse(json["last_tested_at"]) : null,
      isActive: json["is_active"] == true,
      originalAddress: json["original_address"],
      countryCode: json["country_code"],
      country: json["country"],
    );
  }

  static const Object _sentinel = Object();

  ProxyNode copyWith({
    String? id,
    String? name,
    ProtocolType? protocol,
    String? address,
    int? port,
    String? uuidOrPassword,
    int? alterId,
    String? cipher,
    NetworkType? network,
    String? path,
    String? host,
    String? serviceName,
    SecurityType? security,
    String? sni,
    List<String>? alpn,
    bool? allowInsecure,
    String? fingerprint,
    String? publicKey,
    String? shortId,
    String? spiderX,
    String? mode,
    String? extra,
    String? flow,
    String? headerType,
    bool? enableMux,
    String? echConfigList,
    String? verifyPeerCertByName,
    String? certificatePinning,
    String? subscriptionId,
    Object? latencyMs = _sentinel,
    bool clearLatency = false,
    DateTime? lastTestedAt,
    bool? isActive,
    String? originalAddress,
    bool clearOriginalAddress = false,
    bool clearCountry = false,
    String? countryCode,
    String? country,
  }) {
    final int? resolvedLatency = clearLatency
        ? null
        : (identical(latencyMs, _sentinel) ? this.latencyMs : latencyMs as int?);

    return ProxyNode(
      id: id ?? this.id,
      name: name ?? this.name,
      protocol: protocol ?? this.protocol,
      address: address ?? this.address,
      port: port ?? this.port,
      uuidOrPassword: uuidOrPassword ?? this.uuidOrPassword,
      alterId: alterId ?? this.alterId,
      cipher: cipher ?? this.cipher,
      network: network ?? this.network,
      path: path ?? this.path,
      host: host ?? this.host,
      serviceName: serviceName ?? this.serviceName,
      security: security ?? this.security,
      sni: sni ?? this.sni,
      alpn: alpn ?? this.alpn,
      allowInsecure: allowInsecure ?? this.allowInsecure,
      fingerprint: fingerprint ?? this.fingerprint,
      publicKey: publicKey ?? this.publicKey,
      shortId: shortId ?? this.shortId,
      spiderX: spiderX ?? this.spiderX,
      mode: mode ?? this.mode,
      extra: extra ?? this.extra,
      flow: flow ?? this.flow,
      headerType: headerType ?? this.headerType,
      enableMux: enableMux ?? this.enableMux,
      echConfigList: echConfigList ?? this.echConfigList,
      verifyPeerCertByName: verifyPeerCertByName ?? this.verifyPeerCertByName,
      certificatePinning: certificatePinning ?? this.certificatePinning,
      subscriptionId: subscriptionId ?? this.subscriptionId,
      latencyMs: resolvedLatency,
      lastTestedAt: lastTestedAt ?? this.lastTestedAt,
      isActive: isActive ?? this.isActive,
      originalAddress: clearOriginalAddress ? null : (originalAddress ?? this.originalAddress),
      countryCode: clearCountry ? null : (countryCode ?? this.countryCode),
      country: clearCountry ? null : (country ?? this.country),
    );
  }

  String toShareUrl() {
    switch (protocol) {
      case ProtocolType.vless:
        final params = <String, String>{};
        if (security == SecurityType.tls) params['security'] = 'tls';
        if (security == SecurityType.reality) params['security'] = 'reality';
        if (sni != null && sni!.isNotEmpty) params['sni'] = sni!;
        if (fingerprint != null && fingerprint!.isNotEmpty) params['fp'] = fingerprint!;
        if (publicKey != null && publicKey!.isNotEmpty) params['pbk'] = publicKey!;
        if (shortId != null && shortId!.isNotEmpty) params['sid'] = shortId!;
        if (spiderX != null && spiderX!.isNotEmpty) params['spx'] = spiderX!;
        if (flow != null && flow!.isNotEmpty) params['flow'] = flow!;
        if (headerType != null && headerType!.isNotEmpty) params['headerType'] = headerType!;
        params['type'] = network.name;
        if (host != null && host!.isNotEmpty) params['host'] = host!;
        if (path != null && path!.isNotEmpty) params['path'] = path!;
        if (mode != null && mode!.isNotEmpty) params['mode'] = mode!;
        if (extra != null && extra!.isNotEmpty) params['extra'] = extra!;

        final query = params.entries
            .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
            .join('&');
        final frag = Uri.encodeComponent(name);
        return 'vless://$uuidOrPassword@$address:$port${query.isNotEmpty ? "?$query" : ""}${frag.isNotEmpty ? "#$frag" : ""}';

      case ProtocolType.trojan:
        final params = <String, String>{};
        if (security == SecurityType.tls) params['security'] = 'tls';
        if (sni != null && sni!.isNotEmpty) params['sni'] = sni!;
        if (flow != null && flow!.isNotEmpty) params['flow'] = flow!;
        if (headerType != null && headerType!.isNotEmpty) params['headerType'] = headerType!;
        params['type'] = network.name;
        if (host != null && host!.isNotEmpty) params['host'] = host!;
        if (path != null && path!.isNotEmpty) params['path'] = path!;
        final query = params.entries
            .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
            .join('&');
        final frag = Uri.encodeComponent(name);
        return 'trojan://$uuidOrPassword@$address:$port${query.isNotEmpty ? "?$query" : ""}${frag.isNotEmpty ? "#$frag" : ""}';

      default:
        return 'vless://$uuidOrPassword@$address:$port#${Uri.encodeComponent(name)}';
    }
  }
}
