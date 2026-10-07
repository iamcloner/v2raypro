import 'dart:convert';
import 'dart:io';
import '../models/proxy_node.dart';

class CountryService {
  static final CountryService instance = CountryService._internal();
  CountryService._internal();

  static final Map<String, String> _cache = {};

  /// Decodes a flag emoji (e.g. 'DE', 'US')
  static String? extractFlagEmoji(String text) {
    if (text.isEmpty) return null;
    for (int i = 0; i <= text.length - 4; i++) {
      if (text.codeUnitAt(i) == 0xD83C &&
          text.codeUnitAt(i + 1) >= 0xDDE6 &&
          text.codeUnitAt(i + 1) <= 0xDDFF &&
          text.codeUnitAt(i + 2) == 0xD83C &&
          text.codeUnitAt(i + 3) >= 0xDDE6 &&
          text.codeUnitAt(i + 3) <= 0xDDFF) {
        final c1 = String.fromCharCode(65 + (text.codeUnitAt(i + 1) - 0xDDE6));
        final c2 = String.fromCharCode(65 + (text.codeUnitAt(i + 3) - 0xDDE6));
        return '$c1$c2'.toUpperCase();
      }
    }
    return null;
  }

  /// Extracts 2-letter ISO country code from remarks/name text
  static String? extractCountryCodeFromName(String name) {
    if (name.isEmpty) return null;

    // 1. Check flag emojis
    final flag = extractFlagEmoji(name);
    if (flag != null) return flag;

    // 2. Common brackets/prefixes: [DE], (US), [TR], DE-, US-, etc.
    final upper = name.toUpperCase();
    final codeRegex = RegExp(r'(?:\[|\(|\b)([A-Z]{2})(?:\]|\)|\s*[-_:])');
    final match = codeRegex.firstMatch(upper);
    if (match != null) {
      final code = match.group(1);
      if (code != null && _knownCountryCodes.contains(code)) {
        return code;
      }
    }

    // 3. Known country names in string
    for (final entry in _countryNameToCode.entries) {
      if (upper.contains(entry.key)) {
        return entry.value;
      }
    }

    return null;
  }

  /// Extracts country code from domain TLD if applicable
  static String? extractCountryFromHost(String host) {
    final lower = host.trim().toLowerCase();
    final parts = lower.split('.');
    if (parts.length >= 2) {
      final tld = parts.last.toUpperCase();
      if (tld.length == 2 && _knownCountryCodes.contains(tld) && tld != 'CO' && tld != 'IO' && tld != 'ME' && tld != 'TV') {
        return tld;
      }
    }
    return null;
  }

  /// Resolves country code for a ProxyNode synchronously if cached or present in name/host
  static String? resolveSync(ProxyNode node) {
    if (node.countryCode != null && node.countryCode!.trim().length == 2) {
      return node.countryCode!.trim().toUpperCase();
    }
    final fromName = extractCountryCodeFromName(node.name);
    if (fromName != null) return fromName;

    final addr = node.address.trim().toLowerCase();
    if (_cache.containsKey(addr)) return _cache[addr];

    final fromHost = extractCountryFromHost(addr);
    if (fromHost != null) return fromHost;

    return null;
  }

  /// Resolves country code for a ProxyNode asynchronously
  /// Combines instant heuristic extraction with asynchronous cached GeoIP lookup.
  Future<String?> resolveCountryCode(ProxyNode node) async {
    // 1. If already set on node
    if (node.countryCode != null && node.countryCode!.trim().length == 2) {
      return node.countryCode!.trim().toUpperCase();
    }

    // 2. Check node remarks/name
    final fromName = extractCountryCodeFromName(node.name);
    if (fromName != null) {
      _cache[node.address.trim().toLowerCase()] = fromName;
      return fromName;
    }

    // 3. Check memory cache for this host/address
    final addr = node.address.trim().toLowerCase();
    if (_cache.containsKey(addr)) {
      return _cache[addr];
    }

    // 4. Check domain TLD
    final fromHost = extractCountryFromHost(addr);
    if (fromHost != null) {
      _cache[addr] = fromHost;
      return fromHost;
    }

    // 5. Asynchronous GeoIP lookup
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 2);
      try {
        final queryAddr = Uri.encodeComponent(addr);
        final req = await client.getUrl(Uri.parse('http://ip-api.com/json/$queryAddr?fields=countryCode')).timeout(const Duration(seconds: 2));
        final resp = await req.close().timeout(const Duration(seconds: 2));
        if (resp.statusCode == 200) {
          final body = await resp.transform(utf8.decoder).join();
          final data = jsonDecode(body);
          final code = data['countryCode']?.toString().trim().toUpperCase();
          if (code != null && code.length == 2) {
            _cache[addr] = code;
            return code;
          }
        }
      } catch (_) {} finally {
        client.close(force: true);
      }
    } catch (_) {}

    return null;
  }

  static const Set<String> _knownCountryCodes = {
    'AD', 'AE', 'AF', 'AG', 'AI', 'AL', 'AM', 'AO', 'AQ', 'AR', 'AS', 'AT', 'AU', 'AW', 'AX', 'AZ',
    'BA', 'BB', 'BD', 'BE', 'BF', 'BG', 'BH', 'BI', 'BJ', 'BL', 'BM', 'BN', 'BO', 'BQ', 'BR', 'BS',
    'BT', 'BV', 'BW', 'BY', 'BZ', 'CA', 'CC', 'CD', 'CF', 'CG', 'CH', 'CI', 'CK', 'CL', 'CM', 'CN',
    'CR', 'CU', 'CV', 'CW', 'CX', 'CY', 'CZ', 'DE', 'DJ', 'DK', 'DM', 'DO', 'DZ', 'EC', 'EE', 'EG',
    'EH', 'ER', 'ES', 'ET', 'FI', 'FJ', 'FK', 'FM', 'FO', 'FR', 'GA', 'GB', 'GD', 'GE', 'GF', 'GG',
    'GH', 'GI', 'GL', 'GM', 'GN', 'GP', 'GQ', 'GR', 'GS', 'GT', 'GU', 'GW', 'GY', 'HK', 'HM', 'HN',
    'HR', 'HT', 'HU', 'ID', 'IE', 'IL', 'IM', 'IN', 'IO', 'IQ', 'IR', 'IS', 'IT', 'JE', 'JM', 'JO',
    'JP', 'KE', 'KG', 'KH', 'KI', 'KM', 'KN', 'KP', 'KR', 'KW', 'KY', 'KZ', 'LA', 'LB', 'LC', 'LI',
    'LK', 'LR', 'LS', 'LT', 'LU', 'LV', 'LY', 'MA', 'MC', 'MD', 'ME', 'MF', 'MG', 'MH', 'MK', 'ML',
    'MM', 'MN', 'MO', 'MP', 'MQ', 'MR', 'MS', 'MT', 'MU', 'MV', 'MW', 'MX', 'MY', 'MZ', 'NA', 'NC',
    'NE', 'NF', 'NG', 'NI', 'NL', 'NO', 'NP', 'NR', 'NU', 'NZ', 'OM', 'PA', 'PE', 'PF', 'PG', 'PH',
    'PK', 'PL', 'PM', 'PN', 'PR', 'PS', 'PT', 'PW', 'PY', 'QA', 'RE', 'RO', 'RS', 'RU', 'RW', 'SA',
    'SB', 'SC', 'SD', 'SE', 'SG', 'SH', 'SI', 'SJ', 'SK', 'SL', 'SM', 'SN', 'SO', 'SR', 'SS', 'ST',
    'SV', 'SX', 'SY', 'SZ', 'TC', 'TD', 'TF', 'TG', 'TH', 'TJ', 'TK', 'TL', 'TM', 'TN', 'TO', 'TR',
    'TT', 'TV', 'TW', 'TZ', 'UA', 'UG', 'UM', 'US', 'UY', 'UZ', 'VA', 'VC', 'VE', 'VG', 'VI', 'VN',
    'VU', 'WF', 'WS', 'YE', 'YT', 'ZA', 'ZM', 'ZW'
  };

  static const Map<String, String> _countryNameToCode = {
    'GERMANY': 'DE',
    'DEUTSCHLAND': 'DE',
    'UNITED STATES': 'US',
    'AMERICA': 'US',
    'USA': 'US',
    'FRANCE': 'FR',
    'NETHERLANDS': 'NL',
    'HOLLAND': 'NL',
    'TURKEY': 'TR',
    'TURKIYE': 'TR',
    'FINLAND': 'FI',
    'UNITED KINGDOM': 'GB',
    'ENGLAND': 'GB',
    'BRITAIN': 'GB',
    'UK': 'GB',
    'CANADA': 'CA',
    'SINGAPORE': 'SG',
    'JAPAN': 'JP',
    'SWEDEN': 'SE',
    'SWITZERLAND': 'CH',
    'ITALY': 'IT',
    'SPAIN': 'ES',
    'POLAND': 'PL',
    'RUSSIA': 'RU',
    'IRAN': 'IR',
    'EMIRATES': 'AE',
    'UAE': 'AE',
    'DUBAI': 'AE',
    'AUSTRIA': 'AT',
    'AUSTRALIA': 'AU',
    'UKRAINE': 'UA',
    'NORWAY': 'NO',
    'DENMARK': 'DK',
    'BELGIUM': 'BE',
    'IRELAND': 'IE',
    'HONG KONG': 'HK',
    'SOUTH KOREA': 'KR',
    'KOREA': 'KR',
    'BRAZIL': 'BR',
    'INDIA': 'IN',
    'ROMANIA': 'RO',
    'BULGARIA': 'BG',
    'CZECH': 'CZ',
    'HUNGARY': 'HU',
    'LITHUANIA': 'LT',
    'LATVIA': 'LV',
    'ESTONIA': 'EE',
  };
}
