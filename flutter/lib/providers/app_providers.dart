import "dart:async";
import "dart:convert";
import "dart:io";
import "dart:math";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "../models/proxy_node.dart";
import "../models/scan_result.dart";
import "../models/subscription_item.dart";
import "../models/dns_settings.dart";
import "../models/log_entry.dart";
import "../models/outbound_info.dart";
import "../models/traffic_stats.dart";
import "../services/cdn_scanner_service.dart";
import "../services/cloudflare_scanner_service.dart";
import "../services/log_service.dart";
import "../services/storage_service.dart";
import "../services/tray_service.dart";
import "../services/xray_process_service.dart";
import "../services/free_configs_service.dart";
import "../utils/config_parser.dart";
import "package:uuid/uuid.dart";

enum ConnectionStateEnum { disconnected, connecting, connected, disconnecting, error }

class ConnectionStatusNotifier extends StateNotifier<ConnectionStateEnum> {
  final Ref ref;
  ConnectionStatusNotifier(this.ref) : super(ConnectionStateEnum.disconnected);

  void setConnected() {
    ref.read(connectedAtProvider.notifier).state = DateTime.now();
    state = ConnectionStateEnum.connected;
    ref.read(outboundInfoProvider.notifier).fetch();
    _testPing();
    AppTrayService.instance.updateTrayMenu();

    if (ref.read(autoEnableSysProxyOnConnectProvider) && !ref.read(isSystemProxyEnabledProvider)) {
      ref.read(isSystemProxyEnabledProvider.notifier).toggle(true);
    }
    if (ref.read(autoEnableTunOnConnectProvider) && !ref.read(isTunEnabledProvider)) {
      ref.read(isTunEnabledProvider.notifier).toggle(true);
    }
  }

  void setDisconnected() {
    ref.read(connectedAtProvider.notifier).state = null;
    ref.read(outboundInfoProvider.notifier).reset();
    ref.read(trafficStatsProvider.notifier).reset();
    state = ConnectionStateEnum.disconnected;
    AppTrayService.instance.updateTrayMenu();
  }

  Future<void> _testPing() async {
    final nodes = ref.read(nodesProvider);
    if (nodes.isEmpty) return;
    final active = nodes.firstWhere((n) => n.isActive, orElse: () => nodes.first);
    final lat = await XrayProcessService.instance.testNodeLatency(active);
    ref.read(nodesProvider.notifier).updateLatency(active.id, lat);
  }

  Future<void> connect([ProxyNode? targetNode]) async {
    final nodes = ref.read(nodesProvider);
    if (nodes.isEmpty) {
      state = ConnectionStateEnum.error;
      return;
    }

    final activeNode = targetNode ?? nodes.firstWhere((n) => n.isActive, orElse: () => nodes.first);
    final isTun = ref.read(isTunEnabledProvider) || ref.read(autoEnableTunOnConnectProvider);
    final isSysProxy = ref.read(isSystemProxyEnabledProvider) || ref.read(autoEnableSysProxyOnConnectProvider);
    final enableUdp = ref.read(enableUdpProvider);

    if (isTun && !XrayProcessService.instance.isRunningAsAdmin()) {
      LogService.instance.add("TUN Mode requires Administrator privileges on Windows. Please restart application as Administrator.", level: LogLevel.warning, source: "system");
      state = ConnectionStateEnum.error;
      return;
    }

    state = ConnectionStateEnum.connecting;
    final ok = await XrayProcessService.instance.start(
      activeNode,
      enableTun: isTun,
      setSysProxy: isSysProxy,
      enableUdp: enableUdp,
    );
    if (ok) {
      setConnected();
    } else {
      state = ConnectionStateEnum.error;
    }
  }

  Future<void> reconnectWithUpdatedSettings() async {
    if (state == ConnectionStateEnum.connected) {
      final nodes = ref.read(nodesProvider);
      if (nodes.isEmpty) return;
      final active = nodes.firstWhere((n) => n.isActive, orElse: () => nodes.first);
      state = ConnectionStateEnum.connecting;
      await XrayProcessService.instance.stop();
      await connect(active);
    }
  }

  Future<void> toggleConnect() async {
    if (state == ConnectionStateEnum.disconnected || state == ConnectionStateEnum.error) {
      await connect();
    } else if (state == ConnectionStateEnum.connected) {
      state = ConnectionStateEnum.disconnecting;
      await XrayProcessService.instance.stop();
      setDisconnected();
    }
  }
}

final connectionStatusProvider = StateNotifierProvider<ConnectionStatusNotifier, ConnectionStateEnum>((ref) {
  return ConnectionStatusNotifier(ref);
});

class TrafficStatsNotifier extends StateNotifier<TrafficStats> {
  StreamSubscription<TrafficStats>? _sub;

  TrafficStatsNotifier() : super(const TrafficStats()) {
    _sub = XrayProcessService.instance.trafficStream.listen((stats) {
      state = stats;
    });
  }

  void update(TrafficStats stats) {
    state = stats;
  }

  void reset() {
    state = const TrafficStats();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

final trafficStatsProvider = StateNotifierProvider<TrafficStatsNotifier, TrafficStats>((ref) {
  return TrafficStatsNotifier();
});

class SystemProxyNotifier extends StateNotifier<bool> {
  SystemProxyNotifier() : super(false) {
    _init();
  }

  Future<void> _init() async {
    state = await StorageService.instance.loadSystemProxyEnabled();
  }

  void toggle(bool enable) {
    state = enable;
    StorageService.instance.saveSystemProxyEnabled(enable);
    XrayProcessService.instance.setWindowsSystemProxy(enable);
  }
}

final isSystemProxyEnabledProvider = StateNotifierProvider<SystemProxyNotifier, bool>((ref) {
  return SystemProxyNotifier();
});

class TunNotifier extends StateNotifier<bool> {
  TunNotifier() : super(false) {
    _init();
  }

  Future<void> _init() async {
    state = await StorageService.instance.loadTunEnabled();
  }

  void toggle(bool enable) {
    state = enable;
    StorageService.instance.saveTunEnabled(enable);
  }
}

final isTunEnabledProvider = StateNotifierProvider<TunNotifier, bool>((ref) {
  return TunNotifier();
});

// Production persistent nodes notifier
class NodesNotifier extends StateNotifier<List<ProxyNode>> {
  NodesNotifier() : super([]) {
    _init();
  }

  Future<void> _init() async {
    final saved = await StorageService.instance.loadNodes();
    if (saved.isNotEmpty) {
      final seenIds = <String>{};
      bool hasActive = false;
      final fixed = <ProxyNode>[];
      for (final n in saved) {
        String uniqueId = n.id;
        if (seenIds.contains(uniqueId) || uniqueId.isEmpty) {
          uniqueId = const Uuid().v4();
        }
        seenIds.add(uniqueId);

        bool active = n.isActive;
        if (active) {
          if (hasActive) {
            active = false;
          } else {
            hasActive = true;
          }
        }
        fixed.add(n.copyWith(id: uniqueId, isActive: active));
      }

      if (fixed.isNotEmpty && !hasActive) {
        fixed[0] = fixed[0].copyWith(isActive: true);
      }

      state = fixed;
      _save();
    }
  }

  void _save() {
    StorageService.instance.saveNodes(state);
  }

  void addNode(ProxyNode node) {
    final isFirst = state.isEmpty;
    state = [...state, node.copyWith(isActive: isFirst ? true : node.isActive)];
    _save();
  }

  void addNodes(List<ProxyNode> newNodes) {
    if (newNodes.isEmpty) return;
    final wasEmpty = state.isEmpty;
    final list = List<ProxyNode>.from(state);
    for (int i = 0; i < newNodes.length; i++) {
      final n = newNodes[i];
      list.add(n.copyWith(isActive: wasEmpty && i == 0 ? true : n.isActive));
    }
    state = list;
    _save();
  }

  void selectAndConnectFreeNode(ProxyNode freeNode) {
    final existingIdx = state.indexWhere((n) => n.id == freeNode.id);
    if (existingIdx != -1) {
      setActive(freeNode.id);
    } else {
      final updated = state.map((n) => n.copyWith(isActive: false)).toList();
      state = [freeNode.copyWith(isActive: true), ...updated];
      _save();
    }
  }

  void updateLatency(String id, int? latencyMs) {
    state = state.map((n) {
      if (n.id == id) {
        return n.copyWith(latencyMs: latencyMs, lastTestedAt: DateTime.now());
      }
      return n;
    }).toList();
    _save();
  }

  void updateLatenciesBatch(Map<String, int?> latencies) {
    if (latencies.isEmpty) return;
    final now = DateTime.now();
    state = state.map((n) {
      if (latencies.containsKey(n.id)) {
        return n.copyWith(latencyMs: latencies[n.id], lastTestedAt: now);
      }
      return n;
    }).toList();
    _save();
  }

  void removeNode(String id) {
    state = state.where((n) => n.id != id).toList();
    if (state.isNotEmpty && !state.any((n) => n.isActive)) {
      state[0].isActive = true;
      state = [...state];
    }
    _save();
  }

  void removeNodesBySubscription(String subId) {
    state = state.where((n) => n.subscriptionId != subId).toList();
    if (state.isNotEmpty && !state.any((n) => n.isActive)) {
      state[0].isActive = true;
      state = [...state];
    }
    _save();
  }

  int removeDeadNodes({
    String? subscriptionId,
    bool onlyCustom = false,
    bool includeUntested = false,
  }) {
    final toRemove = <String>{};
    for (final n in state) {
      if (onlyCustom && n.subscriptionId != null) continue;
      if (subscriptionId != null && n.subscriptionId != subscriptionId) continue;
      final isDead = includeUntested ? !n.hasValidPing : n.hasTimedOut;
      if (isDead) {
        toRemove.add(n.id);
      }
    }
    if (toRemove.isEmpty) return 0;

    state = state.where((n) => !toRemove.contains(n.id)).toList();
    if (state.isNotEmpty && !state.any((n) => n.isActive)) {
      state[0].isActive = true;
      state = [...state];
    }
    _save();
    return toRemove.length;
  }

  void replaceSubscriptionNodes(String subId, List<ProxyNode> newNodes) {
    final oldSubNodes = state.where((n) => n.subscriptionId == subId).toList();
    final nonSubNodes = state.where((n) => n.subscriptionId != subId).toList();

    String makeConfigKey(ProxyNode n) {
      return "${n.protocol.name}|${n.address.trim().toLowerCase()}|${n.port}|${n.uuidOrPassword.trim()}|${n.network.name}|${(n.path ?? '').trim()}";
    }

    // Build O(1) hash map of existing nodes for instant match
    final oldMap = <String, List<ProxyNode>>{};
    for (final old in oldSubNodes) {
      final k = makeConfigKey(old);
      (oldMap[k] ??= []).add(old);
    }

    final updatedSubNodes = <ProxyNode>[];

    for (final newNode in newNodes) {
      final k = makeConfigKey(newNode);
      final candidateList = oldMap[k];
      ProxyNode? match;
      if (candidateList != null && candidateList.isNotEmpty) {
        match = candidateList.removeAt(0);
      }

      if (match != null) {
        // Config hasn't changed: preserve its id, ping latency, lastTestedAt, isActive and clean IP!
        updatedSubNodes.add(newNode.copyWith(
          id: match.id,
          latencyMs: match.latencyMs,
          lastTestedAt: match.lastTestedAt,
          isActive: match.isActive,
          originalAddress: match.originalAddress,
          subscriptionId: subId,
        ));
      } else {
        updatedSubNodes.add(newNode.copyWith(
          subscriptionId: subId,
          isActive: false,
        ));
      }
    }

    final combined = [...nonSubNodes, ...updatedSubNodes];

    // Ensure strictly at most one node is active globally
    bool hasActive = false;
    for (int i = 0; i < combined.length; i++) {
      if (combined[i].isActive) {
        if (hasActive) {
          combined[i] = combined[i].copyWith(isActive: false);
        } else {
          hasActive = true;
        }
      }
    }
    if (combined.isNotEmpty && !hasActive) {
      combined[0] = combined[0].copyWith(isActive: true);
    }

    state = combined;
    _save();
  }

  void setActive(String id) {
    state = state.map((n) => n.copyWith(isActive: n.id == id)).toList();
    _save();
  }

  void updateNode(ProxyNode updated) {
    state = state.map((n) => n.id == updated.id ? updated : n).toList();
    _save();
  }

  void applyIp(String nodeId, String newIp) {
    state = state.map((n) {
      if (n.id == nodeId) {
        final orig = n.originalAddress ?? n.address;
        final isDomain = !orig.contains(RegExp(r'^\d+\.\d+\.\d+\.\d+$'));
        return n.copyWith(
          originalAddress: orig,
          address: newIp,
          host: (n.host != null && n.host!.isNotEmpty) ? n.host : (isDomain ? orig : null),
          sni: (n.sni != null && n.sni!.isNotEmpty) ? n.sni : (isDomain ? orig : null),
        );
      }
      return n;
    }).toList();
    _save();
  }

  void restoreAddress(String nodeId) {
    state = state.map((n) {
      if (n.id == nodeId && n.originalAddress != null) {
        return n.copyWith(
          address: n.originalAddress!,
          clearOriginalAddress: true,
        );
      }
      return n;
    }).toList();
    _save();
  }
}

final nodesProvider = StateNotifierProvider<NodesNotifier, List<ProxyNode>>((ref) {
  return NodesNotifier();
});

class SubscriptionsNotifier extends StateNotifier<List<SubscriptionItem>> {
  final Ref ref;
  Timer? _autoUpdateTimer;

  SubscriptionsNotifier(this.ref) : super([]) {
    _init();
    _startAutoUpdateTimer();
  }

  @override
  void dispose() {
    _autoUpdateTimer?.cancel();
    super.dispose();
  }

  void _startAutoUpdateTimer() {
    // Check every 10 minutes if any autoUpdate subscription hasn't been updated for 1 hour
    _autoUpdateTimer = Timer.periodic(const Duration(minutes: 10), (timer) {
      _checkHourlyAutoUpdate();
    });
  }

  Future<void> _checkHourlyAutoUpdate() async {
    final now = DateTime.now();
    for (final s in state) {
      if (s.autoUpdate) {
        if (s.lastUpdated == null || now.difference(s.lastUpdated!).inMinutes >= 60) {
          await updateSubscription(s.id);
        }
      }
    }
  }

  Future<void> _init() async {
    final saved = await StorageService.instance.loadSubscriptions();
    state = saved;
    // Also perform initial check
    _checkHourlyAutoUpdate();
  }

  void _save() {
    StorageService.instance.saveSubscriptions(state);
  }

  void toggleAutoUpdate(String id, bool val) {
    state = state.map((s) {
      if (s.id == id) {
        return s.copyWith(autoUpdate: val);
      }
      return s;
    }).toList();
    _save();
    if (val) {
      _checkHourlyAutoUpdate();
    }
  }

  Future<int> addSubscription(String name, String url) async {
    final subId = "sub-${DateTime.now().millisecondsSinceEpoch}";
    final item = SubscriptionItem(
      id: subId,
      name: name.trim().isEmpty ? "Subscription ${state.length + 1}" : name.trim(),
      url: url.trim(),
    );
    state = [...state, item];
    _save();
    return await updateSubscription(subId);
  }

  void removeSubscription(String id) {
    state = state.where((s) => s.id != id).toList();
    _save();
    ref.read(nodesProvider.notifier).removeNodesBySubscription(id);
  }

  void editSubscription(String id, String newName, String newUrl) {
    final cleanUrl = newUrl.trim();
    final cleanName = newName.trim();
    state = state.map((s) {
      if (s.id == id) {
        return s.copyWith(
          name: cleanName.isNotEmpty ? cleanName : s.name,
          url: cleanUrl.isNotEmpty ? cleanUrl : s.url,
        );
      }
      return s;
    }).toList();
    _save();
    updateSubscription(id);
  }

  Future<int> updateSubscription(String id) async {
    final idx = state.indexWhere((s) => s.id == id);
    if (idx == -1) return 0;
    final sub = state[idx];

    try {
      final uri = Uri.parse(sub.url);
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 15);
      final request = await client.getUrl(uri);
      request.headers.set("User-Agent", "v2rayN/6.42");
      final response = await request.close();

      int? uploadBytes;
      int? downloadBytes;
      int? totalBytes;
      DateTime? expireDate;

      final userInfo = response.headers.value("subscription-userinfo") ??
          response.headers.value("Subscription-Userinfo");
      if (userInfo != null && userInfo.isNotEmpty) {
        final pairs = userInfo.split(";");
        for (final pair in pairs) {
          final kv = pair.trim().split("=");
          if (kv.length == 2) {
            final key = kv[0].trim().toLowerCase();
            final val = int.tryParse(kv[1].trim());
            if (val != null) {
              if (key == "upload") uploadBytes = val;
              if (key == "download") downloadBytes = val;
              if (key == "total") totalBytes = val;
              if (key == "expire") {
                expireDate = DateTime.fromMillisecondsSinceEpoch(val * 1000);
              }
            }
          }
        }
      }

      final body = await response.transform(utf8.decoder).join();
      client.close();

      final parsed = await ConfigParser.parseBatchAsync(body);

      // Fallback: parse traffic/expire info from config name strings if headers not present
      if (totalBytes == null || expireDate == null) {
        for (final node in parsed) {
          final name = node.name;
          if (totalBytes == null) {
            final totalMatch = RegExp(r'(\d+)\s*(?:G|GB)', caseSensitive: false).firstMatch(name);
            final remMatch = RegExp(r'📊?\s*([\d\.]+)\s*GB', caseSensitive: false).firstMatch(name);
            if (remMatch != null) {
              final gb = double.tryParse(remMatch.group(1) ?? "");
              if (gb != null) {
                final remBytes = (gb * 1024 * 1024 * 1024).toInt();
                if (totalMatch != null) {
                  final totGb = double.tryParse(totalMatch.group(1) ?? "");
                  if (totGb != null) {
                    totalBytes = (totGb * 1024 * 1024 * 1024).toInt();
                    downloadBytes = totalBytes - remBytes;
                    uploadBytes = 0;
                  }
                } else {
                  totalBytes = remBytes;
                  uploadBytes = 0;
                  downloadBytes = 0;
                }
              }
            }
          }
          if (expireDate == null) {
            final dayMatch = RegExp(r'⏳\s*(\d+)\s*D', caseSensitive: false).firstMatch(name);
            if (dayMatch != null) {
              final days = int.tryParse(dayMatch.group(1) ?? "");
              if (days != null) {
                expireDate = DateTime.now().add(Duration(days: days));
              }
            }
          }
        }
      }

      if (parsed.isNotEmpty) {
        final tagged = parsed.map((n) => n.copyWith(subscriptionId: sub.id)).toList();
        ref.read(nodesProvider.notifier).replaceSubscriptionNodes(sub.id, tagged);
        state[idx] = sub.copyWith(
          lastUpdated: DateTime.now(),
          nodeCount: tagged.length,
          uploadBytes: uploadBytes ?? sub.uploadBytes,
          downloadBytes: downloadBytes ?? sub.downloadBytes,
          totalBytes: totalBytes ?? sub.totalBytes,
          expireDate: expireDate ?? sub.expireDate,
        );
        state = [...state];
        _save();
        return tagged.length;
      }
    } catch (_) {}
    return 0;
  }

  Future<void> updateAll() async {
    for (final s in state) {
      await updateSubscription(s.id);
    }
  }

  void updateNodeCount(String subId, int newCount) {
    final idx = state.indexWhere((s) => s.id == subId);
    if (idx != -1) {
      state[idx] = state[idx].copyWith(nodeCount: newCount);
      state = [...state];
      _save();
    }
  }
}

final subscriptionsProvider = StateNotifierProvider<SubscriptionsNotifier, List<SubscriptionItem>>((ref) {
  return SubscriptionsNotifier(ref);
});

enum ScannerStrategy { radar, target }

class RadarLogEntry {
  final String ip;
  final int latencyMs;
  final DateTime timestamp;
  final int? improvementMs;

  RadarLogEntry({
    required this.ip,
    required this.latencyMs,
    required this.timestamp,
    this.improvementMs,
  });
}

class ScannerState {
  final bool isScanning;
  final ScannerStrategy strategy;
  final CdnProvider selectedCdn;
  final int workers; // Concurrency from slider (5 to 100)
  final int targetTotalCandidates; // Target total from slider (200 to 10,000)
  final int total;
  final int scanned;
  final String currentIp;
  final List<ScanResult> results;
  final ScanResult? bestIp;
  final String? connectedIp;
  final int? currentBestLatency;
  final List<RadarLogEntry> radarLogs;
  final String? statusMessage;
  final int radarHealthyCount;
  final bool showRadarTrafficWarning;

  int get threshold => workers;

  ScannerState({
    this.isScanning = false,
    this.strategy = ScannerStrategy.radar,
    this.selectedCdn = CdnProvider.cloudflare,
    int? workers,
    int? threshold,
    this.targetTotalCandidates = 500,
    this.total = 0,
    this.scanned = 0,
    this.currentIp = "",
    this.results = const [],
    this.bestIp,
    this.connectedIp,
    this.currentBestLatency,
    this.radarLogs = const [],
    this.statusMessage,
    this.radarHealthyCount = 0,
    this.showRadarTrafficWarning = false,
  }) : workers = (workers ?? threshold ?? 20).clamp(5, 100);

  ScannerState copyWith({
    bool? isScanning,
    ScannerStrategy? strategy,
    CdnProvider? selectedCdn,
    int? workers,
    int? threshold,
    int? targetTotalCandidates,
    int? total,
    int? scanned,
    String? currentIp,
    List<ScanResult>? results,
    ScanResult? bestIp,
    String? connectedIp,
    int? currentBestLatency,
    List<RadarLogEntry>? radarLogs,
    String? statusMessage,
    int? radarHealthyCount,
    bool? showRadarTrafficWarning,
  }) {
    return ScannerState(
      isScanning: isScanning ?? this.isScanning,
      strategy: strategy ?? this.strategy,
      selectedCdn: selectedCdn ?? this.selectedCdn,
      workers: workers ?? threshold ?? this.workers,
      targetTotalCandidates: targetTotalCandidates ?? this.targetTotalCandidates,
      total: total ?? this.total,
      scanned: scanned ?? this.scanned,
      currentIp: currentIp ?? this.currentIp,
      results: results ?? this.results,
      bestIp: bestIp ?? this.bestIp,
      connectedIp: connectedIp ?? this.connectedIp,
      currentBestLatency: currentBestLatency ?? this.currentBestLatency,
      radarLogs: radarLogs ?? this.radarLogs,
      statusMessage: statusMessage ?? this.statusMessage,
      radarHealthyCount: radarHealthyCount ?? this.radarHealthyCount,
      showRadarTrafficWarning: showRadarTrafficWarning ?? this.showRadarTrafficWarning,
    );
  }
}

class ScannerNotifier extends StateNotifier<ScannerState> {
  final Ref ref;
  bool _isCancelled = false;
  bool _hasWarnedRadarTraffic = false;

  ScannerNotifier(this.ref) : super(ScannerState());

  void setSelectedCdn(CdnProvider cdn) {
    if (state.isScanning) return;
    state = state.copyWith(selectedCdn: cdn);
  }

  void setStrategy(ScannerStrategy strategy) {
    if (state.isScanning) return;
    state = state.copyWith(strategy: strategy);
  }

  void setWorkers(int workers) {
    if (state.isScanning) return;
    state = state.copyWith(workers: workers.clamp(5, 100));
  }

  void setThreshold(int threshold) => setWorkers(threshold);

  void setTargetTotalCandidates(int total) {
    if (state.isScanning) return;
    state = state.copyWith(targetTotalCandidates: total.clamp(200, 10000));
  }

  void cancelScan() {
    _isCancelled = true;
    CloudflareScannerService.instance.cancel();
    state = state.copyWith(isScanning: false, statusMessage: "Stopped");
  }

  void dismissRadarWarning() {
    state = state.copyWith(showRadarTrafficWarning: false);
  }

  void resetScan() {
    _hasWarnedRadarTraffic = false;
    if (state.isScanning) {
      cancelScan();
    }
    state = ScannerState(
      strategy: state.strategy,
      selectedCdn: state.selectedCdn,
      workers: state.workers,
      targetTotalCandidates: state.targetTotalCandidates,
      isScanning: false,
      total: 0,
      scanned: 0,
      currentIp: "",
      results: [],
      bestIp: null,
      connectedIp: null,
      currentBestLatency: null,
      radarLogs: [],
      statusMessage: null,
      radarHealthyCount: 0,
      showRadarTrafficWarning: false,
    );
  }

  Future<void> startScan() async {
    if (state.isScanning) return;
    final nodes = ref.read(nodesProvider);
    if (nodes.isEmpty) return;
    final activeNode = nodes.firstWhere((n) => n.isActive, orElse: () => nodes.first);
    
    final cdn = state.selectedCdn;
    final allRanges = ref.read(cdnRangesProvider);
    final customCidrs = allRanges[cdn] ?? cdn.defaultCidrs;

    final origAddress = activeNode.originalAddress ?? activeNode.address;
    final isDomain = !origAddress.contains(RegExp(r'^\d+\.\d+\.\d+\.\d+$'));

    _isCancelled = false;
    _hasWarnedRadarTraffic = false;
    final strategy = state.strategy;
    final workers = state.workers;

    if (strategy == ScannerStrategy.radar) {
      // RADAR MODE: Infinite & continuous scan across CDN ranges
      state = state.copyWith(
        isScanning: true,
        total: 0, // 0 indicates infinite continuous stream
        scanned: 0,
        currentIp: "",
        results: [],
        bestIp: null,
        connectedIp: activeNode.address,
        currentBestLatency: null,
        radarLogs: [],
        statusMessage: "Radar active...",
        radarHealthyCount: 0,
        showRadarTrafficWarning: false,
      );

      final rng = Random();

      while (!_isCancelled) {
        final chunk = CdnScannerService.generateCandidateIps(
          cdn: cdn,
          count: workers,
          customCidrs: customCidrs,
          rng: rng,
        );

        final futures = chunk.map((ip) async {
          final candidateNode = activeNode.copyWith(
            address: ip,
            host: (activeNode.host != null && activeNode.host!.isNotEmpty)
                ? activeNode.host
                : (isDomain ? origAddress : null),
            sni: (activeNode.sni != null && activeNode.sni!.isNotEmpty)
                ? activeNode.sni
                : (isDomain ? origAddress : null),
          );
          final lat = await XrayProcessService.instance.testNodeLatency(
            candidateNode,
            timeout: const Duration(seconds: 3),
          );
          return MapEntry(ip, lat);
        });

        final chunkResults = await Future.wait(futures);
        if (_isCancelled) break;

        for (final entry in chunkResults) {
          if (_isCancelled) break;
          final ip = entry.key;
          final lat = entry.value;

          state = state.copyWith(
            scanned: state.scanned + 1,
            currentIp: ip,
          );

          if (lat != null) {
            final newHealthyCount = state.radarHealthyCount + 1;
            final shouldWarn = newHealthyCount >= 10 && !_hasWarnedRadarTraffic;
            if (shouldWarn) {
              _hasWarnedRadarTraffic = true;
            }

            final scanRes = ScanResult(
              ip: ip,
              port: activeNode.port,
              tcpSuccess: true,
              tcpLatencyMs: lat,
              tlsSuccess: activeNode.security == SecurityType.tls || activeNode.security == SecurityType.reality,
              tlsLatencyMs: lat,
              protocolSuccess: true,
              totalLatencyMs: lat,
              rankScore: lat.toDouble(),
            );

            // Update state.results with all responsive IPs (sorted by latency ascending)
            final existingIndex = state.results.indexWhere((r) => r.ip == ip);
            List<ScanResult> updatedResults;
            if (existingIndex >= 0) {
              final existing = state.results[existingIndex];
              if ((existing.totalLatencyMs ?? 99999) > lat) {
                updatedResults = List<ScanResult>.from(state.results);
                updatedResults[existingIndex] = scanRes;
              } else {
                updatedResults = state.results;
              }
            } else {
              updatedResults = [...state.results, scanRes];
            }
            updatedResults.sort((a, b) => (a.totalLatencyMs ?? 99999).compareTo(b.totalLatencyMs ?? 99999));

            final prevBest = state.currentBestLatency;
            final isNewBest = prevBest == null || lat < prevBest;

            if (isNewBest) {
              final improvement = prevBest != null ? (prevBest - lat) : null;
              final newEntry = RadarLogEntry(
                ip: ip,
                latencyMs: lat,
                timestamp: DateTime.now(),
                improvementMs: improvement,
              );

              state = state.copyWith(
                results: updatedResults,
                bestIp: scanRes,
                connectedIp: ip,
                currentBestLatency: lat,
                radarLogs: [newEntry, ...state.radarLogs],
                radarHealthyCount: newHealthyCount,
                showRadarTrafficWarning: shouldWarn ? true : state.showRadarTrafficWarning,
              );

              // Apply the new best IP to active node
              LogService.instance.add(
                "[Radar] Discovered new best ${cdn.displayName} IP: $ip (${lat}ms)${improvement != null ? ' - improved by ${improvement}ms' : ''}",
                level: LogLevel.access,
                source: "scanner",
              );
              ref.read(nodesProvider.notifier).applyIp(activeNode.id, ip);

              // Connect or hot-switch Xray connection
              final nodeToConnect = activeNode.copyWith(
                address: ip,
                originalAddress: origAddress,
                host: (activeNode.host != null && activeNode.host!.isNotEmpty)
                    ? activeNode.host
                    : (isDomain ? origAddress : null),
                sni: (activeNode.sni != null && activeNode.sni!.isNotEmpty)
                    ? activeNode.sni
                    : (isDomain ? origAddress : null),
              );

              final connState = ref.read(connectionStatusProvider);
              if (connState == ConnectionStateEnum.connected) {
                await XrayProcessService.instance.stop();
                await XrayProcessService.instance.start(
                  nodeToConnect,
                  enableTun: ref.read(isTunEnabledProvider),
                  setSysProxy: ref.read(isSystemProxyEnabledProvider),
                );
              } else {
                final ok = await XrayProcessService.instance.start(
                  nodeToConnect,
                  enableTun: ref.read(isTunEnabledProvider),
                  setSysProxy: ref.read(isSystemProxyEnabledProvider),
                );
                if (ok) {
                  ref.read(connectionStatusProvider.notifier).setConnected();
                }
              }
            } else {
              state = state.copyWith(
                results: updatedResults,
                radarHealthyCount: newHealthyCount,
                showRadarTrafficWarning: shouldWarn ? true : state.showRadarTrafficWarning,
              );
              LogService.instance.add(
                "[Radar] Discovered responsive ${cdn.displayName} IP: $ip (${lat}ms)",
                level: LogLevel.info,
                source: "scanner",
              );
            }
          }
        }
      }

      state = state.copyWith(isScanning: false, statusMessage: "Stopped");
    } else {
      // TARGET MODE: User-selected pool size (200 to 10,000)
      final totalCount = state.targetTotalCandidates;
      final candidates = CdnScannerService.generateCandidateIps(
        cdn: cdn,
        count: totalCount,
        customCidrs: customCidrs,
      );

      state = state.copyWith(
        isScanning: true,
        total: candidates.length,
        scanned: 0,
        currentIp: "",
        results: [],
        bestIp: null,
        connectedIp: activeNode.address,
        currentBestLatency: null,
        radarLogs: [],
        statusMessage: "Scanning...",
      );

      for (int i = 0; i < candidates.length; i += workers) {
        if (_isCancelled) break;
        final chunk = candidates.sublist(i, min(i + workers, candidates.length));

        final futures = chunk.map((ip) async {
          final candidateNode = activeNode.copyWith(
            address: ip,
            host: (activeNode.host != null && activeNode.host!.isNotEmpty)
                ? activeNode.host
                : (isDomain ? origAddress : null),
            sni: (activeNode.sni != null && activeNode.sni!.isNotEmpty)
                ? activeNode.sni
                : (isDomain ? origAddress : null),
          );
          final lat = await XrayProcessService.instance.testNodeLatency(
            candidateNode,
            timeout: const Duration(seconds: 3),
          );
          return MapEntry(ip, lat);
        });

        final chunkResults = await Future.wait(futures);
        if (_isCancelled) break;

        for (final entry in chunkResults) {
          if (_isCancelled) break;
          final ip = entry.key;
          final lat = entry.value;

          state = state.copyWith(
            scanned: state.scanned + 1,
            currentIp: ip,
          );

          if (lat != null) {
            final scanRes = ScanResult(
              ip: ip,
              port: activeNode.port,
              tcpSuccess: true,
              tcpLatencyMs: lat,
              tlsSuccess: activeNode.security == SecurityType.tls || activeNode.security == SecurityType.reality,
              tlsLatencyMs: lat,
              protocolSuccess: true,
              totalLatencyMs: lat,
              rankScore: lat.toDouble(),
            );

            final updatedList = [...state.results, scanRes];
            updatedList.sort((a, b) => (a.totalLatencyMs ?? 99999).compareTo(b.totalLatencyMs ?? 99999));
            state = state.copyWith(
              results: updatedList,
              bestIp: updatedList.first,
            );
          }
        }
      }

      state = state.copyWith(isScanning: false, statusMessage: "Finished");
      LogService.instance.add(
        "[Target] Scan finished. Tested ${state.scanned}/${candidates.length} IPs, found ${state.results.length} responsive servers.",
        level: LogLevel.info,
        source: "scanner",
      );
    }
  }

  Future<void> connectToCandidateIp(String ip, int latencyMs) async {
    final nodes = ref.read(nodesProvider);
    if (nodes.isEmpty) return;
    final activeNode = nodes.firstWhere((n) => n.isActive, orElse: () => nodes.first);

    LogService.instance.add(
      "[Scanner] Connecting to selected IP: $ip (${latencyMs}ms)...",
      level: LogLevel.info,
      source: "scanner",
    );
    ref.read(nodesProvider.notifier).applyIp(activeNode.id, ip);
    state = state.copyWith(connectedIp: ip);

    final origAddress = activeNode.originalAddress ?? activeNode.address;
    final isDomain = !origAddress.contains(RegExp(r'^\d+\.\d+\.\d+\.\d+$'));
    final nodeToConnect = activeNode.copyWith(
      address: ip,
      originalAddress: origAddress,
      host: (activeNode.host != null && activeNode.host!.isNotEmpty)
          ? activeNode.host
          : (isDomain ? origAddress : null),
      sni: (activeNode.sni != null && activeNode.sni!.isNotEmpty)
          ? activeNode.sni
          : (isDomain ? origAddress : null),
    );

    final connState = ref.read(connectionStatusProvider);
    if (connState == ConnectionStateEnum.connected) {
      await XrayProcessService.instance.stop();
      await XrayProcessService.instance.start(
        nodeToConnect,
        enableTun: ref.read(isTunEnabledProvider),
        setSysProxy: ref.read(isSystemProxyEnabledProvider),
      );
    } else {
      final ok = await XrayProcessService.instance.start(
        nodeToConnect,
        enableTun: ref.read(isTunEnabledProvider),
        setSysProxy: ref.read(isSystemProxyEnabledProvider),
      );
      if (ok) {
        ref.read(connectionStatusProvider.notifier).setConnected();
      }
    }
  }

  Future<void> connectToTargetIp(String ip, int latencyMs) =>
      connectToCandidateIp(ip, latencyMs);
}

final scannerProvider = StateNotifierProvider<ScannerNotifier, ScannerState>((ref) {
  return ScannerNotifier(ref);
});

class CdnRangesNotifier extends StateNotifier<Map<CdnProvider, List<String>>> {
  CdnRangesNotifier() : super({
    for (final p in CdnProvider.values) p: p.defaultCidrs,
  }) {
    _init();
  }

  Future<void> _init() async {
    final map = <CdnProvider, List<String>>{};
    for (final p in CdnProvider.values) {
      final saved = await StorageService.instance.loadCdnRanges(p);
      map[p] = saved.isNotEmpty ? saved : p.defaultCidrs;
    }
    state = map;
  }

  void updateRanges(CdnProvider provider, List<String> ranges) {
    state = {...state, provider: ranges};
    StorageService.instance.saveCdnRanges(provider, ranges);
  }

  void resetToDefault(CdnProvider provider) {
    state = {...state, provider: provider.defaultCidrs};
    StorageService.instance.saveCdnRanges(provider, provider.defaultCidrs);
  }
}

final cdnRangesProvider = StateNotifierProvider<CdnRangesNotifier, Map<CdnProvider, List<String>>>((ref) {
  return CdnRangesNotifier();
});

class CloudflareRangesNotifier extends StateNotifier<List<String>> {
  final Ref ref;
  CloudflareRangesNotifier(this.ref) : super(CdnProvider.cloudflare.defaultCidrs) {
    _init();
  }

  Future<void> _init() async {
    final saved = await StorageService.instance.loadCloudflareRanges();
    if (saved.isNotEmpty) {
      state = saved;
    }
  }

  void updateRanges(List<String> ranges) {
    state = ranges;
    ref.read(cdnRangesProvider.notifier).updateRanges(CdnProvider.cloudflare, ranges);
  }

  void resetToDefault() {
    state = CdnProvider.cloudflare.defaultCidrs;
    ref.read(cdnRangesProvider.notifier).resetToDefault(CdnProvider.cloudflare);
  }
}

final cfRangesProvider = StateNotifierProvider<CloudflareRangesNotifier, List<String>>((ref) {
  return CloudflareRangesNotifier(ref);
});

class DnsNotifier extends StateNotifier<DnsSettings> {
  DnsNotifier() : super(const DnsSettings()) {
    _load();
  }

  Future<void> _load() async {
    final saved = await StorageService.instance.loadDnsSettings();
    state = saved;
    XrayProcessService.instance.dnsServers = saved.servers;
  }

  Future<void> setPreset(String presetId) async {
    final preset = DnsSettings.presets.firstWhere(
      (p) => p.id == presetId,
      orElse: () => DnsSettings.presets.first,
    );
    final updated = state.copyWith(
      presetId: presetId,
      servers: preset.id == "custom" ? state.servers : preset.servers,
    );
    state = updated;
    XrayProcessService.instance.dnsServers = updated.servers;
    await StorageService.instance.saveDnsSettings(updated);
  }

  Future<void> updateCustomServers(List<String> servers) async {
    final updated = state.copyWith(
      presetId: "custom",
      servers: servers,
    );
    state = updated;
    XrayProcessService.instance.dnsServers = updated.servers;
    await StorageService.instance.saveDnsSettings(updated);
  }
}

final dnsSettingsProvider = StateNotifierProvider<DnsNotifier, DnsSettings>((ref) {
  return DnsNotifier();
});

// Default to English as requested
final currentLocaleProvider = StateProvider<String>((ref) => "en");

// Port settings providers with persistence and automatic XrayProcessService sync
class HttpPortNotifier extends StateNotifier<int> {
  HttpPortNotifier() : super(10888) {
    _init();
  }

  Future<void> _init() async {
    final p = await StorageService.instance.loadHttpPort();
    state = p;
    XrayProcessService.instance.httpPort = p;
  }

  void setPort(int port) {
    state = port;
    XrayProcessService.instance.httpPort = port;
    StorageService.instance.saveHttpPort(port);
  }
}

final httpPortProvider = StateNotifierProvider<HttpPortNotifier, int>((ref) {
  return HttpPortNotifier();
});

class SocksPortNotifier extends StateNotifier<int> {
  SocksPortNotifier() : super(10999) {
    _init();
  }

  Future<void> _init() async {
    final p = await StorageService.instance.loadSocksPort();
    state = p;
    XrayProcessService.instance.socksPort = p;
  }

  void setPort(int port) {
    state = port;
    XrayProcessService.instance.socksPort = port;
    StorageService.instance.saveSocksPort(port);
  }
}

final socksPortProvider = StateNotifierProvider<SocksPortNotifier, int>((ref) {
  return SocksPortNotifier();
});

class LogsNotifier extends StateNotifier<List<LogEntry>> {
  StreamSubscription<LogEntry>? _sub;

  LogsNotifier() : super(LogService.instance.logs) {
    _sub = LogService.instance.onNewLog.listen((_) {
      state = LogService.instance.logs;
    });
  }

  void add(String message, {LogLevel level = LogLevel.info, String source = "system"}) {
    LogService.instance.add(message, level: level, source: source);
  }

  void clear() {
    LogService.instance.clear();
    state = [];
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

final logsProvider = StateNotifierProvider<LogsNotifier, List<LogEntry>>((ref) {
  return LogsNotifier();
});

class OutboundInfoNotifier extends StateNotifier<OutboundInfo> {
  final Ref ref;
  OutboundInfoNotifier(this.ref) : super(const OutboundInfo());

  Future<void> fetch() async {
    state = state.copyWith(isLoading: true, error: null);
    final httpPort = ref.read(httpPortProvider);

    String? ipv4;
    String? country;
    String? countryCode;
    String? city;
    String? isp;
    String? ipv6;

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 4);
    client.findProxy = (uri) => "PROXY 127.0.0.1:$httpPort;";

    // Fetch IPv4 & Geolocation through local proxy
    // 1. Primary: ip-api.com
    try {
      final req = await client.getUrl(Uri.parse("http://ip-api.com/json/"));
      final resp = await req.close().timeout(const Duration(seconds: 4));
      if (resp.statusCode == 200) {
        final body = await resp.transform(utf8.decoder).join();
        final data = jsonDecode(body);
        if (data["status"] == "success") {
          ipv4 = data["query"]?.toString();
          country = data["country"]?.toString();
          countryCode = data["countryCode"]?.toString();
          city = data["city"]?.toString();
          isp = data["isp"]?.toString();
        }
      }
    } catch (_) {}

    // 2. Fallback 1: ipwho.is
    if (countryCode == null || countryCode.isEmpty) {
      try {
        final req = await client.getUrl(Uri.parse("https://ipwho.is/"));
        final resp = await req.close().timeout(const Duration(seconds: 4));
        if (resp.statusCode == 200) {
          final body = await resp.transform(utf8.decoder).join();
          final data = jsonDecode(body);
          if (data["success"] == true) {
            ipv4 ??= data["ip"]?.toString();
            country ??= data["country"]?.toString();
            countryCode ??= data["country_code"]?.toString();
            city ??= data["city"]?.toString();
            isp ??= data["connection"]?["isp"]?.toString();
          }
        }
      } catch (_) {}
    }

    // 3. Fallback 2: api.ip.sb/geoip
    if (countryCode == null || countryCode.isEmpty) {
      try {
        final req = await client.getUrl(Uri.parse("https://api.ip.sb/geoip"));
        final resp = await req.close().timeout(const Duration(seconds: 4));
        if (resp.statusCode == 200) {
          final body = await resp.transform(utf8.decoder).join();
          final data = jsonDecode(body);
          ipv4 ??= data["ip"]?.toString();
          country ??= data["country"]?.toString();
          countryCode ??= data["country_code"]?.toString();
          city ??= data["city"]?.toString();
          isp ??= data["isp"]?.toString();
        }
      } catch (_) {}
    }

    // 4. Fallback 3: api4.ipify.org (IP only)
    if (ipv4 == null) {
      try {
        final req = await client.getUrl(Uri.parse("https://api4.ipify.org?format=json"));
        final resp = await req.close().timeout(const Duration(seconds: 3));
        if (resp.statusCode == 200) {
          final body = await resp.transform(utf8.decoder).join();
          final data = jsonDecode(body);
          ipv4 = data["ip"]?.toString();
        }
      } catch (_) {}
    }

    // Fetch IPv6 through local proxy
    try {
      final req6 = await client.getUrl(Uri.parse("https://api6.ipify.org?format=json"));
      final resp6 = await req6.close().timeout(const Duration(seconds: 3));
      if (resp6.statusCode == 200) {
        final body = await resp6.transform(utf8.decoder).join();
        final data = jsonDecode(body);
        ipv6 = data["ip"]?.toString();
      }
    } catch (_) {
      ipv6 = null;
    } finally {
      client.close();
    }

    state = OutboundInfo(
      ipv4: ipv4,
      ipv6: ipv6,
      country: country,
      countryCode: countryCode,
      city: city,
      isp: isp,
      isLoading: false,
    );
  }

  void reset() {
    state = const OutboundInfo();
  }
}

final outboundInfoProvider = StateNotifierProvider<OutboundInfoNotifier, OutboundInfo>((ref) {
  return OutboundInfoNotifier(ref);
});

final connectedAtProvider = StateProvider<DateTime?>((ref) => null);

// False by default: masks half of IP addresses with ***
final showFullIpProvider = StateProvider<bool>((ref) => false);

class NodeCdnDetectionNotifier extends StateNotifier<Map<String, CdnProvider?>> {
  final Ref ref;
  final Map<String, CdnProvider?> _syncCache = {};

  NodeCdnDetectionNotifier(this.ref) : super({});

  CdnProvider? detectCdn(String rawAddress) {
    final addr = rawAddress.trim().toLowerCase();
    if (addr.isEmpty) return null;
    if (state.containsKey(addr)) return state[addr];
    if (_syncCache.containsKey(addr)) return _syncCache[addr];

    final cdnRanges = ref.read(cdnRangesProvider);
    final syncMatch = CdnScannerService.detectCdnHostSync(addr, cdnRanges);
    _syncCache[addr] = syncMatch;

    // Safely update state outside the build phase to prevent widget rebuild errors
    Future.microtask(() {
      if (mounted && !state.containsKey(addr)) {
        state = {...state, addr: syncMatch};
      }
    });

    return syncMatch;
  }

  /// Explicit async DNS check for active node or on-demand inspection
  Future<CdnProvider?> checkDomainCdn(String domain) async {
    final addr = domain.trim().toLowerCase();
    if (addr.isEmpty) return null;
    final cdnRanges = ref.read(cdnRangesProvider);
    final resolved = await CdnScannerService.detectCdnFromHost(addr, cdnRanges);
    if (resolved != null && mounted) {
      _syncCache[addr] = resolved;
      state = {...state, addr: resolved};
      ref.read(cfCheckedHostsProvider.notifier).markCdn(addr, true);
    }
    return resolved;
  }
}

final nodeCdnMapProvider = StateNotifierProvider<NodeCdnDetectionNotifier, Map<String, CdnProvider?>>((ref) {
  return NodeCdnDetectionNotifier(ref);
});

class CfCheckedHostsNotifier extends StateNotifier<Map<String, bool>> {
  final Ref ref;
  final Map<String, bool> _syncCache = {};

  CfCheckedHostsNotifier(this.ref) : super({});

  void markCdn(String addr, bool isCdn) {
    final key = addr.trim().toLowerCase();
    _syncCache[key] = isCdn;
    if (mounted) {
      state = {...state, key: isCdn};
    }
  }

  bool isCloudflare(String address) {
    final addr = address.trim().toLowerCase();
    if (state.containsKey(addr)) return state[addr]!;
    if (_syncCache.containsKey(addr)) return _syncCache[addr]!;

    final cdn = ref.read(nodeCdnMapProvider.notifier).detectCdn(addr);
    final isSupported = cdn != null;
    _syncCache[addr] = isSupported;

    // Safely update state outside the build phase
    Future.microtask(() {
      if (mounted && !state.containsKey(addr)) {
        state = {...state, addr: isSupported};
      }
    });

    return isSupported;
  }
}

final cfCheckedHostsProvider = StateNotifierProvider<CfCheckedHostsNotifier, Map<String, bool>>((ref) {
  return CfCheckedHostsNotifier(ref);
});

// Settings Providers
class StartOnBootNotifier extends StateNotifier<bool> {
  StartOnBootNotifier() : super(false) {
    _load();
  }
  Future<void> _load() async {
    state = await StorageService.instance.loadStartOnBoot();
  }
  Future<void> toggle(bool val) async {
    state = val;
    await StorageService.instance.saveStartOnBoot(val);
  }
}
final startOnBootProvider = StateNotifierProvider<StartOnBootNotifier, bool>((ref) => StartOnBootNotifier());

class AutoConnectNotifier extends StateNotifier<bool> {
  AutoConnectNotifier() : super(false) {
    _load();
  }
  Future<void> _load() async {
    state = await StorageService.instance.loadAutoConnect();
  }
  Future<void> toggle(bool val) async {
    state = val;
    await StorageService.instance.saveAutoConnect(val);
  }
}
final autoConnectOnLaunchProvider = StateNotifierProvider<AutoConnectNotifier, bool>((ref) => AutoConnectNotifier());

class AutoSysProxyNotifier extends StateNotifier<bool> {
  AutoSysProxyNotifier() : super(false) {
    _load();
  }
  Future<void> _load() async {
    state = await StorageService.instance.loadAutoSysProxy();
  }
  Future<void> toggle(bool val) async {
    state = val;
    await StorageService.instance.saveAutoSysProxy(val);
  }
}
final autoEnableSysProxyOnConnectProvider = StateNotifierProvider<AutoSysProxyNotifier, bool>((ref) => AutoSysProxyNotifier());

class AutoTunNotifier extends StateNotifier<bool> {
  AutoTunNotifier() : super(false) {
    _load();
  }
  Future<void> _load() async {
    state = await StorageService.instance.loadAutoTun();
  }
  Future<void> toggle(bool val) async {
    state = val;
    await StorageService.instance.saveAutoTun(val);
  }
}
final autoEnableTunOnConnectProvider = StateNotifierProvider<AutoTunNotifier, bool>((ref) => AutoTunNotifier());

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier() : super(ThemeMode.system) {
    _load();
  }
  Future<void> _load() async {
    final str = await StorageService.instance.loadThemeMode();
    if (str == "light") {
      state = ThemeMode.light;
    } else if (str == "dark") {
      state = ThemeMode.dark;
    } else {
      state = ThemeMode.system;
    }
  }
  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    final str = mode == ThemeMode.light ? "light" : (mode == ThemeMode.dark ? "dark" : "system");
    await StorageService.instance.saveThemeMode(str);
  }
  Future<void> setTheme(ThemeMode mode) => setMode(mode);
}
final appThemeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) => ThemeModeNotifier());

class EnableUdpNotifier extends StateNotifier<bool> {
  EnableUdpNotifier() : super(true) {
    _load();
  }
  Future<void> _load() async {
    state = await StorageService.instance.loadEnableUdp();
  }
  Future<void> toggle(bool val) async {
    state = val;
    await StorageService.instance.saveEnableUdp(val);
  }
}
final enableUdpProvider = StateNotifierProvider<EnableUdpNotifier, bool>((ref) => EnableUdpNotifier());

class FreeConfigsState {
  final List<ProxyNode> workingNodes;
  final bool isScanning;
  final int totalScraped;
  final int totalUnique;
  final int testedCandidates;
  final int targetCount;
  final String status;
  final double progress;

  const FreeConfigsState({
    this.workingNodes = const [],
    this.isScanning = false,
    this.totalScraped = 0,
    this.totalUnique = 0,
    this.testedCandidates = 0,
    this.targetCount = 30,
    this.status = 'idle',
    this.progress = 0.0,
  });

  FreeConfigsState copyWith({
    List<ProxyNode>? workingNodes,
    bool? isScanning,
    int? totalScraped,
    int? totalUnique,
    int? testedCandidates,
    int? targetCount,
    String? status,
    double? progress,
  }) {
    return FreeConfigsState(
      workingNodes: workingNodes ?? this.workingNodes,
      isScanning: isScanning ?? this.isScanning,
      totalScraped: totalScraped ?? this.totalScraped,
      totalUnique: totalUnique ?? this.totalUnique,
      testedCandidates: testedCandidates ?? this.testedCandidates,
      targetCount: targetCount ?? this.targetCount,
      status: status ?? this.status,
      progress: progress ?? this.progress,
    );
  }
}

class FreeConfigsNotifier extends StateNotifier<FreeConfigsState> {
  final Ref ref;

  FreeConfigsNotifier(this.ref) : super(const FreeConfigsState()) {
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final saved = await StorageService.instance.loadFreeConfigs();
    if (saved.isNotEmpty) {
      state = state.copyWith(workingNodes: saved);
    }
  }

  Future<void> startScan() async {
    if (state.isScanning) return;
    state = state.copyWith(
      isScanning: true,
      status: 'fetching',
      progress: 0.0,
      testedCandidates: 0,
      totalScraped: 0,
      totalUnique: 0,
      workingNodes: [],
    );

    await FreeConfigsService.instance.fetchAndScan(
      targetWorking: 30,
      batchSize: 30,
      onProgress: (prog) {
        final progressRatio = prog.targetWorking > 0
            ? (prog.workingFound / prog.targetWorking).clamp(0.0, 1.0)
            : 0.0;
        state = state.copyWith(
          workingNodes: prog.workingNodes,
          totalScraped: prog.totalScraped,
          totalUnique: prog.totalUnique,
          testedCandidates: prog.testedCandidates,
          status: prog.status,
          progress: progressRatio,
          isScanning: !prog.isCompleted,
        );
      },
    );

    state = state.copyWith(isScanning: false, status: 'completed');
  }

  void cancelScan() {
    FreeConfigsService.instance.cancel();
    state = state.copyWith(isScanning: false, status: 'cancelled');
  }
}

final freeConfigsProvider = StateNotifierProvider<FreeConfigsNotifier, FreeConfigsState>((ref) {
  return FreeConfigsNotifier(ref);
});



