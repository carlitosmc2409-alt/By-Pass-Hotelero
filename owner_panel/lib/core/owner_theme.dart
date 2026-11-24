import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OwnerTheme {
  static const _themePrefKey = 'staypass_owner_theme_mode';

  /// Controlador reactivo del tema (Oscuro / Claro) persistido para el propietario.
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

  // Paleta "Executive Calm Hospitality" — Cero colores neón, contraste descansado
  static Color get background =>
      isDark ? const Color(0xFF131518) : const Color(0xFFF5F4F0);

  static Color get surface =>
      isDark ? const Color(0xFF1B1E23) : const Color(0xFFEBE8E1);

  static Color get card =>
      isDark ? const Color(0xFF22262C) : const Color(0xFFFFFFFF);

  static Color get border => isDark
      ? const Color(0xFFFFFFFF).withValues(alpha: 0.08)
      : const Color(0xFF1F2328).withValues(alpha: 0.10);

  // Acentos sobrios y profesionales
  static Color get gold =>
      isDark ? const Color(0xFFD2AD6D) : const Color(0xFF8C6229);

  static Color get cyan =>
      isDark ? const Color(0xFF6B9AB8) : const Color(0xFF356382);

  static Color get primary => gold;

  // Estados semánticos suaves (sin brillo neón)
  static Color get available =>
      isDark ? const Color(0xFF529E7E) : const Color(0xFF2C6E52);

  static Color get occupied =>
      isDark ? const Color(0xFFC96A6A) : const Color(0xFFA64242);

  static Color get cleaning =>
      isDark ? const Color(0xFFD49752) : const Color(0xFFB07028);

  static Color get maintenance =>
      isDark ? const Color(0xFF8E84B8) : const Color(0xFF5E538A);

  static Color get textPrimary =>
      isDark ? const Color(0xFFF2EFE9) : const Color(0xFF1F2226);

  static Color get textSecondary =>
      isDark ? const Color(0xFFA0A5AE) : const Color(0xFF61666E);

  static Color get onPrimary =>
      isDark ? const Color(0xFF171614) : const Color(0xFFFFFFFF);

  /// Botón de cambio de tema Claro / Oscuro para las barras superiores del panel.
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

  static ThemeData get theme => darkTheme;
  static ThemeData get darkTheme => _buildTheme(Brightness.dark);
  static ThemeData get lightTheme => _buildTheme(Brightness.light);

  static ThemeData _buildTheme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final bg = dark ? const Color(0xFF131518) : const Color(0xFFF5F4F0);
    final surf = dark ? const Color(0xFF1B1E23) : const Color(0xFFEBE8E1);
    final crd = dark ? const Color(0xFF22262C) : const Color(0xFFFFFFFF);
    final pri = dark ? const Color(0xFFD2AD6D) : const Color(0xFF8C6229);
    final avail = dark ? const Color(0xFF529E7E) : const Color(0xFF2C6E52);
    final cyn = dark ? const Color(0xFF6B9AB8) : const Color(0xFF356382);
    final occ = dark ? const Color(0xFFC96A6A) : const Color(0xFFA64242);
    final txtPri = dark ? const Color(0xFFF2EFE9) : const Color(0xFF1F2226);
    final txtSec = dark ? const Color(0xFFA0A5AE) : const Color(0xFF61666E);
    final onPri = dark ? const Color(0xFF171614) : const Color(0xFFFFFFFF);
    final brd = dark
        ? const Color(0xFFFFFFFF).withValues(alpha: 0.08)
        : const Color(0xFF1F2328).withValues(alpha: 0.10);

    final scheme = dark
        ? ColorScheme.dark(
            primary: pri,
            onPrimary: onPri,
            secondary: avail,
            tertiary: cyn,
            surface: surf,
            onSurface: txtPri,
            error: occ,
          )
        : ColorScheme.light(
            primary: pri,
            onPrimary: onPri,
            secondary: avail,
            tertiary: cyn,
            surface: surf,
            onSurface: txtPri,
            error: occ,
          );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: bg,
      colorScheme: scheme,
      dividerTheme: DividerThemeData(color: brd, thickness: 1),
      appBarTheme: AppBarTheme(
        backgroundColor: dark ? const Color(0xFF16191D) : crd,
        foregroundColor: txtPri,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          color: txtPri,
          fontSize: 17.5,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
      ),
      cardTheme: CardThemeData(
        color: crd,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: brd),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: crd,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
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
            const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: brd),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: brd),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: pri, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: pri,
          foregroundColor: onPri,
          elevation: 0,
          minimumSize: const Size(120, 44),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13.5,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: txtPri,
          side: BorderSide(color: brd),
          minimumSize: const Size(110, 42),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13.5,
          ),
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
