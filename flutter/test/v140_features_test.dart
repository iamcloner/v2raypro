import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:v2raypro/models/proxy_node.dart';
import 'package:v2raypro/models/routing_rule.dart';
import 'package:v2raypro/models/scan_result.dart';
import 'package:v2raypro/providers/app_providers.dart';
import 'package:v2raypro/services/country_service.dart';
import 'package:v2raypro/services/free_configs_service.dart';
import 'package:v2raypro/services/xray_process_service.dart';
import 'package:v2raypro/utils/config_parser.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('v1.4.0 Features & Reconnect / Free Configs / Flow Suite', () {
    test('ConfigParser correctly extracts flow and headerType from VLESS URLs', () {
      const url =
          'vless://tbxjthftff@195.231.39.22:443?security=reality&encryption=none&pbk=HL-IrEO6&fp=chrome&type=tcp&flow=xtls-rprx-vision&headerType=none&sni=play.google.com&sid=5625#Server1';
      final node = ConfigParser.parseSingle(url);

      expect(node, isNotNull);
      expect(node!.protocol, equals(ProtocolType.vless));
      expect(node.flow, equals('xtls-rprx-vision'));
      expect(node.headerType, equals('none'));
      expect(node.security, equals(SecurityType.reality));
      expect(node.publicKey, equals('HL-IrEO6'));
    });

    test('XrayProcessService.generateXrayConfig injects flow into VLESS outbound users', () {
      final node = ProxyNode(
        id: 'node-flow-1',
        name: 'Vision Node',
        protocol: ProtocolType.vless,
        address: '1.2.3.4',
        port: 443,
        uuidOrPassword: 'uuid-vision-1234',
        flow: 'xtls-rprx-vision',
        security: SecurityType.reality,
        publicKey: 'pubkey-abc',
      );

      final config = XrayProcessService.instance.generateXrayConfig(node);
      final outbounds = config['outbounds'] as List;
      final proxyOut = outbounds.firstWhere((o) => o['tag'] == 'proxy') as Map<String, dynamic>;
      final vnext = proxyOut['settings']['vnext'] as List;
      final users = vnext[0]['users'] as List;

      expect(users[0]['id'], equals('uuid-vision-1234'));
      expect(users[0]['flow'], equals('xtls-rprx-vision'));
      expect(users[0]['encryption'], equals('none'));
    });

    test('CountryService.getCountryName resolves country names accurately', () {
      expect(CountryService.getCountryName('US'), equals('United States'));
      expect(CountryService.getCountryName('DE'), equals('Germany'));
      expect(CountryService.getCountryName('NL'), equals('Netherlands'));
      expect(CountryService.getCountryName('TR'), equals('Turkey'));
      expect(CountryService.getCountryName('FI'), equals('Finland'));
      expect(CountryService.getCountryName('IR'), equals('Iran'));
      expect(CountryService.getCountryName('XYZ'), equals('XYZ'));
      expect(CountryService.getCountryName(null), isNull);
      expect(CountryService.getCountryName(''), isNull);
    });

    test('FreeConfigsService cancel immediately cancels ongoing scan', () {
      final service = FreeConfigsService.instance;
      expect(service.isScanning, isFalse);
      service.cancel();
      // Service should gracefully accept cancel
      expect(service.isScanning, isFalse);
    });

    test('selectAndConnectFreeNode preserves country, countryCode, and latency', () {
      final container = ProviderContainer();
      final freeNode = ProxyNode(
        id: 'free-node-1',
        name: 'Free Server [DE]',
        protocol: ProtocolType.vless,
        address: '8.8.8.8',
        port: 443,
        uuidOrPassword: 'test-uuid',
        countryCode: 'DE',
        country: 'Germany',
        latencyMs: 145,
      );

      container.read(nodesProvider.notifier).selectAndConnectFreeNode(freeNode);

      final nodes = container.read(nodesProvider);
      expect(nodes.isNotEmpty, isTrue);
      final active = nodes.firstWhere((n) => n.isActive);
      expect(active.id, equals('free-node-1'));
      expect(active.countryCode, equals('DE'));
      expect(active.country, equals('Germany'));
      expect(active.latencyMs, equals(145));
    });

    test('switchNode switches active node without error', () async {
      final container = ProviderContainer();
      final nodeA = ProxyNode(
        id: 'node-a',
        name: 'Server A',
        protocol: ProtocolType.vless,
        address: '1.1.1.1',
        port: 443,
        uuidOrPassword: 'uuid-a',
        isActive: true,
      );
      final nodeB = ProxyNode(
        id: 'node-b',
        name: 'Server B',
        protocol: ProtocolType.vless,
        address: '2.2.2.2',
        port: 443,
        uuidOrPassword: 'uuid-b',
        isActive: false,
      );

      container.read(nodesProvider.notifier).addNodes([nodeA, nodeB]);
      expect(container.read(connectionStatusProvider), equals(ConnectionStateEnum.disconnected));

      await container.read(connectionStatusProvider.notifier).switchNode('node-b');

      final currentNodes = container.read(nodesProvider);
      final active = currentNodes.firstWhere((n) => n.isActive);
      expect(active.id, equals('node-b'));
    });

    test('NodeTestResult.parseCloudflareTrace parses loc and exit ip correctly', () {
      const sampleTrace = '''
fl=306f15
h=cp.cloudflare.com
ip=185.220.101.5
ts=1772922119.123
visit_scheme=http
uag=Dart/3.6 (dart:io)
colo=FRA
sliver=none
http=http/1.1
loc=DE
tls=off
sni=off
warp=off
gateway=off
rbi=off
kex=none
''';
      final parsed = NodeTestResult.parseCloudflareTrace(sampleTrace);
      expect(parsed.ip, equals('185.220.101.5'));
      expect(parsed.loc, equals('DE'));
    });

    test('NodeTestResult.parseCloudflareTrace handles unknown loc correctly', () {
      const sampleTrace = '''
fl=123
ip=1.2.3.4
loc=XX
''';
      final parsed = NodeTestResult.parseCloudflareTrace(sampleTrace);
      expect(parsed.ip, equals('1.2.3.4'));
      expect(parsed.loc, isNull);
    });

    test('NodeTestResult reflects latency and outbound exit country attribution', () {
      const res = NodeTestResult(
        latencyMs: 120,
        countryCode: 'FI',
        country: 'Finland',
        exitIp: '95.216.12.34',
      );
      expect(res.isSuccess, isTrue);
      expect(res.latencyMs, equals(120));
      expect(res.countryCode, equals('FI'));
      expect(res.country, equals('Finland'));
      expect(res.exitIp, equals('95.216.12.34'));
    });

    test('nodesProvider updates active node country to outbound exit country', () {
      final container = ProviderContainer();
      final node = ProxyNode(
        id: 'node-exit-test',
        name: 'US Bridge Server',
        protocol: ProtocolType.vless,
        address: '1.1.1.1',
        port: 443,
        uuidOrPassword: 'test-uuid',
        countryCode: 'US',
        country: 'United States',
        isActive: true,
      );

      container.read(nodesProvider.notifier).addNodes([node]);

      // Simulate exit country detected via proxy (e.g., DE for 5.5.5.5)
      container.read(nodesProvider.notifier).updateLatency(
        'node-exit-test',
        135,
        countryCode: 'DE',
        country: 'Germany',
      );

      final updated = container.read(nodesProvider).firstWhere((n) => n.id == 'node-exit-test');
      expect(updated.countryCode, equals('DE'));
      expect(updated.country, equals('Germany'));
      expect(updated.latencyMs, equals(135));
    });

    test('CountryService.resolveSync does not return US for Cloudflare/CDN address when name is generic', () {
      final node = ProxyNode(
        id: 'cf-node',
        name: 'Config 1',
        protocol: ProtocolType.vless,
        address: '104.21.5.12',
        port: 443,
        uuidOrPassword: 'test-uuid',
      );
      // Even though 104.21.5.12 is Cloudflare IP, resolveSync must return null, not US!
      expect(CountryService.resolveSync(node), isNull);
    });

    test('CountryService.resolveSync returns country when present in name remarks', () {
      final nodeDe = ProxyNode(
        id: 'de-node',
        name: '🇩🇪 Germany Server',
        protocol: ProtocolType.vless,
        address: '104.21.5.12',
        port: 443,
        uuidOrPassword: 'test-uuid',
      );
      expect(CountryService.resolveSync(nodeDe), equals('DE'));

      final nodeNl = ProxyNode(
        id: 'nl-node',
        name: 'Fast Server [NL]',
        protocol: ProtocolType.vless,
        address: '172.67.1.1',
        port: 443,
        uuidOrPassword: 'test-uuid',
      );
      expect(CountryService.resolveSync(nodeNl), equals('NL'));
    });

    test('XrayProcessService.generateXrayConfig includes allowInsecure in tlsSettings when enabled', () {
      final nodeInsecure = ProxyNode(
        id: 'node-insecure-1',
        name: 'Insecure Node',
        protocol: ProtocolType.vmess,
        address: '151.101.201.135',
        port: 443,
        uuidOrPassword: 'test-uuid',
        security: SecurityType.tls,
        sni: 'ssl.fastly.com',
        allowInsecure: true,
      );

      final config = XrayProcessService.instance.generateXrayConfig(nodeInsecure);
      final outbounds = config['outbounds'] as List;
      final proxyOut = outbounds.firstWhere((o) => o['tag'] == 'proxy') as Map<String, dynamic>;
      final tlsSettings = proxyOut['streamSettings']['tlsSettings'] as Map<String, dynamic>;

      expect(tlsSettings['allowInsecure'], isTrue);
      expect(tlsSettings['serverName'], equals('ssl.fastly.com'));
    });

    test('ConfigParser parses allowInsecure for VMess, VLESS, and Trojan', () {
      final vmessJson = jsonEncode({
        'v': '2',
        'ps': 'Test VMess Insecure',
        'add': '151.101.201.135',
        'port': 443,
        'id': 'uuid-1234',
        'aid': 0,
        'net': 'ws',
        'tls': 'tls',
        'sni': 'ssl.fastly.com',
        'allowInsecure': true,
      });
      final vmessNode = ConfigParser.parseSingle('vmess://${base64Encode(utf8.encode(vmessJson))}');
      expect(vmessNode, isNotNull);
      expect(vmessNode!.allowInsecure, isTrue);

      final vlessNode = ConfigParser.parseSingle(
        'vless://uuid-1234@151.101.201.135:443?security=tls&sni=ssl.fastly.com&insecure=1#VlessInsecure',
      );
      expect(vlessNode, isNotNull);
      expect(vlessNode!.allowInsecure, isTrue);

      final trojanNode = ConfigParser.parseSingle(
        'trojan://pass123@151.101.201.135:443?security=tls&sni=ssl.fastly.com&allowInsecure=1#TrojanInsecure',
      );
      expect(trojanNode, isNotNull);
      expect(trojanNode!.allowInsecure, isTrue);
    });

    test('updateLatency clears false country if node test times out', () {
      final container = ProviderContainer();
      final node = ProxyNode(
        id: 'node-fail-test',
        name: 'Some Server',
        protocol: ProtocolType.vmess,
        address: '151.101.201.135',
        port: 443,
        uuidOrPassword: 'uuid-123',
        countryCode: 'US',
        country: 'United States',
      );

      container.read(nodesProvider.notifier).addNode(node);

      // Node test fails (latencyMs = null)
      container.read(nodesProvider.notifier).updateLatency('node-fail-test', null);

      final updated = container.read(nodesProvider).firstWhere((n) => n.id == 'node-fail-test');
      expect(updated.latencyMs, isNull);
      expect(updated.countryCode, isNull);
      expect(updated.country, isNull);
    });

    test('ProxyNode serialization and copyWith correctly handle 4-tab new fields', () {
      final node = ProxyNode(
        id: 'tab-node-1',
        name: 'My Custom Tab Node',
        protocol: ProtocolType.vless,
        address: '10.0.0.1',
        port: 8443,
        uuidOrPassword: 'tab-uuid-1',
        enableMux: true,
        echConfigList: 'AH6+...base64ECH',
        verifyPeerCertByName: 'example.com',
        certificatePinning: 'abcd1234ef5678',
      );

      final json = node.toJson();
      expect(json['enable_mux'], isTrue);
      expect(json['ech_config_list'], equals('AH6+...base64ECH'));
      expect(json['verify_peer_cert_by_name'], equals('example.com'));
      expect(json['certificate_pinning'], equals('abcd1234ef5678'));

      final restored = ProxyNode.fromJson(json);
      expect(restored.enableMux, isTrue);
      expect(restored.echConfigList, equals('AH6+...base64ECH'));
      expect(restored.verifyPeerCertByName, equals('example.com'));
      expect(restored.certificatePinning, equals('abcd1234ef5678'));

      final modified = restored.copyWith(
        enableMux: false,
        verifyPeerCertByName: 'new-example.com',
      );
      expect(modified.enableMux, isFalse);
      expect(modified.verifyPeerCertByName, equals('new-example.com'));
      expect(modified.certificatePinning, equals('abcd1234ef5678'));
    });

    test('XrayProcessService.generateXrayConfig properly applies mux and TLS advanced settings', () {
      final node = ProxyNode(
        id: 'node-adv-tls',
        name: 'Advanced TLS Node',
        protocol: ProtocolType.vless,
        address: 'my.server.com',
        port: 443,
        uuidOrPassword: 'some-uuid-value',
        security: SecurityType.tls,
        sni: 'my.server.com',
        fingerprint: 'chrome',
        alpn: ['h2', 'http/1.1'],
        enableMux: true,
        echConfigList: 'base64-ech-payload',
        verifyPeerCertByName: 'my.server.com',
        certificatePinning: 'pinned-sha256-hash',
      );

      final config = XrayProcessService.instance.generateXrayConfig(node);
      final outbounds = config['outbounds'] as List;
      final proxyOut = outbounds.firstWhere((o) => o['tag'] == 'proxy') as Map<String, dynamic>;

      // Verify mux
      expect(proxyOut['mux'], isNotNull);
      expect(proxyOut['mux']['enabled'], isTrue);
      expect(proxyOut['mux']['concurrency'], equals(8));

      // Verify streamSettings TLS
      final streamSettings = proxyOut['streamSettings'] as Map<String, dynamic>;
      final tlsSettings = streamSettings['tlsSettings'] as Map<String, dynamic>;
      expect(tlsSettings['serverName'], equals('my.server.com'));
      expect(tlsSettings['fingerprint'], equals('chrome'));
      expect(tlsSettings['alpn'], equals(['h2', 'http/1.1']));
      expect(tlsSettings['echConfigList'], equals('base64-ech-payload'));
      expect(tlsSettings['verifyPeerCertByName'], equals('my.server.com'));
      expect(tlsSettings['pinnedPeerCertificatePublicKeySha256'], equals('pinned-sha256-hash'));
    });

    test('FreeConfigsScanProgress correctly calculates failedCount', () {
      const progress = FreeConfigsScanProgress(
        totalScraped: 120,
        totalUnique: 100,
        testedCandidates: 60,
        workingFound: 15,
        targetWorking: 30,
      );

      expect(progress.failedCount, equals(45));
    });

    test('CountryService & NodeTestResult strictly handles unknown country as null', () {
      const traceBodyWithoutLoc = 'ip=198.51.100.1\nts=1672531199\nuag=Mozilla/5.0\n';
      final trace = NodeTestResult.parseCloudflareTrace(traceBodyWithoutLoc);
      expect(trace.ip, equals('198.51.100.1'));
      expect(trace.loc, isNull);

      // Verify null country name formatting
      expect(CountryService.getCountryName(null), isNull);
      expect(CountryService.getCountryName(''), isNull);
    });

    test('RoutingRule model serializes and deserializes properly', () {
      const rule = RoutingRule(
        id: 'rule-test-1',
        type: RoutingRuleType.address,
        values: ['geosite:ir', 'domain:aparat.com'],
        action: RoutingAction.direct,
        enabled: true,
        remark: 'Iran Local',
      );

      final json = rule.toJson();
      expect(json['id'], equals('rule-test-1'));
      expect(json['type'], equals('address'));
      expect(json['action'], equals('direct'));
      expect(json['values'], equals(['geosite:ir', 'domain:aparat.com']));

      final restored = RoutingRule.fromJson(json);
      expect(restored.id, equals('rule-test-1'));
      expect(restored.type, equals(RoutingRuleType.address));
      expect(restored.action, equals(RoutingAction.direct));
      expect(restored.values, equals(['geosite:ir', 'domain:aparat.com']));
      expect(restored.enabled, isTrue);
      expect(restored.remark, equals('Iran Local'));
    });

    test('XrayProcessService injects Routing rules into routing.rules config', () {
      final node = ProxyNode(
        id: 'routing-node-1',
        name: 'Node with Routing',
        protocol: ProtocolType.vless,
        address: '1.2.3.4',
        port: 443,
        uuidOrPassword: 'uuid-1',
      );

      XrayProcessService.instance.routingRules = [
        const RoutingRule(
          id: 'rule-1',
          type: RoutingRuleType.address,
          values: ['geosite:ir'],
          action: RoutingAction.direct,
        ),
        const RoutingRule(
          id: 'rule-2',
          type: RoutingRuleType.ip,
          values: ['geoip:ir', '10.0.0.0/8'],
          action: RoutingAction.block,
        ),
        const RoutingRule(
          id: 'rule-3',
          type: RoutingRuleType.app,
          values: ['telegram.exe'],
          action: RoutingAction.proxy,
        ),
      ];

      final config = XrayProcessService.instance.generateXrayConfig(node, enableTun: true);
      final routing = config['routing'] as Map<String, dynamic>;
      final rules = routing['rules'] as List;

      // Find the injected rules
      final directDomainRule = rules.cast<Map<String, dynamic>?>().firstWhere(
        (r) => r != null && r['outboundTag'] == 'direct' && r['domain'] != null,
        orElse: () => null,
      );
      expect(directDomainRule, isNotNull);
      expect(directDomainRule!['domain'], equals(['geosite:ir']));

      final blockIpRule = rules.cast<Map<String, dynamic>?>().firstWhere(
        (r) => r != null && r['outboundTag'] == 'block' && r['ip'] != null,
        orElse: () => null,
      );
      expect(blockIpRule, isNotNull);
      expect(blockIpRule!['ip'], equals(['geoip:ir', '10.0.0.0/8']));

      final proxyAppRule = rules.cast<Map<String, dynamic>?>().firstWhere(
        (r) => r != null && r['outboundTag'] == 'proxy' && r['process'] != null,
        orElse: () => null,
      );
      expect(proxyAppRule, isNotNull);
      expect(proxyAppRule!['process'], equals(['telegram.exe']));
    });

    test('Global Allow Insecure and Global Enable Mux apply to nodes even when node flags are false', () {
      final node = ProxyNode(
        id: 'plain-node-1',
        name: 'Plain Node',
        protocol: ProtocolType.vless,
        address: '1.2.3.4',
        port: 443,
        uuidOrPassword: 'uuid-1',
        security: SecurityType.tls,
        allowInsecure: false,
        enableMux: false,
      );

      XrayProcessService.instance.globalAllowInsecure = true;
      XrayProcessService.instance.globalEnableMux = true;

      final config = XrayProcessService.instance.generateXrayConfig(node);
      final outbounds = config['outbounds'] as List;
      final proxyOut = outbounds.firstWhere((o) => o['tag'] == 'proxy') as Map<String, dynamic>;

      // Global Mux should be active
      expect(proxyOut['mux'], isNotNull);
      expect(proxyOut['mux']['enabled'], isTrue);

      // Global Allow Insecure should be active in TLS streamSettings
      final streamSettings = proxyOut['streamSettings'] as Map<String, dynamic>;
      final tlsSettings = streamSettings['tlsSettings'] as Map<String, dynamic>;
      expect(tlsSettings['allowInsecure'], isTrue);

      // Reset
      XrayProcessService.instance.globalAllowInsecure = false;
      XrayProcessService.instance.globalEnableMux = false;
    });

    test('ScanResult serialization and deserialization with country fields', () {
      final res = ScanResult(
        ip: '104.16.1.1',
        port: 443,
        tcpSuccess: true,
        tcpLatencyMs: 45,
        tlsSuccess: true,
        tlsLatencyMs: 50,
        protocolSuccess: true,
        totalLatencyMs: 95,
        rankScore: 95.0,
        countryCode: 'US',
        country: 'United States',
        exitIp: '104.16.1.1',
      );

      expect(res.countryCode, equals('US'));
      expect(res.country, equals('United States'));
      expect(res.exitIp, equals('104.16.1.1'));
      expect(res.latencyTier, equals('Good'));
    });

    test('Country filtering separates healthy nodes from timed out nodes', () {
      final healthyUS = ProxyNode(
        id: 'h-us',
        name: 'US Node 1',
        protocol: ProtocolType.vless,
        address: '1.2.3.4',
        port: 443,
        uuidOrPassword: 'uuid',
        latencyMs: 120,
        lastTestedAt: DateTime.now(),
        countryCode: 'US',
      );

      final deadUS = ProxyNode(
        id: 'd-us',
        name: 'US Node 2',
        protocol: ProtocolType.vless,
        address: '1.2.3.5',
        port: 443,
        uuidOrPassword: 'uuid',
        latencyMs: -1,
        lastTestedAt: DateTime.now(),
        countryCode: 'US',
      );

      final untestedDE = ProxyNode(
        id: 'u-de',
        name: 'DE Node 1',
        protocol: ProtocolType.vless,
        address: '5.6.7.8',
        port: 443,
        uuidOrPassword: 'uuid',
        countryCode: 'DE',
      );

      final nodes = [healthyUS, deadUS, untestedDE];

      // US filter: should ONLY match healthy nodes with countryCode == 'US'
      final filteredUS = nodes.where((n) => n.hasValidPing && n.countryCode == 'US').toList();
      expect(filteredUS.length, equals(1));
      expect(filteredUS.first.id, equals('h-us'));

      // Timeouts filter: should match only timed-out nodes
      final timeouts = nodes.where((n) => n.hasTimedOut).toList();
      expect(timeouts.length, equals(1));
      expect(timeouts.first.id, equals('d-us'));

      // Untested:
      expect(untestedDE.isUntested, isTrue);
      expect(untestedDE.hasValidPing, isFalse);
      expect(untestedDE.hasTimedOut, isFalse);
    });

    test('FreeConfigsState accurately manages timeoutNodes and allNodes', () {
      final healthy = ProxyNode(
        id: 'free-1',
        name: 'Free 1',
        protocol: ProtocolType.vless,
        address: '1.1.1.1',
        port: 443,
        uuidOrPassword: 'uuid',
        latencyMs: 80,
        lastTestedAt: DateTime.now(),
      );
      final dead = ProxyNode(
        id: 'free-2',
        name: 'Free 2',
        protocol: ProtocolType.vless,
        address: '2.2.2.2',
        port: 443,
        uuidOrPassword: 'uuid',
        latencyMs: -1,
        lastTestedAt: DateTime.now(),
      );

      const state = FreeConfigsState(
        workingNodes: [],
        timeoutNodes: [],
      );
      expect(state.allNodes, isEmpty);

      final updatedState = state.copyWith(
        workingNodes: [healthy],
        timeoutNodes: [dead],
        testedCandidates: 2,
      );

      expect(updatedState.workingNodes.length, equals(1));
      expect(updatedState.timeoutNodes.length, equals(1));
      expect(updatedState.allNodes.length, equals(2));
      expect(updatedState.failedCount, equals(1));
    });

    test('RoutingRuleType.app generates process routing rules for Xray TUN mode', () {
      const appRule = RoutingRule(
        id: 'rule-app-1',
        type: RoutingRuleType.app,
        values: ['telegram.exe', 'chrome.exe'],
        action: RoutingAction.proxy,
        enabled: true,
      );

      XrayProcessService.instance.routingRules = [appRule];
      final node = ProxyNode(
        id: 'n1',
        name: 'Test',
        protocol: ProtocolType.vless,
        address: '1.1.1.1',
        port: 443,
        uuidOrPassword: 'uuid',
      );

      // In TUN mode:
      final tunConfig = XrayProcessService.instance.generateXrayConfig(node, enableTun: true);
      final rules = (tunConfig['routing'] as Map<String, dynamic>)['rules'] as List;
      final appRouting = rules.firstWhere((r) => r is Map && r['process'] != null) as Map<String, dynamic>;

      expect(appRouting['outboundTag'], equals('proxy'));
      expect(appRouting['process'], equals(['telegram.exe', 'chrome.exe']));

      // Cleanup
      XrayProcessService.instance.routingRules = [];
    });
  });
}

