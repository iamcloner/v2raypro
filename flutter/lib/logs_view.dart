import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "core/l10n/translations.dart";
import "core/theme/app_theme.dart";
import "models/log_entry.dart";
import "providers/app_providers.dart";

class LogsView extends ConsumerStatefulWidget {
  const LogsView({super.key});

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
      backgroundColor: const Color(0xFF0F131C),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E2433),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    "${filteredLogs.length}",
                    style: const TextStyle(fontSize: 12, color: Colors.white70, fontWeight: FontWeight.bold),
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
                          : const Color(0xFF1E2433),
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
                          color: _autoScroll ? AppTheme.primaryAccent : Colors.white60,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          AppStrings.get("autoscroll", locale: locale),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _autoScroll ? AppTheme.primaryAccent : Colors.white60,
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
                  icon: const Icon(Icons.copy_rounded, size: 19, color: Colors.white70),
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFF1E2433),
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
                    backgroundColor: const Color(0xFF1E2433),
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
                    style: const TextStyle(fontSize: 13, color: Colors.white),
                    decoration: InputDecoration(
                      hintText: AppStrings.get("search_logs", locale: locale),
                      hintStyle: const TextStyle(fontSize: 12, color: Colors.white38),
                      prefixIcon: const Icon(Icons.search_rounded, size: 18, color: Colors.white38),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 16, color: Colors.white38),
                              onPressed: () => _searchController.clear(),
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                      filled: true,
                      fillColor: const Color(0xFF161C28),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFF263044)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFF263044)),
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
                  color: const Color(0xFF090D14),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF1E2638), width: 1),
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
                                color: Colors.white24,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _searchQuery.isNotEmpty || _selectedLevel != null
                                    ? AppStrings.get("no_matching_logs", locale: locale)
                                    : AppStrings.get("no_logs", locale: locale),
                                style: const TextStyle(color: Colors.white54, fontSize: 14),
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
                                        style: const TextStyle(color: Color(0xFF64748B)),
                                      ),
                                      // Source tag
                                      TextSpan(
                                        text: "[${entry.source.toUpperCase()}] ",
                                        style: const TextStyle(
                                          color: Color(0xFF94A3B8),
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
                                              ? const Color(0xFFFFA198)
                                              : (entry.level == LogLevel.warning
                                                  ? const Color(0xFFFFE08A)
                                                  : Colors.white),
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
    return InkWell(
      onTap: onSelected,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.18) : const Color(0xFF161C28),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? color : const Color(0xFF263044),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? color : Colors.white70,
          ),
        ),
      ),
    );
  }
}
