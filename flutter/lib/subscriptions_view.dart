import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/l10n/translations.dart';
import 'core/theme/app_theme.dart';
import 'models/proxy_node.dart';
import 'models/subscription_item.dart';
import 'providers/app_providers.dart';
import 'services/xray_process_service.dart';
import 'utils/ip_mask_util.dart';
import 'widgets/edit_config_dialog.dart';
import 'widgets/country_flag_badge.dart';
import 'widgets/country_filter_bar.dart';
import 'services/country_service.dart';
import 'services/storage_service.dart';

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
  final Map<String, int> _expandedSubLimit = {};
  final Map<String, bool> _testingSubMap = {};
  final Map<String, bool> _cancelSubMap = {};
  final Map<String, int> _subTestedCount = {};
  final Map<String, int> _subTotalCount = {};
  final Map<String, String?> _subCountryFilterMap = {};
  final Map<String, String?> _subEtaMap = {};
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

  void _showEditSubDialog(SubscriptionItem sub, String locale) {
    final nameCtrl = TextEditingController(text: sub.name);
    final urlCtrl = TextEditingController(text: sub.url);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.edit, color: AppTheme.primaryAccent),
            const SizedBox(width: 8),
            Text("${AppStrings.get('edit_config', locale: locale)} (Sub)"),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(
                  labelText: AppStrings.get("sub_name", locale: locale),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: urlCtrl,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: AppStrings.get("sub_url", locale: locale),
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
            style: FilledButton.styleFrom(backgroundColor: AppTheme.primaryAccent),
            child: const Text("Save & Refresh"),
            onPressed: () {
              final newName = nameCtrl.text.trim();
              final newUrl = urlCtrl.text.trim();
              if (newUrl.isNotEmpty) {
                ref.read(subscriptionsProvider.notifier).editSubscription(sub.id, newName, newUrl);
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Subscription updated and refreshing...")),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Future<void> _pasteSubFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) return;

    if (text.startsWith("http://") || text.startsWith("https://")) {
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        const SnackBar(content: Text("Adding subscription from clipboard URL...")),
      );
      final count = await ref
          .read(subscriptionsProvider.notifier)
          .addSubscription("Sub ${ref.read(subscriptionsProvider).length + 1}", text);
      messenger.showSnackBar(
        SnackBar(content: Text("$count nodes imported from subscription.")),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Clipboard does not contain a valid subscription URL (http/https).")),
      );
    }
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

    final res = await XrayProcessService.instance.testNodeRealDelay(node);
    ref.read(nodesProvider.notifier).updateLatency(
      node.id,
      res.latencyMs,
      countryCode: res.countryCode,
      country: res.country,
    );

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
      _testingNodeIds.addAll(subNodes.map((n) => n.id));
      _subTotalCount[subId] = subNodes.length;
      _subTestedCount[subId] = 0;
    });

    int currentIndex = 0;
    const concurrency = 10;
    final testStartTime = DateTime.now();

    Future<void> runWorker() async {
      while (currentIndex < subNodes.length && _cancelSubMap[subId] != true && mounted) {
        final nodeIndex = currentIndex++;
        if (nodeIndex >= subNodes.length) break;
        final n = subNodes[nodeIndex];

        final res = await XrayProcessService.instance.testNodeRealDelay(n);
        if (_cancelSubMap[subId] == true || !mounted) break;

        if (mounted) {
          ref.read(nodesProvider.notifier).updateLatency(
            n.id,
            res.latencyMs,
            countryCode: res.countryCode,
            country: res.country,
          );
          final tested = (_subTestedCount[subId] ?? 0) + 1;
          String? eta;
          if (subNodes.length > 50 && tested > 0 && tested < subNodes.length) {
            final elapsed = DateTime.now().difference(testStartTime);
            final avgPerNode = elapsed.inMilliseconds / tested;
            final remainingMs = (avgPerNode * (subNodes.length - tested)).round();
            final remSeconds = (remainingMs / 1000).round();
            final minutes = remSeconds ~/ 60;
            final seconds = remSeconds % 60;
            eta = '~${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
          }
          setState(() {
            _testingNodeIds.remove(n.id);
            _subTestedCount[subId] = tested;
            _subEtaMap[subId] = eta;
          });
        }
      }
    }

    final workerCount = math.min(concurrency, subNodes.length);
    final workers = List.generate(workerCount, (_) => runWorker());
    await Future.wait(workers);

    if (mounted) {
      setState(() {
        _testingSubMap[subId] = false;
        _cancelSubMap[subId] = false;
        _subEtaMap[subId] = null;
      });
      // Immediately flush tested latencies and countries to storage
      final allNodes = ref.read(nodesProvider);
      StorageService.instance.saveNodes(allNodes, immediate: true);
    }
  }

  Future<void> _deleteDeadSubNodes(SubscriptionItem sub, List<ProxyNode> subNodes, String locale) async {
    final deadNodes = subNodes.where((n) => n.hasTimedOut).toList();
    if (deadNodes.isEmpty) {
      final untestedCount = subNodes.where((n) => n.isUntested).length;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            untestedCount > 0
                ? (locale == 'fa'
                    ? 'ابتدا با دکمه «تست پینگ همه» کانفیگ‌های این ساب را بررسی کنید تا بی‌پاسخ‌ها مشخص شوند.'
                    : 'Run "Test All Ping" first to check and mark timed-out configs in this subscription.')
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
            Expanded(child: Text("${sub.name}: ${AppStrings.get('confirm_delete_dead_title', locale: locale)}")),
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
      final removed = ref.read(nodesProvider.notifier).removeDeadNodes(subscriptionId: sub.id);
      final remaining = subNodes.length - removed;
      ref.read(subscriptionsProvider.notifier).updateNodeCount(sub.id, remaining >= 0 ? remaining : 0);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "${sub.name}: ${AppStrings.get('delete_dead_success', locale: locale).replaceAll('{count}', removed.toString())}",
          ),
          backgroundColor: Colors.redAccent.shade700,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final subs = ref.watch(subscriptionsProvider);
    final allNodes = ref.watch(nodesProvider);
    final locale = ref.watch(currentLocaleProvider);
    final showFullIp = ref.watch(showFullIpProvider);
    final outbound = ref.watch(outboundInfoProvider);
    final connState = ref.watch(connectionStatusProvider);
    final isConnected = connState == ConnectionStateEnum.connected;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyV, control: true): _pasteSubFromClipboard,
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

                    // Sort subNodes: working nodes first (lowest ping), then untested, then timed-out last
                    subNodes.sort((a, b) {
                      if (a.hasValidPing && b.hasValidPing) {
                        return a.latencyMs!.compareTo(b.latencyMs!);
                      }
                      if (a.hasValidPing && !b.hasValidPing) return -1;
                      if (!a.hasValidPing && b.hasValidPing) return 1;
                      if (a.isUntested && b.hasTimedOut) return -1;
                      if (a.hasTimedOut && b.isUntested) return 1;
                      return a.name.compareTo(b.name);
                    });

                    final isExpandedAll = _expandedSubConfigs.contains(sub.id);
                    final maxDisplay = _expandedSubLimit[sub.id] ?? 50;
                    final selectedCountry = _subCountryFilterMap[sub.id];
                    final filteredSubNodes = subNodes.where((n) {
                      if (selectedCountry == null) return true;
                      if (selectedCountry == '__timeouts__') {
                        return n.hasTimedOut;
                      }
                      if (selectedCountry == '__unknown__') {
                        return n.hasValidPing && (n.countryCode == null || n.countryCode!.trim().isEmpty);
                      }
                      return n.hasValidPing && n.countryCode?.trim().toUpperCase() == selectedCountry;
                    }).toList();
                    final displayedNodes = isExpandedAll ? filteredSubNodes.take(maxDisplay).toList() : filteredSubNodes.take(3).toList();

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
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "${sub.nodeCount} nodes  •  ${sub.lastUpdated != null ? 'Updated: ' + sub.lastUpdated!.toLocal().toString().substring(0, 16) : 'Never updated'}",
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12),
                            ),
                            if (sub.formattedRemainingTraffic != null || sub.formattedRemainingTime != null) ...[
                              const SizedBox(height: 4),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: [
                                  if (sub.formattedRemainingTraffic != null)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.blue.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.5), width: 0.8),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.data_usage_rounded, size: 12, color: Colors.blueAccent),
                                          const SizedBox(width: 4),
                                          Text(
                                            sub.formattedRemainingTraffic!,
                                            style: const TextStyle(fontSize: 11, color: Colors.blueAccent, fontWeight: FontWeight.bold),
                                          ),
                                        ],
                                      ),
                                    ),
                                  if (sub.formattedRemainingTime != null)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: (sub.expireDate != null && sub.expireDate!.isBefore(DateTime.now()))
                                            ? Colors.red.withValues(alpha: 0.15)
                                            : Colors.orange.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                          color: (sub.expireDate != null && sub.expireDate!.isBefore(DateTime.now()))
                                              ? Colors.redAccent.withValues(alpha: 0.5)
                                              : Colors.orangeAccent.withValues(alpha: 0.5),
                                          width: 0.8,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.timer_outlined,
                                            size: 12,
                                            color: (sub.expireDate != null && sub.expireDate!.isBefore(DateTime.now()))
                                                ? Colors.redAccent
                                                : Colors.orangeAccent,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            sub.formattedRemainingTime!,
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: (sub.expireDate != null && sub.expireDate!.isBefore(DateTime.now()))
                                                  ? Colors.redAccent
                                                  : Colors.orangeAccent,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ],
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
                                      ? (_subEtaMap[sub.id] != null
                                          ? '$subPercent% (${_subEtaMap[sub.id]})'
                                          : '$subPercent% (${AppStrings.get("cancel_scan", locale: locale)})')
                                      : AppStrings.get("test_all_sub", locale: locale),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isTestingSub ? Colors.amber : null,
                                    fontWeight: isTestingSub ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                                onPressed: () => _testAllSubNodes(sub, subNodes),
                              ),
                              const SizedBox(width: 4),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.delete_sweep_rounded, size: 18, color: Colors.redAccent),
                                tooltip: AppStrings.get("delete_sub_dead", locale: locale),
                                onPressed: () => _deleteDeadSubNodes(sub, subNodes, locale),
                              ),
                              const SizedBox(width: 4),
                            ],
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.edit, size: 18, color: Colors.amberAccent),
                              tooltip: "Edit Subscription",
                              onPressed: () => _showEditSubDialog(sub, locale),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.share, size: 18, color: Colors.purpleAccent),
                              tooltip: "Share Subscription URL",
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: sub.url));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text("Subscription URL copied to clipboard.")),
                                );
                              },
                            ),
                            if (isUpdating)
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 8),
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              )
                            else
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.sync_rounded, size: 18, color: Colors.cyanAccent),
                                tooltip: "Update subscription",
                                onPressed: () => _updateSub(sub),
                              ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: Icon(Icons.delete_outline_rounded, size: 18, color: Colors.redAccent.shade100),
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
                          if (subNodes.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                              child: CountryFilterBar(
                                nodes: subNodes,
                                selectedCountryCode: _subCountryFilterMap[sub.id],
                                onCountrySelected: (code) {
                                  setState(() {
                                    _subCountryFilterMap[sub.id] = code;
                                  });
                                },
                                locale: locale,
                              ),
                            ),
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
                                final cdnMap = ref.watch(nodeCdnMapProvider);
                                final cdn = cdnMap[node.address.trim().toLowerCase()] ?? ref.read(nodeCdnMapProvider.notifier).detectCdn(node.address);

                                final isThisNodeConnected = isConnected && node.isActive;
                                final displayCountryCode = isThisNodeConnected
                                    ? (outbound.countryCode ?? node.countryCode)
                                    : node.countryCode;
                                final displayCountry = isThisNodeConnected
                                    ? (outbound.country ?? node.country ?? (displayCountryCode != null ? CountryService.getCountryName(displayCountryCode) : null))
                                    : node.country;

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
                                      if (cdn != null) ...[
                                        const SizedBox(width: 6),
                                        CdnBadge(cdn: cdn),
                                      ],
                                    ],
                                  ),
                                  subtitle: Text(
                                    "${IpMaskUtil.mask(node.address, showFull: showFullIp)}:${node.port}  •  ${node.protocol.name.toUpperCase()}  •  ${node.network.name.toUpperCase()}",
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (displayCountryCode != null && displayCountryCode.isNotEmpty) ...[
                                        CountryPillBadge(
                                          countryCode: displayCountryCode,
                                          country: displayCountry,
                                        ),
                                        const SizedBox(width: 5),
                                      ],
                                      if (isTesting)
                                        const Padding(
                                          padding: EdgeInsets.symmetric(horizontal: 8),
                                          child: SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(strokeWidth: 2),
                                          ),
                                        )
                                      else if (node.hasValidPing) ...[
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: AppTheme.successColor.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(color: AppTheme.successColor.withValues(alpha: 0.3), width: 0.8),
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
                                      ]
                                      else if (node.hasTimedOut)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: AppTheme.errorColor.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(color: AppTheme.errorColor.withValues(alpha: 0.4), width: 0.8),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(Icons.cloud_off_rounded, size: 11, color: AppTheme.errorColor),
                                              const SizedBox(width: 3),
                                              Text(
                                                AppStrings.get("timeout", locale: locale),
                                                style: const TextStyle(
                                                  color: AppTheme.errorColor,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      IconButton(
                                        visualDensity: VisualDensity.compact,
                                        icon: const Icon(Icons.bolt_rounded, size: 18, color: Colors.cyanAccent),
                                        tooltip: "Ping test",
                                        onPressed: () => _testNodeLatency(node),
                                      ),
                                      IconButton(
                                        visualDensity: VisualDensity.compact,
                                        icon: const Icon(Icons.edit, size: 18, color: Colors.amberAccent),
                                        tooltip: AppStrings.get("edit_config", locale: locale),
                                        onPressed: () => EditConfigDialog.show(context, node, locale),
                                      ),
                                      IconButton(
                                        visualDensity: VisualDensity.compact,
                                        icon: const Icon(Icons.share, size: 18, color: Colors.purpleAccent),
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
                                    ref.read(connectionStatusProvider.notifier).switchNode(node.id);
                                  },
                                );
                              },
                            ),
                            if (filteredSubNodes.length > 3)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
                                child: Center(
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (isExpandedAll && filteredSubNodes.length > displayedNodes.length)
                                        TextButton.icon(
                                          icon: const Icon(Icons.add_rounded, size: 16),
                                          label: Text(
                                            locale == 'fa'
                                                ? 'نمایش بیشتر (+50 از ${filteredSubNodes.length - displayedNodes.length} باقی‌مانده)'
                                                : 'Show More (+50 of ${filteredSubNodes.length - displayedNodes.length} remaining)',
                                            style: const TextStyle(fontSize: 12),
                                          ),
                                          onPressed: () {
                                            setState(() {
                                              _expandedSubLimit[sub.id] = (_expandedSubLimit[sub.id] ?? 50) + 50;
                                            });
                                          },
                                        ),
                                      if (isExpandedAll && filteredSubNodes.length > displayedNodes.length)
                                        const SizedBox(width: 12),
                                      TextButton.icon(
                                        icon: Icon(
                                          isExpandedAll ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                                          size: 18,
                                        ),
                                        label: Text(
                                          isExpandedAll
                                              ? AppStrings.get("show_less_configs", locale: locale)
                                              : "${AppStrings.get("show_all_configs", locale: locale)} (${filteredSubNodes.length})",
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                        onPressed: () {
                                          setState(() {
                                            if (isExpandedAll) {
                                              _expandedSubConfigs.remove(sub.id);
                                              _expandedSubLimit[sub.id] = 50;
                                            } else {
                                              _expandedSubConfigs.add(sub.id);
                                            }
                                          });
                                        },
                                      ),
                                    ],
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
      ),
    ),
  );
  }
}