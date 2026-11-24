import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pms_guest_app/core/theme.dart';
import 'package:pms_guest_app/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
      'StayPassApp renders login screen and toggles between dark and light themes',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await AppTheme.loadSavedTheme();
    await tester.pumpWidget(const StayPassApp());
    await tester.pump();

    expect(find.text('StayPass QR'), findsOneWidget);
    expect(find.text('Iniciar sesión'), findsOneWidget);
    expect(find.text('Crear cuenta'), findsOneWidget);
    expect(AppTheme.themeMode.value, ThemeMode.dark);

    // Alternar a tema claro desde el botón de tema en la interfaz
    final themeToggle = find.byIcon(Icons.light_mode_outlined);
    expect(themeToggle, findsOneWidget);
    await tester.tap(themeToggle);
    await tester.pumpAndSettle();

    expect(AppTheme.themeMode.value, ThemeMode.light);
    expect(find.byIcon(Icons.dark_mode_outlined), findsOneWidget);
  });
}
