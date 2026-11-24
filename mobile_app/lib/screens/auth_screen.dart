import 'dart:async';
import 'package:flutter/foundation.dart';
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
  String _portalRole = 'GUEST'; // 'GUEST' | 'RECEPTIONIST' | 'CLEANING'
  bool _isLogin = true;
  bool _awaitingOtp = false;
  bool _loading = false;
  bool _obscurePassword = true;
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

  // Controladores Huésped
  final _fullNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController(
    text: kDebugMode ? '+584129876543' : '',
  );
  final _cedulaCtrl = TextEditingController(
    text: kDebugMode ? 'V-20123456' : '',
  );
  final _paymentPhoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController(
    text: kDebugMode ? 'Guest@12345' : '',
  );
  final _otpCtrl = TextEditingController();

  // Controladores Personal (Recepción y Limpieza)
  final _hotelCodeCtrl = TextEditingController(
    text: kDebugMode ? 'motel-la-brisa-caracas' : '',
  );
  final _receptionUserCtrl = TextEditingController(
    text: kDebugMode ? 'juan.recepcion' : '',
  );
  final _receptionPassCtrl = TextEditingController(
    text: kDebugMode ? 'Recepcion2026*' : '',
  );
  final _cleaningAliasCtrl = TextEditingController(
    text: kDebugMode ? 'camarera1' : '',
  );
  final _cleaningPinCtrl = TextEditingController(
    text: kDebugMode ? '1234' : '',
  );

  @override
  void initState() {
    super.initState();
    unawaited(_loadBanks());
  }

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _phoneCtrl.dispose();
    _cedulaCtrl.dispose();
    _paymentPhoneCtrl.dispose();
    _passwordCtrl.dispose();
    _otpCtrl.dispose();
    _hotelCodeCtrl.dispose();
    _receptionUserCtrl.dispose();
    _receptionPassCtrl.dispose();
    _cleaningAliasCtrl.dispose();
    _cleaningPinCtrl.dispose();
    super.dispose();
  }

  Future<void> _openServerUrlDialog() async {
    final ctrl = TextEditingController(text: ApiClient.baseUrl);
    final saved = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
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
      await ApiClient.setCustomBaseUrl(saved);
      await _loadBanks();
      if (mounted) {
        setState(() {
          _info = 'Conectado a ${ApiClient.baseUrl}';
        });
      }
    }
  }

  Future<void> _loadBanks() async {
    try {
      final list = await widget.api.fetchBanks();
      if (mounted && list.isNotEmpty) {
        setState(() {
          _banks = list;
        });
      }
    } on Object {
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
      if (_portalRole == 'RECEPTIONIST') {
        final hotelCode = _hotelCodeCtrl.text.trim();
        final username = _receptionUserCtrl.text.trim();
        final password = _receptionPassCtrl.text;

        if (hotelCode.isEmpty || username.isEmpty || password.isEmpty) {
          throw const ApiException(
            400,
            'Ingrese el código del hotel, usuario y contraseña de recepcionista.',
          );
        }

        await widget.api.loginReceptionist(
          hotelCode: hotelCode,
          username: username,
          password: password,
        );
        widget.onAuthenticated();
        return;
      }

      if (_portalRole == 'CLEANING') {
        final hotelCode = _hotelCodeCtrl.text.trim();
        final alias = _cleaningAliasCtrl.text.trim();
        final pin = _cleaningPinCtrl.text.trim();

        if (hotelCode.isEmpty || alias.isEmpty || pin.isEmpty) {
          throw const ApiException(
            400,
            'Ingrese el código del hotel, alias y PIN de camarería.',
          );
        }

        await widget.api.loginCleaningStaff(
          hotelCode: hotelCode,
          alias: alias,
          pin: pin,
        );
        widget.onAuthenticated();
        return;
      }

      // Modo HUÉSPED
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
    } on Object catch (e) {
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
    final isDark = AppTheme.isDark;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            // Barra superior limpia con Servidor, Tema Claro/Oscuro y Camuflaje
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton.icon(
                    onPressed: _openServerUrlDialog,
                    icon: Icon(
                      Icons.dns_outlined,
                      size: 16,
                      color: AppTheme.textSecondary,
                    ),
                    label: Text(
                      'Servidor',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      AppTheme.themeToggleButton(),
                      TextButton.icon(
                        onPressed: StealthCalculatorScreen.enable,
                        icon: Icon(
                          Icons.calculate_outlined,
                          size: 17,
                          color: AppTheme.textSecondary,
                        ),
                        label: Text(
                          'Camuflaje',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppTheme.surface,
                              border: Border.all(
                                color: AppTheme.warmBeige.withValues(alpha: 0.45),
                                width: 1.5,
                              ),
                            ),
                            child: Icon(
                              Icons.qr_code_scanner_rounded,
                              size: 30,
                              color: AppTheme.warmBeige,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'StayPass QR',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Reserva rápida y discreta · Pago Móvil automático · Llave QR para barrera y habitación.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 13.5,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _featureBadge(
                              Icons.directions_car_filled_outlined,
                              'Barrera QR',
                              AppTheme.cyan,
                            ),
                            _featureBadge(
                              Icons.shield_moon_outlined,
                              '100% Privado',
                              AppTheme.gold,
                            ),
                            _featureBadge(
                              Icons.check_circle_outline_rounded,
                              'Pago Móvil Rápido',
                              AppTheme.accent,
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        // Selector de Perfil / Rol de Acceso
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: AppTheme.surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppTheme.border),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: _roleSegmentButton(
                                  icon: Icons.person_outline,
                                  label: 'Huésped',
                                  selected: _portalRole == 'GUEST',
                                  onTap: () => setState(() {
                                    _portalRole = 'GUEST';
                                    _error = null;
                                  }),
                                ),
                              ),
                              Expanded(
                                child: _roleSegmentButton(
                                  icon: Icons.support_agent_rounded,
                                  label: 'Recepción',
                                  selected: _portalRole == 'RECEPTIONIST',
                                  onTap: () => setState(() {
                                    _portalRole = 'RECEPTIONIST';
                                    _error = null;
                                  }),
                                ),
                              ),
                              Expanded(
                                child: _roleSegmentButton(
                                  icon: Icons.cleaning_services_rounded,
                                  label: 'Limpieza',
                                  selected: _portalRole == 'CLEANING',
                                  onTap: () => setState(() {
                                    _portalRole = 'CLEANING';
                                    _error = null;
                                  }),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          decoration: BoxDecoration(
                            color: AppTheme.card,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: AppTheme.border),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(
                                  alpha: isDark ? 0.25 : 0.05,
                                ),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.all(22),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (_portalRole == 'RECEPTIONIST') ...[
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.support_agent_rounded,
                                      color: Colors.tealAccent,
                                      size: 22,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Acceso Recepción & Asistencia',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.textPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Para resolver contingencias, destrabar cerraduras, accionar barrera FAAC y aprobar pagos manuales.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                TextField(
                                  controller: _hotelCodeCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'Código / Slug del Hotel',
                                    hintText: 'ej: hotel-caracas',
                                    prefixIcon: Icon(Icons.hotel_outlined),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _receptionUserCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'Usuario de Recepción',
                                    hintText: 'ej: juan.recepcion',
                                    prefixIcon: Icon(Icons.badge_outlined),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _receptionPassCtrl,
                                  obscureText: _obscurePassword,
                                  decoration: InputDecoration(
                                    labelText: 'Contraseña',
                                    prefixIcon: const Icon(Icons.lock_outline),
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _obscurePassword
                                            ? Icons.visibility_off_outlined
                                            : Icons.visibility_outlined,
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          _obscurePassword = !_obscurePassword;
                                        });
                                      },
                                    ),
                                  ),
                                  onSubmitted: (_) => _submit(),
                                ),
                              ] else if (_portalRole == 'CLEANING') ...[
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.cleaning_services_rounded,
                                      color: Colors.amberAccent,
                                      size: 22,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Acceso Camarería (Cero Finanzas)',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.textPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Consulte habitaciones para aseo, alertas de salida (≤15m) y entregas en pasaplatos.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                TextField(
                                  controller: _hotelCodeCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'Código / Slug del Hotel',
                                    hintText: 'ej: hotel-caracas',
                                    prefixIcon: Icon(Icons.hotel_outlined),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _cleaningAliasCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'Alias Operativo',
                                    hintText: 'ej: camarera1',
                                    prefixIcon: Icon(Icons.badge_outlined),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _cleaningPinCtrl,
                                  keyboardType: TextInputType.number,
                                  obscureText: _obscurePassword,
                                  decoration: InputDecoration(
                                    labelText: 'PIN Numérico (4 dígitos)',
                                    hintText: '1234',
                                    prefixIcon: const Icon(Icons.pin_outlined),
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _obscurePassword
                                            ? Icons.visibility_off_outlined
                                            : Icons.visibility_outlined,
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          _obscurePassword = !_obscurePassword;
                                        });
                                      },
                                    ),
                                  ),
                                  onSubmitted: (_) => _submit(),
                                ),
                              ] else ...[
                                if (!_awaitingOtp)
                                Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: AppTheme.surface,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: AppTheme.border),
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
                              const SizedBox(height: 18),
                              if (_awaitingOtp) ...[
                                Row(
                                  children: [
                                    Icon(
                                      Icons.verified_outlined,
                                      color: AppTheme.gold,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Verificación de Código',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.textPrimary,
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
                                      labelText: 'Alias o nombre (uso privado)',
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
                                    prefixIcon:
                                        Icon(Icons.phone_android_outlined),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                if (!_isLogin) ...[
                                  Container(
                                    margin:
                                        const EdgeInsets.symmetric(vertical: 4),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: AppTheme.accent
                                          .withValues(alpha: 0.10),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: AppTheme.accent
                                            .withValues(alpha: 0.25),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.flash_on_rounded,
                                              size: 16,
                                              color: AppTheme.accent,
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              'Pago Móvil Frecuente (Automático)',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 12.5,
                                                color: AppTheme.accent,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Tus datos viajan cifrados y permiten confirmar tu Pago Móvil al instante sin enviar capturas.',
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
                                      prefixIcon:
                                          Icon(Icons.account_balance_outlined),
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
                                      labelText:
                                          'Teléfono afiliado al Pago Móvil',
                                      hintText: 'Vacío si es el mismo teléfono',
                                      prefixIcon: Icon(Icons.payments_outlined),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                ],
                                TextField(
                                  controller: _passwordCtrl,
                                  obscureText: _obscurePassword,
                                  decoration: InputDecoration(
                                    labelText: 'Contraseña',
                                    prefixIcon: const Icon(Icons.lock_outline),
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _obscurePassword
                                            ? Icons.visibility_off_outlined
                                            : Icons.visibility_outlined,
                                      ),
                                      tooltip: _obscurePassword
                                          ? 'Mostrar contraseña'
                                          : 'Ocultar contraseña',
                                      onPressed: () {
                                        setState(() {
                                          _obscurePassword = !_obscurePassword;
                                        });
                                      },
                                    ),
                                  ),
                                  onSubmitted: (_) => _submit(),
                                ),
                              ],
                              ],
                              if (_info != null) ...[
                                const SizedBox(height: 14),
                                Text(
                                  _info!,
                                  style: TextStyle(
                                    color: AppTheme.accent,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                              if (_error != null) ...[
                                const SizedBox(height: 14),
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color:
                                        AppTheme.danger.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    _error!,
                                    style: TextStyle(
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
                                    ? SizedBox(
                                        height: 18,
                                        width: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: AppTheme.onPrimary,
                                        ),
                                      )
                                    : Icon(
                                        _awaitingOtp
                                            ? Icons.check_circle_outline
                                            : Icons.arrow_forward_rounded,
                                      ),
                                label: Text(
                                  _portalRole == 'RECEPTIONIST'
                                      ? 'Entrar a Recepción'
                                      : (_portalRole == 'CLEANING'
                                          ? 'Entrar a Limpieza'
                                          : (_awaitingOtp
                                              ? 'Verificar código'
                                              : (_isLogin
                                                  ? 'Entrar a StayPass'
                                                  : 'Crear Cuenta Privada'))),
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
            ),
          ],
        ),
      ),
    );
  }

  Widget _roleSegmentButton({
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: selected ? AppTheme.onPrimary : AppTheme.textSecondary,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
                color: selected ? AppTheme.onPrimary : AppTheme.textSecondary,
              ),
            ),
          ],
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
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13.5,
            color: selected ? AppTheme.onPrimary : AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _featureBadge(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.25)),
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
