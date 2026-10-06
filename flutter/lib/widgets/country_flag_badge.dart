import 'package:flutter/material.dart';

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
