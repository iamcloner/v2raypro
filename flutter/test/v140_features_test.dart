import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:v2raypro/models/proxy_node.dart';
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
  });
}

