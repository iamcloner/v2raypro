import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:v2raypro/models/dns_settings.dart';
import 'package:v2raypro/models/proxy_node.dart';
import 'package:v2raypro/providers/app_providers.dart';
import 'package:v2raypro/services/cdn_scanner_service.dart';
import 'package:v2raypro/services/xray_process_service.dart';
import 'package:v2raypro/models/traffic_stats.dart';
import 'package:v2raypro/services/free_configs_service.dart';
import 'package:v2raypro/utils/config_parser.dart';

void main() {
  group('CdnScannerService Multi-CDN Detection', () {
    test('Correctly detects Cloudflare IP ranges', () {
      expect(CdnScannerService.detectCdnHostSync('104.18.25.1'), equals(CdnProvider.cloudflare));
      expect(CdnScannerService.detectCdnHostSync('172.67.180.2'), equals(CdnProvider.cloudflare));
      expect(CdnScannerService.detectCdnHostSync('188.114.96.5'), equals(CdnProvider.cloudflare));
    });

    test('Correctly detects Fastly IP ranges', () {
      expect(CdnScannerService.detectCdnHostSync('151.101.65.140'), equals(CdnProvider.fastly));
      expect(CdnScannerService.detectCdnHostSync('199.232.0.1'), equals(CdnProvider.fastly));
    });

    test('Correctly detects AWS CloudFront IP ranges', () {
      expect(CdnScannerService.detectCdnHostSync('13.32.50.1'), equals(CdnProvider.awsCloudFront));
      expect(CdnScannerService.detectCdnHostSync('54.230.10.15'), equals(CdnProvider.awsCloudFront));
      expect(CdnScannerService.detectCdnHostSync('99.84.1.1'), equals(CdnProvider.awsCloudFront));
    });

    test('Correctly detects G-Core IP ranges', () {
      expect(CdnScannerService.detectCdnHostSync('92.223.84.10'), equals(CdnProvider.gcore));
      expect(CdnScannerService.detectCdnHostSync('92.223.120.5'), equals(CdnProvider.gcore));
    });

    test('Correctly detects ArvanCloud IP ranges', () {
      expect(CdnScannerService.detectCdnHostSync('185.143.232.10'), equals(CdnProvider.arvancloud));
      expect(CdnScannerService.detectCdnHostSync('185.143.235.250'), equals(CdnProvider.arvancloud));
      expect(CdnScannerService.detectCdnHostSync('94.182.152.50'), equals(CdnProvider.arvancloud));
    });

    test('Returns null for non-CDN IP', () {
      expect(CdnScannerService.detectCdnHostSync('8.8.8.8'), isNull);
      expect(CdnScannerService.detectCdnHostSync('1.1.1.1'), equals(CdnProvider.cloudflare));
      expect(CdnScannerService.detectCdnHostSync('127.0.0.1'), isNull);
    });

    test('Generates random candidate IPs within selected CDN CIDRs', () {
      for (final provider in CdnProvider.values) {
        final candidates = CdnScannerService.generateCandidateIps(
          cdn: provider,
          count: 20,
        );
        expect(candidates.length, equals(20));
        for (final ip in candidates) {
          final detected = CdnScannerService.detectCdnHostSync(ip);
          expect(detected, equals(provider), reason: 'Candidate $ip should belong to ${provider.displayName}');
        }
      }
    });
  });

  group('Domain Node Host & SNI Preservation', () {
    test('applyIp preserves host and sni when originalAddress is a domain', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final domainNode = ProxyNode(
        id: 'test-domain-node',
        name: 'CDN Vless Domain',
        protocol: ProtocolType.vless,
        address: 'my-cdn-server.example.com',
        port: 443,
        uuidOrPassword: '00000000-0000-0000-0000-000000000000',
        network: NetworkType.ws,
        security: SecurityType.tls,
      );

      container.read(nodesProvider.notifier).addNode(domainNode);

      // Apply clean IP
      const cleanIp = '104.18.22.33';
      container.read(nodesProvider.notifier).applyIp(domainNode.id, cleanIp);

      final updatedNode = container.read(nodesProvider).firstWhere((n) => n.id == domainNode.id);
      expect(updatedNode.address, equals(cleanIp));
      expect(updatedNode.originalAddress, equals('my-cdn-server.example.com'));
      expect(updatedNode.host, equals('my-cdn-server.example.com'));
      expect(updatedNode.sni, equals('my-cdn-server.example.com'));

      // Restore original
      container.read(nodesProvider.notifier).restoreAddress(domainNode.id);
      final restoredNode = container.read(nodesProvider).firstWhere((n) => n.id == domainNode.id);
      expect(restoredNode.address, equals('my-cdn-server.example.com'));
      expect(restoredNode.originalAddress, isNull);
    });

    test('applyIp keeps pre-existing host and sni if already set', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final customSniNode = ProxyNode(
        id: 'test-custom-sni',
        name: 'CDN Node Custom SNI',
        protocol: ProtocolType.vless,
        address: '104.18.1.1',
        port: 443,
        uuidOrPassword: '00000000-0000-0000-0000-000000000000',
        network: NetworkType.ws,
        security: SecurityType.tls,
        host: 'custom-host.org',
        sni: 'custom-sni.org',
      );

      container.read(nodesProvider.notifier).addNode(customSniNode);
      container.read(nodesProvider.notifier).applyIp(customSniNode.id, '104.18.99.100');

      final updated = container.read(nodesProvider).firstWhere((n) => n.id == customSniNode.id);
      expect(updated.address, equals('104.18.99.100'));
      expect(updated.host, equals('custom-host.org'));
      expect(updated.sni, equals('custom-sni.org'));
    });
  });

  group('DnsSettings & Xray Config Generation', () {
    test('DnsSettings JSON serialization roundtrip', () {
      const original = DnsSettings(
        presetId: 'custom',
        servers: ['1.1.1.1', '8.8.8.8', 'https://dns.google/dns-query'],
      );

      final jsonMap = original.toJson();
      final recovered = DnsSettings.fromJson(jsonMap);

      expect(recovered.presetId, equals(original.presetId));
      expect(recovered.servers, equals(original.servers));
    });

    test('All presets have non-empty server lists', () {
      for (final p in DnsSettings.presets) {
        if (p.id != 'custom') {
          expect(p.servers, isNotEmpty);
          for (final s in p.servers) {
            expect(s.trim(), isNotEmpty);
          }
        }
      }
    });

    test('Xray config uses configured DNS servers and filters DoH for TUN', () {
      final node = ProxyNode(
        id: 'test-node-dns',
        name: 'Test Node',
        protocol: ProtocolType.vless,
        address: '104.18.1.1',
        port: 443,
        uuidOrPassword: '00000000-0000-0000-0000-000000000000',
        network: NetworkType.ws,
        security: SecurityType.tls,
      );

      XrayProcessService.instance.dnsServers = [
        '1.1.1.1',
        '8.8.8.8',
        'https://1.1.1.1/dns-query',
      ];

      final config = XrayProcessService.instance.generateXrayConfig(
        node,
        enableTun: true,
      );

      // Root DNS should contain all servers including DoH
      final dnsBlock = config['dns'] as Map<String, dynamic>;
      final servers = dnsBlock['servers'] as List<dynamic>;
      expect(servers, contains('https://1.1.1.1/dns-query'));
      expect(servers, contains('1.1.1.1'));
      expect(servers, contains('8.8.8.8'));

      // TUN inbound settings should filter out DoH URLs
      final inbounds = (config['inbounds'] as List<dynamic>).cast<Map<String, dynamic>>();
      final tunInbound = inbounds.firstWhere(
        (i) => i['tag'] == 'tun-in',
        orElse: () => <String, dynamic>{},
      );
      expect(tunInbound.isNotEmpty, isTrue);
      final tunDns = (tunInbound['settings']?['dns'] as List<dynamic>?)?.cast<String>();
      expect(tunDns, isNotNull);
      expect(tunDns!.any((d) => d.startsWith('http')), isFalse);
      expect(tunDns, contains('1.1.1.1'));
      expect(tunDns, contains('8.8.8.8'));
    });
  });

  group('Large Config & Performance Benchmarks', () {
    test('ConfigParser.parseBatchAsync parses 500 links smoothly without blocking', () async {
      final buffer = StringBuffer();
      for (int i = 0; i < 500; i++) {
        buffer.writeln('vless://user$i@1.1.1.${i % 250}:443?type=tcp&security=none#node_$i');
      }

      final sw = Stopwatch()..start();
      final nodes = await ConfigParser.parseBatchAsync(buffer.toString());
      sw.stop();

      expect(nodes.length, 500);
      expect(nodes.first.name, 'node_0');
      expect(nodes.last.name, 'node_499');
      expect(sw.elapsedMilliseconds, lessThan(3000));
    });

    test('replaceSubscriptionNodes scales linearly O(N) with 1,000 nodes', () {
      final container = ProviderContainer();
      final notifier = container.read(nodesProvider.notifier);

      final existing = <ProxyNode>[];
      for (int i = 0; i < 1000; i++) {
        existing.add(ProxyNode(
          id: 'old_$i',
          name: 'Old $i',
          protocol: ProtocolType.vless,
          address: '1.2.3.${i % 250}',
          port: 443,
          uuidOrPassword: 'uuid_$i',
          subscriptionId: 'sub_test',
          latencyMs: 50 + (i % 100),
        ));
      }
      notifier.addNodes(existing);

      final incoming = <ProxyNode>[];
      for (int i = 0; i < 1000; i++) {
        incoming.add(ProxyNode(
          id: 'incoming_$i',
          name: 'Updated $i',
          protocol: ProtocolType.vless,
          address: '1.2.3.${i % 250}',
          port: 443,
          uuidOrPassword: 'uuid_$i',
        ));
      }

      final sw = Stopwatch()..start();
      notifier.replaceSubscriptionNodes('sub_test', incoming);
      sw.stop();

      final currentNodes = container.read(nodesProvider);
      expect(currentNodes.length, 1000);
      expect(currentNodes.first.latencyMs, isNotNull);
      expect(currentNodes.first.id, 'old_0');
      expect(sw.elapsedMilliseconds, lessThan(1000));
    });

    test('updateLatenciesBatch updates multiple nodes in one atomic operation', () {
      final container = ProviderContainer();
      final notifier = container.read(nodesProvider.notifier);

      final nodes = [
        ProxyNode(id: 'n1', name: 'N1', protocol: ProtocolType.vless, address: '1.1.1.1', port: 443, uuidOrPassword: 'u1'),
        ProxyNode(id: 'n2', name: 'N2', protocol: ProtocolType.vless, address: '1.1.1.2', port: 443, uuidOrPassword: 'u2'),
        ProxyNode(id: 'n3', name: 'N3', protocol: ProtocolType.vless, address: '1.1.1.3', port: 443, uuidOrPassword: 'u3'),
      ];
      notifier.addNodes(nodes);

      notifier.updateLatenciesBatch({
        'n1': 45,
        'n2': 120,
        'n3': null,
      });

      final updated = container.read(nodesProvider);
      expect(updated.firstWhere((n) => n.id == 'n1').latencyMs, 45);
      expect(updated.firstWhere((n) => n.id == 'n2').latencyMs, 120);
      expect(updated.firstWhere((n) => n.id == 'n3').latencyMs, isNull);
    });
  });

  group('CDN Badges and Dynamic Scanner UI', () {
    test('All CdnProvider enum values have non-empty displayName and displayNameFa', () {
      for (final cdn in CdnProvider.values) {
        expect(cdn.displayName.isNotEmpty, isTrue);
        expect(cdn.displayNameFa.isNotEmpty, isTrue);
      }
    });

    test('Scanner title dynamically formats correctly for English and Persian', () {
      for (final cdn in CdnProvider.values) {
        final enTitle = '${cdn.displayName} Scanner';
        final faTitle = 'اسکنر ${cdn.displayNameFa}';

        expect(enTitle, contains(cdn.displayName));
        expect(faTitle, contains('اسکنر'));
        expect(faTitle, contains(cdn.displayNameFa));
      }

      // Explicit check for user-mentioned Fastly
      expect('Fastly Scanner', equals('${CdnProvider.fastly.displayName} Scanner'));
      expect('اسکنر فستلی', equals('اسکنر ${CdnProvider.fastly.displayNameFa}'));
    });
  });

  group('TrafficStats & Live Metrics', () {
    test('formatBytes handles zero and negative numbers', () {
      expect(TrafficStats.formatBytes(0), equals('0.0 B'));
      expect(TrafficStats.formatBytes(-5), equals('0.0 B'));
    });

    test('formatBytes formats units correctly', () {
      expect(TrafficStats.formatBytes(500), equals('500.0 B'));
      expect(TrafficStats.formatBytes(1024), equals('1.0 KB'));
      expect(TrafficStats.formatBytes(1536), equals('1.5 KB'));
      expect(TrafficStats.formatBytes(1024 * 1024), equals('1.0 MB'));
      expect(TrafficStats.formatBytes((12.4 * 1024 * 1024).round()), equals('12.4 MB'));
      expect(TrafficStats.formatBytes(1024 * 1024 * 1024), equals('1.00 GB'));
    });

    test('TrafficStats stores downlink and uplink and computes total', () {
      const stats = TrafficStats(downlinkBytes: 2048, uplinkBytes: 1024);
      expect(stats.downlinkBytes, 2048);
      expect(stats.uplinkBytes, 1024);
      expect(stats.totalBytes, 3072);
      expect(stats.formattedDownlink, '2.0 KB');
      expect(stats.formattedUplink, '1.0 KB');
      expect(stats.formattedTotal, '3.0 KB');
    });

    test('TrafficStatsNotifier updates and resets correctly', () {
      final notifier = TrafficStatsNotifier();
      expect(notifier.state.downlinkBytes, 0);
      expect(notifier.state.uplinkBytes, 0);

      notifier.update(const TrafficStats(downlinkBytes: 5242880, uplinkBytes: 1048576));
      expect(notifier.state.formattedDownlink, '5.0 MB');
      expect(notifier.state.formattedUplink, '1.0 MB');

      notifier.reset();
      expect(notifier.state.downlinkBytes, 0);
      expect(notifier.state.uplinkBytes, 0);
    });
  });

  group('Dead Configs & Timeout Detection & Deletion', () {
    test('ProxyNode accurately identifies working, untested, and timed-out states', () {
      final untested = ProxyNode(
        id: 'u1',
        name: 'Untested Node',
        protocol: ProtocolType.vless,
        address: '1.1.1.1',
        port: 443,
        uuidOrPassword: 'id',
      );
      expect(untested.isUntested, isTrue);
      expect(untested.hasValidPing, isFalse);
      expect(untested.hasTimedOut, isFalse);

      final working = untested.copyWith(
        latencyMs: 145,
        lastTestedAt: DateTime.now(),
      );
      expect(working.isUntested, isFalse);
      expect(working.hasValidPing, isTrue);
      expect(working.hasTimedOut, isFalse);
      expect(working.latencyMs, 145);

      final timedOut = working.copyWith(
        latencyMs: null,
        lastTestedAt: DateTime.now(),
      );
      expect(timedOut.isUntested, isFalse);
      expect(timedOut.hasValidPing, isFalse);
      expect(timedOut.hasTimedOut, isTrue);
      expect(timedOut.latencyMs, isNull);
    });

    test('copyWith preserves existing latency when not passed, and clears when null', () {
      final nodeWithPing = ProxyNode(
        id: 'p1',
        name: 'Node with ping',
        protocol: ProtocolType.vless,
        address: '1.1.1.1',
        port: 443,
        uuidOrPassword: 'id',
        latencyMs: 80,
      );

      // Preserved when not passed
      final renamed = nodeWithPing.copyWith(name: 'Renamed Node');
      expect(renamed.latencyMs, 80);

      // Cleared when explicitly null
      final cleared = nodeWithPing.copyWith(latencyMs: null);
      expect(cleared.latencyMs, isNull);

      // Cleared when clearLatency is true
      final cleared2 = nodeWithPing.copyWith(clearLatency: true);
      expect(cleared2.latencyMs, isNull);
    });

    test('NodesNotifier.removeDeadNodes deletes only timed-out nodes and leaves valid ones', () {
      final container = ProviderContainer();
      final notifier = container.read(nodesProvider.notifier);

      final now = DateTime.now();
      final nodes = [
        ProxyNode(id: 'w1', name: 'Working 1', protocol: ProtocolType.vless, address: '1.1.1.1', port: 443, uuidOrPassword: 'u', latencyMs: 60, lastTestedAt: now),
        ProxyNode(id: 't1', name: 'TimedOut 1', protocol: ProtocolType.vless, address: '1.1.1.2', port: 443, uuidOrPassword: 'u', latencyMs: null, lastTestedAt: now),
        ProxyNode(id: 'u1', name: 'Untested 1', protocol: ProtocolType.vless, address: '1.1.1.3', port: 443, uuidOrPassword: 'u'),
        ProxyNode(id: 't2', name: 'TimedOut 2', protocol: ProtocolType.vless, address: '1.1.1.4', port: 443, uuidOrPassword: 'u', latencyMs: null, lastTestedAt: now),
      ];
      notifier.addNodes(nodes);

      expect(container.read(nodesProvider).length, 4);

      final removedCount = notifier.removeDeadNodes();
      expect(removedCount, 2);

      final remaining = container.read(nodesProvider);
      expect(remaining.length, 2);
      expect(remaining.any((n) => n.id == 'w1'), isTrue);
      expect(remaining.any((n) => n.id == 'u1'), isTrue);
      expect(remaining.any((n) => n.id == 't1'), isFalse);
      expect(remaining.any((n) => n.id == 't2'), isFalse);
    });

    test('NodesNotifier.removeDeadNodes can filter by subscriptionId or onlyCustom', () {
      final container = ProviderContainer();
      final notifier = container.read(nodesProvider.notifier);

      final now = DateTime.now();
      final nodes = [
        ProxyNode(id: 'c_dead', name: 'Custom Dead', protocol: ProtocolType.vless, address: '1.1.1.1', port: 443, uuidOrPassword: 'u', latencyMs: null, lastTestedAt: now),
        ProxyNode(id: 's_dead', name: 'Sub Dead', protocol: ProtocolType.vless, address: '1.1.1.2', port: 443, uuidOrPassword: 'u', subscriptionId: 'sub_a', latencyMs: null, lastTestedAt: now),
      ];
      notifier.addNodes(nodes);

      // Only custom
      final removedCustom = notifier.removeDeadNodes(onlyCustom: true);
      expect(removedCustom, 1);
      expect(container.read(nodesProvider).any((n) => n.id == 'c_dead'), isFalse);
      expect(container.read(nodesProvider).any((n) => n.id == 's_dead'), isTrue);

      // Subscription specific
      final removedSub = notifier.removeDeadNodes(subscriptionId: 'sub_a');
      expect(removedSub, 1);
      expect(container.read(nodesProvider).isEmpty, isTrue);
    });
  });

  group('FreeConfigsService Logic', () {
    test('Contains all 9 specified subscription sources', () {
      expect(FreeConfigsService.defaultSubUrls.length, equals(9));
      expect(FreeConfigsService.defaultSubUrls, contains('https://raw.githubusercontent.com/iboxz/free-v2ray-collector/main/main/mix.txt'));
      expect(FreeConfigsService.defaultSubUrls, contains('https://raw.githubusercontent.com/youfoundamin/V2rayCollector/main/vless_iran.txt'));
      expect(FreeConfigsService.defaultSubUrls, contains('https://raw.githubusercontent.com/Kwinshadow/TelegramV2rayCollector/main/sublinks/mix.txt'));
      expect(FreeConfigsService.defaultSubUrls, contains('https://raw.githubusercontent.com/youfoundamin/V2rayCollector/main/vmess_iran.txt'));
      expect(FreeConfigsService.defaultSubUrls, contains('https://raw.githubusercontent.com/youfoundamin/V2rayCollector/main/ss_iran.txt'));
      expect(FreeConfigsService.defaultSubUrls, contains('https://raw.githubusercontent.com/youfoundamin/V2rayCollector/main/trojan_iran.txt'));
      expect(FreeConfigsService.defaultSubUrls, contains('https://raw.githubusercontent.com/youfoundamin/V2rayCollector/main/mixed_iran.txt'));
      expect(FreeConfigsService.defaultSubUrls, contains('https://raw.githubusercontent.com/mohamadfg-dev/telegram-v2ray-configs-collector/refs/heads/main/category/trojan.txt'));
      expect(FreeConfigsService.defaultSubUrls, contains('https://raw.githubusercontent.com/MahanKenway/Freedom-V2Ray/main/configs/mix_sub.txt'));
    });

    test('makeConfigKey correctly deduplicates configurations with identical endpoint parameters', () {
      final n1 = ProxyNode(
        id: '1',
        name: 'Config A (from Sub 1)',
        protocol: ProtocolType.vless,
        address: '104.18.22.1',
        port: 443,
        uuidOrPassword: 'test-uuid-1234',
        network: NetworkType.ws,
        path: '/vless-ws',
      );

      final n2 = ProxyNode(
        id: '2',
        name: 'Config B (from Sub 2 with different title)',
        protocol: ProtocolType.vless,
        address: '104.18.22.1',
        port: 443,
        uuidOrPassword: 'test-uuid-1234',
        network: NetworkType.ws,
        path: '/vless-ws',
      );

      final n3 = ProxyNode(
        id: '3',
        name: 'Config C (different port)',
        protocol: ProtocolType.vless,
        address: '104.18.22.1',
        port: 8443,
        uuidOrPassword: 'test-uuid-1234',
        network: NetworkType.ws,
        path: '/vless-ws',
      );

      expect(FreeConfigsService.makeConfigKey(n1), equals(FreeConfigsService.makeConfigKey(n2)));
      expect(FreeConfigsService.makeConfigKey(n1), isNot(equals(FreeConfigsService.makeConfigKey(n3))));
    });

    test('NodesNotifier.selectAndConnectFreeNode activates the free node properly', () {
      final container = ProviderContainer();
      final notifier = container.read(nodesProvider.notifier);

      final freeNode = ProxyNode(
        id: 'free_1',
        name: 'Free Fast Node',
        protocol: ProtocolType.vless,
        address: '104.18.1.1',
        port: 443,
        uuidOrPassword: 'uuid',
        latencyMs: 95,
      );

      notifier.selectAndConnectFreeNode(freeNode);

      final nodes = container.read(nodesProvider);
      expect(nodes.length, 1);
      expect(nodes.first.id, 'free_1');
      expect(nodes.first.isActive, isTrue);

      final secondFreeNode = ProxyNode(
        id: 'free_2',
        name: 'Free Second Node',
        protocol: ProtocolType.vmess,
        address: '104.18.2.2',
        port: 443,
        uuidOrPassword: 'uuid2',
        latencyMs: 110,
      );

      notifier.selectAndConnectFreeNode(secondFreeNode);
      final nodesAfterSecond = container.read(nodesProvider);
      final active = nodesAfterSecond.firstWhere((n) => n.isActive);
      expect(active.id, 'free_2');
      final first = nodesAfterSecond.firstWhere((n) => n.id == 'free_1');
      expect(first.isActive, isFalse);
    });
  });
}


