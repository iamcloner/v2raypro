import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/l10n/translations.dart';
import '../core/theme/app_theme.dart';
import '../models/proxy_node.dart';
import '../providers/app_providers.dart';
import '../utils/config_parser.dart';
import 'config_form_tabs.dart';

class AddConfigDialog extends ConsumerStatefulWidget {
  final String locale;

  const AddConfigDialog({
    super.key,
    required this.locale,
  });

  static Future<void> show(BuildContext context, String locale) {
    return showDialog(
      context: context,
      builder: (ctx) => AddConfigDialog(locale: locale),
    );
  }

  @override
  ConsumerState<AddConfigDialog> createState() => _AddConfigDialogState();
}

class _AddConfigDialogState extends ConsumerState<AddConfigDialog> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final GlobalKey<ConfigFormTabsState> _manualFormKey = GlobalKey<ConfigFormTabsState>();

  // URL field
  final _urlController = TextEditingController();

  // JSON field
  final _jsonController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _urlController.dispose();
    _jsonController.dispose();
    super.dispose();
  }

  void _saveManual() {
    final formState = _manualFormKey.currentState;
    if (formState == null) return;

    final error = formState.validate();
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error)),
      );
      return;
    }

    final node = formState.buildNode();
    ref.read(nodesProvider.notifier).addNodes([node]);
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${node.name} added successfully')),
    );
  }

  Future<void> _saveUrl() async {
    final text = _urlController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please paste a configuration URL')),
      );
      return;
    }

    final nodes = await ConfigParser.parseBatchAsync(text);
    if (!mounted) return;
    if (nodes.isNotEmpty) {
      ref.read(nodesProvider.notifier).addNodes(nodes);
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${nodes.length} configuration(s) imported successfully')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No valid proxy configurations found in URL')),
      );
    }
  }

  void _saveJson() {
    final text = _jsonController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please paste JSON content')),
      );
      return;
    }

    try {
      final decoded = jsonDecode(text);
      final List<ProxyNode> nodes = [];

      if (decoded is List) {
        for (final item in decoded) {
          if (item is Map<String, dynamic>) {
            nodes.add(ProxyNode.fromJson(item));
          }
        }
      } else if (decoded is Map<String, dynamic>) {
        if (decoded.containsKey('address') || decoded.containsKey('server')) {
          nodes.add(ProxyNode.fromJson(decoded));
        } else if (decoded.containsKey('outbounds')) {
          final outbounds = decoded['outbounds'] as List?;
          if (outbounds != null) {
            for (final ob in outbounds) {
              if (ob is Map<String, dynamic> && ob['protocol'] != 'freedom' && ob['protocol'] != 'blackhole') {
                try {
                  nodes.add(ProxyNode.fromJson(ob));
                } catch (_) {}
              }
            }
          }
        } else {
          nodes.add(ProxyNode.fromJson(decoded));
        }
      }

      if (nodes.isNotEmpty) {
        ref.read(nodesProvider.notifier).addNodes(nodes);
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${nodes.length} configuration(s) imported from JSON')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No valid proxy structures recognized in JSON')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invalid JSON format: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = widget.locale;

    return AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.add_circle_outline_rounded, color: AppTheme.primaryAccent),
              const SizedBox(width: 8),
              Text(AppStrings.get('add_config', locale: loc)),
            ],
          ),
          const SizedBox(height: 12),
          TabBar(
            controller: _tabController,
            labelColor: AppTheme.primaryAccent,
            unselectedLabelColor: Colors.grey,
            indicatorColor: AppTheme.primaryAccent,
            tabs: [
              Tab(
                icon: const Icon(Icons.tune_rounded, size: 18),
                text: AppStrings.get('add_manual', locale: loc),
              ),
              Tab(
                icon: const Icon(Icons.link_rounded, size: 18),
                text: AppStrings.get('add_vless_url', locale: loc),
              ),
              Tab(
                icon: const Icon(Icons.code_rounded, size: 18),
                text: AppStrings.get('add_json', locale: loc),
              ),
            ],
          ),
        ],
      ),
      content: SizedBox(
        width: 580,
        height: 520,
        child: TabBarView(
          controller: _tabController,
          children: [
            // Mode 1: Manual (4-tab editor)
            ConfigFormTabs(
              key: _manualFormKey,
              locale: loc,
            ),

            // Mode 2: URL
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Paste VLESS, VMess, Trojan, or SS links (one per line):',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: TextField(
                      controller: _urlController,
                      maxLines: null,
                      expands: true,
                      decoration: const InputDecoration(
                        hintText: 'vless://...\nvmess://...\ntrojan://...',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Mode 3: JSON
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Paste exported Xray outbound or config JSON:',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: TextField(
                      controller: _jsonController,
                      maxLines: null,
                      expands: true,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                      decoration: const InputDecoration(
                        hintText: '{\n  "outbounds": [...]\n}',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          child: Text(AppStrings.get('cancel_scan', locale: loc)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppTheme.primaryAccent),
          onPressed: () {
            switch (_tabController.index) {
              case 0:
                _saveManual();
                break;
              case 1:
                _saveUrl();
                break;
              case 2:
                _saveJson();
                break;
            }
          },
          child: Text(AppStrings.get('add_config', locale: loc)),
        ),
      ],
    );
  }
}