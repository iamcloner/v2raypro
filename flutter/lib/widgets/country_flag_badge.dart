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
    final flagUrl = 'https://flagcdn.com/w40/${code.toLowerCase()}.png';

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
        child: Image.network(
          flagUrl,
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
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return Container(
              color: const Color(0xFF1E2638),
              alignment: Alignment.center,
              child: Text(
                code,
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: Colors.white54,
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
