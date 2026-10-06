import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/l10n/translations.dart';
import 'core/theme/app_theme.dart';
import 'models/scan_result.dart';
import 'providers/app_providers.dart';
import 'services/cloudflare_scanner_service.dart';

class ScannerView extends ConsumerStatefulWidget {
  const ScannerView({super.key});

  @override
  ConsumerState<ScannerView> createState() => _ScannerViewState();
}

class _ScannerViewState extends ConsumerState<ScannerView>
    with SingleTickerProviderStateMixin {
  double _threshold = 30.0;
  String _searchQuery = '';
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
    final isCf = activeNode != null &&
        CloudflareScannerService.isCloudflareIp(
            activeNode.address, ref.watch(cfRangesProvider));

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
            // 1. Target Node Info Header
            _buildNodeHeaderCard(activeNode, isCf, locale),
            const SizedBox(height: 16),

            // 2. Strategy Switcher (Radar vs Target)
            _buildStrategySelector(state, locale),
            const SizedBox(height: 16),

            // 3. Scan Threshold Slider & Controls
            _buildControlsCard(state, activeNode, isCf, locale),
            const SizedBox(height: 16),

            // 4. Progress Indicator (when scanning or finished)
            if (state.isScanning || state.scanned > 0) ...[
              _buildProgressCard(state, locale),
              const SizedBox(height: 16),
            ],

            // 5. Strategy Specific View
            if (state.strategy == ScannerStrategy.radar)
              _buildRadarView(state, activeNode, locale)
            else
              _buildTargetView(state, activeNode, locale),
          ],
        ),
      ),
    );
  }

  Widget _buildNodeHeaderCard(dynamic activeNode, bool isCf, String locale) {
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
                      AppStrings.get('scanner', locale: locale),
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                if (activeNode?.originalAddress != null)
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
                        const SnackBar(content: Text('Original host restored')),
                      );
                    },
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
                        : '${activeNode.name} (${activeNode.address})',
                    style: const TextStyle(color: Colors.grey, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isCf) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.amber, width: 0.8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.star_rounded, size: 13, color: Colors.amber),
                        SizedBox(width: 3),
                        Text(
                          "CF",
                          style: TextStyle(
                            color: Colors.amber,
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
            if (activeNode != null && !isCf) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border:
                      Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded,
                        color: Colors.amber, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        AppStrings.get('scanner_cf_only_notice', locale: locale),
                        style:
                            const TextStyle(color: Colors.amber, fontSize: 12),
                      ),
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

  Widget _buildStrategySelector(ScannerState state, String locale) {
    final isRadar = state.strategy == ScannerStrategy.radar;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            SegmentedButton<ScannerStrategy>(
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
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  isRadar ? Icons.radar_rounded : Icons.track_changes_rounded,
                  size: 16,
                  color: AppTheme.primaryAccent,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isRadar
                        ? AppStrings.get('radar_desc', locale: locale)
                        : AppStrings.get('target_desc', locale: locale),
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlsCard(
      ScannerState state, dynamic activeNode, bool isCf, String locale) {
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
                Row(
                  children: [
                    const Icon(Icons.tune_rounded, size: 18, color: Colors.grey),
                    const SizedBox(width: 6),
                    Text(
                      AppStrings.get('scan_count', locale: locale),
                      style: const TextStyle(fontWeight: FontWeight.w600),
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
                    '${_threshold.round()} IP',
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
                value: _threshold,
                min: 5.0,
                max: 100.0,
                divisions: 19,
                label: '${_threshold.round()}',
                onChanged: state.isScanning
                    ? null
                    : (val) {
                        setState(() => _threshold = val);
                        ref
                            .read(scannerProvider.notifier)
                            .setThreshold(val.round());
                      },
              ),
            ),
            const SizedBox(height: 10),
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
                    onPressed: (activeNode == null || !isCf)
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
    final progress =
        state.total > 0 ? (state.scanned / state.total).clamp(0.0, 1.0) : 0.0;
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
                  '${AppStrings.get(state.isScanning ? 'scanning' : 'scan_finished', locale: locale)} (${state.scanned} / ${state.total})',
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

  Widget _buildRadarView(
      ScannerState state, dynamic activeNode, String locale) {
    final hasConnectedIp =
        state.connectedIp != null && state.currentBestLatency != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
                        ? 'به محض یافتن اولین پینگ، متصل می‌شود و اسکن برای پینگ‌های کمتر ادامه می‌یابد.'
                        : 'روی دکمه «شروع رادار» کلیک کنید تا اسکن خودکار فعال شود.',
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
                            ? 'در حال اسکن و پایش رنج‌ها...'
                            : 'هنوز بهبودی ثبت نشده است.',
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
                  hintText: 'Filter IP...',
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
                '${filtered.length} پاسخ‌دهنده',
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
              return _buildTargetResultCard(res, index, locale);
            },
          ),
      ],
    );
  }

  Widget _buildTargetResultCard(ScanResult res, int index, String locale) {
    final lat = res.totalLatencyMs ?? res.tcpLatencyMs ?? 0;
    final isTop = index == 0;
    Color badgeColor;
    if (lat < 120) {
      badgeColor = AppTheme.successColor;
    } else if (lat < 250) {
      badgeColor = Colors.amber;
    } else {
      badgeColor = AppTheme.errorColor;
    }

    return Card(
      color: isTop
          ? AppTheme.primaryAccent.withValues(alpha: 0.08)
          : const Color(0xFF161B26),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isTop
              ? AppTheme.primaryAccent.withValues(alpha: 0.5)
              : Colors.grey.shade800,
          width: isTop ? 1.2 : 0.8,
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
                color: isTop
                    ? Colors.amber.withValues(alpha: 0.2)
                    : Colors.grey.shade800,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '#${index + 1}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: isTop ? Colors.amber : Colors.grey.shade300,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    res.ip,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Port: ${res.port}  •  ${res.latencyTier}',
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
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primaryAccent,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.bolt_rounded, size: 16),
              label: Text(
                AppStrings.get('connect_apply', locale: locale),
                style: const TextStyle(fontSize: 12),
              ),
              onPressed: () async {
                await ref
                    .read(scannerProvider.notifier)
                    .connectToTargetIp(res.ip, lat);
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
}

