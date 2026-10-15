import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/l10n/translations.dart';
import 'core/theme/app_theme.dart';
import 'models/scan_result.dart';
import 'providers/app_providers.dart';
import 'services/cdn_scanner_service.dart';
import 'widgets/country_flag_badge.dart';

class ScannerView extends ConsumerStatefulWidget {
  final VoidCallback? onOpenDrawer;
  const ScannerView({super.key, this.onOpenDrawer});

  @override
  ConsumerState<ScannerView> createState() => _ScannerViewState();
}

class _ScannerViewState extends ConsumerState<ScannerView>
    with SingleTickerProviderStateMixin {
  double _workers = 20.0;
  double _targetTotal = 500.0;
  String _searchQuery = '';
  int _activeAccordion = 0;
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
    ref.watch(nodeCdnMapProvider);
    final detectedCdn = activeNode != null
        ? ref.read(nodeCdnMapProvider.notifier).detectCdnForNode(activeNode)
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

    final isPortrait = MediaQuery.of(context).orientation == Orientation.portrait ||
        MediaQuery.of(context).size.width < 650;
    final scannerTitle = locale == 'fa'
        ? 'اسکنر ${currentCdn.displayNameFa}'
        : '${currentCdn.displayName} Scanner';

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
                    scannerTitle,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ],
              ),
              actions: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.restart_alt_rounded, size: 20),
                  tooltip: AppStrings.get('reset_scan', locale: locale),
                  onPressed: () {
                    ref.read(scannerProvider.notifier).resetScan();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(AppStrings.get('scan_reset_done', locale: locale))),
                    );
                  },
                ),
                if (activeNode?.originalAddress != null)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.restore_rounded, size: 20),
                    tooltip: AppStrings.get('restore_original', locale: locale),
                    onPressed: () {
                      ref.read(nodesProvider.notifier).restoreAddress(activeNode!.id);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(AppStrings.get('original_restored', locale: locale))),
                      );
                    },
                  ),
                const SizedBox(width: 4),
              ],
            )
          : null,
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: Platform.isAndroid ? 12 : 20,
          vertical: Platform.isAndroid ? 10 : 14,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Header with Title & Action buttons (Desktop only)
            if (!Platform.isAndroid) ...[
              _buildNodeHeaderCard(activeNode, currentCdn, locale),
              const SizedBox(height: 12),
            ],

            if (isPortrait) ...[
              // Portrait mobile layout: stacked vertically
              _buildScannerStatsDashboard(state, locale, isPortrait: true),
              if (state.isScanning) ...[
                const SizedBox(height: 10),
                _buildProgressCard(state, locale),
              ],
              const SizedBox(height: 12),
              _buildStrategyAndControlsCard(state, activeNode, locale, isPortrait: true),
              const SizedBox(height: 12),
              _buildConnectedIpDisplayCard(state, activeNode, locale, isPortrait: true),
              const SizedBox(height: 12),
              _buildDualAccordionCard(state, locale, isPortrait: true),
            ] else ...[
              // Landscape / Desktop layout: 2 equal columns
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _buildTopLeftDashboard(state, locale),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _buildStrategyAndControlsCard(state, activeNode, locale),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _buildConnectedIpDisplayCard(state, activeNode, locale),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _buildDualAccordionCard(state, locale),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 14),
          ],
        ),
      ),
    );
  }

  Widget _buildTopLeftDashboard(ScannerState state, String locale) {
    return SizedBox(
      height: 280,
      child: Column(
        children: [
          Expanded(
            child: _buildScannerStatsDashboard(state, locale),
          ),
          if (state.isScanning) ...[
            const SizedBox(height: 8),
            _buildProgressCard(state, locale),
          ],
        ],
      ),
    );
  }

  Widget _buildNodeHeaderCard(
    dynamic activeNode,
    CdnProvider currentCdn,
    String locale,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(Icons.speed_rounded,
                    color: AppTheme.primaryAccent, size: 22),
                const SizedBox(width: 8),
                Text(
                  locale == 'fa'
                      ? 'اسکنر ${currentCdn.displayNameFa}'
                      : '${currentCdn.displayName} Scanner',
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
                    foregroundColor:
                        Theme.of(context).colorScheme.onSurfaceVariant,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
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
                          horizontal: 12, vertical: 8),
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
      ),
    );
  }

  Widget _buildStrategyAndControlsCard(
    ScannerState state,
    dynamic activeNode,
    String locale, {
    bool isPortrait = false,
  }) {
    final isRadar = state.strategy == ScannerStrategy.radar;

    return SizedBox(
      height: isPortrait ? null : 280,
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisAlignment: isPortrait ? MainAxisAlignment.start : MainAxisAlignment.spaceBetween,
            children: [
            // Strategy Selection: Radar and Target side-by-side with separate info icons
            Row(
              children: [
                Expanded(
                  child: _buildStrategyButton(
                    strategy: ScannerStrategy.radar,
                    isSelected: isRadar,
                    title: AppStrings.get('radar', locale: locale),
                    icon: Icons.radar_rounded,
                    tooltipDesc:
                        AppStrings.get('radar_full_desc', locale: locale),
                    isScanning: state.isScanning,
                    onTap: () {
                      ref
                          .read(scannerProvider.notifier)
                          .setStrategy(ScannerStrategy.radar);
                      setState(() => _activeAccordion = 0);
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildStrategyButton(
                    strategy: ScannerStrategy.target,
                    isSelected: !isRadar,
                    title: AppStrings.get('target', locale: locale),
                    icon: Icons.track_changes_rounded,
                    tooltipDesc:
                        AppStrings.get('target_full_desc', locale: locale),
                    isScanning: state.isScanning,
                    onTap: () {
                      ref
                          .read(scannerProvider.notifier)
                          .setStrategy(ScannerStrategy.target);
                      setState(() => _activeAccordion = 1);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Concurrency Slider (تعداد تست همزمان)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.tune_rounded,
                        size: 16, color: Colors.grey),
                    const SizedBox(width: 6),
                    Text(
                      AppStrings.get('concurrent_workers', locale: locale),
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ],
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${_workers.round()} Threads',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryAccent,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3.0,
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 6.0),
                overlayShape:
                    const RoundSliderOverlayShape(overlayRadius: 12.0),
                activeTrackColor: AppTheme.primaryAccent,
                thumbColor: AppTheme.primaryAccent,
              ),
              child: Slider(
                value: _workers.clamp(5.0, 100.0),
                min: 5.0,
                max: 100.0,
                divisions: 95,
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

            // Target Mode only: Total Candidates Slider (تعداد آیپی ها برای تست - فقط در حالت تارگت)
            if (!isRadar) ...[
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.hub_rounded,
                          size: 16, color: Colors.amber),
                      const SizedBox(width: 6),
                      Text(
                        AppStrings.get('target_total_count', locale: locale),
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${_targetTotal.round()} IPs',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                        color: Colors.amber,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3.0,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 6.0),
                  overlayShape:
                      const RoundSliderOverlayShape(overlayRadius: 12.0),
                  activeTrackColor: Colors.amber,
                  thumbColor: Colors.amber,
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
            ],

            const SizedBox(height: 10),
            // Start / Stop scan button (دکمه شروع اسکن)
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: state.isScanning
                    ? AppTheme.errorColor
                    : AppTheme.primaryAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: Icon(
                state.isScanning
                    ? Icons.stop_circle_rounded
                    : (isRadar
                        ? Icons.radar_rounded
                        : Icons.search_rounded),
                size: 18,
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
                    fontSize: 14, fontWeight: FontWeight.bold),
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
          ],
        ),
      ),
    ),
    );
  }

  Widget _buildStrategyButton({
    required ScannerStrategy strategy,
    required bool isSelected,
    required String title,
    required IconData icon,
    required String tooltipDesc,
    required bool isScanning,
    required VoidCallback onTap,
  }) {
    final primaryColor = strategy == ScannerStrategy.radar
        ? AppTheme.primaryAccent
        : Colors.amber;

    return Material(
      color: isSelected
          ? primaryColor.withValues(alpha: 0.12)
          : Theme.of(context).cardColor,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: isScanning ? null : onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected
                  ? primaryColor
                  : Theme.of(context).dividerColor.withValues(alpha: 0.4),
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 18,
                    color: isSelected ? primaryColor : Colors.grey,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: isSelected
                          ? primaryColor
                          : Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
              Tooltip(
                message: tooltipDesc,
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.symmetric(horizontal: 20),
                preferBelow: true,
                textStyle: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  height: 1.4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E2230),
                  borderRadius: BorderRadius.circular(8),
                  border:
                      Border.all(color: primaryColor.withValues(alpha: 0.4)),
                  boxShadow: const [
                    BoxShadow(
                        color: Colors.black45,
                        blurRadius: 8,
                        offset: Offset(0, 3)),
                  ],
                ),
                child: MouseRegion(
                  cursor: SystemMouseCursors.help,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.info_outline_rounded,
                      size: 16,
                      color: isSelected ? primaryColor : Colors.grey,
                    ),
                  ),
                ),
              ),
            ],
          ),
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          isRadar
                              ? '${AppStrings.get(state.isScanning ? 'scanning' : 'scan_finished', locale: locale)} (${state.scanned})'
                              : '${AppStrings.get(state.isScanning ? 'scanning' : 'scan_finished', locale: locale)} (${state.scanned} / ${state.total})',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (!isRadar && state.isScanning && state.estimatedRemainingTime != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryAccent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppTheme.primaryAccent.withValues(alpha: 0.4)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.timer_outlined, size: 10, color: AppTheme.primaryAccent),
                              const SizedBox(width: 3),
                              Text(
                                state.estimatedRemainingTime!,
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.primaryAccent,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (state.currentIp.isNotEmpty)
                  Text(
                    state.currentIp,
                    style: const TextStyle(
                      color: AppTheme.primaryAccent,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: Colors.grey.shade800,
                valueColor: const AlwaysStoppedAnimation(AppTheme.primaryAccent),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectedIpDisplayCard(
    ScannerState state,
    dynamic activeNode,
    String locale, {
    bool isPortrait = false,
  }) {
    final hasConnectedIp =
        state.connectedIp != null && state.currentBestLatency != null;
    final showTrafficNotice =
        state.isScanning && state.showRadarTrafficWarning;

    return SizedBox(
      height: isPortrait ? null : 280,
      child: Card(
        color: hasConnectedIp
            ? AppTheme.primaryAccent.withValues(alpha: 0.08)
            : Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            children: [
              if (showTrafficNotice) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade900.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber.shade700, width: 1.0),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded,
                          color: Colors.amber, size: 16),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          AppStrings.get('radar_traffic_warning', locale: locale),
                          style: const TextStyle(
                            color: Colors.amber,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            height: 1.25,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      InkWell(
                        onTap: () {
                          ref.read(scannerProvider.notifier).dismissRadarWarning();
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(3),
                          child: Icon(
                            Icons.close_rounded,
                            size: 14,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (!isPortrait) const Spacer() else const SizedBox(height: 12),
              // Radar Pulse Icon
              ScaleTransition(
                scale: (state.isScanning &&
                        state.strategy == ScannerStrategy.radar)
                    ? _pulseAnimation
                    : const AlwaysStoppedAnimation(1.0),
                child: Container(
                  padding: EdgeInsets.all(showTrafficNotice ? 8 : 12),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: (hasConnectedIp
                            ? AppTheme.successColor
                            : (state.isScanning
                                ? AppTheme.primaryAccent
                                : Colors.grey))
                        .withValues(alpha: 0.15),
                    border: Border.all(
                      color: (hasConnectedIp
                              ? AppTheme.successColor
                              : (state.isScanning
                                  ? AppTheme.primaryAccent
                                  : Colors.grey))
                          .withValues(alpha: 0.4),
                      width: 1.5,
                    ),
                  ),
                  child: Icon(
                    Icons.radar_rounded,
                    size: showTrafficNotice ? 26 : 34,
                    color: hasConnectedIp
                        ? AppTheme.successColor
                        : (state.isScanning
                            ? AppTheme.primaryAccent
                            : Colors.grey),
                  ),
                ),
              ),
              SizedBox(height: showTrafficNotice ? 6 : 10),

              if (hasConnectedIp) ...[
                Text(
                  AppStrings.get('current_active_ip', locale: locale),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 3),
                SelectableText(
                  state.connectedIp!,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.successColor.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.successColor),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.bolt_rounded,
                          color: AppTheme.successColor, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        '${state.currentBestLatency} ms  •  ${AppStrings.get('connected', locale: locale)}',
                        style: const TextStyle(
                          color: AppTheme.successColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.copy_rounded, size: 12),
                  label: Text(
                    AppStrings.get('copy_ip', locale: locale),
                    style: const TextStyle(fontSize: 11),
                  ),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: state.connectedIp!));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(AppStrings.get('ip_copied', locale: locale))),
                    );
                  },
                ),
              ] else ...[
                Text(
                  state.isScanning
                      ? AppStrings.get('searching_clean_ip', locale: locale)
                      : AppStrings.get('radar_ready', locale: locale),
                  style: TextStyle(
                    color: state.isScanning
                        ? AppTheme.primaryAccent
                        : Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Text(
                    state.isScanning
                        ? AppStrings.get('radar_first_connect_hint', locale: locale)
                        : AppStrings.get('radar_start_prompt', locale: locale),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
              if (!isPortrait) const Spacer() else const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDualAccordionCard(
    ScannerState state,
    String locale, {
    bool isPortrait = false,
  }) {
    return SizedBox(
      height: isPortrait ? 380 : 280,
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Accordion 1 Header: Radar Latency Improvements History
              _buildAccordionHeader(
                index: 0,
                icon: Icons.history_rounded,
                iconColor: AppTheme.primaryAccent,
                title: AppStrings.get('radar_history', locale: locale),
                badgeCount: state.radarLogs.length,
                isOpen: _activeAccordion == 0,
                onTap: () {
                  setState(() {
                    _activeAccordion = 0;
                  });
                },
              ),

              // Expanded Panel for Accordion 0
              if (_activeAccordion == 0) ...[
                const SizedBox(height: 6),
                Expanded(
                  child: _buildRadarHistoryContent(state, locale),
                ),
                const SizedBox(height: 6),
              ] else ...[
                const SizedBox(height: 6),
              ],

              // Accordion 2 Header: Discovered Clean IPs
              _buildAccordionHeader(
                index: 1,
                icon: Icons.dns_rounded,
                iconColor: AppTheme.successColor,
                title: AppStrings.get('discovered_clean_ips', locale: locale),
                badgeCount: state.results.length,
                isOpen: _activeAccordion == 1,
                onTap: () {
                  setState(() {
                    _activeAccordion = 1;
                  });
                },
              ),

              // Expanded Panel for Accordion 1
              if (_activeAccordion == 1) ...[
                const SizedBox(height: 6),
                Expanded(
                  child: _buildCleanIpsContent(state, locale),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAccordionHeader({
    required int index,
    required IconData icon,
    required Color iconColor,
    required String title,
    required int badgeCount,
    required bool isOpen,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isOpen
              ? iconColor.withValues(alpha: 0.12)
              : (theme.brightness == Brightness.dark
                  ? const Color(0xFF161A26)
                  : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isOpen
                ? iconColor.withValues(alpha: 0.4)
                : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: isOpen ? iconColor : theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: isOpen ? iconColor : theme.colorScheme.onSurface,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
              decoration: BoxDecoration(
                color: isOpen
                    ? iconColor.withValues(alpha: 0.2)
                    : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$badgeCount',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isOpen ? iconColor : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              isOpen ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
              size: 18,
              color: isOpen ? iconColor : theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRadarHistoryContent(ScannerState state, String locale) {
    if (state.radarLogs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            state.isScanning
                ? AppStrings.get('scanning_subnets', locale: locale)
                : AppStrings.get('no_improvements_yet', locale: locale),
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView.separated(
      itemCount: state.radarLogs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final log = state.radarLogs[index];
        final isFirst = index == state.radarLogs.length - 1;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: index == 0
                ? AppTheme.primaryAccent.withValues(alpha: 0.12)
                : (Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF131722)
                    : Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)),
            borderRadius: BorderRadius.circular(8),
            border: index == 0
                ? Border.all(
                    color: AppTheme.primaryAccent.withValues(alpha: 0.4),
                  )
                : null,
          ),
          child: Row(
            children: [
              Icon(
                index == 0 ? Icons.star_rounded : Icons.trending_down_rounded,
                color: index == 0 ? Colors.amber : AppTheme.successColor,
                size: 16,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      log.ip,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      isFirst
                          ? AppStrings.get('initial_connection', locale: locale)
                          : (log.improvementMs != null
                              ? '${log.improvementMs} ms ${AppStrings.get('latency_improved', locale: locale)}'
                              : AppStrings.get('latency_improved', locale: locale)),
                      style: TextStyle(
                        fontSize: 10,
                        color: index == 0
                            ? AppTheme.primaryAccent
                            : Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.successColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${log.latencyMs} ms',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                    color: AppTheme.successColor,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCleanIpsContent(ScannerState state, String locale) {
    final filtered = state.results.where((r) {
      if (_searchQuery.isNotEmpty && !r.ip.contains(_searchQuery)) return false;
      return true;
    }).toList();

    return Column(
      children: [
        SizedBox(
          height: 32,
          child: TextField(
            style: const TextStyle(fontSize: 12),
            decoration: InputDecoration(
              hintText: AppStrings.get('filter_ip_hint', locale: locale),
              prefixIcon: const Icon(Icons.search, size: 16),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 14),
                      onPressed: () => setState(() => _searchQuery = ''),
                      padding: EdgeInsets.zero,
                    )
                  : null,
              filled: true,
              fillColor: Theme.of(context).brightness == Brightness.dark
                  ? const Color(0xFF131722)
                  : Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
            ),
            onChanged: (val) => setState(() => _searchQuery = val),
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      state.isScanning
                          ? AppStrings.get('target_active', locale: locale)
                          : AppStrings.get('no_responsive_ips', locale: locale),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
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
              : Theme.of(context).cardColor),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isConnected
            ? const BorderSide(
                color: AppTheme.successColor,
                width: 1.2,
              )
            : (isTop
                ? BorderSide(
                    color: AppTheme.primaryAccent.withValues(alpha: 0.5),
                    width: 1.0,
                  )
                : BorderSide.none),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
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
                        : Theme.of(context).colorScheme.surfaceContainerHighest),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '#${index + 1}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: isConnected
                      ? AppTheme.successColor
                      : (isTop
                          ? Colors.amber
                          : Theme.of(context).colorScheme.onSurfaceVariant),
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
                      if (res.countryCode != null) ...[
                        CountryFlagBadge(
                          countryCode: res.countryCode,
                          width: 20,
                          height: 14,
                        ),
                        const SizedBox(width: 6),
                      ],
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
                  if (!mounted) return;
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

  Widget _buildScannerStatsDashboard(
    ScannerState state,
    String locale, {
    bool isPortrait = false,
  }) {
    final scannedCount = state.scanned;
    final responsiveCount = state.results.length;
    final successRate = scannedCount > 0
        ? ((responsiveCount / scannedCount) * 100).toStringAsFixed(1)
        : '0.0';
    final bestPing = state.bestIp?.latencyMs != null
        ? '${state.bestIp!.latencyMs} ms'
        : (state.currentBestLatency != null
            ? '${state.currentBestLatency} ms'
            : '--');

    final row1 = Row(
      children: [
        Expanded(
          child: _buildScannerMetricCard(
            icon: Icons.search_rounded,
            iconColor: Colors.blueAccent,
            label: AppStrings.get('tested_ips', locale: locale),
            value: '$scannedCount',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildScannerMetricCard(
            icon: Icons.dns_rounded,
            iconColor: AppTheme.successColor,
            label: AppStrings.get('responsive_ips', locale: locale),
            value: '$responsiveCount',
            highlightColor: AppTheme.successColor,
          ),
        ),
      ],
    );

    final row2 = Row(
      children: [
        Expanded(
          child: _buildScannerMetricCard(
            icon: Icons.percent_rounded,
            iconColor: Colors.amber,
            label: AppStrings.get('success_rate', locale: locale),
            value: '$successRate%',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildScannerMetricCard(
            icon: Icons.bolt_rounded,
            iconColor: AppTheme.primaryAccent,
            label: AppStrings.get('best_ping', locale: locale),
            value: bestPing,
            highlightColor: bestPing != '--' ? AppTheme.primaryAccent : null,
          ),
        ),
      ],
    );

    if (isPortrait) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          row1,
          const SizedBox(height: 10),
          row2,
        ],
      );
    }

    return Column(
      children: [
        Expanded(child: row1),
        const SizedBox(height: 10),
        Expanded(child: row2),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
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
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: highlightColor ??
                        Theme.of(context).colorScheme.onSurface,
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


