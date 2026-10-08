import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import '../models/proxy_node.dart';
import 'cdn_scanner_service.dart';
import 'cloudflare_scanner_service.dart';

class LocalGeoIp {
  static final LocalGeoIp instance = LocalGeoIp._internal();
  LocalGeoIp._internal();

  bool _loaded = false;
  bool _loading = false;
  Uint32List? _startArr;
  Uint32List? _endArr;
  Uint16List? _cIdxArr;
  final List<String> _countryCodes = [];

  static String? findGeoIpDatPath() {
    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final candidates = [
        "$exeDir/xray/geoip.dat",
        "$exeDir/geoip.dat",
        "$exeDir/bin/geoip.dat",
        "$exeDir/assets/bin/geoip.dat",
        "$exeDir/data/flutter_assets/assets/bin/geoip.dat",
        "assets/bin/geoip.dat",
        "flutter/assets/bin/geoip.dat",
        "build/windows/xray/geoip.dat",
        "dist/v2raypro/xray/geoip.dat",
        "geoip.dat",
        "xray/geoip.dat",
      ];
      for (final c in candidates) {
        if (File(c).existsSync()) return c;
      }
    } catch (_) {}
    return null;
  }

  Future<void> ensureLoaded() async {
    if (_loaded || _loading) return;
    _loading = true;
    try {
      final path = findGeoIpDatPath();
      if (path == null) {
        _loading = false;
        return;
      }
      final file = File(path);
      if (!file.existsSync()) {
        _loading = false;
        return;
      }

      final bytes = await file.readAsBytes();
      int offset = 0;

      final ranges = <_GeoRange>[];
      final cMap = <String, int>{};

      while (offset < bytes.length) {
        final tag = bytes[offset++];
        final fieldNum = tag >> 3;
        final wireType = tag & 0x07;
        if (fieldNum == 1 && wireType == 2) {
          int len = 0, shift = 0;
          while (true) {
            final b = bytes[offset++];
            len |= (b & 0x7F) << shift;
            if ((b & 0x80) == 0) break;
            shift += 7;
          }
          final end = offset + len;
          String countryCode = '';
          int cIndex = -1;
          while (offset < end) {
            final entryTag = bytes[offset++];
            final entryField = entryTag >> 3;
            final entryWire = entryTag & 0x07;
            if (entryField == 1 && entryWire == 2) {
              int strLen = 0, sShift = 0;
              while (true) {
                final b = bytes[offset++];
                strLen |= (b & 0x7F) << sShift;
                if ((b & 0x80) == 0) break;
                sShift += 7;
              }
              countryCode = String.fromCharCodes(bytes.sublist(offset, offset + strLen)).toUpperCase();
              offset += strLen;
              if (countryCode.length == 2) {
                if (!cMap.containsKey(countryCode)) {
                  cMap[countryCode] = _countryCodes.length;
                  _countryCodes.add(countryCode);
                }
                cIndex = cMap[countryCode]!;
              } else {
                cIndex = -1;
              }
            } else if (entryField == 2 && entryWire == 2) {
              int cLen = 0, cShift = 0;
              while (true) {
                final b = bytes[offset++];
                cLen |= (b & 0x7F) << cShift;
                if ((b & 0x80) == 0) break;
                cShift += 7;
              }
              final cEnd = offset + cLen;
              if (cIndex < 0) {
                offset = cEnd;
                continue;
              }
              List<int>? ipBytes;
              int prefix = 32;
              while (offset < cEnd) {
                final cfTag = bytes[offset++];
                final cfField = cfTag >> 3;
                final cfWire = cfTag & 0x07;
                if (cfField == 1 && cfWire == 2) {
                  int ipLen = 0, iShift = 0;
                  while (true) {
                    final b = bytes[offset++];
                    ipLen |= (b & 0x7F) << iShift;
                    if ((b & 0x80) == 0) break;
                    iShift += 7;
                  }
                  ipBytes = bytes.sublist(offset, offset + ipLen);
                  offset += ipLen;
                } else if (cfField == 2 && cfWire == 0) {
                  int pVal = 0, pShift = 0;
                  while (true) {
                    final b = bytes[offset++];
                    pVal |= (b & 0x7F) << pShift;
                    if ((b & 0x80) == 0) break;
                    pShift += 7;
                  }
                  prefix = pVal;
                }
              }
              if (ipBytes != null && ipBytes.length == 4) {
                int ipNum = ((ipBytes[0] << 24) | (ipBytes[1] << 16) | (ipBytes[2] << 8) | ipBytes[3]) & 0xFFFFFFFF;
                int mask = prefix == 0 ? 0 : ((0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF);
                int start = ipNum & mask;
                int endRange = (start | (~mask & 0xFFFFFFFF)) & 0xFFFFFFFF;
                ranges.add(_GeoRange(start, endRange, prefix, cIndex));
              }
            } else {
              if (entryWire == 0) while ((bytes[offset++] & 0x80) != 0) {}
              else if (entryWire == 2) {
                int sLen = 0, sShift = 0;
                while (true) {
                  final b = bytes[offset++];
                  sLen |= (b & 0x7F) << sShift;
                  if ((b & 0x80) == 0) break;
                  sShift += 7;
                }
                offset += sLen;
              }
            }
          }
        }
      }

      ranges.sort((a, b) {
        final c = a.start.compareTo(b.start);
        if (c != 0) return c;
        return b.prefix.compareTo(a.prefix);
      });

      final n = ranges.length;
      _startArr = Uint32List(n);
      _endArr = Uint32List(n);
      _cIdxArr = Uint16List(n);
      for (int i = 0; i < n; i++) {
        _startArr![i] = ranges[i].start;
        _endArr![i] = ranges[i].end;
        _cIdxArr![i] = ranges[i].countryIndex;
      }
      _loaded = true;
    } catch (_) {} finally {
      _loading = false;
    }
  }

  String? lookup(String ipStr) {
    if (!_loaded || _startArr == null) return null;
    final parts = ipStr.trim().split('.');
    if (parts.length != 4) return null;
    final b0 = int.tryParse(parts[0]);
    final b1 = int.tryParse(parts[1]);
    final b2 = int.tryParse(parts[2]);
    final b3 = int.tryParse(parts[3]);
    if (b0 == null || b1 == null || b2 == null || b3 == null) return null;
    final target = ((b0 << 24) | (b1 << 16) | (b2 << 8) | b3) & 0xFFFFFFFF;

    int low = 0;
    int high = _startArr!.length - 1;
    int match = -1;

    while (low <= high) {
      int mid = (low + high) >> 1;
      int s = _startArr![mid];
      if (s <= target) {
        if (target <= _endArr![mid]) {
          match = mid;
        }
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }

    if (match >= 0) return _countryCodes[_cIdxArr![match]];
    return null;
  }
}

class _GeoRange {
  final int start;
  final int end;
  final int prefix;
  final int countryIndex;
  _GeoRange(this.start, this.end, this.prefix, this.countryIndex);
}

class CountryService {
  static final CountryService instance = CountryService._internal();
  CountryService._internal() {
    LocalGeoIp.instance.ensureLoaded();
  }

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

  static bool isCdnOrCloudflare(String address) {
    final clean = address.trim().toLowerCase();
    if (CloudflareScannerService.isCloudflareHostSync(clean)) return true;
    if (CdnScannerService.detectCdnHostSync(clean) != null) return true;
    if (clean.startsWith('104.') ||
        clean.startsWith('172.6') ||
        clean.startsWith('188.114.') ||
        clean.startsWith('162.159.') ||
        clean.startsWith('8.6.')) {
      return true;
    }
    return false;
  }

  /// Resolves country code for a ProxyNode synchronously if cached or present in name/host/local IP
  static String? resolveSync(ProxyNode node) {
    if (node.countryCode != null && node.countryCode!.trim().length == 2) {
      return node.countryCode!.trim().toUpperCase();
    }
    // 1. Explicit remarks/name text (flags, [DE], country name)
    final fromName = extractCountryCodeFromName(node.name);
    if (fromName != null) return fromName;

    final addr = node.address.trim().toLowerCase();
    if (_cache.containsKey(addr)) return _cache[addr];

    // 2. If address is a CDN or Cloudflare Anycast IP, DO NOT lookup in GeoIP!
    // Cloudflare/CDN Anycast IPs are registered in US and will falsely label proxies as US.
    if (isCdnOrCloudflare(addr)) {
      return null;
    }

    final fromHost = extractCountryFromHost(addr);
    if (fromHost != null) return fromHost;

    // 3. For direct non-CDN VPS IPs, local GeoIP lookup is valid
    final localCode = LocalGeoIp.instance.lookup(addr);
    if (localCode != null) {
      _cache[addr] = localCode;
      return localCode;
    }

    return null;
  }

  /// Resolves country code for a ProxyNode asynchronously 100% offline via local GeoIP
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

    final addr = node.address.trim().toLowerCase();

    // 3. Check memory cache for this host/address
    if (_cache.containsKey(addr)) {
      return _cache[addr];
    }

    // 4. If address is a CDN or Cloudflare Anycast IP, DO NOT lookup in GeoIP!
    if (isCdnOrCloudflare(addr)) {
      return null;
    }

    final fromHost = extractCountryFromHost(addr);
    if (fromHost != null) {
      _cache[addr] = fromHost;
      return fromHost;
    }

    // 5. Ensure local GeoIP database is loaded
    await LocalGeoIp.instance.ensureLoaded();

    // 6. Check if address is an IP or resolve domain
    String ip = addr;
    if (!RegExp(r'^\d+\.\d+\.\d+\.\d+$').hasMatch(addr)) {
      try {
        final lookup = await InternetAddress.lookup(addr).timeout(const Duration(seconds: 1));
        if (lookup.isNotEmpty) {
          ip = lookup.first.address;
          if (isCdnOrCloudflare(ip)) {
            return null;
          }
        }
      } catch (_) {}
    }

    final localCode = LocalGeoIp.instance.lookup(ip);
    if (localCode != null && localCode.length == 2) {
      _cache[addr] = localCode;
      return localCode;
    }

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

  static String? getCountryName(String? code) {
    if (code == null || code.trim().isEmpty) return null;
    final upper = code.trim().toUpperCase();
    return _codeToCountryName[upper] ?? upper;
  }

  static const Map<String, String> _codeToCountryName = {
    'US': 'United States',
    'DE': 'Germany',
    'FR': 'France',
    'NL': 'Netherlands',
    'GB': 'United Kingdom',
    'CA': 'Canada',
    'TR': 'Turkey',
    'FI': 'Finland',
    'SG': 'Singapore',
    'JP': 'Japan',
    'SE': 'Sweden',
    'CH': 'Switzerland',
    'IT': 'Italy',
    'ES': 'Spain',
    'PL': 'Poland',
    'RU': 'Russia',
    'IR': 'Iran',
    'AE': 'United Arab Emirates',
    'AT': 'Austria',
    'AU': 'Australia',
    'UA': 'Ukraine',
    'NO': 'Norway',
    'DK': 'Denmark',
    'BE': 'Belgium',
    'IE': 'Ireland',
    'HK': 'Hong Kong',
    'KR': 'South Korea',
    'BR': 'Brazil',
    'IN': 'India',
    'RO': 'Romania',
    'BG': 'Bulgaria',
    'CZ': 'Czech Republic',
    'HU': 'Hungary',
    'LT': 'Lithuania',
    'LV': 'Latvia',
    'EE': 'Estonia',
  };
}
