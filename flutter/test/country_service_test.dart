import 'package:flutter_test/flutter_test.dart';
import 'package:v2raypro/models/proxy_node.dart';
import 'package:v2raypro/services/country_service.dart';

void main() {
  group('CountryService Unit Tests', () {
    test('extractFlagEmoji detects German flag surrogate pair', () {
      final flagStr = '🇩🇪 Germany Server';
      final code = CountryService.extractFlagEmoji(flagStr);
      expect(code, equals('DE'));
    });

    test('extractFlagEmoji detects US flag surrogate pair', () {
      final flagStr = 'Fast Vless 🇺🇸 #1';
      final code = CountryService.extractFlagEmoji(flagStr);
      expect(code, equals('US'));
    });

    test('extractCountryCodeFromName detects brackets [DE], (US), [TR]', () {
      expect(CountryService.extractCountryCodeFromName('[DE] Fast Server'), equals('DE'));
      expect(CountryService.extractCountryCodeFromName('(US) Cloudflare CDN'), equals('US'));
      expect(CountryService.extractCountryCodeFromName('TR - Istanbul Vless'), equals('TR'));
      expect(CountryService.extractCountryCodeFromName('VLESS-DE-01'), equals('DE'));
    });

    test('extractCountryCodeFromName detects country names', () {
      expect(CountryService.extractCountryCodeFromName('Germany High Speed'), equals('DE'));
      expect(CountryService.extractCountryCodeFromName('Netherlands VIP'), equals('NL'));
      expect(CountryService.extractCountryCodeFromName('United Kingdom #2'), equals('GB'));
      expect(CountryService.extractCountryCodeFromName('France Server'), equals('FR'));
    });

    test('extractCountryFromHost detects TLDs', () {
      expect(CountryService.extractCountryFromHost('node.server.de'), equals('DE'));
      expect(CountryService.extractCountryFromHost('vpn.domain.fr'), equals('FR'));
      expect(CountryService.extractCountryFromHost('us.gateway.nl'), equals('NL'));
      expect(CountryService.extractCountryFromHost('generic.domain.com'), isNull);
    });

    test('resolveSync resolves country code synchronously from node', () {
      final node = ProxyNode(
        id: 'test-1',
        name: '🇩🇪 Frankfurt Cloudflare',
        protocol: ProtocolType.vless,
        address: '1.2.3.4',
        port: 443,
        uuidOrPassword: 'test',
      );
      final code = CountryService.resolveSync(node);
      expect(code, equals('DE'));
    });

    test('ProxyNode stores and serializes countryCode', () {
      final node = ProxyNode(
        id: 'test-2',
        name: 'Node with Country',
        protocol: ProtocolType.vless,
        address: '1.2.3.4',
        port: 443,
        uuidOrPassword: 'test',
        countryCode: 'TR',
        country: 'Turkey',
      );

      final json = node.toJson();
      expect(json['country_code'], equals('TR'));
      expect(json['country'], equals('Turkey'));

      final parsed = ProxyNode.fromJson(json);
      expect(parsed.countryCode, equals('TR'));
      expect(parsed.country, equals('Turkey'));
    });
  });
}
