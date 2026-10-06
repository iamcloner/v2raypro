import 'configs_view.dart';
import 'scanner_view.dart';
import 'settings_view.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'models/proxy_node.dart';
import 'models/scan_result.dart';
import 'core/ffi/rust_bridge.dart';
import 'core/l10n/translations.dart';
import 'core/theme/app_theme.dart';
import 'providers/app_providers.dart';
import 'services/xray_process_service.dart';

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
      title: 'V2Ray Pro',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      locale: locale,
      supportedLocales: const [
        Locale('en', ''),
        Locale('fa', ''),
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

  final List<Widget> _pages = const [
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
                    color: AppTheme.primaryAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.shield_rounded, color: AppTheme.primaryAccent, size: 28),
                ),
              ),
              destinations: [
                NavigationRailDestination(
                  icon: const Icon(Icons.dashboard_rounded),
                  label: Text(AppStrings.get('dashboard', locale: locale)),
                ),
                NavigationRailDestination(
                  icon: const Icon(Icons.hub_rounded),
                  label: Text(AppStrings.get('configs', locale: locale)),
                ),
                NavigationRailDestination(
                  icon: const Icon(Icons.radar_rounded),
                  label: Text(AppStrings.get('scanner', locale: locale)),
                ),
                NavigationRailDestination(
                  icon: const Icon(Icons.settings_rounded),
                  label: Text(AppStrings.get('settings', locale: locale)),
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
            label: AppStrings.get('dashboard', locale: locale),
          ),
          NavigationDestination(
            icon: const Icon(Icons.hub_rounded),
            label: AppStrings.get('configs', locale: locale),
          ),
          NavigationDestination(
            icon: const Icon(Icons.radar_rounded),
            label: AppStrings.get('scanner', locale: locale),
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_rounded),
            label: AppStrings.get('settings', locale: locale),
          ),
        ],
      ),
    );
  }
}

class DashboardView extends ConsumerWidget {
  const DashboardView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(connectionStatusProvider);
    final nodes = ref.watch(nodesProvider);
    final activeNode = nodes.isEmpty ? null : nodes.firstWhere((n) => n.isActive, orElse: () => nodes.first);
    final locale = ref.watch(currentLocaleProvider);
    final isSysProxy = ref.watch(isSystemProxyEnabledProvider);

    final isConnected = status == ConnectionStateEnum.connected;
    final isConnecting = status == ConnectionStateEnum.connecting;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
              child: Column(
                children: [
                  Container(
                    width: 130,
                    height: 130,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: (isConnected ? AppTheme.successColor : Colors.grey.shade800).withValues(alpha: 0.15),
                      border: Border.all(
                        color: isConnected ? AppTheme.successColor : Colors.grey.shade700,
                        width: 3,
                      ),
                    ),
                    child: Center(
                      child: IconButton(
                        iconSize: 52,
                        icon: Icon(
                          isConnected ? Icons.power_settings_new_rounded : Icons.play_arrow_rounded,
                          color: isConnected ? AppTheme.successColor : Colors.white,
                        ),
                        onPressed: nodes.isEmpty ? null : () {
                          ref.read(connectionStatusProvider.notifier).toggleConnect();
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    nodes.isEmpty
                        ? AppStrings.get('no_nodes', locale: locale)
                        : isConnected
                            ? AppStrings.get('connected', locale: locale)
                            : isConnecting
                                ? AppStrings.get('connecting', locale: locale)
                                : AppStrings.get('disconnected', locale: locale),
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: isConnected ? AppTheme.successColor : Colors.grey.shade400,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (activeNode != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      '${activeNode.name} (${activeNode.address}:${activeNode.port})',
                      style: const TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: BorderSide(color: isSysProxy ? AppTheme.successColor : Colors.grey.shade700),
                  ),
                  icon: Icon(Icons.shield_outlined, color: isSysProxy ? AppTheme.successColor : Colors.grey),
                  label: Text(
                    AppStrings.get('set_system_proxy', locale: locale),
                    style: TextStyle(color: isSysProxy ? AppTheme.successColor : Colors.white),
                  ),
                  onPressed: () {
                    XrayProcessService.instance.setWindowsSystemProxy(true);
                    ref.read(isSystemProxyEnabledProvider.notifier).state = true;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(AppStrings.get('set_system_proxy', locale: locale))),
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: BorderSide(color: !isSysProxy ? AppTheme.errorColor : Colors.grey.shade700),
                  ),
                  icon: Icon(Icons.remove_moderator_outlined, color: !isSysProxy ? AppTheme.errorColor : Colors.grey),
                  label: Text(
                    AppStrings.get('clear_system_proxy', locale: locale),
                    style: TextStyle(color: !isSysProxy ? AppTheme.errorColor : Colors.white),
                  ),
                  onPressed: () {
                    XrayProcessService.instance.setWindowsSystemProxy(false);
                    ref.read(isSystemProxyEnabledProvider.notifier).state = false;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(AppStrings.get('clear_system_proxy', locale: locale))),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _buildMetricTile(
                  title: AppStrings.get('ping', locale: locale),
                  value: activeNode?.latencyMs != null ? '${activeNode!.latencyMs} ms' : '--',
                  icon: Icons.speed_rounded,
                  color: AppTheme.primaryAccent,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildMetricTile(
                  title: AppStrings.get('download', locale: locale),
                  value: isConnected ? '12.4 MB' : '0 B',
                  icon: Icons.arrow_downward_rounded,
                  color: AppTheme.successColor,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildMetricTile(
                  title: AppStrings.get('upload', locale: locale),
                  value: isConnected ? '1.8 MB' : '0 B',
                  icon: Icons.arrow_upward_rounded,
                  color: AppTheme.secondaryAccent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (activeNode != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          activeNode.name,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryAccent.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            activeNode.protocol.name.toUpperCase(),
                            style: const TextStyle(fontSize: 12, color: AppTheme.primaryAccent, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    _buildDetailRow('IP / Server', activeNode.address),
                    const SizedBox(height: 8),
                    _buildDetailRow('Port', ''),
                    const SizedBox(height: 8),
                    _buildDetailRow('Transport', activeNode.network.name.toUpperCase()),
                    const SizedBox(height: 8),
                    _buildDetailRow('Security', activeNode.security.name.toUpperCase()),
                    if (activeNode.originalAddress != null) ...[
                      const SizedBox(height: 8),
                      _buildDetailRow('Original Host', activeNode.originalAddress!),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMetricTile({required String title, required String value, required IconData icon, required Color color}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
      ],
    );
  }
}

