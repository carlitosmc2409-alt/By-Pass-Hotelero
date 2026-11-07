import 'package:flutter/material.dart';

class OwnerTheme {
  // Paleta "Executive Nocturnal Command Center"
  static const Color background = Color(0xFF07090F);
  static const Color surface = Color(0xFF101420);
  static const Color card = Color(0xFF151B2B);
  static const Color gold = Color(0xFFE5B869);
  static const Color cyan = Color(0xFF38BDF8);
  static const Color primary = Color(0xFF38BDF8);
  static const Color available = Color(0xFF10B981);
  static const Color occupied = Color(0xFFF43F5E);
  static const Color cleaning = Color(0xFFF59E0B);
  static const Color maintenance = Color(0xFFA78BFA);
  static const Color textPrimary = Color(0xFFF8FAFC);
  static const Color textSecondary = Color(0xFF94A3B8);

  static ThemeData get theme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      colorScheme: const ColorScheme.dark(
        primary: gold,
        secondary: available,
        tertiary: cyan,
        surface: surface,
        error: occupied,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF0B0E17),
        elevation: 0,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
        ),
      ),
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        labelStyle: const TextStyle(color: textSecondary, fontSize: 13.5),
        contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.09)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.09)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: gold, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: gold,
          foregroundColor: const Color(0xFF08090E),
          elevation: 0,
          minimumSize: const Size(120, 46),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          side: BorderSide(color: Colors.white.withValues(alpha: 0.16)),
          minimumSize: const Size(110, 42),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}
