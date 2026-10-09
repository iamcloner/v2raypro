import 'package:flutter_test/flutter_test.dart';
import 'package:v2raypro/models/proxy_node.dart';
import 'package:v2raypro/services/xray_process_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('v1.5.2 Allow LAN & Config Generation Tests', () {
    final testNode = ProxyNode(
      id: 'test-node-1',
      name: 'Test Node',
      address: '1.2.3.4',
      port: 443,
      uuidOrPassword: 'uuid-1234',
      protocol: ProtocolType.vless,
      network: NetworkType.tcp,
      security: SecurityType.none,
    );

    test('generateXrayConfig uses 127.0.0.1 when allowLan is false and globalAllowLan is false', () {
      XrayProcessService.instance.globalAllowLan = false;
      final config = XrayProcessService.instance.generateXrayConfig(testNode, allowLan: false);
      final inbounds = config['inbounds'] as List<dynamic>;

      final socksIn = inbounds.firstWhere((i) => i['tag'] == 'socks-in');
      final httpIn = inbounds.firstWhere((i) => i['tag'] == 'http-in');

      expect(socksIn['listen'], '127.0.0.1');
      expect(httpIn['listen'], '127.0.0.1');
    });

    test('generateXrayConfig uses 0.0.0.0 when allowLan is true', () {
      XrayProcessService.instance.globalAllowLan = false;
      final config = XrayProcessService.instance.generateXrayConfig(testNode, allowLan: true);
      final inbounds = config['inbounds'] as List<dynamic>;

      final socksIn = inbounds.firstWhere((i) => i['tag'] == 'socks-in');
      final httpIn = inbounds.firstWhere((i) => i['tag'] == 'http-in');

      expect(socksIn['listen'], '0.0.0.0');
      expect(httpIn['listen'], '0.0.0.0');
    });

    test('generateXrayConfig uses 0.0.0.0 when globalAllowLan is true even if allowLan is false', () {
      XrayProcessService.instance.globalAllowLan = true;
      final config = XrayProcessService.instance.generateXrayConfig(testNode, allowLan: false);
      final inbounds = config['inbounds'] as List<dynamic>;

      final socksIn = inbounds.firstWhere((i) => i['tag'] == 'socks-in');
      final httpIn = inbounds.firstWhere((i) => i['tag'] == 'http-in');

      expect(socksIn['listen'], '0.0.0.0');
      expect(httpIn['listen'], '0.0.0.0');
      XrayProcessService.instance.globalAllowLan = false;
    });
  });

  group('v1.5.2 Apply IP & Metadata Preservation Tests', () {
    test('ProxyNode copyWith updates latencyMs, countryCode and country correctly', () {
      final node = ProxyNode(
        id: 'node-1',
        name: '🇩🇪 Germany Node',
        address: '104.16.1.1',
        port: 443,
        uuidOrPassword: 'uuid-1234',
        protocol: ProtocolType.vless,
        network: NetworkType.tcp,
        security: SecurityType.none,
      );

      final updated = node.copyWith(
        address: '104.16.2.2',
        latencyMs: 120,
        countryCode: 'DE',
        country: 'Germany',
      );

      expect(updated.address, '104.16.2.2');
      expect(updated.latencyMs, 120);
      expect(updated.countryCode, 'DE');
      expect(updated.country, 'Germany');
    });

    test('ProxyNode clearLatency and clearCountry resets fields correctly', () {
      final node = ProxyNode(
        id: 'node-1',
        name: 'Custom Node',
        address: '104.16.1.1',
        port: 443,
        uuidOrPassword: 'uuid-1234',
        protocol: ProtocolType.vless,
        network: NetworkType.tcp,
        security: SecurityType.none,
        latencyMs: 150,
        countryCode: 'US',
        country: 'United States',
      );

      final cleared = node.copyWith(
        clearLatency: true,
        clearCountry: true,
      );

      expect(cleared.latencyMs, isNull);
      expect(cleared.countryCode, isNull);
      expect(cleared.country, isNull);
    });
  });
}
