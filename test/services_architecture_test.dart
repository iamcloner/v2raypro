import "package:flutter_test/flutter_test.dart";
import "package:v2raypro/models/proxy_node.dart";
import "package:v2raypro/models/service_models.dart";
import "package:v2raypro/services/core_service.dart";
import "package:v2raypro/services/tun_service.dart";
import "package:v2raypro/services/ping_service.dart";
import "package:v2raypro/utils/config_generator.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final testNode = ProxyNode(
    id: "test-node-1",
    name: "Test Server",
    address: "1.1.1.1",
    port: 443,
    protocol: ProtocolType.vless,
    uuidOrPassword: "12345678-1234-1234-1234-123456789abc",
    security: SecurityType.tls,
    sni: "test.example.com",
  );

  group("Architecture: CoreConfig and ConfigGenerator", () {
    test("generates valid Xray configuration from node", () {
      final config = CoreConfig.fromNode(testNode, type: CoreType.xray);
      expect(config.type, CoreType.xray);
      expect(config.rawJson, contains("outbounds"));
      expect(config.rawJson, contains("inbounds"));

      final serverInfo = config.extractServerAddressAndPort();
      expect(serverInfo.address, "1.1.1.1");
      expect(serverInfo.port, 443);
    });

    test("generates valid Singbox configuration from node", () {
      final config = CoreConfig.fromNode(testNode, type: CoreType.singbox);
      expect(config.type, CoreType.singbox);
      expect(config.rawJson, contains("outbounds"));
      expect(config.rawJson, contains("inbounds"));

      final serverInfo = config.extractServerAddressAndPort();
      expect(serverInfo.address, "1.1.1.1");
      expect(serverInfo.port, 443);
    });
  });

  group("Architecture: TunService", () {
    test("initial state is disconnected", () {
      final tun = TunService.instance;
      expect(tun.status, TunStatus.disconnect);
      expect(tun.isConnected, false);
    });

    test("handles setStatus connect and disconnect", () async {
      final tun = TunService.instance;
      await tun.setStatus(status: TunStatus.disconnect, socksPort: 10808, httpPort: 10809);
      expect(tun.status, TunStatus.disconnect);
      expect(tun.isConnected, false);
    });

    test("isRunningAsAdmin returns boolean", () {
      expect(TunService.instance.isRunningAsAdmin(), isA<bool>());
    });
  });

  group("Architecture: PingService", () {
    test("ipTest mode correctly extracts server address and executes", () async {
      final cfg = CoreConfig.fromNode(testNode);
      final res = await PingService.instance.ping(
        config: cfg,
        pingMode: PingMode.ipTest,
        pingType: PingType.tcp,
        timeout: const Duration(milliseconds: 500),
      );
      expect(res, isA<PingResult>());
    });

    test("ipTest mode supports ICMP, TCP, and UDP ping types", () async {
      final cfg = CoreConfig.fromNode(testNode);
      for (final type in [PingType.tcp, PingType.icmp, PingType.udp]) {
        final res = await PingService.instance.ping(
          config: cfg,
          pingMode: PingMode.ipTest,
          pingType: type,
          timeout: const Duration(milliseconds: 300),
        );
        expect(res, isA<PingResult>());
      }
    });

    test("realDelay mode executes with showCountry parameter", () async {
      final cfg = CoreConfig.fromNode(testNode);
      final res = await PingService.instance.ping(
        config: cfg,
        destination: "127.0.0.1",
        port: 80,
        pingMode: PingMode.realDelay,
        pingType: PingType.tcp,
        showCountry: true,
        timeout: const Duration(milliseconds: 200),
      );
      expect(res, isA<PingResult>());
    });
  });

  group("Architecture: CoreService", () {
    test("initial state and ports", () {
      final core = CoreService.instance;
      expect(core.state, CoreState.disconnected);
      expect(core.socksPort, isPositive);
      expect(core.httpPort, isPositive);
      expect(core.apiPort, isPositive);
    });

    test("provides active duration and traffic streams", () {
      final core = CoreService.instance;
      expect(core.durationStream, isA<Stream<Duration>>());
      expect(core.trafficStream, isA<Stream>());
      expect(core.stateStream, isA<Stream<CoreState>>());
    });

    test("disconnect resets active state", () async {
      final core = CoreService.instance;
      await core.disconnect();
      expect(core.state, CoreState.disconnected);
      expect(core.activeConfig, isNull);
    });
  });
}
