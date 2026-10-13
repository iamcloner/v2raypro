import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:v2raypro/models/proxy_node.dart';
import 'package:v2raypro/providers/app_providers.dart';
import 'package:v2raypro/services/xray_process_service.dart';
import 'package:v2raypro/utils/config_parser.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('v1.7.2 Xray TLS Settings - allowInsecure Removal & Cert Pinning', () {
    test('generateXrayConfig never produces allowInsecure: true in tlsSettings', () {
      final node = ProxyNode(
        id: 'node-tls-test',
        name: 'TLS Node',
        address: '1.2.3.4',
        port: 443,
        uuidOrPassword: 'uuid-test',
        protocol: ProtocolType.vless,
        network: NetworkType.tcp,
        security: SecurityType.tls,
        allowInsecure: true, // Legacy or user preference flag
        certificatePinning: 'abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890',
      );

      final config = XrayProcessService.instance.generateXrayConfig(node);
      final outbounds = config['outbounds'] as List<dynamic>;
      final proxyOutbound = outbounds.firstWhere((o) => o['tag'] == 'proxy');
      final streamSettings = proxyOutbound['streamSettings'] as Map<String, dynamic>;
      final tlsSettings = streamSettings['tlsSettings'] as Map<String, dynamic>;

      expect(tlsSettings.containsKey('allowInsecure'), isFalse,
          reason: 'allowInsecure has been removed from Xray and causes fatal startup crashes');
      expect(tlsSettings['pinnedPeerCertSha256'],
          'abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890');
    });

    test('generateXrayConfig Reality outbound also avoids allowInsecure', () {
      final node = ProxyNode(
        id: 'node-reality-test',
        name: 'Reality Node',
        address: '1.2.3.4',
        port: 443,
        uuidOrPassword: 'uuid-test',
        protocol: ProtocolType.vless,
        network: NetworkType.tcp,
        security: SecurityType.reality,
        publicKey: 'pubkey123',
        shortId: 'short123',
        allowInsecure: true,
      );

      final config = XrayProcessService.instance.generateXrayConfig(node);
      final outbounds = config['outbounds'] as List<dynamic>;
      final proxyOutbound = outbounds.firstWhere((o) => o['tag'] == 'proxy');
      final streamSettings = proxyOutbound['streamSettings'] as Map<String, dynamic>;
      final realitySettings = streamSettings['realitySettings'] as Map<String, dynamic>;

      expect(realitySettings.containsKey('allowInsecure'), isFalse);
      expect(realitySettings['publicKey'], 'pubkey123');
      expect(realitySettings['shortId'], 'short123');
    });
  });

  group('v1.7.2 Sing-box Outbound Parsing & Conversion Tests', () {
    test('parseSingBoxOutbound parses VLESS sing-box outbound accurately', () {
      final outboundJson = {
        "type": "vless",
        "tag": "sing-vless-node",
        "server": "singbox.example.com",
        "server_port": 8443,
        "uuid": "99999999-8888-7777-6666-555555555555",
        "flow": "xtls-rprx-vision",
        "tls": {
          "enabled": true,
          "server_name": "sni.example.com",
          "insecure": false,
          "reality": {
            "enabled": true,
            "public_key": "my-pub-key",
            "short_id": "my-short-id"
          }
        }
      };

      final node = ConfigParser.parseSingBoxOutbound(outboundJson);
      expect(node, isNotNull);
      expect(node!.name, 'sing-vless-node');
      expect(node.protocol, ProtocolType.vless);
      expect(node.address, 'singbox.example.com');
      expect(node.port, 8443);
      expect(node.uuidOrPassword, '99999999-8888-7777-6666-555555555555');
      expect(node.flow, 'xtls-rprx-vision');
      expect(node.security, SecurityType.reality);
      expect(node.sni, 'sni.example.com');
      expect(node.publicKey, 'my-pub-key');
      expect(node.shortId, 'my-short-id');
    });

    test('parseSingBoxOutbound parses VMess with WebSocket sing-box outbound', () {
      final outboundJson = {
        "type": "vmess",
        "tag": "sing-vmess-ws",
        "server": "1.1.1.1",
        "server_port": 443,
        "uuid": "aaaa-bbbb-cccc",
        "security": "auto",
        "transport": {
          "type": "ws",
          "path": "/ws-path",
          "headers": {
            "Host": "cf-host.com"
          }
        },
        "tls": {
          "enabled": true,
          "server_name": "cf-host.com"
        }
      };

      final node = ConfigParser.parseSingBoxOutbound(outboundJson);
      expect(node, isNotNull);
      expect(node!.protocol, ProtocolType.vmess);
      expect(node.network, NetworkType.ws);
      expect(node.path, '/ws-path');
      expect(node.host, 'cf-host.com');
      expect(node.sni, 'cf-host.com');
      expect(node.security, SecurityType.tls);
    });

    test('parseSingBoxConfig parses full sing-box JSON configuration', () {
      final fullConfig = {
        "outbounds": [
          {
            "type": "trojan",
            "tag": "trojan-node",
            "server": "trojan.server.com",
            "server_port": 443,
            "password": "trojan-password",
            "tls": {
              "enabled": true,
              "server_name": "trojan.server.com"
            }
          },
          {
            "type": "direct",
            "tag": "direct-out"
          },
          {
            "type": "block",
            "tag": "block-out"
          }
        ]
      };

      final nodes = ConfigParser.parseSingBoxConfig(jsonEncode(fullConfig));
      expect(nodes.length, 1);
      expect(nodes.first.name, 'trojan-node');
      expect(nodes.first.protocol, ProtocolType.trojan);
      expect(nodes.first.uuidOrPassword, 'trojan-password');
      expect(nodes.first.address, 'trojan.server.com');
    });

    test('toSingBoxOutbound converts ProxyNode to standard sing-box outbound map', () {
      final node = ProxyNode(
        id: 'node-to-singbox',
        name: 'Export Singbox',
        address: 'node.server.com',
        port: 443,
        uuidOrPassword: 'test-uuid-value',
        protocol: ProtocolType.vless,
        network: NetworkType.grpc,
        serviceName: 'grpc-service',
        security: SecurityType.reality,
        publicKey: 'pub-key-singbox',
        shortId: 'short-id-singbox',
        sni: 'sni.server.com',
      );

      final outbound = ConfigParser.toSingBoxOutbound(node);
      expect(outbound['type'], 'vless');
      expect(outbound['server'], 'node.server.com');
      expect(outbound['server_port'], 443);
      expect(outbound['uuid'], 'test-uuid-value');
      expect(outbound['transport']?['type'], 'grpc');
      expect(outbound['transport']?['service_name'], 'grpc-service');
      expect(outbound['tls']?['enabled'], isTrue);
      expect(outbound['tls']?['reality']?['public_key'], 'pub-key-singbox');
    });

    test('generateSingBoxConfig generates full runnable sing-box configuration', () {
      final node = ProxyNode(
        id: 'node-runnable',
        name: 'Runnable Node',
        address: '1.2.3.4',
        port: 8080,
        uuidOrPassword: 'pass',
        protocol: ProtocolType.shadowsocks,
        cipher: 'aes-128-gcm',
      );

      final jsonStr = ConfigParser.generateSingBoxConfig(node, inSocksPort: 10808);
      final config = jsonDecode(jsonStr) as Map<String, dynamic>;
      expect(config['inbounds'], isNotEmpty);
      expect(config['outbounds'], isNotEmpty);

      final outbounds = config['outbounds'] as List<dynamic>;
      final proxyOut = outbounds.firstWhere((o) => o['tag'] == 'Runnable Node');
      expect(proxyOut['type'], 'shadowsocks');
      expect(proxyOut['method'], 'aes-128-gcm');
      expect(proxyOut['password'], 'pass');
    });

    test('parseSingle auto-detects sing-box JSON configuration string', () {
      final singBoxJson = '''
      {
        "outbounds": [
          {
            "type": "vless",
            "tag": "Auto-Detect SingBox",
            "server": "192.168.1.1",
            "server_port": 443,
            "uuid": "uuid-test-autodetect"
          }
        ]
      }
      ''';

      final node = ConfigParser.parseSingle(singBoxJson);
      expect(node, isNotNull);
      expect(node!.name, 'Auto-Detect SingBox');
      expect(node.protocol, ProtocolType.vless);
      expect(node.address, '192.168.1.1');
    });
  });

  group('v1.7.2 Testing Mode & Concurrency Settings Tests', () {
    test('TestMode enum has normal and turbo modes', () {
      expect(TestMode.values.length, 2);
      expect(TestMode.normal.name, 'normal');
      expect(TestMode.turbo.name, 'turbo');
    });

    test('ScannerState clamps workers concurrency up to 500', () {
      final state1 = ScannerState(workers: 1000);
      expect(state1.workers, 500);

      final state2 = ScannerState(workers: 2);
      expect(state2.workers, 5);

      final state3 = ScannerState(workers: 250);
      expect(state3.workers, 250);
    });

    test('TestConcurrencyNotifier clamps concurrency between 5 and 100', () async {
      final notifier = TestConcurrencyNotifier();
      await notifier.setConcurrency(300);
      expect(notifier.state, 100);

      await notifier.setConcurrency(2);
      expect(notifier.state, 5);

      await notifier.setConcurrency(45);
      expect(notifier.state, 45);
    });

    test('tcpPing returns null on unreachable loopback dummy port without crashing', () async {
      // Test rapid TCP ping timeout handling
      final latency = await XrayProcessService.instance.tcpPing(
        '127.0.0.1',
        59999,
        count: 2,
        timeout: const Duration(milliseconds: 100),
      );
      // Since port 59999 is closed/unreachable, it should cleanly return null
      expect(latency, isNull);
    });
  });
}
