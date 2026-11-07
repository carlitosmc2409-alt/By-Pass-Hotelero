import 'package:flutter/material.dart';
import '../core/api_client.dart';
import '../core/theme.dart';
import '../models/models.dart';
import 'stealth_screen.dart';

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
    BankOption(code: '0172', name: 'Bancamiga'),
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

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _phoneCtrl.dispose();
    _cedulaCtrl.dispose();
    _paymentPhoneCtrl.dispose();
    _passwordCtrl.dispose();
    _otpCtrl.dispose();
    super.dispose();
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
      // Mantiene lista local si el backend está iniciando
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
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.75),
            radius: 1.25,
            colors: [
              Color(0xFF1D1812),
              Color(0xFF0B0E18),
              AppTheme.background,
            ],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              Positioned(
                top: 8,
                right: 12,
                child: TextButton.icon(
                  onPressed: StealthCalculatorScreen.enable,
                  icon: const Icon(
                    Icons.calculate_outlined,
                    size: 17,
                    color: AppTheme.textSecondary,
                  ),
                  label: const Text(
                    'Camuflaje',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              ),
              Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                colors: [Color(0xFF2C2314), Color(0xFF131724)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              border: Border.all(
                                color: AppTheme.gold.withValues(alpha: 0.55),
                                width: 1.4,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.gold.withValues(alpha: 0.16),
                                  blurRadius: 28,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.qr_code_scanner_rounded,
                              size: 34,
                              color: AppTheme.gold,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'StayPass QR',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Check-in privado sin recepción · Pago Móvil BDV Cero-Clics · Acceso directo en Barrera Vehicular FAAC y Habitación.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _featureBadge(
                              Icons.directions_car_filled_outlined,
                              'Barrera FAAC QR',
                              AppTheme.cyan,
                            ),
                            _featureBadge(
                              Icons.shield_moon_outlined,
                              '100% Anónimo',
                              AppTheme.gold,
                            ),
                            _featureBadge(
                              Icons.bolt_rounded,
                              'BDV Instantáneo',
                              AppTheme.accent,
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        Container(
                          decoration: BoxDecoration(
                            color: AppTheme.card.withValues(alpha: 0.94),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.09),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.45),
                                blurRadius: 30,
                                offset: const Offset(0, 14),
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.all(22),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (!_awaitingOtp)
                                Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: AppTheme.surface,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: Colors.white.withValues(alpha: 0.06),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: _modeTabButton(
                                          label: 'Iniciar sesión',
                                          selected: _isLogin,
                                          onTap: () => setState(() {
                                            _isLogin = true;
                                            _error = null;
                                          }),
                                        ),
                                      ),
                                      Expanded(
                                        child: _modeTabButton(
                                          label: 'Crear cuenta',
                                          selected: !_isLogin,
                                          onTap: () => setState(() {
                                            _isLogin = false;
                                            _error = null;
                                          }),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              const SizedBox(height: 20),
                              if (_awaitingOtp) ...[
                                const Row(
                                  children: [
                                    Icon(Icons.verified_outlined, color: AppTheme.gold),
                                    SizedBox(width: 8),
                                    Text(
                                      'Verificación WhatsApp OTP',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _otpCtrl,
                                  keyboardType: TextInputType.number,
                                  maxLength: 6,
                                  decoration: const InputDecoration(
                                    labelText: 'Código de 6 dígitos',
                                    hintText: '123456',
                                    prefixIcon: Icon(Icons.pin_outlined),
                                  ),
                                ),
                              ] else ...[
                                if (!_isLogin) ...[
                                  TextField(
                                    controller: _fullNameCtrl,
                                    decoration: const InputDecoration(
                                      labelText: 'Alias o nombre (uso privado cifrado)',
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
                                  Container(
                                    margin: const EdgeInsets.symmetric(vertical: 6),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: AppTheme.accent.withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: AppTheme.accent.withValues(alpha: 0.28),
                                      ),
                                    ),
                                    child: const Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.flash_on_rounded,
                                              size: 17,
                                              color: AppTheme.accent,
                                            ),
                                            SizedBox(width: 6),
                                            Text(
                                              'Pago Móvil Frecuente (Cero-Clics)',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 13,
                                                color: AppTheme.accent,
                                              ),
                                            ),
                                          ],
                                        ),
                                        SizedBox(height: 4),
                                        Text(
                                          'Cifrado con AES-256. Permite validar tu Pago Móvil BDV al instante sin enviar capturas ni ver al personal.',
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            color: AppTheme.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
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
                                    initialValue: _selectedBank,
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
                                      hintText: 'Vacío si es el mismo teléfono',
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
                                  onSubmitted: (_) => _submit(),
                                ),
                              ],
                              if (_info != null) ...[
                                const SizedBox(height: 14),
                                Text(
                                  _info!,
                                  style: const TextStyle(
                                    color: AppTheme.accent,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                              if (_error != null) ...[
                                const SizedBox(height: 14),
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: AppTheme.danger.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    _error!,
                                    style: const TextStyle(
                                      color: AppTheme.danger,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 20),
                              ElevatedButton.icon(
                                onPressed: _loading ? null : _submit,
                                icon: _loading
                                    ? const SizedBox(
                                        height: 18,
                                        width: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.black,
                                        ),
                                      )
                                    : Icon(
                                        _awaitingOtp
                                            ? Icons.check_circle_outline
                                            : Icons.arrow_forward_rounded,
                                      ),
                                label: Text(
                                  _awaitingOtp
                                      ? 'Verificar código'
                                      : (_isLogin
                                          ? 'Entrar en Modo Privado'
                                          : 'Crear Billetera de Acceso QR'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _modeTabButton({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: selected ? AppTheme.gold : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13.5,
            color: selected ? const Color(0xFF090A0F) : AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _featureBadge(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13.5, color: color),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
