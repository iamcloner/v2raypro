import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "../../core/l10n/translations.dart";
import "../../core/theme/app_theme.dart";
import "../../providers/app_providers.dart";

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
