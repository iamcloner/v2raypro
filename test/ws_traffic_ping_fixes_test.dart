import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:v2raypro/models/proxy_node.dart';
import 'package:v2raypro/services/ping_service.dart';
import 'package:v2raypro/utils/config_generator.dart';

void main() {
  group('WebSocket Configuration & Flow Fixes Tests', () {
    test('generateXrayConfig generates safe WebSocket path and host headers', () {
      final node = ProxyNode(
        id: 'ws_test_1',
        name: 'WS Node Without Leading Slash',
        protocol: ProtocolType.vless,
        address: '104.16.1.1',
        port: 443,
        uuidOrPassword: 'uuid-1234',
        network: NetworkType.ws,
        path: 'graphql?ed=2048',
        host: 'cdn.example.com',
        security: SecurityType.tls,
        sni: 'cdn.example.com',
      );

      final config = ConfigGenerator.generateXrayConfig(node);
      final outbounds = config['outbounds'] as List;
      final proxyOutbound = outbounds.firstWhere((o) => o['tag'] == 'proxy');
      final streamSettings = proxyOutbound['streamSettings'] as Map<String, dynamic>;
      final wsSettings = streamSettings['wsSettings'] as Map<String, dynamic>;

      expect(wsSettings['path'], equals('/graphql?ed=2048'));
      expect(wsSettings['host'], equals('cdn.example.com'));
      expect(wsSettings['headers']['Host'], equals('cdn.example.com'));
    });

    test('generateXrayConfig omits flow for WebSocket even if node has flow set', () {
      final node = ProxyNode(
        id: 'ws_test_flow',
        name: 'VLESS WS Node With Incompatible Flow',
        protocol: ProtocolType.vless,
        address: '104.16.1.1',
        port: 443,
        uuidOrPassword: 'uuid-1234',
        network: NetworkType.ws,
        path: '/ws',
        host: 'ws.example.com',
        security: SecurityType.tls,
        flow: 'xtls-rprx-vision',
      );

      final config = ConfigGenerator.generateXrayConfig(node);
      final outbounds = config['outbounds'] as List;
      final proxyOutbound = outbounds.firstWhere((o) => o['tag'] == 'proxy');
      final users = (proxyOutbound['settings']['vnext'] as List)[0]['users'] as List;
      final user = users[0] as Map<String, dynamic>;

      // flow must be stripped for WebSocket transport
      expect(user.containsKey('flow'), isFalse);
    });

    test('generateXrayConfig keeps flow for TCP transport', () {
      final node = ProxyNode(
        id: 'tcp_test_flow',
        name: 'VLESS TCP Node With Flow',
        protocol: ProtocolType.vless,
        address: '104.16.1.1',
        port: 443,
        uuidOrPassword: 'uuid-1234',
        network: NetworkType.tcp,
        security: SecurityType.reality,
        flow: 'xtls-rprx-vision',
      );

      final config = ConfigGenerator.generateXrayConfig(node);
      final outbounds = config['outbounds'] as List;
      final proxyOutbound = outbounds.firstWhere((o) => o['tag'] == 'proxy');
      final users = (proxyOutbound['settings']['vnext'] as List)[0]['users'] as List;
      final user = users[0] as Map<String, dynamic>;

      expect(user['flow'], equals('xtls-rprx-vision'));
    });

    test('generateSingboxConfig includes transport for WebSocket nodes', () {
      final node = ProxyNode(
        id: 'singbox_ws',
        name: 'Singbox WS Node',
        protocol: ProtocolType.vless,
        address: '104.16.1.1',
        port: 443,
        uuidOrPassword: 'uuid-1234',
        network: NetworkType.ws,
        path: 'chat',
        host: 'cdn.example.com',
        security: SecurityType.tls,
      );

      final config = ConfigGenerator.generateSingboxConfig(node);
      final outbounds = config['outbounds'] as List;
      final proxy = outbounds.firstWhere((o) => o['tag'] == 'proxy');

      expect(proxy.containsKey('transport'), isTrue);
      expect(proxy['transport']['type'], equals('ws'));
      expect(proxy['transport']['path'], equals('/chat'));
      expect(proxy['transport']['headers']['Host'], equals('cdn.example.com'));
    });
  });

  group('PingService Protocol Handshake Tests', () {
    test('WebSocket probe accepts 400 Bad Request with HTML body without rejecting as CDN error', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((client) {
        client.listen((data) {
          final req = utf8.decode(data);
          if (req.contains('Upgrade: websocket')) {
            client.write(
              'HTTP/1.1 400 Bad Request\r\n'
              'Content-Type: text/html\r\n\r\n'
              '<html><body><h1>400 Bad Request</h1></body></html>',
            );
          }
        });
      });

      final wsNode = ProxyNode(
        id: 'mock_ws',
        name: 'Mock WS Node',
        protocol: ProtocolType.vless,
        address: '127.0.0.1',
        port: server.port,
        uuidOrPassword: 'test-uuid',
        network: NetworkType.ws,
        path: '/vless-ws',
        security: SecurityType.none,
      );

      final delay = await PingService.instance.pingProtocolDelay(
        wsNode,
        timeout: const Duration(seconds: 2),
      );

      await server.close();

      expect(delay, isNotNull);
      expect(delay! >= 0, isTrue);
    });
  });
}