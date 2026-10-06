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

  Map<String, dynamic> generateXrayConfig(ProxyNode node, {bool enableTun = false}) {
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
        "settings": {"auth": "noauth", "udp": true},
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
          "mtu": 1500
        },
        "sniffing": {"enabled": true, "destOverride": ["http", "tls"]}
      });
    }

    return {
      "log": {"loglevel": "warning"},
      "dns": {
        "servers": [
          "https+local://1.1.1.1/dns-query",
          "8.8.8.8",
          "1.1.1.1",
          "localhost"
        ]
      },
      "inbounds": inbounds,
      "outbounds": [
        outbound,
        {"tag": "direct", "protocol": "freedom"},
        {"tag": "block", "protocol": "blackhole"}
      ],
      "routing": {
        "domainStrategy": "IPIfNonMatch",
        "rules": [
          {"type": "field", "outboundTag": "direct", "ip": ["geoip:private"]}
        ]
      }
    };
  }

  Future<bool> start(ProxyNode node, {bool enableTun = false, bool setSysProxy = false}) async {
    if (_state == EngineState.running) {
      await stop();
    }

    _state = EngineState.starting;
    LogService.instance.add("Initializing Xray core for node: ${node.name} (${node.address}:${node.port}) [TUN: $enableTun, SysProxy: $setSysProxy]", level: LogLevel.info, source: "system");

    final binaryPath = _findXrayBinary();
    if (binaryPath == null) {
      _state = EngineState.error;
      LogService.instance.add("Xray binary not found. Unable to start core.", level: LogLevel.error, source: "system");
      return false;
    }

    try {
      final configJson = generateXrayConfig(node, enableTun: enableTun);
      final tmpDir = Directory.systemTemp;
      _currentConfigFile = File("${tmpDir.path}/v2raypro_active_config.json");
      await _currentConfigFile!.writeAsString(jsonEncode(configJson));

      _process = await Process.start(
        binaryPath,
        ["run", "-c", _currentConfigFile!.path],
        mode: ProcessStartMode.normal,
      );

      _process!.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
        lastLog = line;
        LogService.instance.addFromRawLine(line, source: "xray");
      });
      _process!.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
        lastErrorLog = line;
        LogService.instance.addFromRawLine(line, source: "xray");
      });

      _process!.exitCode.then((code) {
        LogService.instance.add("Xray core exited with code $code", level: code == 0 ? LogLevel.info : LogLevel.warning, source: "xray");
        if (_state == EngineState.running) {
          _state = EngineState.stopped;
        }
      });

      // Allow 300ms to verify process did not immediately crash
      await Future.delayed(const Duration(milliseconds: 300));
      if (_state == EngineState.stopped) {
        _state = EngineState.error;
        LogService.instance.add("Xray core exited immediately after launch. Check configuration.", level: LogLevel.error, source: "system");
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
    _process?.kill();
    _process = null;
    try {
      if (_currentConfigFile != null && await _currentConfigFile!.exists()) {
        await _currentConfigFile!.delete();
      }
    } catch (_) {}
    _state = EngineState.stopped;
    LogService.instance.add("Xray core stopped.", level: LogLevel.info, source: "system");
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
}

