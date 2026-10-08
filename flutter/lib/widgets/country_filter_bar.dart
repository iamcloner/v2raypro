import 'dart:ui';
import 'package:flutter/material.dart';
import '../core/l10n/translations.dart';
import '../core/theme/app_theme.dart';
import '../models/proxy_node.dart';
import '../services/country_service.dart';
import 'country_flag_badge.dart';

class CountryFilterBar extends StatefulWidget {
  final List<ProxyNode> nodes;
  final String? selectedCountryCode; // null = all, '__unknown__' = unknown
  final ValueChanged<String?> onCountrySelected;
  final String locale;

  const CountryFilterBar({
    super.key,
    required this.nodes,
    required this.selectedCountryCode,
    required this.onCountrySelected,
    required this.locale,
  });

  @override
  State<CountryFilterBar> createState() => _CountryFilterBarState();
}

class _CountryFilterBarState extends State<CountryFilterBar> {
  final ScrollController _scrollController = ScrollController();
  bool _canScrollLeft = false;
  bool _canScrollRight = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateScrollButtons);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateScrollButtons());
  }

  @override
  void didUpdateWidget(covariant CountryFilterBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateScrollButtons());
  }

  @override
  void dispose() {
    _scrollController.removeListener(_updateScrollButtons);
    _scrollController.dispose();
    super.dispose();
  }

  void _updateScrollButtons() {
    if (!mounted || !_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.offset;
    final canLeft = currentScroll > 8;
    final canRight = currentScroll < maxScroll - 8;
    if (canLeft != _canScrollLeft || canRight != _canScrollRight) {
      setState(() {
        _canScrollLeft = canLeft;
        _canScrollRight = canRight;
      });
    }
  }

  void _scroll(double delta) {
    if (!_scrollController.hasClients) return;
    final target = (_scrollController.offset + delta)
        .clamp(0.0, _scrollController.position.maxScrollExtent);
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.nodes.isEmpty) return const SizedBox.shrink();

    // Group tested nodes by country (only healthy nodes) and track timeouts
    final Map<String, int> counts = {};
    int unknownCount = 0;
    int healthyTestedCount = 0;
    int timeoutCount = 0;

    for (final node in widget.nodes) {
      if (node.hasValidPing) {
        healthyTestedCount++;
        final code = node.countryCode?.trim().toUpperCase();
        if (code != null && code.length == 2) {
          counts[code] = (counts[code] ?? 0) + 1;
        } else {
          unknownCount++;
        }
      } else if (node.hasTimedOut) {
        timeoutCount++;
      }
    }

    if (healthyTestedCount == 0 && counts.isEmpty && unknownCount == 0 && timeoutCount == 0) {
      return const SizedBox.shrink();
    }

    final sortedCountryCodes = counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));

    final isRtl = widget.locale == 'fa';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          if (_canScrollLeft)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => _scroll(isRtl ? 150 : -150),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white24, width: 0.8),
                  ),
                  child: Icon(
                    isRtl ? Icons.chevron_right_rounded : Icons.chevron_left_rounded,
                    size: 18,
                    color: AppTheme.primaryAccent,
                  ),
                ),
              ),
            ),
          Expanded(
            child: ScrollConfiguration(
              behavior: const MaterialScrollBehavior().copyWith(
                dragDevices: {
                  PointerDeviceKind.touch,
                  PointerDeviceKind.mouse,
                  PointerDeviceKind.trackpad,
                  PointerDeviceKind.stylus,
                },
              ),
              child: SingleChildScrollView(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        avatar: const Icon(Icons.public_rounded, size: 16),
                        label: Text(
                          '${AppStrings.get('all_countries', locale: widget.locale)} ($healthyTestedCount)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: widget.selectedCountryCode == null ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        selected: widget.selectedCountryCode == null,
                        selectedColor: AppTheme.primaryAccent.withValues(alpha: 0.25),
                        checkmarkColor: AppTheme.primaryAccent,
                        onSelected: (_) => widget.onCountrySelected(null),
                      ),
                    ),
                    ...sortedCountryCodes.map((code) {
                      final isSelected = widget.selectedCountryCode == code;
                      final count = counts[code]!;
                      final name = CountryService.getCountryName(code) ?? code;

                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: FilterChip(
                          avatar: CountryFlagBadge(countryCode: code, width: 18, height: 13),
                          label: Text(
                            '$code ($count)',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          tooltip: '$name ($count)',
                          selected: isSelected,
                          selectedColor: AppTheme.primaryAccent.withValues(alpha: 0.25),
                          checkmarkColor: AppTheme.primaryAccent,
                          onSelected: (_) => widget.onCountrySelected(isSelected ? null : code),
                        ),
                      );
                    }),
                    if (unknownCount > 0)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: FilterChip(
                          avatar: const Icon(Icons.help_outline_rounded, size: 15, color: Colors.grey),
                          label: Text(
                            '${AppStrings.get('unknown_country', locale: widget.locale)} ($unknownCount)',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade300,
                              fontWeight: widget.selectedCountryCode == '__unknown__' ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          selected: widget.selectedCountryCode == '__unknown__',
                          selectedColor: Colors.grey.withValues(alpha: 0.25),
                          checkmarkColor: Colors.white,
                          onSelected: (_) => widget.onCountrySelected(
                            widget.selectedCountryCode == '__unknown__' ? null : '__unknown__',
                          ),
                        ),
                      ),
                    if (timeoutCount > 0)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: FilterChip(
                          avatar: const Icon(Icons.timer_off_rounded, size: 15, color: Colors.redAccent),
                          label: Text(
                            '${AppStrings.get('timeouts_category', locale: widget.locale)} ($timeoutCount)',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.redAccent.shade100,
                              fontWeight: widget.selectedCountryCode == '__timeouts__' ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          selected: widget.selectedCountryCode == '__timeouts__',
                          selectedColor: Colors.redAccent.withValues(alpha: 0.25),
                          checkmarkColor: Colors.white,
                          onSelected: (_) => widget.onCountrySelected(
                            widget.selectedCountryCode == '__timeouts__' ? null : '__timeouts__',
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (_canScrollRight)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => _scroll(isRtl ? -150 : 150),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white24, width: 0.8),
                  ),
                  child: Icon(
                    isRtl ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
                    size: 18,
                    color: AppTheme.primaryAccent,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
