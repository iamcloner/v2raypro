import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "../../core/l10n/translations.dart";
import "../../core/theme/app_theme.dart";
import "../../providers/app_providers.dart";

class SettingsView extends ConsumerWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(currentLocaleProvider);

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            AppStrings.get("settings", locale: locale),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.language_rounded, color: AppTheme.primaryAccent),
                  title: const Text("Language / ????"),
                  subtitle: Text(locale == "fa" ? "????? (RTL)" : "English"),
                  trailing: DropdownButton<String>(
                    value: locale,
                    underline: const SizedBox(),
                    items: const [
                      DropdownMenuItem(value: "en", child: Text("English")),
                      DropdownMenuItem(value: "fa", child: Text("?????")),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        ref.read(currentLocaleProvider.notifier).state = val;
                      }
                    },
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.dns_rounded, color: AppTheme.secondaryAccent),
                  title: const Text("Xray Core Path"),
                  subtitle: const Text("assets/bin/xray.exe"),
                  trailing: const Icon(Icons.folder_open_rounded),
                  onTap: () {},
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.science_rounded, color: AppTheme.warningColor),
                  title: Text(AppStrings.get("mock_mode", locale: locale)),
                  subtitle: const Text("Run offline simulated scans for testing"),
                  value: true,
                  onChanged: (val) {},
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
