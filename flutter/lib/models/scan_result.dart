class ScanResult {
  final String ip;
  final int port;
  final bool tcpSuccess;
  final int? tcpLatencyMs;
  final bool tlsSuccess;
  final int? tlsLatencyMs;
  final bool protocolSuccess;
  final int? totalLatencyMs;
  final String? error;
  final double rankScore;

  ScanResult({
    required this.ip,
    required this.port,
    required this.tcpSuccess,
    this.tcpLatencyMs,
    required this.tlsSuccess,
    this.tlsLatencyMs,
    required this.protocolSuccess,
    this.totalLatencyMs,
    this.error,
    required this.rankScore,
  });

  factory ScanResult.fromJson(Map<String, dynamic> json) {
    return ScanResult(
      ip: json["ip"] ?? "",
      port: (json["port"] as num?)?.toInt() ?? 443,
      tcpSuccess: json["tcp_success"] == true,
      tcpLatencyMs: (json["tcp_latency_ms"] as num?)?.toInt(),
      tlsSuccess: json["tls_success"] == true,
      tlsLatencyMs: (json["tls_latency_ms"] as num?)?.toInt(),
      protocolSuccess: json["protocol_success"] == true,
      totalLatencyMs: (json["total_latency_ms"] as num?)?.toInt(),
      error: json["error"],
      rankScore: (json["rank_score"] as num?)?.toDouble() ?? 99999.0,
    );
  }

  int? get latencyMs => totalLatencyMs ?? tcpLatencyMs;

  String get latencyTier {
    final lat = totalLatencyMs ?? tcpLatencyMs;
    if (lat == null) return "Timeout";
    if (lat < 60) return "Excellent";
    if (lat < 120) return "Good";
    if (lat < 220) return "Average";
    return "Poor";
  }
}
