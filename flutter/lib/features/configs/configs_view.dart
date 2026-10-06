import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "../../core/l10n/translations.dart";
import "../../core/theme/app_theme.dart";
import "../../models/proxy_node.dart";
import "../../providers/app_providers.dart";

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
