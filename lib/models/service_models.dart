import "dart:convert";
import "proxy_node.dart";
import "../utils/config_generator.dart";

/// Operating mode of the core service
enum CoreMode {
  tun,
  proxy,
}

/// Status / action commanded to the core service
enum CoreStatus {
  connect,
  change,
  disconnect,
}

/// Underlying core engine type
enum CoreType {
  xray,
  singbox,
}

/// Lifecycle status of the core service
enum CoreState {
  disconnected,
  connecting,
  connected,
  disconnecting,
  error,
}

/// Unified configuration wrapper passed to CoreService and PingService
class CoreConfig {
  /// The raw JSON configuration structure (Xray or Sing-box)
  final Map<String, dynamic> rawJson;

  /// The core type expected by this configuration
  final CoreType type;

  /// Optional original proxy node from which this config was derived
  final ProxyNode? node;

  const CoreConfig({
    required this.rawJson,
    this.type = CoreType.xray,
    this.node,
  });

  /// Factory from raw Xray JSON Map
  factory CoreConfig.fromXrayJson(Map<String, dynamic> json, {ProxyNode? node}) {
    return CoreConfig(
      rawJson: json,
      type: CoreType.xray,
      node: node,
    );
  }

  /// Factory from ProxyNode using ConfigGenerator
  factory CoreConfig.fromNode(
    ProxyNode node, {
    CoreType type = CoreType.xray,
    int socksPort = 10808,
    int httpPort = 10809,
    bool enableTun = false,
    bool enableUdp = true,
    bool enableMux = false,
    bool allowInsecure = false,
    bool allowLan = false,
  }) {
    final raw = (type == CoreType.singbox)
        ? ConfigGenerator.generateSingboxConfig(node, socksPort: socksPort, httpPort: httpPort, enableTun: enableTun)
        : ConfigGenerator.generateXrayConfig(
            node,
            socksPort: socksPort,
            httpPort: httpPort,
            enableTun: enableTun,
            enableUdp: enableUdp,
            enableMux: enableMux,
            allowInsecure: allowInsecure,
            allowLan: allowLan,
          );
    return CoreConfig(rawJson: raw, type: type, node: node);
  }

  /// Factory from raw Sing-box JSON Map
  factory CoreConfig.fromSingboxJson(Map<String, dynamic> json, {ProxyNode? node}) {
    return CoreConfig(
      rawJson: json,
      type: CoreType.singbox,
      node: node,
    );
  }

  /// Factory from JSON string
  factory CoreConfig.fromJsonString(String jsonStr, {CoreType type = CoreType.xray, ProxyNode? node}) {
    final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
    return CoreConfig(
      rawJson: decoded,
      type: type,
      node: node,
    );
  }

  /// Extracts the server address and port from the underlying configuration
  ({String address, int port}) extractServerAddressAndPort() {
    if (node != null && node!.address.isNotEmpty && node!.port > 0) {
      return (address: node!.address, port: node!.port);
    }

    if (type == CoreType.xray) {
      final outbounds = rawJson['outbounds'] as List?;
      if (outbounds != null && outbounds.isNotEmpty) {
        for (final ob in outbounds) {
          if (ob is Map<String, dynamic>) {
            final tag = ob['tag'] as String? ?? '';
            if (tag == 'proxy' || tag.startsWith('proxy') || tag == 'out_0') {
              final settings = ob['settings'] as Map<String, dynamic>?;
              if (settings != null) {
                final vnext = settings['vnext'] as List?;
                if (vnext != null && vnext.isNotEmpty) {
                  final first = vnext[0] as Map<String, dynamic>;
                  final addr = first['address'] as String? ?? '';
                  final p = first['port'] as int? ?? 0;
                  if (addr.isNotEmpty && p > 0) return (address: addr, port: p);
                }
                final servers = settings['servers'] as List?;
                if (servers != null && servers.isNotEmpty) {
                  final first = servers[0] as Map<String, dynamic>;
                  final addr = first['address'] as String? ?? '';
                  final p = first['port'] as int? ?? 0;
                  if (addr.isNotEmpty && p > 0) return (address: addr, port: p);
                }
              }
            }
          }
        }
      }
    } else if (type == CoreType.singbox) {
      final outbounds = rawJson['outbounds'] as List?;
      if (outbounds != null) {
        for (final ob in outbounds) {
          if (ob is Map<String, dynamic>) {
            final addr = ob['server'] as String? ?? '';
            final p = ob['server_port'] as int? ?? 0;
            if (addr.isNotEmpty && p > 0) return (address: addr, port: p);
          }
        }
      }
    }

    return (address: '', port: 0);
  }

  String toJsonString({bool pretty = false}) {
    return pretty ? const JsonEncoder.withIndent('  ').convert(rawJson) : jsonEncode(rawJson);
  }
}

/// Commands for TunService
enum TunStatus {
  connect,
  disconnect,
}

/// Types of ping protocols supported
enum PingType {
  icmp,
  tcp,
  udp,
}

/// Modes of ping testing
enum PingMode {
  realDelay,
  ipTest,
}

/// Result returned from PingService operations
class PingResult {
  final int? latencyMs;
  final bool isSuccess;
  final String? countryCode;
  final String? countryName;
  final String? exitIp;
  final String? errorMessage;

  const PingResult({
    this.latencyMs,
    required this.isSuccess,
    this.countryCode,
    this.countryName,
    this.exitIp,
    this.errorMessage,
  });

  factory PingResult.success({
    required int latencyMs,
    String? countryCode,
    String? countryName,
    String? exitIp,
  }) {
    return PingResult(
      latencyMs: latencyMs,
      isSuccess: true,
      countryCode: countryCode,
      countryName: countryName,
      exitIp: exitIp,
    );
  }

  factory PingResult.failure(String errorMessage) {
    return PingResult(
      latencyMs: null,
      isSuccess: false,
      errorMessage: errorMessage,
    );
  }
}
