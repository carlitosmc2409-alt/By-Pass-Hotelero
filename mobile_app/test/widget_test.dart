import 'package:flutter_test/flutter_test.dart';
import 'package:pms_guest_app/main.dart';

void main() {
  testWidgets('StayPassApp renders login and registration screen', (WidgetTester tester) async {
    await tester.pumpWidget(const StayPassApp());

    expect(find.text('StayPass QR'), findsOneWidget);
    expect(find.text('Iniciar sesión'), findsOneWidget);
    expect(find.text('Crear cuenta'), findsOneWidget);
  });
}
