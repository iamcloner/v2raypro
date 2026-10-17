import "dart:async";
import "dart:convert";
import "dart:io";
import "package:flutter/services.dart";
import "package:path_provider/path_provider.dart";
import "../models/service_models.dart";
import "../models/traffic_stats.dart";
import "../models/proxy_node.dart";
import "../models/routing_rule.dart";
import "../models/log_entry.dart";
import "tun_service.dart";
import "log_service.dart";

import "storage_service.dart";

/// Dedicated Core Service implementing the exact diagram specification:
/// Manages proxy/socks server lifecycle, handles Status (connect, change, disconnect),
/// controls TunService when Mode == tun, and streams connection duration and upload/download usage.
class CoreService {
  static final CoreService instance = CoreService._internal();
  CoreService._internal() {
    initSettings();
  }

  CoreState _state = CoreState.disconnected;
  CoreState get state => _state;
  final _stateStreamController = StreamController<CoreState>.broadcast();
  Stream<CoreState> get stateStream => _stateStreamController.stream;

  // Active configuration & parameters
  CoreMode _mode = CoreMode.proxy;
  CoreMode get mode => _mode;

  int _httpPort = 10888;
  int get httpPort => _httpPort;
  set httpPort(int port) => _httpPort = port;

  int _socksPort = 10999;
  int get socksPort => _socksPort;
  set socksPort(int port) => _socksPort = port;

  Future<void> initSettings() async {
    try {
      _httpPort = await StorageService.instance.loadHttpPort();
      _socksPort = await StorageService.instance.loadSocksPort();
      _allowLan = await StorageService.instance.loadAllowLan();
      _allowInsecure = await StorageService.instance.loadGlobalAllowInsecure();
      _enableMux = await StorageService.instance.loadGlobalEnableMux();
    } catch (_) {}
  }

  /// Checks whether a TCP port can be bound on loopback
  static Future<bool> isPortAvailable(int port) async {
    try {
      final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
      await s.close();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Finds an available port starting from preferredPort
  static Future<int> findAvailablePort(int preferredPort, {int maxAttempts = 20}) async {
    for (int i = 0; i < maxAttempts; i++) {
      final candidate = preferredPort + i;
      if (await isPortAvailable(candidate)) {
        return candidate;
      }
    }
    try {
      final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = s.port;
      await s.close();
      return port;
    } catch (_) {
      return preferredPort;
    }
  }

  int _apiPort = 10085;
  int get apiPort => _apiPort;

  bool _enableUdp = true;
  bool get enableUdp => _enableUdp;
  set enableUdp(bool v) => _enableUdp = v;

  bool _enableMux = false;
  bool get enableMux => _enableMux;
  set enableMux(bool v) => _enableMux = v;

  bool _allowInsecure = false;
  bool get allowInsecure => _allowInsecure;
  set allowInsecure(bool v) => _allowInsecure = v;

  bool _allowLan = false;
  bool get allowLan => _allowLan;
  set allowLan(bool v) => _allowLan = v;

  List<String> dnsServers = const ["1.1.1.1", "1.0.0.1", "https://1.1.1.1/dns-query"];
  List<RoutingRule> routingRules = [];
  AppRoutingMode appRoutingMode = AppRoutingMode.exclusive;

  CoreConfig? _activeConfig;
  CoreConfig? get activeConfig => _activeConfig;

  Process? _coreProcess;
  File? _activeConfigFile;

  // Connection duration stream
  DateTime? _connectedAt;
  DateTime? get connectedAt => _connectedAt;
  Timer? _durationTimer;
  final _durationStreamController = StreamController<Duration>.broadcast();
  Stream<Duration> get durationStream => _durationStreamController.stream;

  // Traffic usage stream
  Timer? _trafficTimer;
  final _trafficStreamController = StreamController<TrafficStats>.broadcast();
  Stream<TrafficStats> get trafficStream => _trafficStreamController.stream;
  TrafficStats _currentTrafficStats = const TrafficStats();
  TrafficStats get currentTrafficStats => _currentTrafficStats;

  // Platform specific paths
  String? _androidBinaryPath;
  Directory? _androidAssetDir;

  // ========================================================
  // Main Unified Action Entrypoint
  // ========================================================

  /// Executes action based on Status: connect, change, or disconnect
  Future<bool> execute({
    required CoreStatus status,
    required CoreMode mode,
    required CoreConfig config,
    int? httpPort,
    int? socksPort,
    bool? enableUdp,
    bool? enableMux,
    bool? allowInsecure,
    bool? allowLan,
  }) async {
    _mode = mode;
    if (httpPort != null) _httpPort = httpPort;
    if (socksPort != null) _socksPort = socksPort;
    if (enableUdp != null) _enableUdp = enableUdp;
    if (enableMux != null) _enableMux = enableMux;
    if (allowInsecure != null) _allowInsecure = allowInsecure;
    if (allowLan != null) _allowLan = allowLan;

    switch (status) {
      case CoreStatus.connect:
        return await connect(
          mode: mode,
          config: config,
          httpPort: _httpPort,
          socksPort: _socksPort,
          enableUdp: _enableUdp,
          enableMux: _enableMux,
          allowInsecure: _allowInsecure,
          allowLan: _allowLan,
        );
      case CoreStatus.change:
        return await changeConfig(config);
      case CoreStatus.disconnect:
        await disconnect();
        return true;
    }
  }

  // ========================================================
  // Branch 1: Status == connect
  // ========================================================

  /// Connect to config and listen proxy/socks server.
  /// If Mode == tun -> triggers TunService.
  /// Outputs: connection duration and upload_usage / download_usage.
  Future<bool> connect({
    required CoreMode mode,
    required CoreConfig config,
    required int httpPort,
    required int socksPort,
    bool enableUdp = true,
    bool enableMux = false,
    bool allowInsecure = false,
    bool allowLan = false,
  }) async {
    // 1. Disconnect any existing core
    await _stopCoreProcess();

    if (Platform.isWindows) {
      try {
        Process.runSync("taskkill", ["/F", "/IM", "xray.exe"]);
      } catch (_) {}
    }

    int safeSocksPort = socksPort;
    int safeHttpPort = httpPort;

    if (Platform.isWindows) {
      if (!await isPortAvailable(safeSocksPort)) {
        final newSocks = await findAvailablePort(safeSocksPort);
        LogService.instance.add("Port $safeSocksPort is unavailable; switched to port $newSocks for SOCKS.", level: LogLevel.warning, source: "core");
        safeSocksPort = newSocks;
      }

      if (!await isPortAvailable(safeHttpPort) || safeHttpPort == safeSocksPort) {
        final base = safeHttpPort == safeSocksPort ? safeSocksPort + 1 : safeHttpPort;
        final newHttp = await findAvailablePort(base);
        LogService.instance.add("Port $safeHttpPort is unavailable; switched to port $newHttp for HTTP.", level: LogLevel.warning, source: "core");
        safeHttpPort = newHttp;
      }
    }

    _mode = mode;
    _httpPort = safeHttpPort;
    _socksPort = safeSocksPort;
    _enableUdp = enableUdp;
    _enableMux = enableMux;
    _allowInsecure = allowInsecure;
    _allowLan = allowLan;
    _activeConfig = config;

    _setState(CoreState.connecting);
    LogService.instance.add("CoreService: Connecting to config (Mode: ${mode.name}, SOCKS: $_socksPort, HTTP: $_httpPort)...", level: LogLevel.info, source: "core");

    final binaryPath = _findCoreBinary(config.type);
    if (binaryPath == null) {
      _setState(CoreState.error);
      LogService.instance.add("CoreService: Executable for ${config.type.name} not found.", level: LogLevel.error, source: "core");
      return false;
    }

    try {
      // 2. Build full runtime config JSON
      final runtimeConfig = _buildRuntimeConfig(
        config: config,
        enableTun: (mode == CoreMode.tun),
        enableUdp: enableUdp,
        enableMux: enableMux,
        allowInsecure: allowInsecure,
        allowLan: allowLan,
      );

      final tmpDir = Platform.isAndroid && _androidAssetDir != null
          ? _androidAssetDir!
          : Directory.systemTemp;
      _activeConfigFile = File("${tmpDir.path}/v2raypro_active_config.json");
      await _activeConfigFile!.writeAsString(jsonEncode(runtimeConfig));

      final workDir = _getWorkingDirectory(binaryPath);
      final env = _getCoreEnvironment();

      // Start core process
      _coreProcess = await Process.start(
        binaryPath,
        ["run", "-c", _activeConfigFile!.path],
        workingDirectory: workDir,
        environment: env,
        mode: ProcessStartMode.normal,
      );

      bool earlyCrash = false;
      _coreProcess!.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
        LogService.instance.addFromRawLine(line, source: config.type.name);
      }, onError: (_) {});
      _coreProcess!.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
        LogService.instance.addFromRawLine(line, source: config.type.name);
      }, onError: (_) {});

      _coreProcess!.exitCode.then((code) {
        if (_state == CoreState.connecting) {
          earlyCrash = true;
          _setState(CoreState.error);
        } else if (_state == CoreState.connected) {
          _setState(CoreState.disconnected);
        }
        LogService.instance.add("${config.type.name} core exited with code $code", level: code == 0 ? LogLevel.info : LogLevel.error, source: "core");
      });

      await Future.delayed(const Duration(milliseconds: 350));
      if (earlyCrash || _state == CoreState.error) {
        await _stopCoreProcess();
        return false;
      }

      // 3. If Mode == tun -> Trigger TunService
      if (mode == CoreMode.tun) {
        final tunOk = await TunService.instance.setStatus(
          status: TunStatus.connect,
          socksPort: _socksPort,
          httpPort: _httpPort,
          xrayBinary: binaryPath,
          configPath: _activeConfigFile?.path,
          assetDir: _androidAssetDir?.path,
        );

        if (!tunOk) {
          LogService.instance.add("CoreService: TunService failed to activate.", level: LogLevel.error, source: "core");
          await _stopCoreProcess();
          _setState(CoreState.error);
          return false;
        }
      }

      _setState(CoreState.connected);
      _startDurationTimer();
      _startTrafficPolling();
      LogService.instance.add("CoreService: Connected successfully.", level: LogLevel.info, source: "core");
      return true;
    } catch (e) {
      LogService.instance.add("CoreService: Failed to connect: $e", level: LogLevel.error, source: "core");
      await _stopCoreProcess();
      _setState(CoreState.error);
      return false;
    }
  }

  // ========================================================
  // Branch 2: Status == change
  // ========================================================

  /// Disconnect config and stop proxy server, then connect to new config.
  /// Outputs: connection duration and upload_usage / download_usage.
  Future<bool> changeConfig(CoreConfig newConfig) async {
    LogService.instance.add("CoreService: Changing active configuration...", level: LogLevel.info, source: "core");
    _setState(CoreState.connecting);

    // 1. Disconnect config and stop proxy server
    await _stopCoreProcess();

    // 2. Connect to new config and listen proxy/socks server
    return await connect(
      mode: _mode,
      config: newConfig,
      httpPort: _httpPort,
      socksPort: _socksPort,
      enableUdp: _enableUdp,
      enableMux: _enableMux,
      allowInsecure: _allowInsecure,
      allowLan: _allowLan,
    );
  }

  // ========================================================
  // Branch 3: Status == disconnect
  // ========================================================

  /// Disconnect config and stop proxy server.
  /// If Mode == tun -> triggers TunService (disconnect).
  Future<void> disconnect() async {
    _setState(CoreState.disconnecting);
    LogService.instance.add("CoreService: Disconnecting...", level: LogLevel.info, source: "core");

    // 1. If Mode == tun -> Trigger TunService disconnect
    if (_mode == CoreMode.tun) {
      await TunService.instance.setStatus(
        status: TunStatus.disconnect,
        socksPort: _socksPort,
        httpPort: _httpPort,
      );
    }

    // 2. Disconnect config and stop proxy server
    await _stopCoreProcess();

    _stopDurationTimer();
    _stopTrafficPolling();
    _activeConfig = null;
    _setState(CoreState.disconnected);
    LogService.instance.add("CoreService: Disconnected.", level: LogLevel.info, source: "core");
  }

  // ========================================================
  // Duration & Traffic Streams
  // ========================================================

  void _startDurationTimer() {
    _durationTimer?.cancel();
    _connectedAt = DateTime.now();
    _durationStreamController.add(Duration.zero);

    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_connectedAt != null) {
        final elapsed = DateTime.now().difference(_connectedAt!);
        _durationStreamController.add(elapsed);
      }
    });
  }

  void _stopDurationTimer() {
    _durationTimer?.cancel();
    _durationTimer = null;
    _connectedAt = null;
    _durationStreamController.add(Duration.zero);
  }

  void _startTrafficPolling() {
    _trafficTimer?.cancel();
    _currentTrafficStats = const TrafficStats();
    _trafficStreamController.add(_currentTrafficStats);

    _trafficTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (_state != CoreState.connected) return;
      try {
        final client = HttpClient();
        client.connectionTimeout = const Duration(milliseconds: 700);
        final uri = Uri.parse("http://127.0.0.1:$_apiPort/debug/vars");
        final req = await client.getUrl(uri).timeout(const Duration(milliseconds: 700));
        final resp = await req.close().timeout(const Duration(milliseconds: 700));
        if (resp.statusCode == 200) {
          final body = await resp.transform(utf8.decoder).join();
          final parsed = jsonDecode(body);
          if (parsed is Map<String, dynamic> && parsed['stats'] is Map<String, dynamic>) {
            final statList = parsed['stats']['stat'] as List? ?? [];
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
    _currentTrafficStats = const TrafficStats();
    _trafficStreamController.add(_currentTrafficStats);
  }

  void _setState(CoreState s) {
    _state = s;
    _stateStreamController.add(s);
  }

  Future<void> _stopCoreProcess() async {
    if (_coreProcess != null) {
      final pid = _coreProcess!.pid;
      _coreProcess!.kill();
      _coreProcess = null;
      if (Platform.isWindows) {
        try {
          Process.runSync("taskkill", ["/F", "/T", "/PID", "$pid"]);
        } catch (_) {}
      }
    }
    try {
      if (_activeConfigFile != null && await _activeConfigFile!.exists()) {
        await _activeConfigFile!.delete();
      }
    } catch (_) {}
  }

  // ========================================================
  // Helpers: Config Assembly & Binary Resolution
  // ========================================================

  Map<String, dynamic> _buildRuntimeConfig({
    required CoreConfig config,
    required bool enableTun,
    required bool enableUdp,
    required bool enableMux,
    required bool allowInsecure,
    required bool allowLan,
  }) {
    final raw = Map<String, dynamic>.from(config.rawJson);
    final listenAddr = allowLan ? "0.0.0.0" : "127.0.0.1";

    final inbounds = <Map<String, dynamic>>[
      {
        "tag": "socks-in",
        "port": _socksPort,
        "listen": listenAddr,
        "protocol": "socks",
        "settings": {"auth": "noauth", "udp": enableUdp},
        "sniffing": {"enabled": true, "destOverride": ["http", "tls"]}
      },
      {
        "tag": "http-in",
        "port": _httpPort,
        "listen": listenAddr,
        "protocol": "http",
        "sniffing": {"enabled": true, "destOverride": ["http", "tls"]}
      },
      {
        "tag": "api",
        "port": _apiPort,
        "listen": "127.0.0.1",
        "protocol": "dokodemo-door",
        "settings": {"address": "127.0.0.1"}
      }
    ];

    if (enableTun) {
      inbounds.add({
        "tag": "tun-in",
        "protocol": "tun",
        "settings": {
          "name": "v2raypro-tun",
          "mtu": 1500,
          "gateway": ["172.19.0.1/30"],
          "dns": ["1.1.1.1", "8.8.8.8"],
          "autoSystemRoutingTable": ["0.0.0.0/0", "0.0.0.0/1", "128.0.0.0/1"],
          "autoOutboundsInterface": "auto"
        },
        "sniffing": {"enabled": true, "destOverride": ["http", "tls", "quic"]}
      });
    }

    final outbounds = (raw["outbounds"] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];

    if (enableMux && outbounds.isNotEmpty) {
      outbounds[0]["mux"] = {"enabled": true, "concurrency": 8};
    }

    return {
      "log": {"loglevel": Platform.isAndroid ? "none" : "warning"},
      "api": {"tag": "api", "services": ["StatsService"]},
      "stats": {},
      "policy": {
        "levels": {"0": {"statsUserUplink": true, "statsUserDownlink": true}},
        "system": {
          "statsInboundUplink": true,
          "statsInboundDownlink": true,
          "statsOutboundUplink": true,
          "statsOutboundDownlink": true
        }
      },
      "dns": {
        "servers": dnsServers.isNotEmpty ? dnsServers : ["1.1.1.1", "8.8.8.8", "localhost"]
      },
      "inbounds": inbounds,
      "outbounds": outbounds.isNotEmpty
          ? outbounds
          : [
              {"tag": "proxy", "protocol": "freedom"},
              {"tag": "direct", "protocol": "freedom"},
              {"tag": "block", "protocol": "blackhole"}
            ],
      "routing": raw["routing"] ?? {
        "domainStrategy": "IPIfNonMatch",
        "rules": [
          {"type": "field", "inboundTag": ["api"], "outboundTag": "api"},
          {"type": "field", "outboundTag": "direct", "ip": ["geoip:private"]}
        ]
      }
    };
  }

  String? _findCoreBinary(CoreType type) {
    if (Platform.isAndroid) {
      if (_androidBinaryPath != null && File(_androidBinaryPath!).existsSync()) {
        return _androidBinaryPath;
      }
      return null;
    }

    final exeName = type == CoreType.singbox ? "sing-box.exe" : "xray.exe";
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final candidates = [
      "$exeDir/xray/$exeName",
      "xray/$exeName",
      exeName,
      "assets/bin/$exeName",
      "$exeDir/$exeName",
      "$exeDir/assets/bin/$exeName",
      "$exeDir/data/flutter_assets/assets/bin/$exeName",
      "flutter/assets/bin/$exeName",
    ];

    for (final path in candidates) {
      if (File(path).existsSync()) {
        return path;
      }
    }
    return null;
  }

  String _getWorkingDirectory(String binaryPath) {
    if (Platform.isAndroid && _androidAssetDir != null) {
      return _androidAssetDir!.path;
    }
    return File(binaryPath).parent.path;
  }

  Map<String, String>? _getCoreEnvironment() {
    if (Platform.isAndroid && _androidAssetDir != null) {
      return {"XRAY_LOCATION_ASSET": _androidAssetDir!.path};
    }
    return null;
  }

  Future<void> initAndroid() async {
    if (!Platform.isAndroid) return;
    try {
      const channel = MethodChannel('com.v2raypro.app/native');
      final path = await channel.invokeMethod<String>('getXrayBinary');
      if (path != null && File(path).existsSync()) {
        _androidBinaryPath = path;
      }
    } catch (_) {}

    try {
      final appSupport = await getApplicationSupportDirectory();
      final xrayDir = Directory('${appSupport.path}/xray');
      if (!xrayDir.existsSync()) {
        await xrayDir.create(recursive: true);
      }
      _androidAssetDir = xrayDir;
    } catch (_) {}
  }
}
