import 'package:flutter_test/flutter_test.dart';
import '../lib/utils/config_parser.dart';
import '../lib/models/proxy_node.dart';

void main() {
  test('Parses user VLESS XHTTP URL correctly', () {
    final url = 'vless://a6be2b03-b846-49c8-ad62-79b1a773b960@8.6.112.246:2053?encryption=none&security=tls&sni=gaia.payamnews.com&fp=chrome&alpn=h2%2Chttp%2F1.1&type=xhttp&host=gaia.payamnews.com&path=%2Fpkgs%2F&mode=auto&extra=%7B%22mode%22%3A%22auto%22%2C%22xPaddingBytes%22%3A%22100-1000%22%7D#cf2';
    final node = ConfigParser.parseSingle(url);
    expect(node, isNotNull);
    expect(node!.name, 'cf2');
    expect(node.protocol, ProtocolType.vless);
    expect(node.address, '8.6.112.246');
    expect(node.port, 2053);
    expect(node.uuidOrPassword, 'a6be2b03-b846-49c8-ad62-79b1a773b960');
    expect(node.network, NetworkType.xhttp);
    expect(node.security, SecurityType.tls);
    expect(node.sni, 'gaia.payamnews.com');
    expect(node.host, 'gaia.payamnews.com');
    expect(node.path, '/pkgs/');
    expect(node.mode, 'auto');
    expect(node.fingerprint, 'chrome');
    expect(node.alpn, ['h2', 'http/1.1']);
    expect(node.extra, contains('xPaddingBytes'));
  });
}
