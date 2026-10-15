import 'dart:convert';
import 'dart:isolate';
import 'package:uuid/uuid.dart';
import '../models/proxy_node.dart';

class ConfigParser {
  /// Asynchronously parse batch of configs in a background isolate to avoid freezing the UI
  static Future<List<ProxyNode>> parseBatchAsync(String content) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return [];
    if (trimmed.length < 5000 && !trimmed.contains('\n') && !trimmed.contains('\r')) {
      return parseBatch(trimmed);
    }
    try {
      return await Isolate.run(() => parseBatch(content));
    } catch (_) {
      return parseBatch(content);
    }
  }

  /// Parse a single config link or batch of links (newline-separated or base64 subscription or sing-box json)
  static List<ProxyNode> parseBatch(String content) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return [];

    // Attempt sing-box JSON configuration detection
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      final singBoxNodes = parseSingBoxConfig(trimmed);
      if (singBoxNodes.isNotEmpty) {
        return singBoxNodes;
      }
    }

    // Attempt base64 subscription decoding
    String decoded = trimmed;
    try {
      final normalized = _normalizeBase64(trimmed);
      final bytes = base64Decode(normalized);
      decoded = utf8.decode(bytes);
    } catch (_) {
      // Not a base64 subscription, use raw content
      decoded = trimmed;
    }

    // Check decoded payload for sing-box JSON
    if (decoded.trim().startsWith('{') || decoded.trim().startsWith('[')) {
      final singBoxNodes = parseSingBoxConfig(decoded.trim());
      if (singBoxNodes.isNotEmpty) {
        return singBoxNodes;
      }
    }

    final nodes = <ProxyNode>[];
    for (final rawLine in const LineSplitter().convert(decoded)) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('//') || line.startsWith('#')) continue;
      final node = parseSingle(line);
      if (node != null) {
        nodes.add(node);
      }
    }

    return nodes;
  }

  static ProxyNode? parseSingle(String url) {
    final trimmed = url.trim();
    if (trimmed.startsWith('vless://')) {
      return _parseVless(trimmed);
    } else if (trimmed.startsWith('vmess://')) {
      return _parseVmess(trimmed);
    } else if (trimmed.startsWith('trojan://')) {
      return _parseTrojan(trimmed);
    } else if (trimmed.startsWith('ss://')) {
      return _parseShadowsocks(trimmed);
    } else if (trimmed.startsWith('sing-box://') || trimmed.startsWith('singbox://')) {
      return _parseSingBoxUrl(trimmed);
    } else if (trimmed.startsWith('{')) {
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map<String, dynamic>) {
          if (decoded.containsKey('outbounds')) {
            final list = parseSingBoxConfig(trimmed);
            if (list.isNotEmpty) return list.first;
          }
          return parseSingBoxOutbound(decoded);
        }
      } catch (_) {}
    }
    return null;
  }

  static String _normalizeBase64(String input) {
    var str = input.replaceAll('\r', '').replaceAll('\n', '').trim();
    while (str.length % 4 != 0) {
      str += '=';
    }
    return str;
  }

  static ProxyNode? _parseVless(String url) {
    try {
      final uri = Uri.parse(url);
      final uuid = uri.userInfo;
      if (uuid.isEmpty) return null;

      final address = uri.host;
      if (address.isEmpty) return null;
      final port = uri.port > 0 ? uri.port : 443;

      final params = uri.queryParameters;
      final fragment = uri.fragment;
      final name = fragment.isNotEmpty
          ? Uri.decodeComponent(fragment)
          : '$address:$port';

      final typeStr = (params['type'] ?? 'tcp').toLowerCase();
      NetworkType network;
      switch (typeStr) {
        case 'xhttp':
          network = NetworkType.xhttp;
          break;
        case 'splithttp':
          network = NetworkType.splithttp;
          break;
        case 'ws':
          network = NetworkType.ws;
          break;
        case 'grpc':
          network = NetworkType.grpc;
          break;
        case 'h2':
          network = NetworkType.h2;
          break;
        case 'httpupgrade':
          network = NetworkType.httpUpgrade;
          break;
        default:
          network = NetworkType.tcp;
      }

      final secStr = (params['security'] ?? 'none').toLowerCase();
      SecurityType security;
      if (secStr == 'reality') {
        security = SecurityType.reality;
      } else if (secStr == 'tls') {
        security = SecurityType.tls;
      } else {
        security = SecurityType.none;
      }

      List<String>? alpnList;
      if (params.containsKey('alpn') && params['alpn']!.isNotEmpty) {
        alpnList = params['alpn']!.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      }

      return ProxyNode(
        id: const Uuid().v4(),
        name: name,
        protocol: ProtocolType.vless,
        address: address,
        port: port,
        uuidOrPassword: uuid,
        network: network,
        path: params['path'],
        host: params['host'],
        serviceName: params['serviceName'],
        security: security,
        sni: params['sni'] ?? params['host'],
        alpn: alpnList,
        allowInsecure: params['allowInsecure'] == '1' ||
            params['allowInsecure'] == 'true' ||
            params['insecure'] == '1' ||
            params['insecure'] == 'true',
        fingerprint: params['fp'] ?? params['fingerprint'],
        publicKey: params['pbk'],
        shortId: params['sid'],
        spiderX: params['spx'],
        mode: params['mode'],
        extra: params['extra'],
        flow: params['flow'],
        headerType: params['headerType'],
      );
    } catch (_) {
      return null;
    }
  }

  static ProxyNode? _parseVmess(String url) {
    try {
      final payload = url.substring('vmess://'.length).trim();
      final decodedJson = utf8.decode(base64Decode(_normalizeBase64(payload)));
      final map = jsonDecode(decodedJson) as Map<String, dynamic>;

      final address = (map['add'] ?? '').toString();
      final port = int.tryParse(map['port']?.toString() ?? '443') ?? 443;
      final uuid = (map['id'] ?? '').toString();
      final name = (map['ps'] ?? '').toString().isNotEmpty ? map['ps'].toString() : '$address:$port';
      final alterId = int.tryParse(map['aid']?.toString() ?? '0') ?? 0;

      final netStr = (map['net'] ?? 'tcp').toString().toLowerCase();
      NetworkType network;
      switch (netStr) {
        case 'xhttp':
          network = NetworkType.xhttp;
          break;
        case 'splithttp':
          network = NetworkType.splithttp;
          break;
        case 'ws':
          network = NetworkType.ws;
          break;
        case 'grpc':
          network = NetworkType.grpc;
          break;
        case 'h2':
          network = NetworkType.h2;
          break;
        default:
          network = NetworkType.tcp;
      }

      final tlsStr = (map['tls'] ?? '').toString().toLowerCase();
      final security = tlsStr == 'tls' ? SecurityType.tls : SecurityType.none;

      List<String>? alpnList;
      if (map['alpn'] != null) {
        if (map['alpn'] is List) {
          alpnList = (map['alpn'] as List).map((e) => e.toString()).toList();
        } else if (map['alpn'] is String && (map['alpn'] as String).isNotEmpty) {
          alpnList = (map['alpn'] as String).split(',').map((e) => e.trim()).toList();
        }
      }

      final allowInsecure = map['insecure'] == '1' ||
          map['insecure'] == true ||
          map['allowInsecure'] == '1' ||
          map['allowInsecure'] == true;

      return ProxyNode(
        id: const Uuid().v4(),
        name: name,
        protocol: ProtocolType.vmess,
        address: address,
        port: port,
        uuidOrPassword: uuid,
        alterId: alterId,
        cipher: (map['scy'] ?? 'auto').toString(),
        network: network,
        path: map['path']?.toString(),
        host: map['host']?.toString(),
        security: security,
        sni: map['sni']?.toString() ?? map['host']?.toString(),
        alpn: alpnList,
        allowInsecure: allowInsecure,
        fingerprint: map['fp']?.toString(),
        headerType: map['type']?.toString(),
      );
    } catch (_) {
      return null;
    }
  }

  static ProxyNode? _parseTrojan(String url) {
    try {
      final uri = Uri.parse(url);
      final password = uri.userInfo;
      if (password.isEmpty) return null;

      final address = uri.host;
      if (address.isEmpty) return null;
      final port = uri.port > 0 ? uri.port : 443;

      final params = uri.queryParameters;
      final fragment = uri.fragment;
      final name = fragment.isNotEmpty
          ? Uri.decodeComponent(fragment)
          : '$address:$port';

      final typeStr = (params['type'] ?? 'tcp').toLowerCase();
      NetworkType network;
      switch (typeStr) {
        case 'ws':
          network = NetworkType.ws;
          break;
        case 'grpc':
          network = NetworkType.grpc;
          break;
        case 'xhttp':
          network = NetworkType.xhttp;
          break;
        default:
          network = NetworkType.tcp;
      }

      final secStr = (params['security'] ?? 'tls').toLowerCase();
      final security = secStr == 'none' ? SecurityType.none : SecurityType.tls;

      List<String>? alpnList;
      if (params.containsKey('alpn') && params['alpn']!.isNotEmpty) {
        alpnList = params['alpn']!.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      }

      return ProxyNode(
        id: const Uuid().v4(),
        name: name,
        protocol: ProtocolType.trojan,
        address: address,
        port: port,
        uuidOrPassword: password,
        network: network,
        path: params['path'],
        host: params['host'],
        serviceName: params['serviceName'],
        security: security,
        sni: params['sni'] ?? params['host'],
        alpn: alpnList,
        allowInsecure: params['allowInsecure'] == '1' ||
            params['allowInsecure'] == 'true' ||
            params['insecure'] == '1' ||
            params['insecure'] == 'true',
        fingerprint: params['fp'] ?? params['fingerprint'],
        flow: params['flow'],
        headerType: params['headerType'],
      );
    } catch (_) {
      return null;
    }
  }

  static ProxyNode? _parseShadowsocks(String url) {
    try {
      final uri = Uri.parse(url);
      final name = uri.fragment.isNotEmpty ? Uri.decodeComponent(uri.fragment) : 'SS Node';

      String address = uri.host;
      int port = uri.port > 0 ? uri.port : 8388;
      String cipher = 'aes-256-gcm';
      String password = '';

      final userinfo = uri.userInfo;
      if (userinfo.contains(':')) {
        final parts = userinfo.split(':');
        cipher = parts[0];
        password = parts[1];
      } else if (userinfo.isNotEmpty) {
        try {
          final decoded = utf8.decode(base64Decode(_normalizeBase64(userinfo)));
          final parts = decoded.split(':');
          if (parts.length >= 2) {
            cipher = parts[0];
            password = parts.sublist(1).join(':');
          } else {
            password = userinfo;
          }
        } catch (_) {
          password = userinfo;
        }
      }

      if (address.isEmpty && uri.path.isNotEmpty) {
        try {
          final decoded = utf8.decode(base64Decode(_normalizeBase64(uri.path)));
          final atIdx = decoded.indexOf('@');
          if (atIdx > 0) {
            final creds = decoded.substring(0, atIdx).split(':');
            final server = decoded.substring(atIdx + 1).split(':');
            cipher = creds[0];
            password = creds[1];
            address = server[0];
            port = int.parse(server[1]);
          }
        } catch (_) {}
      }

      if (address.isEmpty) return null;

      return ProxyNode(
        id: const Uuid().v4(),
        name: name,
        protocol: ProtocolType.shadowsocks,
        address: address,
        port: port,
        uuidOrPassword: password,
        cipher: cipher,
      );
    } catch (_) {
      return null;
    }
  }

  static ProxyNode? _parseSingBoxUrl(String url) {
    try {
      final payload = url.replaceFirst(RegExp(r'^sing-?box://', caseSensitive: false), '').trim();
      if (payload.isEmpty) return null;

      // Try direct JSON
      if (payload.startsWith('{')) {
        final decoded = jsonDecode(payload);
        if (decoded is Map<String, dynamic>) {
          return parseSingBoxOutbound(decoded);
        }
      }

      // Try Base64 JSON
      try {
        final decodedBytes = base64Decode(_normalizeBase64(payload));
        final jsonStr = utf8.decode(decodedBytes);
        final decoded = jsonDecode(jsonStr);
        if (decoded is Map<String, dynamic>) {
          return parseSingBoxOutbound(decoded);
        }
      } catch (_) {}

      // Try URI decoded
      final uriDecoded = Uri.decodeComponent(payload);
      if (uriDecoded.startsWith('{')) {
        final decoded = jsonDecode(uriDecoded);
        if (decoded is Map<String, dynamic>) {
          return parseSingBoxOutbound(decoded);
        }
      }
    } catch (_) {}
    return null;
  }

  /// Parses a Sing-box outbound configuration map into a ProxyNode
  static ProxyNode? parseSingBoxOutbound(Map<String, dynamic> map) {
    try {
      final type = (map['type'] as String?)?.toLowerCase();
      if (type == null) return null;

      ProtocolType protocol;
      switch (type) {
        case 'vless':
          protocol = ProtocolType.vless;
          break;
        case 'vmess':
          protocol = ProtocolType.vmess;
          break;
        case 'trojan':
          protocol = ProtocolType.trojan;
          break;
        case 'shadowsocks':
          protocol = ProtocolType.shadowsocks;
          break;
        default:
          return null;
      }

      final address = (map['server'] as String?)?.trim() ?? '';
      if (address.isEmpty) return null;
      final port = (map['server_port'] as num?)?.toInt() ?? 443;
      final name = (map['tag'] as String?)?.trim() ?? '$address:$port';

      final uuidOrPassword = (map['uuid'] ?? map['password'] ?? '') as String;
      final flow = map['flow'] as String?;
      final cipher = map['method'] as String?;
      final alterId = (map['alter_id'] as num?)?.toInt() ?? 0;

      // TLS / Security
      SecurityType security = SecurityType.none;
      String? sni;
      List<String>? alpn;
      bool allowInsecure = false;
      String? fingerprint;
      String? publicKey;
      String? shortId;

      if (map['tls'] is Map) {
        final tls = map['tls'] as Map<String, dynamic>;
        if (tls['enabled'] == true) {
          security = SecurityType.tls;
          sni = tls['server_name'] as String?;
          if (tls['alpn'] is List) {
            alpn = (tls['alpn'] as List).map((e) => e.toString()).toList();
          }
          allowInsecure = tls['insecure'] == true;
          if (tls['utls'] is Map) {
            fingerprint = (tls['utls'] as Map)['fingerprint'] as String?;
          }
          if (tls['reality'] is Map) {
            final reality = tls['reality'] as Map<String, dynamic>;
            if (reality['enabled'] == true) {
              security = SecurityType.reality;
              publicKey = reality['public_key'] as String?;
              shortId = reality['short_id'] as String?;
            }
          }
        }
      }

      // Transport
      NetworkType network = NetworkType.tcp;
      String? path;
      String? host;
      String? serviceName;

      if (map['transport'] is Map) {
        final trans = map['transport'] as Map<String, dynamic>;
        final transType = (trans['type'] as String?)?.toLowerCase();
        switch (transType) {
          case 'ws':
            network = NetworkType.ws;
            path = trans['path'] as String?;
            if (trans['headers'] is Map) {
              host = (trans['headers'] as Map)['Host'] as String?;
            }
            break;
          case 'grpc':
            network = NetworkType.grpc;
            serviceName = trans['service_name'] as String?;
            break;
          case 'http':
            network = NetworkType.h2;
            path = trans['path'] as String?;
            host = trans['host'] is List ? (trans['host'] as List).firstOrNull?.toString() : trans['host'] as String?;
            break;
          case 'httpupgrade':
            network = NetworkType.httpUpgrade;
            path = trans['path'] as String?;
            host = trans['host'] as String?;
            break;
        }
      }

      return ProxyNode(
        id: const Uuid().v4(),
        name: name,
        protocol: protocol,
        address: address,
        port: port,
        uuidOrPassword: uuidOrPassword,
        alterId: alterId,
        cipher: cipher,
        network: network,
        path: path,
        host: host,
        serviceName: serviceName,
        security: security,
        sni: sni,
        alpn: alpn,
        allowInsecure: allowInsecure,
        fingerprint: fingerprint,
        publicKey: publicKey,
        shortId: shortId,
        flow: flow,
      );
    } catch (_) {
      return null;
    }
  }

  /// Parses a full Sing-box JSON configuration string
  static List<ProxyNode> parseSingBoxConfig(String jsonStr) {
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is Map<String, dynamic>) {
        if (decoded['outbounds'] is List) {
          final nodes = <ProxyNode>[];
          for (final ob in (decoded['outbounds'] as List)) {
            if (ob is Map<String, dynamic>) {
              final node = parseSingBoxOutbound(ob);
              if (node != null) nodes.add(node);
            }
          }
          return nodes;
        } else {
          final node = parseSingBoxOutbound(decoded);
          if (node != null) return [node];
        }
      } else if (decoded is List) {
        final nodes = <ProxyNode>[];
        for (final item in decoded) {
          if (item is Map<String, dynamic>) {
            final node = parseSingBoxOutbound(item);
            if (node != null) nodes.add(node);
          }
        }
        return nodes;
      }
    } catch (_) {}
    return [];
  }

  /// Serializes a ProxyNode into a Sing-box outbound configuration map
  static Map<String, dynamic> toSingBoxOutbound(ProxyNode node) {
    final map = <String, dynamic>{
      'type': node.protocol.name,
      'tag': node.name,
      'server': node.address,
      'server_port': node.port,
    };

    if (node.protocol == ProtocolType.vless || node.protocol == ProtocolType.vmess) {
      map['uuid'] = node.uuidOrPassword;
      if (node.protocol == ProtocolType.vmess && node.alterId > 0) {
        map['alter_id'] = node.alterId;
      }
      if (node.flow != null && node.flow!.isNotEmpty) {
        map['flow'] = node.flow;
      }
    } else if (node.protocol == ProtocolType.trojan) {
      map['password'] = node.uuidOrPassword;
    } else if (node.protocol == ProtocolType.shadowsocks) {
      map['password'] = node.uuidOrPassword;
      map['method'] = node.cipher ?? 'aes-128-gcm';
    }

    if (node.security == SecurityType.tls || node.security == SecurityType.reality) {
      final tls = <String, dynamic>{
        'enabled': true,
        'server_name': node.sni ?? node.host ?? node.address,
      };
      if (node.allowInsecure) {
        tls['insecure'] = true;
      }
      if (node.alpn != null && node.alpn!.isNotEmpty) {
        tls['alpn'] = node.alpn;
      }
      if (node.fingerprint != null && node.fingerprint!.isNotEmpty) {
        tls['utls'] = {
          'enabled': true,
          'fingerprint': node.fingerprint,
        };
      }
      if (node.security == SecurityType.reality) {
        tls['reality'] = {
          'enabled': true,
          'public_key': node.publicKey ?? '',
          'short_id': node.shortId ?? '',
        };
      }
      map['tls'] = tls;
    }

    if (node.network == NetworkType.ws) {
      final ws = <String, dynamic>{
        'type': 'ws',
        'path': node.path ?? '/',
      };
      if (node.host != null && node.host!.isNotEmpty) {
        ws['headers'] = {'Host': node.host};
      }
      map['transport'] = ws;
    } else if (node.network == NetworkType.grpc) {
      map['transport'] = {
        'type': 'grpc',
        'service_name': node.serviceName ?? '',
      };
    } else if (node.network == NetworkType.httpUpgrade) {
      map['transport'] = {
        'type': 'httpupgrade',
        'path': node.path ?? '/',
        if (node.host != null && node.host!.isNotEmpty) 'host': node.host,
      };
    }

    return map;
  }

  /// Generates a complete, runnable Sing-box JSON configuration from a ProxyNode
  static String generateSingBoxConfig(
    ProxyNode node, {
    int inHttpPort = 10809,
    int inSocksPort = 10808,
    bool allowLan = false,
  }) {
    final bindAddr = allowLan ? '0.0.0.0' : '127.0.0.1';
    final proxyOutbound = toSingBoxOutbound(node);
    final config = {
      'log': {
        'level': 'info',
        'timestamp': true,
      },
      'inbounds': [
        {
          'type': 'mixed',
          'tag': 'mixed-in',
          'listen': bindAddr,
          'listen_port': inHttpPort,
          'sniff': true,
        },
        {
          'type': 'socks',
          'tag': 'socks-in',
          'listen': bindAddr,
          'listen_port': inSocksPort,
          'sniff': true,
        },
      ],
      'outbounds': [
        proxyOutbound,
        {
          'type': 'direct',
          'tag': 'direct',
        },
        {
          'type': 'block',
          'tag': 'block',
        },
      ],
      'route': {
        'rules': [
          {
            'protocol': 'dns',
            'outbound': 'direct',
          },
          {
            'ip_is_private': true,
            'outbound': 'direct',
          },
        ],
        'auto_detect_interface': true,
      },
    };
    return const JsonEncoder.withIndent('  ').convert(config);
  }
}
