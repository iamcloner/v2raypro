import "dart:async";
import "dart:convert";
import "dart:io";
import "dart:math";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "../models/proxy_node.dart";
import "../models/scan_result.dart";
import "../models/subscription_item.dart";
import "../models/log_entry.dart";
import "../models/outbound_info.dart";
import "../services/cloudflare_scanner_service.dart";
import "../services/log_service.dart";
import "../services/storage_service.dart";
import "../services/tray_service.dart";
import "../services/xray_process_service.dart";
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
    state = ConnectionStateEnum.disconnected;
    AppTrayService.instance.updateTrayMenu();
  }

  Future<void> _testPing() async {
    final nodes = ref.read(nodesProvider);
    if (nodes.isEmpty) return;
    final active = nodes.firstWhere((n) => n.isActive, orElse: () => nodes.first);
    final lat = await XrayProcessService.instance.testNodeLatency(active);
    if (lat != null) {
      ref.read(nodesProvider.notifier).updateLatency(active.id, lat);
    }
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

  void updateLatency(String id, int? latencyMs) {
    state = state.map((n) {
      if (n.id == id) {
        return n.copyWith(latencyMs: latencyMs, lastTestedAt: DateTime.now());
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
    final oldSubNodes = state.where((n) => n.subscriptionId == subId).toList();
    final nonSubNodes = state.where((n) => n.subscriptionId != subId).toList();

    bool isSameConfig(ProxyNode a, ProxyNode b) {
      return a.protocol == b.protocol &&
          a.address.trim().toLowerCase() == b.address.trim().toLowerCase() &&
          a.port == b.port &&
          a.uuidOrPassword.trim() == b.uuidOrPassword.trim() &&
          a.network == b.network &&
          (a.path ?? '').trim() == (b.path ?? '').trim();
    }

    final updatedSubNodes = <ProxyNode>[];
    final usedOldNodes = <ProxyNode>{};

    for (final newNode in newNodes) {
      ProxyNode? match;
      for (final old in oldSubNodes) {
        if (!usedOldNodes.contains(old) && isSameConfig(old, newNode)) {
          match = old;
          usedOldNodes.add(old);
          break;
        }
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

      final parsed = ConfigParser.parseBatch(body);

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
    final customCidrs = ref.read(cfRangesProvider);

    _isCancelled = false;
    _hasWarnedRadarTraffic = false;
    final strategy = state.strategy;
    final workers = state.workers;

    if (strategy == ScannerStrategy.radar) {
      // RADAR MODE: Infinite & continuous scan across all Cloudflare ranges
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
        final chunk = CloudflareScannerService.generateCandidateIps(
          count: workers,
          cidrs: customCidrs,
          rng: rng,
        );

        final futures = chunk.map((ip) async {
          final candidateNode = activeNode.copyWith(address: ip);
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
                "[Radar] Discovered new best Cloudflare IP: $ip (${lat}ms)${improvement != null ? ' - improved by ${improvement}ms' : ''}",
                level: LogLevel.access,
                source: "scanner",
              );
              ref.read(nodesProvider.notifier).applyIp(activeNode.id, ip);

              // Connect or hot-switch Xray connection
              final connState = ref.read(connectionStatusProvider);
              if (connState == ConnectionStateEnum.connected) {
                await XrayProcessService.instance.stop();
                await XrayProcessService.instance.start(
                  activeNode.copyWith(address: ip),
                  enableTun: ref.read(isTunEnabledProvider),
                  setSysProxy: ref.read(isSystemProxyEnabledProvider),
                );
              } else {
                final ok = await XrayProcessService.instance.start(
                  activeNode.copyWith(address: ip),
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
                "[Radar] Discovered responsive Cloudflare IP: $ip (${lat}ms)",
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
      final candidates = CloudflareScannerService.generateCandidateIps(
        count: totalCount,
        cidrs: customCidrs,
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
          final candidateNode = activeNode.copyWith(address: ip);
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

    final connState = ref.read(connectionStatusProvider);
    if (connState == ConnectionStateEnum.connected) {
      await XrayProcessService.instance.stop();
      await XrayProcessService.instance.start(
        activeNode.copyWith(address: ip),
        enableTun: ref.read(isTunEnabledProvider),
        setSysProxy: ref.read(isSystemProxyEnabledProvider),
      );
    } else {
      final ok = await XrayProcessService.instance.start(
        activeNode.copyWith(address: ip),
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

class CloudflareRangesNotifier extends StateNotifier<List<String>> {
  CloudflareRangesNotifier() : super(CloudflareScannerService.defaultCidrs) {
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
    StorageService.instance.saveCloudflareRanges(ranges);
  }

  void resetToDefault() {
    state = CloudflareScannerService.defaultCidrs;
    StorageService.instance.saveCloudflareRanges(CloudflareScannerService.defaultCidrs);
  }
}

final cfRangesProvider = StateNotifierProvider<CloudflareRangesNotifier, List<String>>((ref) {
  return CloudflareRangesNotifier();
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

class CfCheckedHostsNotifier extends StateNotifier<Map<String, bool>> {
  final Ref ref;
  CfCheckedHostsNotifier(this.ref) : super({});

  bool isCloudflare(String address) {
    final addr = address.trim().toLowerCase();
    if (state.containsKey(addr)) return state[addr]!;
    final cfRanges = ref.read(cfRangesProvider);
    final isCf = CloudflareScannerService.isCloudflareHostSync(addr, cfRanges);
    state = {...state, addr: isCf};
    if (!isCf && !addr.contains(RegExp(r'^\d+\.\d+\.\d+\.\d+$'))) {
      CloudflareScannerService.resolveAndCheckCloudflare(addr, cfRanges).then((resolvedIsCf) {
        if (resolvedIsCf) {
          state = {...state, addr: true};
        }
      });
    }
    return isCf;
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


