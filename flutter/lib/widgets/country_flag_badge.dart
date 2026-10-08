import 'package:flutter/material.dart';
import '../services/cdn_scanner_service.dart';

class CountryFlagBadge extends StatelessWidget {
  final String? countryCode;
  final double width;
  final double height;

  const CountryFlagBadge({
    super.key,
    required this.countryCode,
    this.width = 24,
    this.height = 17,
  });

  @override
  Widget build(BuildContext context) {
    if (countryCode == null || countryCode!.trim().length != 2) {
      return const Icon(Icons.public_rounded, size: 18, color: Colors.blueAccent);
    }

    final code = countryCode!.trim().toUpperCase();
    final assetPath = 'assets/flags/${code.toLowerCase()}.png';

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: Colors.white24, width: 0.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2.5),
        child: Image.asset(
          assetPath,
          width: width,
          height: height,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              color: const Color(0xFF1E2638),
              alignment: Alignment.center,
              child: Text(
                code,
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: Colors.white70,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class CdnBadge extends StatelessWidget {
  final CdnProvider cdn;
  const CdnBadge({super.key, required this.cdn});

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    IconData icon;

    switch (cdn) {
      case CdnProvider.cloudflare:
        color = Colors.amber;
        label = "CF";
        icon = Icons.bolt_rounded;
        break;
      case CdnProvider.fastly:
        color = const Color(0xFFFF4D4F); // Vibrant Red/Crimson
        label = "Fastly";
        icon = Icons.flash_on_rounded;
        break;
      case CdnProvider.awsCloudFront:
        color = const Color(0xFFFF9900); // AWS Orange
        label = "AWS";
        icon = Icons.cloud_done_rounded;
        break;
      case CdnProvider.gcore:
        color = const Color(0xFFA855F7); // Purple/Violet
        label = "G-Core";
        icon = Icons.dns_rounded;
        break;
      case CdnProvider.arvancloud:
        color = const Color(0xFF00E5FF); // Electric Cyan/Teal
        label = "Arvan";
        icon = Icons.cloud_circle_rounded;
        break;
    }

    return Tooltip(
      message: "${cdn.displayName} CDN",
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color, width: 0.8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CountryPillBadge extends StatelessWidget {
  final String? countryCode;
  final String? country;
  final bool showUnknown;

  const CountryPillBadge({
    super.key,
    required this.countryCode,
    this.country,
    this.showUnknown = false,
  });

  @override
  Widget build(BuildContext context) {
    if (countryCode == null || countryCode!.trim().length != 2) {
      if (!showUnknown) return const SizedBox.shrink();
      return Tooltip(
        message: 'Unknown Country (نامشخص)',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: Colors.white12, width: 0.8),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.public_rounded, size: 13, color: Colors.blueAccent),
              SizedBox(width: 4),
              Text(
                '??',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final code = countryCode!.trim().toUpperCase();
    final tooltipText = (country != null && country!.isNotEmpty) ? '$country ($code)' : 'Country: $code';

    return Tooltip(
      message: tooltipText,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2.5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: Colors.white24, width: 0.8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CountryFlagBadge(countryCode: code, width: 18, height: 13),
            const SizedBox(width: 4),
            Text(
              code,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
