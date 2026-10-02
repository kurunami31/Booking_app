import 'package:flutter/material.dart';

/// SakayTa design tokens: a calm civic teal with amber for fares and rose
/// reserved for SOS and destructive actions.
class AppTheme {
  const AppTheme._();

  static const Color brand50 = Color(0xFFECFEFF);
  static const Color brand100 = Color(0xFFCFFAFE);
  static const Color brand200 = Color(0xFFA5F3FC);
  static const Color brand500 = Color(0xFF06B6D4);
  static const Color brand600 = Color(0xFF0891B2);
  static const Color brand700 = Color(0xFF0E7490);
  static const Color brand800 = Color(0xFF155E75);
  static const Color brand900 = Color(0xFF164E63);

  static const Color fare100 = Color(0xFFFEF3C7);
  static const Color fare700 = Color(0xFFB45309);

  static const Color sos500 = Color(0xFFE11D48);
  static const Color sos600 = Color(0xFFBE123C);

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: brand700,
      primary: brand700,
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFFF1F5F9),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: Color(0xFF0F172A),
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: brand600, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          side: const BorderSide(color: Color(0xFFCBD5E1)),
          foregroundColor: const Color(0xFF1E293B),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: brand50,
      ),
      dividerTheme: const DividerThemeData(color: Color(0xFFE2E8F0)),
    );
  }
}
