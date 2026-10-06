import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/l10n/translations.dart';
import 'core/theme/app_theme.dart';
import 'providers/app_providers.dart';
import 'services/update_service.dart';
import 'services/xray_process_service.dart';

class SettingsView extends ConsumerStatefulWidget {
  const SettingsView({super.key});

  @override
  ConsumerState<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends ConsumerState<SettingsView> {
  late TextEditingController _cfRangesController;
  late TextEditingController _httpPortController;
  late TextEditingController _socksPortController;
  late TextEditingController _appTestUrlController;
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
  String? _downloadedAppPath;

  @override
  void initState() {
    super.initState();
    _appTestUrlController = TextEditingController(text: UpdateService.defaultAppTestUrl);
  }

  @override
  void dispose() {
    _cfRangesController.dispose();
    _httpPortController.dispose();
    _socksPortController.dispose();
    _appTestUrlController.dispose();
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
    try {
      final customUrl = _appTestUrlController.text.trim().isNotEmpty ? _appTestUrlController.text.trim() : null;
      final info = await UpdateService.instance.checkAppUpdate(customUrl: customUrl);
      if (mounted) {
        setState(() {
          _appInfo = info;
          _appChecking = false;
          _appStatusMsg = info.hasUpdate ? 'New version available: ${info.latestVersion}' : 'Application is up to date';
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

    final locale = ref.read(currentLocaleProvider);
    setState(() {
      _appUpdating = true;
      _appProgress = 0.0;
      _appStatusMsg = AppStrings.get('updating', locale: locale);
    });

    try {
      final success = await UpdateService.instance.downloadAndApplyAppUpdate(
        dlUrl,
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

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(currentLocaleProvider);
    final httpPort = ref.watch(httpPortProvider);
    final socksPort = ref.watch(socksPortProvider);
    final cfRanges = ref.watch(cfRangesProvider);

    final themeMode = ref.watch(appThemeModeProvider);
    final startOnBoot = ref.watch(startOnBootProvider);
    final autoConnectOnLaunch = ref.watch(autoConnectOnLaunchProvider);
    final autoSysProxy = ref.watch(autoEnableSysProxyOnConnectProvider);
    final autoTun = ref.watch(autoEnableTunOnConnectProvider);
    final enableUdp = ref.watch(enableUdpProvider);

    if (!_initialized) {
      _cfRangesController = TextEditingController(text: cfRanges.join('\n'));
      _httpPortController = TextEditingController(text: httpPort.toString());
      _socksPortController = TextEditingController(text: socksPort.toString());
      _initialized = true;
    }

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
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
          const SizedBox(height: 20),

          // 1. General & Appearance
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.palette_rounded, color: AppTheme.primaryAccent),
                  title: Text(AppStrings.get('theme_mode', locale: locale)),
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
                  title: const Text('Language / زبان'),
                  subtitle: Text(locale == 'fa' ? 'فارسی' : 'English'),
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
          Text(
            locale == 'fa' ? 'راه‌اندازی و اتصال خودکار' : 'Startup & Automation',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.power_settings_new_rounded, color: AppTheme.primaryAccent),
                  title: Text(AppStrings.get('start_on_boot', locale: locale)),
                  subtitle: Text(AppStrings.get('start_on_boot_desc', locale: locale), style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  value: startOnBoot,
                  onChanged: (val) {
                    ref.read(startOnBootProvider.notifier).toggle(val);
                  },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.flash_on_rounded, color: Colors.amber),
                  title: Text(AppStrings.get('auto_connect_on_launch', locale: locale)),
                  subtitle: Text(AppStrings.get('auto_connect_on_launch_desc', locale: locale), style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  value: autoConnectOnLaunch,
                  onChanged: (val) {
                    ref.read(autoConnectOnLaunchProvider.notifier).toggle(val);
                  },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.shield_outlined, color: AppTheme.successColor),
                  title: Text(AppStrings.get('auto_sysproxy_on_connect', locale: locale)),
                  subtitle: Text(AppStrings.get('auto_sysproxy_on_connect_desc', locale: locale), style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  value: autoSysProxy,
                  onChanged: (val) {
                    ref.read(autoEnableSysProxyOnConnectProvider.notifier).toggle(val);
                  },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.vpn_lock_rounded, color: AppTheme.primaryAccent),
                  title: Text(AppStrings.get('auto_tun_on_connect', locale: locale)),
                  subtitle: Text(AppStrings.get('auto_tun_on_connect_desc', locale: locale), style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  value: autoTun,
                  onChanged: (val) {
                    if (val && !XrayProcessService.instance.isRunningAsAdmin()) {
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          backgroundColor: const Color(0xFF1E2230),
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
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.compare_arrows_rounded, color: Colors.tealAccent),
                  title: Text(AppStrings.get('enable_udp', locale: locale)),
                  subtitle: Text(AppStrings.get('enable_udp_desc', locale: locale), style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  value: enableUdp,
                  onChanged: (val) {
                    ref.read(enableUdpProvider.notifier).toggle(val);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 3. Updates Center
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                AppStrings.get('updates', locale: locale),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              Text(
                AppStrings.get('updates_desc', locale: locale),
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                // 3.1 Xray Core Update
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
                  trailing: Row(
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

                // 3.2 Geo Files Update
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
                  trailing: Row(
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

                // 3.3 App Update
                ExpansionTile(
                  leading: const Icon(Icons.system_update_rounded, color: Colors.tealAccent),
                  title: Text(AppStrings.get('app_update', locale: locale)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${AppStrings.get('current_version', locale: locale)}: ${UpdateService.currentAppVersion} ${_appInfo != null ? ' • ${AppStrings.get('latest_version', locale: locale)}: ${_appInfo!.latestVersion}' : ''}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      if (_appStatusMsg != null)
                        Text(
                          _appStatusMsg!,
                          style: TextStyle(
                            fontSize: 11,
                            color: _appStatusMsg!.contains('up to date') || _appStatusMsg!.contains('Downloaded')
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
                  trailing: Row(
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
                          label: Text(AppStrings.get('update_now', locale: locale), style: const TextStyle(fontSize: 11)),
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
                      const SizedBox(width: 8),
                      const Icon(Icons.expand_more_rounded, size: 20),
                    ],
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Update Server URL (Test / Staging URL):',
                            style: TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _appTestUrlController,
                            style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                            decoration: InputDecoration(
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                              hintText: 'https://...',
                            ),
                          ),
                          if (_downloadedAppPath != null) ...[
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppTheme.successColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: AppTheme.successColor.withValues(alpha: 0.3)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.folder_zip_rounded, color: AppTheme.successColor, size: 18),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Saved to: $_downloadedAppPath',
                                      style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 4. Ports Settings
          Text(
            AppStrings.get('port_settings', locale: locale),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.settings_ethernet_rounded, color: AppTheme.primaryAccent),
                  title: Text(AppStrings.get('http_port', locale: locale)),
                  subtitle: Text('Current: $httpPort  •  (Default: 10888)'),
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
                  title: Text(AppStrings.get('socks_port', locale: locale)),
                  subtitle: Text('Current: $socksPort  •  (Default: 10999)'),
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
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.compare_arrows_rounded, color: Colors.tealAccent),
                  title: Text(AppStrings.get('enable_udp', locale: locale)),
                  subtitle: Text(AppStrings.get('enable_udp_desc', locale: locale), style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  value: enableUdp,
                  onChanged: (val) {
                    ref.read(enableUdpProvider.notifier).toggle(val);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 5. Cloudflare Scan Ranges
          Card(
            clipBehavior: Clip.antiAlias,
            child: ExpansionTile(
              initiallyExpanded: false,
              leading: const Icon(Icons.network_ping_rounded, color: AppTheme.secondaryAccent),
              title: Text(
                AppStrings.get('cf_ranges_title', locale: locale),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                '${cfRanges.length} CIDR ranges configured  •  Tap to view / edit',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        AppStrings.get('cf_ranges_desc', locale: locale),
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _cfRangesController,
                        maxLines: 8,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                        decoration: InputDecoration(
                          hintText: AppStrings.get('cf_ranges_hint', locale: locale),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          filled: true,
                          fillColor: Theme.of(context).cardColor,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          OutlinedButton.icon(
                            icon: const Icon(Icons.restore_rounded, size: 16),
                            label: Text(AppStrings.get('reset_default', locale: locale)),
                            onPressed: () {
                              ref.read(cfRangesProvider.notifier).resetToDefault();
                              setState(() {
                                _cfRangesController.text = ref.read(cfRangesProvider).join('\n');
                              });
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(AppStrings.get('reset_default', locale: locale))),
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
                              final lines = _cfRangesController.text
                                  .split('\n')
                                  .map((l) => l.trim())
                                  .where((l) => l.isNotEmpty && !l.startsWith('#'))
                                  .toList();
                              ref.read(cfRangesProvider.notifier).updateRanges(lines);
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
        ],
      ),
    );
  }
}
