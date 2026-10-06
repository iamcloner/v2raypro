import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/l10n/translations.dart';
import 'core/theme/app_theme.dart';
import 'models/proxy_node.dart';
import 'providers/app_providers.dart';
import 'services/cloudflare_scanner_service.dart';
import 'services/xray_process_service.dart';
import 'utils/config_parser.dart';

class ConfigsView extends ConsumerStatefulWidget {
  const ConfigsView({super.key});

  @override
  ConsumerState<ConfigsView> createState() => _ConfigsViewState();
}

class _ConfigsViewState extends ConsumerState<ConfigsView> {
  final _importController = TextEditingController();
  final Set<String> _testingNodeIds = {};
  bool _isTestingAll = false;

  void _showImportDialog(String locale) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppStrings.get('add_config', locale: locale)),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _importController,
                maxLines: 5,
                decoration: const InputDecoration(
                  hintText: 'Paste vless://, vmess://, trojan://, ss://, or multi-line configurations...',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(ctx),
          ),
          FilledButton(
            child: const Text('Import'),
            onPressed: () {
              final text = _importController.text.trim();
              if (text.isNotEmpty) {
                final nodes = ConfigParser.parseBatch(text);
                if (nodes.isNotEmpty) {
                  ref.read(nodesProvider.notifier).addNodes(nodes);
                  _importController.clear();
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('${nodes.length} configuration(s) added successfully')),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('No valid proxy configurations found.')),
                  );
                }
              }
            },
          ),
        ],
      ),
    );
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

  Future<void> _testAllNodes() async {
    final nodes = ref.read(nodesProvider);
    if (nodes.isEmpty || _isTestingAll) return;

    setState(() {
      _isTestingAll = true;
    });

    for (final node in nodes) {
      if (!mounted) break;
      await _testNodeLatency(node);
    }

    if (mounted) {
      setState(() {
        _isTestingAll = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final allNodes = ref.watch(nodesProvider);
    final nodes = allNodes.where((n) => n.subscriptionId == null).toList();
    final locale = ref.watch(currentLocaleProvider);

    return Scaffold(
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
                        icon: _isTestingAll
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.speed_rounded, size: 18),
                        label: Text(_isTestingAll ? 'Testing...' : 'Test All Ping'),
                        onPressed: _isTestingAll ? null : _testAllNodes,
                      ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: AppTheme.primaryAccent),
                      icon: const Icon(Icons.add),
                      label: Text(AppStrings.get('add_config', locale: locale)),
                      onPressed: () => _showImportDialog(locale),
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
                    final cfRanges = ref.watch(cfRangesProvider);
                    final isCf = CloudflareScannerService.isCloudflareIp(node.address, cfRanges);

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
                          '${node.address}:${node.port}  •  ${node.protocol.name.toUpperCase()}  •  ${node.network.name.toUpperCase()}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isTesting)
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 12),
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
                              icon: const Icon(Icons.bolt_rounded, size: 20, color: Colors.cyanAccent),
                              tooltip: 'Ping test',
                              onPressed: () => _testNodeLatency(node),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline_rounded, color: Colors.grey),
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
    );
  }
}
