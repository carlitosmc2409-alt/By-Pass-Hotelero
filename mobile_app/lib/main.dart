import 'package:flutter/material.dart';
import 'core/api_client.dart';
import 'core/theme.dart';
import 'screens/auth_screen.dart';
import 'screens/hotels_screen.dart';

void main() {
  runApp(const StayPassApp());
}

class StayPassApp extends StatefulWidget {
  const StayPassApp({super.key});

  @override
  State<StayPassApp> createState() => _StayPassAppState();
}

class _StayPassAppState extends State<StayPassApp> {
  final ApiClient _api = ApiClient();
  bool _authenticated = false;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'StayPass QR',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: _authenticated
          ? HotelsScreen(
              api: _api,
              onLogout: () {
                _api.setAccessToken(null);
                setState(() => _authenticated = false);
              },
            )
          : AuthScreen(
              api: _api,
              onAuthenticated: () => setState(() => _authenticated = true),
            ),
    );
  }
}
