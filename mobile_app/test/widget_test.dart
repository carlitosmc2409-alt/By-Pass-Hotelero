import 'package:flutter_test/flutter_test.dart';
import 'package:pms_guest_app/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('StayPassApp renders login and registration screen',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const StayPassApp());
    await tester.pump();

    expect(find.text('StayPass QR'), findsOneWidget);
    expect(find.text('Iniciar sesión'), findsOneWidget);
    expect(find.text('Crear cuenta'), findsOneWidget);
  });
}
