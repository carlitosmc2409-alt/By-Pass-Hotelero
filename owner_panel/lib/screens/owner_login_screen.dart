import 'package:flutter/material.dart';
import '../core/owner_api.dart';
import '../core/owner_theme.dart';

class OwnerLoginScreen extends StatefulWidget {
  final OwnerApiClient api;
  final VoidCallback onAuthenticated;

  const OwnerLoginScreen({
    super.key,
    required this.api,
    required this.onAuthenticated,
  });

  @override
  State<OwnerLoginScreen> createState() => _OwnerLoginScreenState();
}

class _OwnerLoginScreenState extends State<OwnerLoginScreen> {
  bool _isCleaningMode = false;
  final _emailCtrl = TextEditingController(text: 'propietario@test.com');
  final _passwordCtrl = TextEditingController(text: 'Admin@12345');

  final _hotelCodeCtrl = TextEditingController();
  final _aliasCtrl = TextEditingController(text: 'camarera1');
  final _pinCtrl = TextEditingController(text: '1234');

  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _hotelCodeCtrl.dispose();
    _aliasCtrl.dispose();
    _pinCtrl.dispose();
    super.dispose();
  }

  Future<void> _openServerUrlDialog() async {
    final ctrl = TextEditingController(text: OwnerApiClient.baseUrl);
    final saved = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: OwnerTheme.card,
        title: const Text('Servidor API StayPass'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            labelText: 'URL API (ej: http://192.168.0.122:3000/api/v1)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (saved != null && saved.isNotEmpty) {
      await OwnerApiClient.setCustomBaseUrl(saved);
      if (mounted) setState(() {});
    }
  }

  Future<void> _login() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      if (_isCleaningMode) {
        await widget.api.loginCleaning(
          hotelCode: _hotelCodeCtrl.text.trim(),
          alias: _aliasCtrl.text.trim(),
          pin: _pinCtrl.text.trim(),
        );
      } else {
        await widget.api.loginOwner(
          email: _emailCtrl.text.trim(),
          password: _passwordCtrl.text,
        );
      }
      widget.onAuthenticated();
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.7),
            radius: 1.25,
            colors: [
              Color(0xFF1A1711),
              Color(0xFF0C101C),
              OwnerTheme.background,
            ],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: _openServerUrlDialog,
                          icon: const Icon(
                            Icons.dns_outlined,
                            size: 16,
                            color: OwnerTheme.textSecondary,
                          ),
                          label: const Text(
                            'Servidor',
                            style: TextStyle(
                              fontSize: 12,
                              color: OwnerTheme.textSecondary,
                            ),
                          ),
                        ),
                      ),
                      Center(
                        child: Container(
                          width: 66,
                          height: 66,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: OwnerTheme.surface,
                            border: Border.all(
                              color: OwnerTheme.gold.withValues(alpha: 0.55),
                              width: 1.4,
                            ),
                          ),
                          child: Icon(
                            _isCleaningMode
                                ? Icons.cleaning_services_rounded
                                : Icons.apartment_rounded,
                            size: 32,
                            color: OwnerTheme.gold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'StayPass · Panel del Propietario',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _isCleaningMode
                            ? 'Modo Operativo de Camareras · Cero acceso a finanzas ni datos personales.'
                            : 'Control ejecutivo en vivo: BDV Cero-Clics, Barreras FAAC, Pasaplatos y Ocupación.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 13,
                          color: OwnerTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: OwnerTheme.surface,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: _roleChip(
                                label: 'Gerencia / Dueño',
                                selected: !_isCleaningMode,
                                onTap: () => setState(() {
                                  _isCleaningMode = false;
                                  _error = null;
                                }),
                              ),
                            ),
                            Expanded(
                              child: _roleChip(
                                label: 'Personal Limpieza',
                                selected: _isCleaningMode,
                                onTap: () => setState(() {
                                  _isCleaningMode = true;
                                  _error = null;
                                }),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (!_isCleaningMode) ...[
                        TextField(
                          controller: _emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'Correo electrónico',
                            prefixIcon: Icon(Icons.email_outlined),
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _passwordCtrl,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Contraseña',
                            prefixIcon: Icon(Icons.lock_outline),
                          ),
                          onSubmitted: (_) => _login(),
                        ),
                      ] else ...[
                        TextField(
                          controller: _aliasCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Alias operativo (ej: camarera1)',
                            prefixIcon: Icon(Icons.badge_outlined),
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _pinCtrl,
                          obscureText: true,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'PIN de acceso (ej: 1234)',
                            prefixIcon: Icon(Icons.pin_outlined),
                          ),
                          onSubmitted: (_) => _login(),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _hotelCodeCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Código de hotel (opcional)',
                            prefixIcon: Icon(Icons.domain_outlined),
                          ),
                        ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 14),
                        Text(
                          _error!,
                          style: const TextStyle(color: OwnerTheme.occupied),
                        ),
                      ],
                      const SizedBox(height: 22),
                      ElevatedButton(
                        onPressed: _loading ? null : _login,
                        child: _loading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.black,
                                ),
                              )
                            : Text(
                                _isCleaningMode
                                    ? 'Abrir Tablero de Limpieza'
                                    : 'Acceder al Panel',
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _roleChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? OwnerTheme.gold : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: selected ? const Color(0xFF08090E) : OwnerTheme.textSecondary,
          ),
        ),
      ),
    );
  }
}
