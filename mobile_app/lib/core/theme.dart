import 'package:flutter/material.dart';

class AppTheme {
  // Paleta "Hotel Booking Luxury Warm / Nocturnal Boutique"
  // Inspirada en diseño boutique cálido (#E0BDAF, #2C2C2C, #FFD33C, etc.)
  static const Color background = Color(0xFF0A0C13); // Fondo oscuro profundo refinado
  static const Color surface = Color(0xFF141824);    // Superficie contenedores oscuros
  static const Color card = Color(0xFF181C2B);       // Tarjetas con bordes ultra suaves
  static const Color cardLight = Color(0xFF222738);  // Tarjetas secundarias elevadas
  static const Color warmBeige = Color(0xFFE0BDAF);  // Beige rosado cálido boutique (principal del diseño)
  static const Color gold = Color(0xFFFFD33C);       // Amarillo dorado radiante (estrellas / acentos)
  static const Color primary = warmBeige;            // Botones principales y destacados
  static const Color accent = Color(0xFF10B981);     // Verde esmeralda confirmación
  static const Color cyan = Color(0xFF38BDF8);       // Azul FAAC / IoT
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFF43F5E);
  static const Color textPrimary = Color(0xFFF8FAFC);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF64748B);
  static const Color brownAccent = Color(0xFF524E48); // Tono tierra neutro del mockup

  static LinearGradient roomTierGradient(String type) {
    switch (type.toUpperCase()) {
      case 'SUITE':
        return const LinearGradient(
          colors: [Color(0xFF2E241E), Color(0xFF191D2C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case 'PREMIUM':
        return const LinearGradient(
          colors: [Color(0xFF321F28), Color(0xFF191D2C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case 'DELUXE':
        return const LinearGradient(
          colors: [Color(0xFF23253B), Color(0xFF181C2B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      default:
        return const LinearGradient(
          colors: [Color(0xFF1A2332), Color(0xFF161A28)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
    }
  }

  static Color roomTierAccent(String type) {
    switch (type.toUpperCase()) {
      case 'SUITE':
        return warmBeige;
      case 'PREMIUM':
        return gold;
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
        primary: warmBeige,
        secondary: gold,
        tertiary: accent,
        surface: surface,
        error: danger,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
        ),
      ),
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.07)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        labelStyle: const TextStyle(color: textSecondary, fontSize: 13.5),
        hintStyle: TextStyle(color: textSecondary.withValues(alpha: 0.55)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: warmBeige, width: 1.6),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: warmBeige,
          foregroundColor: const Color(0xFF1E1B18),
          minimumSize: const Size.fromHeight(52),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          textStyle: const TextStyle(
            fontSize: 15.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.3,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          side: BorderSide(color: Colors.white.withValues(alpha: 0.16)),
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
    );
  }
}
