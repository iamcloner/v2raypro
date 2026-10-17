class IpMaskUtil {
  static String mask(String input, {bool showFull = false}) {
    if (showFull || input.trim().isEmpty) return input;
    final trimmed = input.trim();

    // Check if standard IPv4 (e.g. 104.28.12.34 or 104.28.12.34:443)
    final partsWithPort = trimmed.split(':');
    final isIpv6 = trimmed.contains('::') || (trimmed.contains(':') && partsWithPort.length > 2);
    final ipPart = isIpv6 ? trimmed : partsWithPort[0];
    final portPart = (!isIpv6 && partsWithPort.length == 2) ? ':${partsWithPort[1]}' : '';

    final ipv4Parts = ipPart.split('.');
    if (ipv4Parts.length == 4) {
      return "${ipv4Parts[0]}.${ipv4Parts[1]}.***.***$portPart";
    }

    // IPv6
    if (isIpv6) {
      final segments = trimmed.split(':').where((s) => s.isNotEmpty).toList();
      if (segments.length >= 2) {
        return "${segments[0]}:${segments[1]}:***:***";
      }
      return "$trimmed (masked)";
    }

    // Domain name (e.g. sub.example.com)
    if (trimmed.contains('.')) {
      final dotIdx = trimmed.indexOf('.');
      if (dotIdx > 2) {
        final prefix = trimmed.substring(0, (dotIdx / 2).ceil());
        final suffix = trimmed.substring(dotIdx);
        return "$prefix***$suffix$portPart";
      }
    }

    if (trimmed.length > 6) {
      return "${trimmed.substring(0, 3)}***${trimmed.substring(trimmed.length - 2)}";
    }

    return trimmed;
  }
}
