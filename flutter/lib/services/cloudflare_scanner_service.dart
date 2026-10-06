import "dart:async";
import "dart:io";
import "dart:math";
import "../models/scan_result.dart";

class CloudflareScannerService {
  static final CloudflareScannerService instance = CloudflareScannerService._internal();
  CloudflareScannerService._internal();

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
  }) async* {
    _isCancelled = false;
    final rng = Random();

    // 1. Generate real IP candidates across Cloudflare subnets
    final candidates = <String>[];
    for (int i = 0; i < candidateCount; i++) {
      final prefix = cfSubnets[rng.nextInt(cfSubnets.length)];
      final ip = "$prefix${rng.nextInt(250) + 1}.${rng.nextInt(254) + 1}";
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
