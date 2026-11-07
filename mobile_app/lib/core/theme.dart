import 'package:flutter/material.dart';

class AppTheme {
  // Paleta "Nocturnal Boutique / Stealth Luxury"
  static const Color background = Color(0xFF07080D); // Obsidiana profunda
  static const Color surface = Color(0xFF10131E);    // Cristal ahumado oscuro
  static const Color card = Color(0xFF151927);       // Terciopelo nocturno
  static const Color gold = Color(0xFFE5B869);       // Ámbar Champán VIP
  static const Color primary = Color(0xFF7C5CFF);    // Violeta eléctrico sutil
  static const Color accent = Color(0xFF10B981);     // Esmeralda verificación / QR activo
  static const Color cyan = Color(0xFF38BDF8);       // Azul FAAC / IoT
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFF43F5E);
  static const Color textPrimary = Color(0xFFF8FAFC);
  static const Color textSecondary = Color(0xFF94A3B8);

  static LinearGradient roomTierGradient(String type) {
    switch (type.toUpperCase()) {
      case 'SUITE':
        return const LinearGradient(
          colors: [Color(0xFF2B2112), Color(0xFF161826)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case 'PREMIUM':
        return const LinearGradient(
          colors: [Color(0xFF2D1424), Color(0xFF151828)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case 'DELUXE':
        return const LinearGradient(
          colors: [Color(0xFF1E1938), Color(0xFF141827)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      default:
        return const LinearGradient(
          colors: [Color(0xFF142234), Color(0xFF131826)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
    }
  }

  static Color roomTierAccent(String type) {
    switch (type.toUpperCase()) {
      case 'SUITE':
        return gold;
      case 'PREMIUM':
        return const Color(0xFFF472B6);
      case 'DELUXE':
        return const Color(0xFFA78BFA);
      default:
        return cyan;
    }
  }

  static String roomTierLabel(String type) {
    switch (type.toUpperCase()) {
      case 'SUITE':
        return 'Suite Boutique';
      case 'PREMIUM':
        return 'Jacuzzi VIP';
      case 'DELUXE':
        return 'Deluxe Privada';
      default:
        return 'Confort Discreto';
    }
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      colorScheme: const ColorScheme.dark(
        primary: gold,
        secondary: accent,
        tertiary: primary,
        surface: surface,
        error: danger,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF0A0C14),
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 19,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        labelStyle: const TextStyle(color: textSecondary, fontSize: 13.5),
        hintStyle: TextStyle(color: textSecondary.withValues(alpha: 0.55)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.09)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.09)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: gold, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: gold,
          foregroundColor: const Color(0xFF090A0F),
          minimumSize: const Size.fromHeight(50),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          side: BorderSide(color: Colors.white.withValues(alpha: 0.16)),
          minimumSize: const Size.fromHeight(46),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}
