import "dart:async";
import "dart:convert";
import "dart:io";
import "dart:math";
import "../models/scan_result.dart";

enum CdnProvider {
  cloudflare,
  fastly,
  awsCloudFront,
  gcore,
  arvancloud;

  String get id {
    switch (this) {
      case CdnProvider.cloudflare:
        return "cloudflare";
      case CdnProvider.fastly:
        return "fastly";
      case CdnProvider.awsCloudFront:
        return "cloudfront";
      case CdnProvider.gcore:
        return "gcore";
      case CdnProvider.arvancloud:
        return "arvancloud";
    }
  }

  String get displayName {
    switch (this) {
      case CdnProvider.cloudflare:
        return "Cloudflare";
      case CdnProvider.fastly:
        return "Fastly";
      case CdnProvider.awsCloudFront:
        return "AWS CloudFront";
      case CdnProvider.gcore:
        return "G-Core";
      case CdnProvider.arvancloud:
        return "ArvanCloud";
    }
  }

  String get displayNameFa {
    switch (this) {
      case CdnProvider.cloudflare:
        return "کلودفلر";
      case CdnProvider.fastly:
        return "فستلی";
      case CdnProvider.awsCloudFront:
        return "کلودفرانت (AWS)";
      case CdnProvider.gcore:
        return "جی‌کور (G-Core)";
      case CdnProvider.arvancloud:
        return "ابر آروان (ArvanCloud)";
    }
  }

  List<String> get defaultCidrs {
    switch (this) {
      case CdnProvider.cloudflare:
        return const [
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
      case CdnProvider.fastly:
        return const [
          "151.101.0.0/16",
          "199.232.0.0/16",
          "157.52.64.0/18",
          "167.82.0.0/17",
          "146.75.0.0/16",
          "151.106.0.0/16",
          "199.27.72.0/21",
        ];
      case CdnProvider.awsCloudFront:
        return const [
          "13.32.0.0/15",
          "13.35.0.0/16",
          "18.64.0.0/14",
          "18.160.0.0/15",
          "52.84.0.0/15",
          "54.192.0.0/16",
          "54.230.0.0/16",
          "54.239.128.0/18",
          "54.239.192.0/19",
          "54.240.128.0/18",
          "64.252.64.0/18",
          "65.8.0.0/16",
          "65.9.0.0/17",
          "99.84.0.0/16",
          "99.86.0.0/16",
          "143.204.0.0/16",
          "204.246.164.0/22",
          "205.251.192.0/19",
        ];
      case CdnProvider.gcore:
        return const [
          "92.223.64.0/18",
          "92.38.128.0/17",
          "92.223.0.0/18",
          "146.185.128.0/19",
          "188.114.128.0/19",
          "194.26.28.0/22",
          "195.123.208.0/20",
          "5.188.120.0/21",
        ];
      case CdnProvider.arvancloud:
        return const [
          "185.143.232.0/22",
          "94.182.152.0/21",
          "188.114.86.0/24",
          "185.228.238.0/23",
          "185.231.112.0/22",
          "188.121.96.0/22",
          "89.39.208.0/21",
          "185.211.56.0/22",
          "185.215.232.0/22",
        ];
    }
  }

  List<String> get wellKnownDomains {
    switch (this) {
      case CdnProvider.cloudflare:
        return const [
          "cloudflare.com",
          ".cloudflare.com",
          "workers.dev",
          ".workers.dev",
          "pages.dev",
          ".pages.dev",
          ".cfargotunnel.com",
        ];
      case CdnProvider.fastly:
        return const [
          "fastly.net",
          ".fastly.net",
          "fastlylb.net",
          ".fastlylb.net",
        ];
      case CdnProvider.awsCloudFront:
        return const [
          "cloudfront.net",
          ".cloudfront.net",
          "amazonaws.com",
          ".amazonaws.com",
        ];
      case CdnProvider.gcore:
        return const [
          "gcore.com",
          ".gcore.com",
          "gcore.lu",
          ".gcore.lu",
          "gcdn.co",
          ".gcdn.co",
        ];
      case CdnProvider.arvancloud:
        return const [
          "arvancloud.ir",
          ".arvancloud.ir",
          "arvancloud.com",
          ".arvancloud.com",
          "arvancdn.ir",
          ".arvancdn.ir",
        ];
    }
  }
}

class CdnScannerService {
  static final CdnScannerService instance = CdnScannerService._internal();
  CdnScannerService._internal();

  static final Map<String, CdnProvider?> _hostCdnCache = {};

  /// Fast bitwise check whether an IPv4 address belongs to a single CIDR
  static bool isIpInCidr(String ip, String cidr) {
    try {
      final parts = ip.trim().split('.').map(int.tryParse).toList();
      if (parts.length != 4 || parts.any((p) => p == null || p < 0 || p > 255)) {
        return false;
      }
      final int ipInt = (parts[0]! << 24) | (parts[1]! << 16) | (parts[2]! << 8) | parts[3]!;

      final cidrParts = cidr.trim().split('/');
      final baseParts = cidrParts[0].split('.').map(int.tryParse).toList();
      if (baseParts.length != 4 || baseParts.any((p) => p == null)) return false;

      final prefixLen = cidrParts.length > 1 ? int.parse(cidrParts[1]) : 32;
      if (prefixLen < 0 || prefixLen > 32) return false;

      final int baseInt = (baseParts[0]! << 24) | (baseParts[1]! << 16) | (baseParts[2]! << 8) | baseParts[3]!;
      final int mask = prefixLen == 0 ? 0 : (~0 << (32 - prefixLen));

      return (ipInt & mask) == (baseInt & mask);
    } catch (_) {
      return false;
    }
  }

  /// Check whether an IPv4 address is in a list of CIDRs
  static bool isIpInCidrs(String ip, List<String> cidrs) {
    for (final cidr in cidrs) {
      if (isIpInCidr(ip, cidr)) return true;
    }
    return false;
  }

  /// Mathematically sample a random usable IPv4 from a CIDR
  static String sampleIpFromCidr(String cidr, Random rng) {
    try {
      final parts = cidr.trim().split('/');
      final ipParts = parts[0].split('.').map(int.parse).toList();
      if (ipParts.length != 4) throw const FormatException();

      final prefixLength = parts.length > 1 ? int.parse(parts[1]) : 32;
      if (prefixLength < 0 || prefixLength > 32) throw const FormatException();

      int baseIp = (ipParts[0] << 24) | (ipParts[1] << 16) | (ipParts[2] << 8) | ipParts[3];
      final hostBits = 32 - prefixLength;

      if (hostBits <= 1) {
        return parts[0];
      }

      final hostCount = 1 << hostBits;
      final offset = (hostBits > 2) ? (rng.nextInt(hostCount - 2) + 1) : rng.nextInt(hostCount);
      final sampledIp = (baseIp & (~((1 << hostBits) - 1))) | offset;

      final o1 = (sampledIp >> 24) & 0xFF;
      final o2 = (sampledIp >> 16) & 0xFF;
      final o3 = (sampledIp >> 8) & 0xFF;
      final o4 = sampledIp & 0xFF;

      return "$o1.$o2.$o3.$o4";
    } catch (_) {
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

  /// Detect which CDN an IP belongs to, using custom ranges if supplied or default ranges
  static CdnProvider? detectCdnFromIp(String ip, [Map<CdnProvider, List<String>>? allCdnRanges]) {
    final cleanIp = ip.trim();
    if (!cleanIp.contains(RegExp(r'^\d+\.\d+\.\d+\.\d+$'))) {
      return null;
    }

    for (final provider in CdnProvider.values) {
      final ranges = allCdnRanges?[provider] ?? provider.defaultCidrs;
      if (isIpInCidrs(cleanIp, ranges)) {
        return provider;
      }
    }
    return null;
  }

  /// Synchronously test host against known well-known domain suffixes or direct IP
  static CdnProvider? detectCdnHostSync(String host, [Map<CdnProvider, List<String>>? allCdnRanges]) {
    final clean = host.trim().toLowerCase();
    if (_hostCdnCache.containsKey(clean)) {
      return _hostCdnCache[clean];
    }

    // 1. Direct IP check
    final ipMatch = detectCdnFromIp(clean, allCdnRanges);
    if (ipMatch != null) {
      _hostCdnCache[clean] = ipMatch;
      return ipMatch;
    }

    // 2. Well-known domain suffixes
    for (final provider in CdnProvider.values) {
      for (final domainPattern in provider.wellKnownDomains) {
        if (clean == domainPattern || clean.endsWith(domainPattern)) {
          _hostCdnCache[clean] = provider;
          return provider;
        }
      }
    }

    return null;
  }

  /// Asynchronously resolve domain to IP and detect which CDN it points to
  static Future<CdnProvider?> detectCdnFromHost(
    String host, [
    Map<CdnProvider, List<String>>? allCdnRanges,
  ]) async {
    final clean = host.trim().toLowerCase();
    if (_hostCdnCache.containsKey(clean)) {
      return _hostCdnCache[clean];
    }

    final syncResult = detectCdnHostSync(clean, allCdnRanges);
    if (syncResult != null) {
      _hostCdnCache[clean] = syncResult;
      return syncResult;
    }

    // If it's a domain name, resolve its IP addresses
    if (!clean.contains(RegExp(r'^\d+\.\d+\.\d+\.\d+$'))) {
      try {
        final addresses = await InternetAddress.lookup(clean).timeout(const Duration(seconds: 4));
        for (final addr in addresses) {
          final matched = detectCdnFromIp(addr.address, allCdnRanges);
          if (matched != null) {
            _hostCdnCache[clean] = matched;
            return matched;
          }
        }
      } catch (_) {}
    }

    _hostCdnCache[clean] = null;
    return null;
  }

  /// Generate candidate IPs for a specific CDN provider
  static List<String> generateCandidateIps({
    required CdnProvider cdn,
    required int count,
    List<String>? customCidrs,
    Random? rng,
  }) {
    final rand = rng ?? Random();
    final ranges = (customCidrs != null && customCidrs.isNotEmpty)
        ? customCidrs
        : cdn.defaultCidrs;
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

  /// Real network probe for latency, TLS handshake, and origin backend response
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
          host: sni ?? ip,
          onBadCertificate: (_) => true,
        ).timeout(timeout);
        tlsMs = tlsSw.elapsedMilliseconds;
        tlsSuccess = true;
        activeSocket = secureSocket;
      }

      // Perform real HTTP / WebSocket upgrade probe to verify live origin reachability
      final targetHost = host ?? sni ?? ip;
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

      final totalLatency = sw.elapsedMilliseconds;
      return ScanResult(
        ip: ip,
        port: port,
        tcpSuccess: true,
        tcpLatencyMs: tcpMs,
        tlsSuccess: tlsSuccess,
        tlsLatencyMs: tlsMs,
        protocolSuccess: true,
        totalLatencyMs: totalLatency,
        rankScore: totalLatency.toDouble(),
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
}
