import 'configs_view.dart';
import 'subscriptions_view.dart';
import 'scanner_view.dart';
import 'logs_view.dart';
import 'settings_view.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:ui';
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
import 'services/tray_service.dart';
import 'services/update_service.dart';
import 'services/xray_process_service.dart';
import 'utils/ip_mask_util.dart';
import 'widgets/country_flag_badge.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  RustBridge.instance.initialize();

  // Startup safety check: If previous run left active proxy or orphan xray/TUN processes, clean them up immediately
  try {
    XrayProcessService.instance.cleanupSystemAndXray();
  } catch (_) {}

  final container = ProviderContainer();
  await AppTrayService.instance.init(container);
  runApp(UncontrolledProviderScope(container: container, child: const V2RayProApp()));
}

class V2RayProApp extends ConsumerStatefulWidget {
  const V2RayProApp({super.key});

  @override
  ConsumerState<V2RayProApp> createState() => _V2RayProAppState();
}

class _V2RayProAppState extends ConsumerState<V2RayProApp> {
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(
      onExitRequested: () async {
        try {
          XrayProcessService.instance.cleanupSystemAndXray();
        } catch (_) {}
        return AppExitResponse.exit;
      },
      onDetach: () {
        try {
          XrayProcessService.instance.cleanupSystemAndXray();
        } catch (_) {}
      },
    );
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localeStr = ref.watch(currentLocaleProvider);
    final locale = Locale(localeStr);
    final themeMode = ref.watch(appThemeModeProvider);

    return MaterialApp(
      title: 'V2Ray Pro',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
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
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAutoConnect();
    });
  }

  void _checkAutoConnect() {
    final autoConnect = ref.read(autoConnectOnLaunchProvider);
    final status = ref.read(connectionStatusProvider);
    if (autoConnect && status == ConnectionStateEnum.disconnected) {
      final nodes = ref.read(nodesProvider);
      final activeNode = nodes.isEmpty ? null : nodes.firstWhere((n) => n.isActive, orElse: () => nodes.first);
      if (activeNode != null) {
        ref.read(connectionStatusProvider.notifier).connect(activeNode);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(currentLocaleProvider);
    final isDesktop = MediaQuery.of(context).size.width >= 700;
    final nodes = ref.watch(nodesProvider);
    final activeNode = nodes.isEmpty ? null : nodes.firstWhere((n) => n.isActive, orElse: () => nodes.first);
    final cfHosts = ref.watch(cfCheckedHostsProvider);
    final isCf = activeNode != null && (cfHosts[activeNode.address.trim().toLowerCase()] ?? ref.read(cfCheckedHostsProvider.notifier).isCloudflare(activeNode.address));

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
                padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: const Color(0xFF00D2FF).withValues(alpha: 0.4),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF00D2FF).withValues(alpha: 0.25),
                            blurRadius: 14,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Image.asset(
                        'assets/app_icon.png',
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          "V2Ray",
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                            letterSpacing: 0.5,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 3),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1.5),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF00D2FF), Color(0xFFFF7A00)],
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            "PRO",
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 8,
                              color: Colors.white,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
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
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFF00D2FF).withValues(alpha: 0.4),
                  width: 1.2,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.asset('assets/app_icon.png', fit: BoxFit.cover),
            ),
            const SizedBox(width: 10),
            const Text(
              "V2Ray",
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 17,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(width: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF00D2FF), Color(0xFFFF7A00)],
                ),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                "PRO",
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 9,
                  color: Colors.white,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ],
        ),
      ),
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
    final cfHosts = ref.watch(cfCheckedHostsProvider);
    final showFullIp = ref.watch(showFullIpProvider);

    final isConnected = status == ConnectionStateEnum.connected;
    final isConnecting = status == ConnectionStateEnum.connecting;
    final isCf = activeNode != null && (cfHosts[activeNode.address.trim().toLowerCase()] ?? ref.read(cfCheckedHostsProvider.notifier).isCloudflare(activeNode.address));

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 0. Top Brand Header
          _buildBrandHeader(context, status, isConnected, isConnecting, locale),
          const SizedBox(height: 16),

          // 1. Top Section: Connect Card (50% width) and IP Info Card (50% width) side-by-side
          LayoutBuilder(
            builder: (context, constraints) {
              final isDesktop = constraints.maxWidth >= 640;
              final connectCard = _buildConnectCard(
                context,
                ref,
                status: status,
                nodes: nodes,
                activeNode: activeNode,
                locale: locale,
                isConnected: isConnected,
                isConnecting: isConnecting,
                isCf: isCf,
                showFullIp: showFullIp,
              );
              final ipCard = _buildIpInfoCard(
                context,
                ref,
                outbound: outbound,
                activeNode: activeNode,
                locale: locale,
                isConnected: isConnected,
                connectedAt: connectedAt,
                showFullIp: showFullIp,
              );

              if (isDesktop) {
                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: connectCard),
                      const SizedBox(width: 16),
                      Expanded(child: ipCard),
                    ],
                  ),
                );
              } else {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    connectCard,
                    const SizedBox(height: 16),
                    ipCard,
                  ],
                );
              }
            },
          ),
          const SizedBox(height: 16),

          // 2. System Proxy & TUN Mode Toggles
          Row(
            children: [
              Expanded(
                child: Opacity(
                  opacity: isConnected ? 1.0 : 0.45,
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
                                    isConnected
                                        ? AppStrings.get('system_proxy_desc', locale: locale)
                                        : AppStrings.get('connect_first_hint', locale: locale),
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: isConnected ? Colors.grey : AppTheme.secondaryAccent.withValues(alpha: 0.8),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          Switch(
                            value: isConnected && isSysProxy,
                            activeColor: AppTheme.successColor,
                            onChanged: isConnected
                                ? (val) {
                                    ref.read(isSystemProxyEnabledProvider.notifier).toggle(val);
                                  }
                                : null,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Opacity(
                  opacity: isConnected ? 1.0 : 0.45,
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
                                    isConnected
                                        ? AppStrings.get('tun_mode_desc', locale: locale)
                                        : AppStrings.get('connect_first_hint', locale: locale),
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: isConnected ? Colors.grey : AppTheme.primaryAccent.withValues(alpha: 0.8),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          Switch(
                            value: isConnected && isTun,
                            activeColor: AppTheme.primaryAccent,
                            onChanged: isConnected
                                ? (val) async {
                                    if (val && !XrayProcessService.instance.isRunningAsAdmin()) {
                                      _showAdminElevationDialog(context, locale);
                                      return;
                                    }
                                    ref.read(isTunEnabledProvider.notifier).toggle(val);
                                    await ref.read(connectionStatusProvider.notifier).reconnectWithUpdatedSettings();
                                  }
                                : null,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 3. Traffic Metrics Tiles
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
        ],
      ),
    );
  }

  Widget _buildBrandHeader(
    BuildContext context,
    ConnectionStateEnum status,
    bool isConnected,
    bool isConnecting,
    String locale,
  ) {
    Color statusColor;
    String statusText;

    if (isConnected) {
      statusColor = AppTheme.successColor;
      statusText = AppStrings.get('connected', locale: locale);
    } else if (isConnecting) {
      statusColor = Colors.amber;
      statusText = AppStrings.get('connecting', locale: locale);
    } else {
      statusColor = Colors.grey.shade400;
      statusText = AppStrings.get('disconnected', locale: locale);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF131722),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isConnected
              ? const Color(0xFF00D2FF).withValues(alpha: 0.35)
              : const Color(0xFF222938),
          width: 1.2,
        ),
        boxShadow: [
          if (isConnected)
            BoxShadow(
              color: const Color(0xFF00D2FF).withValues(alpha: 0.08),
              blurRadius: 18,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF00D2FF).withValues(alpha: 0.5),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00D2FF).withValues(alpha: 0.25),
                      blurRadius: 14,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Image.asset('assets/app_icon.png', fit: BoxFit.cover),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Text(
                        "V2Ray",
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.6,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF00D2FF), Color(0xFFFF7A00)],
                          ),
                          borderRadius: BorderRadius.circular(5),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFFF7A00).withValues(alpha: 0.35),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                        child: const Text(
                          "PRO",
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.0,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Text(
                          UpdateService.currentAppVersion,
                          style: const TextStyle(
                            fontSize: 10,
                            fontFamily: 'monospace',
                            color: Colors.grey,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    AppStrings.get('app_tagline', locale: locale),
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade400,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: statusColor.withValues(alpha: 0.4),
                width: 1.0,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: statusColor,
                    boxShadow: [
                      if (isConnected)
                        BoxShadow(
                          color: statusColor.withValues(alpha: 0.6),
                          blurRadius: 8,
                          spreadRadius: 2,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectCard(
    BuildContext context,
    WidgetRef ref, {
    required ConnectionStateEnum status,
    required List<ProxyNode> nodes,
    required ProxyNode? activeNode,
    required String locale,
    required bool isConnected,
    required bool isConnecting,
    required bool isCf,
    required bool showFullIp,
  }) {
    return Card(
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
          mainAxisAlignment: MainAxisAlignment.center,
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
                          final isTun = ref.read(isTunEnabledProvider);
                          if (!isConnected && isTun && !XrayProcessService.instance.isRunningAsAdmin()) {
                            _showAdminElevationDialog(context, locale);
                            return;
                          }
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
                      '${activeNode.name} (${IpMaskUtil.mask(activeNode.address, showFull: showFullIp)}:${activeNode.port})',
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
    );
  }

  Widget _buildIpInfoCard(
    BuildContext context,
    WidgetRef ref, {
    required OutboundInfo outbound,
    required ProxyNode? activeNode,
    required String locale,
    required bool isConnected,
    required DateTime? connectedAt,
    required bool showFullIp,
  }) {
    return Card(
      color: const Color(0xFF131824),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isConnected ? AppTheme.primaryAccent.withValues(alpha: 0.35) : const Color(0xFF1E2638),
          width: 1.2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Header Row: Icon + Title/Location + Eye Button + Refresh Button
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: (isConnected ? AppTheme.primaryAccent : Colors.grey.shade700).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.public_rounded,
                    size: 20,
                    color: isConnected ? AppTheme.primaryAccent : Colors.grey,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isConnected
                            ? AppStrings.get('connected_country', locale: locale)
                            : AppStrings.get('outbound_ip', locale: locale),
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                      if (isConnected)
                        Row(
                          children: [
                            CountryFlagBadge(countryCode: outbound.countryCode),
                            const SizedBox(width: 8),
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
                        )
                      else
                        Text(
                          AppStrings.get('offline_hint', locale: locale),
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                // Eye button to toggle mask/unmask IP
                IconButton(
                  tooltip: AppStrings.get(showFullIp ? 'hide_ip' : 'show_full_ip', locale: locale),
                  icon: Icon(
                    showFullIp ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                    size: 19,
                    color: showFullIp ? AppTheme.primaryAccent : Colors.white70,
                  ),
                  onPressed: () {
                    ref.read(showFullIpProvider.notifier).state = !showFullIp;
                  },
                ),
                // Refresh button
                IconButton(
                  tooltip: AppStrings.get('refresh_ip', locale: locale),
                  icon: outbound.isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryAccent),
                        )
                      : Icon(
                          Icons.refresh_rounded,
                          size: 18,
                          color: isConnected ? Colors.white70 : Colors.grey.shade600,
                        ),
                  onPressed: (!isConnected || outbound.isLoading)
                      ? null
                      : () => ref.read(outboundInfoProvider.notifier).fetch(),
                ),
              ],
            ),
            const Divider(height: 20, color: Colors.white12),

            // 4-Item Grid: 2 rows of 2 columns
            Row(
              children: [
                Expanded(
                  child: _buildInfoItem(
                    title: AppStrings.get('ipv4_address', locale: locale),
                    value: isConnected
                        ? (outbound.ipv4 != null
                            ? IpMaskUtil.mask(outbound.ipv4!, showFull: showFullIp)
                            : (outbound.isLoading ? '...' : '--'))
                        : '--',
                    icon: Icons.lan_rounded,
                    color: const Color(0xFF38BDF8),
                    copyable: isConnected && outbound.ipv4 != null,
                    copyValue: outbound.ipv4,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildInfoItem(
                    title: AppStrings.get('ipv6_address', locale: locale),
                    value: isConnected
                        ? (outbound.ipv6 != null
                            ? IpMaskUtil.mask(outbound.ipv6!, showFull: showFullIp)
                            : (outbound.isLoading ? '...' : AppStrings.get('not_supported', locale: locale)))
                        : '--',
                    icon: Icons.alt_route_rounded,
                    color: const Color(0xFFA78BFA),
                    copyable: isConnected && outbound.ipv6 != null,
                    copyValue: outbound.ipv6,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _buildPingItem(
                    title: AppStrings.get('ping', locale: locale),
                    latency: isConnected ? activeNode?.latencyMs : null,
                    isTesting: _isTestingPing,
                    onRetest: (isConnected && activeNode != null) ? () => _retestPing(activeNode) : null,
                    locale: locale,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildInfoItem(
                    title: AppStrings.get('connection_duration', locale: locale),
                    value: isConnected ? _formatDuration(connectedAt) : "00:00:00",
                    icon: Icons.timer_outlined,
                    color: isConnected ? AppTheme.successColor : Colors.grey,
                    copyable: false,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoItem({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required bool copyable,
    String? copyValue,
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
                    final textToCopy = copyValue ?? value;
                    Clipboard.setData(ClipboardData(text: textToCopy));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('$textToCopy copied'), duration: const Duration(seconds: 1)),
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

  void _showAdminElevationDialog(BuildContext context, String locale) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E2230),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.admin_panel_settings_rounded, color: Colors.amber, size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                AppStrings.get('tun_admin_required_title', locale: locale),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Text(
          AppStrings.get('tun_admin_required_desc', locale: locale),
          style: const TextStyle(fontSize: 13, color: Colors.white70, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(AppStrings.get('cancel', locale: locale)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryAccent,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.security_rounded, size: 18),
            label: Text(AppStrings.get('restart_as_admin', locale: locale)),
            onPressed: () async {
              Navigator.of(ctx).pop();
              await XrayProcessService.instance.restartAsAdmin();
            },
          ),
        ],
      ),
    );
  }
}


