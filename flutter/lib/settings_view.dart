import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/l10n/translations.dart';
import 'core/theme/app_theme.dart';
import 'models/dns_settings.dart';
import 'providers/app_providers.dart';
import 'services/cdn_scanner_service.dart';
import 'services/update_service.dart';
import 'services/xray_process_service.dart';

class SettingsView extends ConsumerStatefulWidget {
  final VoidCallback? onOpenDrawer;
  const SettingsView({super.key, this.onOpenDrawer});

  @override
  ConsumerState<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends ConsumerState<SettingsView> {
  late TextEditingController _cdnRangesController;
  late TextEditingController _dnsServersController;
  late TextEditingController _httpPortController;
  late TextEditingController _socksPortController;
  CdnProvider _selectedCdnForRanges = CdnProvider.cloudflare;
  bool _initialized = false;

  // Xray Core Update State
  bool _xrayChecking = false;
  bool _xrayUpdating = false;
  double _xrayProgress = 0.0;
  UpdateInfo? _xrayInfo;
  String? _xrayStatusMsg;

  // Geo Files Update State
  bool _geoChecking = false;
  bool _geoUpdating = false;
  double _geoProgress = 0.0;
  UpdateInfo? _geoInfo;
  String? _geoStatusMsg;

  // App Update State
  bool _appChecking = false;
  bool _appUpdating = false;
  double _appProgress = 0.0;
  UpdateInfo? _appInfo;
  String? _appStatusMsg;

  // Update All State
  bool _updatingAll = false;
  String? _updateAllStatusMsg;

  Future<void> _updateAll() async {
    if (_updatingAll || _xrayUpdating || _geoUpdating || _appUpdating) return;
    final locale = ref.read(currentLocaleProvider);
    setState(() {
      _updatingAll = true;
      _updateAllStatusMsg = AppStrings.get('updating', locale: locale);
    });

    try {
      // 1. Update Geo Files
      await _updateGeoFiles();

      // 2. Check & Update Xray Core
      await _checkXrayUpdate();
      if (_xrayInfo?.hasUpdate == true && _xrayInfo?.downloadUrl != null) {
        await _updateXray();
      }

      // 3. Check App Update
      await _checkAppUpdate();

      if (mounted) {
        setState(() {
          _updatingAll = false;
          _updateAllStatusMsg = locale == 'fa'
              ? 'عملیات به‌روزرسانی همه با موفقیت انجام شد.'
              : 'All updates checked and completed.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _updatingAll = false;
          _updateAllStatusMsg = 'Error: $e';
        });
      }
    }
  }

  @override
  void dispose() {
    _cdnRangesController.dispose();
    _dnsServersController.dispose();
    _httpPortController.dispose();
    _socksPortController.dispose();
    super.dispose();
  }

  Future<void> _checkXrayUpdate() async {
    setState(() {
      _xrayChecking = true;
      _xrayStatusMsg = null;
    });
    try {
      final info = await UpdateService.instance.checkXrayUpdate();
      if (mounted) {
        setState(() {
          _xrayInfo = info;
          _xrayChecking = false;
          _xrayStatusMsg = info.hasUpdate ? 'Update available!' : 'Up to date';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _xrayChecking = false;
          _xrayStatusMsg = 'Failed to check: $e';
        });
      }
    }
  }

  Future<void> _updateXray() async {
    if (_xrayInfo?.downloadUrl == null) return;
    setState(() {
      _xrayUpdating = true;
      _xrayProgress = 0.0;
      _xrayStatusMsg = 'Downloading...';
    });
    try {
      final success = await UpdateService.instance.updateXray(
        _xrayInfo!.downloadUrl!,
        onProgress: (p) {
          if (mounted) setState(() => _xrayProgress = p);
        },
      );
      if (mounted) {
        setState(() {
          _xrayUpdating = false;
          _xrayStatusMsg = success ? 'Xray updated successfully!' : 'Update installation failed';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _xrayUpdating = false;
          _xrayStatusMsg = 'Error: $e';
        });
      }
    }
  }

  Future<void> _checkGeoUpdate() async {
    setState(() {
      _geoChecking = true;
      _geoStatusMsg = null;
    });
    try {
      final info = await UpdateService.instance.checkGeoUpdate();
      if (mounted) {
        setState(() {
          _geoInfo = info;
          _geoChecking = false;
          _geoStatusMsg = 'Latest data ready to download';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _geoChecking = false;
          _geoStatusMsg = 'Failed to check: $e';
        });
      }
    }
  }

  Future<void> _updateGeoFiles() async {
    setState(() {
      _geoUpdating = true;
      _geoProgress = 0.0;
      _geoStatusMsg = 'Downloading Geo files...';
    });
    try {
      final success = await UpdateService.instance.updateGeoFiles(
        onProgress: (p) {
          if (mounted) setState(() => _geoProgress = p);
        },
      );
      if (mounted) {
        setState(() {
          _geoUpdating = false;
          _geoStatusMsg = success ? 'GeoIP & GeoSite updated!' : 'Failed to update Geo files';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _geoUpdating = false;
          _geoStatusMsg = 'Error: $e';
        });
      }
    }
  }

  Future<void> _checkAppUpdate() async {
    setState(() {
      _appChecking = true;
      _appStatusMsg = null;
    });
    final locale = ref.read(currentLocaleProvider);
    try {
      final info = await UpdateService.instance.checkAppUpdate();
      if (mounted) {
        setState(() {
          _appInfo = info;
          _appChecking = false;
          if (info.hasUpdate) {
            _appStatusMsg = locale == 'fa'
                ? 'نسخه جدید در دسترس است: ${info.latestVersion}'
                : 'New version available: ${info.latestVersion}';
          } else {
            _appStatusMsg = AppStrings.get('up_to_date', locale: locale);
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _appChecking = false;
          _appStatusMsg = 'Failed to check: $e';
        });
      }
    }
  }

  Future<void> _downloadAppUpdate() async {
    final dlUrl = _appInfo?.downloadUrl;
    if (dlUrl == null || dlUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No download URL available for this release.')),
      );
      return;
    }
    await _downloadAppUpdateDirectly(dlUrl);
  }

  Future<void> _downloadAppUpdateDirectly(String url) async {
    if (url.trim().isEmpty) return;
    final locale = ref.read(currentLocaleProvider);
    setState(() {
      _appUpdating = true;
      _appProgress = 0.0;
      _appStatusMsg = AppStrings.get('updating', locale: locale);
    });

    try {
      final success = await UpdateService.instance.downloadAndApplyAppUpdate(
        url.trim(),
        onProgress: (phase, p) {
          if (mounted) {
            setState(() {
              _appProgress = p;
              if (phase == 'downloading') {
                _appStatusMsg = '${AppStrings.get('updating', locale: locale)} ${(p * 100).toInt()}%';
              } else if (phase == 'extracting') {
                _appStatusMsg = AppStrings.get('extracting', locale: locale);
              } else if (phase == 'applying') {
                _appStatusMsg = AppStrings.get('applying_update', locale: locale);
              }
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          _appUpdating = false;
          _appStatusMsg = success
              ? AppStrings.get('update_success', locale: locale)
              : AppStrings.get('update_failed', locale: locale);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _appUpdating = false;
          _appStatusMsg = '${AppStrings.get('update_failed', locale: locale)}: $e';
        });
      }
    }
  }

  Widget _buildInfoTooltip(String message) {
    return Tooltip(
      message: message,
      padding: const EdgeInsets.all(10),
      margin: const EdgeInsets.symmetric(horizontal: 20),
      preferBelow: true,
      textStyle: const TextStyle(color: Colors.white, fontSize: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2230),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.primaryAccent.withValues(alpha: 0.4)),
        boxShadow: const [
          BoxShadow(color: Colors.black38, blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4.0),
        child: Icon(
          Icons.info_outline_rounded,
          size: 17,
          color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
        ),
      ),
    );
  }

  Widget _buildCategoryHeader(IconData icon, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppTheme.primaryAccent),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildAndroidThemeChip({
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primaryAccent.withValues(alpha: 0.18)
              : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? AppTheme.primaryAccent : Colors.white.withValues(alpha: 0.1),
            width: isSelected ? 1.6 : 1.0,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected ? AppTheme.primaryAccent : Colors.grey,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? AppTheme.primaryAccent : Theme.of(context).colorScheme.onSurface,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAndroidModeChip({
    required String label,
    required String desc,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primaryAccent.withValues(alpha: 0.18)
              : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? AppTheme.primaryAccent : Colors.grey.withValues(alpha: 0.25),
            width: isSelected ? 1.6 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected ? AppTheme.primaryAccent : Colors.grey,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected ? AppTheme.primaryAccent : Theme.of(context).colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    desc,
                    style: TextStyle(
                      fontSize: 10,
                      color: isSelected ? AppTheme.primaryAccent.withValues(alpha: 0.8) : Colors.grey,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAndroidProxyPortsSection(String locale, int httpPort, int socksPort) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppTheme.primaryAccent.withValues(alpha: 0.25),
          width: 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.tune_rounded, size: 16, color: AppTheme.primaryAccent),
              const SizedBox(width: 6),
              Text(
                locale == 'fa' ? 'تعیین پورت‌های ورودی محلی (Proxy)' : 'Local Inbound Ports (Proxy)',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.primaryAccent),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // HTTP Port row
          Row(
            children: [
              const Icon(Icons.settings_ethernet_rounded, size: 16, color: AppTheme.primaryAccent),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppStrings.get('http_port', locale: locale),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '127.0.0.1:$httpPort (Default: 10888)',
                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 75,
                height: 32,
                child: TextField(
                  controller: _httpPortController,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  onSubmitted: (val) {
                    final p = int.tryParse(val.trim());
                    if (p != null && p > 0 && p < 65536) {
                      ref.read(httpPortProvider.notifier).setPort(p);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(locale == 'fa' ? 'پورت HTTP ذخیره شد: $p' : 'HTTP port saved: $p')),
                      );
                    }
                  },
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.check_circle_rounded, size: 20, color: AppTheme.successColor),
                tooltip: locale == 'fa' ? 'ذخیره پورت' : 'Save Port',
                onPressed: () {
                  final p = int.tryParse(_httpPortController.text.trim());
                  if (p != null && p > 0 && p < 65536) {
                    ref.read(httpPortProvider.notifier).setPort(p);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(locale == 'fa' ? 'پورت HTTP ذخیره شد: $p' : 'HTTP port saved: $p')),
                    );
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          const SizedBox(height: 8),
          // SOCKS Port row
          Row(
            children: [
              const Icon(Icons.swap_calls_rounded, size: 16, color: AppTheme.secondaryAccent),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppStrings.get('socks_port', locale: locale),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '127.0.0.1:$socksPort (Default: 10999)',
                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 75,
                height: 32,
                child: TextField(
                  controller: _socksPortController,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  onSubmitted: (val) {
                    final p = int.tryParse(val.trim());
                    if (p != null && p > 0 && p < 65536) {
                      ref.read(socksPortProvider.notifier).setPort(p);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(locale == 'fa' ? 'پورت SOCKS ذخیره شد: $p' : 'SOCKS port saved: $p')),
                      );
                    }
                  },
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.check_circle_rounded, size: 20, color: AppTheme.successColor),
                tooltip: locale == 'fa' ? 'ذخیره پورت' : 'Save Port',
                onPressed: () {
                  final p = int.tryParse(_socksPortController.text.trim());
                  if (p != null && p > 0 && p < 65536) {
                    ref.read(socksPortProvider.notifier).setPort(p);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(locale == 'fa' ? 'پورت SOCKS ذخیره شد: $p' : 'SOCKS port saved: $p')),
                    );
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAndroidTestModeSection(String locale, TestMode testMode) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.tune_rounded, color: AppTheme.primaryAccent, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  AppStrings.get('test_mode', locale: locale),
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
              _buildInfoTooltip(AppStrings.get('tooltip_test_mode', locale: locale)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildAndroidTestModeChip(
                  label: AppStrings.get('test_mode_normal', locale: locale),
                  icon: Icons.check_circle_outline_rounded,
                  iconColor: AppTheme.primaryAccent,
                  isSelected: testMode == TestMode.normal,
                  onTap: () => ref.read(testModeProvider.notifier).setMode(TestMode.normal),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildAndroidTestModeChip(
                  label: AppStrings.get('test_mode_turbo', locale: locale),
                  icon: Icons.bolt_rounded,
                  iconColor: Colors.amber,
                  isSelected: testMode == TestMode.turbo,
                  onTap: () => ref.read(testModeProvider.notifier).setMode(TestMode.turbo),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAndroidTestModeChip({
    required String label,
    required IconData icon,
    required Color iconColor,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primaryAccent.withValues(alpha: 0.18)
              : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? AppTheme.primaryAccent : Colors.grey.withValues(alpha: 0.25),
            width: isSelected ? 1.6 : 1.0,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: isSelected ? iconColor : Colors.grey),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? AppTheme.primaryAccent : Theme.of(context).colorScheme.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAndroidConcurrencySection(String locale, int testConcurrency) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.hub_rounded, color: AppTheme.secondaryAccent, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  AppStrings.get('test_concurrency', locale: locale),
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
              _buildInfoTooltip(AppStrings.get('tooltip_test_concurrency', locale: locale)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.secondaryAccent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.secondaryAccent.withValues(alpha: 0.3)),
                ),
                child: Text(
                  '$testConcurrency',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.secondaryAccent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            AppStrings.get('test_concurrency_desc', locale: locale),
            style: const TextStyle(fontSize: 10.5, color: Colors.grey),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3.0,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12.0),
            ),
            child: Slider(
              value: testConcurrency.toDouble(),
              min: 5.0,
              max: 100.0,
              divisions: 95,
              label: '$testConcurrency',
              activeColor: AppTheme.secondaryAccent,
              onChanged: (val) {
                ref.read(testConcurrencyProvider.notifier).setConcurrency(val.round());
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(currentLocaleProvider);
    final httpPort = ref.watch(httpPortProvider);
    final socksPort = ref.watch(socksPortProvider);
    final dnsSettings = ref.watch(dnsSettingsProvider);
    final cdnRanges = ref.watch(cdnRangesProvider);

    final themeMode = ref.watch(appThemeModeProvider);
    final isTun = ref.watch(isTunEnabledProvider);
    final startOnBoot = ref.watch(startOnBootProvider);
    final autoConnectOnLaunch = ref.watch(autoConnectOnLaunchProvider);
    final autoSysProxy = ref.watch(autoEnableSysProxyOnConnectProvider);
    final autoTun = ref.watch(autoEnableTunOnConnectProvider);
    final enableUdp = ref.watch(enableUdpProvider);
    final globalAllowInsecure = ref.watch(globalAllowInsecureProvider);
    final globalEnableMux = ref.watch(globalEnableMuxProvider);
    final allowLan = ref.watch(allowLanProvider);

    final testMode = ref.watch(testModeProvider);
    final testConcurrency = ref.watch(testConcurrencyProvider);

    if (!_initialized) {
      final currentCdnList = cdnRanges[_selectedCdnForRanges] ?? _selectedCdnForRanges.defaultCidrs;
      _cdnRangesController = TextEditingController(text: currentCdnList.join('\n'));
      _dnsServersController = TextEditingController(text: dnsSettings.servers.join('\n'));
      _httpPortController = TextEditingController(text: httpPort.toString());
      _socksPortController = TextEditingController(text: socksPort.toString());
      _initialized = true;
    }

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
                    AppStrings.get('settings', locale: locale),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              actions: [
                Container(
                  margin: const EdgeInsets.only(right: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.primaryAccent.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.verified_rounded, size: 12, color: AppTheme.primaryAccent),
                      const SizedBox(width: 4),
                      Text(
                        UpdateService.currentAppVersion,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primaryAccent),
                      ),
                    ],
                  ),
                ),
              ],
            )
          : null,
      body: ListView(
        padding: EdgeInsets.all(Platform.isAndroid ? 10 : 24),
        children: [
          if (!Platform.isAndroid) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  AppStrings.get('settings', locale: locale),
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.primaryAccent.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.verified_rounded, size: 14, color: AppTheme.primaryAccent),
                      const SizedBox(width: 6),
                      Text(
                        '${AppStrings.get('app_version', locale: locale)}: ${UpdateService.currentAppVersion}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primaryAccent),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],

          // 1. Appearance & Language
          _buildCategoryHeader(Icons.palette_rounded, AppStrings.get('settings_cat_appearance', locale: locale)),
          Card(
            child: Column(
              children: [
                if (Platform.isAndroid)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.brightness_6_rounded, color: AppTheme.primaryAccent, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              AppStrings.get('theme_mode', locale: locale),
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                            ),
                            const SizedBox(width: 6),
                            _buildInfoTooltip(AppStrings.get('tooltip_theme', locale: locale)),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _buildAndroidThemeChip(
                                label: AppStrings.get('theme_dark', locale: locale),
                                icon: Icons.dark_mode_rounded,
                                isSelected: themeMode == ThemeMode.dark,
                                onTap: () => ref.read(appThemeModeProvider.notifier).setTheme(ThemeMode.dark),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildAndroidThemeChip(
                                label: AppStrings.get('theme_light', locale: locale),
                                icon: Icons.light_mode_rounded,
                                isSelected: themeMode == ThemeMode.light,
                                onTap: () => ref.read(appThemeModeProvider.notifier).setTheme(ThemeMode.light),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildAndroidThemeChip(
                                label: AppStrings.get('theme_system', locale: locale),
                                icon: Icons.brightness_auto_rounded,
                                isSelected: themeMode == ThemeMode.system,
                                onTap: () => ref.read(appThemeModeProvider.notifier).setTheme(ThemeMode.system),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  )
                else
                  ListTile(
                    leading: const Icon(Icons.brightness_6_rounded, color: AppTheme.primaryAccent),
                    title: Row(
                      children: [
                        Text(AppStrings.get('theme_mode', locale: locale)),
                        const SizedBox(width: 6),
                        _buildInfoTooltip(AppStrings.get('tooltip_theme', locale: locale)),
                      ],
                    ),
                    trailing: SegmentedButton<ThemeMode>(
                      segments: [
                        ButtonSegment(
                          value: ThemeMode.dark,
                          label: Text(AppStrings.get('theme_dark', locale: locale), style: const TextStyle(fontSize: 11)),
                          icon: const Icon(Icons.dark_mode_rounded, size: 16),
                        ),
                        ButtonSegment(
                          value: ThemeMode.light,
                          label: Text(AppStrings.get('theme_light', locale: locale), style: const TextStyle(fontSize: 11)),
                          icon: const Icon(Icons.light_mode_rounded, size: 16),
                        ),
                        ButtonSegment(
                          value: ThemeMode.system,
                          label: Text(AppStrings.get('theme_system', locale: locale), style: const TextStyle(fontSize: 11)),
                          icon: const Icon(Icons.brightness_auto_rounded, size: 16),
                        ),
                      ],
                      selected: {themeMode},
                      onSelectionChanged: (Set<ThemeMode> newSelection) {
                        ref.read(appThemeModeProvider.notifier).setTheme(newSelection.first);
                      },
                    ),
                  ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.language_rounded, color: AppTheme.secondaryAccent),
                  title: Row(
                    children: [
                      const Text('Language / زبان'),
                      const SizedBox(width: 6),
                      _buildInfoTooltip(AppStrings.get('tooltip_language', locale: locale)),
                    ],
                  ),
                  subtitle: Text(
                    locale == 'fa' ? 'فارسی' : 'English',
                    style: TextStyle(fontSize: Platform.isAndroid ? 11 : 12, color: Colors.grey),
                  ),
                  trailing: DropdownButton<String>(
                    value: locale,
                    underline: const SizedBox(),
                    items: const [
                      DropdownMenuItem(value: 'en', child: Text('English')),
                      DropdownMenuItem(value: 'fa', child: Text('فارسی')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        ref.read(currentLocaleProvider.notifier).state = val;
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 2. Startup & Automation
          _buildCategoryHeader(Icons.power_settings_new_rounded, AppStrings.get('settings_cat_startup', locale: locale)),
          Card(
            child: Column(
              children: [
                if (!Platform.isAndroid) ...[
                  SwitchListTile(
                    secondary: const Icon(Icons.power_settings_new_rounded, color: AppTheme.primaryAccent),
                    title: Row(
                      children: [
                        Text(AppStrings.get('start_on_boot', locale: locale)),
                        const SizedBox(width: 6),
                        _buildInfoTooltip(AppStrings.get('tooltip_start_on_boot', locale: locale)),
                      ],
                    ),
                    subtitle: Text(AppStrings.get('start_on_boot_desc', locale: locale), style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    value: startOnBoot,
                    onChanged: (val) {
                      ref.read(startOnBootProvider.notifier).toggle(val);
                    },
                  ),
                  const Divider(height: 1),
                ],
                SwitchListTile(
                  secondary: const Icon(Icons.flash_on_rounded, color: Colors.amber),
                  title: Row(
                    children: [
                      Flexible(
                        child: Text(
                          AppStrings.get('auto_connect_on_launch', locale: locale),
                          style: TextStyle(fontSize: Platform.isAndroid ? 13 : 14),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      _buildInfoTooltip(AppStrings.get('tooltip_auto_connect', locale: locale)),
                    ],
                  ),
                  subtitle: Text(
                    AppStrings.get('auto_connect_on_launch_desc', locale: locale),
                    style: TextStyle(fontSize: Platform.isAndroid ? 10.5 : 12, color: Colors.grey),
                    maxLines: Platform.isAndroid ? 2 : null,
                    overflow: Platform.isAndroid ? TextOverflow.ellipsis : null,
                  ),
                  value: autoConnectOnLaunch,
                  onChanged: (val) {
                    ref.read(autoConnectOnLaunchProvider.notifier).toggle(val);
                  },
                ),
                if (!Platform.isAndroid) ...[
                  const Divider(height: 1),
                  SwitchListTile(
                    secondary: const Icon(Icons.shield_outlined, color: AppTheme.successColor),
                    title: Row(
                      children: [
                        Text(AppStrings.get('auto_sysproxy_on_connect', locale: locale)),
                        const SizedBox(width: 6),
                        _buildInfoTooltip(AppStrings.get('tooltip_auto_sysproxy', locale: locale)),
                      ],
                    ),
                    subtitle: Text(AppStrings.get('auto_sysproxy_on_connect_desc', locale: locale), style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    value: autoSysProxy,
                    onChanged: (val) {
                      ref.read(autoEnableSysProxyOnConnectProvider.notifier).toggle(val);
                    },
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    secondary: const Icon(Icons.vpn_lock_rounded, color: AppTheme.primaryAccent),
                    title: Row(
                      children: [
                        Text(AppStrings.get('auto_tun_on_connect', locale: locale)),
                        const SizedBox(width: 6),
                        _buildInfoTooltip(AppStrings.get('tooltip_auto_tun', locale: locale)),
                      ],
                    ),
                    subtitle: Text(AppStrings.get('auto_tun_on_connect_desc', locale: locale), style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    value: autoTun,
                    onChanged: (val) {
                      if (val && !XrayProcessService.instance.isRunningAsAdmin()) {
                        showDialog(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            backgroundColor: Theme.of(context).cardColor,
                            title: Text(AppStrings.get('tun_admin_required_title', locale: locale)),
                            content: Text(AppStrings.get('tun_admin_required_desc', locale: locale)),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx), child: Text(AppStrings.get('cancel', locale: locale))),
                              ElevatedButton(
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  XrayProcessService.instance.restartAsAdmin();
                                },
                                child: Text(AppStrings.get('restart_as_admin', locale: locale)),
                              ),
                            ],
                          ),
                        );
                        return;
                      }
                      ref.read(autoEnableTunOnConnectProvider.notifier).toggle(val);
                    },
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 3. Core & Network Settings
          _buildCategoryHeader(Icons.router_rounded, AppStrings.get('settings_cat_core_net', locale: locale)),
          Card(
            child: Column(
              children: [
                if (Platform.isAndroid) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.hub_rounded, color: AppTheme.primaryAccent, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              locale == 'fa' ? 'حالت اتصال' : 'Connection Mode',
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _buildAndroidModeChip(
                                label: locale == 'fa' ? 'وی‌پی‌ان (TUN)' : 'TUN (VPN)',
                                desc: locale == 'fa' ? 'کل دستگاه' : 'Whole Device',
                                icon: Icons.vpn_lock_rounded,
                                isSelected: isTun,
                                onTap: () {
                                  ref.read(isTunEnabledProvider.notifier).toggle(true);
                                  ref.read(autoEnableTunOnConnectProvider.notifier).toggle(true);
                                  if (ref.read(connectionStatusProvider) == ConnectionStateEnum.connected) {
                                    ref.read(connectionStatusProvider.notifier).reconnectWithUpdatedSettings();
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildAndroidModeChip(
                                label: locale == 'fa' ? 'پروکسی (Proxy)' : 'Proxy Mode',
                                desc: locale == 'fa' ? 'پورت محلی' : 'Local Inbound',
                                icon: Icons.settings_ethernet_rounded,
                                isSelected: !isTun,
                                onTap: () {
                                  ref.read(isTunEnabledProvider.notifier).toggle(false);
                                  ref.read(autoEnableTunOnConnectProvider.notifier).toggle(false);
                                  if (ref.read(connectionStatusProvider) == ConnectionStateEnum.connected) {
                                    ref.read(connectionStatusProvider.notifier).reconnectWithUpdatedSettings();
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                        if (!isTun) ...[
                          const SizedBox(height: 10),
                          _buildAndroidProxyPortsSection(locale, httpPort, socksPort),
                        ],
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                ],
                SwitchListTile(
                  secondary: const Icon(Icons.compare_arrows_rounded, color: Colors.tealAccent),
                  title: Row(
                    children: [
                      Flexible(
                        child: Text(
                          AppStrings.get('enable_udp', locale: locale),
                          style: TextStyle(fontSize: Platform.isAndroid ? 13 : 14),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      _buildInfoTooltip(AppStrings.get('tooltip_enable_udp', locale: locale)),
                    ],
                  ),
                  subtitle: Text(
                    AppStrings.get('enable_udp_desc', locale: locale),
                    style: TextStyle(fontSize: Platform.isAndroid ? 10.5 : 12, color: Colors.grey),
                    maxLines: Platform.isAndroid ? 2 : null,
                    overflow: Platform.isAndroid ? TextOverflow.ellipsis : null,
                  ),
                  value: enableUdp,
                  onChanged: (val) {
                    ref.read(enableUdpProvider.notifier).toggle(val);
                  },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.security_update_warning_rounded, color: Colors.orangeAccent),
                  title: Row(
                    children: [
                      Flexible(
                        child: Text(
                          AppStrings.get('global_allow_insecure', locale: locale),
                          style: TextStyle(fontSize: Platform.isAndroid ? 13 : 14),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      _buildInfoTooltip(AppStrings.get('tooltip_allow_insecure', locale: locale)),
                    ],
                  ),
                  subtitle: Text(
                    AppStrings.get('global_allow_insecure_desc', locale: locale),
                    style: TextStyle(fontSize: Platform.isAndroid ? 10.5 : 12, color: Colors.grey),
                    maxLines: Platform.isAndroid ? 2 : null,
                    overflow: Platform.isAndroid ? TextOverflow.ellipsis : null,
                  ),
                  value: globalAllowInsecure,
                  onChanged: (val) {
                    ref.read(globalAllowInsecureProvider.notifier).toggle(val);
                    if (ref.read(connectionStatusProvider) == ConnectionStateEnum.connected) {
                      ref.read(connectionStatusProvider.notifier).reconnectWithUpdatedSettings();
                    }
                  },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.alt_route_rounded, color: Colors.cyanAccent),
                  title: Row(
                    children: [
                      Flexible(
                        child: Text(
                          AppStrings.get('global_enable_mux', locale: locale),
                          style: TextStyle(fontSize: Platform.isAndroid ? 13 : 14),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      _buildInfoTooltip(AppStrings.get('tooltip_enable_mux', locale: locale)),
                    ],
                  ),
                  subtitle: Text(
                    AppStrings.get('global_enable_mux_desc', locale: locale),
                    style: TextStyle(fontSize: Platform.isAndroid ? 10.5 : 12, color: Colors.grey),
                    maxLines: Platform.isAndroid ? 2 : null,
                    overflow: Platform.isAndroid ? TextOverflow.ellipsis : null,
                  ),
                  value: globalEnableMux,
                  onChanged: (val) {
                    ref.read(globalEnableMuxProvider.notifier).toggle(val);
                    if (ref.read(connectionStatusProvider) == ConnectionStateEnum.connected) {
                      ref.read(connectionStatusProvider.notifier).reconnectWithUpdatedSettings();
                    }
                  },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.lan_rounded, color: Colors.lightGreenAccent),
                  title: Row(
                    children: [
                      Flexible(
                        child: Text(
                          AppStrings.get('allow_lan', locale: locale),
                          style: TextStyle(fontSize: Platform.isAndroid ? 13 : 14),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      _buildInfoTooltip(AppStrings.get('tooltip_allow_lan', locale: locale)),
                    ],
                  ),
                  subtitle: Text(
                    AppStrings.get('allow_lan_desc', locale: locale),
                    style: TextStyle(fontSize: Platform.isAndroid ? 10.5 : 12, color: Colors.grey),
                    maxLines: Platform.isAndroid ? 2 : null,
                    overflow: Platform.isAndroid ? TextOverflow.ellipsis : null,
                  ),
                  value: allowLan,
                  onChanged: (val) {
                    ref.read(allowLanProvider.notifier).toggle(val);
                    if (ref.read(connectionStatusProvider) == ConnectionStateEnum.connected) {
                      ref.read(connectionStatusProvider.notifier).reconnectWithUpdatedSettings();
                    }
                  },
                ),
                if (!Platform.isAndroid) ...[
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.settings_ethernet_rounded, color: AppTheme.primaryAccent),
                    title: Row(
                      children: [
                        Text(AppStrings.get('http_port', locale: locale)),
                        const SizedBox(width: 6),
                        _buildInfoTooltip(AppStrings.get('tooltip_http_port', locale: locale)),
                      ],
                    ),
                    subtitle: Text(
                      'Current: $httpPort  •  (Default: 10888)',
                      style: TextStyle(fontSize: Platform.isAndroid ? 11 : 12, color: Colors.grey),
                    ),
                    trailing: SizedBox(
                      width: 140,
                      child: TextField(
                        controller: _httpPortController,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.check_rounded, size: 18, color: AppTheme.successColor),
                            tooltip: "Save port",
                            onPressed: () {
                              final p = int.tryParse(_httpPortController.text.trim());
                              if (p != null && p > 0 && p < 65536) {
                                ref.read(httpPortProvider.notifier).setPort(p);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('HTTP port updated to $p')),
                                );
                              }
                            },
                          ),
                        ),
                        onSubmitted: (val) {
                          final p = int.tryParse(val.trim());
                          if (p != null && p > 0 && p < 65536) {
                            ref.read(httpPortProvider.notifier).setPort(p);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('HTTP port updated to $p')),
                            );
                          }
                        },
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.swap_calls_rounded, color: AppTheme.secondaryAccent),
                    title: Row(
                      children: [
                        Text(AppStrings.get('socks_port', locale: locale)),
                        const SizedBox(width: 6),
                        _buildInfoTooltip(AppStrings.get('tooltip_socks_port', locale: locale)),
                      ],
                    ),
                    subtitle: Text(
                      'Current: $socksPort  •  (Default: 10999)',
                      style: TextStyle(fontSize: Platform.isAndroid ? 11 : 12, color: Colors.grey),
                    ),
                    trailing: SizedBox(
                      width: 140,
                      child: TextField(
                        controller: _socksPortController,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.check_rounded, size: 18, color: AppTheme.successColor),
                            tooltip: "Save port",
                            onPressed: () {
                              final p = int.tryParse(_socksPortController.text.trim());
                              if (p != null && p > 0 && p < 65536) {
                                ref.read(socksPortProvider.notifier).setPort(p);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('SOCKS port updated to $p')),
                                );
                              }
                            },
                          ),
                        ),
                        onSubmitted: (val) {
                          final p = int.tryParse(val.trim());
                          if (p != null && p > 0 && p < 65536) {
                            ref.read(socksPortProvider.notifier).setPort(p);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('SOCKS port updated to $p')),
                            );
                          }
                        },
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),

          // DNS Settings Card (Inside Core & Network)
          Card(
            clipBehavior: Clip.antiAlias,
            child: ExpansionTile(
              initiallyExpanded: false,
              leading: const Icon(Icons.dns_rounded, color: AppTheme.primaryAccent),
              title: Row(
                children: [
                  Text(
                    AppStrings.get('dns_settings_title', locale: locale),
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 6),
                  _buildInfoTooltip(AppStrings.get('tooltip_dns_settings', locale: locale)),
                ],
              ),
              subtitle: Text(
                '${dnsSettings.servers.length} servers configured (${dnsSettings.presetId.toUpperCase()})  •  Tap to view / edit',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        AppStrings.get('dns_settings_desc', locale: locale),
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: DnsSettings.presets.map((preset) {
                          final isSelected = dnsSettings.presetId == preset.id;
                          return ChoiceChip(
                            label: Text(preset.name),
                            selected: isSelected,
                            selectedColor: AppTheme.primaryAccent.withValues(alpha: 0.2),
                            onSelected: (selected) {
                              if (selected) {
                                ref.read(dnsSettingsProvider.notifier).setPreset(preset.id);
                                if (preset.id != 'custom') {
                                  _dnsServersController.text = preset.servers.join('\n');
                                }
                              }
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _dnsServersController,
                        maxLines: 4,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                        decoration: InputDecoration(
                          hintText: AppStrings.get('custom_dns_hint', locale: locale),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          filled: true,
                          fillColor: Theme.of(context).cardColor,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryAccent,
                              foregroundColor: Colors.white,
                            ),
                            icon: const Icon(Icons.save_rounded, size: 16),
                            label: Text(AppStrings.get('save_dns', locale: locale)),
                            onPressed: () {
                              final servers = _dnsServersController.text
                                  .split(RegExp(r'[\n,]'))
                                  .map((s) => s.trim())
                                  .where((s) => s.isNotEmpty)
                                  .toList();
                              if (servers.isNotEmpty) {
                                ref.read(dnsSettingsProvider.notifier).updateCustomServers(servers);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(AppStrings.get('dns_saved', locale: locale))),
                                );
                              }
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 4. Config Testing & Concurrency
          _buildCategoryHeader(Icons.speed_rounded, AppStrings.get('settings_cat_testing', locale: locale)),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Column(
                children: [
                  if (Platform.isAndroid) ...[
                    _buildAndroidTestModeSection(locale, testMode),
                    const Divider(height: 1),
                    _buildAndroidConcurrencySection(locale, testConcurrency),
                  ] else ...[
                    ListTile(
                      leading: const Icon(Icons.tune_rounded, color: AppTheme.primaryAccent),
                      title: Row(
                        children: [
                          Text(AppStrings.get('test_mode', locale: locale)),
                          const SizedBox(width: 6),
                          _buildInfoTooltip(AppStrings.get('tooltip_test_mode', locale: locale)),
                        ],
                      ),
                      subtitle: Text(
                        AppStrings.get('test_mode_desc', locale: locale),
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      trailing: SegmentedButton<TestMode>(
                        segments: [
                          ButtonSegment(
                            value: TestMode.normal,
                            label: Text(AppStrings.get('test_mode_normal', locale: locale), style: const TextStyle(fontSize: 11)),
                            icon: const Icon(Icons.check_circle_outline_rounded, size: 16),
                          ),
                          ButtonSegment(
                            value: TestMode.turbo,
                            label: Text(AppStrings.get('test_mode_turbo', locale: locale), style: const TextStyle(fontSize: 11)),
                            icon: const Icon(Icons.bolt_rounded, size: 16, color: Colors.amber),
                          ),
                        ],
                        selected: {testMode},
                        onSelectionChanged: (Set<TestMode> newSelection) {
                          ref.read(testModeProvider.notifier).setMode(newSelection.first);
                        },
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.hub_rounded, color: AppTheme.secondaryAccent),
                      title: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(AppStrings.get('test_concurrency', locale: locale)),
                          const SizedBox(width: 6),
                          _buildInfoTooltip(AppStrings.get('tooltip_test_concurrency', locale: locale)),
                        ],
                      ),
                      subtitle: Text(
                        AppStrings.get('test_concurrency_desc', locale: locale),
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 130,
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 3.0,
                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
                                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12.0),
                              ),
                              child: Slider(
                                value: testConcurrency.toDouble(),
                                min: 5.0,
                                max: 100.0,
                                divisions: 95,
                                label: '$testConcurrency',
                                activeColor: AppTheme.secondaryAccent,
                                onChanged: (val) {
                                  ref.read(testConcurrencyProvider.notifier).setConcurrency(val.round());
                                },
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppTheme.secondaryAccent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppTheme.secondaryAccent.withValues(alpha: 0.3)),
                            ),
                            child: Text(
                              '$testConcurrency',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.secondaryAccent,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // 5. CDN IP Ranges Card
          _buildCategoryHeader(Icons.cell_tower_rounded, AppStrings.get('settings_cat_cdn', locale: locale)),
          Card(
            clipBehavior: Clip.antiAlias,
            child: ExpansionTile(
              initiallyExpanded: false,
              leading: const Icon(Icons.network_ping_rounded, color: AppTheme.secondaryAccent),
              title: Row(
                children: [
                  Text(
                    AppStrings.get('cdn_ranges_title', locale: locale),
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 6),
                  _buildInfoTooltip(AppStrings.get('tooltip_cdn_ranges', locale: locale)),
                ],
              ),
              subtitle: Text(
                '${cdnRanges[_selectedCdnForRanges]?.length ?? 0} CIDR ranges for ${_selectedCdnForRanges.displayName}  •  Tap to view / edit',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        AppStrings.get('cdn_ranges_desc', locale: locale),
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: CdnProvider.values.map((cdn) {
                          final isSelected = _selectedCdnForRanges == cdn;
                          return ChoiceChip(
                            label: Text(cdn.displayName),
                            selected: isSelected,
                            selectedColor: AppTheme.secondaryAccent.withValues(alpha: 0.2),
                            onSelected: (selected) {
                              if (selected) {
                                setState(() {
                                  _selectedCdnForRanges = cdn;
                                  final list = ref.read(cdnRangesProvider)[cdn] ?? cdn.defaultCidrs;
                                  _cdnRangesController.text = list.join('\n');
                                });
                              }
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _cdnRangesController,
                        maxLines: 8,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                        decoration: InputDecoration(
                          hintText: AppStrings.get('cf_ranges_hint', locale: locale),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          filled: true,
                          fillColor: Theme.of(context).cardColor,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Platform.isAndroid
                          ? Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              alignment: WrapAlignment.end,
                              children: [
                                OutlinedButton.icon(
                                  icon: const Icon(Icons.restore_rounded, size: 16),
                                  label: Text(AppStrings.get('reset_default', locale: locale), style: const TextStyle(fontSize: 12)),
                                  onPressed: () {
                                    ref.read(cdnRangesProvider.notifier).resetToDefault(_selectedCdnForRanges);
                                    setState(() {
                                      _cdnRangesController.text = _selectedCdnForRanges.defaultCidrs.join('\n');
                                    });
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(AppStrings.get('ranges_reset', locale: locale))),
                                    );
                                  },
                                ),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.primaryAccent,
                                    foregroundColor: Colors.white,
                                  ),
                                  icon: const Icon(Icons.save_rounded, size: 16),
                                  label: Text(AppStrings.get('save_ranges', locale: locale), style: const TextStyle(fontSize: 12)),
                                  onPressed: () {
                                    final lines = _cdnRangesController.text
                                        .split('\n')
                                        .map((l) => l.trim())
                                        .where((l) => l.isNotEmpty && !l.startsWith('#'))
                                        .toList();
                                    ref.read(cdnRangesProvider.notifier).updateRanges(_selectedCdnForRanges, lines);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(AppStrings.get('ranges_saved', locale: locale))),
                                    );
                                  },
                                ),
                              ],
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                OutlinedButton.icon(
                                  icon: const Icon(Icons.restore_rounded, size: 16),
                                  label: Text(AppStrings.get('reset_default', locale: locale)),
                                  onPressed: () {
                                    ref.read(cdnRangesProvider.notifier).resetToDefault(_selectedCdnForRanges);
                                    setState(() {
                                      _cdnRangesController.text = _selectedCdnForRanges.defaultCidrs.join('\n');
                                    });
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(AppStrings.get('ranges_reset', locale: locale))),
                                    );
                                  },
                                ),
                                const SizedBox(width: 12),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.primaryAccent,
                                    foregroundColor: Colors.white,
                                  ),
                                  icon: const Icon(Icons.save_rounded, size: 16),
                                  label: Text(AppStrings.get('save_ranges', locale: locale)),
                                  onPressed: () {
                                    final lines = _cdnRangesController.text
                                        .split('\n')
                                        .map((l) => l.trim())
                                        .where((l) => l.isNotEmpty && !l.startsWith('#'))
                                        .toList();
                                    ref.read(cdnRangesProvider.notifier).updateRanges(_selectedCdnForRanges, lines);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(AppStrings.get('ranges_saved', locale: locale))),
                                    );
                                  },
                                ),
                              ],
                            ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 6. Updates Center (Accordion with Update All)
          _buildCategoryHeader(Icons.system_update_rounded, AppStrings.get('settings_cat_updates', locale: locale)),
          Card(
            clipBehavior: Clip.antiAlias,
            child: ExpansionTile(
              initiallyExpanded: false,
              leading: const Icon(Icons.system_update_rounded, color: AppTheme.primaryAccent),
              title: Row(
                children: [
                  Text(
                    AppStrings.get('updates', locale: locale),
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 6),
                  _buildInfoTooltip(AppStrings.get('tooltip_updates', locale: locale)),
                ],
              ),
              subtitle: Text(
                _updateAllStatusMsg ?? AppStrings.get('updates_desc', locale: locale),
                style: TextStyle(
                  fontSize: 12,
                  color: _updateAllStatusMsg != null ? AppTheme.successColor : Colors.grey,
                ),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Platform.isAndroid
                      ? IconButton(
                          tooltip: _updatingAll
                              ? AppStrings.get('updating', locale: locale)
                              : AppStrings.get('update_all', locale: locale),
                          icon: _updatingAll
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryAccent),
                                )
                              : const Icon(Icons.autorenew_rounded, color: AppTheme.primaryAccent),
                          onPressed: _updatingAll ? null : _updateAll,
                        )
                      : FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.primaryAccent,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          icon: _updatingAll
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.autorenew_rounded, size: 16),
                          label: Text(
                            _updatingAll
                                ? AppStrings.get('updating', locale: locale)
                                : AppStrings.get('update_all', locale: locale),
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                          onPressed: _updatingAll ? null : _updateAll,
                        ),
                  const SizedBox(width: 8),
                  const Icon(Icons.expand_more_rounded),
                ],
              ),
              children: [
                if (_updatingAll) ...[
                  const LinearProgressIndicator(),
                  const SizedBox(height: 8),
                ],
                const Divider(height: 1),
                // 6.1 Xray Core Update
                ListTile(
                  leading: const Icon(Icons.dns_rounded, color: AppTheme.primaryAccent),
                  title: Text(AppStrings.get('xray_core_update', locale: locale)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _xrayInfo != null
                            ? '${AppStrings.get('current_version', locale: locale)}: ${_xrayInfo!.currentVersion}  •  ${AppStrings.get('latest_version', locale: locale)}: ${_xrayInfo!.latestVersion}'
                            : 'Official GitHub XTLS/Xray-core',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      if (_xrayStatusMsg != null)
                        Text(
                          _xrayStatusMsg!,
                          style: TextStyle(
                            fontSize: 11,
                            color: _xrayStatusMsg!.contains('success') || _xrayStatusMsg!.contains('Up to date')
                                ? AppTheme.successColor
                                : Colors.amber,
                          ),
                        ),
                      if (_xrayUpdating) ...[
                        const SizedBox(height: 6),
                        LinearProgressIndicator(value: _xrayProgress > 0 ? _xrayProgress : null),
                      ],
                    ],
                  ),
                  trailing: Platform.isAndroid
                      ? (_xrayInfo?.hasUpdate == true && !_xrayUpdating
                          ? IconButton(
                              tooltip: AppStrings.get('update_now', locale: locale),
                              icon: const Icon(Icons.file_download_rounded, color: AppTheme.successColor),
                              onPressed: _updateXray,
                            )
                          : IconButton(
                              tooltip: AppStrings.get('check_update', locale: locale),
                              icon: _xrayChecking
                                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.refresh_rounded),
                              onPressed: _xrayChecking || _xrayUpdating ? null : _checkXrayUpdate,
                            ))
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_xrayInfo?.hasUpdate == true && !_xrayUpdating)
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.successColor,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                ),
                                icon: const Icon(Icons.file_download_rounded, size: 16),
                                label: Text(AppStrings.get('update_now', locale: locale), style: const TextStyle(fontSize: 11)),
                                onPressed: _updateXray,
                              )
                            else
                              OutlinedButton.icon(
                                icon: _xrayChecking
                                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                    : const Icon(Icons.refresh_rounded, size: 16),
                                label: Text(
                                  _xrayChecking ? AppStrings.get('checking', locale: locale) : AppStrings.get('check_update', locale: locale),
                                  style: const TextStyle(fontSize: 11),
                                ),
                                onPressed: _xrayChecking || _xrayUpdating ? null : _checkXrayUpdate,
                              ),
                          ],
                        ),
                ),
                const Divider(height: 1),

                // 6.2 Geo Files Update
                ListTile(
                  leading: const Icon(Icons.public_rounded, color: AppTheme.secondaryAccent),
                  title: Text(AppStrings.get('geo_files_update', locale: locale)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _geoInfo != null
                            ? '${AppStrings.get('current_version', locale: locale)}: ${_geoInfo!.currentVersion}  •  ${AppStrings.get('latest_version', locale: locale)}: ${_geoInfo!.latestVersion}'
                            : 'Loyalsoldier/v2ray-rules-dat (geoip.dat & geosite.dat)',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      if (_geoStatusMsg != null)
                        Text(
                          _geoStatusMsg!,
                          style: TextStyle(
                            fontSize: 11,
                            color: _geoStatusMsg!.contains('updated') ? AppTheme.successColor : Colors.amber,
                          ),
                        ),
                      if (_geoUpdating) ...[
                        const SizedBox(height: 6),
                        LinearProgressIndicator(value: _geoProgress > 0 ? _geoProgress : null),
                      ],
                    ],
                  ),
                  trailing: Platform.isAndroid
                      ? (_geoInfo != null && !_geoUpdating
                          ? IconButton(
                              tooltip: AppStrings.get('update_now', locale: locale),
                              icon: const Icon(Icons.download_rounded, color: AppTheme.primaryAccent),
                              onPressed: _updateGeoFiles,
                            )
                          : IconButton(
                              tooltip: AppStrings.get('check_update', locale: locale),
                              icon: _geoChecking
                                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.cloud_download_rounded),
                              onPressed: _geoChecking || _geoUpdating ? null : _checkGeoUpdate,
                            ))
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_geoInfo != null && !_geoUpdating)
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.primaryAccent,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                ),
                                icon: const Icon(Icons.download_rounded, size: 16),
                                label: Text(AppStrings.get('update_now', locale: locale), style: const TextStyle(fontSize: 11)),
                                onPressed: _updateGeoFiles,
                              )
                            else
                              OutlinedButton.icon(
                                icon: _geoChecking
                                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                    : const Icon(Icons.cloud_download_rounded, size: 16),
                                label: Text(
                                  _geoChecking ? AppStrings.get('checking', locale: locale) : AppStrings.get('check_update', locale: locale),
                                  style: const TextStyle(fontSize: 11),
                                ),
                                onPressed: _geoChecking || _geoUpdating ? null : _checkGeoUpdate,
                              ),
                          ],
                        ),
                ),
                const Divider(height: 1),

                // 6.3 App Update
                ListTile(
                  leading: const Icon(Icons.system_update_rounded, color: Colors.tealAccent),
                  title: Text(AppStrings.get('app_update', locale: locale)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${AppStrings.get('current_version', locale: locale)}: ${UpdateService.currentAppVersion}${_appInfo != null ? ' • ${AppStrings.get('latest_version', locale: locale)}: ${_appInfo!.latestVersion}' : ''}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      if (_appStatusMsg != null)
                        Text(
                          _appStatusMsg!,
                          style: TextStyle(
                            fontSize: 11,
                            color: _appStatusMsg!.contains('up to date') || _appStatusMsg!.contains('به‌روز است') || _appStatusMsg!.contains('موفقیت')
                                ? AppTheme.successColor
                                : Colors.amber,
                          ),
                        ),
                      if (_appUpdating) ...[
                        const SizedBox(height: 6),
                        LinearProgressIndicator(value: _appProgress > 0 ? _appProgress : null),
                      ],
                    ],
                  ),
                  trailing: Platform.isAndroid
                      ? (_appInfo?.hasUpdate == true && !_appUpdating
                          ? IconButton(
                              tooltip: AppStrings.get('update_now', locale: locale),
                              icon: const Icon(Icons.downloading_rounded, color: AppTheme.successColor),
                              onPressed: _downloadAppUpdate,
                            )
                          : IconButton(
                              tooltip: AppStrings.get('check_update', locale: locale),
                              icon: _appChecking
                                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.refresh_rounded),
                              onPressed: _appChecking || _appUpdating ? null : _checkAppUpdate,
                            ))
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_appInfo?.hasUpdate == true && !_appUpdating)
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.successColor,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                ),
                                icon: const Icon(Icons.downloading_rounded, size: 16),
                                label: Text(
                                  AppStrings.get('update_now', locale: locale),
                                  style: const TextStyle(fontSize: 11),
                                ),
                                onPressed: _downloadAppUpdate,
                              )
                            else
                              OutlinedButton.icon(
                                icon: _appChecking
                                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                    : const Icon(Icons.refresh_rounded, size: 16),
                                label: Text(
                                  _appChecking ? AppStrings.get('checking', locale: locale) : AppStrings.get('check_update', locale: locale),
                                  style: const TextStyle(fontSize: 11),
                                ),
                                onPressed: _appChecking || _appUpdating ? null : _checkAppUpdate,
                              ),
                          ],
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
