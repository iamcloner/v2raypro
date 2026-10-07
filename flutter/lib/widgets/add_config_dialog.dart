import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../core/l10n/translations.dart';
import '../core/theme/app_theme.dart';
import '../models/proxy_node.dart';
import '../providers/app_providers.dart';
import '../utils/config_parser.dart';

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

  // Manual fields
  final _manualName = TextEditingController(text: 'Custom Node');
  final _manualAddress = TextEditingController();
  final _manualPort = TextEditingController(text: '443');
  final _manualUuid = TextEditingController();
  final _manualSni = TextEditingController();
  final _manualHost = TextEditingController();
  final _manualPath = TextEditingController();
  final _manualPbk = TextEditingController();
  final _manualSid = TextEditingController();
  ProtocolType _manualProtocol = ProtocolType.vless;
  NetworkType _manualNetwork = NetworkType.tcp;
  SecurityType _manualSecurity = SecurityType.tls;

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
    _manualName.dispose();
    _manualAddress.dispose();
    _manualPort.dispose();
    _manualUuid.dispose();
    _manualSni.dispose();
    _manualHost.dispose();
    _manualPath.dispose();
    _manualPbk.dispose();
    _manualSid.dispose();
    _urlController.dispose();
    _jsonController.dispose();
    super.dispose();
  }

  void _saveManual() {
    final addr = _manualAddress.text.trim();
    if (addr.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter server address')),
      );
      return;
    }

    final port = int.tryParse(_manualPort.text.trim()) ?? 443;
    final uuid = _manualUuid.text.trim().isEmpty ? const Uuid().v4() : _manualUuid.text.trim();
    final name = _manualName.text.trim().isEmpty ? 'Node-$addr' : _manualName.text.trim();

    final node = ProxyNode(
      id: const Uuid().v4(),
      name: name,
      protocol: _manualProtocol,
      address: addr,
      port: port,
      uuidOrPassword: uuid,
      network: _manualNetwork,
      security: _manualSecurity,
      sni: _manualSni.text.trim().isEmpty ? null : _manualSni.text.trim(),
      host: _manualHost.text.trim().isEmpty ? null : _manualHost.text.trim(),
      path: _manualPath.text.trim().isEmpty ? null : _manualPath.text.trim(),
      publicKey: _manualPbk.text.trim().isEmpty ? null : _manualPbk.text.trim(),
      shortId: _manualSid.text.trim().isEmpty ? null : _manualSid.text.trim(),
    );

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
          // Xray outbound config or full config
          final outbounds = decoded['outbounds'] as List?;
          if (outbounds != null && outbounds.isNotEmpty) {
            for (final out in outbounds) {
              if (out is Map<String, dynamic>) {
                final protoStr = (out['protocol'] ?? '').toString().toLowerCase();
                final proto = ProtocolType.values.firstWhere(
                  (p) => p.name.toLowerCase() == protoStr,
                  orElse: () => ProtocolType.vless,
                );
                final tag = out['tag'] ?? 'JSON Config';
                final settings = out['settings'] as Map<String, dynamic>? ?? {};
                final vnext = settings['vnext'] as List?;
                if (vnext != null && vnext.isNotEmpty) {
                  final first = vnext[0] as Map<String, dynamic>;
                  final addr = first['address'] ?? '127.0.0.1';
                  final port = (first['port'] as num?)?.toInt() ?? 443;
                  final users = first['users'] as List?;
                  final uuid = (users != null && users.isNotEmpty) ? (users[0]['id'] ?? '') : '';
                  nodes.add(ProxyNode(
                    id: const Uuid().v4(),
                    name: tag,
                    protocol: proto,
                    address: addr,
                    port: port,
                    uuidOrPassword: uuid,
                  ));
                }
              }
            }
          }
        } else {
          // Generic single JSON proxy node
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
        width: 540,
        height: 420,
        child: TabBarView(
          controller: _tabController,
          children: [
            // Mode 1: Manual
            SingleChildScrollView(
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _manualName,
                    decoration: InputDecoration(
                      labelText: AppStrings.get('config_name', locale: loc),
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: DropdownButtonFormField<ProtocolType>(
                          value: _manualProtocol,
                          decoration: const InputDecoration(
                            labelText: 'Protocol',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          items: ProtocolType.values
                              .where((p) => p != ProtocolType.customJson)
                              .map((p) => DropdownMenuItem(
                                    value: p,
                                    child: Text(p.name.toUpperCase()),
                                  ))
                              .toList(),
                          onChanged: (val) {
                            if (val != null) setState(() => _manualProtocol = val);
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 3,
                        child: DropdownButtonFormField<NetworkType>(
                          value: _manualNetwork,
                          decoration: InputDecoration(
                            labelText: AppStrings.get('network_type', locale: loc),
                            isDense: true,
                            border: const OutlineInputBorder(),
                          ),
                          items: NetworkType.values
                              .map((n) => DropdownMenuItem(
                                    value: n,
                                    child: Text(n.name.toUpperCase()),
                                  ))
                              .toList(),
                          onChanged: (val) {
                            if (val != null) setState(() => _manualNetwork = val);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: _manualAddress,
                          decoration: InputDecoration(
                            labelText: AppStrings.get('server_address', locale: loc),
                            hintText: 'e.g. 104.18.1.1',
                            isDense: true,
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _manualPort,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: AppStrings.get('server_port', locale: loc),
                            isDense: true,
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _manualUuid,
                    decoration: InputDecoration(
                      labelText: AppStrings.get('user_id', locale: loc),
                      hintText: 'UUID or password',
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<SecurityType>(
                    value: _manualSecurity,
                    decoration: InputDecoration(
                      labelText: AppStrings.get('security_type', locale: loc),
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                    items: SecurityType.values
                        .map((s) => DropdownMenuItem(
                              value: s,
                              child: Text(s.name.toUpperCase()),
                            ))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _manualSecurity = val);
                    },
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _manualSni,
                          decoration: const InputDecoration(
                            labelText: 'SNI (ServerName)',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _manualHost,
                          decoration: const InputDecoration(
                            labelText: 'Host header',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _manualPath,
                    decoration: const InputDecoration(
                      labelText: 'Path (e.g. /ws)',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (_manualSecurity == SecurityType.reality) ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: _manualPbk,
                      decoration: const InputDecoration(
                        labelText: 'Reality Public Key (pbk)',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _manualSid,
                      decoration: const InputDecoration(
                        labelText: 'Reality Short ID (sid)',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Mode 2: URL
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Paste one or multiple share links (vless://, vmess://, trojan://, ss://):',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: TextField(
                      controller: _urlController,
                      maxLines: null,
                      expands: true,
                      decoration: const InputDecoration(
                        hintText: 'vless://uuid@host:443?security=tls&type=ws#MyNode\nvmess://...',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Mode 3: JSON
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Paste Xray configuration JSON or ProxyNode JSON object/array:',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  const SizedBox(height: 10),
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
          child: const Text('Cancel'),
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
          child: const Text('Add Configuration'),
        ),
      ],
    );
  }
}