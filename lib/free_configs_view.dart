import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/l10n/translations.dart';
import 'core/theme/app_theme.dart';
import 'models/proxy_node.dart';
import 'providers/app_providers.dart';
import 'services/cdn_scanner_service.dart';
import 'services/country_service.dart';
import 'utils/ip_mask_util.dart';
import 'widgets/country_flag_badge.dart';
import 'widgets/country_filter_bar.dart';

class FreeConfigsView extends ConsumerStatefulWidget {
  final VoidCallback? onOpenDrawer;
  const FreeConfigsView({super.key, this.onOpenDrawer});

  @override
  ConsumerState<FreeConfigsView> createState() => _FreeConfigsViewState();
}

class _FreeConfigsViewState extends ConsumerState<FreeConfigsView> {
  final TextEditingController _searchController = TextEditingController();
  String _searchFilter = '';
  String? _selectedCountryCode;
  bool _isSearchExpanded = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchFilter = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    ref.read(freeConfigsProvider.notifier).cancelScan();
    super.dispose();
  }

  Future<void> _handleConnect(ProxyNode node) async {
    final connState = ref.read(connectionStatusProvider);
    final nodes = ref.read(nodesProvider);
    final activeNode = nodes.where((n) => n.isActive).firstOrNull;

    if (connState == ConnectionStateEnum.connected && activeNode?.id == node.id) {
      await ref.read(connectionStatusProvider.notifier).toggleConnect();
    } else {
      ref.read(nodesProvider.notifier).selectAndConnectFreeNode(node);
      await ref.read(connectionStatusProvider.notifier).connect(node);
    }
  }

  @override
  Widget build(BuildContext context) {
    final freeState = ref.watch(freeConfigsProvider);
    final locale = ref.watch(currentLocaleProvider);
    final showFullIp = ref.watch(showFullIpProvider);
    final cdnMap = ref.watch(nodeCdnMapProvider);
    final connectionState = ref.watch(connectionStatusProvider);
    final outbound = ref.watch(outboundInfoProvider);
    final nodes = ref.watch(nodesProvider);
    final activeNode = nodes.where((n) => n.isActive).firstOrNull;

    final isConnected = connectionState == ConnectionStateEnum.connected;
    final isConnecting = connectionState == ConnectionStateEnum.connecting;

    final nodesToFilter = freeState.allNodes.isNotEmpty ? freeState.allNodes : freeState.workingNodes;
    final filteredNodes = nodesToFilter.where((n) {
      // 1. Country & Timeouts filter
      if (_selectedCountryCode != null) {
        if (_selectedCountryCode == '__timeouts__') {
          if (!n.hasTimedOut) return false;
        } else if (_selectedCountryCode == '__unknown__') {
          if (!n.hasValidPing || (n.countryCode != null && n.countryCode!.trim().isNotEmpty)) return false;
        } else {
          if (!n.hasValidPing || n.countryCode?.trim().toUpperCase() != _selectedCountryCode) return false;
        }
      }

      // 2. Text search filter
      if (_searchFilter.isNotEmpty) {
        final name = n.name.toLowerCase();
        final addr = n.address.toLowerCase();
        final proto = n.protocol.name.toLowerCase();
        if (!name.contains(_searchFilter) && !addr.contains(_searchFilter) && !proto.contains(_searchFilter)) {
          return false;
        }
      }
      return true;
    }).toList();

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
                    AppStrings.get('free_configs', locale: locale),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ],
              ),
              actions: [
                IconButton(
                  icon: Icon(_isSearchExpanded ? Icons.close : Icons.search, size: 20),
                  tooltip: AppStrings.get('search_nodes', locale: locale),
                  onPressed: () {
                    setState(() {
                      _isSearchExpanded = !_isSearchExpanded;
                      if (!_isSearchExpanded) {
                        _searchController.clear();
                      }
                    });
                  },
                ),
                if (freeState.isScanning)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amber),
                    ),
                    tooltip: AppStrings.get('cancel_scan', locale: locale),
                    onPressed: () => ref.read(freeConfigsProvider.notifier).cancelScan(),
                  )
                else
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.autorenew_rounded, color: AppTheme.primaryAccent),
                    tooltip: AppStrings.get('get_new_configs', locale: locale),
                    onPressed: () {
                      setState(() => _selectedCountryCode = null);
                      ref.read(freeConfigsProvider.notifier).startScan();
                    },
                  ),
                const SizedBox(width: 4),
              ],
            )
          : null,
      body: Padding(
        padding: EdgeInsets.all(Platform.isAndroid ? 12 : 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (Platform.isAndroid) ...[
              if (_isSearchExpanded) ...[
                SizedBox(
                  height: 38,
                  child: TextField(
                    controller: _searchController,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: AppStrings.get('search_nodes', locale: locale),
                      prefixIcon: const Icon(Icons.search, size: 16),
                      suffixIcon: _searchFilter.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 14),
                              onPressed: () => _searchController.clear(),
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ] else
              // Top Bar for Desktop
              LayoutBuilder(
                builder: (context, constraints) {

                final isNarrow = constraints.maxWidth < 600;
                final titleCol = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.card_giftcard_rounded, color: AppTheme.primaryAccent, size: 24),
                        const SizedBox(width: 8),
                        Text(
                          AppStrings.get('free_configs', locale: locale),
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      AppStrings.get('free_configs_desc', locale: locale),
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                    ),
                  ],
                );

                final actionBtn = freeState.isScanning
                    ? OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.amber, width: 1.5),
                        ),
                        icon: const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amber),
                        ),
                        label: Text(
                          AppStrings.get('cancel_scan', locale: locale),
                          style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold),
                        ),
                        onPressed: () => ref.read(freeConfigsProvider.notifier).cancelScan(),
                      )
                    : FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.primaryAccent,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                        icon: const Icon(Icons.autorenew_rounded, size: 18),
                        label: Text(
                          AppStrings.get('get_new_configs', locale: locale),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        onPressed: () {
                          setState(() => _selectedCountryCode = null);
                          ref.read(freeConfigsProvider.notifier).startScan();
                        },
                      );

                if (isNarrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      titleCol,
                      const SizedBox(height: 12),
                      Align(alignment: Alignment.centerLeft, child: actionBtn),
                    ],
                  );
                }

                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    titleCol,
                    actionBtn,
                  ],
                );
              },
            ),
            const SizedBox(height: 16),

            // Metrics / Stats Dashboard Cards
            _buildStatsDashboard(freeState, locale),
            const SizedBox(height: 16),

            // Scanning progress banner (if active)
            if (freeState.isScanning) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.amber),
                            ),
                            const SizedBox(width: 10),
                            Flexible(
                              child: Text(
                                Platform.isAndroid
                                    ? (freeState.status == 'fetching'
                                        ? (locale == 'fa' ? 'درحال دریافت...' : 'Fetching...')
                                        : (locale == 'fa' ? 'درحال تست...' : 'Testing...'))
                                    : (freeState.status == 'fetching'
                                        ? AppStrings.get('scanning_free_subs', locale: locale)
                                        : AppStrings.get('testing_real_delay_batch', locale: locale)),
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${freeState.testedCandidates} / ${freeState.totalUnique} (${(freeState.progress * 100).toInt()}%)',
                              style: const TextStyle(
                                color: Colors.amber,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                            if (freeState.estimatedRemainingTime != null)
                              Text(
                                '${AppStrings.get('estimated_remaining_time', locale: locale)}: ${freeState.estimatedRemainingTime}',
                                style: TextStyle(
                                  color: Colors.amber.shade200,
                                  fontSize: 11,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: freeState.progress > 0 ? freeState.progress : null,
                        minHeight: 6,
                        backgroundColor: Colors.white10,
                        color: Colors.amber,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Country Filter Bar (based on real tested countries and timeouts)
            if (nodesToFilter.isNotEmpty)
              CountryFilterBar(
                nodes: nodesToFilter,
                selectedCountryCode: _selectedCountryCode,
                onCountrySelected: (code) => setState(() => _selectedCountryCode = code),
                locale: locale,
              ),

            // Search filter if nodes present (Desktop/Windows only; Android uses search icon in top bar)
            if (!Platform.isAndroid && nodesToFilter.isNotEmpty) ...[
              SizedBox(
                height: 42,
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: AppStrings.get('search_nodes', locale: locale),
                    prefixIcon: const Icon(Icons.search, size: 18),
                    suffixIcon: _searchFilter.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 16),
                            onPressed: () => _searchController.clear(),
                          )
                        : null,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                  ),
                ),
              ),
              const SizedBox(height: 14),
            ],

            // Content List
            Expanded(
              child: nodesToFilter.isEmpty && !freeState.isScanning
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.wifi_off_rounded, size: 64, color: Colors.grey.shade700),
                          const SizedBox(height: 16),
                          Text(
                            AppStrings.get('no_free_configs_yet', locale: locale),
                            style: const TextStyle(color: Colors.grey, fontSize: 14),
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(backgroundColor: AppTheme.primaryAccent),
                            icon: const Icon(Icons.autorenew_rounded, size: 18),
                            label: Text(AppStrings.get('get_new_configs', locale: locale)),
                            onPressed: () => ref.read(freeConfigsProvider.notifier).startScan(),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      itemCount: filteredNodes.length,
                      separatorBuilder: (c, i) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final node = filteredNodes[index];
                        final isThisNodeActive = activeNode?.id == node.id ||
                            (activeNode != null &&
                                activeNode.address == node.address &&
                                activeNode.port == node.port &&
                                activeNode.uuidOrPassword == node.uuidOrPassword);

                        final isThisNodeConnected = isConnected && isThisNodeActive;
                        final isThisNodeConnecting = isConnecting && isThisNodeActive;

                        final displayCountryCode = isThisNodeConnected
                            ? (outbound.countryCode ?? node.countryCode ?? CountryService.resolveSync(node))
                            : (node.countryCode ?? CountryService.resolveSync(node));
                        final displayCountry = isThisNodeConnected
                            ? (outbound.country ?? node.country ?? (displayCountryCode != null ? CountryService.getCountryName(displayCountryCode) : null))
                            : (node.country ?? (displayCountryCode != null ? CountryService.getCountryName(displayCountryCode) : null));

                        final cdn = cdnMap[node.address.trim().toLowerCase()] ??
                            ref.read(nodeCdnMapProvider.notifier).detectCdn(node.address);

                        return Card(
                          margin: Platform.isAndroid ? EdgeInsets.zero : const EdgeInsets.symmetric(vertical: 4),
                          elevation: Platform.isAndroid ? (isThisNodeActive ? 2 : 0) : null,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(Platform.isAndroid ? 12 : 10),
                            side: Platform.isAndroid
                                ? (isThisNodeActive
                                    ? const BorderSide(color: AppTheme.primaryAccent, width: 2.0)
                                    : BorderSide(color: Colors.white.withValues(alpha: 0.08), width: 1.0))
                                : BorderSide(
                                    color: isThisNodeConnected
                                        ? AppTheme.primaryAccent
                                        : (isThisNodeActive ? Colors.cyanAccent.withValues(alpha: 0.5) : Colors.transparent),
                                    width: isThisNodeConnected ? 1.5 : 1,
                                  ),
                          ),
                          color: Platform.isAndroid
                              ? (isThisNodeActive
                                  ? AppTheme.primaryAccent.withValues(alpha: 0.08)
                                  : Theme.of(context).cardColor)
                              : null,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(Platform.isAndroid ? 12 : 10),
                            onTap: () => _handleConnect(node),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              child: Row(
                                children: [
                                  // Active Indicator (Desktop only)
                                  if (!Platform.isAndroid) ...[
                                    Icon(
                                      isThisNodeConnected
                                          ? Icons.radio_button_checked
                                          : (isThisNodeActive ? Icons.radio_button_checked : Icons.radio_button_off),
                                      color: isThisNodeConnected ? AppTheme.primaryAccent : Colors.grey,
                                      size: 22,
                                    ),
                                    const SizedBox(width: 12),
                                  ],

                                  // Country Flag / Unknown Pill Badge
                                  CountryPillBadge(
                                    countryCode: displayCountryCode,
                                    country: displayCountry,
                                    showUnknown: true,
                                  ),
                                  const SizedBox(width: 10),

                                  // Node Details
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Flexible(
                                              child: Text(
                                                node.name,
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 13,
                                                  color: isThisNodeConnected ? AppTheme.primaryAccent : null,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            if (cdn != null) ...[
                                              const SizedBox(width: 6),
                                              CdnBadge(cdn: cdn),
                                            ],
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${IpMaskUtil.mask(node.address, showFull: showFullIp)}:${node.port}  •  ${node.protocol.name.toUpperCase()}  •  ${node.network.name.toUpperCase()}',
                                          style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),

                                  // Real Delay Latency Badge
                                  if (node.hasValidPing)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: AppTheme.successColor.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        '${node.latencyMs} ms',
                                        style: const TextStyle(
                                          color: AppTheme.successColor,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  const SizedBox(width: 8),

                                  // Connect Action Button
                                  if (isThisNodeConnecting)
                                    const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  else
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: isThisNodeConnected ? Colors.redAccent.shade700 : AppTheme.primaryAccent,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                        visualDensity: VisualDensity.compact,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                      ),
                                      onPressed: () => _handleConnect(node),
                                      child: Text(
                                        isThisNodeConnected
                                            ? AppStrings.get('disconnect', locale: locale)
                                            : AppStrings.get('connect', locale: locale),
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                ],
                              ),
                            ),
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

  Widget _buildStatsDashboard(FreeConfigsState state, String locale) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final card1 = _buildStatCard(
          icon: Icons.cloud_download_rounded,
          iconColor: Colors.blueAccent,
          label: AppStrings.get('total_candidates', locale: locale),
          value: state.totalScraped > 0 ? '${state.totalScraped}' : (state.workingNodes.isNotEmpty ? '${state.workingNodes.length}' : '0'),
        );
        final card2 = _buildStatCard(
          icon: Icons.filter_alt_rounded,
          iconColor: Colors.purpleAccent,
          label: AppStrings.get('unique_candidates', locale: locale),
          value: state.totalUnique > 0 ? '${state.totalUnique}' : (state.workingNodes.isNotEmpty ? '${state.workingNodes.length}' : '0'),
        );
        final card3 = _buildStatCard(
          icon: Icons.speed_rounded,
          iconColor: Colors.amber,
          label: AppStrings.get('tested_count', locale: locale),
          value: state.testedCandidates > 0 ? '${state.testedCandidates}' : (state.workingNodes.isNotEmpty ? '${state.workingNodes.length}' : '0'),
        );
        final card4 = _buildStatCard(
          icon: Icons.check_circle_rounded,
          iconColor: AppTheme.successColor,
          label: AppStrings.get('responsive_configs_count', locale: locale),
          value: '${state.workingNodes.length}',
          highlightColor: AppTheme.successColor,
        );
        final card5 = _buildStatCard(
          icon: Icons.cancel_rounded,
          iconColor: Colors.redAccent,
          label: AppStrings.get('failed_timeout_count', locale: locale),
          value: '${state.failedCount}',
          highlightColor: state.failedCount > 0 ? Colors.redAccent : null,
        );

        if (Platform.isAndroid || constraints.maxWidth < 700) {
          final spacing = Platform.isAndroid ? 6.0 : 8.0;
          return Column(
            children: [
              Row(children: [card1, SizedBox(width: spacing), card2]),
              SizedBox(height: spacing),
              Row(children: [card3, SizedBox(width: spacing), card4]),
              SizedBox(height: spacing),
              Row(children: [card5]),
            ],
          );
        }

        return Row(
          children: [
            card1,
            const SizedBox(width: 10),
            card2,
            const SizedBox(width: 10),
            card3,
            const SizedBox(width: 10),
            card4,
            const SizedBox(width: 10),
            card5,
          ],
        );
      },
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    Color? highlightColor,
  }) {
    final isAndroid = Platform.isAndroid;
    return Expanded(
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isAndroid ? 8 : 12,
          vertical: isAndroid ? 6 : 10,
        ),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(isAndroid ? 8 : 10),
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(isAndroid ? 5 : 7),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(isAndroid ? 6 : 8),
              ),
              child: Icon(icon, size: isAndroid ? 14 : 18, color: iconColor),
            ),
            SizedBox(width: isAndroid ? 6 : 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: isAndroid ? 9.5 : 10.5,
                      color: Colors.grey.shade400,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: isAndroid ? 1 : 2),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: isAndroid ? 13 : 15,
                      fontWeight: FontWeight.bold,
                      color: highlightColor ?? Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
