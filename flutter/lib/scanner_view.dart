import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/l10n/translations.dart';
import 'core/theme/app_theme.dart';
import 'models/scan_result.dart';
import 'providers/app_providers.dart';
import 'services/cdn_scanner_service.dart';
import 'services/cloudflare_scanner_service.dart';

class ScannerView extends ConsumerStatefulWidget {
  const ScannerView({super.key});

  @override
  ConsumerState<ScannerView> createState() => _ScannerViewState();
}

class _ScannerViewState extends ConsumerState<ScannerView>
    with SingleTickerProviderStateMixin {
  double _workers = 20.0;
  double _targetTotal = 500.0;
  String _searchQuery = '';
  bool _showStrategyInfo = false;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    _pulseAnimation = Tween<double>(begin: 0.9, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(scannerProvider);
    final nodes = ref.watch(nodesProvider);
    final activeNode = nodes.isEmpty
        ? null
        : nodes.firstWhere((n) => n.isActive, orElse: () => nodes.first);
    final locale = ref.watch(currentLocaleProvider);
    final cdnMap = ref.watch(nodeCdnMapProvider);
    final detectedCdn = activeNode != null
        ? (cdnMap[activeNode.address.trim().toLowerCase()] ??
            ref.read(nodeCdnMapProvider.notifier).detectCdn(activeNode.address))
        : null;

    if (detectedCdn != null && state.selectedCdn != detectedCdn && !state.isScanning) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(scannerProvider.notifier).setSelectedCdn(detectedCdn);
        }
      });
    }

    final currentCdn = state.selectedCdn;

    // Keep sliders in sync with provider if not editing
    if (!state.isScanning) {
      if (_workers.round() != state.workers) {
        _workers = state.workers.toDouble();
      }
      if (_targetTotal.round() != state.targetTotalCandidates) {
        _targetTotal = state.targetTotalCandidates.toDouble();
      }
    }

    // Handle radar animation
    if (state.isScanning && state.strategy == ScannerStrategy.radar) {
      if (!_pulseController.isAnimating) {
        _pulseController.repeat(reverse: true);
      }
    } else {
      if (_pulseController.isAnimating) {
        _pulseController.stop();
        _pulseController.reset();
      }
    }

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Target Node Info Header with Reset & Restore Buttons
            _buildNodeHeaderCard(activeNode, currentCdn, detectedCdn, locale),
            const SizedBox(height: 16),

            // Metrics / Stats Dashboard Card
            _buildScannerStatsDashboard(state, locale),
            const SizedBox(height: 16),

            // 2. Strategy Switcher with Info Guide Button
            _buildStrategySelector(state, locale),
            const SizedBox(height: 16),

            // 3. Scan Concurrency Slider & Action Controls
            _buildControlsCard(state, activeNode, locale),
            const SizedBox(height: 16),

            // 4. Progress Indicator (only while active scanning)
            if (state.isScanning) ...[
              _buildProgressCard(state, locale),
              const SizedBox(height: 16),
            ],

            // 5. Strategy Specific View (Radar or Target)
            if (state.strategy == ScannerStrategy.radar)
              _buildRadarView(state, activeNode, locale)
            else
              _buildTargetView(state, activeNode, locale),
          ],
        ),
      ),
    );
  }

  Widget _buildNodeHeaderCard(
    dynamic activeNode,
    CdnProvider currentCdn,
    CdnProvider? detectedCdn,
    String locale,
  ) {
    final origAddr = activeNode?.originalAddress ?? activeNode?.address;
    final isDomain = origAddr != null &&
        !origAddr.toString().contains(RegExp(r'^\d+\.\d+\.\d+\.\d+$'));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.speed_rounded,
                        color: AppTheme.primaryAccent, size: 22),
                    const SizedBox(width: 8),
                    Text(
                      locale == 'fa' ? 'اسکنر ${currentCdn.displayNameFa}' : '${currentCdn.displayName} Scanner',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                Row(
                  children: [
                    // Reset Scan Button
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.grey.shade300,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                      ),
                      icon: const Icon(Icons.restart_alt_rounded, size: 16),
                      label: Text(
                        AppStrings.get('reset_scan', locale: locale),
                        style: const TextStyle(fontSize: 12),
                      ),
                      onPressed: () {
                        ref.read(scannerProvider.notifier).resetScan();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                                AppStrings.get('scan_reset_done', locale: locale)),
                          ),
                        );
                      },
                    ),
                    if (activeNode?.originalAddress != null) ...[
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                        ),
                        icon: const Icon(Icons.restore_rounded, size: 16),
                        label: Text(
                          AppStrings.get('restore_original', locale: locale),
                          style: const TextStyle(fontSize: 12),
                        ),
                        onPressed: () {
                          ref
                              .read(nodesProvider.notifier)
                              .restoreAddress(activeNode!.id);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text(AppStrings.get('original_restored',
                                    locale: locale))),
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Target CDN Selection Chips
            Row(
              children: [
                Text(
                  '${AppStrings.get('cdn_select', locale: locale)}: ',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: CdnProvider.values.map((cdn) {
                        final isSelected = cdn == currentCdn;
                        final isDetected = cdn == detectedCdn;
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isDetected) ...[
                                  const Icon(Icons.check_circle_rounded,
                                      size: 13, color: Colors.greenAccent),
                                  const SizedBox(width: 4),
                                ],
                                Text(locale == 'fa'
                                    ? cdn.displayNameFa
                                    : cdn.displayName),
                              ],
                            ),
                            selected: isSelected,
                            selectedColor: AppTheme.primaryAccent.withValues(alpha: 0.3),
                            onSelected: ref.watch(scannerProvider).isScanning
                                ? null
                                : (selected) {
                                    if (selected) {
                                      ref
                                          .read(scannerProvider.notifier)
                                          .setSelectedCdn(cdn);
                                    }
                                  },
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Flexible(
                  child: Text(
                    activeNode == null
                        ? AppStrings.get('no_nodes', locale: locale)
                        : (activeNode.originalAddress != null
                            ? '${activeNode.name} • ${activeNode.originalAddress} -> ${activeNode.address}'
                            : (isDomain
                                ? '${activeNode.name} (${activeNode.address})'
                                : '${activeNode.name} (${activeNode.address})')),
                    style: const TextStyle(color: Colors.grey, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (detectedCdn != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.greenAccent.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.greenAccent, width: 0.8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.check_circle_outline_rounded,
                            size: 12, color: Colors.greenAccent),
                        const SizedBox(width: 3),
                        Text(
                          detectedCdn.displayName,
                          style: const TextStyle(
                            color: Colors.greenAccent,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            if (activeNode != null && isDomain) ...[
              const SizedBox(height: 8),
              Text(
                '${AppStrings.get('domain_detected', locale: locale)}: ${currentCdn.displayName} (SNI & Host preserved)',
                style: const TextStyle(color: Colors.cyanAccent, fontSize: 11),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStrategySelector(ScannerState state, String locale) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: SegmentedButton<ScannerStrategy>(
                    segments: [
                      ButtonSegment<ScannerStrategy>(
                        value: ScannerStrategy.radar,
                        icon: const Icon(Icons.radar_rounded),
                        label: Text(
                          AppStrings.get('radar', locale: locale),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      ButtonSegment<ScannerStrategy>(
                        value: ScannerStrategy.target,
                        icon: const Icon(Icons.track_changes_rounded),
                        label: Text(
                          AppStrings.get('target', locale: locale),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                    selected: {state.strategy},
                    onSelectionChanged: state.isScanning
                        ? null
                        : (selection) {
                            ref
                                .read(scannerProvider.notifier)
                                .setStrategy(selection.first);
                          },
                  ),
                ),
                const SizedBox(width: 10),
                // Strategy Explanation Guide Button
                IconButton.filledTonal(
                  icon: Icon(
                    _showStrategyInfo
                        ? Icons.info_rounded
                        : Icons.info_outline_rounded,
                    color: AppTheme.primaryAccent,
                  ),
                  tooltip: AppStrings.get('strategy_info_tooltip', locale: locale),
                  onPressed: () {
                    setState(() => _showStrategyInfo = !_showStrategyInfo);
                  },
                ),
              ],
            ),
            // Expandable Strategy Explanation Box
            if (_showStrategyInfo) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.primaryAccent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppTheme.primaryAccent.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.radar_rounded,
                            size: 18, color: AppTheme.primaryAccent),
                        const SizedBox(width: 6),
                        Text(
                          AppStrings.get('radar_how_it_works', locale: locale),
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: AppTheme.primaryAccent),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      AppStrings.get('radar_full_desc', locale: locale),
                      style:
                          const TextStyle(color: Colors.grey, fontSize: 12, height: 1.4),
                    ),
                    const Divider(height: 16, color: Colors.white12),
                    Row(
                      children: [
                        const Icon(Icons.track_changes_rounded,
                            size: 18, color: Colors.amber),
                        const SizedBox(width: 6),
                        Text(
                          AppStrings.get('target_how_it_works', locale: locale),
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: Colors.amber),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      AppStrings.get('target_full_desc', locale: locale),
                      style:
                          const TextStyle(color: Colors.grey, fontSize: 12, height: 1.4),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildControlsCard(
      ScannerState state, dynamic activeNode, String locale) {
    final isRadar = state.strategy == ScannerStrategy.radar;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.tune_rounded,
                            size: 18, color: Colors.grey),
                        const SizedBox(width: 6),
                        Text(
                          AppStrings.get('concurrent_workers', locale: locale),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      AppStrings.get('concurrent_workers_hint', locale: locale),
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppTheme.primaryAccent.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    '${_workers.round()} Threads',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryAccent,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: AppTheme.primaryAccent,
                thumbColor: AppTheme.primaryAccent,
                overlayColor: AppTheme.primaryAccent.withValues(alpha: 0.2),
              ),
              child: Slider(
                value: _workers,
                min: 5.0,
                max: 100.0,
                divisions: 19,
                label: '${_workers.round()}',
                onChanged: state.isScanning
                    ? null
                    : (val) {
                        setState(() => _workers = val);
                        ref
                            .read(scannerProvider.notifier)
                            .setWorkers(val.round());
                      },
              ),
            ),
            // Target Mode: Total Candidates Slider (200 to 10,000)
            if (!isRadar) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.hub_rounded,
                              size: 18, color: Colors.amber),
                          const SizedBox(width: 6),
                          Text(
                            AppStrings.get('target_total_count', locale: locale),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        AppStrings.get('target_total_hint', locale: locale),
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: Colors.amber.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      '${_targetTotal.round()} IPs',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                        color: Colors.amber,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: Colors.amber,
                  thumbColor: Colors.amber,
                  overlayColor: Colors.amber.withValues(alpha: 0.2),
                ),
                child: Slider(
                  value: _targetTotal,
                  min: 200.0,
                  max: 10000.0,
                  divisions: 49,
                  label: '${_targetTotal.round()}',
                  onChanged: state.isScanning
                      ? null
                      : (val) {
                          setState(() => _targetTotal = val);
                          ref
                              .read(scannerProvider.notifier)
                              .setTargetTotalCandidates(val.round());
                        },
                ),
              ),
            ] else ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.primaryAccent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: AppTheme.primaryAccent.withValues(alpha: 0.25)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.all_inclusive_rounded,
                        size: 18, color: AppTheme.primaryAccent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        AppStrings.get('radar_infinite_notice', locale: locale),
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: state.isScanning
                          ? AppTheme.errorColor
                          : AppTheme.primaryAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: Icon(
                      state.isScanning
                          ? Icons.stop_circle_rounded
                          : (isRadar
                              ? Icons.radar_rounded
                              : Icons.search_rounded),
                    ),
                    label: Text(
                      state.isScanning
                          ? (isRadar
                              ? AppStrings.get('stop_radar', locale: locale)
                              : AppStrings.get('stop_target', locale: locale))
                          : (isRadar
                              ? AppStrings.get('start_radar', locale: locale)
                              : AppStrings.get('start_target', locale: locale)),
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    onPressed: (activeNode == null)
                        ? null
                        : () {
                            if (state.isScanning) {
                              ref.read(scannerProvider.notifier).cancelScan();
                            } else {
                              ref.read(scannerProvider.notifier).startScan();
                            }
                          },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressCard(ScannerState state, String locale) {
    final isRadar = state.strategy == ScannerStrategy.radar;
    final progress = (state.total > 0 && !isRadar)
        ? (state.scanned / state.total).clamp(0.0, 1.0)
        : null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isRadar
                      ? '${AppStrings.get(state.isScanning ? 'scanning' : 'scan_finished', locale: locale)} (${AppStrings.get('scanned_count_label', locale: locale)}: ${state.scanned})'
                      : '${AppStrings.get(state.isScanning ? 'scanning' : 'scan_finished', locale: locale)} (${state.scanned} / ${state.total})',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (state.currentIp.isNotEmpty)
                  Text(
                    state.currentIp,
                    style: const TextStyle(
                      color: AppTheme.primaryAccent,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: Colors.grey.shade800,
                valueColor: const AlwaysStoppedAnimation(AppTheme.primaryAccent),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRadarTrafficWarningCard(BuildContext context, String locale) {
    return Card(
      color: Colors.amber.shade900.withValues(alpha: 0.2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Colors.amber, width: 1.2),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    AppStrings.get('radar_traffic_warning', locale: locale),
                    style: const TextStyle(
                      color: Colors.amber,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () {
                    ref.read(scannerProvider.notifier).dismissRadarWarning();
                  },
                  child: Text(
                    AppStrings.get('dismiss', locale: locale),
                    style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber.shade700,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.stop_rounded, size: 16),
                  label: Text(
                    AppStrings.get('stop_radar', locale: locale),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  onPressed: () {
                    ref.read(scannerProvider.notifier).cancelScan();
                    ref.read(scannerProvider.notifier).dismissRadarWarning();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRadarView(
      ScannerState state, dynamic activeNode, String locale) {
    final hasConnectedIp =
        state.connectedIp != null && state.currentBestLatency != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.showRadarTrafficWarning) ...[
          _buildRadarTrafficWarningCard(context, locale),
          const SizedBox(height: 14),
        ],
        // Live Radar Active Display Card
        Card(
          color: hasConnectedIp
              ? AppTheme.primaryAccent.withValues(alpha: 0.12)
              : const Color(0xFF161B26),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: hasConnectedIp
                  ? AppTheme.primaryAccent
                  : Colors.grey.shade800,
              width: hasConnectedIp ? 1.5 : 1.0,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              children: [
                ScaleTransition(
                  scale: (state.isScanning &&
                          state.strategy == ScannerStrategy.radar)
                      ? _pulseAnimation
                      : const AlwaysStoppedAnimation(1.0),
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: (hasConnectedIp
                              ? AppTheme.successColor
                              : (state.isScanning
                                  ? AppTheme.primaryAccent
                                  : Colors.grey))
                          .withValues(alpha: 0.2),
                    ),
                    child: Icon(
                      Icons.radar_rounded,
                      size: 50,
                      color: hasConnectedIp
                          ? AppTheme.successColor
                          : (state.isScanning
                              ? AppTheme.primaryAccent
                              : Colors.grey),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (hasConnectedIp) ...[
                  Text(
                    AppStrings.get('current_active_ip', locale: locale),
                    style: const TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    state.connectedIp!,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppTheme.successColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppTheme.successColor),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.bolt_rounded,
                            color: AppTheme.successColor, size: 16),
                        const SizedBox(width: 4),
                        Text(
                          '${state.currentBestLatency} ms  •  ${AppStrings.get('connected', locale: locale)}',
                          style: const TextStyle(
                            color: AppTheme.successColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  Text(
                    state.isScanning
                        ? AppStrings.get('searching_clean_ip', locale: locale)
                        : AppStrings.get('radar_ready', locale: locale),
                    style: TextStyle(
                      color: state.isScanning
                          ? AppTheme.primaryAccent
                          : Colors.grey,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    state.isScanning
                        ? AppStrings.get('radar_first_connect_hint', locale: locale)
                        : AppStrings.get('radar_start_prompt', locale: locale),
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Radar Improvement Timeline Card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.history_rounded,
                            size: 20, color: AppTheme.primaryAccent),
                        const SizedBox(width: 8),
                        Text(
                          AppStrings.get('radar_history', locale: locale),
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade800,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${state.radarLogs.length}',
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (state.radarLogs.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: Text(
                        state.isScanning
                            ? AppStrings.get('scanning_subnets', locale: locale)
                            : AppStrings.get('no_improvements_yet', locale: locale),
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: state.radarLogs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final log = state.radarLogs[index];
                      final isFirst = index == state.radarLogs.length - 1;
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: index == 0
                              ? AppTheme.primaryAccent.withValues(alpha: 0.1)
                              : const Color(0xFF131722),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: index == 0
                                ? AppTheme.primaryAccent.withValues(alpha: 0.4)
                                : Colors.grey.shade800,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              index == 0
                                  ? Icons.star_rounded
                                  : Icons.trending_down_rounded,
                              color: index == 0
                                  ? Colors.amber
                                  : AppTheme.successColor,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    log.ip,
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    isFirst
                                        ? AppStrings.get('initial_connection',
                                            locale: locale)
                                        : (log.improvementMs != null
                                            ? '${log.improvementMs} ms ${AppStrings.get('latency_improved', locale: locale)}'
                                            : AppStrings.get('latency_improved',
                                                locale: locale)),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: index == 0
                                          ? AppTheme.primaryAccent
                                          : Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color:
                                    AppTheme.successColor.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${log.latencyMs} ms',
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.successColor,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Discovered Responsive IPs in Radar Mode (Manual Switch Available)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.dns_rounded,
                            size: 20, color: AppTheme.successColor),
                        const SizedBox(width: 8),
                        Text(
                          AppStrings.get('radar_discovered_ips', locale: locale),
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.successColor.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: AppTheme.successColor.withValues(alpha: 0.4)),
                      ),
                      child: Text(
                        '${state.results.length}',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.successColor),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  AppStrings.get('radar_discovered_ips_hint', locale: locale),
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 14),
                if (state.results.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: Text(
                        state.isScanning
                            ? AppStrings.get('scanning_subnets', locale: locale)
                            : AppStrings.get('no_responsive_ips', locale: locale),
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: state.results.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final res = state.results[index];
                      return _buildTargetResultCard(
                        res,
                        index,
                        locale,
                        connectedIp: state.connectedIp,
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTargetView(
      ScannerState state, dynamic activeNode, String locale) {
    final filtered = state.results.where((r) {
      if (_searchQuery.isNotEmpty && !r.ip.contains(_searchQuery)) return false;
      return true;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                decoration: InputDecoration(
                  hintText: AppStrings.get('filter_ip_hint', locale: locale),
                  prefixIcon: const Icon(Icons.search, size: 20),
                  filled: true,
                  fillColor: const Color(0xFF171C28),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                onChanged: (val) => setState(() => _searchQuery = val),
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF171C28),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${filtered.length} ${AppStrings.get('responsive_count', locale: locale)}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: Text(
                state.isScanning
                    ? AppStrings.get('target_active', locale: locale)
                    : AppStrings.get('no_responsive_ips', locale: locale),
                style: const TextStyle(color: Colors.grey),
              ),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: filtered.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final res = filtered[index];
              return _buildTargetResultCard(
                res,
                index,
                locale,
                connectedIp: state.connectedIp,
              );
            },
          ),
      ],
    );
  }

  Widget _buildTargetResultCard(
    ScanResult res,
    int index,
    String locale, {
    String? connectedIp,
  }) {
    final lat = res.totalLatencyMs ?? res.tcpLatencyMs ?? 0;
    final isTop = index == 0;
    final isConnected = connectedIp != null && res.ip == connectedIp;

    Color badgeColor;
    if (lat < 120) {
      badgeColor = AppTheme.successColor;
    } else if (lat < 250) {
      badgeColor = Colors.amber;
    } else {
      badgeColor = AppTheme.errorColor;
    }

    return Card(
      color: isConnected
          ? AppTheme.successColor.withValues(alpha: 0.08)
          : (isTop
              ? AppTheme.primaryAccent.withValues(alpha: 0.08)
              : const Color(0xFF161B26)),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isConnected
              ? AppTheme.successColor.withValues(alpha: 0.7)
              : (isTop
                  ? AppTheme.primaryAccent.withValues(alpha: 0.5)
                  : Colors.grey.shade800),
          width: (isConnected || isTop) ? 1.2 : 0.8,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isConnected
                    ? AppTheme.successColor.withValues(alpha: 0.2)
                    : (isTop
                        ? Colors.amber.withValues(alpha: 0.2)
                        : Colors.grey.shade800),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '#${index + 1}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: isConnected
                      ? AppTheme.successColor
                      : (isTop ? Colors.amber : Colors.grey.shade300),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        res.ip,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      if (isConnected) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.successColor.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.check_circle_rounded,
                                  size: 11, color: AppTheme.successColor),
                              const SizedBox(width: 3),
                              Text(
                                AppStrings.get('currently_active', locale: locale),
                                style: const TextStyle(
                                  color: AppTheme.successColor,
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
                  const SizedBox(height: 2),
                  Text(
                    '${AppStrings.get('server_port', locale: locale)}: ${res.port}  •  ${res.latencyTier}',
                    style: const TextStyle(color: Colors.grey, fontSize: 11),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: badgeColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: badgeColor.withValues(alpha: 0.4)),
              ),
              child: Text(
                '$lat ms',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                  color: badgeColor,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.copy_rounded, size: 18),
              tooltip: AppStrings.get('copy_ip', locale: locale),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: res.ip));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content:
                          Text(AppStrings.get('ip_copied', locale: locale))),
                );
              },
            ),
            if (isConnected)
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.successColor.withValues(alpha: 0.25),
                  foregroundColor: AppTheme.successColor,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                ),
                icon: const Icon(Icons.check_rounded, size: 16),
                label: Text(
                  AppStrings.get('currently_active', locale: locale),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                onPressed: null,
              )
            else
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primaryAccent,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.swap_horiz_rounded, size: 16),
                label: Text(
                  AppStrings.get('switch_ip', locale: locale),
                  style: const TextStyle(fontSize: 12),
                ),
                onPressed: () async {
                  await ref
                      .read(scannerProvider.notifier)
                      .connectToCandidateIp(res.ip, lat);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                          'IP ${res.ip} ($lat ms) ${AppStrings.get('connected', locale: locale)}'),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildScannerStatsDashboard(ScannerState state, String locale) {
    final scannedCount = state.scanned;
    final responsiveCount = state.results.length;
    final successRate = scannedCount > 0 ? ((responsiveCount / scannedCount) * 100).toStringAsFixed(1) : '0.0';
    final bestPing = state.bestIp?.latencyMs != null
        ? '${state.bestIp!.latencyMs} ms'
        : (state.currentBestLatency != null ? '${state.currentBestLatency} ms' : '--');

    return Row(
      children: [
        _buildScannerMetricCard(
          icon: Icons.search_rounded,
          iconColor: Colors.blueAccent,
          label: AppStrings.get('tested_ips', locale: locale),
          value: '$scannedCount',
        ),
        const SizedBox(width: 10),
        _buildScannerMetricCard(
          icon: Icons.dns_rounded,
          iconColor: AppTheme.successColor,
          label: AppStrings.get('responsive_ips', locale: locale),
          value: '$responsiveCount',
          highlightColor: AppTheme.successColor,
        ),
        const SizedBox(width: 10),
        _buildScannerMetricCard(
          icon: Icons.percent_rounded,
          iconColor: Colors.amber,
          label: AppStrings.get('success_rate', locale: locale),
          value: '$successRate%',
        ),
        const SizedBox(width: 10),
        _buildScannerMetricCard(
          icon: Icons.bolt_rounded,
          iconColor: AppTheme.primaryAccent,
          label: AppStrings.get('best_ping', locale: locale),
          value: bestPing,
          highlightColor: bestPing != '--' ? AppTheme.primaryAccent : null,
        ),
      ],
    );
  }

  Widget _buildScannerMetricCard({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    Color? highlightColor,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF161C28),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white12, width: 0.8),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 18, color: iconColor),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: highlightColor ?? Colors.white,
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


