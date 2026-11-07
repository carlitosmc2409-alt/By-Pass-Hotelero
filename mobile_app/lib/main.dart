import 'package:flutter/material.dart';
import 'core/api_client.dart';
import 'core/theme.dart';
import 'screens/auth_screen.dart';
import 'screens/hotels_screen.dart';
import 'screens/stealth_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
  void initState() {
    super.initState();
    _restoreSavedSession();
  }

  Future<void> _restoreSavedSession() async {
    final ok = await _api.restoreSession();
    if (ok && mounted) {
      setState(() => _authenticated = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'StayPass QR',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      builder: (context, child) {
        return ValueListenableBuilder<bool>(
          valueListenable: StealthCalculatorScreen.active,
          builder: (context, isStealth, _) {
            if (isStealth) {
              return StealthCalculatorScreen(
                onUnlock: StealthCalculatorScreen.disable,
              );
            }
            return child ?? const SizedBox.shrink();
          },
        );
      },
      home: _authenticated
          ? HotelsScreen(
              api: _api,
              onLogout: () async {
                await _api.logout();
                if (mounted) {
                  setState(() => _authenticated = false);
                }
              },
            )
          : AuthScreen(
              api: _api,
              onAuthenticated: () => setState(() => _authenticated = true),
            ),
    );
  }
}
