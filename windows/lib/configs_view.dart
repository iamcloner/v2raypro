import 'dart:convert';
import 'dart:io';
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
import 'widgets/country_filter_bar.dart';
import 'services/country_service.dart';
import 'services/storage_service.dart';
import 'widgets/qr_scanner_dialog.dart';

class ConfigsView extends ConsumerStatefulWidget {
  final VoidCallback? onNavigateToFreeConfigs;
  final VoidCallback? onOpenDrawer;
  const ConfigsView({super.key, this.onNavigateToFreeConfigs, this.onOpenDrawer});

  @override
  ConsumerState<ConfigsView> createState() => _ConfigsViewState();
}

class _ConfigsViewState extends ConsumerState<ConfigsView> {
  final Set<String> _testingNodeIds = {};
  bool _isTestingAll = false;
  bool _cancelTestingAll = false;
  int _totalToTest = 0;
  int _testedCount = 0;
  String? _selectedCountryCode;
  String? _testRemainingEta;

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
      _selectedCountryCode = null;
      _isTestingAll = true;
      _cancelTestingAll = false;
      _testingNodeIds.addAll(nodes.map((n) => n.id));
      _totalToTest = nodes.length;
      _testedCount = 0;
    });

    ref.read(nodesProvider.notifier).clearLatencies(onlyCustom: true);

    int currentIndex = 0;
    final concurrency = ref.read(testConcurrencyProvider);
    final testMode = ref.read(testModeProvider);
    final isTurbo = testMode == TestMode.turbo;
    final testStartTime = DateTime.now();

    Future<void> runWorker() async {
      while (currentIndex < nodes.length && !_cancelTestingAll && mounted) {
        final nodeIndex = currentIndex++;
        if (nodeIndex >= nodes.length) break;
        final n = nodes[nodeIndex];

        final res = await XrayProcessService.instance.testNodeRealDelay(
          n,
          isTurbo: isTurbo,
        );
        if (_cancelTestingAll || !mounted) break;

        if (mounted) {
          ref.read(nodesProvider.notifier).updateLatency(
            n.id,
            res.latencyMs,
            countryCode: res.countryCode,
            country: res.country,
          );
          final tested = _testedCount + 1;
          String? eta;
          if (nodes.length > 50 && tested > 0 && tested < nodes.length) {
            final elapsed = DateTime.now().difference(testStartTime);
            final avgPerNode = elapsed.inMilliseconds / tested;
            final remainingMs = (avgPerNode * (nodes.length - tested)).round();
            final remSeconds = (remainingMs / 1000).round();
            final minutes = remSeconds ~/ 60;
            final seconds = remSeconds % 60;
            eta = '~${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
          }
          setState(() {
            _testingNodeIds.remove(n.id);
            _testedCount = tested;
            _testRemainingEta = eta;
          });
        }
      }
    }

    final workerCount = math.min(concurrency, nodes.length);
    final workers = List.generate(workerCount, (_) => runWorker());
    await Future.wait(workers);

    if (mounted) {
      setState(() {
        _isTestingAll = false;
        _cancelTestingAll = false;
        _testingNodeIds.clear();
        _testRemainingEta = null;
      });
      // Immediately flush tested latencies and countries to storage
      final allNodes = ref.read(nodesProvider);
      StorageService.instance.saveNodes(allNodes, immediate: true);
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

  Future<void> _deleteAllNodes(String locale) async {
    final nodes = ref.read(nodesProvider).where((n) => n.subscriptionId == null && !n.isFree).toList();
    if (nodes.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.delete_forever_rounded, color: Colors.redAccent),
            const SizedBox(width: 8),
            Text(locale == 'fa' ? 'حذف همه کانفیگ‌ها' : 'Delete All Configs'),
          ],
        ),
        content: Text(
          locale == 'fa'
              ? 'آیا از حذف تمامی ${nodes.length} کانفیگ این بخش اطمینان دارید؟'
              : 'Are you sure you want to delete all ${nodes.length} configs in this section?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(AppStrings.get('cancel', locale: locale)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(AppStrings.get('delete', locale: locale)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      ref.read(nodesProvider.notifier).clearCustomNodes();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(locale == 'fa' ? 'تمامی کانفیگ‌های این بخش حذف شدند.' : 'All section configs deleted.'),
        ),
      );
    }
  }

  Future<void> _showQrDialog(String locale) async {
    if (Platform.isAndroid) {
      final code = await QrScannerDialog.show(context, locale: locale);
      if (code != null && code.isNotEmpty && mounted) {
        final nodes = await ConfigParser.parseBatchAsync(code);
        if (nodes.isNotEmpty && mounted) {
          ref.read(nodesProvider.notifier).addNodes(nodes);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(locale == 'fa'
                  ? '${nodes.length} کانفیگ با موفقیت اضافه شد.'
                  : '${nodes.length} configuration(s) added successfully.'),
              backgroundColor: AppTheme.successColor,
            ),
          );
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(locale == 'fa'
                  ? 'کانفیگ معتبری در بارکد اسکن شده یافت نشد.'
                  : 'No valid proxy config found in QR code.'),
              backgroundColor: Colors.orangeAccent,
            ),
          );
        }
      }
      return;
    }

    final controller = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.qr_code_scanner_rounded, color: Colors.amber),
            const SizedBox(width: 8),
            Text(locale == 'fa' ? 'اسکن یا درج کد QR' : 'Scan / Enter QR Code'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              locale == 'fa'
                  ? 'لینک کانفیگ یا متن حاصل از اسکن بارکد QR را وارد کنید:'
                  : 'Paste the config link from your QR code scan or clipboard below:',
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'vless://... / vmess://... / trojan://...',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.paste_rounded),
                  tooltip: 'Paste',
                  onPressed: () async {
                    final data = await Clipboard.getData(Clipboard.kTextPlain);
                    if (data?.text != null) {
                      controller.text = data!.text!;
                    }
                  },
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(AppStrings.get('cancel', locale: locale)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final text = controller.text.trim();
              if (text.isNotEmpty) {
                final nodes = await ConfigParser.parseBatchAsync(text);
                if (nodes.isNotEmpty && mounted) {
                  ref.read(nodesProvider.notifier).addNodes(nodes);
                  Navigator.of(ctx).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('${nodes.length} configuration(s) added successfully.')),
                  );
                } else if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('No valid proxy config found in text.')),
                  );
                }
              }
            },
            child: Text(AppStrings.get('import', locale: locale)),
          ),
        ],
      ),
    );
  }

  void _showAddConfigBottomSheet(String locale) {
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
                locale == 'fa' ? 'افزودن کانفیگ جدید' : 'Add New Config',
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
                  child: const Icon(Icons.edit_note_rounded, color: AppTheme.primaryAccent),
                ),
                title: Text(locale == 'fa' ? 'افزودن دستی (Add Config)' : 'Add Config Manually'),
                subtitle: Text(
                  locale == 'fa' ? 'ساخت کانفیگ سفارشی با وارد کردن پارامترها' : 'Build custom configuration manually',
                  style: const TextStyle(fontSize: 11),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  AddConfigDialog.show(context, locale);
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
                title: Text(locale == 'fa' ? 'از کلیپ‌بورد (Import from Clipboard)' : 'Import from Clipboard'),
                subtitle: Text(
                  locale == 'fa' ? 'خواندن لینک‌های vless، vmess و trojan کپی‌شده' : 'Paste copied vless, vmess, trojan configs',
                  style: const TextStyle(fontSize: 11),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _pasteFromClipboard();
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.qr_code_scanner_rounded, color: Colors.amber),
                ),
                title: Text(locale == 'fa' ? 'اسکن بارکد (Scan QR Code)' : 'Scan QR Code'),
                subtitle: Text(
                  locale == 'fa' ? 'اسکن تصویر یا درج متن بارکد' : 'Scan QR image or enter QR link',
                  style: const TextStyle(fontSize: 11),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _showQrDialog(locale);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allNodes = ref.watch(nodesProvider);
    final nodes = allNodes.where((n) => n.subscriptionId == null && !n.isFree).toList();
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
    final outbound = ref.watch(outboundInfoProvider);
    final connState = ref.watch(connectionStatusProvider);
    final isConnected = connState == ConnectionStateEnum.connected;
    final isDesktop = MediaQuery.of(context).size.width >= 650;

    final progress = _totalToTest > 0 ? (_testedCount / _totalToTest).clamp(0.0, 1.0) : 0.0;
    final progressPercent = (progress * 100).toInt();

    final filteredNodes = nodes.where((n) {
      if (_selectedCountryCode == null) return true;
      if (_selectedCountryCode == '__timeouts__') {
        return n.hasTimedOut;
      }
      if (_selectedCountryCode == '__unknown__') {
        return n.hasValidPing && (n.countryCode == null || n.countryCode!.trim().isEmpty);
      }
      return n.hasValidPing && n.countryCode?.trim().toUpperCase() == _selectedCountryCode;
    }).toList();

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyV, control: true): _pasteFromClipboard,
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
                        AppStrings.get('configs', locale: locale),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ],
                  ),
                  actions: [
                    // Small Free Configs button
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.card_giftcard_rounded, color: Colors.orangeAccent, size: 22),
                      tooltip: locale == 'fa' ? 'کانفیگ رایگان' : 'Free Configs',
                      onPressed: () => widget.onNavigateToFreeConfigs?.call(),
                    ),
                    // Test All Ping button
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: _isTestingAll
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                value: progress > 0 ? progress : null,
                                strokeWidth: 2,
                                color: Colors.amber,
                              ),
                            )
                          : const Icon(Icons.speed_rounded, color: Colors.blueAccent),
                      tooltip: _isTestingAll
                          ? (_testRemainingEta != null
                              ? '$progressPercent% ($_testRemainingEta)'
                              : '$progressPercent% (${AppStrings.get("cancel_scan", locale: locale)})')
                          : (locale == 'fa' ? 'تست پینگ همه' : 'Test all configs'),
                      onPressed: nodes.isEmpty ? null : () => _testAllNodes(nodes),
                    ),
                    // Options Menu
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert_rounded),
                      tooltip: locale == 'fa' ? 'منو عملیات' : 'Options',
                      onSelected: (val) {
                        if (val == 'delete_dead') {
                          _deleteDeadNodes(nodes, locale);
                        } else if (val == 'delete_all') {
                          _deleteAllNodes(locale);
                        }
                      },
                      itemBuilder: (ctx) => [
                        PopupMenuItem(
                          value: 'delete_dead',
                          child: Row(
                            children: [
                              const Icon(Icons.delete_sweep_rounded, color: Colors.redAccent, size: 20),
                              const SizedBox(width: 8),
                              Text(locale == 'fa' ? 'حذف کانفیگ‌های نامعتبر' : 'Delete Dead Configs'),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'delete_all',
                          child: Row(
                            children: [
                              const Icon(Icons.delete_forever_rounded, color: Colors.redAccent, size: 20),
                              const SizedBox(width: 8),
                              Text(locale == 'fa' ? 'حذف تمامی کانفیگ‌ها' : 'Delete All Configs'),
                            ],
                          ),
                        ),
                      ],
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
                  tooltip: locale == 'fa' ? 'افزودن کانفیگ' : 'Add Config',
                  onPressed: () => _showAddConfigBottomSheet(locale),
                  child: const Icon(Icons.add, size: 28),
                )
              : null,
          body: Padding(
            padding: EdgeInsets.all(Platform.isAndroid ? 12 : 24),
            child: Column(
              children: [
                if (Platform.isAndroid)
                  const SizedBox.shrink()
                else
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isNarrow = constraints.maxWidth < 640;
                    final buttons = [
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
                                ? (_testRemainingEta != null
                                    ? '$progressPercent% ($_testRemainingEta)'
                                    : '$progressPercent% (${AppStrings.get("cancel_scan", locale: locale)})')
                                : AppStrings.get('test_all', locale: locale),
                            style: TextStyle(
                              color: _isTestingAll ? Colors.amber : null,
                              fontWeight: _isTestingAll ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          onPressed: () => _testAllNodes(nodes),
                        ),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.redAccent,
                            side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.6), width: 1.2),
                          ),
                          icon: const Icon(Icons.delete_sweep_rounded, size: 18),
                          label: Text(AppStrings.get('delete_dead_configs', locale: locale)),
                          onPressed: () => _deleteDeadNodes(nodes, locale),
                        ),
                      ],
                      FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: AppTheme.primaryAccent),
                        icon: const Icon(Icons.add),
                        label: Text(AppStrings.get('add_config', locale: locale)),
                        onPressed: () => AddConfigDialog.show(context, locale),
                      ),
                    ];

                    if (isNarrow) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            AppStrings.get('configs', locale: locale),
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: buttons,
                          ),
                        ],
                      );
                    } else {
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            AppStrings.get('configs', locale: locale),
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: buttons,
                          ),
                        ],
                      );
                    }
                  },
                ),
                if (!Platform.isAndroid) const SizedBox(height: 16),
                if (nodes.isNotEmpty)
                  CountryFilterBar(
                    nodes: nodes,
                    selectedCountryCode: _selectedCountryCode,
                    onCountrySelected: (code) => setState(() => _selectedCountryCode = code),
                    locale: locale,
                  ),
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
                      itemCount: filteredNodes.length,
                      separatorBuilder: (c, i) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final node = filteredNodes[index];
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
                          return Card(
                            margin: EdgeInsets.zero,
                            elevation: node.isActive ? 2 : 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: node.isActive
                                  ? const BorderSide(color: AppTheme.primaryAccent, width: 2.0)
                                  : BorderSide(color: Colors.white.withValues(alpha: 0.08), width: 1.0),
                            ),
                            color: node.isActive
                                ? AppTheme.primaryAccent.withValues(alpha: 0.08)
                                : Theme.of(context).cardColor,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () {
                                ref.read(connectionStatusProvider.notifier).switchNode(node.id);
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: AppTheme.primaryAccent.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            node.protocol.name.toUpperCase(),
                                            style: const TextStyle(
                                              color: AppTheme.primaryAccent,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            node.name,
                                            style: TextStyle(
                                              fontWeight: node.isActive ? FontWeight.bold : FontWeight.w600,
                                              fontSize: 13,
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
                                                SnackBar(content: Text(AppStrings.get('share_copied', locale: locale))),
                                              );
                                            } else if (val == 'delete') {
                                              ref.read(nodesProvider.notifier).removeNode(node.id);
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
                                            const PopupMenuItem(
                                              value: 'delete',
                                              child: Row(
                                                children: [
                                                  Icon(Icons.delete_outline_rounded, size: 18, color: Colors.redAccent),
                                                  SizedBox(width: 8),
                                                  Text('Delete'),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
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
                                                  style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
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
                                                  style: TextStyle(fontSize: 9, color: Colors.grey.shade400, fontWeight: FontWeight.bold),
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
                                            const SizedBox(width: 6),
                                          ],
                                          if (node.hasValidPing)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: AppTheme.successColor.withValues(alpha: 0.15),
                                                borderRadius: BorderRadius.circular(4),
                                                border: Border.all(color: AppTheme.successColor.withValues(alpha: 0.3), width: 0.8),
                                              ),
                                              child: Text(
                                                '${node.latencyMs} ms',
                                                style: const TextStyle(
                                                  color: AppTheme.successColor,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            )
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
                                                  const Icon(Icons.cloud_off_rounded, size: 10, color: AppTheme.errorColor),
                                                  const SizedBox(width: 3),
                                                  Text(
                                                    AppStrings.get('timeout', locale: locale),
                                                    style: const TextStyle(
                                                      color: AppTheme.errorColor,
                                                      fontSize: 10,
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
                          );
                        }

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
                                else ...[
                                  if (displayCountryCode != null && displayCountryCode.isNotEmpty) ...[
                                    CountryPillBadge(
                                      countryCode: displayCountryCode,
                                      country: displayCountry,
                                    ),
                                    const SizedBox(width: 6),
                                  ],
                                  if (node.hasValidPing)
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
                                ],
                                if (isDesktop) ...[
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
                                ] else ...[
                                  PopupMenuButton<String>(
                                    icon: const Icon(Icons.more_vert_rounded, size: 20),
                                    padding: EdgeInsets.zero,
                                    onSelected: (val) {
                                      if (val == 'ping') {
                                        _testNodeLatency(node);
                                      } else if (val == 'edit') {
                                        EditConfigDialog.show(context, node, locale);
                                      } else if (val == 'share') {
                                        Clipboard.setData(ClipboardData(text: node.toShareUrl()));
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text(AppStrings.get('share_copied', locale: locale))),
                                        );
                                      } else if (val == 'delete') {
                                        ref.read(nodesProvider.notifier).removeNode(node.id);
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
                                      const PopupMenuItem(
                                        value: 'delete',
                                        child: Row(
                                          children: [
                                            Icon(Icons.delete_outline_rounded, size: 18, color: Colors.redAccent),
                                            SizedBox(width: 8),
                                            Text('Delete'),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                            onTap: () {
                              ref.read(connectionStatusProvider.notifier).switchNode(node.id);
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