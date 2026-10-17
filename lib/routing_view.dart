import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';
import 'core/l10n/translations.dart';
import 'core/theme/app_theme.dart';
import 'models/routing_rule.dart';
import 'providers/app_providers.dart';

class RoutingView extends ConsumerStatefulWidget {
  final VoidCallback? onOpenDrawer;
  const RoutingView({super.key, this.onOpenDrawer});

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
          backgroundColor: Theme.of(context).cardColor,
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
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: math.min(480.0, MediaQuery.of(context).size.width * 0.88),
            ),
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
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        avatar: const Icon(Icons.arrow_forward_rounded, size: 16),
                        label: Text(AppStrings.get('routing_action_direct', locale: locale), style: const TextStyle(fontSize: 12)),
                        selected: selectedAction == RoutingAction.direct,
                        selectedColor: AppTheme.primaryAccent.withValues(alpha: 0.2),
                        onSelected: (val) {
                          if (val) setDialogState(() => selectedAction = RoutingAction.direct);
                        },
                      ),
                      ChoiceChip(
                        avatar: const Icon(Icons.vpn_lock_rounded, size: 16),
                        label: Text(AppStrings.get('routing_action_proxy', locale: locale), style: const TextStyle(fontSize: 12)),
                        selected: selectedAction == RoutingAction.proxy,
                        selectedColor: Colors.cyanAccent.withValues(alpha: 0.2),
                        onSelected: (val) {
                          if (val) setDialogState(() => selectedAction = RoutingAction.proxy);
                        },
                      ),
                      ChoiceChip(
                        avatar: const Icon(Icons.block_rounded, size: 16),
                        label: Text(AppStrings.get('routing_action_block', locale: locale), style: const TextStyle(fontSize: 12)),
                        selected: selectedAction == RoutingAction.block,
                        selectedColor: Colors.redAccent.withValues(alpha: 0.2),
                        onSelected: (val) {
                          if (val) setDialogState(() => selectedAction = RoutingAction.block);
                        },
                      ),
                    ],
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
                  if (type == RoutingRuleType.app) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            Platform.isAndroid
                                ? (locale == 'fa' ? 'برنامه اندروید:' : 'Android Application:')
                                : AppStrings.get('routing_app_file_label', locale: locale),
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (Platform.isAndroid)
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: AppTheme.primaryAccent, width: 1.2),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            ),
                            icon: const Icon(Icons.apps_rounded, size: 16, color: AppTheme.primaryAccent),
                            label: Text(
                              locale == 'fa' ? 'انتخاب از برنامه‌ها' : 'Select App',
                              style: const TextStyle(fontSize: 12, color: AppTheme.primaryAccent, fontWeight: FontWeight.bold),
                            ),
                            onPressed: () {
                              _showInstalledAppsPicker(context, locale, (appName, packageName) {
                                setDialogState(() {
                                  final current = valuesController.text.trim();
                                  if (current.isEmpty) {
                                    valuesController.text = packageName;
                                  } else {
                                    final lines = current
                                        .split(RegExp(r'[\r\n,]+'))
                                        .map((s) => s.trim())
                                        .where((s) => s.isNotEmpty)
                                        .toList();
                                    if (!lines.contains(packageName)) {
                                      lines.add(packageName);
                                      valuesController.text = lines.join('\n');
                                    }
                                  }
                                  if (remarkController.text.trim().isEmpty) {
                                    remarkController.text = appName;
                                  }
                                });
                              });
                            },
                          )
                        else
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: AppTheme.primaryAccent, width: 1.2),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            ),
                            icon: const Icon(Icons.folder_open_rounded, size: 16, color: AppTheme.primaryAccent),
                            label: Text(
                              AppStrings.get('routing_open_exe', locale: locale),
                              style: const TextStyle(fontSize: 12, color: AppTheme.primaryAccent, fontWeight: FontWeight.bold),
                            ),
                            onPressed: () async {
                              try {
                                final result = await FilePicker.platform.pickFiles(
                                  type: FileType.custom,
                                  allowedExtensions: ['exe'],
                                  dialogTitle: locale == 'fa' ? 'انتخاب فایل اجرایی برنامه (.exe)' : 'Select Executable (.exe)',
                                );
                                if (result != null && result.files.isNotEmpty) {
                                  final fileName = result.files.single.name;
                                  if (fileName.isNotEmpty) {
                                    setDialogState(() {
                                      final current = valuesController.text.trim();
                                      if (current.isEmpty) {
                                        valuesController.text = fileName;
                                      } else {
                                        final lines = current
                                            .split(RegExp(r'[\r\n,]+'))
                                            .map((s) => s.trim())
                                            .where((s) => s.isNotEmpty)
                                            .toList();
                                        if (!lines.any((l) => l.toLowerCase() == fileName.toLowerCase())) {
                                          lines.add(fileName);
                                          valuesController.text = lines.join('\n');
                                        }
                                      }
                                      if (remarkController.text.trim().isEmpty) {
                                        final base = fileName.replaceAll(RegExp(r'\.exe$', caseSensitive: false), '');
                                        if (base.isNotEmpty) {
                                          remarkController.text = base[0].toUpperCase() + base.substring(1);
                                        }
                                      }
                                    });
                                  }
                                }
                              } catch (_) {}
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                  TextField(
                    controller: valuesController,
                    maxLines: 5,
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

  void _showInstalledAppsPicker(
    BuildContext context,
    String locale,
    void Function(String appName, String packageName) onSelected,
  ) {
    showDialog(
      context: context,
      builder: (ctx) {
        String filter = '';
        return StatefulBuilder(
          builder: (dialogCtx, setModalState) {
            return AlertDialog(
              backgroundColor: Theme.of(context).cardColor,
              title: Row(
                children: [
                  const Icon(Icons.apps_rounded, color: AppTheme.primaryAccent),
                  const SizedBox(width: 8),
                  Text(
                    locale == 'fa' ? 'انتخاب برنامه' : 'Select Application',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              content: SizedBox(
                width: math.min(420.0, MediaQuery.of(context).size.width * 0.9),
                height: 400,
                child: Column(
                  children: [
                    TextField(
                      autofocus: false,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search_rounded, size: 18),
                        hintText: locale == 'fa' ? 'جستجوی برنامه...' : 'Search app...',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onChanged: (val) {
                        setModalState(() {
                          filter = val.trim().toLowerCase();
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: FutureBuilder<List<dynamic>?>(
                        future: const MethodChannel('com.v2raypro.app/native').invokeMethod<List<dynamic>>('getInstalledApps'),
                        builder: (fCtx, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          if (snapshot.hasError || !snapshot.hasData) {
                            return Center(
                              child: Text(
                                locale == 'fa' ? 'خطا در بارگذاری برنامه‌ها' : 'Failed to load apps',
                                style: const TextStyle(color: Colors.redAccent),
                              ),
                            );
                          }
                          final rawApps = snapshot.data!;
                          final apps = rawApps.map((item) {
                            final map = Map<String, dynamic>.from(item as Map);
                            return {
                              'name': map['name']?.toString() ?? '',
                              'packageName': map['packageName']?.toString() ?? '',
                            };
                          }).where((app) {
                            if (filter.isEmpty) return true;
                            final n = app['name']!.toLowerCase();
                            final p = app['packageName']!.toLowerCase();
                            return n.contains(filter) || p.contains(filter);
                          }).toList();

                          if (apps.isEmpty) {
                            return Center(
                              child: Text(
                                locale == 'fa' ? 'برنامه‌ای یافت نشد' : 'No applications found',
                                style: const TextStyle(color: Colors.grey),
                              ),
                            );
                          }

                          return ListView.separated(
                            itemCount: apps.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (_, idx) {
                              final app = apps[idx];
                              return ListTile(
                                dense: true,
                                leading: Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryAccent.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Icon(Icons.android_rounded, color: AppTheme.primaryAccent, size: 18),
                                ),
                                title: Text(
                                  app['name']!,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  app['packageName']!,
                                  style: const TextStyle(fontSize: 10, color: Colors.grey, fontFamily: 'monospace'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                onTap: () {
                                  Navigator.pop(dialogCtx);
                                  onSelected(app['name']!, app['packageName']!);
                                },
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: Text(AppStrings.get('cancel', locale: locale)),
                ),
              ],
            );
          },
        );
      },
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
        if (type == RoutingRuleType.app) ...[
          _buildAppRoutingModeCard(locale),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded, color: Colors.amber, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    AppStrings.get('routing_tun_required', locale: locale),
                    style: const TextStyle(fontSize: 11.5, color: Colors.amberAccent),
                  ),
                ),
              ],
            ),
          ),
        ],
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
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: [
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryAccent,
                              foregroundColor: Colors.white,
                            ),
                            icon: const Icon(Icons.add_rounded, size: 18),
                            label: Text(AppStrings.get('routing_add_rule', locale: locale)),
                            onPressed: () => _showRuleDialog(defaultType: type),
                          ),
                          if (type == RoutingRuleType.app)
                            if (Platform.isAndroid)
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: AppTheme.primaryAccent, width: 1.2),
                                ),
                                icon: const Icon(Icons.apps_rounded, size: 18, color: AppTheme.primaryAccent),
                                label: Text(
                                  locale == 'fa' ? 'انتخاب از برنامه‌ها' : 'Select App',
                                  style: const TextStyle(color: AppTheme.primaryAccent, fontWeight: FontWeight.bold),
                                ),
                                onPressed: () {
                                  _showInstalledAppsPicker(context, locale, (appName, packageName) {
                                    _showRuleDialog(
                                      defaultType: RoutingRuleType.app,
                                      existingRule: RoutingRule(
                                        id: const Uuid().v4(),
                                        type: RoutingRuleType.app,
                                        values: [packageName],
                                        action: RoutingAction.direct,
                                        enabled: true,
                                        remark: appName,
                                      ),
                                    );
                                  });
                                },
                              )
                            else
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: AppTheme.primaryAccent, width: 1.2),
                                ),
                                icon: const Icon(Icons.folder_open_rounded, size: 18, color: AppTheme.primaryAccent),
                                label: Text(
                                  AppStrings.get('routing_open_exe', locale: locale),
                                  style: const TextStyle(color: AppTheme.primaryAccent, fontWeight: FontWeight.bold),
                                ),
                                onPressed: () async {
                                  try {
                                    final result = await FilePicker.platform.pickFiles(
                                      type: FileType.custom,
                                      allowedExtensions: ['exe'],
                                      dialogTitle: locale == 'fa' ? 'انتخاب فایل اجرایی برنامه (.exe)' : 'Select Executable (.exe)',
                                    );
                                    if (result != null && result.files.isNotEmpty) {
                                      final fileName = result.files.single.name;
                                      if (fileName.isNotEmpty) {
                                        final base = fileName.replaceAll(RegExp(r'\.exe$', caseSensitive: false), '');
                                        final remark = base.isNotEmpty ? base[0].toUpperCase() + base.substring(1) : null;
                                        _showRuleDialog(
                                          defaultType: RoutingRuleType.app,
                                          existingRule: RoutingRule(
                                            id: const Uuid().v4(),
                                            type: RoutingRuleType.app,
                                            values: [fileName],
                                            action: RoutingAction.direct,
                                            enabled: true,
                                            remark: remark,
                                          ),
                                        );
                                      }
                                    }
                                  } catch (_) {}
                                },
                              ),
                        ],
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
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: Theme.of(context).colorScheme.onSurface,
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
                                          color: Theme.of(context).brightness == Brightness.dark
                                              ? Colors.white.withValues(alpha: 0.06)
                                              : Colors.black.withValues(alpha: 0.05),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          v,
                                          style: TextStyle(
                                            fontFamily: 'monospace',
                                            fontSize: 11,
                                            color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                    AppStrings.get('routing', locale: locale),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              actions: [
                IconButton(
                  tooltip: AppStrings.get('routing_add_rule', locale: locale),
                  icon: const Icon(Icons.add_rounded, color: AppTheme.primaryAccent),
                  onPressed: () => _showRuleDialog(),
                ),
              ],
            )
          : null,
      body: Column(
        children: [
          if (!Platform.isAndroid)
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

  Widget _buildAppRoutingModeCard(String locale) {
    final mode = ref.watch(appRoutingModeProvider);
    final isExclusive = mode == AppRoutingMode.exclusive;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.tune_rounded, size: 18, color: AppTheme.primaryAccent),
              const SizedBox(width: 8),
              Text(
                AppStrings.get('app_routing_policy', locale: locale),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: isExclusive
                      ? Colors.orange.withValues(alpha: 0.15)
                      : AppTheme.primaryAccent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isExclusive ? 'Exclusive' : 'Inclusive',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isExclusive ? Colors.orange : AppTheme.primaryAccent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () {
                    if (!isExclusive) {
                      ref.read(appRoutingModeProvider.notifier).setMode(AppRoutingMode.exclusive);
                      if (ref.read(connectionStatusProvider) == ConnectionStateEnum.connected) {
                        ref.read(connectionStatusProvider.notifier).reconnectWithUpdatedSettings();
                      }
                    }
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: isExclusive
                          ? Colors.orange.withValues(alpha: 0.12)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isExclusive
                            ? Colors.orange
                            : Theme.of(context).dividerColor.withValues(alpha: 0.4),
                        width: isExclusive ? 1.5 : 1.0,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.call_split_rounded,
                              size: 16,
                              color: isExclusive ? Colors.orange : Colors.grey,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                AppStrings.get('app_routing_exclusive', locale: locale),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: isExclusive ? Colors.orange : null,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          AppStrings.get('app_routing_exclusive_desc', locale: locale),
                          style: TextStyle(
                            fontSize: 10,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                            height: 1.25,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: InkWell(
                  onTap: () {
                    if (isExclusive) {
                      ref.read(appRoutingModeProvider.notifier).setMode(AppRoutingMode.inclusive);
                      if (ref.read(connectionStatusProvider) == ConnectionStateEnum.connected) {
                        ref.read(connectionStatusProvider.notifier).reconnectWithUpdatedSettings();
                      }
                    }
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: !isExclusive
                          ? AppTheme.primaryAccent.withValues(alpha: 0.12)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: !isExclusive
                            ? AppTheme.primaryAccent
                            : Theme.of(context).dividerColor.withValues(alpha: 0.4),
                        width: !isExclusive ? 1.5 : 1.0,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.filter_alt_rounded,
                              size: 16,
                              color: !isExclusive ? AppTheme.primaryAccent : Colors.grey,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                AppStrings.get('app_routing_inclusive', locale: locale),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: !isExclusive ? AppTheme.primaryAccent : null,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          AppStrings.get('app_routing_inclusive_desc', locale: locale),
                          style: TextStyle(
                            fontSize: 10,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                            height: 1.25,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
