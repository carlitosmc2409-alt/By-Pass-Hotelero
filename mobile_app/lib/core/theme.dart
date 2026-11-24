import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppTheme {
  static const _themePrefKey = 'staypass_guest_theme_mode';

  /// Controlador reactivo del tema (Oscuro / Claro) persistido en el dispositivo.
  static final ValueNotifier<ThemeMode> themeMode =
      ValueNotifier<ThemeMode>(ThemeMode.dark);

  static bool get isDark => themeMode.value != ThemeMode.light;

  static Future<void> loadSavedTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_themePrefKey);
      if (saved == 'light') {
        themeMode.value = ThemeMode.light;
      } else {
        themeMode.value = ThemeMode.dark;
      }
    } catch (_) {}
  }

  static Future<void> toggleTheme() async {
    final next = isDark ? ThemeMode.light : ThemeMode.dark;
    themeMode.value = next;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _themePrefKey,
        next == ThemeMode.light ? 'light' : 'dark',
      );
    } catch (_) {}
  }

  // Paleta "Soft Boutique Hospitality" — Cero colores neón, tonos orgánicos y cálidos
  static Color get background =>
      isDark ? const Color(0xFF141312) : const Color(0xFFF6F4F0);

  static Color get surface =>
      isDark ? const Color(0xFF1D1B1A) : const Color(0xFFEDE9E2);

  static Color get card =>
      isDark ? const Color(0xFF23211F) : const Color(0xFFFFFFFF);

  static Color get cardLight =>
      isDark ? const Color(0xFF2B2825) : const Color(0xFFF9F7F4);

  static Color get border => isDark
      ? const Color(0xFFFFFFFF).withValues(alpha: 0.08)
      : const Color(0xFF24211E).withValues(alpha: 0.10);

  // Acentos suaves sin saturación neón
  static Color get warmBeige =>
      isDark ? const Color(0xFFD5B399) : const Color(0xFF8C5E42);

  static Color get gold =>
      isDark ? const Color(0xFFCDA768) : const Color(0xFF9C7234);

  static Color get primary => warmBeige;

  // Verde salvia (confirmación suave)
  static Color get accent =>
      isDark ? const Color(0xFF529E7E) : const Color(0xFF2F6F55);

  // Azul pizarra sereno (IoT / FAAC)
  static Color get cyan =>
      isDark ? const Color(0xFF6B9AB8) : const Color(0xFF3A6A88);

  // Ocre suave (avisos)
  static Color get warning =>
      isDark ? const Color(0xFFD49752) : const Color(0xFFB4742E);

  // Terracota suave (errores / alertas)
  static Color get danger =>
      isDark ? const Color(0xFFC96A6A) : const Color(0xFFA84444);

  static Color get textPrimary =>
      isDark ? const Color(0xFFF3EFEA) : const Color(0xFF221F1D);

  static Color get textSecondary =>
      isDark ? const Color(0xFFA69F98) : const Color(0xFF68625C);

  static Color get textMuted =>
      isDark ? const Color(0xFF756E68) : const Color(0xFF968E87);

  static Color get onPrimary =>
      isDark ? const Color(0xFF1A1715) : const Color(0xFFFFFFFF);

  static Color get onAccent =>
      isDark ? const Color(0xFF121614) : const Color(0xFFFFFFFF);

  static LinearGradient roomTierGradient(String type) {
    if (!isDark) {
      switch (type.toUpperCase()) {
        case 'SUITE':
          return const LinearGradient(
            colors: [Color(0xFFEFE6DC), Color(0xFFF8F6F2)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          );
        case 'PREMIUM':
          return const LinearGradient(
            colors: [Color(0xFFF2E8DC), Color(0xFFF8F6F2)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          );
        case 'DELUXE':
          return const LinearGradient(
            colors: [Color(0xFFE7EBF0), Color(0xFFF8F6F2)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          );
        default:
          return const LinearGradient(
            colors: [Color(0xFFEAECEF), Color(0xFFF8F6F2)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          );
      }
    }

    switch (type.toUpperCase()) {
      case 'SUITE':
        return const LinearGradient(
          colors: [Color(0xFF2C241E), Color(0xFF1E1C1A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case 'PREMIUM':
        return const LinearGradient(
          colors: [Color(0xFF2E2320), Color(0xFF1E1C1A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case 'DELUXE':
        return const LinearGradient(
          colors: [Color(0xFF232730), Color(0xFF1E1C1A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      default:
        return const LinearGradient(
          colors: [Color(0xFF20252B), Color(0xFF1C1B1A)],
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
        return isDark ? const Color(0xFF8E84B8) : const Color(0xFF5D5387);
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

  /// Botón rápido para alternar entre Modo Claro y Modo Oscuro en cualquier AppBar.
  static Widget themeToggleButton({Color? iconColor}) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeMode,
      builder: (context, mode, _) {
        final dark = mode != ThemeMode.light;
        return IconButton(
          tooltip: dark ? 'Cambiar a tema claro' : 'Cambiar a tema oscuro',
          onPressed: toggleTheme,
          icon: Icon(
            dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
            color: iconColor ?? textSecondary,
            size: 20,
          ),
        );
      },
    );
  }

  static ThemeData get darkTheme => _buildTheme(Brightness.dark);
  static ThemeData get lightTheme => _buildTheme(Brightness.light);

  static ThemeData _buildTheme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final bg = dark ? const Color(0xFF141312) : const Color(0xFFF6F4F0);
    final surf = dark ? const Color(0xFF1D1B1A) : const Color(0xFFEDE9E2);
    final crd = dark ? const Color(0xFF23211F) : const Color(0xFFFFFFFF);
    final pri = dark ? const Color(0xFFD5B399) : const Color(0xFF8C5E42);
    final sec = dark ? const Color(0xFFCDA768) : const Color(0xFF9C7234);
    final ter = dark ? const Color(0xFF529E7E) : const Color(0xFF2F6F55);
    final err = dark ? const Color(0xFFC96A6A) : const Color(0xFFA84444);
    final txtPri = dark ? const Color(0xFFF3EFEA) : const Color(0xFF221F1D);
    final txtSec = dark ? const Color(0xFFA69F98) : const Color(0xFF68625C);
    final onPri = dark ? const Color(0xFF1A1715) : const Color(0xFFFFFFFF);
    final brd = dark
        ? const Color(0xFFFFFFFF).withValues(alpha: 0.08)
        : const Color(0xFF24211E).withValues(alpha: 0.10);

    final scheme = dark
        ? ColorScheme.dark(
            primary: pri,
            onPrimary: onPri,
            secondary: sec,
            tertiary: ter,
            surface: surf,
            onSurface: txtPri,
            error: err,
          )
        : ColorScheme.light(
            primary: pri,
            onPrimary: onPri,
            secondary: sec,
            tertiary: ter,
            surface: surf,
            onSurface: txtPri,
            error: err,
          );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: bg,
      colorScheme: scheme,
      dividerTheme: DividerThemeData(color: brd, thickness: 1),
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: txtPri,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: txtPri,
          fontSize: 19,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
      ),
      cardTheme: CardThemeData(
        color: crd,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: brd),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: crd,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: brd),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? surf : crd,
        labelStyle: TextStyle(color: txtSec, fontSize: 13.5),
        hintStyle: TextStyle(color: txtSec.withValues(alpha: 0.6)),
        prefixIconColor: txtSec,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: brd),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: brd),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: pri, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: pri,
          foregroundColor: onPri,
          minimumSize: const Size.fromHeight(50),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.1,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: txtPri,
          side: BorderSide(color: brd),
          minimumSize: const Size.fromHeight(46),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surf,
        selectedColor: pri,
        side: BorderSide(color: brd),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: crd,
        contentTextStyle: TextStyle(
          color: txtPri,
          fontWeight: FontWeight.w600,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: brd),
        ),
      ),
    );
  }
}
