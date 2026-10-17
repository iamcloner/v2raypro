import "dart:async";
import "dart:convert";
import "dart:io";
import "../models/service_models.dart";
import "../models/proxy_node.dart";
import "country_service.dart";
import "log_service.dart";

/// Dedicated Ping Service implementing the exact diagram specification:
/// Supports PingMode.ipTest (direct ping to node IP/Port) and
/// PingMode.realDelay (temporary proxy connection with optional exit IP/country discovery).
class PingService {
  static final PingService instance = PingService._internal();
  PingService._internal();

  static int _ephemeralPortCounter = 31000;

  /// Main entrypoint corresponding to diagram:
  /// Destination, Port, Ping_Type, Ping_mode, Show_country, Config [json] (xray or singbox)
  Future<PingResult> ping({
    required CoreConfig config,
    String destination = "cp.cloudflare.com",
    int port = 80,
    PingType pingType = PingType.tcp,
    PingMode pingMode = PingMode.realDelay,
    bool showCountry = false,
    Duration timeout = const Duration(seconds: 4),
    String? xrayBinaryPath,
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    if (pingMode == PingMode.ipTest) {
      return await _executeIpTest(
        config: config,
        pingType: pingType,
        timeout: timeout,
      );
    } else {
      return await _executeRealDelay(
        config: config,
        destination: destination,
        port: port,
        pingType: pingType,
        showCountry: showCountry,
        timeout: timeout,
        xrayBinaryPath: xrayBinaryPath,
        workingDirectory: workingDirectory,
        environment: environment,
      );
    }
  }

  // ========================================================
  // 1. IP Test Mode (Extract IP & Port, Take Ping)
  // ========================================================

  Future<PingResult> _executeIpTest({
    required CoreConfig config,
    required PingType pingType,
    required Duration timeout,
  }) async {
    final serverInfo = config.extractServerAddressAndPort();
    final address = serverInfo.address;
    final port = serverInfo.port;

    if (address.isEmpty || port <= 0) {
      return PingResult.failure("Invalid server address or port in config");
    }

    try {
      int? latency;
      switch (pingType) {
        case PingType.tcp:
          latency = await _tcpPing(address, port, timeout: timeout);
          break;
        case PingType.icmp:
          latency = await _icmpPing(address, timeout: timeout);
          break;
        case PingType.udp:
          latency = await _udpPing(address, port, timeout: timeout);
          break;
      }

      if (latency != null && latency > 0) {
        return PingResult.success(latencyMs: latency);
      } else {
        return PingResult.failure("Target unreachable via ${pingType.name.toUpperCase()}");
      }
    } catch (e) {
      return PingResult.failure(e.toString());
    }
  }

  Future<int?> _tcpPing(String host, int port, {required Duration timeout}) async {
    final sw = Stopwatch()..start();
    try {
      final socket = await Socket.connect(host, port, timeout: timeout);
      sw.stop();
      await socket.close();
      socket.destroy();
      return sw.elapsedMilliseconds;
    } catch (_) {
      return null;
    }
  }

  Future<int?> _icmpPing(String host, {required Duration timeout}) async {
    final sw = Stopwatch()..start();
    try {
      final isWin = Platform.isWindows;
      final cmd = isWin ? "ping" : "ping";
      final args = isWin
          ? ["-n", "1", "-w", timeout.inMilliseconds.toString(), host]
          : ["-c", "1", "-W", timeout.inSeconds.toString(), host];

      final res = await Process.run(cmd, args).timeout(timeout);
      sw.stop();
      if (res.exitCode == 0) {
        final out = res.stdout.toString();
        // Extract time from output
        final match = RegExp(r"(?:time|زمان)[=< ]*(\d+(?:\.\d+)?)ms", caseSensitive: false).firstMatch(out);
        if (match != null) {
          final t = double.tryParse(match.group(1)!);
          if (t != null) return t.round();
        }
        return sw.elapsedMilliseconds;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<int?> _udpPing(String host, int port, {required Duration timeout}) async {
    final sw = Stopwatch()..start();
    RawDatagramSocket? socket;
    try {
      final addresses = await InternetAddress.lookup(host).timeout(timeout);
      if (addresses.isEmpty) return null;

      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      final dummyPacket = [0x00, 0x01, 0x02];
      socket.send(dummyPacket, addresses.first, port);
      sw.stop();
      return sw.elapsedMilliseconds > 0 ? sw.elapsedMilliseconds : 1;
    } catch (_) {
      return null;
    } finally {
      socket?.close();
    }
  }

  // ========================================================
  // 2. Real Delay Mode (Connect Temporary -> Ping -> Show Country? -> Disconnect)
  // ========================================================

  Future<PingResult> _executeRealDelay({
    required CoreConfig config,
    required String destination,
    required int port,
    required PingType pingType,
    required bool showCountry,
    required Duration timeout,
    String? xrayBinaryPath,
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    // 1. Connect temporary to config or direct probe
    int? latency;
    String? countryCode;
    String? countryName;
    String? exitIp;

    if (config.node != null && (xrayBinaryPath == null || !File(xrayBinaryPath).existsSync())) {
      latency = await _probeNodeDirectly(config.node!, timeout);
      if (latency != null && showCountry) {
        final loc = LocalGeoIp.instance.lookup(config.node!.address);
        if (loc != null) {
          countryCode = loc;
          countryName = CountryService.getCountryName(loc);
        }
      }
    } else {
      final tempPort = _getEphemeralPort();
      _TemporaryProxyInstance? tempProxy;

      try {
        tempProxy = await _startTemporaryProxy(
          config: config,
          listenPort: tempPort,
          xrayBinaryPath: xrayBinaryPath,
          workingDirectory: workingDirectory,
          environment: environment,
        );

        final client = HttpClient();
        client.findProxy = (uri) => "PROXY 127.0.0.1:$tempPort";
        client.connectionTimeout = timeout;

        // 2. Take a ping (ping type) through the temporary connection
        latency = await _measureRealDelayThroughProxy(
          client: client,
          destination: destination,
          port: port,
          pingType: pingType,
          timeout: timeout,
        );

        // Fallback: If proxy measurement timed out, try strict protocol probe
        if (latency == null && config.node != null) {
          latency = await _probeNodeDirectly(config.node!, timeout);
        }

        // 3. If Show_country == true -> Send HTTP request and get IP info
        if (showCountry) {
          if (latency != null) {
            final ipInfo = await _fetchExitIpInfo(client, timeout: timeout);
            countryCode = ipInfo.countryCode;
            countryName = ipInfo.countryName;
            exitIp = ipInfo.exitIp;
          }
          if (countryCode == null && config.node != null) {
            final loc = LocalGeoIp.instance.lookup(config.node!.address);
            if (loc != null) {
              countryCode = loc;
              countryName = CountryService.getCountryName(loc);
            }
          }
        }
      } catch (e) {
        if (config.node != null) {
          latency = await _probeNodeDirectly(config.node!, timeout);
          if (showCountry && latency != null) {
            final loc = LocalGeoIp.instance.lookup(config.node!.address);
            if (loc != null) {
              countryCode = loc;
              countryName = CountryService.getCountryName(loc);
            }
          }
        } else {
          return PingResult.failure(e.toString());
        }
      } finally {
        // 4. Disconnect temporary connection
        await tempProxy?.dispose();
      }
    }

    if (latency != null && latency > 0) {
      return PingResult.success(
        latencyMs: latency,
        countryCode: countryCode,
        countryName: countryName,
        exitIp: exitIp,
      );
    } else {
      return PingResult.failure("Real delay probe timed out or destination unreachable");
    }
  }

  Future<int?> pingProtocolDelay(
    ProxyNode node, {
    Duration timeout = const Duration(seconds: 3),
    int count = 1,
  }) async {
    int? lowest;
    for (int i = 0; i < count; i++) {
      final res = await _probeNodeStrictProtocol(node, timeout);
      if (res != null && res > 0) {
        if (lowest == null || res < lowest) lowest = res;
      } else {
        if (i == 0) break;
      }
    }
    return lowest;
  }

  Future<int?> pingGoogleViaProxy(
    HttpClient client, {
    int count = 1,
    Duration timeout = const Duration(seconds: 4),
  }) async {
    int? best;
    for (int i = 0; i < count; i++) {
      try {
        final sw = Stopwatch()..start();
        final req = await client.getUrl(Uri.parse('http://www.google.com/generate_204')).timeout(timeout);
        final resp = await req.close().timeout(timeout);
        sw.stop();
        await resp.drain();
        if (resp.statusCode == 204 || resp.statusCode == 200) {
          final lat = sw.elapsedMilliseconds;
          if (best == null || lat < best) best = lat;
        }
      } catch (_) {}
    }
    return best;
  }

  Future<int?> _probeNodeStrictProtocol(ProxyNode node, Duration timeout) async {
    final sw = Stopwatch()..start();
    Socket? rawSocket;
    try {
      rawSocket = await Socket.connect(node.address, node.port, timeout: timeout);
      final tcpLatency = sw.elapsedMilliseconds;
      Socket activeSocket = rawSocket;

      final sni = (node.sni != null && node.sni!.isNotEmpty)
          ? node.sni!
          : ((node.host != null && node.host!.isNotEmpty) ? node.host! : node.address);

      if (node.security == SecurityType.tls) {
        try {
          activeSocket = await SecureSocket.secure(
            rawSocket,
            host: sni,
            supportedProtocols: const ['http/1.1'],
            onBadCertificate: (_) => node.allowInsecure,
          ).timeout(timeout);
        } catch (_) {
          rawSocket.destroy();
          return null;
        }
      }

      final isWsTransport = node.network == NetworkType.ws || node.network == NetworkType.httpUpgrade;
      final isXhttpTransport = node.network == NetworkType.xhttp || node.network == NetworkType.splithttp;

      if (isWsTransport || isXhttpTransport) {
        final path = (node.path == null || node.path!.trim().isEmpty)
            ? '/'
            : (node.path!.trim().startsWith('/') ? node.path!.trim() : '/${node.path!.trim()}');

        final hostHeader = (node.host != null && node.host!.trim().isNotEmpty)
            ? node.host!.trim()
            : sni;

        final String httpRequest;
        if (isWsTransport) {
          httpRequest =
              'GET $path HTTP/1.1\r\n'
              'Host: $hostHeader\r\n'
              'User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64)\r\n'
              'Upgrade: websocket\r\n'
              'Connection: Upgrade\r\n'
              'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n'
              'Sec-WebSocket-Version: 13\r\n\r\n';
        } else {
          // XHTTP / SplitHTTP endpoint probe
          httpRequest =
              'GET $path HTTP/1.1\r\n'
              'Host: $hostHeader\r\n'
              'User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64)\r\n'
              'Accept: */*\r\n'
              'Connection: close\r\n\r\n';
        }

        final reqSw = Stopwatch()..start();
        activeSocket.add(utf8.encode(httpRequest));
        await activeSocket.flush();

        final completer = Completer<int?>();
        final sub = activeSocket.listen((data) {
          reqSw.stop();
          if (!completer.isCompleted) {
            final respStr = utf8.decode(data, allowMalformed: true);
            final firstLine = respStr.split('\r\n').first;
            final isCdnError = respStr.contains('502') ||
                respStr.contains('503') ||
                respStr.contains('504') ||
                respStr.contains('520') ||
                respStr.contains('521') ||
                respStr.contains('522') ||
                respStr.contains('523') ||
                respStr.contains('524') ||
                respStr.contains('525') ||
                respStr.contains('526') ||
                respStr.contains('530') ||
                respStr.contains('Error 1000') ||
                respStr.contains('Error 1005') ||
                respStr.contains('Error 1020') ||
                respStr.contains('Direct IP access not allowed');

            final isAcceptable = isWsTransport
                ? ((firstLine.contains(' 101 ') ||
                        firstLine.contains(' 200 ') ||
                        firstLine.contains(' 204 ') ||
                        firstLine.contains(' 400 ')) &&
                    !isCdnError)
                : ((firstLine.contains(' 101 ') ||
                        firstLine.contains(' 200 ') ||
                        firstLine.contains(' 204 ') ||
                        firstLine.contains(' 400 ') ||
                        firstLine.contains(' 404 ') ||
                        firstLine.contains(' 405 ')) &&
                    !isCdnError);

            if (isAcceptable) {
              final roundTrip = reqSw.elapsedMilliseconds;
              completer.complete(roundTrip > 0 ? roundTrip : tcpLatency);
            } else {
              completer.complete(null);
            }
          }
        }, onError: (_) {
          if (!completer.isCompleted) completer.complete(null);
        }, onDone: () {
          if (!completer.isCompleted) completer.complete(null);
        });

        final res = await completer.future.timeout(timeout, onTimeout: () => null);
        await sub.cancel();
        activeSocket.destroy();
        return res;
      }

      sw.stop();
      activeSocket.destroy();
      return tcpLatency > 0 ? tcpLatency : sw.elapsedMilliseconds;
    } catch (_) {
      try {
        rawSocket?.destroy();
      } catch (_) {}
      return null;
    }
  }

  Future<int?> _probeNodeDirectly(ProxyNode node, Duration timeout) async {
    return await _probeNodeStrictProtocol(node, timeout);
  }

  int _getEphemeralPort() {
    _ephemeralPortCounter++;
    if (_ephemeralPortCounter > 60000) _ephemeralPortCounter = 31000;
    return _ephemeralPortCounter;
  }

  Future<int?> _measureRealDelayThroughProxy({
    required HttpClient client,
    required String destination,
    required int port,
    required PingType pingType,
    required Duration timeout,
  }) async {
    final sw = Stopwatch()..start();
    try {
      final scheme = (port == 443) ? "https" : "http";
      final portSuffix = (port == 80 || port == 443) ? "" : ":$port";
      final uri = Uri.parse("$scheme://$destination$portSuffix/generate_204");
      final req = await client.getUrl(uri).timeout(timeout);
      final resp = await req.close().timeout(timeout);
      sw.stop();
      await resp.drain();
      if (resp.statusCode == 200 || resp.statusCode == 204) {
        return sw.elapsedMilliseconds;
      }
      return null;
    } catch (_) {
      try {
        final fallbackSw = Stopwatch()..start();
        final uri = Uri.parse("http://www.google.com/generate_204");
        final req = await client.getUrl(uri).timeout(timeout);
        final resp = await req.close().timeout(timeout);
        fallbackSw.stop();
        await resp.drain();
        if (resp.statusCode == 200 || resp.statusCode == 204) {
          return fallbackSw.elapsedMilliseconds;
        }
      } catch (_) {}
      return null;
    }
  }

  Future<({String? countryCode, String? countryName, String? exitIp})> _fetchExitIpInfo(
    HttpClient client, {
    required Duration timeout,
  }) async {
    try {
      final req = await client.getUrl(Uri.parse("http://cp.cloudflare.com/cdn-cgi/trace")).timeout(timeout);
      final resp = await req.close().timeout(timeout);
      if (resp.statusCode == 200) {
        final body = await resp.transform(utf8.decoder).join().timeout(timeout);
        String? ip;
        String? loc;
        for (final line in body.split("\n")) {
          final trimmed = line.trim();
          if (trimmed.startsWith("ip=")) {
            ip = trimmed.substring(3).trim();
          } else if (trimmed.startsWith("loc=")) {
            final l = trimmed.substring(4).trim().toUpperCase();
            if (l.isNotEmpty && l != "XX") loc = l;
          }
        }
        if (loc != null) {
          final name = CountryService.getCountryName(loc);
          return (countryCode: loc, countryName: name, exitIp: ip);
        }
      }
    } catch (_) {}
    return (countryCode: null, countryName: null, exitIp: null);
  }

  Future<_TemporaryProxyInstance> _startTemporaryProxy({
    required CoreConfig config,
    required int listenPort,
    String? xrayBinaryPath,
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    final tempDir = Directory.systemTemp;
    final tempFile = File("${tempDir.path}/v2raypro_ping_temp_${DateTime.now().millisecondsSinceEpoch}_$listenPort.json");

    final raw = Map<String, dynamic>.from(config.rawJson);
    final inbounds = <Map<String, dynamic>>[
      {
        "tag": "temp-in",
        "port": listenPort,
        "listen": "127.0.0.1",
        "protocol": "http",
      }
    ];

    final outbounds = (raw["outbounds"] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
    if (outbounds.isEmpty && config.node != null) {
      // Build outbound from node if not present
      outbounds.add({
        "tag": "proxy",
        "protocol": config.node!.protocol.name,
      });
    }

    final testConfig = {
      "log": {"loglevel": "none"},
      "dns": {"servers": ["1.1.1.1", "8.8.8.8", "localhost"]},
      "inbounds": inbounds,
      "outbounds": outbounds,
      "routing": {
        "domainStrategy": "IPIfNonMatch",
        "rules": [
          {"type": "field", "inboundTag": ["temp-in"], "outboundTag": "proxy"}
        ]
      }
    };

    await tempFile.writeAsString(jsonEncode(testConfig));

    Process? process;
    if (xrayBinaryPath != null && File(xrayBinaryPath).existsSync()) {
      process = await Process.start(
        xrayBinaryPath,
        ["run", "-c", tempFile.path],
        workingDirectory: workingDirectory,
        environment: environment,
      );
      // Wait until listening socket is ready
      for (int i = 0; i < 8; i++) {
        try {
          final s = await Socket.connect("127.0.0.1", listenPort, timeout: const Duration(milliseconds: 50));
          await s.close();
          s.destroy();
          break;
        } catch (_) {
          await Future.delayed(const Duration(milliseconds: 50));
        }
      }
    }

    return _TemporaryProxyInstance(process: process, configFile: tempFile);
  }
}

class _TemporaryProxyInstance {
  final Process? process;
  final File configFile;

  _TemporaryProxyInstance({this.process, required this.configFile});

  Future<void> dispose() async {
    if (process != null) {
      process!.kill();
    }
    try {
      if (await configFile.exists()) {
        await configFile.delete();
      }
    } catch (_) {}
  }
}
