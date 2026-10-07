import "dart:async";
import "dart:convert";
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
    "162.159.0.0/16",
    "1.0.0.0/24",
    "1.1.1.0/24",
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

  /// Check if a given IPv4 address belongs to any Cloudflare CIDR (default or custom)
  static bool isCloudflareIp(String ip, [List<String>? cidrs]) {
    final targetIp = ip.trim();
    final parts = targetIp.split('.').map(int.tryParse).toList();
    if (parts.length != 4 || parts.any((p) => p == null || p < 0 || p > 255)) {
      return false;
    }
    final int ipInt = (parts[0]! << 24) | (parts[1]! << 16) | (parts[2]! << 8) | parts[3]!;
    final ranges = (cidrs != null && cidrs.isNotEmpty) ? cidrs : defaultCidrs;

    for (final cidr in ranges) {
      try {
        final cidrParts = cidr.trim().split('/');
        final baseParts = cidrParts[0].split('.').map(int.tryParse).toList();
        if (baseParts.length != 4 || baseParts.any((p) => p == null)) continue;

        final prefixLen = cidrParts.length > 1 ? int.parse(cidrParts[1]) : 32;
        if (prefixLen < 0 || prefixLen > 32) continue;

        final int baseInt = (baseParts[0]! << 24) | (baseParts[1]! << 16) | (baseParts[2]! << 8) | baseParts[3]!;
        final int mask = prefixLen == 0 ? 0 : (~0 << (32 - prefixLen));

        if ((ipInt & mask) == (baseInt & mask)) {
          return true;
        }
      } catch (_) {}
    }
    return false;
  }

  static final Map<String, bool> _domainCfCache = {};

  /// Check if a host (IP or domain name) is Cloudflare synchronously using cache or known rules
  static bool isCloudflareHostSync(String host, [List<String>? cidrs]) {
    final clean = host.trim().toLowerCase();
    if (_domainCfCache.containsKey(clean)) {
      return _domainCfCache[clean]!;
    }
    // Direct IP check
    if (isCloudflareIp(clean, cidrs)) {
      _domainCfCache[clean] = true;
      return true;
    }
    // Well-known Cloudflare domain suffix check
    if (clean == 'cloudflare.com' ||
        clean.endsWith('.cloudflare.com') ||
        clean == 'workers.dev' ||
        clean.endsWith('.workers.dev') ||
        clean == 'pages.dev' ||
        clean.endsWith('.pages.dev') ||
        clean.endsWith('.cfargotunnel.com')) {
      _domainCfCache[clean] = true;
      return true;
    }
    return false;
  }

  /// Asynchronously resolve domain and determine if it points to Cloudflare
  static Future<bool> resolveAndCheckCloudflare(String host, [List<String>? cidrs]) async {
    final clean = host.trim().toLowerCase();
    if (_domainCfCache.containsKey(clean)) {
      return _domainCfCache[clean]!;
    }
    if (isCloudflareHostSync(clean, cidrs)) {
      _domainCfCache[clean] = true;
      return true;
    }

    try {
      final addresses = await InternetAddress.lookup(clean).timeout(const Duration(seconds: 3));
      for (final addr in addresses) {
        if (isCloudflareIp(addr.address, cidrs)) {
          _domainCfCache[clean] = true;
          return true;
        }
      }
    } catch (_) {}

    _domainCfCache[clean] = false;
    return false;
  }

  /// Generate a unique, shuffled list of candidate IPs sampled from given or default CIDRs.
  static List<String> generateCandidateIps({
    required int count,
    List<String>? cidrs,
    Random? rng,
  }) {
    final rand = rng ?? Random();
    final ranges = (cidrs != null && cidrs.isNotEmpty) ? cidrs : defaultCidrs;
    final Set<String> candidates = {};

    int attempts = 0;
    while (candidates.length < count && attempts < count * 80) {
      attempts++;
      final cidr = ranges[rand.nextInt(ranges.length)];
      final ip = sampleIpFromCidr(cidr, rand);
      candidates.add(ip);
    }

    final list = candidates.toList();
    list.shuffle(rand);
    return list;
  }

  bool _isCancelled = false;

  void cancel() {
    _isCancelled = true;
  }

  /// Perform a real network probe (TCP Socket connect + TLS handshake + live origin response)
  Future<ScanResult> testRealIp({
    required String ip,
    required int port,
    String? sni,
    String? host,
    Duration timeout = const Duration(milliseconds: 2500),
  }) async {
    final sw = Stopwatch()..start();
    Socket? socket;
    try {
      socket = await Socket.connect(ip, port, timeout: timeout);
      final tcpMs = sw.elapsedMilliseconds;

      int? tlsMs;
      bool tlsSuccess = false;
      Socket activeSocket = socket;

      if (port == 443 || sni != null) {
        final tlsSw = Stopwatch()..start();
        final secureSocket = await SecureSocket.secure(
          socket,
          host: sni ?? "cloudflare.com",
          onBadCertificate: (cert) => true,
        ).timeout(timeout);
        tlsMs = tlsSw.elapsedMilliseconds;
        tlsSuccess = true;
        activeSocket = secureSocket;
      }

      // Perform real HTTP / WebSocket upgrade probe to verify live origin reachability
      final targetHost = host ?? sni ?? "cloudflare.com";
      final httpRequest =
          'GET / HTTP/1.1\r\n'
          'Host: $targetHost\r\n'
          'User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64)\r\n'
          'Upgrade: websocket\r\n'
          'Connection: Upgrade\r\n'
          'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n'
          'Sec-WebSocket-Version: 13\r\n'
          '\r\n';

      activeSocket.add(utf8.encode(httpRequest));
      await activeSocket.flush();

      final completer = Completer<bool>();
      final sub = activeSocket.listen(
        (data) {
          if (!completer.isCompleted) {
            final res = utf8.decode(data, allowMalformed: true);
            final firstLine = res.split('\r\n').first;
            final isGood = firstLine.contains('101') ||
                firstLine.contains('400') ||
                firstLine.contains('200') ||
                firstLine.contains('204');
            final isBad = res.contains('502') ||
                res.contains('503') ||
                res.contains('504') ||
                res.contains('520') ||
                res.contains('521') ||
                res.contains('522') ||
                res.contains('523') ||
                res.contains('524') ||
                res.contains('525') ||
                res.contains('526') ||
                res.contains('530') ||
                res.contains('403') ||
                res.contains('Error 1000') ||
                res.contains('Error 1005');

            completer.complete(isGood && !isBad);
          }
        },
        onError: (_) {
          if (!completer.isCompleted) completer.complete(false);
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete(false);
        },
      );

      final protocolOk = await completer.future.timeout(timeout, onTimeout: () => false);
      await sub.cancel();
      sw.stop();
      activeSocket.destroy();

      if (!protocolOk) {
        return ScanResult(
          ip: ip,
          port: port,
          tcpSuccess: true,
          tcpLatencyMs: tcpMs,
          tlsSuccess: tlsSuccess,
          tlsLatencyMs: tlsMs,
          protocolSuccess: false,
          error: "Origin unreachable (CDN 5xx / 403)",
          rankScore: 99999.0,
        );
      }

      final totalMs = sw.elapsedMilliseconds;
      return ScanResult(
        ip: ip,
        port: port,
        tcpSuccess: true,
        tcpLatencyMs: tcpMs,
        tlsSuccess: tlsSuccess,
        tlsLatencyMs: tlsMs,
        protocolSuccess: true,
        totalLatencyMs: totalMs,
        rankScore: totalMs.toDouble(),
      );
    } catch (e) {
      sw.stop();
      try {
        socket?.destroy();
      } catch (_) {}
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
