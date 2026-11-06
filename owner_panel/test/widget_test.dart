import 'package:flutter_test/flutter_test.dart';
import 'package:pms_owner_panel/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('OwnerPanelApp muestra la pantalla de acceso del propietario',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const OwnerPanelApp());
    await tester.pump();

    expect(find.text('StayPass · Panel del Propietario'), findsOneWidget);
    expect(find.text('Acceder al Panel'), findsOneWidget);
    expect(find.text('Correo electrónico'), findsOneWidget);
  });
}
