import 'package:flutter/material.dart';
import '../core/api_client.dart';
import '../core/theme.dart';
import '../models/models.dart';

class AuthScreen extends StatefulWidget {
  final ApiClient api;
  final VoidCallback onAuthenticated;

  const AuthScreen({
    super.key,
    required this.api,
    required this.onAuthenticated,
  });

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _isLogin = true;
  bool _awaitingOtp = false;
  bool _loading = false;
  String? _error;
  String? _info;

  List<BankOption> _banks = const [
    BankOption(code: '0102', name: 'Banco de Venezuela'),
    BankOption(code: '0134', name: 'Banesco'),
    BankOption(code: '0105', name: 'Mercantil'),
    BankOption(code: '0108', name: 'Provincial'),
    BankOption(code: '0191', name: 'Banco Nacional de Crédito (BNC)'),
  ];
  String _selectedBank = '0102';

  final _fullNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController(text: '+584129876543');
  final _cedulaCtrl = TextEditingController(text: 'V-20123456');
  final _paymentPhoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController(text: 'Guest@12345');
  final _otpCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadBanks();
  }

  Future<void> _loadBanks() async {
    try {
      final list = await widget.api.fetchBanks();
      if (mounted && list.isNotEmpty) {
        setState(() {
          _banks = list;
        });
      }
    } catch (_) {
      // Mantiene lista por defecto si el servidor aún no está accesible
    }
  }

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
      _info = null;
    });

    try {
      if (_awaitingOtp) {
        await widget.api.verifyGuestOtp(
          phone: _phoneCtrl.text.trim(),
          code: _otpCtrl.text.trim(),
        );
        await widget.api.loginGuest(
          phone: _phoneCtrl.text.trim(),
          password: _passwordCtrl.text,
        );
        widget.onAuthenticated();
        return;
      }

      if (_isLogin) {
        await widget.api.loginGuest(
          phone: _phoneCtrl.text.trim(),
          password: _passwordCtrl.text,
        );
        widget.onAuthenticated();
      } else {
        final phone = _phoneCtrl.text.trim();
        final paymentPhone = _paymentPhoneCtrl.text.trim().isEmpty
            ? phone
            : _paymentPhoneCtrl.text.trim();

        final res = await widget.api.registerGuest(
          fullName: _fullNameCtrl.text.trim(),
          phone: phone,
          cedula: _cedulaCtrl.text.trim(),
          paymentBank: _selectedBank,
          paymentPhone: paymentPhone,
          paymentCedula: _cedulaCtrl.text.trim(),
          password: _passwordCtrl.text,
        );
        setState(() {
          _awaitingOtp = true;
          _info = res['message']?.toString() ??
              'Revisa tu WhatsApp para ingresar el código OTP.';
        });
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.qr_code_scanner_rounded,
                    size: 52,
                    color: AppTheme.primary,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'StayPass QR',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Reserva, paga por Pago Móvil y entra directo con tu QR sin pasar por recepción.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 13.5),
                  ),
                  const SizedBox(height: 28),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (!_awaitingOtp)
                            Row(
                              children: [
                                Expanded(
                                  child: ChoiceChip(
                                    label: const Text('Iniciar sesión'),
                                    selected: _isLogin,
                                    onSelected: (_) => setState(() {
                                      _isLogin = true;
                                      _error = null;
                                    }),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: ChoiceChip(
                                    label: const Text('Crear cuenta'),
                                    selected: !_isLogin,
                                    onSelected: (_) => setState(() {
                                      _isLogin = false;
                                      _error = null;
                                    }),
                                  ),
                                ),
                              ],
                            ),
                          const SizedBox(height: 18),
                          if (_awaitingOtp) ...[
                            const Text(
                              'Verificación WhatsApp OTP',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _otpCtrl,
                              keyboardType: TextInputType.number,
                              maxLength: 6,
                              decoration: const InputDecoration(
                                labelText: 'Código de 6 dígitos',
                                hintText: '123456',
                              ),
                            ),
                          ] else ...[
                            if (!_isLogin) ...[
                              TextField(
                                controller: _fullNameCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Nombre completo',
                                  prefixIcon: Icon(Icons.person_outline),
                                ),
                              ),
                              const SizedBox(height: 12),
                            ],
                            TextField(
                              controller: _phoneCtrl,
                              keyboardType: TextInputType.phone,
                              decoration: const InputDecoration(
                                labelText: 'Teléfono (+58)',
                                hintText: '+584129876543',
                                prefixIcon: Icon(Icons.phone_android_outlined),
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (!_isLogin) ...[
                              const Divider(height: 24),
                              const Text(
                                'Datos de Pago Móvil Frecuente',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: AppTheme.accent,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Se usan para verificar tus pagos al instante sin esperas.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _cedulaCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Cédula titular Pago Móvil',
                                  hintText: 'V-20123456',
                                  prefixIcon: Icon(Icons.badge_outlined),
                                ),
                              ),
                              const SizedBox(height: 12),
                              DropdownButtonFormField<String>(
                                value: _selectedBank,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'Banco emisor',
                                  prefixIcon: Icon(Icons.account_balance_outlined),
                                ),
                                items: _banks
                                    .map(
                                      (b) => DropdownMenuItem(
                                        value: b.code,
                                        child: Text(
                                          '${b.code} — ${b.name}',
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(() => _selectedBank = val);
                                  }
                                },
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _paymentPhoneCtrl,
                                keyboardType: TextInputType.phone,
                                decoration: const InputDecoration(
                                  labelText: 'Teléfono afiliado al Pago Móvil',
                                  hintText: 'Dejar vacío si es el mismo número',
                                  prefixIcon: Icon(Icons.payments_outlined),
                                ),
                              ),
                              const SizedBox(height: 12),
                            ],
                            TextField(
                              controller: _passwordCtrl,
                              obscureText: true,
                              decoration: const InputDecoration(
                                labelText: 'Contraseña',
                                prefixIcon: Icon(Icons.lock_outline),
                              ),
                            ),
                          ],
                          if (_info != null) ...[
                            const SizedBox(height: 14),
                            Text(
                              _info!,
                              style: const TextStyle(color: AppTheme.accent),
                            ),
                          ],
                          if (_error != null) ...[
                            const SizedBox(height: 14),
                            Text(
                              _error!,
                              style: const TextStyle(color: AppTheme.danger),
                            ),
                          ],
                          const SizedBox(height: 20),
                          ElevatedButton(
                            onPressed: _loading ? null : _submit,
                            child: _loading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : Text(
                                    _awaitingOtp
                                        ? 'Verificar código'
                                        : (_isLogin ? 'Entrar' : 'Registrarme'),
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
