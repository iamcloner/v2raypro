import 'package:flutter/material.dart';
import '../core/l10n/translations.dart';
import '../core/theme/app_theme.dart';
import '../models/proxy_node.dart';
import '../services/country_service.dart';
import 'country_flag_badge.dart';

class CountryFilterBar extends StatelessWidget {
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
  Widget build(BuildContext context) {
    if (nodes.isEmpty) return const SizedBox.shrink();

    // Group tested nodes by country
    final Map<String, int> counts = {};
    int unknownCount = 0;
    int testedCount = 0;

    for (final node in nodes) {
      if (node.hasValidPing) {
        testedCount++;
        final code = node.countryCode?.trim().toUpperCase();
        if (code != null && code.length == 2) {
          counts[code] = (counts[code] ?? 0) + 1;
        } else {
          unknownCount++;
        }
      }
    }

    if (testedCount == 0 && counts.isEmpty && unknownCount == 0) {
      return const SizedBox.shrink();
    }

    final sortedCountryCodes = counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: FilterChip(
                avatar: const Icon(Icons.public_rounded, size: 16),
                label: Text(
                  '${AppStrings.get('all_countries', locale: locale)} ($testedCount)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: selectedCountryCode == null ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                selected: selectedCountryCode == null,
                selectedColor: AppTheme.primaryAccent.withValues(alpha: 0.25),
                checkmarkColor: AppTheme.primaryAccent,
                onSelected: (_) => onCountrySelected(null),
              ),
            ),
            ...sortedCountryCodes.map((code) {
              final isSelected = selectedCountryCode == code;
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
                  onSelected: (_) => onCountrySelected(isSelected ? null : code),
                ),
              );
            }),
            if (unknownCount > 0)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: FilterChip(
                  avatar: const Icon(Icons.help_outline_rounded, size: 15, color: Colors.grey),
                  label: Text(
                    '${AppStrings.get('unknown_country', locale: locale)} ($unknownCount)',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade300,
                      fontWeight: selectedCountryCode == '__unknown__' ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  selected: selectedCountryCode == '__unknown__',
                  selectedColor: Colors.grey.withValues(alpha: 0.25),
                  checkmarkColor: Colors.white,
                  onSelected: (_) => onCountrySelected(
                    selectedCountryCode == '__unknown__' ? null : '__unknown__',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
