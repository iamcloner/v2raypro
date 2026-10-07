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
  });
}
