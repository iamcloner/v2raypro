import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/l10n/translations.dart';
import 'core/theme/app_theme.dart';
import 'models/proxy_node.dart';
import 'providers/app_providers.dart';
import 'services/cdn_scanner_service.dart';
import 'utils/ip_mask_util.dart';
import 'widgets/country_flag_badge.dart';

class FreeConfigsView extends ConsumerStatefulWidget {
  const FreeConfigsView({super.key});

  @override
  ConsumerState<FreeConfigsView> createState() => _FreeConfigsViewState();
}

class _FreeConfigsViewState extends ConsumerState<FreeConfigsView> {
  final TextEditingController _searchController = TextEditingController();
  String _searchFilter = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchFilter = _searchController.text.trim().toLowerCase();
      });
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = ref.read(freeConfigsProvider);
      if (state.workingNodes.isEmpty && !state.isScanning) {
        ref.read(freeConfigsProvider.notifier).startScan();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _handleConnect(ProxyNode node) async {
    final connState = ref.read(connectionStatusProvider);
    final nodes = ref.read(nodesProvider);
    final activeNode = nodes.where((n) => n.isActive).firstOrNull;

    if (connState == ConnectionStateEnum.connected && activeNode?.id == node.id) {
      // Toggle disconnect
      await ref.read(connectionStatusProvider.notifier).toggleConnect();
    } else {
      // Select and connect
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
    final nodes = ref.watch(nodesProvider);
    final activeNode = nodes.where((n) => n.isActive).firstOrNull;

    final isConnected = connectionState == ConnectionStateEnum.connected;
    final isConnecting = connectionState == ConnectionStateEnum.connecting;

    final filteredNodes = freeState.workingNodes.where((n) {
      if (_searchFilter.isEmpty) return true;
      final name = n.name.toLowerCase();
      final addr = n.address.toLowerCase();
      final proto = n.protocol.name.toLowerCase();
      return name.contains(_searchFilter) || addr.contains(_searchFilter) || proto.contains(_searchFilter);
    }).toList();

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Bar
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
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
                ),
                Row(
                  children: [
                    if (freeState.isScanning)
                      OutlinedButton.icon(
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
                    else
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.primaryAccent,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                        icon: const Icon(Icons.autorenew_rounded, size: 18),
                        label: Text(
                          AppStrings.get('get_new_configs', locale: locale),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        onPressed: () => ref.read(freeConfigsProvider.notifier).startScan(),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Scanning progress banner
            if (freeState.isScanning) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF161C2C),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.amber.withValues(alpha: 0.4), width: 1),
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
                            Text(
                              freeState.status == 'fetching'
                                  ? AppStrings.get('scanning_free_subs', locale: locale)
                                  : AppStrings.get('testing_real_delay_batch', locale: locale),
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ],
                        ),
                        Text(
                          AppStrings.get('found_of_target', locale: locale)
                              .replaceAll('{count}', freeState.workingNodes.length.toString())
                              .replaceAll('{target}', freeState.targetCount.toString()),
                          style: const TextStyle(
                            color: Colors.amber,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
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
            ] else if (freeState.workingNodes.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.successColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.successColor.withValues(alpha: 0.25), width: 0.8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_rounded, size: 16, color: AppTheme.successColor),
                    const SizedBox(width: 8),
                    Text(
                      AppStrings.get('free_configs_ready', locale: locale)
                          .replaceAll('{count}', freeState.workingNodes.length.toString()),
                      style: const TextStyle(
                        color: AppTheme.successColor,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Search filter if nodes present
            if (freeState.workingNodes.isNotEmpty) ...[
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
              child: freeState.workingNodes.isEmpty && !freeState.isScanning
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

                        final cdn = cdnMap[node.address.trim().toLowerCase()] ??
                            ref.read(nodeCdnMapProvider.notifier).detectCdn(node.address);

                        return Card(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(
                              color: isThisNodeConnected
                                  ? AppTheme.primaryAccent
                                  : (isThisNodeActive ? Colors.cyanAccent.withValues(alpha: 0.5) : Colors.transparent),
                              width: isThisNodeConnected ? 1.5 : 1,
                            ),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () => _handleConnect(node),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              child: Row(
                                children: [
                                  // Active Indicator
                                  Icon(
                                    isThisNodeConnected
                                        ? Icons.radio_button_checked
                                        : (isThisNodeActive ? Icons.radio_button_checked : Icons.radio_button_off),
                                    color: isThisNodeConnected ? AppTheme.primaryAccent : Colors.grey,
                                    size: 22,
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

                                  // Latency Badge
                                  if (node.hasValidPing)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: AppTheme.successColor.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: AppTheme.successColor.withValues(alpha: 0.3),
                                          width: 0.8,
                                        ),
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
                                  const SizedBox(width: 12),

                                  // Connect Action Button (NO Edit, NO Share)
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
}
