import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/l10n/translations.dart';
import '../core/theme/app_theme.dart';
import '../models/proxy_node.dart';
import '../providers/app_providers.dart';
import 'config_form_tabs.dart';

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
  final GlobalKey<ConfigFormTabsState> _formKey = GlobalKey<ConfigFormTabsState>();

  void _save() {
    final formState = _formKey.currentState;
    if (formState == null) return;

    final error = formState.validate();
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error)),
      );
      return;
    }

    final updated = formState.buildNode(
      id: widget.node.id,
      isActive: widget.node.isActive,
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
      content: ConfigFormTabs(
        key: _formKey,
        initialNode: widget.node,
        locale: loc,
      ),
      actions: [
        TextButton(
          child: Text(AppStrings.get('cancel_scan', locale: loc)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppTheme.primaryAccent),
          onPressed: _save,
          child: Text(AppStrings.get('save_changes', locale: loc).isNotEmpty ? AppStrings.get('save_changes', locale: loc) : 'Save Changes'),
        ),
      ],
    );
  }
}