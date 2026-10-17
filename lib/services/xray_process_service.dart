import "dart:async";
import "dart:io";
import "package:flutter/services.dart";
import "../models/proxy_node.dart";
import "../models/routing_rule.dart";
import "../models/traffic_stats.dart";
import "../models/service_models.dart";
import "../utils/config_generator.dart";
import "core_service.dart";
import "tun_service.dart";
import "ping_service.dart";
import "log_service.dart";

/// Result of testing a node (legacy wrapper for PingResult)
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

  factory NodeTestResult.fromPingResult(PingResult res) {
    return NodeTestResult(
      latencyMs: res.latencyMs,
      countryCode: res.countryCode,
      country: res.countryName,
      exitIp: res.exitIp,
    );
  }

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

/// Architecture Facade & Bridge:
/// Delegates all operations to the new three dedicated services:
/// - CoreService (Process lifecycle, connection duration, upload/download usage)
/// - TunService (TUN interface, Wintun, Android VPN service)
/// - PingService (realDelay, ipTest, ICMP/TCP/UDP)
class XrayProcessService {
  static final XrayProcessService instance = XrayProcessService._internal();
  XrayProcessService._internal();

  CoreService get core => CoreService.instance;
  TunService get tun => TunService.instance;
  PingService get ping => PingService.instance;

  EngineState get state {
    switch (core.state) {
      case CoreState.disconnected:
        return EngineState.stopped;
      case CoreState.connecting:
        return EngineState.starting;
      case CoreState.connected:
        return EngineState.running;
      case CoreState.disconnecting:
        return EngineState.stopping;
      case CoreState.error:
        return EngineState.error;
    }
  }

  ProxyNode? _activeRunningNode;
  ProxyNode? get activeRunningNode => _activeRunningNode;

  int get socksPort => core.socksPort;
  set socksPort(int p) => core.socksPort = p;

  int get httpPort => core.httpPort;
  set httpPort(int p) => core.httpPort = p;

  int get apiPort => core.apiPort;

  List<String> get dnsServers => core.dnsServers;
  set dnsServers(List<String> d) => core.dnsServers = d;

  bool get isSystemProxySet => tun.isSystemProxySet;

  bool get globalAllowInsecure => core.allowInsecure;
  set globalAllowInsecure(bool v) => core.allowInsecure = v;

  bool get globalEnableMux => core.enableMux;
  set globalEnableMux(bool v) => core.enableMux = v;

  bool get globalAllowLan => core.allowLan;
  set globalAllowLan(bool v) => core.allowLan = v;

  List<RoutingRule> get routingRules => core.routingRules;
  set routingRules(List<RoutingRule> r) => core.routingRules = r;

  AppRoutingMode get appRoutingMode => core.appRoutingMode;
  set appRoutingMode(AppRoutingMode m) => core.appRoutingMode = m;

  Stream<TrafficStats> get trafficStream => core.trafficStream;
  TrafficStats get currentTrafficStats => core.currentTrafficStats;

  VoidCallback? get onAndroidNotificationDisconnect => tun.onNotificationDisconnect;
  set onAndroidNotificationDisconnect(VoidCallback? cb) => tun.onNotificationDisconnect = cb;

  Directory? get androidAssetDir => null;

  Future<void> initAndroid() async {
    await core.initAndroid();
  }

  bool isRunningAsAdmin() => tun.isRunningAsAdmin();

  Future<void> restartAsAdmin() => tun.restartAsAdmin();

  void setWindowsSystemProxy(bool enable, {int? port}) {
    tun.setWindowsSystemProxy(enable, port: port);
  }

  Future<bool> isAndroidVpnRunning() => tun.isVpnActive();

  Future<bool> prepareAndroidVpn() => tun.prepareAndroidVpn();

  Future<void> syncAndroidLogs() => tun.syncAndroidLogs();

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

  String? findXrayBinarySync() {
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
    for (final p in candidates) {
      if (File(p).existsSync()) return p;
    }
    return null;
  }

  bool isCoreAvailable() {
    if (Platform.isAndroid) return true;
    return findXrayBinarySync() != null;
  }

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

  Map<String, dynamic> generateXrayConfig(
    ProxyNode node, {
    bool enableTun = false,
    bool enableUdp = true,
    bool allowLan = false,
  }) {
    return ConfigGenerator.generateXrayConfig(
      node,
      socksPort: socksPort,
      httpPort: httpPort,
      apiPort: apiPort,
      enableTun: enableTun,
      enableUdp: enableUdp,
      enableMux: globalEnableMux,
      allowInsecure: globalAllowInsecure,
      allowLan: allowLan || globalAllowLan,
      dnsServers: dnsServers,
      routingRules: routingRules,
      appRoutingMode: appRoutingMode,
    );
  }

  Future<bool> start(
    ProxyNode node, {
    bool enableTun = false,
    bool setSysProxy = false,
    bool enableUdp = true,
    bool allowLan = false,
    String? notificationTitle,
    String? disconnectText,
    String? configName,
    int? httpPort,
    int? socksPort,
  }) async {
    final effectiveHttpPort = httpPort ?? this.httpPort;
    final effectiveSocksPort = socksPort ?? this.socksPort;

    _activeRunningNode = node;
    final config = CoreConfig.fromNode(
      node,
      type: CoreType.xray,
      socksPort: effectiveSocksPort,
      httpPort: effectiveHttpPort,
      enableTun: enableTun,
      enableUdp: enableUdp,
      enableMux: globalEnableMux,
      allowInsecure: globalAllowInsecure,
      allowLan: allowLan || globalAllowLan,
    );

    final ok = await core.connect(
      mode: enableTun ? CoreMode.tun : CoreMode.proxy,
      config: config,
      httpPort: effectiveHttpPort,
      socksPort: effectiveSocksPort,
      enableUdp: enableUdp,
      enableMux: globalEnableMux,
      allowInsecure: globalAllowInsecure,
      allowLan: allowLan || globalAllowLan,
      notificationTitle: notificationTitle,
      disconnectText: disconnectText,
      configName: configName ?? node.name,
    );

    if (ok && setSysProxy && Platform.isWindows) {
      tun.setWindowsSystemProxy(true, port: core.httpPort);
    }

    return ok;
  }

  Future<void> stop() async {
    _activeRunningNode = null;
    await core.disconnect();
  }

  void cleanupSystemAndXray({bool force = false}) {
    tun.setWindowsSystemProxy(false);
    if (Platform.isWindows) {
      try {
        Process.runSync("taskkill", ["/F", "/IM", "xray.exe"]);
      } catch (_) {}
    }
  }

  // ========================================================
  // Ping & Real Delay Delegations
  // ========================================================

  Future<PingResult> pingNode(
    ProxyNode node, {
    PingMode mode = PingMode.realDelay,
    PingType type = PingType.tcp,
    bool showCountry = true,
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final cfg = CoreConfig.fromNode(node, type: CoreType.xray);
    return await ping.ping(
      config: cfg,
      pingMode: mode,
      pingType: type,
      showCountry: showCountry,
      timeout: timeout,
      xrayBinaryPath: findXrayBinarySync(),
    );
  }

  Future<NodeTestResult> testNodeRealDelay(
    ProxyNode node, {
    Duration timeout = const Duration(seconds: 4),
    bool isTurbo = false,
  }) async {
    final effectiveTimeout = isTurbo ? const Duration(milliseconds: 1500) : timeout;

    // Ping must directly test node endpoint and NOT pass through running VPN/proxy
    final res = await pingNode(
      node,
      mode: PingMode.realDelay,
      type: PingType.tcp,
      showCountry: true,
      timeout: effectiveTimeout,
    );
    return NodeTestResult.fromPingResult(res);
  }

  Future<int?> tcpPing(
    String host,
    int port, {
    int count = 1,
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final dummyNode = ProxyNode(
      id: "probe",
      name: "probe",
      address: host,
      port: port,
      protocol: ProtocolType.vless,
      uuidOrPassword: "dummy",
    );
    final cfg = CoreConfig.fromNode(dummyNode);
    int? bestLatency;
    for (int i = 0; i < count; i++) {
      final res = await ping.ping(
        config: cfg,
        pingMode: PingMode.ipTest,
        pingType: PingType.tcp,
        timeout: timeout,
      );
      if (res.latencyMs != null) {
        if (bestLatency == null || res.latencyMs! < bestLatency) {
          bestLatency = res.latencyMs;
        }
      }
    }
    return bestLatency;
  }

  Future<int?> testNodeLatency(ProxyNode node, {Duration timeout = const Duration(seconds: 3)}) async {
    return await ping.pingProtocolDelay(node, timeout: timeout, count: 1);
  }

  Future<Map<String, NodeTestResult>> testNodesBatchRealProxy(
    List<ProxyNode> nodes, {
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final results = <String, NodeTestResult>{};
    await Future.wait(nodes.map((node) async {
      final res = await testNodeRealDelay(node, timeout: timeout);
      results[node.id] = res;
    }));
    return results;
  }
}
