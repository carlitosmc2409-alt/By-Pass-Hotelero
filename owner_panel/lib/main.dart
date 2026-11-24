import 'dart:async';
import 'package:flutter/material.dart';
import 'core/owner_api.dart';
import 'core/owner_theme.dart';
import 'screens/cleaning_board_screen.dart';
import 'screens/owner_dashboard_screen.dart';
import 'screens/owner_login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await OwnerTheme.loadSavedTheme();
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
    unawaited(_restoreSavedSession());
  }

  Future<void> _restoreSavedSession() async {
    final ok = await _api.restoreSession();
    if (ok && mounted) {
      setState(() => _authenticated = true);
    }
  }

  Future<void> _handleLogout() async {
    await _api.logout();
    if (mounted) {
      setState(() => _authenticated = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: OwnerTheme.themeMode,
      builder: (context, currentMode, _) {
        return MaterialApp(
          title: 'StayPass · Panel del Propietario',
          debugShowCheckedModeBanner: false,
          theme: OwnerTheme.lightTheme,
          darkTheme: OwnerTheme.darkTheme,
          themeMode: currentMode,
          home: !_authenticated
              ? OwnerLoginScreen(
                  api: _api,
                  onAuthenticated: () => setState(() => _authenticated = true),
                )
              : _api.isCleaningRole
                  ? CleaningBoardScreen(
                      api: _api,
                      onLogout: _handleLogout,
                    )
                  : OwnerDashboardScreen(
                      api: _api,
                      onLogout: _handleLogout,
                    ),
        );
      },
    );
  }
}
