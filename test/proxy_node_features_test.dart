import 'package:flutter_test/flutter_test.dart';
import 'package:v2raypro/models/proxy_node.dart';

void main() {
  test('ProxyNode toShareUrl and copyWith test', () {
    final node = ProxyNode(
      id: 'test-1',
      name: 'CF Server',
      protocol: ProtocolType.vless,
      address: '104.18.0.1',
      port: 443,
      uuidOrPassword: 'uuid-1234',
      network: NetworkType.ws,
      security: SecurityType.tls,
      sni: 'example.com',
      path: '/ws',
    );

    final shareUrl = node.toShareUrl();
    expect(shareUrl, contains('vless://uuid-1234@104.18.0.1:443'));
    expect(shareUrl, contains('security=tls'));
    expect(shareUrl, contains('type=ws'));
    expect(shareUrl, contains('sni=example.com'));
    expect(shareUrl, contains('path=%2Fws'));
    expect(shareUrl, contains('#CF%20Server'));

    final updated = node.copyWith(
      name: 'Renamed CF',
      port: 8443,
      security: SecurityType.reality,
      publicKey: 'pbk-key',
    );

    expect(updated.name, 'Renamed CF');
    expect(updated.port, 8443);
    expect(updated.security, SecurityType.reality);
    expect(updated.publicKey, 'pbk-key');
  });
}