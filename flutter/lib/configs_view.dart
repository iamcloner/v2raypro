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
import 'widgets/country_flag_badge.dart';

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
    final nodes = await ConfigParser.parseBatchAsync(text);
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

      final chunkResults = <String, int?>{};

      // 1. Try batch real proxy test via Xray for the chunk first
      Map<String, int> batchProxyResults = {};
      if (XrayProcessService.instance.isCoreAvailable()) {
        try {
          batchProxyResults = await XrayProcessService.instance.testNodesBatchRealProxy(
            chunk,
            timeout: const Duration(seconds: 4),
          );
        } catch (_) {}
      }

      for (final n in chunk) {
        if (batchProxyResults.containsKey(n.id) && batchProxyResults[n.id]! > 0) {
          chunkResults[n.id] = batchProxyResults[n.id];
        }
      }

      // 2. For any remaining nodes, test via direct protocol fallback
      final remaining = chunk.where((n) => !chunkResults.containsKey(n.id)).toList();
      if (remaining.isNotEmpty) {
        await Future.wait(remaining.map((n) async {
          if (_cancelTestingAll) return;
          final lat = await XrayProcessService.instance.testNodeLatency(n);
          chunkResults[n.id] = lat;
        }));
      }

      if (mounted && chunkResults.isNotEmpty) {
        ref.read(nodesProvider.notifier).updateLatenciesBatch(chunkResults);
      }

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

  Future<void> _deleteDeadNodes(List<ProxyNode> customNodes, String locale) async {
    final deadNodes = customNodes.where((n) => n.hasTimedOut).toList();
    if (deadNodes.isEmpty) {
      final untestedCount = customNodes.where((n) => n.isUntested).length;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            untestedCount > 0
                ? (locale == 'fa'
                    ? 'ابتدا با دکمه «تست پینگ همه» کانفیگ‌ها را بررسی کنید تا بی‌پاسخ‌ها مشخص شوند.'
                    : 'Run "Test All Ping" first to check and mark timed-out configs.')
                : AppStrings.get('delete_dead_none', locale: locale),
          ),
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.delete_sweep_rounded, color: Colors.redAccent),
            const SizedBox(width: 8),
            Text(AppStrings.get('confirm_delete_dead_title', locale: locale)),
          ],
        ),
        content: Text(
          AppStrings.get('confirm_delete_dead_msg', locale: locale)
              .replaceAll('{count}', deadNodes.length.toString()),
        ),
        actions: [
          TextButton(
            child: Text(AppStrings.get('cancel_scan', locale: locale)),
            onPressed: () => Navigator.pop(ctx, false),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: Text(AppStrings.get('delete_dead_configs', locale: locale)),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final removed = ref.read(nodesProvider.notifier).removeDeadNodes(onlyCustom: true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppStrings.get('delete_dead_success', locale: locale)
                .replaceAll('{count}', removed.toString()),
          ),
          backgroundColor: Colors.redAccent.shade700,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final allNodes = ref.watch(nodesProvider);
    final nodes = allNodes.where((n) => n.subscriptionId == null).toList();
    // Sort by status: working nodes first (lowest ping to highest), then untested, then timed-out last
    nodes.sort((a, b) {
      if (a.hasValidPing && b.hasValidPing) {
        return a.latencyMs!.compareTo(b.latencyMs!);
      }
      if (a.hasValidPing && !b.hasValidPing) return -1;
      if (!a.hasValidPing && b.hasValidPing) return 1;
      if (a.isUntested && b.hasTimedOut) return -1;
      if (a.hasTimedOut && b.isUntested) return 1;
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
                        if (nodes.isNotEmpty) ...[
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
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.redAccent,
                              side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.6), width: 1.2),
                            ),
                            icon: const Icon(Icons.delete_sweep_rounded, size: 18),
                            label: Text(AppStrings.get('delete_dead_configs', locale: locale)),
                            onPressed: () => _deleteDeadNodes(nodes, locale),
                          ),
                          const SizedBox(width: 12),
                        ],
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
                        final cdnMap = ref.watch(nodeCdnMapProvider);
                        final cdn = cdnMap[node.address.trim().toLowerCase()] ?? ref.read(nodeCdnMapProvider.notifier).detectCdn(node.address);

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
                                if (cdn != null) ...[
                                  const SizedBox(width: 6),
                                  CdnBadge(cdn: cdn),
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
                                else if (node.hasValidPing)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: AppTheme.successColor.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: AppTheme.successColor.withValues(alpha: 0.3), width: 0.8),
                                    ),
                                    child: Text(
                                      '${node.latencyMs} ms',
                                      style: const TextStyle(
                                        color: AppTheme.successColor,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  )
                                else if (node.hasTimedOut)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: AppTheme.errorColor.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: AppTheme.errorColor.withValues(alpha: 0.4), width: 0.8),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.cloud_off_rounded, size: 12, color: AppTheme.errorColor),
                                        const SizedBox(width: 4),
                                        Text(
                                          AppStrings.get('timeout', locale: locale),
                                          style: const TextStyle(
                                            color: AppTheme.errorColor,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
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