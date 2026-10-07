import "dart:async";
import "dart:convert";
import "dart:ffi" as ffi;
import "dart:io";
import "dart:math";
import "../models/proxy_node.dart";
import "../models/log_entry.dart";
import "../models/traffic_stats.dart";
import "cdn_scanner_service.dart";
import "country_service.dart";
import "log_service.dart";

class NodeTestResult {
  final int? latencyMs;
  final String? countryCode;
  final String? country;
  final String? exitIp;

  const NodeTestResult({
    this.latencyMs,
    this.countryCode,
    this.country,
    this.exitIp,
  });

  bool get isSuccess => latencyMs != null && latencyMs! > 0;

  static ({String? ip, String? loc}) parseCloudflareTrace(String body) {
    String? ip;
    String? loc;
    for (final line in body.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.startsWith('ip=')) {
        ip = trimmed.substring(3).trim();
      } else if (trimmed.startsWith('loc=')) {
        final val = trimmed.substring(4).trim().toUpperCase();
        if (val.isNotEmpty && val != 'XX') {
          loc = val;
        }
      }
    }
    return (ip: ip, loc: loc);
  }
}

enum EngineState { stopped, starting, running, stopping, error }

class XrayProcessService {
  static final XrayProcessService instance = XrayProcessService._internal();
  XrayProcessService._internal();

  Process? _process;
  EngineState _state = EngineState.stopped;
  EngineState get state => _state;

  File? _currentConfigFile;
  ProxyNode? _activeRunningNode;
  int socksPort = 10999;
  int httpPort = 10888;
  int apiPort = 10085;
  List<String> dnsServers = const ["1.1.1.1", "1.0.0.1", "https://1.1.1.1/dns-query"];
  bool isSystemProxySet = false;
  String? lastLog;
  String? lastErrorLog;

  Timer? _trafficTimer;
  final _trafficStreamController = StreamController<TrafficStats>.broadcast();
  Stream<TrafficStats> get trafficStream => _trafficStreamController.stream;
  TrafficStats _currentTrafficStats = const TrafficStats();
  TrafficStats get currentTrafficStats => _currentTrafficStats;

  String? _findXrayBinary() {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final candidates = [
      "$exeDir/xray/xray.exe",
      "xray/xray.exe",
      "xray.exe",
      "assets/bin/xray.exe",
      "$exeDir/xray.exe",
      "$exeDir/assets/bin/xray.exe",
      "$exeDir/data/flutter_assets/assets/bin/xray.exe",
      "flutter/assets/bin/xray.exe",
    ];

    for (final path in candidates) {
      if (File(path).existsSync()) {
        return path;
      }
    }
    return null;
  }

  /// Public accessor to locate the Xray executable
  String? findXrayBinarySync() => _findXrayBinary();

  /// Check if Xray binary is available on the system
  bool isCoreAvailable() => _findXrayBinary() != null;

  /// Check whether a node configuration is structurally valid and supported by Xray
  bool isNodeConfigSupported(ProxyNode node) {
    if (node.address.trim().isEmpty || node.port <= 0 || node.port > 65535) return false;
    if (node.protocol == ProtocolType.vless || node.protocol == ProtocolType.vmess) {
      if (node.uuidOrPassword.trim().isEmpty) return false;
    }
    if (node.security == SecurityType.reality) {
      if (node.publicKey == null || node.publicKey!.trim().isEmpty) return false;
    }
    return true;
  }

  Map<String, dynamic> generateXrayConfig(ProxyNode node, {bool enableTun = false, bool enableUdp = true}) {
    final netName = (node.network == NetworkType.splithttp || node.network == NetworkType.xhttp)
        ? "xhttp"
        : node.network.name;

    final streamSettings = <String, dynamic>{
      "network": netName,
      "security": node.security.name,
    };

    if (node.security == SecurityType.tls) {
      final tls = <String, dynamic>{
        "serverName": node.sni ?? node.host ?? node.address,
      };
      if (node.fingerprint != null && node.fingerprint!.isNotEmpty) {
        tls["fingerprint"] = node.fingerprint;
      }
      if (node.alpn != null && node.alpn!.isNotEmpty) {
        tls["alpn"] = node.alpn;
      }
      streamSettings["tlsSettings"] = tls;
    } else if (node.security == SecurityType.reality) {
      if (node.publicKey != null && node.publicKey!.trim().isNotEmpty) {
        final reality = <String, dynamic>{
          "serverName": node.sni ?? node.host ?? "",
          "publicKey": node.publicKey!.trim(),
          "shortId": node.shortId ?? "",
          "spiderX": node.spiderX ?? "/",
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
        "path": node.path ?? "/",
        "host": node.host ?? node.sni ?? node.address,
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
        "path": node.path ?? "/",
        "headers": {"Host": node.host ?? node.sni ?? node.address},
      };
    } else if (node.network == NetworkType.grpc) {
      streamSettings["grpcSettings"] = {
        "serviceName": node.serviceName ?? "",
        "multiMode": true,
      };
    } else if (node.network == NetworkType.h2) {
      streamSettings["httpSettings"] = {
        "path": node.path ?? "/",
        "host": [node.host ?? node.sni ?? node.address],
      };
    } else if (node.network == NetworkType.httpUpgrade) {
      streamSettings["httpUpgradeSettings"] = {
        "path": node.path ?? "/",
        "host": node.host ?? node.sni ?? node.address,
      };
    }

    if (node.network == NetworkType.tcp && (node.headerType?.toLowerCase() == 'http')) {
      streamSettings["tcpSettings"] = {
        "header": {
          "type": "http",
          "request": {
            "path": [node.path ?? "/"],
            "headers": {
              "Host": [node.host ?? node.sni ?? node.address],
            }
          }
        }
      };
    }

    Map<String, dynamic> outbound;
    if (node.protocol == ProtocolType.vless) {
      final user = <String, dynamic>{
        "id": node.uuidOrPassword,
        "encryption": "none",
        "level": 0,
      };
      if (node.flow != null && node.flow!.trim().isNotEmpty) {
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
      const supportedSsMethods = {
        'aes-128-gcm',
        'aes-256-gcm',
        'chacha20-poly1305',
        'chacha20-ietf-poly1305',
        'xchacha20-ietf-poly1305',
        '2022-blake3-aes-128-gcm',
        '2022-blake3-aes-256-gcm',
        '2022-blake3-chacha20-poly1305',
        'none',
        'plain',
      };
      final rawMethod = (node.cipher ?? '').toLowerCase().trim();
      final method = supportedSsMethods.contains(rawMethod) ? rawMethod : 'aes-256-gcm';

      outbound = {
        "tag": "proxy",
        "protocol": "shadowsocks",
        "settings": {
          "servers": [
            {
              "address": node.address,
              "port": node.port,
              "method": method,
              "password": node.uuidOrPassword,
              "level": 0
            }
          ]
        }
      };
    }

    final inbounds = <Map<String, dynamic>>[
      {
        "tag": "socks-in",
        "port": socksPort,
        "listen": "127.0.0.1",
        "protocol": "socks",
        "settings": {"auth": "noauth", "udp": enableUdp},
        "sniffing": {"enabled": true, "destOverride": ["http", "tls"]}
      },
      {
        "tag": "http-in",
        "port": httpPort,
        "listen": "127.0.0.1",
        "protocol": "http",
        "sniffing": {"enabled": true, "destOverride": ["http", "tls"]}
      }
    ];

    if (enableTun) {
      inbounds.add({
        "tag": "tun-in",
        "protocol": "tun",
        "settings": {
          "name": "v2raypro-tun",
          "mtu": 1500,
          "gateway": [
            "172.19.0.1/30"
          ],
          "dns": (() {
            final tunIps = dnsServers
                .where((s) => !s.startsWith("https://") && s.toLowerCase() != "localhost" && s.trim().isNotEmpty)
                .toList();
            return tunIps.isNotEmpty ? tunIps : ["1.1.1.1", "8.8.8.8"];
          })(),
          "autoSystemRoutingTable": [
            "0.0.0.0/0",
            "0.0.0.0/1",
            "128.0.0.0/1"
          ],
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
        ? [
            ...dnsServers,
            if (!dnsServers.contains("localhost")) "localhost"
          ]
        : ["8.8.8.8", "1.1.1.1", "https://1.1.1.1/dns-query", "localhost"];

    return {
      "log": {"loglevel": "warning"},
      "api": {
        "tag": "api",
        "services": ["StatsService"]
      },
      "stats": {},
      "policy": {
        "levels": {
          "0": {
            "statsUserUplink": true,
            "statsUserDownlink": true
          }
        },
        "system": {
          "statsInboundUplink": true,
          "statsInboundDownlink": true,
          "statsOutboundUplink": true,
          "statsOutboundDownlink": true
        }
      },
      "dns": {
        "servers": effectiveDns
      },
      "inbounds": [
        ...inbounds,
        {
          "tag": "api",
          "port": apiPort,
          "listen": "127.0.0.1",
          "protocol": "dokodemo-door",
          "settings": {"address": "127.0.0.1"}
        }
      ],
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
          {"type": "field", "outboundTag": "direct", "ip": ["geoip:private"]}
        ]
      }
    };
  }

  Future<bool> _isPortAvailable(int port) async {
    try {
      final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
      await s.close();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _ensurePortAvailable(int port) async {
    if (await _isPortAvailable(port)) return true;

    LogService.instance.add("Port $port is currently in use. Attempting to release conflicting background process...", level: LogLevel.warning, source: "system");

    if (Platform.isWindows) {
      try {
        Process.runSync("powershell", [
          "-NoProfile",
          "-NonInteractive",
          "-Command",
          "\$c = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue; if (\$c) { Stop-Process -Id \$c.OwningProcess -Force -ErrorAction SilentlyContinue }",
        ]);
      } catch (_) {}
    }

    await Future.delayed(const Duration(milliseconds: 300));
    return await _isPortAvailable(port);
  }

  Future<bool> start(ProxyNode node, {bool enableTun = false, bool setSysProxy = false, bool enableUdp = true}) async {
    // Always stop and cleanup any existing process
    await stop();

    _state = EngineState.starting;
    LogService.instance.add("Initializing Xray core for node: ${node.name} (${node.address}:${node.port}) [TUN: $enableTun, SysProxy: $setSysProxy, UDP: $enableUdp]", level: LogLevel.info, source: "system");

    final binaryPath = _findXrayBinary();
    if (binaryPath == null) {
      _state = EngineState.error;
      LogService.instance.add("Xray binary not found. Unable to start core.", level: LogLevel.error, source: "system");
      return false;
    }

    // Verify and ensure inbound ports are free before launching Xray
    final socksOk = await _ensurePortAvailable(socksPort);
    if (!socksOk) {
      _state = EngineState.error;
      LogService.instance.add("SOCKS port $socksPort is occupied by another application. Please change it in Settings.", level: LogLevel.error, source: "system");
      return false;
    }

    final httpOk = await _ensurePortAvailable(httpPort);
    if (!httpOk) {
      _state = EngineState.error;
      LogService.instance.add("HTTP port $httpPort is occupied by another application. Please change it in Settings.", level: LogLevel.error, source: "system");
      return false;
    }

    final apiOk = await _ensurePortAvailable(apiPort);
    if (!apiOk) {
      LogService.instance.add("API port $apiPort is occupied by another application. Traffic stats may be unavailable.", level: LogLevel.warning, source: "system");
    }

    try {
      final configJson = generateXrayConfig(node, enableTun: enableTun, enableUdp: enableUdp);
      final tmpDir = Directory.systemTemp;
      _currentConfigFile = File("${tmpDir.path}/v2raypro_active_config.json");
      await _currentConfigFile!.writeAsString(jsonEncode(configJson));

      _process = await Process.start(
        binaryPath,
        ["run", "-c", _currentConfigFile!.path],
        workingDirectory: File(binaryPath).parent.path,
        mode: ProcessStartMode.normal,
      );

      bool processExitedEarly = false;
      int? earlyExitCode;
      final capturedLines = <String>[];

      _process!.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
        lastLog = line;
        capturedLines.add(line);
        LogService.instance.addFromRawLine(line, source: "xray");
      });
      _process!.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
        lastErrorLog = line;
        capturedLines.add(line);
        LogService.instance.addFromRawLine(line, source: "xray");
      });

      _process!.exitCode.then((code) {
        if (_state == EngineState.starting) {
          processExitedEarly = true;
          earlyExitCode = code;
          _state = EngineState.error;
        } else if (_state == EngineState.running) {
          _state = EngineState.stopped;
        }
        final level = code == 0 ? LogLevel.info : LogLevel.error;
        LogService.instance.add("Xray core exited with code $code", level: level, source: "xray");
      });

      // Allow 400ms to verify process initialized and did not immediately crash
      await Future.delayed(const Duration(milliseconds: 400));
      if (processExitedEarly || _state != EngineState.starting) {
        _state = EngineState.error;
        final errorMsg = capturedLines.isNotEmpty
            ? capturedLines.last
            : "Process terminated unexpectedly with exit code $earlyExitCode";
        LogService.instance.add("Xray failed to initialize: $errorMsg", level: LogLevel.error, source: "system");
        return false;
      }

      // Enable system proxy on Windows only if requested
      if (Platform.isWindows && setSysProxy) {
        setWindowsSystemProxy(true);
      }

      _state = EngineState.running;
      _activeRunningNode = node;
      _startTrafficPolling();
      LogService.instance.add("Xray core started successfully.", level: LogLevel.info, source: "system");
      return true;
    } catch (e) {
      _state = EngineState.error;
      _activeRunningNode = null;
      LogService.instance.add("Failed to start Xray process: $e", level: LogLevel.error, source: "system");
      return false;
    }
  }

  Future<void> stop() async {
    _state = EngineState.stopping;
    _activeRunningNode = null;
    _stopTrafficPolling();
    LogService.instance.add("Stopping Xray core...", level: LogLevel.info, source: "system");
    if (Platform.isWindows) {
      setWindowsSystemProxy(false);
    }
    if (_process != null) {
      final pid = _process!.pid;
      _process!.kill();
      _process = null;
      if (Platform.isWindows) {
        try {
          Process.runSync("taskkill", ["/F", "/T", "/PID", "$pid"]);
        } catch (_) {}
      }
    }
    try {
      if (_currentConfigFile != null && await _currentConfigFile!.exists()) {
        await _currentConfigFile!.delete();
      }
    } catch (_) {}
    _state = EngineState.stopped;
    LogService.instance.add("Xray core stopped.", level: LogLevel.info, source: "system");
  }

  /// Complete system cleanup for startup and shutdown:
  /// Clears Windows system proxy, terminates orphan xray processes, and removes temp config
  void cleanupSystemAndXray() {
    try {
      if (Platform.isWindows) {
        setWindowsSystemProxy(false);
        // Kill any orphan xray.exe processes left running
        try {
          Process.runSync("taskkill", ["/F", "/IM", "xray.exe"]);
        } catch (_) {}
      }
      if (_process != null) {
        _process!.kill();
        _process = null;
      }
      final tmpDir = Directory.systemTemp;
      final activeConfig = File("${tmpDir.path}/v2raypro_active_config.json");
      if (activeConfig.existsSync()) {
        try { activeConfig.deleteSync(); } catch (_) {}
      }
      _state = EngineState.stopped;
    } catch (_) {}
  }

  void _notifyWindowsProxyChanged() {
    if (!Platform.isWindows) return;
    try {
      final wininet = ffi.DynamicLibrary.open("wininet.dll");
      final internetSetOption = wininet.lookupFunction<
          ffi.Int32 Function(ffi.Pointer, ffi.Int32, ffi.Pointer, ffi.Int32),
          int Function(ffi.Pointer, int, ffi.Pointer, int)>("InternetSetOptionW");
      internetSetOption(ffi.Pointer.fromAddress(0), 39, ffi.Pointer.fromAddress(0), 0); // INTERNET_OPTION_SETTINGS_CHANGED
      internetSetOption(ffi.Pointer.fromAddress(0), 37, ffi.Pointer.fromAddress(0), 0); // INTERNET_OPTION_REFRESH
    } catch (_) {}
  }

  void setWindowsSystemProxy(bool enable) {
    if (!Platform.isWindows) return;
    try {
      if (enable) {
        Process.runSync("reg", [
          "add",
          r"HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings",
          "/v",
          "ProxyEnable",
          "/t",
          "REG_DWORD",
          "/d",
          "1",
          "/f"
        ]);
        Process.runSync("reg", [
          "add",
          r"HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings",
          "/v",
          "ProxyServer",
          "/t",
          "REG_SZ",
          "/d",
          "127.0.0.1:$httpPort",
          "/f"
        ]);
        isSystemProxySet = true;
      } else {
        Process.runSync("reg", [
          "add",
          r"HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings",
          "/v",
          "ProxyEnable",
          "/t",
          "REG_DWORD",
          "/d",
          "0",
          "/f"
        ]);
        isSystemProxySet = false;
      }
      _notifyWindowsProxyChanged();
      LogService.instance.add(
        enable ? "System proxy activated (127.0.0.1:$httpPort)" : "System proxy deactivated",
        level: LogLevel.info,
        source: "system",
      );
    } catch (_) {}
  }

  void _startTrafficPolling() {
    _trafficTimer?.cancel();
    final binary = _findXrayBinary();
    if (binary == null) return;

    _trafficTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (_state != EngineState.running) return;
      try {
        final res = await Process.run(binary, [
          'api',
          'statsquery',
          '--server=127.0.0.1:$apiPort',
        ]);
        if (res.exitCode == 0 && res.stdout != null) {
          final json = jsonDecode(res.stdout.toString()) as Map<String, dynamic>;
          final statList = json['stat'] as List<dynamic>?;
          if (statList != null) {
            int downlink = 0;
            int uplink = 0;
            for (final item in statList) {
              if (item is Map<String, dynamic>) {
                final name = item['name'] as String? ?? '';
                final val = item['value'] as int? ?? 0;
                if (name == 'outbound>>>proxy>>>traffic>>>downlink') {
                  downlink += val;
                } else if (name == 'outbound>>>proxy>>>traffic>>>uplink') {
                  uplink += val;
                }
              }
            }
            // Fallback: If proxy outbound didn't capture (e.g. direct/tun), check inbounds
            if (downlink == 0 && uplink == 0) {
              for (final item in statList) {
                if (item is Map<String, dynamic>) {
                  final name = item['name'] as String? ?? '';
                  final val = item['value'] as int? ?? 0;
                  if (name.contains('traffic>>>downlink') && !name.contains('api')) {
                    downlink += val;
                  } else if (name.contains('traffic>>>uplink') && !name.contains('api')) {
                    uplink += val;
                  }
                }
              }
            }
            _currentTrafficStats = TrafficStats(downlinkBytes: downlink, uplinkBytes: uplink);
            _trafficStreamController.add(_currentTrafficStats);
          }
        }
      } catch (_) {}
    });
  }

  void _stopTrafficPolling() {
    _trafficTimer?.cancel();
    _trafficTimer = null;
    _currentTrafficStats = const TrafficStats(downlinkBytes: 0, uplinkBytes: 0);
    _trafficStreamController.add(_currentTrafficStats);
  }

  /// Concurrently tests a batch of candidate nodes using an ephemeral multi-inbound Xray process.
  /// Routes genuine HTTP requests through each node to Cloudflare cdn-cgi/trace to obtain:
  /// 1. True round-trip latency (ping).
  /// 2. Outbound exit IP.
  /// 3. Outbound exit country (loc).
  /// Falls back to generate_204 endpoints if cdn-cgi/trace fails.
  /// Returns a Map of node ID to NodeTestResult.
  Future<Map<String, NodeTestResult>> testNodesBatchRealProxy(
    List<ProxyNode> nodes, {
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final validNodes = nodes.where(isNodeConfigSupported).toList();
    if (validNodes.isEmpty) return {};

    final xrayBin = _findXrayBinary();
    if (xrayBin == null) return {};

    final basePort = 29200 + (Random().nextInt(400) * 10);
    final inbounds = <Map<String, dynamic>>[];
    final outbounds = <Map<String, dynamic>>[];
    final rules = <Map<String, dynamic>>[];

    for (int i = 0; i < validNodes.length; i++) {
      final port = basePort + i;
      final inTag = 'in_$i';
      final outTag = 'out_$i';

      inbounds.add({
        'tag': inTag,
        'port': port,
        'listen': '127.0.0.1',
        'protocol': 'http',
      });

      final fullConfig = generateXrayConfig(validNodes[i]);
      final ob = Map<String, dynamic>.from(fullConfig['outbounds'][0] as Map<String, dynamic>);
      ob['tag'] = outTag;
      outbounds.add(ob);

      rules.add({
        'type': 'field',
        'inboundTag': [inTag],
        'outboundTag': outTag,
      });
    }

    outbounds.add({'tag': 'dns-out', 'protocol': 'dns'});
    outbounds.add({'tag': 'direct', 'protocol': 'freedom'});
    rules.add({'type': 'field', 'port': 53, 'outboundTag': 'dns-out'});

    final testConfig = {
      'log': {'loglevel': 'none'},
      'dns': {'servers': ['1.1.1.1', '8.8.8.8', 'localhost']},
      'inbounds': inbounds,
      'outbounds': outbounds,
      'routing': {
        'domainStrategy': 'IPIfNonMatch',
        'rules': rules,
      }
    };

    final tempFile = File('${Directory.systemTemp.path}/xray_batch_test_${DateTime.now().millisecondsSinceEpoch}.json');
    Process? proc;
    try {
      await tempFile.writeAsString(jsonEncode(testConfig));

      final valResult = await Process.run(xrayBin, ['run', '-test', '-c', tempFile.path]);
      if (valResult.exitCode != 0) {
        if (validNodes.length > 1) {
          final singleResults = <String, NodeTestResult>{};
          for (final singleNode in validNodes) {
            final res = await testNodesBatchRealProxy([singleNode], timeout: timeout);
            singleResults.addAll(res);
          }
          return singleResults;
        }
        return {};
      }

      proc = await Process.start(xrayBin, ['run', '-c', tempFile.path]);
      await Future.delayed(const Duration(milliseconds: 250));

      final results = <String, NodeTestResult>{};
      await Future.wait(List.generate(validNodes.length, (i) async {
        final port = basePort + i;
        final node = validNodes[i];
        final client = HttpClient();
        client.findProxy = (uri) => 'PROXY 127.0.0.1:$port';
        client.connectionTimeout = timeout;

        // 1. Primary: Cloudflare cdn-cgi/trace gives real exit IP and exit country code
        final sw = Stopwatch()..start();
        try {
          final r = await client.getUrl(Uri.parse('http://cp.cloudflare.com/cdn-cgi/trace')).timeout(timeout);
          final resp = await r.close().timeout(timeout);
          if (resp.statusCode == 200) {
            final body = await resp.transform(utf8.decoder).join().timeout(timeout);
            sw.stop();
            final trace = NodeTestResult.parseCloudflareTrace(body);
            String? cCode = trace.loc;
            if (cCode == null && trace.ip != null) {
              cCode = LocalGeoIp.instance.lookup(trace.ip!);
            }
            if (cCode == null) {
              cCode = CountryService.resolveSync(node) ?? await CountryService.instance.resolveCountryCode(node);
            }
            final cName = cCode != null ? CountryService.getCountryName(cCode) : null;
            results[node.id] = NodeTestResult(
              latencyMs: sw.elapsedMilliseconds,
              countryCode: cCode,
              country: cName,
              exitIp: trace.ip,
            );
          }
        } catch (_) {}

        // 2. Fallback if cdn-cgi/trace failed: generate_204 endpoints
        if (!results.containsKey(node.id)) {
          final fallbackUrls = [
            'http://cp.cloudflare.com/generate_204',
            'http://www.google.com/generate_204',
            'http://connectivitycheck.gstatic.com/generate_204',
          ];

          for (final targetUrl in fallbackUrls) {
            if (results.containsKey(node.id)) break;
            final swFall = Stopwatch()..start();
            try {
              final r = await client.getUrl(Uri.parse(targetUrl)).timeout(timeout);
              final resp = await r.close().timeout(timeout);
              swFall.stop();
              if (resp.statusCode == 204 || resp.statusCode == 200) {
                final cCode = CountryService.resolveSync(node) ?? await CountryService.instance.resolveCountryCode(node);
                final cName = cCode != null ? CountryService.getCountryName(cCode) : null;
                results[node.id] = NodeTestResult(
                  latencyMs: swFall.elapsedMilliseconds,
                  countryCode: cCode,
                  country: cName,
                );
                break;
              }
            } catch (_) {}
          }
        }
        client.close(force: true);
      }));

      return results;
    } catch (_) {
      return {};
    } finally {
      proc?.kill();
      try {
        if (tempFile.existsSync()) await tempFile.delete();
      } catch (_) {}
    }
  }

  /// Real Latency & Outbound Country Test:
  /// Performs an end-to-end transport and protocol test to measure true round-trip response time,
  /// as well as the authentic outbound exit IP and country.
  /// 1. For currently connected active node: queries cdn-cgi/trace via the running local proxy.
  /// 2. If Xray core is available and node is supported: tests genuine proxy delay & exit IP via ephemeral Xray test process.
  /// 3. Fallback: performs direct transport protocol handshake test to the destination server.
  Future<NodeTestResult> testNodeRealDelay(
    ProxyNode node, {
    Duration timeout = const Duration(seconds: 4),
  }) async {
    // 1. If this node is currently connected and active in Xray, test real end-to-end internet ping via local proxy
    if (_state == EngineState.running && _activeRunningNode?.id == node.id) {
      final activeRes = await _testHttpViaLocalProxy(timeout);
      if (activeRes != null && activeRes.isSuccess) {
        if (activeRes.countryCode != null) {
          return activeRes;
        }
        final cCode = CountryService.resolveSync(node) ?? await CountryService.instance.resolveCountryCode(node);
        return NodeTestResult(
          latencyMs: activeRes.latencyMs,
          countryCode: cCode,
          country: cCode != null ? CountryService.getCountryName(cCode) : null,
          exitIp: activeRes.exitIp,
        );
      }
    }

    // 2. Try genuine proxy delay test through an ephemeral Xray test process
    if (isNodeConfigSupported(node) && _findXrayBinary() != null) {
      try {
        final batchResult = await testNodesBatchRealProxy([node], timeout: timeout);
        if (batchResult.containsKey(node.id) && batchResult[node.id] != null && batchResult[node.id]!.isSuccess) {
          return batchResult[node.id]!;
        }
      } catch (_) {}
    }

    // 3. Fallback to direct real protocol handshake latency test
    final handshakeLat = await _testNodeRealProtocolDelay(node, timeout: timeout);
    if (handshakeLat != null && handshakeLat > 0) {
      final cCode = CountryService.resolveSync(node) ?? await CountryService.instance.resolveCountryCode(node);
      return NodeTestResult(
        latencyMs: handshakeLat,
        countryCode: cCode,
        country: cCode != null ? CountryService.getCountryName(cCode) : null,
      );
    }

    return const NodeTestResult(latencyMs: null);
  }

  /// Backward-compatible latency tester returning milliseconds
  Future<int?> testNodeLatency(ProxyNode node, {Duration timeout = const Duration(seconds: 4)}) async {
    final res = await testNodeRealDelay(node, timeout: timeout);
    return res.latencyMs;
  }

  Future<NodeTestResult?> _testHttpViaLocalProxy(Duration timeout) async {
    // 1. Primary: Cloudflare cdn-cgi/trace through running local proxy
    HttpClient? client;
    try {
      client = HttpClient();
      client.findProxy = (uri) => "PROXY 127.0.0.1:$httpPort";
      client.connectionTimeout = timeout;
      final sw = Stopwatch()..start();
      final request = await client.getUrl(Uri.parse("http://cp.cloudflare.com/cdn-cgi/trace")).timeout(timeout);
      final response = await request.close().timeout(timeout);
      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join().timeout(timeout);
        sw.stop();
        client.close(force: true);
        final trace = NodeTestResult.parseCloudflareTrace(body);
        String? cCode = trace.loc;
        if (cCode == null && trace.ip != null) {
          cCode = LocalGeoIp.instance.lookup(trace.ip!);
        }
        final cName = cCode != null ? CountryService.getCountryName(cCode) : null;
        return NodeTestResult(
          latencyMs: sw.elapsedMilliseconds,
          countryCode: cCode,
          country: cName,
          exitIp: trace.ip,
        );
      }
    } catch (_) {
      try {
        client?.close(force: true);
      } catch (_) {}
    }

    // 2. Fallback to generate_204 targets
    final targets = [
      "http://cp.cloudflare.com/generate_204",
      "http://www.google.com/generate_204",
      "http://connectivitycheck.gstatic.com/generate_204",
    ];

    for (final target in targets) {
      final sw = Stopwatch()..start();
      HttpClient? fClient;
      try {
        fClient = HttpClient();
        fClient.findProxy = (uri) => "PROXY 127.0.0.1:$httpPort";
        fClient.connectionTimeout = timeout;
        final request = await fClient.getUrl(Uri.parse(target)).timeout(timeout);
        final response = await request.close().timeout(timeout);
        sw.stop();
        fClient.close(force: true);
        if (response.statusCode == 204 || response.statusCode == 200) {
          return NodeTestResult(latencyMs: sw.elapsedMilliseconds);
        }
      } catch (_) {
        try {
          fClient?.close(force: true);
        } catch (_) {}
      }
    }
    return null;
  }

  Future<int?> _testNodeRealProtocolDelay(ProxyNode node, {Duration timeout = const Duration(seconds: 4)}) async {
    final sw = Stopwatch()..start();
    Socket? rawSocket;
    try {
      rawSocket = await Socket.connect(node.address, node.port, timeout: timeout);
      Socket activeSocket = rawSocket;

      final host = (node.host != null && node.host!.isNotEmpty)
          ? node.host!
          : ((node.sni != null && node.sni!.isNotEmpty) ? node.sni! : node.address);
      final sni = (node.sni != null && node.sni!.isNotEmpty)
          ? node.sni!
          : ((node.host != null && node.host!.isNotEmpty) ? node.host! : node.address);

      if (node.security == SecurityType.tls) {
        try {
          activeSocket = await SecureSocket.secure(
            rawSocket,
            host: sni,
            onBadCertificate: (_) => true,
          ).timeout(timeout);
        } catch (_) {
          // If SecureSocket fails, connection already established over TCP
        }
      } else if (node.security == SecurityType.reality) {
        // Reality uses uTLS which Dart SecureSocket does not natively handle.
        // Attempt probe; if certificate validation fails, keep the established TCP socket.
        try {
          final probe = await SecureSocket.secure(
            rawSocket,
            host: sni,
            onBadCertificate: (_) => true,
          ).timeout(timeout);
          activeSocket = probe;
        } catch (_) {
          // Expected for Reality nodes without full uTLS client
        }
      }

      // Check if node uses HTTP / WebSocket / XHTTP / SplitHTTP transport
      // NOTE: NetworkType.tcp MUST NOT send websocket upgrade!
      final isHttpTransport = node.network == NetworkType.ws ||
          node.network == NetworkType.httpUpgrade ||
          node.network == NetworkType.xhttp ||
          node.network == NetworkType.splithttp;

      if (isHttpTransport) {
        final path = (node.path == null || node.path!.isEmpty)
            ? '/'
            : (node.path!.startsWith('/') ? node.path! : '/${node.path}');

        final httpRequest =
            'GET $path HTTP/1.1\r\n'
            'Host: $host\r\n'
            'User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64)\r\n'
            'Upgrade: websocket\r\n'
            'Connection: Upgrade\r\n'
            'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n'
            'Sec-WebSocket-Version: 13\r\n'
            '\r\n';

        activeSocket.add(utf8.encode(httpRequest));
        await activeSocket.flush();

        final completer = Completer<int?>();
        final subscription = activeSocket.listen(
          (data) {
            sw.stop();
            if (!completer.isCompleted) {
              final responseStr = utf8.decode(data, allowMalformed: true);
              final firstLine = responseStr.split('\r\n').first;

              // Strictly reject CDN error status codes or WAF blocks (502, 503, 504, 520-526, etc.):
              final isCdnError = responseStr.contains('502') ||
                  responseStr.contains('503') ||
                  responseStr.contains('504') ||
                  responseStr.contains('520') ||
                  responseStr.contains('521') ||
                  responseStr.contains('522') ||
                  responseStr.contains('523') ||
                  responseStr.contains('524') ||
                  responseStr.contains('525') ||
                  responseStr.contains('526') ||
                  responseStr.contains('530') ||
                  responseStr.contains('Error 1000') ||
                  responseStr.contains('Error 1005') ||
                  responseStr.contains('Error 1020');

              // Accept any HTTP response indicating backend or web server responded:
              // 101, 200, 204, 301, 302, 400 (standard V2Ray WS probe response), 404
              final isAcceptableStatus = firstLine.startsWith('HTTP/') &&
                  !isCdnError &&
                  !firstLine.contains('502') &&
                  !firstLine.contains('503') &&
                  !firstLine.contains('504');

              if (isAcceptableStatus) {
                completer.complete(sw.elapsedMilliseconds);
              } else {
                completer.complete(null);
              }
            }
          },
          onError: (_) {
            if (!completer.isCompleted) completer.complete(null);
          },
          onDone: () {
            if (!completer.isCompleted) completer.complete(null);
          },
        );

        final result = await completer.future.timeout(timeout, onTimeout: () => null);
        await subscription.cancel();
        activeSocket.destroy();
        return result;
      }

      // gRPC transport: Send HTTP/2 client preface
      if (node.network == NetworkType.grpc) {
        final h2Preface = utf8.encode('PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n');
        final h2Settings = [0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00];
        activeSocket.add(h2Preface);
        activeSocket.add(h2Settings);
        await activeSocket.flush();

        final completer = Completer<int?>();
        final subscription = activeSocket.listen(
          (data) {
            sw.stop();
            if (!completer.isCompleted) {
              completer.complete(sw.elapsedMilliseconds);
            }
          },
          onError: (_) {
            if (!completer.isCompleted) completer.complete(null);
          },
          onDone: () {
            if (!completer.isCompleted) completer.complete(null);
          },
        );

        final result = await completer.future.timeout(timeout, onTimeout: () => null);
        await subscription.cancel();
        activeSocket.destroy();
        return result;
      }

      // Standard TCP / Direct / Reality: Socket connect (+ TLS if available) is successful!
      sw.stop();
      activeSocket.destroy();
      return sw.elapsedMilliseconds;
    } catch (_) {
      try {
        rawSocket?.destroy();
      } catch (_) {}
      return null;
    }
  }

  /// Check if the process is running with Administrator privileges on Windows
  bool isRunningAsAdmin() {
    if (!Platform.isWindows) return true;
    try {
      final res = Process.runSync("net", ["session"]);
      return res.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Relaunch application with Administrator privileges via UAC
  Future<void> restartAsAdmin() async {
    if (!Platform.isWindows) return;
    try {
      final exePath = Platform.resolvedExecutable;
      await Process.start("powershell", [
        "-NoProfile",
        "-Command",
        "Start-Process -FilePath '$exePath' -Verb RunAs",
      ]);
      exit(0);
    } catch (_) {}
  }
}

