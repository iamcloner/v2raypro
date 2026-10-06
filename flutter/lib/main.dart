import 'configs_view.dart';
import 'subscriptions_view.dart';
import 'scanner_view.dart';
import 'logs_view.dart';
import 'settings_view.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'models/proxy_node.dart';
import 'models/scan_result.dart';
import 'models/outbound_info.dart';
import 'core/ffi/rust_bridge.dart';
import 'core/l10n/translations.dart';
import 'core/theme/app_theme.dart';
import 'providers/app_providers.dart';
import 'services/cloudflare_scanner_service.dart';
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

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(currentLocaleProvider);
    final isDesktop = MediaQuery.of(context).size.width >= 700;
    final nodes = ref.watch(nodesProvider);
    final activeNode = nodes.isEmpty ? null : nodes.firstWhere((n) => n.isActive, orElse: () => nodes.first);
    final cfRanges = ref.watch(cfRangesProvider);
    final isCf = activeNode != null && CloudflareScannerService.isCloudflareIp(activeNode.address, cfRanges);

    // Build pages and nav items dynamically: Scanner is completely excluded if active node is not Cloudflare
    final pages = <Widget>[
      const DashboardView(),
      const ConfigsView(),
      const SubscriptionsView(),
      if (isCf) const ScannerView(),
      const LogsView(),
      const SettingsView(),
    ];

    if (_selectedIndex >= pages.length) {
      _selectedIndex = 0;
    }

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
                  icon: const Icon(Icons.rss_feed_rounded),
                  label: Text(AppStrings.get('subscriptions', locale: locale)),
                ),
                if (isCf)
                  NavigationRailDestination(
                    icon: const Icon(Icons.radar_rounded),
                    label: Text(AppStrings.get('scanner', locale: locale)),
                  ),
                NavigationRailDestination(
                  icon: const Icon(Icons.article_rounded),
                  label: Text(AppStrings.get('logs', locale: locale)),
                ),
                NavigationRailDestination(
                  icon: const Icon(Icons.settings_rounded),
                  label: Text(AppStrings.get('settings', locale: locale)),
                ),
              ],
            ),
            const VerticalDivider(thickness: 1, width: 1, color: Color(0xFF1E2433)),
            Expanded(child: pages[_selectedIndex]),
          ],
        ),
      );
    }

    return Scaffold(
      body: pages[_selectedIndex],
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
            icon: const Icon(Icons.rss_feed_rounded),
            label: AppStrings.get('subscriptions', locale: locale),
          ),
          if (isCf)
            NavigationDestination(
              icon: const Icon(Icons.radar_rounded),
              label: AppStrings.get('scanner', locale: locale),
            ),
          NavigationDestination(
            icon: const Icon(Icons.article_rounded),
            label: AppStrings.get('logs', locale: locale),
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

class DashboardView extends ConsumerStatefulWidget {
  const DashboardView({super.key});

  @override
  ConsumerState<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends ConsumerState<DashboardView> {
  Timer? _ticker;
  bool _isTestingPing = false;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _formatDuration(DateTime? connectedAt) {
    if (connectedAt == null) return "00:00:00";
    final diff = DateTime.now().difference(connectedAt);
    final h = diff.inHours.toString().padLeft(2, '0');
    final m = (diff.inMinutes % 60).toString().padLeft(2, '0');
    final s = (diff.inSeconds % 60).toString().padLeft(2, '0');
    return "$h:$m:$s";
  }

  Future<void> _retestPing(ProxyNode node) async {
    if (_isTestingPing) return;
    setState(() => _isTestingPing = true);
    final lat = await XrayProcessService.instance.testNodeLatency(node);
    if (mounted) {
      if (lat != null) {
        ref.read(nodesProvider.notifier).updateLatency(node.id, lat);
      }
      setState(() => _isTestingPing = false);
    }
  }

  Color _latencyColor(int? lat) {
    if (lat == null) return Colors.grey;
    if (lat < 150) return AppTheme.successColor;
    if (lat < 300) return Colors.amber;
    return AppTheme.errorColor;
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(connectionStatusProvider);
    final nodes = ref.watch(nodesProvider);
    final activeNode = nodes.isEmpty ? null : nodes.firstWhere((n) => n.isActive, orElse: () => nodes.first);
    final locale = ref.watch(currentLocaleProvider);
    final isSysProxy = ref.watch(isSystemProxyEnabledProvider);
    final isTun = ref.watch(isTunEnabledProvider);
    final connectedAt = ref.watch(connectedAtProvider);
    final outbound = ref.watch(outboundInfoProvider);
    final cfRanges = ref.watch(cfRangesProvider);

    final isConnected = status == ConnectionStateEnum.connected;
    final isConnecting = status == ConnectionStateEnum.connecting;
    final isCf = activeNode != null && CloudflareScannerService.isCloudflareIp(activeNode.address, cfRanges);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Hero Connection Status Card
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: isConnected ? AppTheme.successColor.withValues(alpha: 0.4) : const Color(0xFF1E2638),
                width: 1.2,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 20),
              child: Column(
                children: [
                  Container(
                    width: 82,
                    height: 82,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: (isConnected ? AppTheme.successColor : (isConnecting ? AppTheme.primaryAccent : Colors.grey.shade800)).withValues(alpha: 0.15),
                      border: Border.all(
                        color: isConnected ? AppTheme.successColor : (isConnecting ? AppTheme.primaryAccent : Colors.grey.shade700),
                        width: 2.8,
                      ),
                    ),
                    child: Center(
                      child: IconButton(
                        iconSize: 40,
                        icon: isConnecting
                            ? const SizedBox(
                                width: 34,
                                height: 34,
                                child: CircularProgressIndicator(strokeWidth: 3, color: AppTheme.primaryAccent),
                              )
                            : Icon(
                                isConnected ? Icons.power_settings_new_rounded : Icons.play_arrow_rounded,
                                color: isConnected ? AppTheme.successColor : Colors.white,
                              ),
                        onPressed: nodes.isEmpty || isConnecting
                            ? null
                            : () {
                                ref.read(connectionStatusProvider.notifier).toggleConnect();
                              },
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    nodes.isEmpty
                        ? AppStrings.get('no_nodes', locale: locale)
                        : isConnected
                            ? AppStrings.get('connected', locale: locale)
                            : isConnecting
                                ? AppStrings.get('connecting', locale: locale)
                                : AppStrings.get('disconnected', locale: locale),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isConnected ? AppTheme.successColor : (isConnecting ? AppTheme.primaryAccent : Colors.grey.shade400),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (activeNode != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            '${activeNode.name} (${activeNode.address}:${activeNode.port})',
                            style: const TextStyle(fontSize: 13, color: Colors.grey),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isCf) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.amber, width: 0.8),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.star_rounded, size: 13, color: Colors.amber),
                                SizedBox(width: 2),
                                Text(
                                  "CF",
                                  style: TextStyle(
                                    color: Colors.amber,
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
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 2. Connected Live Diagnostics Card (When Connected)
          if (isConnected) ...[
            Card(
              color: const Color(0xFF131824),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: AppTheme.primaryAccent.withValues(alpha: 0.35), width: 1.2),
              ),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header: Location / Country & Refresh Button
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryAccent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.public_rounded, size: 20, color: AppTheme.primaryAccent),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                AppStrings.get('connected_country', locale: locale),
                                style: const TextStyle(fontSize: 11, color: Colors.grey),
                              ),
                              Row(
                                children: [
                                  Text(
                                    outbound.flagEmoji,
                                    style: const TextStyle(fontSize: 16),
                                  ),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      outbound.country != null
                                          ? '${outbound.country}${outbound.city != null ? ' (${outbound.city})' : ''}'
                                          : (outbound.isLoading
                                              ? AppStrings.get('fetching_ip', locale: locale)
                                              : AppStrings.get('unknown_location', locale: locale)),
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (outbound.isp != null) ...[
                                    const SizedBox(width: 6),
                                    Text(
                                      '•  ${outbound.isp}',
                                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: AppStrings.get('refresh_ip', locale: locale),
                          icon: outbound.isLoading
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryAccent),
                                )
                              : const Icon(Icons.refresh_rounded, size: 18, color: Colors.white70),
                          onPressed: outbound.isLoading
                              ? null
                              : () => ref.read(outboundInfoProvider.notifier).fetch(),
                        ),
                      ],
                    ),
                    const Divider(height: 22, color: Colors.white12),

                    // 4-Item Grid: IPv4, IPv6, Last Ping, Connection Duration
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final isNarrow = constraints.maxWidth < 620;
                        return Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            // IPv4 Tile
                            SizedBox(
                              width: isNarrow ? (constraints.maxWidth - 12) / 2 : (constraints.maxWidth - 36) / 4,
                              child: _buildInfoItem(
                                title: AppStrings.get('ipv4_address', locale: locale),
                                value: outbound.ipv4 ?? (outbound.isLoading ? '...' : '--'),
                                icon: Icons.lan_rounded,
                                color: const Color(0xFF38BDF8),
                                copyable: outbound.ipv4 != null,
                              ),
                            ),
                            // IPv6 Tile
                            SizedBox(
                              width: isNarrow ? (constraints.maxWidth - 12) / 2 : (constraints.maxWidth - 36) / 4,
                              child: _buildInfoItem(
                                title: AppStrings.get('ipv6_address', locale: locale),
                                value: outbound.ipv6 ?? AppStrings.get('not_supported', locale: locale),
                                icon: Icons.alt_route_rounded,
                                color: const Color(0xFFA78BFA),
                                copyable: outbound.ipv6 != null,
                              ),
                            ),
                            // Last Ping Tile with Retest Button
                            SizedBox(
                              width: isNarrow ? (constraints.maxWidth - 12) / 2 : (constraints.maxWidth - 36) / 4,
                              child: _buildPingItem(
                                title: AppStrings.get('ping', locale: locale),
                                latency: activeNode?.latencyMs,
                                isTesting: _isTestingPing,
                                onRetest: activeNode != null ? () => _retestPing(activeNode) : null,
                                locale: locale,
                              ),
                            ),
                            // Duration Tile
                            SizedBox(
                              width: isNarrow ? (constraints.maxWidth - 12) / 2 : (constraints.maxWidth - 36) / 4,
                              child: _buildInfoItem(
                                title: AppStrings.get('connection_duration', locale: locale),
                                value: _formatDuration(connectedAt),
                                icon: Icons.timer_outlined,
                                color: AppTheme.successColor,
                                copyable: false,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // 3. System Proxy & TUN Mode Toggles
          Row(
            children: [
              Expanded(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.shield_outlined,
                              color: (isConnected && isSysProxy) ? AppTheme.successColor : Colors.grey,
                              size: 24,
                            ),
                            const SizedBox(width: 10),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  AppStrings.get('system_proxy', locale: locale),
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                                Text(
                                  AppStrings.get('system_proxy_desc', locale: locale),
                                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                                ),
                              ],
                            ),
                          ],
                        ),
                        Switch(
                          value: isConnected && isSysProxy,
                          activeColor: AppTheme.successColor,
                          onChanged: !isConnected
                              ? null
                              : (val) {
                                  ref.read(isSystemProxyEnabledProvider.notifier).toggle(val);
                                },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.vpn_lock_rounded,
                              color: (isConnected && isTun) ? AppTheme.primaryAccent : Colors.grey,
                              size: 24,
                            ),
                            const SizedBox(width: 10),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  AppStrings.get('tun_mode', locale: locale),
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                                Text(
                                  AppStrings.get('tun_mode_desc', locale: locale),
                                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                                ),
                              ],
                            ),
                          ],
                        ),
                        Switch(
                          value: isConnected && isTun,
                          activeColor: AppTheme.primaryAccent,
                          onChanged: !isConnected
                              ? null
                              : (val) {
                                  ref.read(isTunEnabledProvider.notifier).toggle(val);
                                },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 4. Traffic Metrics Tiles
          Row(
            children: [
              Expanded(
                child: _buildMetricTile(
                  title: AppStrings.get('download', locale: locale),
                  value: isConnected ? '12.4 MB' : '0 B',
                  icon: Icons.arrow_downward_rounded,
                  color: AppTheme.successColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMetricTile(
                  title: AppStrings.get('upload', locale: locale),
                  value: isConnected ? '1.8 MB' : '0 B',
                  icon: Icons.arrow_upward_rounded,
                  color: AppTheme.secondaryAccent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMetricTile(
                  title: activeNode?.protocol.name.toUpperCase() ?? 'PROTOCOL',
                  value: activeNode?.network.name.toUpperCase() ?? '--',
                  icon: Icons.cable_rounded,
                  color: AppTheme.primaryAccent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 5. Active Node Technical Details Card
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
                        Flexible(
                          child: Text(
                            activeNode.name,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
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
                    _buildDetailRow('Port', '${activeNode.port}'),
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

  Widget _buildInfoItem({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required bool copyable,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF192030),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF263248), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (copyable)
                InkWell(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: value));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('$value copied'), duration: const Duration(seconds: 1)),
                    );
                  },
                  child: const Padding(
                    padding: EdgeInsets.all(2.0),
                    child: Icon(Icons.copy_rounded, size: 13, color: Colors.white54),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
              color: color,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildPingItem({
    required String title,
    required int? latency,
    required bool isTesting,
    required VoidCallback? onRetest,
    required String locale,
  }) {
    final color = _latencyColor(latency);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF192030),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF263248), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bolt_rounded, size: 14, color: color),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (onRetest != null)
                InkWell(
                  onTap: isTesting ? null : onRetest,
                  child: isTesting
                      ? const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 1.5, color: AppTheme.primaryAccent),
                        )
                      : const Padding(
                          padding: EdgeInsets.all(2.0),
                          child: Icon(Icons.refresh_rounded, size: 13, color: Colors.white54),
                        ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            latency != null ? '$latency ms' : '--',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricTile({required String title, required String value, required IconData icon, required Color color}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
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


