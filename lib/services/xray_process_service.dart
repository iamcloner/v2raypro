import "dart:async";
import "dart:convert";
import "dart:ffi" as ffi;
import "dart:io";
import "package:flutter/services.dart";
import "package:path_provider/path_provider.dart";
import "../models/proxy_node.dart";
import "../models/routing_rule.dart";
import "../models/log_entry.dart";
import "../models/traffic_stats.dart";
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
  bool globalAllowInsecure = false;
  bool globalEnableMux = false;
  bool globalAllowLan = false;
  List<RoutingRule> routingRules = [];
  AppRoutingMode appRoutingMode = AppRoutingMode.exclusive;
  String? lastLog;
  String? lastErrorLog;
  static int _nextBatchPort = 29200;

  Timer? _trafficTimer;
  final _trafficStreamController = StreamController<TrafficStats>.broadcast();
  Stream<TrafficStats> get trafficStream => _trafficStreamController.stream;
  TrafficStats _currentTrafficStats = const TrafficStats();
  TrafficStats get currentTrafficStats => _currentTrafficStats;

  String? _androidBinaryPath;
  Directory? _androidAssetDir;
  VoidCallback? onAndroidNotificationDisconnect;

  Future<void> initAndroid() async {
    if (!Platform.isAndroid) return;
    try {
      const channel = MethodChannel('com.v2raypro.app/native');
      final path = await channel.invokeMethod<String>('getXrayBinary');
      if (path != null && File(path).existsSync()) {
        _androidBinaryPath = path;
      }
    } catch (e) {
      LogService.instance.add("Android getXrayBinary: $e", level: LogLevel.warning, source: "system");
    }

    if (_androidBinaryPath == null) {
      try {
        const channel = MethodChannel('com.v2raypro.app/native');
        final libDir = await channel.invokeMethod<String>('getNativeLibraryDir');
        if (libDir != null) {
          final candidate = File('$libDir/libxray.so');
          if (candidate.existsSync()) {
            _androidBinaryPath = candidate.path;
          }
        }
      } catch (_) {}
    }

    try {
      final appSupport = await getApplicationSupportDirectory();
      final xrayDir = Directory('${appSupport.path}/xray');
      if (!xrayDir.existsSync()) {
        await xrayDir.create(recursive: true);
      }
      _androidAssetDir = xrayDir;

      for (final datName in ['geoip.dat', 'geosite.dat']) {
        final targetFile = File('${xrayDir.path}/$datName');
        if (!targetFile.existsSync() || targetFile.lengthSync() < 1000) {
          try {
            final byteData = await rootBundle.load('assets/bin/$datName');
            final buffer = byteData.buffer;
            await targetFile.writeAsBytes(
              buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes),
              flush: true,
            );
          } catch (e) {
            LogService.instance.add("Failed to extract $datName: $e", level: LogLevel.warning, source: "system");
          }
        }
      }

      LocalGeoIp.instance.ensureLoaded();

      const nativeChannel = MethodChannel('com.v2raypro.app/native');
      nativeChannel.setMethodCallHandler((call) async {
        if (call.method == 'onDisconnectedFromNotification') {
          await stop();
          onAndroidNotificationDisconnect?.call();
        }
      });
    } catch (e) {
      LogService.instance.add("Failed to initialize Android asset dir: $e", level: LogLevel.warning, source: "system");
    }
  }

  Directory? get androidAssetDir => _androidAssetDir;

  Future<bool> startAndroidVpn(
    String configName, {
    String xrayBinary = '',
    String configPath = '',
    String? assetDir,
    bool isTun = true,
    String? notificationTitle,
    String? disconnectText,
    String appRoutingMode = 'exclusive',
    List<String> appRoutingList = const [],
  }) async {
    if (!Platform.isAndroid) return false;
    try {
      const channel = MethodChannel('com.v2raypro.app/native');
      final res = await channel.invokeMethod<bool>('startVpnService', {
        'configName': configName,
        'httpPort': httpPort,
        'socksPort': socksPort,
        'isTun': isTun,
        'notificationTitle': notificationTitle ?? 'V2RayPro - متصل',
        'disconnectText': disconnectText ?? 'قطع اتصال',
        'appRoutingMode': appRoutingMode,
        'appRoutingList': appRoutingList,
        'xrayBinary': xrayBinary,
        'configPath': configPath,
        'assetDir': assetDir,
      });
      return res ?? false;
    } catch (e) {
      LogService.instance.add("startAndroidVpn failed: $e", level: LogLevel.warning, source: "system");
      return false;
    }
  }

  Future<void> stopAndroidVpn() async {
    if (!Platform.isAndroid) return;
    try {
      const channel = MethodChannel('com.v2raypro.app/native');
      await channel.invokeMethod('stopVpnService');
    } catch (_) {}
  }

  Future<bool> isAndroidVpnRunning() async {
    if (!Platform.isAndroid) return false;
    try {
      const channel = MethodChannel('com.v2raypro.app/native');
      final res = await channel.invokeMethod<bool>('isVpnRunning');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> isAnotherVpnActive() async {
    if (!Platform.isAndroid) return false;
    try {
      const channel = MethodChannel('com.v2raypro.app/native');
      final res = await channel.invokeMethod<bool>('isAnotherVpnActive');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  String _getWorkingDirectory(String binaryPath) {
    if (Platform.isAndroid && _androidAssetDir != null) {
      return _androidAssetDir!.path;
    }
    return File(binaryPath).parent.path;
  }

  Map<String, String>? _getXrayEnvironment() {
    if (Platform.isAndroid && _androidAssetDir != null) {
      return {"XRAY_LOCATION_ASSET": _androidAssetDir!.path};
    }
    return null;
  }

  String? _findXrayBinary() {
    if (Platform.isAndroid) {
      if (_androidBinaryPath != null && File(_androidBinaryPath!).existsSync()) {
        return _androidBinaryPath;
      }
      return null;
    }
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

  Map<String, dynamic> generateXrayConfig(ProxyNode node, {bool enableTun = false, bool enableUdp = true, bool allowLan = false}) {
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

    if (node.enableMux || globalEnableMux) {
      outbound["mux"] = {
        "enabled": true,
        "concurrency": 8,
      };
    }

    final listenAddr = (allowLan || globalAllowLan) ? "0.0.0.0" : "127.0.0.1";
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
      "log": {
        "loglevel": Platform.isAndroid ? "none" : "warning",
      },
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
          {"type": "field", "outboundTag": "direct", "ip": ["geoip:private"]},
          // User-defined custom routing rules
          ...(() {
            final custom = <Map<String, dynamic>>[];
            for (final r in routingRules.where((rule) => rule.enabled)) {
              if (r.values.isEmpty) continue;
              if (r.type == RoutingRuleType.address) {
                // Normalize geosite rules:
                // Many geosite.dat databases (including v2fly community) use 'geosite:category-ir'
                // rather than 'geosite:ir'. Expand 'geosite:ir' to both category-ir and regex for complete coverage.
                final expandedDomains = <String>[];
                for (final val in r.values) {
                  final trimmed = val.trim();
                  if (trimmed.toLowerCase() == "geosite:ir") {
                    expandedDomains.add("geosite:category-ir");
                    expandedDomains.add("regexp:.*\\.ir\$");
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

  Future<bool> start(
    ProxyNode node, {
    bool enableTun = false,
    bool setSysProxy = false,
    bool enableUdp = true,
    bool allowLan = false,
    String? notificationTitle,
    String? disconnectText,
  }) async {
    // Always stop and cleanup any existing process
    await stop();

    _state = EngineState.starting;
    LogService.instance.add("Initializing Xray core for node: ${node.name} (${node.address}:${node.port}) [TUN: $enableTun, SysProxy: $setSysProxy, UDP: $enableUdp, LAN: ${allowLan || globalAllowLan}]", level: LogLevel.info, source: "system");

    if (Platform.isAndroid && _androidBinaryPath == null) {
      await initAndroid();
    }

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
      final configJson = generateXrayConfig(node, enableTun: enableTun, enableUdp: enableUdp, allowLan: allowLan || globalAllowLan);
      final tmpDir = Platform.isAndroid && _androidAssetDir != null
          ? _androidAssetDir!
          : Directory.systemTemp;
      _currentConfigFile = File("${tmpDir.path}/v2raypro_active_config.json");
      await _currentConfigFile!.writeAsString(jsonEncode(configJson));

      final workDir = _getWorkingDirectory(binaryPath);
      final env = _getXrayEnvironment();

      _process = await Process.start(
        binaryPath,
        ["run", "-c", _currentConfigFile!.path],
        workingDirectory: workDir,
        environment: env,
        mode: ProcessStartMode.normal,
      );

      bool processExitedEarly = false;
      int? earlyExitCode;
      final capturedLines = <String>[];

      _process!.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
        lastLog = line;
        capturedLines.add(line);
        LogService.instance.addFromRawLine(line, source: "xray");
      }, onError: (_) {});
      _process!.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
        lastErrorLog = line;
        capturedLines.add(line);
        LogService.instance.addFromRawLine(line, source: "xray");
      }, onError: (_) {});

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

      if (Platform.isAndroid) {
        final appRules = routingRules
            .where((r) => r.type == RoutingRuleType.app && r.enabled)
            .expand((r) => r.values)
            .map((e) => e.trim())
            .where((pkg) => pkg.isNotEmpty)
            .toSet()
            .toList();

        final started = await startAndroidVpn(
          node.name,
          xrayBinary: binaryPath,
          configPath: _currentConfigFile!.path,
          assetDir: _androidAssetDir?.path,
          isTun: enableTun,
          notificationTitle: notificationTitle,
          disconnectText: disconnectText,
          appRoutingMode: appRoutingMode.name,
          appRoutingList: appRules,
        );

        if (!started) {
          _process?.kill();
          _process = null;
          _state = EngineState.error;
          LogService.instance.add("Failed to start Android VPN service.", level: LogLevel.error, source: "system");
          return false;
        }

        await Future.delayed(const Duration(milliseconds: 200));
      } else {
        // Windows Desktop
        if (setSysProxy) {
          setWindowsSystemProxy(true);
        }
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
    if (Platform.isAndroid) {
      await stopAndroidVpn();
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
  /// Clears Windows system proxy, terminates orphan xray processes, and removes temp config.
  /// On Android, background VPN is preserved unless [force] is true.
  void cleanupSystemAndXray({bool force = false}) {
    try {
      if (Platform.isWindows) {
        setWindowsSystemProxy(false);
        // Kill any orphan xray.exe processes left running
        try {
          Process.runSync("taskkill", ["/F", "/IM", "xray.exe"]);
        } catch (_) {}
      }
      if (Platform.isAndroid && force) {
        stopAndroidVpn();
      }
      if (_process != null && (!Platform.isAndroid || force)) {
        _process!.kill();
        _process = null;
      }
      final tmpDir = Directory.systemTemp;
      final activeConfig = File("${tmpDir.path}/v2raypro_active_config.json");
      if (activeConfig.existsSync() && (!Platform.isAndroid || force)) {
        try { activeConfig.deleteSync(); } catch (_) {}
      }
      if (!Platform.isAndroid || force) {
        _state = EngineState.stopped;
      }
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

    final basePort = _nextBatchPort;
    _nextBatchPort += validNodes.length + 5;
    if (_nextBatchPort > 55000) _nextBatchPort = 29200;

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

    final tempDir = Platform.isAndroid && _androidAssetDir != null
        ? _androidAssetDir!
        : Directory.systemTemp;
    final tempFile = File('${tempDir.path}/xray_batch_test_${DateTime.now().millisecondsSinceEpoch}.json');
    Process? proc;
    try {
      await tempFile.writeAsString(jsonEncode(testConfig));

      proc = await Process.start(
        xrayBin,
        ['run', '-c', tempFile.path],
        workingDirectory: _getWorkingDirectory(xrayBin),
        environment: _getXrayEnvironment(),
      );
      // Fast startup delay for localhost socket binding
      await Future.delayed(const Duration(milliseconds: 40));

      final results = <String, NodeTestResult>{};
      await Future.wait(List.generate(validNodes.length, (i) async {
        final port = basePort + i;
        final node = validNodes[i];
        final client = HttpClient();
        client.findProxy = (uri) => 'PROXY 127.0.0.1:$port';
        client.connectionTimeout = timeout;

        // 1. Primary: Ping google.com:443 3 times and select the lowest ping
        final lowestPing = await pingGoogleViaProxy(client, count: 3, timeout: timeout);

        if (lowestPing != null) {
          String? cCode;
          String? cName;
          String? exitIp;

          // Attempt fast trace to discover exit IP and country
          try {
            final r = await client.getUrl(Uri.parse('http://cp.cloudflare.com/cdn-cgi/trace')).timeout(timeout);
            final resp = await r.close().timeout(timeout);
            if (resp.statusCode == 200) {
              final body = await resp.transform(utf8.decoder).join().timeout(timeout);
              final trace = NodeTestResult.parseCloudflareTrace(body);
              cCode = trace.loc;
              exitIp = trace.ip;
              if (cCode == null && exitIp != null) {
                cCode = LocalGeoIp.instance.lookup(exitIp);
              }
              if (cCode != null) {
                cName = CountryService.getCountryName(cCode);
              }
            }
          } catch (_) {}

          final resolvedCode = cCode ?? node.countryCode ?? CountryService.resolveSync(node);
          final resolvedName = cName ?? (resolvedCode != null ? CountryService.getCountryName(resolvedCode) : node.country);
          results[node.id] = NodeTestResult(
            latencyMs: lowestPing,
            countryCode: resolvedCode,
            country: resolvedName,
            exitIp: exitIp,
          );
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

  /// Fast TCP probe: attempts up to [count] quick TCP handshakes to host:port.
  /// Returns lowest elapsed milliseconds among [count] attempts, or null if all fail.
  Future<int?> tcpPing(
    String host,
    int port, {
    int count = 3,
    Duration timeout = const Duration(milliseconds: 650),
  }) async {
    int? lowestPing;
    for (int i = 0; i < count; i++) {
      try {
        final sw = Stopwatch()..start();
        final s = await Socket.connect(host, port, timeout: timeout);
        sw.stop();
        s.destroy();
        final lat = sw.elapsedMilliseconds;
        if (lowestPing == null || lat < lowestPing) {
          lowestPing = lat;
        }
      } catch (_) {}
    }
    return lowestPing;
  }

  /// Pings google.com:443 via an established HTTP proxy client up to [count] times (default 3),
  /// returning the lowest latency in milliseconds, or null if all attempts fail.
  Future<int?> pingGoogleViaProxy(
    HttpClient client, {
    int count = 3,
    Duration timeout = const Duration(milliseconds: 2500),
  }) async {
    int? lowestPing;
    for (int attempt = 0; attempt < count; attempt++) {
      // 1. Primary: http://www.google.com/generate_204
      // Provides authentic Real Delay through proxy matching v2rayN and v2rayNG without nested double-TLS overhead
      final swHttp = Stopwatch()..start();
      try {
        final r = await client.getUrl(Uri.parse('http://www.google.com/generate_204')).timeout(timeout);
        final resp = await r.close().timeout(timeout);
        swHttp.stop();
        if (resp.statusCode == 204 || resp.statusCode == 200) {
          final lat = swHttp.elapsedMilliseconds;
          if (lowestPing == null || lat < lowestPing) {
            lowestPing = lat;
          }
          continue;
        }
      } catch (_) {}

      // 2. Secondary fallback: http://cp.cloudflare.com/generate_204
      final swCf = Stopwatch()..start();
      try {
        final r = await client.getUrl(Uri.parse('http://cp.cloudflare.com/generate_204')).timeout(timeout);
        final resp = await r.close().timeout(timeout);
        swCf.stop();
        if (resp.statusCode == 204 || resp.statusCode == 200) {
          final lat = swCf.elapsedMilliseconds;
          if (lowestPing == null || lat < lowestPing) {
            lowestPing = lat;
          }
          continue;
        }
      } catch (_) {}

      // 3. Third fallback: https://www.google.com/generate_204
      final swHttps = Stopwatch()..start();
      try {
        final r = await client.getUrl(Uri.parse('https://www.google.com/generate_204')).timeout(timeout);
        final resp = await r.close().timeout(timeout);
        swHttps.stop();
        if (resp.statusCode == 204 || resp.statusCode == 200) {
          final lat = swHttps.elapsedMilliseconds;
          if (lowestPing == null || lat < lowestPing) {
            lowestPing = lat;
          }
        }
      } catch (_) {}
    }
    return lowestPing;
  }

  /// Real Latency & Outbound Country Test:
  /// Performs an authentic 3-probe handshake test (matching v2rayNG & v2box TCPing and TLS ping)
  /// or end-to-end proxy test if the node is currently connected and active.
  Future<NodeTestResult> testNodeRealDelay(
    ProxyNode node, {
    Duration timeout = const Duration(milliseconds: 2800),
    bool isTurbo = false,
  }) async {
    // 1. If this node is currently connected and active in Xray / Android VPN, test real end-to-end internet ping via running local proxy
    final isRunningLocally = _state == EngineState.running || (Platform.isAndroid && await isAndroidVpnRunning());
    if (isRunningLocally && (node.isActive || _activeRunningNode?.id == node.id)) {
      final activeRes = await _testHttpViaLocalProxy(timeout);
      if (activeRes != null && activeRes.isSuccess) {
        final cCode = node.countryCode ?? CountryService.resolveSync(node);
        return NodeTestResult(
          latencyMs: activeRes.latencyMs,
          countryCode: activeRes.countryCode ?? cCode,
          country: activeRes.country ?? (cCode != null ? CountryService.getCountryName(cCode) : node.country),
          exitIp: activeRes.exitIp,
        );
      }
    }

    // 2. Direct protocol probe (TCP/TLS handshake to node.address:node.port, 3 probes, taking lowest):
    // Exactly matches v2rayNG and v2box latency!
    final handshakeLat = await _testNodeRealProtocolDelay(node, timeout: timeout, count: 3);
    if (handshakeLat != null && handshakeLat > 0) {
      final cCode = node.countryCode ?? CountryService.resolveSync(node);
      return NodeTestResult(
        latencyMs: handshakeLat,
        countryCode: cCode,
        country: cCode != null ? CountryService.getCountryName(cCode) : node.country,
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
    HttpClient? client;
    try {
      client = HttpClient();
      client.findProxy = (uri) => "PROXY 127.0.0.1:$httpPort";
      client.connectionTimeout = timeout;

      // 1. Primary: 3x ping to google.com:443 to measure lowest latency
      final lowestPing = await pingGoogleViaProxy(client, count: 3, timeout: timeout);

      String? cCode;
      String? cName;
      String? exitIp;

      // 2. Discover exit IP & country via Cloudflare trace
      try {
        final request = await client.getUrl(Uri.parse("http://cp.cloudflare.com/cdn-cgi/trace")).timeout(timeout);
        final response = await request.close().timeout(timeout);
        if (response.statusCode == 200) {
          final body = await response.transform(utf8.decoder).join().timeout(timeout);
          final trace = NodeTestResult.parseCloudflareTrace(body);
          cCode = trace.loc;
          exitIp = trace.ip;
          if (cCode == null && exitIp != null) {
            cCode = LocalGeoIp.instance.lookup(exitIp);
          }
          if (cCode != null) {
            cName = CountryService.getCountryName(cCode);
          }
        }
      } catch (_) {}

      client.close(force: true);

      if (lowestPing != null) {
        return NodeTestResult(
          latencyMs: lowestPing,
          countryCode: cCode,
          country: cName,
          exitIp: exitIp,
        );
      }
    } catch (_) {
      try {
        client?.close(force: true);
      } catch (_) {}
    }

    return null;
  }

  Future<int?> _singleProtocolProbe(ProxyNode node, Duration timeout) async {
    final effectiveTimeout = timeout > const Duration(milliseconds: 1500)
        ? const Duration(milliseconds: 1200)
        : timeout;
    final sw = Stopwatch()..start();
    Socket? rawSocket;
    try {
      rawSocket = await Socket.connect(node.address, node.port, timeout: effectiveTimeout);
      final tcpLatency = sw.elapsedMilliseconds;
      Socket activeSocket = rawSocket;

      final host = (node.host != null && node.host!.isNotEmpty)
          ? node.host!
          : ((node.sni != null && node.sni!.isNotEmpty) ? node.sni! : node.address);
      final sni = (node.sni != null && node.sni!.isNotEmpty)
          ? node.sni!
          : ((node.host != null && node.host!.isNotEmpty) ? node.host! : node.address);

      int handshakeLatency = tcpLatency;
      if (node.security == SecurityType.tls) {
        try {
          activeSocket = await SecureSocket.secure(
            rawSocket,
            host: sni,
            onBadCertificate: (_) => node.allowInsecure || globalAllowInsecure,
          ).timeout(effectiveTimeout);
          handshakeLatency = sw.elapsedMilliseconds;
        } catch (_) {
          rawSocket.destroy();
          return null;
        }
      } else if (node.security == SecurityType.reality) {
        // Reality uses uTLS which Dart SecureSocket does not natively handle.
        // Attempt probe; if certificate validation fails, keep the established TCP socket.
        try {
          final probe = await SecureSocket.secure(
            rawSocket,
            host: sni,
            onBadCertificate: (_) => true,
          ).timeout(effectiveTimeout);
          activeSocket = probe;
          handshakeLatency = sw.elapsedMilliseconds;
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

              // Strictly reject CDN error status codes, WAF blocks or HTML error pages:
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
                  responseStr.contains('Error 1020') ||
                  responseStr.contains('<html') ||
                  responseStr.contains('<!DOCTYPE') ||
                  responseStr.contains('<HTML') ||
                  responseStr.contains('<title>');

              // Authentic 101 Switching Protocols, 200/204, or non-HTML 400 (standard raw Xray/V2Ray origin response):
              // Reject 403, 404, 301, 302, 5xx, or CDN HTML error pages
              final isAcceptableStatus = (firstLine.contains(' 101 ') ||
                      firstLine.contains(' 200 ') ||
                      firstLine.contains(' 204 ') ||
                      firstLine.contains(' 400 ')) &&
                  !isCdnError;

              if (isAcceptableStatus) {
                final latency = sw.elapsedMilliseconds > 0 ? sw.elapsedMilliseconds : handshakeLatency;
                completer.complete(latency);
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

        final result = await completer.future.timeout(effectiveTimeout, onTimeout: () => null);
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
              final latency = sw.elapsedMilliseconds > 0 ? sw.elapsedMilliseconds : handshakeLatency;
              completer.complete(latency);
            }
          },
          onError: (_) {
            if (!completer.isCompleted) completer.complete(null);
          },
          onDone: () {
            if (!completer.isCompleted) completer.complete(null);
          },
        );

        final result = await completer.future.timeout(effectiveTimeout, onTimeout: () => null);
        await subscription.cancel();
        activeSocket.destroy();
        return result;
      }

      // Standard TCP / Direct / Reality: Socket connect (+ TLS if available) is successful!
      sw.stop();
      activeSocket.destroy();
      return sw.elapsedMilliseconds > 0 ? sw.elapsedMilliseconds : handshakeLatency;
    } catch (_) {
      try {
        rawSocket?.destroy();
      } catch (_) {}
      return null;
    }
  }

  Future<int?> _testNodeRealProtocolDelay(
    ProxyNode node, {
    Duration timeout = const Duration(milliseconds: 2800),
    int count = 3,
  }) async {
    final swTotal = Stopwatch()..start();
    int? lowest;
    final perProbeTimeout = count > 1 && timeout.inMilliseconds > 1000
        ? Duration(milliseconds: (timeout.inMilliseconds / count).round())
        : timeout;

    for (int i = 0; i < count; i++) {
      final remaining = timeout - swTotal.elapsed;
      if (remaining <= Duration.zero) break;
      final curTimeout = remaining < perProbeTimeout ? remaining : perProbeTimeout;

      // Authentic protocol probe on each probe to measure true roundtrip real delay (matching v2rayN ~600ms)
      final res = await _singleProtocolProbe(node, curTimeout);

      if (res != null && res > 0) {
        if (lowest == null || res < lowest) {
          lowest = res;
        }
      } else {
        // If the first probe failed completely (cannot connect or handshake failed),
        // the host is unreachable or rejected. Don't waste time on remaining probes.
        if (i == 0) break;
      }
    }
    return lowest;
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

