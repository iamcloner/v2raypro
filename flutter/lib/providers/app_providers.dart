import "package:flutter_riverpod/flutter_riverpod.dart";
import "../models/proxy_node.dart";
import "../models/scan_result.dart";
import "../services/cloudflare_scanner_service.dart";
import "../services/xray_process_service.dart";

enum ConnectionStateEnum { disconnected, connecting, connected, disconnecting, error }

class ConnectionStatusNotifier extends StateNotifier<ConnectionStateEnum> {
  final Ref ref;
  ConnectionStatusNotifier(this.ref) : super(ConnectionStateEnum.disconnected);

  Future<void> toggleConnect() async {
    final nodes = ref.read(nodesProvider);
    final activeNode = nodes.firstWhere((n) => n.isActive, orElse: () => nodes.first);

    if (state == ConnectionStateEnum.disconnected || state == ConnectionStateEnum.error) {
      state = ConnectionStateEnum.connecting;
      final ok = await XrayProcessService.instance.start(activeNode);
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

class NodesNotifier extends StateNotifier<List<ProxyNode>> {
  NodesNotifier() : super([
    ProxyNode(
      id: "node-1",
      name: "Cloudflare CDN Frankfurt",
      protocol: ProtocolType.vless,
      address: "104.16.123.96",
      port: 443,
      uuidOrPassword: "b831381d-6324-4d53-ad4f-8cda48b30811",
      network: NetworkType.ws,
      security: SecurityType.tls,
      path: "/chat",
      host: "fast.cf-edge.com",
      sni: "fast.cf-edge.com",
      latencyMs: 42,
      isActive: true,
    ),
    ProxyNode(
      id: "node-2",
      name: "Direct Reality US",
      protocol: ProtocolType.vless,
      address: "172.64.88.21",
      port: 443,
      uuidOrPassword: "c928491d-5524-4d53-ad4f-8cda48b30999",
      network: NetworkType.tcp,
      security: SecurityType.reality,
      sni: "gateway.icloud.com",
      publicKey: "x8V_kM4s0_Nl792Mlz1mFk70_oX9",
      shortId: "6ba85a9a",
      latencyMs: 88,
    ),
  ]);

  void addNode(ProxyNode node) {
    state = [...state, node];
  }

  void removeNode(String id) {
    state = state.where((n) => n.id != id).toList();
  }

  void setActive(String id) {
    state = state.map((n) => n.copyWith(isActive: n.id == id)).toList();
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
  }
}

final nodesProvider = StateNotifierProvider<NodesNotifier, List<ProxyNode>>((ref) {
  return NodesNotifier();
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

final currentLocaleProvider = StateProvider<String>((ref) => "fa");
