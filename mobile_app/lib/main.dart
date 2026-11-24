import 'dart:async';
import 'package:flutter/material.dart';
import 'core/api_client.dart';
import 'core/theme.dart';
import 'screens/auth_screen.dart';
import 'screens/hotels_screen.dart';
import 'screens/receptionist_dashboard_screen.dart';
import 'screens/cleaning_dashboard_screen.dart';
import 'screens/stealth_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppTheme.loadSavedTheme();
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
    unawaited(_restoreSavedSession());
  }

  Future<void> _restoreSavedSession() async {
    final ok = await _api.restoreSession();
    if (ok && mounted) {
      setState(() => _authenticated = true);
    }
  }

  Widget _buildAuthenticatedHome() {
    switch (_api.currentRole) {
      case 'RECEPTIONIST':
        return ReceptionistDashboardScreen(
          api: _api,
          onLogout: () async {
            await _api.logout();
            if (mounted) {
              setState(() => _authenticated = false);
            }
          },
        );
      case 'CLEANING':
        return CleaningDashboardScreen(
          api: _api,
          onLogout: () async {
            await _api.logout();
            if (mounted) {
              setState(() => _authenticated = false);
            }
          },
        );
      case 'GUEST':
      default:
        return HotelsScreen(
          api: _api,
          onLogout: () async {
            await _api.logout();
            if (mounted) {
              setState(() => _authenticated = false);
            }
          },
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppTheme.themeMode,
      builder: (context, currentMode, _) {
        return MaterialApp(
          title: 'StayPass',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: currentMode,
          builder: (context, child) {
            return ValueListenableBuilder<bool>(
              valueListenable: StealthCalculatorScreen.active,
              builder: (context, isStealth, _) {
                if (isStealth) {
                  return const StealthCalculatorScreen(
                    onUnlock: StealthCalculatorScreen.disable,
                  );
                }
                return child ?? const SizedBox.shrink();
              },
            );
          },
          home: _authenticated
              ? _buildAuthenticatedHome()
              : AuthScreen(
                  api: _api,
                  onAuthenticated: () => setState(() => _authenticated = true),
                ),
        );
      },
    );
  }
}
