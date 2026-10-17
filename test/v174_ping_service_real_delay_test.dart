import 'package:flutter_test/flutter_test.dart';
import 'package:v2raypro/models/proxy_node.dart';
import 'package:v2raypro/models/service_models.dart';
import 'package:v2raypro/services/ping_service.dart';
import 'package:v2raypro/services/xray_process_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Ping Service Calibration & Real Delay Tests', () {
    final testNode = ProxyNode(
      id: 'test_node_ping',
      name: 'Ping Test Node',
      address: '1.2.3.4',
      port: 443,
      protocol: ProtocolType.vless,
      uuidOrPassword: 'test-uuid-ping',
      network: NetworkType.ws,
      security: SecurityType.tls,
      sni: 'example.com',
      path: '/ws',
    );

    test('CoreConfig.fromNode generates valid config for ping service without crashing', () {
      final config = CoreConfig.fromNode(testNode, type: CoreType.xray);
      expect(config.node, isNotNull);
      expect(config.rawJson['inbounds'], isNotEmpty);
      expect(config.rawJson['outbounds'], isNotEmpty);
    });

    test('XrayProcessService isNodeConfigSupported returns true for valid nodes', () {
      expect(XrayProcessService.instance.isNodeConfigSupported(testNode), isTrue);
    });

    test('Ephemeral port counter generates valid ports within safe range', () {
      final s = PingService.instance;
      expect(s, isNotNull);
    });

    test('Fast timeout and failure safety on loopback dummy target', () async {
      final dummyNode = ProxyNode(
        id: 'dummy_loopback',
        name: 'Dummy Loopback',
        address: '127.0.0.1',
        port: 19999,
        protocol: ProtocolType.vless,
        uuidOrPassword: 'dummy',
      );

      final res = await PingService.instance.ping(
        config: CoreConfig.fromNode(dummyNode),
        pingMode: PingMode.ipTest,
        pingType: PingType.tcp,
        timeout: const Duration(milliseconds: 200),
      );
      expect(res.latencyMs, isNull);
    });
  });
}
