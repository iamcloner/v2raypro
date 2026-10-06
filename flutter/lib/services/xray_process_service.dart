import "dart:async";
import "dart:convert";
import "dart:ffi" as ffi;
import "dart:io";
import "../models/proxy_node.dart";
import "../models/log_entry.dart";
import "log_service.dart";

enum EngineState { stopped, starting, running, stopping, error }

class XrayProcessService {
  static final XrayProcessService instance = XrayProcessService._internal();
  XrayProcessService._internal();

  Process? _process;
  EngineState _state = EngineState.stopped;
  EngineState get state => _state;

  File? _currentConfigFile;
  int socksPort = 10999;
  int httpPort = 10888;
  bool isSystemProxySet = false;
  String? lastLog;
  String? lastErrorLog;

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
        "allowInsecure": node.allowInsecure,
      };
      if (node.fingerprint != null && node.fingerprint!.isNotEmpty) {
        tls["fingerprint"] = node.fingerprint;
      }
      if (node.alpn != null && node.alpn!.isNotEmpty) {
        tls["alpn"] = node.alpn;
      }
      streamSettings["tlsSettings"] = tls;
    } else if (node.security == SecurityType.reality) {
      final reality = <String, dynamic>{
        "serverName": node.sni ?? node.host ?? "",
        "publicKey": node.publicKey ?? "",
        "shortId": node.shortId ?? "",
        "spiderX": node.spiderX ?? "/",
      };
      if (node.fingerprint != null && node.fingerprint!.isNotEmpty) {
        reality["fingerprint"] = node.fingerprint;
      }
      streamSettings["realitySettings"] = reality;
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
      };
    } else if (node.network == NetworkType.httpUpgrade) {
      streamSettings["httpUpgradeSettings"] = {
        "path": node.path ?? "/",
        "host": node.host ?? node.sni ?? node.address,
      };
    }

    Map<String, dynamic> outbound;
    if (node.protocol == ProtocolType.vless) {
      outbound = {
        "tag": "proxy",
        "protocol": "vless",
        "settings": {
          "vnext": [
            {
              "address": node.address,
              "port": node.port,
              "users": [
                {"id": node.uuidOrPassword, "encryption": "none", "level": 0}
              ]
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
      outbound = {
        "tag": "proxy",
        "protocol": "shadowsocks",
        "settings": {
          "servers": [
            {
              "address": node.address,
              "port": node.port,
              "method": node.cipher ?? "aes-256-gcm",
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
          "dns": [
            "1.1.1.1",
            "8.8.8.8"
          ],
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

    return {
      "log": {"loglevel": "warning"},
      "dns": {
        "servers": [
          "8.8.8.8",
          "1.1.1.1",
          "https://1.1.1.1/dns-query",
          "localhost"
        ]
      },
      "inbounds": inbounds,
      "outbounds": [
        outbound,
        {"tag": "dns-out", "protocol": "dns"},
        {"tag": "direct", "protocol": "freedom"},
        {"tag": "block", "protocol": "blackhole"}
      ],
      "routing": {
        "domainStrategy": "IPIfNonMatch",
        "rules": [
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
      LogService.instance.add("Xray core started successfully.", level: LogLevel.info, source: "system");
      return true;
    } catch (e) {
      _state = EngineState.error;
      LogService.instance.add("Failed to start Xray process: $e", level: LogLevel.error, source: "system");
      return false;
    }
  }

  Future<void> stop() async {
    _state = EngineState.stopping;
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

  /// Direct socket / TLS latency test to measure real ping
  Future<int?> testNodeLatency(ProxyNode node, {Duration timeout = const Duration(seconds: 4)}) async {
    final sw = Stopwatch()..start();
    try {
      final socket = await Socket.connect(node.address, node.port, timeout: timeout);
      if (node.security == SecurityType.tls || node.security == SecurityType.reality) {
        final secureSocket = await SecureSocket.secure(
          socket,
          host: node.sni ?? node.host ?? node.address,
          onBadCertificate: (_) => true,
        ).timeout(timeout);
        sw.stop();
        await secureSocket.close();
        return sw.elapsedMilliseconds;
      } else {
        sw.stop();
        await socket.close();
        return sw.elapsedMilliseconds;
      }
    } catch (_) {
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

