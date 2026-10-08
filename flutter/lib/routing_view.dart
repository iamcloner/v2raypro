import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'core/l10n/translations.dart';
import 'core/theme/app_theme.dart';
import 'models/routing_rule.dart';
import 'providers/app_providers.dart';

class RoutingView extends ConsumerStatefulWidget {
  const RoutingView({super.key});

  @override
  ConsumerState<RoutingView> createState() => _RoutingViewState();
}

class _RoutingViewState extends ConsumerState<RoutingView> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  RoutingRuleType _typeForIndex(int index) {
    switch (index) {
      case 0:
        return RoutingRuleType.address;
      case 1:
        return RoutingRuleType.ip;
      case 2:
      default:
        return RoutingRuleType.app;
    }
  }

  void _showRuleDialog({RoutingRule? existingRule, RoutingRuleType? defaultType}) {
    final locale = ref.read(currentLocaleProvider);
    final type = existingRule?.type ?? defaultType ?? _typeForIndex(_tabController.index);
    final valuesController = TextEditingController(
      text: existingRule != null ? existingRule.values.join('\n') : '',
    );
    final remarkController = TextEditingController(text: existingRule?.remark ?? '');
    var selectedAction = existingRule?.action ?? RoutingAction.direct;

    String hintText;
    switch (type) {
      case RoutingRuleType.address:
        hintText = AppStrings.get('routing_pattern_hint', locale: locale);
        break;
      case RoutingRuleType.ip:
        hintText = AppStrings.get('routing_ip_hint', locale: locale);
        break;
      case RoutingRuleType.app:
        hintText = AppStrings.get('routing_app_hint', locale: locale);
        break;
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1E2230),
          title: Row(
            children: [
              Icon(
                existingRule != null ? Icons.edit_note_rounded : Icons.add_circle_outline_rounded,
                color: AppTheme.primaryAccent,
              ),
              const SizedBox(width: 8),
              Text(
                existingRule != null
                    ? AppStrings.get('routing_edit_rule', locale: locale)
                    : AppStrings.get('routing_add_rule', locale: locale),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppStrings.get('routing_action', locale: locale),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<RoutingAction>(
                    segments: [
                      ButtonSegment<RoutingAction>(
                        value: RoutingAction.direct,
                        label: Text(AppStrings.get('routing_action_direct', locale: locale)),
                        icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                      ),
                      ButtonSegment<RoutingAction>(
                        value: RoutingAction.proxy,
                        label: Text(AppStrings.get('routing_action_proxy', locale: locale)),
                        icon: const Icon(Icons.vpn_lock_rounded, size: 16),
                      ),
                      ButtonSegment<RoutingAction>(
                        value: RoutingAction.block,
                        label: Text(AppStrings.get('routing_action_block', locale: locale)),
                        icon: const Icon(Icons.block_rounded, size: 16),
                      ),
                    ],
                    selected: {selectedAction},
                    onSelectionChanged: (val) {
                      setDialogState(() => selectedAction = val.first);
                    },
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: remarkController,
                    decoration: InputDecoration(
                      labelText: locale == 'fa' ? 'یادداشت / برچسب (اختیاری)' : 'Remark / Label (Optional)',
                      hintText: locale == 'fa' ? 'مثال: سایت‌های ایرانی، تبلیغات' : 'e.g. Local traffic, Ads',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: valuesController,
                    maxLines: 6,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                    decoration: InputDecoration(
                      labelText: locale == 'fa' ? 'مقادیر (یک مورد در هر سطر یا با ویرگول)' : 'Values (one per line or comma-separated)',
                      hintText: hintText,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    hintText,
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(AppStrings.get('cancel', locale: locale)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryAccent,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                final raw = valuesController.text;
                final lines = raw
                    .split(RegExp(r'[\n,]'))
                    .map((s) => s.trim())
                    .where((s) => s.isNotEmpty)
                    .toList();
                if (lines.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(locale == 'fa' ? 'لطفاً حداقل یک مقدار وارد کنید' : 'Please enter at least one value'),
                    ),
                  );
                  return;
                }

                final remark = remarkController.text.trim();
                if (existingRule != null) {
                  final updated = existingRule.copyWith(
                    action: selectedAction,
                    values: lines,
                    remark: remark.isNotEmpty ? remark : null,
                  );
                  ref.read(routingRulesProvider.notifier).updateRule(updated);
                } else {
                  final newRule = RoutingRule(
                    id: const Uuid().v4(),
                    type: type,
                    values: lines,
                    action: selectedAction,
                    enabled: true,
                    remark: remark.isNotEmpty ? remark : null,
                  );
                  ref.read(routingRulesProvider.notifier).addRule(newRule);
                }

                if (ref.read(connectionStatusProvider) == ConnectionStateEnum.connected) {
                  ref.read(connectionStatusProvider.notifier).reconnectWithUpdatedSettings();
                }

                Navigator.pop(ctx);
              },
              child: Text(AppStrings.get('save', locale: locale)),
            ),
          ],
        ),
      ),
    );
  }

  Color _actionColor(RoutingAction action) {
    switch (action) {
      case RoutingAction.direct:
        return AppTheme.successColor;
      case RoutingAction.proxy:
        return AppTheme.primaryAccent;
      case RoutingAction.block:
        return Colors.redAccent;
    }
  }

  IconData _actionIcon(RoutingAction action) {
    switch (action) {
      case RoutingAction.direct:
        return Icons.arrow_forward_rounded;
      case RoutingAction.proxy:
        return Icons.vpn_lock_rounded;
      case RoutingAction.block:
        return Icons.block_rounded;
    }
  }

  String _actionLabel(RoutingAction action, String locale) {
    switch (action) {
      case RoutingAction.direct:
        return AppStrings.get('routing_action_direct', locale: locale);
      case RoutingAction.proxy:
        return AppStrings.get('routing_action_proxy', locale: locale);
      case RoutingAction.block:
        return AppStrings.get('routing_action_block', locale: locale);
    }
  }

  Widget _buildRuleList(RoutingRuleType type, String locale) {
    final allRules = ref.watch(routingRulesProvider);
    final rules = allRules.where((r) => r.type == type).toList();

    return Column(
      children: [
        if (type == RoutingRuleType.app)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded, color: Colors.amber, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    AppStrings.get('routing_tun_required', locale: locale),
                    style: const TextStyle(fontSize: 12, color: Colors.amberAccent),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: rules.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.alt_route_rounded, size: 48, color: Colors.grey.withValues(alpha: 0.4)),
                      const SizedBox(height: 12),
                      Text(
                        AppStrings.get('routing_empty', locale: locale),
                        style: const TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryAccent,
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: Text(AppStrings.get('routing_add_rule', locale: locale)),
                        onPressed: () => _showRuleDialog(defaultType: type),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: rules.length,
                  itemBuilder: (ctx, idx) {
                    final rule = rules[idx];
                    final actionColor = _actionColor(rule.action);

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Switch(
                              value: rule.enabled,
                              activeColor: AppTheme.primaryAccent,
                              onChanged: (val) {
                                ref.read(routingRulesProvider.notifier).toggleRule(rule.id, val);
                                if (ref.read(connectionStatusProvider) == ConnectionStateEnum.connected) {
                                  ref.read(connectionStatusProvider.notifier).reconnectWithUpdatedSettings();
                                }
                              },
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: actionColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: actionColor.withValues(alpha: 0.4)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(_actionIcon(rule.action), size: 14, color: actionColor),
                                  const SizedBox(width: 4),
                                  Text(
                                    _actionLabel(rule.action, locale),
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: actionColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (rule.remark != null && rule.remark!.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 4),
                                      child: Text(
                                        rule.remark!,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  Wrap(
                                    spacing: 4,
                                    runSpacing: 4,
                                    children: rule.values.map((v) {
                                      return Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(alpha: 0.06),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          v,
                                          style: const TextStyle(
                                            fontFamily: 'monospace',
                                            fontSize: 11,
                                            color: Colors.white70,
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit_rounded, size: 18),
                              tooltip: AppStrings.get('routing_edit_rule', locale: locale),
                              onPressed: () => _showRuleDialog(existingRule: rule),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.redAccent),
                              tooltip: AppStrings.get('delete', locale: locale),
                              onPressed: () {
                                ref.read(routingRulesProvider.notifier).deleteRule(rule.id);
                                if (ref.read(connectionStatusProvider) == ConnectionStateEnum.connected) {
                                  ref.read(connectionStatusProvider.notifier).reconnectWithUpdatedSettings();
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(currentLocaleProvider);

    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppStrings.get('routing', locale: locale),
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      AppStrings.get('routing_desc', locale: locale),
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: Text(AppStrings.get('routing_add_rule', locale: locale)),
                  onPressed: () => _showRuleDialog(),
                ),
              ],
            ),
          ),
          TabBar(
            controller: _tabController,
            tabs: [
              Tab(
                icon: const Icon(Icons.language_rounded, size: 18),
                text: AppStrings.get('routing_tab_address', locale: locale),
              ),
              Tab(
                icon: const Icon(Icons.lan_rounded, size: 18),
                text: AppStrings.get('routing_tab_ip', locale: locale),
              ),
              Tab(
                icon: const Icon(Icons.apps_rounded, size: 18),
                text: AppStrings.get('routing_tab_app', locale: locale),
              ),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildRuleList(RoutingRuleType.address, locale),
                _buildRuleList(RoutingRuleType.ip, locale),
                _buildRuleList(RoutingRuleType.app, locale),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
