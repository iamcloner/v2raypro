import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "core/l10n/translations.dart";
import "core/theme/app_theme.dart";
import "models/subscription_item.dart";
import "providers/app_providers.dart";

class SubscriptionsView extends ConsumerStatefulWidget {
  const SubscriptionsView({super.key});

  @override
  ConsumerState<SubscriptionsView> createState() => _SubscriptionsViewState();
}

class _SubscriptionsViewState extends ConsumerState<SubscriptionsView> {
  final _nameController = TextEditingController();
  final _urlController = TextEditingController();
  final Set<String> _updatingSubIds = {};
  bool _isUpdatingAll = false;

  void _showAddDialog(String locale) {
    _nameController.clear();
    _urlController.clear();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppStrings.get("add_subscription", locale: locale)),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: AppStrings.get("sub_name", locale: locale),
                  hintText: "e.g. My Premium Configs",
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _urlController,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: AppStrings.get("sub_url", locale: locale),
                  hintText: "https://example.com/api/v1/client/subscribe?token=...",
                  border: const OutlineInputBorder(),
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
            child: const Text("Add & Update"),
            onPressed: () async {
              final url = _urlController.text.trim();
              if (url.isNotEmpty) {
                Navigator.pop(ctx);
                final messenger = ScaffoldMessenger.of(context);
                messenger.showSnackBar(
                  const SnackBar(content: Text("Fetching subscription nodes...")),
                );
                final count = await ref
                    .read(subscriptionsProvider.notifier)
                    .addSubscription(_nameController.text.trim(), url);
                messenger.showSnackBar(
                  SnackBar(content: Text("$count nodes imported from subscription.")),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Future<void> _updateSub(SubscriptionItem sub) async {
    if (_updatingSubIds.contains(sub.id)) return;
    setState(() => _updatingSubIds.add(sub.id));

    final count = await ref.read(subscriptionsProvider.notifier).updateSubscription(sub.id);

    if (mounted) {
      setState(() => _updatingSubIds.remove(sub.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("${sub.name}: $count nodes updated")),
      );
    }
  }

  Future<void> _updateAllSubs() async {
    final subs = ref.read(subscriptionsProvider);
    if (subs.isEmpty || _isUpdatingAll) return;

    setState(() => _isUpdatingAll = true);
    await ref.read(subscriptionsProvider.notifier).updateAll();

    if (mounted) {
      setState(() => _isUpdatingAll = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("All subscriptions updated successfully")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final subs = ref.watch(subscriptionsProvider);
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
                  AppStrings.get("subscriptions", locale: locale),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                Row(
                  children: [
                    if (subs.isNotEmpty)
                      OutlinedButton.icon(
                        icon: _isUpdatingAll
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.sync_rounded, size: 18),
                        label: Text(_isUpdatingAll
                            ? "Updating..."
                            : AppStrings.get("update_all_subs", locale: locale)),
                        onPressed: _isUpdatingAll ? null : _updateAllSubs,
                      ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: AppTheme.primaryAccent),
                      icon: const Icon(Icons.add),
                      label: Text(AppStrings.get("add_subscription", locale: locale)),
                      onPressed: () => _showAddDialog(locale),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (subs.isEmpty)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.rss_feed_rounded, size: 64, color: Colors.grey.shade700),
                      const SizedBox(height: 16),
                      Text(
                        AppStrings.get("no_subs", locale: locale),
                        style: const TextStyle(color: Colors.grey, fontSize: 15),
                      ),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  itemCount: subs.length,
                  separatorBuilder: (c, i) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final sub = subs[index];
                    final isUpdating = _updatingSubIds.contains(sub.id);

                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppTheme.primaryAccent.withValues(alpha: 0.15),
                          child: const Icon(Icons.rss_feed_rounded, color: AppTheme.primaryAccent),
                        ),
                        title: Text(sub.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(
                          "${sub.nodeCount} nodes  •  ${sub.lastUpdated != null ? 'Updated: ' + sub.lastUpdated!.toLocal().toString().substring(0, 16) : 'Never updated'}\n${sub.url}",
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        isThreeLine: true,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isUpdating)
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 12),
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              )
                            else
                              IconButton(
                                icon: const Icon(Icons.sync_rounded, color: Colors.cyanAccent),
                                tooltip: "Update subscription",
                                onPressed: () => _updateSub(sub),
                              ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline_rounded, color: Colors.grey),
                              tooltip: "Delete",
                              onPressed: () {
                                ref.read(subscriptionsProvider.notifier).removeSubscription(sub.id);
                              },
                            ),
                          ],
                        ),
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
