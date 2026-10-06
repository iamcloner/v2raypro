import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/l10n/translations.dart';
import 'core/theme/app_theme.dart';
import 'providers/app_providers.dart';
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
  bool _initialized = false;

  @override
  void dispose() {
    _cfRangesController.dispose();
    _httpPortController.dispose();
    _socksPortController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(currentLocaleProvider);
    final httpPort = ref.watch(httpPortProvider);
    final socksPort = ref.watch(socksPortProvider);
    final cfRanges = ref.watch(cfRangesProvider);

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
          Text(
            AppStrings.get('settings', locale: locale),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.language_rounded, color: AppTheme.primaryAccent),
                  title: const Text('Language'),
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
                const Divider(height: 1),
                const ListTile(
                  leading: Icon(Icons.dns_rounded, color: AppTheme.secondaryAccent),
                  title: Text('Xray Core Binary'),
                  subtitle: Text('xray.exe (Official v26.6.1 Embedded)'),
                  trailing: Icon(Icons.check_circle_rounded, color: AppTheme.successColor),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
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
              ],
            ),
          ),
          const SizedBox(height: 20),
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
