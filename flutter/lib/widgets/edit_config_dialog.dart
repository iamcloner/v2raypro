import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/l10n/translations.dart';
import '../core/theme/app_theme.dart';
import '../models/proxy_node.dart';
import '../providers/app_providers.dart';

class EditConfigDialog extends ConsumerStatefulWidget {
  final ProxyNode node;
  final String locale;

  const EditConfigDialog({
    super.key,
    required this.node,
    required this.locale,
  });

  static Future<void> show(BuildContext context, ProxyNode node, String locale) {
    return showDialog(
      context: context,
      builder: (ctx) => EditConfigDialog(node: node, locale: locale),
    );
  }

  @override
  ConsumerState<EditConfigDialog> createState() => _EditConfigDialogState();
}

class _EditConfigDialogState extends ConsumerState<EditConfigDialog> {
  late TextEditingController _nameController;
  late TextEditingController _addressController;
  late TextEditingController _portController;
  late TextEditingController _uuidController;
  late TextEditingController _sniController;
  late TextEditingController _hostController;
  late TextEditingController _pathController;
  late TextEditingController _publicKeyController;
  late TextEditingController _shortIdController;

  late ProtocolType _protocol;
  late NetworkType _network;
  late SecurityType _security;
  late bool _allowInsecure;

  @override
  void initState() {
    super.initState();
    final n = widget.node;
    _nameController = TextEditingController(text: n.name);
    _addressController = TextEditingController(text: n.address);
    _portController = TextEditingController(text: n.port.toString());
    _uuidController = TextEditingController(text: n.uuidOrPassword);
    _sniController = TextEditingController(text: n.sni ?? '');
    _hostController = TextEditingController(text: n.host ?? '');
    _pathController = TextEditingController(text: n.path ?? '');
    _publicKeyController = TextEditingController(text: n.publicKey ?? '');
    _shortIdController = TextEditingController(text: n.shortId ?? '');

    _protocol = n.protocol;
    _network = n.network;
    _security = n.security;
    _allowInsecure = n.allowInsecure;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _portController.dispose();
    _uuidController.dispose();
    _sniController.dispose();
    _hostController.dispose();
    _pathController.dispose();
    _publicKeyController.dispose();
    _shortIdController.dispose();
    super.dispose();
  }

  void _save() {
    final port = int.tryParse(_portController.text.trim()) ?? widget.node.port;
    final updated = widget.node.copyWith(
      name: _nameController.text.trim().isEmpty ? widget.node.name : _nameController.text.trim(),
      protocol: _protocol,
      address: _addressController.text.trim().isEmpty ? widget.node.address : _addressController.text.trim(),
      port: port,
      uuidOrPassword: _uuidController.text.trim(),
      network: _network,
      security: _security,
      sni: _sniController.text.trim().isEmpty ? null : _sniController.text.trim(),
      host: _hostController.text.trim().isEmpty ? null : _hostController.text.trim(),
      path: _pathController.text.trim().isEmpty ? null : _pathController.text.trim(),
      publicKey: _publicKeyController.text.trim().isEmpty ? null : _publicKeyController.text.trim(),
      shortId: _shortIdController.text.trim().isEmpty ? null : _shortIdController.text.trim(),
      allowInsecure: _allowInsecure,
    );

    ref.read(nodesProvider.notifier).updateNode(updated);
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${updated.name} updated')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = widget.locale;

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.edit_note_rounded, color: AppTheme.primaryAccent),
          const SizedBox(width: 8),
          Text(AppStrings.get('edit_config', locale: loc)),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: AppStrings.get('config_name', locale: loc),
                  prefixIcon: const Icon(Icons.label_outline_rounded, size: 20),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<ProtocolType>(
                      value: _protocol,
                      decoration: const InputDecoration(
                        labelText: 'Protocol',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: ProtocolType.values
                          .where((p) => p != ProtocolType.customJson)
                          .map((p) => DropdownMenuItem(
                                value: p,
                                child: Text(p.name.toUpperCase()),
                              ))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _protocol = val);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 3,
                    child: DropdownButtonFormField<NetworkType>(
                      value: _network,
                      decoration: InputDecoration(
                        labelText: AppStrings.get('network_type', locale: loc),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: NetworkType.values
                          .map((n) => DropdownMenuItem(
                                value: n,
                                child: Text(n.name.toUpperCase()),
                              ))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _network = val);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _addressController,
                      decoration: InputDecoration(
                        labelText: AppStrings.get('server_address', locale: loc),
                        prefixIcon: const Icon(Icons.dns_outlined, size: 20),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _portController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: AppStrings.get('server_port', locale: loc),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _uuidController,
                decoration: InputDecoration(
                  labelText: AppStrings.get('user_id', locale: loc),
                  prefixIcon: const Icon(Icons.key_rounded, size: 20),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<SecurityType>(
                value: _security,
                decoration: InputDecoration(
                  labelText: AppStrings.get('security_type', locale: loc),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                items: SecurityType.values
                    .map((s) => DropdownMenuItem(
                          value: s,
                          child: Text(s.name.toUpperCase()),
                        ))
                    .toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _security = val);
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _sniController,
                      decoration: const InputDecoration(
                        labelText: 'SNI / ServerName',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _hostController,
                      decoration: const InputDecoration(
                        labelText: 'Host header',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              if (_security == SecurityType.tls) ...[
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(
                    AppStrings.get('allow_insecure', locale: loc),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    AppStrings.get('allow_insecure_desc', locale: loc),
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                  ),
                  value: _allowInsecure,
                  onChanged: (val) => setState(() => _allowInsecure = val),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _pathController,
                decoration: const InputDecoration(
                  labelText: 'Path (e.g. /ws, /pkgs/)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              if (_security == SecurityType.reality) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _publicKeyController,
                  decoration: const InputDecoration(
                    labelText: 'Reality Public Key (pbk)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _shortIdController,
                  decoration: const InputDecoration(
                    labelText: 'Reality Short ID (sid)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          child: const Text('Cancel'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppTheme.primaryAccent),
          onPressed: _save,
          child: const Text('Save Changes'),
        ),
      ],
    );
  }
}