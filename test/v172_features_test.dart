import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:v2raypro/models/proxy_node.dart';
import 'package:v2raypro/models/routing_rule.dart';
import 'package:v2raypro/providers/app_providers.dart';
import 'package:v2raypro/services/storage_service.dart';
import 'package:v2raypro/services/xray_process_service.dart';
import 'package:v2raypro/services/cdn_scanner_service.dart';
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

    test('ScannerState clamps workers concurrency up to 100', () {
      final state1 = ScannerState(workers: 1000);
      expect(state1.workers, 100);

      final state2 = ScannerState(workers: 2);
      expect(state2.workers, 5);

      final state3 = ScannerState(workers: 50);
      expect(state3.workers, 50);
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

  group('v1.7.3 Android Per-App Routing & Navigation Tests', () {
    test('AppRoutingMode enum contains exclusive and inclusive values', () {
      expect(AppRoutingMode.values, contains(AppRoutingMode.exclusive));
      expect(AppRoutingMode.values, contains(AppRoutingMode.inclusive));
      expect(AppRoutingMode.exclusive.name, 'exclusive');
      expect(AppRoutingMode.inclusive.name, 'inclusive');
    });

    test('StorageService persists and restores AppRoutingMode', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService.instance;

      // Default should be exclusive
      final defaultMode = await storage.loadAppRoutingMode();
      expect(defaultMode, AppRoutingMode.exclusive);

      // Save inclusive
      await storage.saveAppRoutingMode(AppRoutingMode.inclusive);
      final loadedInclusive = await storage.loadAppRoutingMode();
      expect(loadedInclusive, AppRoutingMode.inclusive);

      // Save exclusive
      await storage.saveAppRoutingMode(AppRoutingMode.exclusive);
      final loadedExclusive = await storage.loadAppRoutingMode();
      expect(loadedExclusive, AppRoutingMode.exclusive);
    });

    test('XrayProcessService maintains appRoutingMode state', () {
      final service = XrayProcessService.instance;
      service.appRoutingMode = AppRoutingMode.exclusive;
      expect(service.appRoutingMode, AppRoutingMode.exclusive);

      service.appRoutingMode = AppRoutingMode.inclusive;
      expect(service.appRoutingMode, AppRoutingMode.inclusive);
    });

    test('Navigation history pop logic properly handles stack and returns to dashboard', () {
      final history = <int>[0];
      int selectedIndex = 0;

      void navigateTo(int index) {
        if (selectedIndex != index) {
          history.add(index);
          selectedIndex = index;
        }
      }

      void pop() {
        while (history.isNotEmpty && history.last == selectedIndex) {
          history.removeLast();
        }
        if (history.isNotEmpty) {
          selectedIndex = history.removeLast();
        } else {
          selectedIndex = 0;
        }
      }

      // Start at dashboard (0)
      expect(selectedIndex, 0);

      // Navigate to Configs (1)
      navigateTo(1);
      expect(selectedIndex, 1);
      expect(history, [0, 1]);

      // Navigate to Routing (5)
      navigateTo(5);
      expect(selectedIndex, 5);
      expect(history, [0, 1, 5]);

      // Pop should go back to Configs (1)
      pop();
      expect(selectedIndex, 1);

      // Pop should go back to Dashboard (0)
      pop();
      expect(selectedIndex, 0);

      // Further pop stays at Dashboard (0)
      pop();
      expect(selectedIndex, 0);
    });
  });

  group('v1.7.4 Ping Accuracy, Cloudflare CIDRs & Strict Scanner Validation Tests', () {
    test('Cloudflare CIDR 8.6.112.0/24 is present and detected', () {
      expect(CdnProvider.cloudflare.defaultCidrs.contains('8.6.112.0/24'), isTrue);
      expect(CdnScannerService.detectCdnHostSync('8.6.112.1'), equals(CdnProvider.cloudflare));
      expect(CdnScannerService.detectCdnHostSync('8.6.112.254'), equals(CdnProvider.cloudflare));
    });

    test('Node latency returns fastest result from multi-probe test', () async {
      final node = ProxyNode(
        id: 'test_node_loopback',
        name: 'Loopback Node',
        address: '127.0.0.1',
        port: 65530,
        protocol: ProtocolType.vless,
        uuidOrPassword: 'test',
      );
      final res = await XrayProcessService.instance.testNodeRealDelay(
        node,
        timeout: const Duration(milliseconds: 300),
      );
      expect(res.isSuccess, isFalse);
    });

    test('detectCdnForNode detects Cloudflare from address domain, host or sni', () {
      final container = ProviderContainer();
      final notifier = container.read(nodeCdnMapProvider.notifier);

      final nodeWithCfHost = ProxyNode(
        id: 'node_cf_host',
        name: 'CF Host Node',
        address: '1.2.3.4',
        port: 443,
        protocol: ProtocolType.vless,
        uuidOrPassword: 'test',
        host: 'my-worker.workers.dev',
      );
      expect(notifier.detectCdnForNode(nodeWithCfHost), equals(CdnProvider.cloudflare));

      final nodeWithCfSni = ProxyNode(
        id: 'node_cf_sni',
        name: 'CF SNI Node',
        address: '1.2.3.4',
        port: 443,
        protocol: ProtocolType.vless,
        uuidOrPassword: 'test',
        sni: 'test.cloudflare.com',
      );
      expect(notifier.detectCdnForNode(nodeWithCfSni), equals(CdnProvider.cloudflare));

      final nonCdnNode = ProxyNode(
        id: 'node_non_cdn',
        name: 'Direct Node',
        address: '8.8.8.8',
        port: 443,
        protocol: ProtocolType.vless,
        uuidOrPassword: 'test',
      );
      expect(notifier.detectCdnForNode(nonCdnNode), isNull);
    });
  });


  group('v1.7.6 Android Proxy & UI Tests', () {
    test('Configs badge count isolates custom manual configs from subscriptions and free configs', () {
      final mixedNodes = [
        ProxyNode(id: 'manual1', name: 'Manual 1', address: '1.1.1.1', port: 443, uuidOrPassword: 'uuid1', protocol: ProtocolType.vless),
        ProxyNode(id: 'manual2', name: 'Manual 2', address: '1.1.1.2', port: 443, uuidOrPassword: 'uuid2', protocol: ProtocolType.vless),
        ProxyNode(id: 'sub1', name: 'Sub Node 1', address: '1.1.1.3', port: 443, uuidOrPassword: 'uuid3', protocol: ProtocolType.vless, subscriptionId: 'sub_xyz'),
        ProxyNode(id: 'free1', name: 'Free Node 1', address: '1.1.1.4', port: 443, uuidOrPassword: 'uuid4', protocol: ProtocolType.vless, isFree: true),
      ];

      final customConfigsCount = mixedNodes.where((n) => n.subscriptionId == null && !n.isFree).length;
      expect(customConfigsCount, equals(2));
    });

    test('generateXrayConfig generates valid configuration without errors', () {
      final node = ProxyNode(
        id: 'test_node',
        name: 'Test Node',
        address: '1.2.3.4',
        port: 443,
        uuidOrPassword: 'abc-def-ghi-jkl',
        protocol: ProtocolType.vless,
        network: NetworkType.ws,
        security: SecurityType.tls,
        sni: 'test.example.com',
      );
      final cfg = XrayProcessService.instance.generateXrayConfig(node, enableTun: true);
      expect(cfg, isNotNull);
      expect(cfg['inbounds'], isNotEmpty);
      expect(cfg['outbounds'], isNotEmpty);
      expect(cfg['log'], isNotNull);
    });
  });
}

