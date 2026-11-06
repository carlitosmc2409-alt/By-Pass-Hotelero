import 'package:flutter/material.dart';
import 'core/owner_api.dart';
import 'core/owner_theme.dart';
import 'screens/owner_dashboard_screen.dart';
import 'screens/owner_login_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const OwnerPanelApp());
}

class OwnerPanelApp extends StatefulWidget {
  const OwnerPanelApp({super.key});

  @override
  State<OwnerPanelApp> createState() => _OwnerPanelAppState();
}

class _OwnerPanelAppState extends State<OwnerPanelApp> {
  final OwnerApiClient _api = OwnerApiClient();
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
      title: 'StayPass · Panel del Propietario',
      debugShowCheckedModeBanner: false,
      theme: OwnerTheme.theme,
      home: _authenticated
          ? OwnerDashboardScreen(
              api: _api,
              onLogout: () async {
                await _api.logout();
                if (mounted) {
                  setState(() => _authenticated = false);
                }
              },
            )
          : OwnerLoginScreen(
              api: _api,
              onAuthenticated: () => setState(() => _authenticated = true),
            ),
    );
  }
}
