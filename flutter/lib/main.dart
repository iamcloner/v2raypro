import "package:flutter/material.dart";
import "package:flutter_localizations/flutter_localizations.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "core/ffi/rust_bridge.dart";
import "core/l10n/translations.dart";
import "core/theme/app_theme.dart";
import "features/configs/configs_view.dart";
import "features/dashboard/dashboard_view.dart";
import "features/scanner/scanner_view.dart";
import "features/settings/settings_view.dart";
import "providers/app_providers.dart";

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  RustBridge.instance.initialize();
  runApp(const ProviderScope(child: V2RayProApp()));
}

class V2RayProApp extends ConsumerWidget {
  const V2RayProApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localeStr = ref.watch(currentLocaleProvider);
    final locale = Locale(localeStr);

    return MaterialApp(
      title: "V2Ray Pro",
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      locale: locale,
      supportedLocales: const [
        Locale("en", ""),
        Locale("fa", ""),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const MainShell(),
    );
  }
}

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  int _selectedIndex = 0;

  final _pages = const [
    DashboardView(),
    ConfigsView(),
    ScannerView(),
    SettingsView(),
  ];

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(currentLocaleProvider);
    final isDesktop = MediaQuery.of(context).size.width >= 700;

    if (isDesktop) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _selectedIndex,
              onDestinationSelected: (idx) => setState(() => _selectedIndex = idx),
              labelType: NavigationRailLabelType.all,
              backgroundColor: const Color(0xFF0F131C),
              leading: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryAccent.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.shield_rounded, color: AppTheme.primaryAccent, size: 28),
                ),
              ),
              destinations: [
                NavigationRailDestination(
                  icon: const Icon(Icons.dashboard_rounded),
                  label: Text(AppStrings.get("dashboard", locale: locale)),
                ),
                NavigationRailDestination(
                  icon: const Icon(Icons.hub_rounded),
                  label: Text(AppStrings.get("configs", locale: locale)),
                ),
                NavigationRailDestination(
                  icon: const Icon(Icons.radar_rounded),
                  label: Text(AppStrings.get("scanner", locale: locale)),
                ),
                NavigationRailDestination(
                  icon: const Icon(Icons.settings_rounded),
                  label: Text(AppStrings.get("settings", locale: locale)),
                ),
              ],
            ),
            const VerticalDivider(thickness: 1, width: 1, color: Color(0xFF1E2433)),
            Expanded(child: _pages[_selectedIndex]),
          ],
        ),
      );
    }

    return Scaffold(
      body: _pages[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (idx) => setState(() => _selectedIndex = idx),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.dashboard_rounded),
            label: AppStrings.get("dashboard", locale: locale),
          ),
          NavigationDestination(
            icon: const Icon(Icons.hub_rounded),
            label: AppStrings.get("configs", locale: locale),
          ),
          NavigationDestination(
            icon: const Icon(Icons.radar_rounded),
            label: AppStrings.get("scanner", locale: locale),
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_rounded),
            label: AppStrings.get("settings", locale: locale),
          ),
        ],
      ),
    );
  }
}
