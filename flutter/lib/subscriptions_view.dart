import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/l10n/translations.dart';
import 'core/theme/app_theme.dart';
import 'models/proxy_node.dart';
import 'models/subscription_item.dart';
import 'providers/app_providers.dart';
import 'services/cloudflare_scanner_service.dart';
import 'services/xray_process_service.dart';
import 'widgets/edit_config_dialog.dart';

class SubscriptionsView extends ConsumerStatefulWidget {
  const SubscriptionsView({super.key});

  @override
  ConsumerState<SubscriptionsView> createState() => _SubscriptionsViewState();
}

class _SubscriptionsViewState extends ConsumerState<SubscriptionsView> {
  final _nameController = TextEditingController();
  final _urlController = TextEditingController();
  final Set<String> _updatingSubIds = {};
  final Set<String> _testingNodeIds = {};
  final Set<String> _expandedSubConfigs = {};
  final Map<String, bool> _testingSubMap = {};
  final Map<String, bool> _cancelSubMap = {};
  final Map<String, int> _subTestedCount = {};
  final Map<String, int> _subTotalCount = {};
  bool _isUpdatingAll = false;

  void _showAddDialog(String locale) {
    _nameController.clear();
    _urlController.clear();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppStrings.get("add_subscription", locale: locale)),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: AppStrings.get("sub_name", locale: locale),
                  hintText: "e.g. My Premium Configs",
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _urlController,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: AppStrings.get("sub_url", locale: locale),
                  hintText: "https://example.com/api/v1/client/subscribe?token=...",
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            child: const Text("Cancel"),
            onPressed: () => Navigator.pop(ctx),
          ),
          FilledButton(
            child: const Text("Add & Update"),
            onPressed: () async {
              final url = _urlController.text.trim();
              if (url.isNotEmpty) {
                Navigator.pop(ctx);
                final messenger = ScaffoldMessenger.of(context);
                messenger.showSnackBar(
                  const SnackBar(content: Text("Fetching subscription nodes...")),
                );
                final count = await ref
                    .read(subscriptionsProvider.notifier)
                    .addSubscription(_nameController.text.trim(), url);
                messenger.showSnackBar(
                  SnackBar(content: Text("$count nodes imported from subscription.")),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Future<void> _updateSub(SubscriptionItem sub) async {
    if (_updatingSubIds.contains(sub.id)) return;
    setState(() => _updatingSubIds.add(sub.id));

    final count = await ref.read(subscriptionsProvider.notifier).updateSubscription(sub.id);

    if (mounted) {
      setState(() => _updatingSubIds.remove(sub.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("${sub.name}: $count nodes updated")),
      );
    }
  }

  Future<void> _updateAllSubs() async {
    final subs = ref.read(subscriptionsProvider);
    if (subs.isEmpty || _isUpdatingAll) return;

    setState(() => _isUpdatingAll = true);
    await ref.read(subscriptionsProvider.notifier).updateAll();

    if (mounted) {
      setState(() => _isUpdatingAll = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("All subscriptions updated successfully")),
      );
    }
  }

  Future<void> _testNodeLatency(ProxyNode node) async {
    if (_testingNodeIds.contains(node.id)) return;
    setState(() => _testingNodeIds.add(node.id));

    final latency = await XrayProcessService.instance.testNodeLatency(node);
    ref.read(nodesProvider.notifier).updateLatency(node.id, latency);

    if (mounted) {
      setState(() => _testingNodeIds.remove(node.id));
    }
  }

  Future<void> _testAllSubNodes(SubscriptionItem sub, List<ProxyNode> subNodes) async {
    final subId = sub.id;
    if (subNodes.isEmpty) return;
    if (_testingSubMap[subId] == true) {
      // Cancel requested
      setState(() {
        _cancelSubMap[subId] = true;
      });
      return;
    }

    setState(() {
      _testingSubMap[subId] = true;
      _cancelSubMap[subId] = false;
      _subTotalCount[subId] = subNodes.length;
      _subTestedCount[subId] = 0;
    });

    for (int i = 0; i < subNodes.length; i += 10) {
      if (_cancelSubMap[subId] == true || !mounted) break;
      final chunk = subNodes.sublist(i, math.min(i + 10, subNodes.length));
      setState(() {
        _testingNodeIds.addAll(chunk.map((n) => n.id));
      });

      await Future.wait(chunk.map((n) async {
        if (_cancelSubMap[subId] == true) return;
        final lat = await XrayProcessService.instance.testNodeLatency(n);
        if (mounted) {
          ref.read(nodesProvider.notifier).updateLatency(n.id, lat);
        }
      }));

      if (mounted) {
        setState(() {
          _testingNodeIds.removeAll(chunk.map((n) => n.id));
          _subTestedCount[subId] = (_subTestedCount[subId] ?? 0) + chunk.length;
        });
      }
    }

    if (mounted) {
      setState(() {
        _testingSubMap[subId] = false;
        _cancelSubMap[subId] = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final subs = ref.watch(subscriptionsProvider);
    final allNodes = ref.watch(nodesProvider);
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
                  AppStrings.get("subscriptions", locale: locale),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                Row(
                  children: [
                    if (subs.isNotEmpty)
                      OutlinedButton.icon(
                        icon: _isUpdatingAll
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.sync_rounded, size: 18),
                        label: Text(_isUpdatingAll
                            ? "Updating..."
                            : AppStrings.get("update_all_subs", locale: locale)),
                        onPressed: _isUpdatingAll ? null : _updateAllSubs,
                      ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: AppTheme.primaryAccent),
                      icon: const Icon(Icons.add),
                      label: Text(AppStrings.get("add_subscription", locale: locale)),
                      onPressed: () => _showAddDialog(locale),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (subs.isEmpty)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.rss_feed_rounded, size: 64, color: Colors.grey.shade700),
                      const SizedBox(height: 16),
                      Text(
                        AppStrings.get("no_subs", locale: locale),
                        style: const TextStyle(color: Colors.grey, fontSize: 15),
                      ),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  itemCount: subs.length,
                  separatorBuilder: (c, i) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final sub = subs[index];
                    final isUpdating = _updatingSubIds.contains(sub.id);
                    final subNodes = allNodes.where((n) => n.subscriptionId == sub.id).toList();

                    // Sort subNodes by ping latency ascending (lowest ping first, untested/null last)
                    subNodes.sort((a, b) {
                      if (a.latencyMs != null && b.latencyMs != null) {
                        return a.latencyMs!.compareTo(b.latencyMs!);
                      }
                      if (a.latencyMs != null && b.latencyMs == null) return -1;
                      if (a.latencyMs == null && b.latencyMs != null) return 1;
                      return a.name.compareTo(b.name);
                    });

                    final isExpandedAll = _expandedSubConfigs.contains(sub.id);
                    final displayedNodes = isExpandedAll ? subNodes : subNodes.take(3).toList();

                    final isTestingSub = _testingSubMap[sub.id] == true;
                    final totalSub = _subTotalCount[sub.id] ?? 0;
                    final testedSub = _subTestedCount[sub.id] ?? 0;
                    final subProgress = totalSub > 0 ? (testedSub / totalSub).clamp(0.0, 1.0) : 0.0;
                    final subPercent = (subProgress * 100).toInt();

                    return Card(
                      clipBehavior: Clip.antiAlias,
                      child: ExpansionTile(
                        initiallyExpanded: false,
                        leading: CircleAvatar(
                          backgroundColor: AppTheme.primaryAccent.withValues(alpha: 0.15),
                          child: const Icon(Icons.rss_feed_rounded, color: AppTheme.primaryAccent),
                        ),
                        title: Text(sub.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(
                          "${sub.nodeCount} nodes  •  ${sub.lastUpdated != null ? 'Updated: ' + sub.lastUpdated!.toLocal().toString().substring(0, 16) : 'Never updated'}",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (subNodes.isNotEmpty) ...[
                              OutlinedButton.icon(
                                style: isTestingSub
                                    ? OutlinedButton.styleFrom(
                                        side: const BorderSide(color: Colors.amber, width: 1.2),
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      )
                                    : OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      ),
                                icon: isTestingSub
                                    ? SizedBox(
                                        width: 12,
                                        height: 12,
                                        child: CircularProgressIndicator(
                                          value: subProgress > 0 ? subProgress : null,
                                          strokeWidth: 2,
                                          color: Colors.amber,
                                        ),
                                      )
                                    : const Icon(Icons.speed_rounded, size: 16),
                                label: Text(
                                  isTestingSub
                                      ? '$subPercent% (${AppStrings.get("cancel_scan", locale: locale)})'
                                      : AppStrings.get("test_all_sub", locale: locale),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isTestingSub ? Colors.amber : null,
                                    fontWeight: isTestingSub ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                                onPressed: () => _testAllSubNodes(sub, subNodes),
                              ),
                              const SizedBox(width: 6),
                            ],
                            if (isUpdating)
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 12),
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              )
                            else
                              IconButton(
                                icon: const Icon(Icons.sync_rounded, color: Colors.cyanAccent),
                                tooltip: "Update subscription",
                                onPressed: () => _updateSub(sub),
                              ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline_rounded, color: Colors.grey),
                              tooltip: "Delete",
                              onPressed: () {
                                ref.read(subscriptionsProvider.notifier).removeSubscription(sub.id);
                              },
                            ),
                          ],
                        ),
                        children: [
                          Container(
                            color: Theme.of(context).cardColor.withValues(alpha: 0.4),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      AppStrings.get("auto_update_hourly", locale: locale),
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                    ),
                                    Text(
                                      AppStrings.get("auto_update_hourly_desc", locale: locale),
                                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                                    ),
                                  ],
                                ),
                                Switch(
                                  value: sub.autoUpdate,
                                  activeColor: AppTheme.primaryAccent,
                                  onChanged: (val) {
                                    ref.read(subscriptionsProvider.notifier).toggleAutoUpdate(sub.id, val);
                                  },
                                ),
                              ],
                            ),
                          ),
                          const Divider(height: 1),
                          if (subNodes.isEmpty)
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                AppStrings.get("no_sub_nodes", locale: locale),
                                style: const TextStyle(color: Colors.grey, fontSize: 13),
                              ),
                            )
                          else ...[
                            ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: displayedNodes.length,
                              separatorBuilder: (c, i) => const Divider(height: 1, indent: 56),
                              itemBuilder: (context, nodeIdx) {
                                final node = displayedNodes[nodeIdx];
                                final isTesting = _testingNodeIds.contains(node.id);
                                final cfRanges = ref.watch(cfRangesProvider);
                                final isCf = CloudflareScannerService.isCloudflareIp(node.address, cfRanges);

                                return ListTile(
                                  dense: true,
                                  leading: Icon(
                                    node.isActive ? Icons.radio_button_checked : Icons.radio_button_off,
                                    color: node.isActive ? AppTheme.primaryAccent : Colors.grey,
                                    size: 20,
                                  ),
                                  title: Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          node.name,
                                          style: const TextStyle(fontSize: 14),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (isCf) ...[
                                        const SizedBox(width: 6),
                                        Tooltip(
                                          message: "Cloudflare IP (★)",
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: Colors.amber.withValues(alpha: 0.2),
                                              borderRadius: BorderRadius.circular(4),
                                              border: Border.all(color: Colors.amber, width: 0.8),
                                            ),
                                            child: const Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.star_rounded, size: 13, color: Colors.amber),
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
                                    "${node.address}:${node.port}  •  ${node.protocol.name.toUpperCase()}  •  ${node.network.name.toUpperCase()}",
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (isTesting)
                                        const Padding(
                                          padding: EdgeInsets.symmetric(horizontal: 8),
                                          child: SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(strokeWidth: 2),
                                          ),
                                        )
                                      else if (node.latencyMs != null)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: AppTheme.successColor.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            "${node.latencyMs} ms",
                                            style: const TextStyle(
                                              color: AppTheme.successColor,
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      IconButton(
                                        icon: const Icon(Icons.bolt_rounded, size: 18, color: Colors.cyanAccent),
                                        tooltip: "Ping test",
                                        onPressed: () => _testNodeLatency(node),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.edit_outlined, size: 18, color: Colors.white70),
                                        tooltip: AppStrings.get("edit_config", locale: locale),
                                        onPressed: () => EditConfigDialog.show(context, node, locale),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.share_outlined, size: 18, color: Colors.white70),
                                        tooltip: AppStrings.get("share_config", locale: locale),
                                        onPressed: () {
                                          Clipboard.setData(ClipboardData(text: node.toShareUrl()));
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text(AppStrings.get("share_copied", locale: locale))),
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                  onTap: () {
                                    ref.read(nodesProvider.notifier).setActive(node.id);
                                  },
                                );
                              },
                            ),
                            if (subNodes.length > 3)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
                                child: Center(
                                  child: TextButton.icon(
                                    icon: Icon(
                                      isExpandedAll ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                                      size: 18,
                                    ),
                                    label: Text(
                                      isExpandedAll
                                          ? AppStrings.get("show_less_configs", locale: locale)
                                          : "${AppStrings.get("show_all_configs", locale: locale)} (${subNodes.length})",
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        if (isExpandedAll) {
                                          _expandedSubConfigs.remove(sub.id);
                                        } else {
                                          _expandedSubConfigs.add(sub.id);
                                        }
                                      });
                                    },
                                  ),
                                ),
                              ),
                          ],
                        ],
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