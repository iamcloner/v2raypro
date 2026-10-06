import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/l10n/translations.dart';
import 'core/theme/app_theme.dart';
import 'providers/app_providers.dart';
import 'services/xray_process_service.dart';

class SettingsView extends ConsumerWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(currentLocaleProvider);
    final httpPort = ref.watch(httpPortProvider);
    final socksPort = ref.watch(socksPortProvider);

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
                  subtitle: Text('xray.exe (Official v25 Embedded)'),
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
                  subtitle: Text(httpPort.toString() + ' (Default: 10888)'),
                  trailing: SizedBox(
                    width: 100,
                    child: TextField(
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.end,
                      decoration: const InputDecoration(border: InputBorder.none),
                      controller: TextEditingController(text: httpPort.toString()),
                      onSubmitted: (val) {
                        final p = int.tryParse(val);
                        if (p != null && p > 0 && p < 65535) {
                          ref.read(httpPortProvider.notifier).state = p;
                          XrayProcessService.instance.httpPort = p;
                        }
                      },
                    ),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.swap_calls_rounded, color: AppTheme.secondaryAccent),
                  title: Text(AppStrings.get('socks_port', locale: locale)),
                  subtitle: Text(socksPort.toString() + ' (Default: 10999)'),
                  trailing: SizedBox(
                    width: 100,
                    child: TextField(
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.end,
                      decoration: const InputDecoration(border: InputBorder.none),
                      controller: TextEditingController(text: socksPort.toString()),
                      onSubmitted: (val) {
                        final p = int.tryParse(val);
                        if (p != null && p > 0 && p < 65535) {
                          ref.read(socksPortProvider.notifier).state = p;
                          XrayProcessService.instance.socksPort = p;
                        }
                      },
                    ),
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
