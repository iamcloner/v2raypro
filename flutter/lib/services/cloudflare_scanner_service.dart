import "dart:async";
import "dart:io";
import "dart:math";
import "../models/scan_result.dart";

class CloudflareScannerService {
  static final CloudflareScannerService instance = CloudflareScannerService._internal();
  CloudflareScannerService._internal();

  static const List<String> defaultCidrs = [
    "104.16.0.0/13",
    "104.24.0.0/14",
    "172.64.0.0/13",
    "162.158.0.0/15",
    "198.41.128.0/17",
    "173.245.48.0/20",
    "108.162.192.0/18",
    "190.93.240.0/20",
    "188.114.96.0/20",
    "197.234.240.0/22",
    "141.101.64.0/18",
    "103.21.244.0/22",
    "103.22.200.0/22",
    "103.31.4.0/22",
    "131.0.72.0/22",
  ];

  static const List<String> cfSubnets = [
    "104.16.",
    "104.17.",
    "104.18.",
    "104.19.",
    "104.20.",
    "104.21.",
    "172.64.",
    "172.65.",
    "172.66.",
    "172.67.",
    "162.158.",
    "162.159.",
    "108.162.",
    "198.41.",
    "173.245.",
  ];

  /// Mathematically sample a random usable IPv4 from a CIDR (e.g. 104.18.0.0/16 or 104.16.0.0/13)
  static String sampleIpFromCidr(String cidr, Random rng) {
    try {
      final parts = cidr.trim().split('/');
      final ipParts = parts[0].split('.').map(int.parse).toList();
      if (ipParts.length != 4) throw FormatException();

      final prefixLength = parts.length > 1 ? int.parse(parts[1]) : 32;
      if (prefixLength < 0 || prefixLength > 32) throw FormatException();

      int baseIp = (ipParts[0] << 24) | (ipParts[1] << 16) | (ipParts[2] << 8) | ipParts[3];
      final hostBits = 32 - prefixLength;

      if (hostBits <= 1) {
        return parts[0];
      }

      final hostCount = 1 << hostBits;
      // Reserve network and broadcast address for standard subnets
      final offset = (hostBits > 2) ? (rng.nextInt(hostCount - 2) + 1) : rng.nextInt(hostCount);
      final sampledIp = (baseIp & (~((1 << hostBits) - 1))) | offset;

      final o1 = (sampledIp >> 24) & 0xFF;
      final o2 = (sampledIp >> 16) & 0xFF;
      final o3 = (sampledIp >> 8) & 0xFF;
      final o4 = sampledIp & 0xFF;

      return "$o1.$o2.$o3.$o4";
    } catch (_) {
      // Fallback if parsing fails
      if (cidr.contains('.')) {
        final raw = cidr.split('/')[0].trim();
        final segs = raw.split('.');
        if (segs.length >= 2) {
          return "${segs[0]}.${segs[1]}.${rng.nextInt(250) + 1}.${rng.nextInt(254) + 1}";
        }
      }
      return "104.18.${rng.nextInt(250) + 1}.${rng.nextInt(254) + 1}";
    }
  }

  bool _isCancelled = false;

  void cancel() {
    _isCancelled = true;
  }

  /// Perform a real network probe (TCP Socket connect + TLS handshake + Latency probe)
  Future<ScanResult> testRealIp({
    required String ip,
    required int port,
    String? sni,
    Duration timeout = const Duration(milliseconds: 2500),
  }) async {
    final sw = Stopwatch()..start();
    Socket? socket;
    try {
      // 1. Real TCP Connect stage
      socket = await Socket.connect(ip, port, timeout: timeout);
      final tcpMs = sw.elapsedMilliseconds;

      // 2. Real Secure TLS Handshake stage
      SecureSocket? secureSocket;
      int? tlsMs;
      bool tlsSuccess = false;

      if (port == 443 || sni != null) {
        final tlsSw = Stopwatch()..start();
        try {
          secureSocket = await SecureSocket.secure(
            socket,
            host: sni ?? "cloudflare.com",
            onBadCertificate: (cert) => true, // Accept server certificates
          ).timeout(timeout);
          tlsMs = tlsSw.elapsedMilliseconds;
          tlsSuccess = true;
        } catch (_) {
          tlsSuccess = false;
        }
      }

      final totalMs = sw.elapsedMilliseconds;
      await secureSocket?.close();
      await socket.close();

      return ScanResult(
        ip: ip,
        port: port,
        tcpSuccess: true,
        tcpLatencyMs: tcpMs,
        tlsSuccess: tlsSuccess,
        tlsLatencyMs: tlsMs,
        protocolSuccess: tlsSuccess,
        totalLatencyMs: totalMs,
        rankScore: (tlsSuccess ? totalMs : (tcpMs + 500)).toDouble(),
      );
    } catch (e) {
      sw.stop();
      return ScanResult(
        ip: ip,
        port: port,
        tcpSuccess: false,
        tlsSuccess: false,
        protocolSuccess: false,
        error: e.toString().contains("timed out") ? "Timeout" : "Connection failed",
        rankScore: 99999.0,
      );
    }
  }

  Stream<Map<String, dynamic>> scanCandidates({
    required int candidateCount,
    required int workers,
    required int targetPort,
    String? targetSni,
    List<String>? customCidrs,
  }) async* {
    _isCancelled = false;
    final rng = Random();

    // 1. Generate real IP candidates across Cloudflare subnets or custom CIDRs
    final ranges = (customCidrs != null && customCidrs.isNotEmpty) ? customCidrs : defaultCidrs;
    final candidates = <String>[];
    for (int i = 0; i < candidateCount; i++) {
      final cidr = ranges[rng.nextInt(ranges.length)];
      final ip = sampleIpFromCidr(cidr, rng);
      candidates.add(ip);
    }

    yield {"type": "ScanStarted", "data": {"total": candidates.length}};

    int scanned = 0;
    int successCount = 0;
    ScanResult? best;

    // Process concurrently in chunks matching worker count
    for (int i = 0; i < candidates.length; i += workers) {
      if (_isCancelled) {
        yield {"type": "ScanCancelled", "data": {}};
        return;
      }

      final chunk = candidates.sublist(i, min(i + workers, candidates.length));
      final futures = chunk.map((ip) => testRealIp(
        ip: ip,
        port: targetPort,
        sni: targetSni,
      ));

      final results = await Future.wait(futures);

      for (final res in results) {
        scanned++;
        if (res.tcpSuccess && res.tlsSuccess) {
          successCount++;
          if (best == null || res.rankScore < best.rankScore) {
            best = res;
          }
        }

        yield {
          "type": "ScanProgress",
          "data": {"scanned": scanned, "total": candidates.length, "current_ip": res.ip}
        };

        yield {
          "type": "ScanResult",
          "data": {
            "ip": res.ip,
            "port": res.port,
            "tcp_success": res.tcpSuccess,
            "tcp_latency_ms": res.tcpLatencyMs,
            "tls_success": res.tlsSuccess,
            "tls_latency_ms": res.tlsLatencyMs,
            "protocol_success": res.protocolSuccess,
            "total_latency_ms": res.totalLatencyMs,
            "error": res.error,
            "rank_score": res.rankScore,
          }
        };
      }
    }

    yield {
      "type": "ScanFinished",
      "data": {
        "total_tested": scanned,
        "successful_count": successCount,
        "best_ip": best != null ? {
          "ip": best.ip,
          "port": best.port,
          "tcp_success": best.tcpSuccess,
          "tcp_latency_ms": best.tcpLatencyMs,
          "tls_success": best.tlsSuccess,
          "tls_latency_ms": best.tlsLatencyMs,
          "protocol_success": best.protocolSuccess,
          "total_latency_ms": best.totalLatencyMs,
          "error": best.error,
          "rank_score": best.rankScore,
        } : null,
      }
    };
  }
}
