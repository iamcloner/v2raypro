import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/l10n/translations.dart';
import 'core/theme/app_theme.dart';
import 'models/scan_result.dart';
import 'providers/app_providers.dart';

class ScannerView extends ConsumerStatefulWidget {
  const ScannerView({super.key});

  @override
  ConsumerState<ScannerView> createState() => _ScannerViewState();
}

class _ScannerViewState extends ConsumerState<ScannerView> {
  int _candidates = 30;
  int _workers = 15;
  String _searchQuery = '';
  bool _onlySuccessful = true;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(scannerProvider);
    final nodes = ref.watch(nodesProvider);
    final activeNode = nodes.isEmpty ? null : nodes.firstWhere((n) => n.isActive, orElse: () => nodes.first);
    final locale = ref.watch(currentLocaleProvider);

    final filteredResults = state.results.where((r) {
      if (_onlySuccessful && (!r.tcpSuccess || !r.tlsSuccess)) return false;
      if (_searchQuery.isNotEmpty && !r.ip.contains(_searchQuery)) return false;
      return true;
    }).toList();

    filteredResults.sort((a, b) => a.rankScore.compareTo(b.rankScore));

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
                          AppStrings.get('scanner', locale: locale),
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        if (activeNode?.originalAddress != null)
                          OutlinedButton.icon(
                            icon: const Icon(Icons.restore_rounded, size: 16),
                            label: Text(AppStrings.get('restore_original', locale: locale)),
                            onPressed: () {
                              ref.read(nodesProvider.notifier).restoreAddress(activeNode!.id);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Original host restored')),
                              );
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      activeNode == null
                          ? AppStrings.get('no_nodes', locale: locale)
                          : ('Target: ' + activeNode.name + ' (' + activeNode.address + ')'),
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
                                  ? AppStrings.get('cancel_scan', locale: locale)
                                  : AppStrings.get('find_best_ip', locale: locale),
                            ),
                            onPressed: activeNode == null
                                ? null
                                : () {
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
                          Text(AppStrings.get('scanning', locale: locale) + ' (' + state.scanned.toString() + ' / ' + state.total.toString() + ')'),
                          if (state.currentIp.isNotEmpty)
                            Text(
                              state.currentIp,
                              style: const TextStyle(color: AppTheme.primaryAccent, fontFamily: 'monospace'),
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

            if (state.bestIp != null && activeNode != null) ...[
              Card(
                color: AppTheme.primaryAccent.withValues(alpha: 0.1),
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
                            const Text('Best Clean IP Found', style: TextStyle(fontWeight: FontWeight.bold)),
                            Text(
                              state.bestIp!.ip + '  •  ' + state.bestIp!.tcpLatencyMs.toString() + ' ms  •  ' + state.bestIp!.latencyTier,
                              style: const TextStyle(color: Colors.grey, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: AppTheme.primaryAccent),
                        child: Text(AppStrings.get('apply_ip', locale: locale)),
                        onPressed: () {
                          ref.read(nodesProvider.notifier).applyIp(activeNode.id, state.bestIp!.ip);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Applied IP ' + state.bestIp!.ip + ' to ' + activeNode.name)),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],

            Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Filter by IP...',
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
                  label: const Text('Only Success'),
                  selected: _onlySuccessful,
                  onSelected: (val) => setState(() => _onlySuccessful = val),
                ),
              ],
            ),
            const SizedBox(height: 16),

            if (filteredResults.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: Text(
                    state.isScanning ? 'Scanning candidate subnets...' : 'No results. Click "Find Best IP" to benchmark clean Cloudflare IPs.',
                    style: const TextStyle(color: Colors.grey),
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: filteredResults.length,
                separatorBuilder: (c, i) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final res = filteredResults[index];
                  return _buildResultTile(res, activeNode?.id ?? '', locale);
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
        title: Text(res.ip, style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold)),
        subtitle: Text(
          success
              ? ('TCP: ' + res.tcpLatencyMs.toString() + 'ms  |  TLS: ' + res.tlsLatencyMs.toString() + 'ms  |  ' + res.latencyTier)
              : (res.error ?? 'Failed'),
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
                color: (success ? AppTheme.successColor : AppTheme.errorColor).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                success ? (res.tcpLatencyMs.toString() + ' ms') : 'Timeout',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: success ? AppTheme.successColor : AppTheme.errorColor,
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (activeNodeId.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.check_circle_outline_rounded, color: AppTheme.primaryAccent),
                tooltip: AppStrings.get('apply_ip', locale: locale),
                onPressed: () {
                  ref.read(nodesProvider.notifier).applyIp(activeNodeId, res.ip);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Applied IP ' + res.ip + ' to active node')),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
