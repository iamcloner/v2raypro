import 'dart:io';
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
  final VoidCallback? onOpenDrawer;
  const SubscriptionsView({super.key, this.onOpenDrawer});

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

  void _showAddSubBottomSheet(String locale) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                AppStrings.get("add_subscription", locale: locale),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.add_link_rounded, color: AppTheme.primaryAccent),
                ),
                title: Text(locale == 'fa' ? 'افزودن لینک سابسکریپشن' : 'Add Subscription URL'),
                subtitle: Text(
                  locale == 'fa' ? 'وارد کردن نام و لینک اشتراک' : 'Enter subscription name and URL',
                  style: const TextStyle(fontSize: 11),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _showAddDialog(locale);
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.tealAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.content_paste_rounded, color: Colors.tealAccent),
                ),
                title: Text(locale == 'fa' ? 'از کلیپ‌بورد (Paste from Clipboard)' : 'Import from Clipboard'),
                subtitle: Text(
                  locale == 'fa' ? 'خواندن خودکار لینک ساب کپی شده' : 'Auto import copied subscription link',
                  style: const TextStyle(fontSize: 11),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _pasteSubFromClipboard();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

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

    final testMode = ref.read(testModeProvider);
    final res = await XrayProcessService.instance.testNodeRealDelay(
      node,
      isTurbo: testMode == TestMode.turbo,
    );
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
      _subCountryFilterMap.remove(subId);
      _testingSubMap[subId] = true;
      _cancelSubMap[subId] = false;
      _testingNodeIds.addAll(subNodes.map((n) => n.id));
      _subTotalCount[subId] = subNodes.length;
      _subTestedCount[subId] = 0;
    });

    ref.read(nodesProvider.notifier).clearLatencies(subscriptionId: subId);

    int currentIndex = 0;
    final concurrency = ref.read(testConcurrencyProvider);
    final testMode = ref.read(testModeProvider);
    final isTurbo = testMode == TestMode.turbo;
    final testStartTime = DateTime.now();

    Future<void> runWorker() async {
      while (currentIndex < subNodes.length && _cancelSubMap[subId] != true && mounted) {
        final nodeIndex = currentIndex++;
        if (nodeIndex >= subNodes.length) break;
        final n = subNodes[nodeIndex];

        final res = await XrayProcessService.instance.testNodeRealDelay(
          n,
          isTurbo: isTurbo,
        );
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
          appBar: Platform.isAndroid
              ? AppBar(
                  leading: IconButton(
                    icon: const Icon(Icons.menu_rounded),
                    tooltip: AppStrings.get('more', locale: locale),
                    onPressed: widget.onOpenDrawer,
                  ),
                  titleSpacing: 0,
                  title: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(7),
                          border: Border.all(
                            color: const Color(0xFF00D2FF).withValues(alpha: 0.4),
                            width: 1.2,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Image.asset('assets/app_icon.png', fit: BoxFit.cover),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        AppStrings.get("subscriptions", locale: locale),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ],
                  ),
                  actions: [
                    if (subs.isNotEmpty)
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: _isUpdatingAll
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.sync_rounded, color: Colors.cyanAccent),
                        tooltip: AppStrings.get("update_all_subs", locale: locale),
                        onPressed: _isUpdatingAll ? null : _updateAllSubs,
                      ),
                    const SizedBox(width: 4),
                  ],
                )
              : null,
          floatingActionButton: Platform.isAndroid
              ? FloatingActionButton(
                  backgroundColor: AppTheme.primaryAccent,
                  foregroundColor: Colors.white,
                  elevation: 4,
                  shape: const CircleBorder(),
                  tooltip: AppStrings.get("add_subscription", locale: locale),
                  onPressed: () => _showAddSubBottomSheet(locale),
                  child: const Icon(Icons.add, size: 28),
                )
              : null,
          body: Padding(
            padding: EdgeInsets.all(Platform.isAndroid ? 12 : 24),
            child: Column(
              children: [
                if (!Platform.isAndroid) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          AppStrings.get("subscriptions", locale: locale),
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
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
                ],
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
                      final nCode = n.countryCode ?? CountryService.resolveSync(n);
                      if (selectedCountry == '__unknown__') {
                        return n.hasValidPing && (nCode == null || nCode.trim().isEmpty);
                      }
                      return n.hasValidPing && nCode?.trim().toUpperCase() == selectedCountry;
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
                        trailing: Platform.isAndroid
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // 1. Test ping button (OUTSIDE)
                                  if (subNodes.isNotEmpty)
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      icon: isTestingSub
                                          ? SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(
                                                value: subProgress > 0 ? subProgress : null,
                                                strokeWidth: 2,
                                                color: Colors.amber,
                                              ),
                                            )
                                          : const Icon(Icons.speed_rounded, size: 20, color: Colors.blueAccent),
                                      tooltip: isTestingSub
                                          ? (_subEtaMap[sub.id] != null
                                              ? '$subPercent% (${_subEtaMap[sub.id]})'
                                              : '$subPercent% (${AppStrings.get("cancel_scan", locale: locale)})')
                                          : AppStrings.get("test_all_sub", locale: locale),
                                      onPressed: () => _testAllSubNodes(sub, subNodes),
                                    ),
                                  // 2. Update sub button (OUTSIDE)
                                  if (isUpdating)
                                    const Padding(
                                      padding: EdgeInsets.symmetric(horizontal: 6),
                                      child: SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      ),
                                    )
                                  else
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      icon: const Icon(Icons.sync_rounded, size: 20, color: Colors.cyanAccent),
                                      tooltip: "Update subscription",
                                      onPressed: () => _updateSub(sub),
                                    ),
                                  // 3. Options Menu (delete dead, edit, share, delete sub)
                                  PopupMenuButton<String>(
                                    icon: const Icon(Icons.more_vert_rounded, size: 20),
                                    padding: EdgeInsets.zero,
                                    tooltip: "Options",
                                    onSelected: (val) {
                                      if (val == 'delete_dead') {
                                        _deleteDeadSubNodes(sub, subNodes, locale);
                                      } else if (val == 'edit') {
                                        _showEditSubDialog(sub, locale);
                                      } else if (val == 'share') {
                                        Clipboard.setData(ClipboardData(text: sub.url));
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text("Subscription URL copied to clipboard.")),
                                        );
                                      } else if (val == 'delete') {
                                        ref.read(subscriptionsProvider.notifier).removeSubscription(sub.id);
                                      }
                                    },
                                    itemBuilder: (ctx) => [
                                      if (subNodes.isNotEmpty)
                                        PopupMenuItem(
                                          value: 'delete_dead',
                                          child: Row(
                                            children: [
                                              const Icon(Icons.delete_sweep_rounded, size: 18, color: Colors.redAccent),
                                              const SizedBox(width: 8),
                                              Text(AppStrings.get("delete_sub_dead", locale: locale)),
                                            ],
                                          ),
                                        ),
                                      const PopupMenuItem(
                                        value: 'edit',
                                        child: Row(
                                          children: [
                                            Icon(Icons.edit, size: 18, color: Colors.amberAccent),
                                            SizedBox(width: 8),
                                            Text("Edit"),
                                          ],
                                        ),
                                      ),
                                      const PopupMenuItem(
                                        value: 'share',
                                        child: Row(
                                          children: [
                                            Icon(Icons.share, size: 18, color: Colors.purpleAccent),
                                            SizedBox(width: 8),
                                            Text("Share URL"),
                                          ],
                                        ),
                                      ),
                                      PopupMenuItem(
                                        value: 'delete',
                                        child: Row(
                                          children: [
                                            Icon(Icons.delete_forever_rounded, size: 18, color: Colors.redAccent.shade100),
                                            const SizedBox(width: 8),
                                            const Text("Delete"),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              )
                            : Row(
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
                                    ? (outbound.countryCode ?? node.countryCode ?? CountryService.resolveSync(node))
                                    : (node.countryCode ?? CountryService.resolveSync(node));
                                final displayCountry = isThisNodeConnected
                                    ? (outbound.country ?? node.country ?? (displayCountryCode != null ? CountryService.getCountryName(displayCountryCode) : null))
                                    : (node.country ?? (displayCountryCode != null ? CountryService.getCountryName(displayCountryCode) : null));

                                if (Platform.isAndroid) {
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    child: Card(
                                      margin: EdgeInsets.zero,
                                      elevation: node.isActive ? 2 : 0,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        side: node.isActive
                                            ? const BorderSide(color: AppTheme.primaryAccent, width: 2.0)
                                            : BorderSide(color: Colors.white.withValues(alpha: 0.08), width: 1.0),
                                      ),
                                      color: node.isActive
                                          ? AppTheme.primaryAccent.withValues(alpha: 0.08)
                                          : Theme.of(context).cardColor,
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(10),
                                        onTap: () {
                                          ref.read(connectionStatusProvider.notifier).switchNode(node.id);
                                        },
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Row(
                                                children: [
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: AppTheme.primaryAccent.withValues(alpha: 0.15),
                                                      borderRadius: BorderRadius.circular(4),
                                                    ),
                                                    child: Text(
                                                      node.protocol.name.toUpperCase(),
                                                      style: const TextStyle(
                                                        color: AppTheme.primaryAccent,
                                                        fontSize: 9.5,
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Expanded(
                                                    child: Text(
                                                      node.name,
                                                      style: TextStyle(
                                                        fontWeight: node.isActive ? FontWeight.bold : FontWeight.w600,
                                                        fontSize: 12.5,
                                                        color: node.isActive ? Colors.white : Colors.white.withValues(alpha: 0.9),
                                                      ),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  if (cdn != null) ...[
                                                    const SizedBox(width: 4),
                                                    CdnBadge(cdn: cdn),
                                                  ],
                                                  const SizedBox(width: 4),
                                                  PopupMenuButton<String>(
                                                    icon: const Icon(Icons.more_vert_rounded, size: 18),
                                                    padding: EdgeInsets.zero,
                                                    onSelected: (val) {
                                                      if (val == 'ping') {
                                                        _testNodeLatency(node);
                                                      } else if (val == 'edit') {
                                                        EditConfigDialog.show(context, node, locale);
                                                      } else if (val == 'share') {
                                                        Clipboard.setData(ClipboardData(text: node.toShareUrl()));
                                                        ScaffoldMessenger.of(context).showSnackBar(
                                                          SnackBar(content: Text(AppStrings.get("share_copied", locale: locale))),
                                                        );
                                                      }
                                                    },
                                                    itemBuilder: (ctx) => [
                                                      const PopupMenuItem(
                                                        value: 'ping',
                                                        child: Row(
                                                          children: [
                                                            Icon(Icons.bolt_rounded, size: 18, color: Colors.cyanAccent),
                                                            SizedBox(width: 8),
                                                            Text('Ping test'),
                                                          ],
                                                        ),
                                                      ),
                                                      PopupMenuItem(
                                                        value: 'edit',
                                                        child: Row(
                                                          children: [
                                                            const Icon(Icons.edit, size: 18, color: Colors.amberAccent),
                                                            const SizedBox(width: 8),
                                                            Text(AppStrings.get('edit_config', locale: locale)),
                                                          ],
                                                        ),
                                                      ),
                                                      PopupMenuItem(
                                                        value: 'share',
                                                        child: Row(
                                                          children: [
                                                            const Icon(Icons.share, size: 18, color: Colors.purpleAccent),
                                                            const SizedBox(width: 8),
                                                            Text(AppStrings.get('share_config', locale: locale)),
                                                          ],
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 5),
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: Row(
                                                      children: [
                                                        Icon(Icons.link_rounded, size: 12, color: Colors.grey.shade500),
                                                        const SizedBox(width: 4),
                                                        Flexible(
                                                          child: Text(
                                                            '${IpMaskUtil.mask(node.address, showFull: showFullIp)}:${node.port}',
                                                            style: TextStyle(fontSize: 10.5, color: Colors.grey.shade400),
                                                            overflow: TextOverflow.ellipsis,
                                                          ),
                                                        ),
                                                        const SizedBox(width: 6),
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                                          decoration: BoxDecoration(
                                                            color: Colors.white.withValues(alpha: 0.05),
                                                            borderRadius: BorderRadius.circular(3),
                                                          ),
                                                          child: Text(
                                                            node.network.name.toUpperCase(),
                                                            style: TextStyle(fontSize: 8.5, color: Colors.grey.shade400, fontWeight: FontWeight.bold),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  if (isTesting)
                                                    const SizedBox(
                                                      width: 14,
                                                      height: 14,
                                                      child: CircularProgressIndicator(strokeWidth: 2),
                                                    )
                                                  else ...[
                                                    if (displayCountryCode != null && displayCountryCode.isNotEmpty) ...[
                                                      CountryPillBadge(
                                                        countryCode: displayCountryCode,
                                                        country: displayCountry,
                                                      ),
                                                      const SizedBox(width: 5),
                                                    ],
                                                    if (node.hasValidPing)
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                                        decoration: BoxDecoration(
                                                          color: AppTheme.successColor.withValues(alpha: 0.15),
                                                          borderRadius: BorderRadius.circular(4),
                                                          border: Border.all(color: AppTheme.successColor.withValues(alpha: 0.3), width: 0.8),
                                                        ),
                                                        child: Text(
                                                          "${node.latencyMs} ms",
                                                          style: const TextStyle(
                                                            color: AppTheme.successColor,
                                                            fontSize: 10.5,
                                                            fontWeight: FontWeight.bold,
                                                          ),
                                                        ),
                                                      )
                                                    else if (node.hasTimedOut)
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                                        decoration: BoxDecoration(
                                                          color: AppTheme.errorColor.withValues(alpha: 0.15),
                                                          borderRadius: BorderRadius.circular(4),
                                                          border: Border.all(color: AppTheme.errorColor.withValues(alpha: 0.4), width: 0.8),
                                                        ),
                                                        child: Row(
                                                          mainAxisSize: MainAxisSize.min,
                                                          children: [
                                                            const Icon(Icons.cloud_off_rounded, size: 10, color: AppTheme.errorColor),
                                                            const SizedBox(width: 3),
                                                            Text(
                                                              AppStrings.get("timeout", locale: locale),
                                                              style: const TextStyle(
                                                                color: AppTheme.errorColor,
                                                                fontSize: 9.5,
                                                                fontWeight: FontWeight.bold,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                  ],
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                }

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