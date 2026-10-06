import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'core/l10n/translations.dart';
import 'core/theme/app_theme.dart';
import 'models/proxy_node.dart';
import 'providers/app_providers.dart';
import 'services/cloudflare_scanner_service.dart';
import 'services/xray_process_service.dart';
import 'utils/config_parser.dart';
import 'utils/ip_mask_util.dart';
import 'widgets/add_config_dialog.dart';
import 'widgets/edit_config_dialog.dart';

class ConfigsView extends ConsumerStatefulWidget {
  const ConfigsView({super.key});

  @override
  ConsumerState<ConfigsView> createState() => _ConfigsViewState();
}

class _ConfigsViewState extends ConsumerState<ConfigsView> {
  final Set<String> _testingNodeIds = {};
  bool _isTestingAll = false;
  bool _cancelTestingAll = false;
  int _totalToTest = 0;
  int _testedCount = 0;

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) return;

    // 1. Try URL parsing (vless, vmess, trojan, ss)
    final nodes = ConfigParser.parseBatch(text);
    if (nodes.isNotEmpty) {
      ref.read(nodesProvider.notifier).addNodes(nodes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${nodes.length} configuration(s) imported from clipboard.')),
        );
      }
      return;
    }

    // 2. Try JSON parsing
    try {
      final decoded = jsonDecode(text);
      final List<ProxyNode> jsonNodes = [];
      if (decoded is List) {
        for (final item in decoded) {
          if (item is Map<String, dynamic>) {
            jsonNodes.add(ProxyNode.fromJson(item));
          }
        }
      } else if (decoded is Map<String, dynamic>) {
        if (decoded.containsKey('address') || decoded.containsKey('server')) {
          jsonNodes.add(ProxyNode.fromJson(decoded));
        } else if (decoded.containsKey('outbounds')) {
          final outbounds = decoded['outbounds'] as List?;
          if (outbounds != null) {
            for (final out in outbounds) {
              if (out is Map<String, dynamic>) {
                final protoStr = (out['protocol'] ?? '').toString().toLowerCase();
                final proto = ProtocolType.values.firstWhere(
                  (p) => p.name.toLowerCase() == protoStr,
                  orElse: () => ProtocolType.vless,
                );
                final tag = out['tag'] ?? 'JSON Config';
                final settings = out['settings'] as Map<String, dynamic>? ?? {};
                final vnext = settings['vnext'] as List?;
                if (vnext != null && vnext.isNotEmpty) {
                  final first = vnext[0] as Map<String, dynamic>;
                  final addr = first['address'] ?? '127.0.0.1';
                  final port = (first['port'] as num?)?.toInt() ?? 443;
                  final users = first['users'] as List?;
                  final uuid = (users != null && users.isNotEmpty) ? (users[0]['id'] ?? '') : '';
                  jsonNodes.add(ProxyNode(
                    id: const Uuid().v4(),
                    name: tag,
                    protocol: proto,
                    address: addr,
                    port: port,
                    uuidOrPassword: uuid,
                  ));
                }
              }
            }
          }
        } else {
          jsonNodes.add(ProxyNode.fromJson(decoded));
        }
      }

      if (jsonNodes.isNotEmpty) {
        ref.read(nodesProvider.notifier).addNodes(jsonNodes);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${jsonNodes.length} configuration(s) imported from clipboard JSON.')),
          );
        }
        return;
      }
    } catch (_) {}

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No valid proxy configuration found in clipboard.')),
      );
    }
  }

  Future<void> _testNodeLatency(ProxyNode node) async {
    if (_testingNodeIds.contains(node.id)) return;
    setState(() {
      _testingNodeIds.add(node.id);
    });

    final latency = await XrayProcessService.instance.testNodeLatency(node);
    ref.read(nodesProvider.notifier).updateLatency(node.id, latency);

    if (mounted) {
      setState(() {
        _testingNodeIds.remove(node.id);
      });
    }
  }

  Future<void> _testAllNodes(List<ProxyNode> nodes) async {
    if (nodes.isEmpty) return;
    if (_isTestingAll) {
      setState(() {
        _cancelTestingAll = true;
      });
      return;
    }

    setState(() {
      _isTestingAll = true;
      _cancelTestingAll = false;
      _totalToTest = nodes.length;
      _testedCount = 0;
    });

    for (int i = 0; i < nodes.length; i += 10) {
      if (_cancelTestingAll || !mounted) break;
      final chunk = nodes.sublist(i, math.min(i + 10, nodes.length));
      setState(() {
        _testingNodeIds.addAll(chunk.map((n) => n.id));
      });

      await Future.wait(chunk.map((n) async {
        if (_cancelTestingAll) return;
        final lat = await XrayProcessService.instance.testNodeLatency(n);
        if (mounted) {
          ref.read(nodesProvider.notifier).updateLatency(n.id, lat);
        }
      }));

      if (mounted) {
        setState(() {
          _testingNodeIds.removeAll(chunk.map((n) => n.id));
          _testedCount += chunk.length;
        });
      }
    }

    if (mounted) {
      setState(() {
        _isTestingAll = false;
        _cancelTestingAll = false;
        _testingNodeIds.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final allNodes = ref.watch(nodesProvider);
    final nodes = allNodes.where((n) => n.subscriptionId == null).toList();
    // Sort by latest ping latency ascending (lowest ping first, null/untested last)
    nodes.sort((a, b) {
      if (a.latencyMs != null && b.latencyMs != null) {
        return a.latencyMs!.compareTo(b.latencyMs!);
      }
      if (a.latencyMs != null && b.latencyMs == null) return -1;
      if (a.latencyMs == null && b.latencyMs != null) return 1;
      return a.name.compareTo(b.name);
    });
    final locale = ref.watch(currentLocaleProvider);
    final showFullIp = ref.watch(showFullIpProvider);

    final progress = _totalToTest > 0 ? (_testedCount / _totalToTest).clamp(0.0, 1.0) : 0.0;
    final progressPercent = (progress * 100).toInt();

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyV, control: true): _pasteFromClipboard,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      AppStrings.get('configs', locale: locale),
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    Row(
                      children: [
                        if (nodes.isNotEmpty)
                          OutlinedButton.icon(
                            style: _isTestingAll
                                ? OutlinedButton.styleFrom(
                                    side: const BorderSide(color: Colors.amber, width: 1.5),
                                  )
                                : null,
                            icon: _isTestingAll
                                ? SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      value: progress > 0 ? progress : null,
                                      strokeWidth: 2,
                                      color: Colors.amber,
                                    ),
                                  )
                                : const Icon(Icons.speed_rounded, size: 18),
                            label: Text(
                              _isTestingAll
                                  ? '$progressPercent% (${AppStrings.get("cancel_scan", locale: locale)})'
                                  : AppStrings.get('test_all', locale: locale),
                              style: TextStyle(
                                color: _isTestingAll ? Colors.amber : null,
                                fontWeight: _isTestingAll ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                            onPressed: () => _testAllNodes(nodes),
                          ),
                        const SizedBox(width: 12),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(backgroundColor: AppTheme.primaryAccent),
                          icon: const Icon(Icons.add),
                          label: Text(AppStrings.get('add_config', locale: locale)),
                          onPressed: () => AddConfigDialog.show(context, locale),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                if (nodes.isEmpty)
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.cloud_off_rounded, size: 64, color: Colors.grey.shade700),
                          const SizedBox(height: 16),
                          Text(
                            AppStrings.get('no_nodes', locale: locale),
                            style: const TextStyle(color: Colors.grey, fontSize: 15),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            '(Tip: Press Ctrl+V anytime to paste configs from clipboard)',
                            style: TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: ListView.separated(
                      itemCount: nodes.length,
                      separatorBuilder: (c, i) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final node = nodes[index];
                        final isTesting = _testingNodeIds.contains(node.id);
                        final cfHosts = ref.watch(cfCheckedHostsProvider);
                        final isCf = cfHosts[node.address.trim().toLowerCase()] ?? ref.read(cfCheckedHostsProvider.notifier).isCloudflare(node.address);

                        return Card(
                          child: ListTile(
                            leading: Icon(
                              node.isActive ? Icons.radio_button_checked : Icons.radio_button_off,
                              color: node.isActive ? AppTheme.primaryAccent : Colors.grey,
                            ),
                            title: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    node.name,
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (isCf) ...[
                                  const SizedBox(width: 6),
                                  Tooltip(
                                    message: "Cloudflare IP (★)",
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.amber.withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: Colors.amber, width: 0.8),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.star_rounded, size: 14, color: Colors.amber),
                                          SizedBox(width: 2),
                                          Text(
                                            "CF",
                                            style: TextStyle(
                                              color: Colors.amber,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            subtitle: Text(
                              '${IpMaskUtil.mask(node.address, showFull: showFullIp)}:${node.port}  •  ${node.protocol.name.toUpperCase()}  •  ${node.network.name.toUpperCase()}',
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isTesting)
                                  const Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 10),
                                    child: SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    ),
                                  )
                                else if (node.latencyMs != null)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: AppTheme.successColor.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '${node.latencyMs} ms',
                                      style: const TextStyle(
                                        color: AppTheme.successColor,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(Icons.bolt_rounded, size: 20, color: Colors.cyanAccent),
                                  tooltip: 'Ping test',
                                  onPressed: () => _testNodeLatency(node),
                                ),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(Icons.edit, size: 20, color: Colors.amberAccent),
                                  tooltip: AppStrings.get('edit_config', locale: locale),
                                  onPressed: () => EditConfigDialog.show(context, node, locale),
                                ),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(Icons.share, size: 20, color: Colors.purpleAccent),
                                  tooltip: AppStrings.get('share_config', locale: locale),
                                  onPressed: () {
                                    Clipboard.setData(ClipboardData(text: node.toShareUrl()));
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(AppStrings.get('share_copied', locale: locale))),
                                    );
                                  },
                                ),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  icon: Icon(Icons.delete_outline_rounded, size: 20, color: Colors.redAccent.shade100),
                                  onPressed: () {
                                    ref.read(nodesProvider.notifier).removeNode(node.id);
                                  },
                                ),
                              ],
                            ),
                            onTap: () {
                              ref.read(nodesProvider.notifier).setActive(node.id);
                            },
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}