import "package:flutter/material.dart";

class AppTheme {
  static const primaryAccent = Color(0xFF6366F1); // Modern Indigo
  static const secondaryAccent = Color(0xFF8B5CF6); // Purple
  static const successColor = Color(0xFF10B981); // Emerald Green
  static const errorColor = Color(0xFFEF4444); // Red
  static const warningColor = Color(0xFFF59E0B); // Amber

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: "AppFont",
      colorScheme: const ColorScheme.dark(
        primary: primaryAccent,
        secondary: secondaryAccent,
        surface: Color(0xFF131722),
        error: errorColor,
        onSurface: Color(0xFFE2E8F0),
      ),
      scaffoldBackgroundColor: const Color(0xFF0B0E14),
      cardTheme: CardThemeData(
        color: const Color(0xFF171C28),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF222938), width: 1),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF0B0E14),
        elevation: 0,
        centerTitle: false,
      ),
    );
  }

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      fontFamily: "AppFont",
      colorScheme: const ColorScheme.light(
        primary: primaryAccent,
        secondary: secondaryAccent,
        surface: Color(0xFFF8FAFC),
        error: errorColor,
      ),
      scaffoldBackgroundColor: const Color(0xFFF1F5F9),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFE2E8F0), width: 1),
        ),
      ),
    );
  }
}
