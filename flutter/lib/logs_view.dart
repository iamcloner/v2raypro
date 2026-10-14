import "dart:io";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "core/l10n/translations.dart";
import "core/theme/app_theme.dart";
import "models/log_entry.dart";
import "providers/app_providers.dart";

class LogsView extends ConsumerStatefulWidget {
  final VoidCallback? onOpenDrawer;
  const LogsView({super.key, this.onOpenDrawer});

  @override
  ConsumerState<LogsView> createState() => _LogsViewState();
}

class _LogsViewState extends ConsumerState<LogsView> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  LogLevel? _selectedLevel; // null means 'All'
  bool _autoScroll = true;
  String _searchQuery = "";

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (!_autoScroll || !_scrollController.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Color _levelColor(LogLevel level) {
    switch (level) {
      case LogLevel.info:
        return const Color(0xFF38BDF8); // Sky blue
      case LogLevel.warning:
        return const Color(0xFFFBBF24); // Amber
      case LogLevel.error:
        return const Color(0xFFF87171); // Light Red
      case LogLevel.access:
        return const Color(0xFF34D399); // Emerald
    }
  }

  String _levelLabel(LogLevel level, String locale) {
    switch (level) {
      case LogLevel.info:
        return AppStrings.get("filter_info", locale: locale);
      case LogLevel.warning:
        return AppStrings.get("filter_warning", locale: locale);
      case LogLevel.error:
        return AppStrings.get("filter_error", locale: locale);
      case LogLevel.access:
        return AppStrings.get("filter_access", locale: locale);
    }
  }

  void _copyAllLogs(List<LogEntry> filteredLogs, String locale) {
    if (filteredLogs.isEmpty) return;
    final text = filteredLogs
        .map((e) => "[${e.formattedTime()}] [${e.level.name.toUpperCase()}] [${e.source.toUpperCase()}] ${e.message}")
        .join("\n");

    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppStrings.get("logs_copied", locale: locale)),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(currentLocaleProvider);
    final allLogs = ref.watch(logsProvider);

    // Apply filters
    final filteredLogs = allLogs.where((entry) {
      if (_selectedLevel != null && entry.level != _selectedLevel) {
        return false;
      }
      if (_searchQuery.isNotEmpty) {
        final content = "${entry.message} ${entry.source} ${entry.level.name}".toLowerCase();
        if (!content.contains(_searchQuery)) {
          return false;
        }
      }
      return true;
    }).toList();

    // Trigger auto-scroll if enabled and new logs arrived
    ref.listen<List<LogEntry>>(logsProvider, (_, __) {
      _scrollToBottom();
    });

    return Scaffold(
      appBar: Platform.isAndroid
          ? AppBar(
              leading: IconButton(
                icon: const Icon(Icons.menu_rounded),
                tooltip: AppStrings.get('more', locale: locale),
                onPressed: widget.onOpenDrawer,
              ),
              titleSpacing: 0,
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(
                        color: const Color(0xFF00D2FF).withValues(alpha: 0.4),
                        width: 1.2,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Image.asset('assets/app_icon.png', fit: BoxFit.cover),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    AppStrings.get('logs', locale: locale),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${filteredLogs.length}',
                      style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              actions: [
                IconButton(
                  tooltip: AppStrings.get("autoscroll", locale: locale),
                  icon: Icon(
                    Icons.arrow_downward_rounded,
                    size: 20,
                    color: _autoScroll ? AppTheme.primaryAccent : Colors.grey,
                  ),
                  onPressed: () {
                    setState(() {
                      _autoScroll = !_autoScroll;
                      if (_autoScroll) _scrollToBottom();
                    });
                  },
                ),
                IconButton(
                  tooltip: AppStrings.get("copy_logs", locale: locale),
                  icon: const Icon(Icons.copy_rounded, size: 19),
                  onPressed: filteredLogs.isEmpty ? null : () => _copyAllLogs(filteredLogs, locale),
                ),
                IconButton(
                  tooltip: AppStrings.get("clear_logs", locale: locale),
                  icon: const Icon(Icons.delete_outline_rounded, size: 19, color: Colors.redAccent),
                  onPressed: allLogs.isEmpty
                      ? null
                      : () {
                          ref.read(logsProvider.notifier).clear();
                        },
                ),
              ],
            )
          : null,
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!Platform.isAndroid) ...[
              // Top Bar: Title, Count, Action buttons
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.article_rounded, color: AppTheme.primaryAccent, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    AppStrings.get("logs", locale: locale),
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      "${filteredLogs.length}",
                      style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const Spacer(),
                  // Auto-scroll toggle
                  InkWell(
                    onTap: () {
                      setState(() {
                        _autoScroll = !_autoScroll;
                        if (_autoScroll) _scrollToBottom();
                      });
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: _autoScroll
                            ? AppTheme.primaryAccent.withValues(alpha: 0.2)
                            : Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _autoScroll ? AppTheme.primaryAccent : Colors.transparent,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.arrow_downward_rounded,
                            size: 16,
                            color: _autoScroll ? AppTheme.primaryAccent : Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            AppStrings.get("autoscroll", locale: locale),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _autoScroll ? AppTheme.primaryAccent : Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Copy all button
                  IconButton(
                    tooltip: AppStrings.get("copy_logs", locale: locale),
                    icon: Icon(Icons.copy_rounded, size: 19, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    style: IconButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: filteredLogs.isEmpty ? null : () => _copyAllLogs(filteredLogs, locale),
                  ),
                  const SizedBox(width: 8),
                  // Clear logs button
                  IconButton(
                    tooltip: AppStrings.get("clear_logs", locale: locale),
                    icon: const Icon(Icons.delete_outline_rounded, size: 19, color: Colors.redAccent),
                    style: IconButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: allLogs.isEmpty
                        ? null
                        : () {
                            ref.read(logsProvider.notifier).clear();
                          },
                  ),
                ],
              ),
              const SizedBox(height: 14),
            ],

            // Controls Row: Search Input & Filter Chips
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // Search box
                SizedBox(
                  width: 240,
                  height: 38,
                  child: TextField(
                    controller: _searchController,
                    style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface),
                    decoration: InputDecoration(
                      hintText: AppStrings.get("search_logs", locale: locale),
                      hintStyle: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
                      prefixIcon: Icon(Icons.search_rounded, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.clear_rounded, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                              onPressed: () => _searchController.clear(),
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                      filled: true,
                      fillColor: Theme.of(context).cardColor,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Theme.of(context).dividerColor),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Theme.of(context).dividerColor),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: AppTheme.primaryAccent),
                      ),
                    ),
                  ),
                ),
                // Filter Chip: All
                _buildFilterChip(
                  label: AppStrings.get("filter_all", locale: locale),
                  isSelected: _selectedLevel == null,
                  color: AppTheme.primaryAccent,
                  onSelected: () => setState(() => _selectedLevel = null),
                ),
                // Filter Chip: Info
                _buildFilterChip(
                  label: _levelLabel(LogLevel.info, locale),
                  isSelected: _selectedLevel == LogLevel.info,
                  color: const Color(0xFF38BDF8),
                  onSelected: () => setState(() => _selectedLevel = LogLevel.info),
                ),
                // Filter Chip: Warning
                _buildFilterChip(
                  label: _levelLabel(LogLevel.warning, locale),
                  isSelected: _selectedLevel == LogLevel.warning,
                  color: const Color(0xFFFBBF24),
                  onSelected: () => setState(() => _selectedLevel = LogLevel.warning),
                ),
                // Filter Chip: Error
                _buildFilterChip(
                  label: _levelLabel(LogLevel.error, locale),
                  isSelected: _selectedLevel == LogLevel.error,
                  color: const Color(0xFFF87171),
                  onSelected: () => setState(() => _selectedLevel = LogLevel.error),
                ),
                // Filter Chip: Access
                _buildFilterChip(
                  label: _levelLabel(LogLevel.access, locale),
                  isSelected: _selectedLevel == LogLevel.access,
                  color: const Color(0xFF34D399),
                  onSelected: () => setState(() => _selectedLevel = LogLevel.access),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Main Terminal Console Area
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xFF090D14)
                      : Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: filteredLogs.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _searchQuery.isNotEmpty || _selectedLevel != null
                                    ? Icons.search_off_rounded
                                    : Icons.receipt_long_rounded,
                                size: 48,
                                color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.38),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _searchQuery.isNotEmpty || _selectedLevel != null
                                    ? AppStrings.get("no_matching_logs", locale: locale)
                                    : AppStrings.get("no_logs", locale: locale),
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        )
                      : Scrollbar(
                          controller: _scrollController,
                          thumbVisibility: true,
                          child: ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            itemCount: filteredLogs.length,
                            itemBuilder: (context, index) {
                              final entry = filteredLogs[index];
                              final lvlColor = _levelColor(entry.level);
                              final isDark = Theme.of(context).brightness == Brightness.dark;
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 3),
                                child: SelectableText.rich(
                                  TextSpan(
                                    style: const TextStyle(
                                      fontFamily: "Consolas",
                                      fontSize: 12.5,
                                      height: 1.45,
                                    ),
                                    children: [
                                      // Timestamp
                                      TextSpan(
                                        text: "${entry.formattedTime()} ",
                                        style: TextStyle(
                                          color: isDark ? const Color(0xFF64748B) : Colors.blueGrey.shade600,
                                        ),
                                      ),
                                      // Source tag
                                      TextSpan(
                                        text: "[${entry.source.toUpperCase()}] ",
                                        style: TextStyle(
                                          color: isDark ? const Color(0xFF94A3B8) : Colors.blueGrey.shade700,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      // Level tag
                                      TextSpan(
                                        text: "[${entry.level.name.toUpperCase()}] ",
                                        style: TextStyle(
                                          color: lvlColor,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      // Message
                                      TextSpan(
                                        text: entry.message,
                                        style: TextStyle(
                                          color: entry.level == LogLevel.error
                                              ? (isDark ? const Color(0xFFFFA198) : Colors.red.shade700)
                                              : (entry.level == LogLevel.warning
                                                  ? (isDark ? const Color(0xFFFFE08A) : Colors.amber.shade900)
                                                  : (isDark ? Colors.white : Theme.of(context).colorScheme.onSurface)),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool isSelected,
    required Color color,
    required VoidCallback onSelected,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onSelected,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.18)
              : (isDark ? const Color(0xFF161C28) : Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? color : Theme.of(context).dividerColor,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? color : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
