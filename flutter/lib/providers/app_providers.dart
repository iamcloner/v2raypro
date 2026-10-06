import "dart:convert";
import "dart:io";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "../models/proxy_node.dart";
import "../models/scan_result.dart";
import "../models/subscription_item.dart";
import "../services/cloudflare_scanner_service.dart";
import "../services/storage_service.dart";
import "../services/xray_process_service.dart";
import "../utils/config_parser.dart";

enum ConnectionStateEnum { disconnected, connecting, connected, disconnecting, error }

class ConnectionStatusNotifier extends StateNotifier<ConnectionStateEnum> {
  final Ref ref;
  ConnectionStatusNotifier(this.ref) : super(ConnectionStateEnum.disconnected);

  Future<void> toggleConnect() async {
    final nodes = ref.read(nodesProvider);
    if (nodes.isEmpty) {
      state = ConnectionStateEnum.error;
      return;
    }

    final activeNode = nodes.firstWhere((n) => n.isActive, orElse: () => nodes.first);
    final isTun = ref.read(isTunEnabledProvider);
    final isSysProxy = ref.read(isSystemProxyEnabledProvider);

    if (state == ConnectionStateEnum.disconnected || state == ConnectionStateEnum.error) {
      state = ConnectionStateEnum.connecting;
      final ok = await XrayProcessService.instance.start(
        activeNode,
        enableTun: isTun,
        setSysProxy: isSysProxy,
      );
      if (ok) {
        state = ConnectionStateEnum.connected;
      } else {
        state = ConnectionStateEnum.error;
      }
    } else if (state == ConnectionStateEnum.connected) {
      state = ConnectionStateEnum.disconnecting;
      await XrayProcessService.instance.stop();
      state = ConnectionStateEnum.disconnected;
    }
  }
}

final connectionStatusProvider = StateNotifierProvider<ConnectionStatusNotifier, ConnectionStateEnum>((ref) {
  return ConnectionStatusNotifier(ref);
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
      state = saved;
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

  void updateLatency(String id, int? latencyMs) {
    state = state.map((n) {
      if (n.id == id) {
        return n.copyWith(latencyMs: latencyMs);
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

  void replaceSubscriptionNodes(String subId, List<ProxyNode> newNodes) {
    final nonSubNodes = state.where((n) => n.subscriptionId != subId).toList();
    final wasEmpty = nonSubNodes.isEmpty;
    final list = List<ProxyNode>.from(nonSubNodes);
    for (int i = 0; i < newNodes.length; i++) {
      final n = newNodes[i];
      list.add(n.copyWith(isActive: wasEmpty && i == 0 ? true : n.isActive));
    }
    if (list.isNotEmpty && !list.any((n) => n.isActive)) {
      list[0].isActive = true;
    }
    state = list;
    _save();
  }

  void setActive(String id) {
    state = state.map((n) => n.copyWith(isActive: n.id == id)).toList();
    _save();
  }

  void applyIp(String nodeId, String newIp) {
    state = state.map((n) {
      if (n.id == nodeId) {
        return n.copyWith(
          originalAddress: n.originalAddress ?? n.address,
          address: newIp,
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
          originalAddress: null,
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
  SubscriptionsNotifier(this.ref) : super([]) {
    _init();
  }

  Future<void> _init() async {
    final saved = await StorageService.instance.loadSubscriptions();
    state = saved;
  }

  void _save() {
    StorageService.instance.saveSubscriptions(state);
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
      final body = await response.transform(utf8.decoder).join();
      client.close();

      final parsed = ConfigParser.parseBatch(body);
      if (parsed.isNotEmpty) {
        final tagged = parsed.map((n) => n.copyWith(subscriptionId: sub.id)).toList();
        ref.read(nodesProvider.notifier).replaceSubscriptionNodes(sub.id, tagged);
        state[idx] = sub.copyWith(
          lastUpdated: DateTime.now(),
          nodeCount: tagged.length,
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
}

final subscriptionsProvider = StateNotifierProvider<SubscriptionsNotifier, List<SubscriptionItem>>((ref) {
  return SubscriptionsNotifier(ref);
});

class ScannerState {
  final bool isScanning;
  final int total;
  final int scanned;
  final String currentIp;
  final List<ScanResult> results;
  final ScanResult? bestIp;

  ScannerState({
    this.isScanning = false,
    this.total = 0,
    this.scanned = 0,
    this.currentIp = "",
    this.results = const [],
    this.bestIp,
  });

  ScannerState copyWith({
    bool? isScanning,
    int? total,
    int? scanned,
    String? currentIp,
    List<ScanResult>? results,
    ScanResult? bestIp,
  }) {
    return ScannerState(
      isScanning: isScanning ?? this.isScanning,
      total: total ?? this.total,
      scanned: scanned ?? this.scanned,
      currentIp: currentIp ?? this.currentIp,
      results: results ?? this.results,
      bestIp: bestIp ?? this.bestIp,
    );
  }
}

class ScannerNotifier extends StateNotifier<ScannerState> {
  final Ref ref;
  ScannerNotifier(this.ref) : super(ScannerState());

  void _handleEvent(Map<String, dynamic> evt) {
    final type = evt["type"];
    final data = evt["data"] as Map<String, dynamic>? ?? {};

    if (type == "ScanStarted") {
      state = state.copyWith(
        isScanning: true,
        total: data["total"] ?? 0,
        scanned: 0,
        results: [],
        bestIp: null,
      );
    } else if (type == "ScanProgress") {
      state = state.copyWith(
        scanned: data["scanned"] ?? state.scanned,
        currentIp: data["current_ip"] ?? state.currentIp,
      );
    } else if (type == "ScanResult") {
      final res = ScanResult.fromJson(data);
      final updatedResults = [...state.results, res];
      ScanResult? newBest = state.bestIp;
      if (res.tcpSuccess && res.tlsSuccess) {
        if (newBest == null || res.rankScore < newBest.rankScore) {
          newBest = res;
        }
      }
      state = state.copyWith(results: updatedResults, bestIp: newBest);
    } else if (type == "ScanFinished" || type == "ScanCancelled") {
      state = state.copyWith(isScanning: false);
    }
  }

  void startScan({required int candidates, required int workers}) {
    final nodes = ref.read(nodesProvider);
    if (nodes.isEmpty) return;
    final activeNode = nodes.firstWhere((n) => n.isActive, orElse: () => nodes.first);

    CloudflareScannerService.instance.scanCandidates(
      candidateCount: candidates,
      workers: workers,
      targetPort: activeNode.port,
      targetSni: activeNode.sni ?? activeNode.host,
    ).listen(_handleEvent);
  }

  void cancelScan() {
    CloudflareScannerService.instance.cancel();
    state = state.copyWith(isScanning: false);
  }
}

final scannerProvider = StateNotifierProvider<ScannerNotifier, ScannerState>((ref) {
  return ScannerNotifier(ref);
});

// Default to English as requested
final currentLocaleProvider = StateProvider<String>((ref) => "en");

// Port settings provider
final httpPortProvider = StateProvider<int>((ref) => 10888);
final socksPortProvider = StateProvider<int>((ref) => 10999);
