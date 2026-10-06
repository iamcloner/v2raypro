import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/l10n/translations.dart';
import 'core/theme/app_theme.dart';
import 'models/proxy_node.dart';
import 'providers/app_providers.dart';

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
        title: Text(AppStrings.get('add_config', locale: locale)),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _importController,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'Paste vless://, vmess://, trojan://, ss://, or subscription URL...',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(ctx),
          ),
          FilledButton(
            child: const Text('Import'),
            onPressed: () {
              final text = _importController.text.trim();
              if (text.isNotEmpty) {
                final node = _parseConfigUrl(text);
                ref.read(nodesProvider.notifier).addNode(node);
                _importController.clear();
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Configuration added successfully')),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  ProxyNode _parseConfigUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final scheme = uri.scheme.toLowerCase();
      final proto = scheme == 'vmess'
          ? ProtocolType.vmess
          : scheme == 'trojan'
              ? ProtocolType.trojan
              : scheme == 'ss'
                  ? ProtocolType.shadowsocks
                  : ProtocolType.vless;

      final name = uri.fragment.isNotEmpty
          ? Uri.decodeComponent(uri.fragment)
          : (uri.host + ':' + uri.port.toString());

      return ProxyNode(
        id: 'node-' + DateTime.now().millisecondsSinceEpoch.toString(),
        name: name,
        protocol: proto,
        address: uri.host.isNotEmpty ? uri.host : '127.0.0.1',
        port: uri.port > 0 ? uri.port : 443,
        uuidOrPassword: uri.userInfo,
        network: uri.queryParameters['type'] == 'ws' ? NetworkType.ws : NetworkType.tcp,
        security: uri.queryParameters['security'] == 'reality'
            ? SecurityType.reality
            : uri.queryParameters['security'] == 'tls'
                ? SecurityType.tls
                : SecurityType.none,
        path: uri.queryParameters['path'],
        host: uri.queryParameters['host'],
        sni: uri.queryParameters['sni'] ?? uri.queryParameters['host'],
        publicKey: uri.queryParameters['pbk'],
        shortId: uri.queryParameters['sid'],
        spiderX: uri.queryParameters['spx'],
      );
    } catch (_) {
      return ProxyNode(
        id: 'node-' + DateTime.now().millisecondsSinceEpoch.toString(),
        name: 'Imported Node',
        protocol: ProtocolType.vless,
        address: '127.0.0.1',
        port: 443,
        uuidOrPassword: '',
      );
    }
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
                  AppStrings.get('configs', locale: locale),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: AppTheme.primaryAccent),
                  icon: const Icon(Icons.add),
                  label: Text(AppStrings.get('add_config', locale: locale)),
                  onPressed: () => _showImportDialog(locale),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (nodes.isEmpty)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.cloud_off_rounded, size: 64, color: Colors.grey.shade700),
                      const SizedBox(height: 16),
                      Text(
                        AppStrings.get('no_nodes', locale: locale),
                        style: const TextStyle(color: Colors.grey, fontSize: 15),
                      ),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  itemCount: nodes.length,
                  separatorBuilder: (c, i) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final node = nodes[index];
                    return Card(
                      child: ListTile(
                        leading: Icon(
                          node.isActive ? Icons.radio_button_checked : Icons.radio_button_off,
                          color: node.isActive ? AppTheme.primaryAccent : Colors.grey,
                        ),
                        title: Text(node.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(node.address + ':' + node.port.toString() + '  •  ' + node.protocol.name.toUpperCase()),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (node.latencyMs != null)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppTheme.successColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  node.latencyMs.toString() + ' ms',
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
