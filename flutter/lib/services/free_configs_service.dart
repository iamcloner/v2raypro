import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import '../models/proxy_node.dart';
import '../utils/config_parser.dart';
import 'storage_service.dart';
import 'xray_process_service.dart';
import 'country_service.dart';

class FreeConfigsScanProgress {
  final int totalScraped;
  final int totalUnique;
  final int testedCandidates;
  final int workingFound;
  final int targetWorking;
  final String status;
  final List<ProxyNode> workingNodes;
  final List<ProxyNode> timeoutNodes;
  final bool isCompleted;
  final String? estimatedRemainingTime;

  int get failedCount => (testedCandidates - workingFound).clamp(0, testedCandidates);

  const FreeConfigsScanProgress({
    this.totalScraped = 0,
    this.totalUnique = 0,
    this.testedCandidates = 0,
    this.workingFound = 0,
    this.targetWorking = 30,
    this.status = '',
    this.workingNodes = const [],
    this.timeoutNodes = const [],
    this.isCompleted = false,
    this.estimatedRemainingTime,
  });
}

class FreeConfigsService {
  static final FreeConfigsService instance = FreeConfigsService._internal();
  FreeConfigsService._internal();

  static const List<String> defaultSubUrls = [
    'https://raw.githubusercontent.com/iboxz/free-v2ray-collector/main/main/mix.txt',
    'https://raw.githubusercontent.com/youfoundamin/V2rayCollector/main/vless_iran.txt',
    'https://raw.githubusercontent.com/Kwinshadow/TelegramV2rayCollector/main/sublinks/mix.txt',
    'https://raw.githubusercontent.com/youfoundamin/V2rayCollector/main/vmess_iran.txt',
    'https://raw.githubusercontent.com/youfoundamin/V2rayCollector/main/ss_iran.txt',
    'https://raw.githubusercontent.com/youfoundamin/V2rayCollector/main/trojan_iran.txt',
    'https://raw.githubusercontent.com/youfoundamin/V2rayCollector/main/mixed_iran.txt',
    'https://raw.githubusercontent.com/mohamadfg-dev/telegram-v2ray-configs-collector/refs/heads/main/category/trojan.txt',
    'https://raw.githubusercontent.com/MahanKenway/Freedom-V2Ray/main/configs/mix_sub.txt',
  ];

  bool _isCancelled = false;
  bool _isScanning = false;
  final List<HttpClient> _activeClients = [];

  bool get isScanning => _isScanning;

  void cancel() {
    _isCancelled = true;
    for (final c in _activeClients) {
      try {
        c.close(force: true);
      } catch (_) {}
    }
    _activeClients.clear();
  }

  /// Generate a deduplication key based on protocol and network endpoints
  static String makeConfigKey(ProxyNode n) {
    return "${n.protocol.name}|${n.address.trim().toLowerCase()}|${n.port}|${n.uuidOrPassword.trim()}|${n.network.name}|${(n.path ?? '').trim()}";
  }

  /// Fetch from free subscription links, deduplicate, shuffle, and test with 10 concurrency streaming
  Future<List<ProxyNode>> fetchAndScan({
    void Function(FreeConfigsScanProgress)? onProgress,
    int targetWorking = 30,
    int concurrency = 10,
    int batchSize = 10,
    Random? rng,
  }) async {
    if (_isScanning) {
      // If a previous scan is still terminating, wait up to 2s for it to finish cleanly
      _isCancelled = true;
      int waited = 0;
      while (_isScanning && waited < 40) {
        await Future.delayed(const Duration(milliseconds: 50));
        waited++;
      }
      if (_isScanning) {
        _isScanning = false;
      }
    }

    _isScanning = true;
    _isCancelled = false;
    _activeClients.clear();

    final workingNodes = <ProxyNode>[];
    final timeoutNodes = <ProxyNode>[];

    try {
      onProgress?.call(const FreeConfigsScanProgress(
        status: 'fetching',
        targetWorking: 30,
      ));

      // 1. Fetch all subscription URLs concurrently
      final fetchTasks = defaultSubUrls.map((url) async {
        if (_isCancelled) return '';
        HttpClient? client;
        try {
          client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
          _activeClients.add(client);
          final req = await client.getUrl(Uri.parse(url));
          req.headers.set('User-Agent', 'v2rayN/6.42');
          final resp = await req.close().timeout(const Duration(seconds: 10));
          if (resp.statusCode == 200) {
            final body = await resp.transform(utf8.decoder).join();
            return body;
          }
        } catch (_) {
        } finally {
          if (client != null) {
            _activeClients.remove(client);
            try { client.close(); } catch (_) {}
          }
        }
        return '';
      });

      final rawBodies = await Future.wait(fetchTasks);
      if (_isCancelled) return [];

      // 2. Pre-filter raw lines using a Set to instantly drop duplicate URIs
      final rawLinesSet = <String>{};
      for (final body in rawBodies) {
        if (body.isEmpty) continue;
        final lines = body.split(RegExp(r'[\r\n]+'));
        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.isNotEmpty) {
            rawLinesSet.add(trimmed);
          }
        }
      }

      final totalScraped = rawLinesSet.length;
      if (totalScraped == 0 || _isCancelled) {
        _isScanning = false;
        onProgress?.call(const FreeConfigsScanProgress(
          status: 'failed',
          isCompleted: true,
        ));
        return [];
      }

      onProgress?.call(FreeConfigsScanProgress(
        totalScraped: totalScraped,
        status: 'parsing',
        targetWorking: targetWorking,
      ));

      // 3. Parse in background isolate
      final parsed = await ConfigParser.parseBatchAsync(rawLinesSet.join('\n'));
      if (_isCancelled) return [];

      // 4. Endpoint-level de-duplication & structural validation
      final seenKeys = <String>{};
      final uniqueNodes = <ProxyNode>[];
      for (final node in parsed) {
        if (!XrayProcessService.instance.isNodeConfigSupported(node)) continue;
        final key = makeConfigKey(node);
        if (seenKeys.add(key)) {
          uniqueNodes.add(node.copyWith(subscriptionId: 'free_configs'));
        }
      }

      final totalUnique = uniqueNodes.length;

      // 5. Shuffle unique nodes
      final random = rng ?? Random();
      uniqueNodes.shuffle(random);

      onProgress?.call(FreeConfigsScanProgress(
        totalScraped: totalScraped,
        totalUnique: totalUnique,
        status: 'testing',
        targetWorking: targetWorking,
      ));

      // 6. Test all unique nodes with 10 concurrent workers (streaming updates on each node)
      int currentIndex = 0;
      int testedCount = 0;
      final testStartTime = DateTime.now();

      Future<void> runWorker() async {
        while (currentIndex < uniqueNodes.length && !_isCancelled) {
          final nodeIndex = currentIndex++;
          if (nodeIndex >= uniqueNodes.length) break;
          final node = uniqueNodes[nodeIndex];

          final res = await XrayProcessService.instance.testNodeRealDelay(
            node,
            timeout: const Duration(milliseconds: 2800),
          );
          if (_isCancelled) break;

          testedCount++;

          if (res.isSuccess) {
            final testedNode = node.copyWith(
              latencyMs: res.latencyMs,
              countryCode: res.countryCode,
              country: res.country,
              lastTestedAt: DateTime.now(),
            );
            workingNodes.add(testedNode);
            workingNodes.sort((a, b) => a.latencyMs!.compareTo(b.latencyMs!));
            // Immediate persistence of discovered working nodes
            StorageService.instance.saveFreeConfigs(workingNodes);
          } else {
            final deadNode = node.copyWith(
              latencyMs: -1,
              lastTestedAt: DateTime.now(),
            );
            timeoutNodes.add(deadNode);
          }

          String? etaStr;
          if (totalUnique > 50 && testedCount > 0 && testedCount < totalUnique) {
            final elapsed = DateTime.now().difference(testStartTime);
            final avgPerNode = elapsed.inMilliseconds / testedCount;
            final remainingMs = (avgPerNode * (totalUnique - testedCount)).round();
            final remSeconds = (remainingMs / 1000).round();
            final minutes = remSeconds ~/ 60;
            final seconds = remSeconds % 60;
            etaStr = '~${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
          }

          // Trigger onProgress immediately for every single node tested
          onProgress?.call(FreeConfigsScanProgress(
            totalScraped: totalScraped,
            totalUnique: totalUnique,
            testedCandidates: testedCount,
            workingFound: workingNodes.length,
            status: testedCount >= totalUnique ? 'completed' : 'testing',
            workingNodes: List.unmodifiable(workingNodes),
            timeoutNodes: List.unmodifiable(timeoutNodes),
            isCompleted: testedCount >= totalUnique,
            estimatedRemainingTime: etaStr,
          ));
        }
      }

      final workerCount = min(concurrency, uniqueNodes.length);
      final workers = List.generate(workerCount, (_) => runWorker());
      await Future.wait(workers);

      if (_isCancelled) return workingNodes;

      // Persist the found working nodes
      if (workingNodes.isNotEmpty) {
        await StorageService.instance.saveFreeConfigs(workingNodes);
      }

      onProgress?.call(FreeConfigsScanProgress(
        totalScraped: totalScraped,
        totalUnique: totalUnique,
        testedCandidates: testedCount,
        workingFound: workingNodes.length,
        status: 'completed',
        workingNodes: List.unmodifiable(workingNodes),
        timeoutNodes: List.unmodifiable(timeoutNodes),
        isCompleted: true,
      ));

      return workingNodes;
    } finally {
      _isScanning = false;
      _activeClients.clear();
    }
  }
}
