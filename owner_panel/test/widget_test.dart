import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pms_owner_panel/core/owner_theme.dart';
import 'package:pms_owner_panel/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
      'OwnerPanelApp muestra la pantalla de acceso y permite cambiar entre tema oscuro y claro',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await OwnerTheme.loadSavedTheme();
    await tester.pumpWidget(const OwnerPanelApp());
    await tester.pump();

    expect(find.text('StayPass · Panel del Propietario'), findsOneWidget);
    expect(find.text('Acceder al Panel'), findsOneWidget);
    expect(find.text('Correo electrónico'), findsOneWidget);
    expect(OwnerTheme.themeMode.value, ThemeMode.dark);

    final themeToggle = find.byIcon(Icons.light_mode_outlined);
    expect(themeToggle, findsOneWidget);
    await tester.tap(themeToggle);
    await tester.pumpAndSettle();

    expect(OwnerTheme.themeMode.value, ThemeMode.light);
    expect(find.byIcon(Icons.dark_mode_outlined), findsOneWidget);
  });
}
