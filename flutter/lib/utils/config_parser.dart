import 'dart:convert';
import 'package:uuid/uuid.dart';
import '../models/proxy_node.dart';

class ConfigParser {
  /// Parse a single config link or batch of links (newline-separated or base64 subscription)
  static List<ProxyNode> parseBatch(String content) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return [];

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
        allowInsecure: params['allowInsecure'] == '1' || params['allowInsecure'] == 'true',
        fingerprint: params['fp'] ?? params['fingerprint'],
        publicKey: params['pbk'],
        shortId: params['sid'],
        spiderX: params['spx'],
        mode: params['mode'],
        extra: params['extra'],
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
        fingerprint: map['fp']?.toString(),
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
        allowInsecure: params['allowInsecure'] == '1' || params['allowInsecure'] == 'true',
        fingerprint: params['fp'] ?? params['fingerprint'],
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
}
