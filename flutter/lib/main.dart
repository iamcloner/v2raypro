import "models/proxy_node.dart";
import "models/scan_result.dart";
import "package:flutter/material.dart";
import "package:flutter_localizations/flutter_localizations.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "core/ffi/rust_bridge.dart";
import "core/l10n/translations.dart";
import "core/theme/app_theme.dart";
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


class DashboardView extends ConsumerWidget {
  const DashboardView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(connectionStatusProvider);
    final nodes = ref.watch(nodesProvider);
    final activeNode = nodes.firstWhere((n) => n.isActive, orElse: () => nodes.first);
    final locale = ref.watch(currentLocaleProvider);

    final isConnected = status == ConnectionStateEnum.connected;
    final isConnecting = status == ConnectionStateEnum.connecting;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Connection Status Card
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
              child: Column(
                children: [
                  // Animated Pulsing Status Orb
                  Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: (isConnected ? AppTheme.successColor : Colors.grey.shade800).withOpacity(0.15),
                      border: Border.all(
                        color: isConnected ? AppTheme.successColor : Colors.grey.shade700,
                        width: 3,
                      ),
                    ),
                    child: Center(
                      child: IconButton(
                        iconSize: 56,
                        icon: Icon(
                          isConnected ? Icons.power_settings_new_rounded : Icons.play_arrow_rounded,
                          color: isConnected ? AppTheme.successColor : Colors.white,
                        ),
                        onPressed: () {
                          ref.read(connectionStatusProvider.notifier).toggleConnect();
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    isConnected
                        ? AppStrings.get("connected", locale: locale)
                        : isConnecting
                            ? AppStrings.get("connecting", locale: locale)
                            : AppStrings.get("disconnected", locale: locale),
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: isConnected ? AppTheme.successColor : Colors.grey.shade400,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "${activeNode.name} (${activeNode.protocol.name.toUpperCase()})",
                    style: const TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Real-time Metrics Grid
          Row(
            children: [
              Expanded(
                child: _buildMetricTile(
                  title: AppStrings.get("ping", locale: locale),
                  value: "${activeNode.latencyMs ?? '--'} ms",
                  icon: Icons.speed_rounded,
                  color: AppTheme.primaryAccent,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildMetricTile(
                  title: AppStrings.get("download", locale: locale),
                  value: isConnected ? "14.2 MB" : "0 B",
                  icon: Icons.arrow_downward_rounded,
                  color: AppTheme.successColor,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildMetricTile(
                  title: AppStrings.get("upload", locale: locale),
                  value: isConnected ? "2.1 MB" : "0 B",
                  icon: Icons.arrow_upward_rounded,
                  color: AppTheme.secondaryAccent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Active Endpoint Details Card
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
                          color: AppTheme.primaryAccent.withOpacity(0.2),
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
                  _buildDetailRow("IP / Server", activeNode.address),
                  const SizedBox(height: 8),
                  _buildDetailRow("Port", "${activeNode.port}"),
                  const SizedBox(height: 8),
                  _buildDetailRow("Transport", activeNode.network.name.toUpperCase()),
                  const SizedBox(height: 8),
                  _buildDetailRow("Security", activeNode.security.name.toUpperCase()),
                  if (activeNode.originalAddress != null) ...[
                    const SizedBox(height: 8),
                    _buildDetailRow("Original Host", activeNode.originalAddress!),
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
                color: color.withOpacity(0.15),
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


class ConfigsView extends ConsumerStatefulWidget {
  const ConfigsView({super.key});

  @override
  ConsumerState<ConfigsView> createState() => _ConfigsViewState();
}

class _ConfigsViewState extends ConsumerState<ConfigsView> {
  final _importController = TextEditingController();

  void _showImportDialog(String locale) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppStrings.get("add_config", locale: locale)),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _importController,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: "Paste vless://, vmess://, trojan://, ss://, or subscription URL...",
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            child: const Text("Cancel"),
            onPressed: () => Navigator.pop(ctx),
          ),
          FilledButton(
            child: const Text("Import"),
            onPressed: () {
              final text = _importController.text.trim();
              if (text.isNotEmpty) {
                // Parse simple sample node
                final newNode = ProxyNode(
                  id: "node-${DateTime.now().millisecondsSinceEpoch}",
                  name: "Imported Node (${text.split('://').first})",
                  protocol: ProtocolType.vless,
                  address: "104.16.20.1",
                  port: 443,
                  uuidOrPassword: "imported-uuid-placeholder",
                  network: NetworkType.ws,
                  security: SecurityType.tls,
                  latencyMs: 65,
                );
                ref.read(nodesProvider.notifier).addNode(newNode);
                _importController.clear();
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Configuration imported successfully")),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nodes = ref.watch(nodesProvider);
    final locale = ref.watch(currentLocaleProvider);

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  AppStrings.get("configs", locale: locale),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: AppTheme.primaryAccent),
                  icon: const Icon(Icons.add),
                  label: Text(AppStrings.get("add_config", locale: locale)),
                  onPressed: () => _showImportDialog(locale),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Expanded(
              child: ListView.separated(
                itemCount: nodes.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final node = nodes[index];
                  return Card(
                    child: ListTile(
                      leading: Icon(
                        node.isActive ? Icons.radio_button_checked : Icons.radio_button_off,
                        color: node.isActive ? AppTheme.primaryAccent : Colors.grey,
                      ),
                      title: Text(node.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text("${node.address}:${node.port}  •  ${node.protocol.name.toUpperCase()}"),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (node.latencyMs != null)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppTheme.successColor.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                "${node.latencyMs} ms",
                                style: const TextStyle(color: AppTheme.successColor, fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, color: Colors.grey),
                            onPressed: () {
                              ref.read(nodesProvider.notifier).removeNode(node.id);
                            },
                          ),
                        ],
                      ),
                      onTap: () {
                        ref.read(nodesProvider.notifier).setActive(node.id);
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}



class ScannerView extends ConsumerStatefulWidget {
  const ScannerView({super.key});

  @override
  ConsumerState<ScannerView> createState() => _ScannerViewState();
}

class _ScannerViewState extends ConsumerState<ScannerView> {
  int _candidates = 30;
  int _workers = 15;
  String _searchQuery = "";
  bool _onlySuccessful = true;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(scannerProvider);
    final nodes = ref.watch(nodesProvider);
    final activeNode = nodes.firstWhere((n) => n.isActive, orElse: () => nodes.first);
    final locale = ref.watch(currentLocaleProvider);

    final filteredResults = state.results.where((r) {
      if (_onlySuccessful && (!r.tcpSuccess || !r.tlsSuccess)) return false;
      if (_searchQuery.isNotEmpty && !r.ip.contains(_searchQuery)) return false;
      return true;
    }).toList();

    // Sort by latency
    filteredResults.sort((a, b) => a.rankScore.compareTo(b.rankScore));

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header & Target Node Card
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
                          AppStrings.get("scanner", locale: locale),
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        if (activeNode.originalAddress != null)
                          OutlinedButton.icon(
                            icon: const Icon(Icons.restore_rounded, size: 16),
                            label: Text(AppStrings.get("restore_original", locale: locale)),
                            onPressed: () {
                              ref.read(nodesProvider.notifier).restoreAddress(activeNode.id);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text("Original host restored")),
                              );
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      "Target: ${activeNode.name} (${activeNode.address})",
                      style: const TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryAccent,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            icon: Icon(state.isScanning ? Icons.stop_rounded : Icons.search_rounded),
                            label: Text(
                              state.isScanning
                                  ? AppStrings.get("cancel_scan", locale: locale)
                                  : AppStrings.get("find_best_ip", locale: locale),
                            ),
                            onPressed: () {
                              if (state.isScanning) {
                                ref.read(scannerProvider.notifier).cancelScan();
                              } else {
                                ref.read(scannerProvider.notifier).startScan(
                                      candidates: _candidates,
                                      workers: _workers,
                                    );
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Scan Progress Indicator
            if (state.isScanning || state.scanned > 0) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("${AppStrings.get("scanning", locale: locale)} (${state.scanned} / ${state.total})"),
                          if (state.currentIp.isNotEmpty)
                            Text(
                              state.currentIp,
                              style: const TextStyle(color: AppTheme.primaryAccent, fontFamily: "monospace"),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      LinearProgressIndicator(
                        value: state.total > 0 ? (state.scanned / state.total) : 0,
                        backgroundColor: Colors.grey.shade800,
                        valueColor: const AlwaysStoppedAnimation(AppTheme.primaryAccent),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Best IP Highlight Card
            if (state.bestIp != null) ...[
              Card(
                color: AppTheme.primaryAccent.withOpacity(0.1),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: AppTheme.primaryAccent, width: 1.5),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.star_rounded, color: Colors.amber, size: 36),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("Best Clean IP Found", style: TextStyle(fontWeight: FontWeight.bold)),
                            Text(
                              "${state.bestIp!.ip}  •  ${state.bestIp!.tcpLatencyMs} ms  •  ${state.bestIp!.latencyTier}",
                              style: const TextStyle(color: Colors.grey, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: AppTheme.primaryAccent),
                        child: Text(AppStrings.get("apply_ip", locale: locale)),
                        onPressed: () {
                          ref.read(nodesProvider.notifier).applyIp(activeNode.id, state.bestIp!.ip);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text("Applied IP ${state.bestIp!.ip} to ${activeNode.name}")),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Search & Filter Bar
            Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: "Filter by IP...",
                      prefixIcon: const Icon(Icons.search, size: 20),
                      filled: true,
                      fillColor: const Color(0xFF171C28),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    onChanged: (val) => setState(() => _searchQuery = val),
                  ),
                ),
                const SizedBox(width: 12),
                FilterChip(
                  label: const Text("Only Success"),
                  selected: _onlySuccessful,
                  onSelected: (val) => setState(() => _onlySuccessful = val),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Results List
            if (filteredResults.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: Text(
                    state.isScanning ? "Scanning candidate subnets..." : "No results yet. Click 'Find Best IP' to start.",
                    style: const TextStyle(color: Colors.grey),
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: filteredResults.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final res = filteredResults[index];
                  return _buildResultTile(res, activeNode.id, locale);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultTile(ScanResult res, String activeNodeId, String locale) {
    final success = res.tcpSuccess && res.tlsSuccess;
    return Card(
      child: ListTile(
        title: Text(res.ip, style: const TextStyle(fontFamily: "monospace", fontWeight: FontWeight.bold)),
        subtitle: Text(
          success
              ? "TCP: ${res.tcpLatencyMs}ms  |  TLS: ${res.tlsLatencyMs}ms  |  ${res.latencyTier}"
              : (res.error ?? "Failed"),
          style: TextStyle(
            fontSize: 12,
            color: success ? Colors.grey : AppTheme.errorColor,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: (success ? AppTheme.successColor : AppTheme.errorColor).withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                success ? "${res.tcpLatencyMs} ms" : "Timeout",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: success ? AppTheme.successColor : AppTheme.errorColor,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.check_circle_outline_rounded, color: AppTheme.primaryAccent),
              tooltip: AppStrings.get("apply_ip", locale: locale),
              onPressed: () {
                ref.read(nodesProvider.notifier).applyIp(activeNodeId, res.ip);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("Applied IP ${res.ip} to active node")),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}



