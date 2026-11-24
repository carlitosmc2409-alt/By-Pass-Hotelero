import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/api_client.dart';
import '../core/theme.dart';
import '../models/models.dart';
import 'qr_stay_screen.dart';
import 'stealth_screen.dart';

class BookingPaymentScreen extends StatefulWidget {
  final ApiClient api;
  final HotelModel hotel;
  final RoomModel room;
  final String? extendingReservationId;
  final CreatedReservation? resumeReservation;
  final int? initialHours;
  final bool autoStartHold;

  const BookingPaymentScreen({
    super.key,
    required this.api,
    required this.hotel,
    required this.room,
    this.extendingReservationId,
    this.resumeReservation,
    this.initialHours,
    this.autoStartHold = false,
  });

  @override
  State<BookingPaymentScreen> createState() => _BookingPaymentScreenState();
}

class _BookingPaymentScreenState extends State<BookingPaymentScreen> {
  int _selectedHours = 2;
  bool _loading = false;
  bool _navigatedToQr = false;
  String? _error;
  String? _statusHint;
  CreatedReservation? _reservation;
  final _refCtrl = TextEditingController();

  Timer? _countdownTimer;
  Timer? _pollTimer;
  StreamSubscription<Map<String, dynamic>>? _sseSub;
  Duration _remainingHold = Duration.zero;

  bool get _isExtensionFlow =>
      widget.extendingReservationId != null ||
      (_reservation?.isExtension ?? false);

  bool get _isRoomServiceFlow => _reservation?.isRoomService ?? false;

  double get _estimatedUsd {
    if (_selectedHours >= 24) return widget.room.pricePerNight;
    return widget.room.pricePerHour * _selectedHours;
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialHours != null) {
      _selectedHours = widget.initialHours!;
    } else if (widget.extendingReservationId != null) {
      _selectedHours = 1;
    }

    if (widget.resumeReservation != null) {
      _reservation = widget.resumeReservation;
      _startTimersForReservation();
    } else if (widget.autoStartHold) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_createOrExtendReservation());
      });
    }

    _listenRealtimePaymentEvents();
  }

  void _listenRealtimePaymentEvents() {
    _sseSub = widget.api.connectRealtimeEvents().listen((event) {
      final resv = _reservation;
      if (resv == null || _navigatedToQr || !mounted) return;
      final type = event['type']?.toString() ?? '';
      if (type == 'PAYMENT_APPROVED') {
        final evPayId = event['paymentId']?.toString();
        final evResId = event['reservationId']?.toString();
        final evParentId = event['parentReservationId']?.toString();
        if (evPayId == resv.paymentId ||
            evResId == resv.reservationId ||
            (evParentId != null &&
                evParentId == resv.effectiveQrReservationId)) {
          unawaited(
            _onApprovedNavigate(
              resv.effectiveQrReservationId,
              autoDetected: true,
            ),
          );
        }
      }
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _pollTimer?.cancel();
    _sseSub?.cancel();
    _refCtrl.dispose();
    super.dispose();
  }

  void _startTimersForReservation() {
    _countdownTimer?.cancel();
    _pollTimer?.cancel();

    _updateRemainingTime();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) _updateRemainingTime();
    });

    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      unawaited(_checkPaymentApprovedSilently());
    });
  }

  void _updateRemainingTime() {
    final resv = _reservation;
    if (resv == null) return;
    final diff = resv.paymentExpiresAt.difference(DateTime.now());
    setState(() {
      _remainingHold = diff.isNegative ? Duration.zero : diff;
    });
  }

  Future<void> _checkPaymentApprovedSilently() async {
    final resv = _reservation;
    if (resv == null || _navigatedToQr || !mounted) return;

    try {
      final detail =
          await widget.api.fetchReservationDetail(resv.reservationId);
      final payment = detail['payment'] as Map<String, dynamic>?;
      if (payment != null && payment['status'] == 'APPROVED') {
        await _onApprovedNavigate(
          resv.effectiveQrReservationId,
          autoDetected: true,
        );
      }
    } on Object {
      // Ignora error transitorio de red en polling
    }
  }

  Future<void> _onApprovedNavigate(
    String qrReservationId, {
    bool autoDetected = false,
  }) async {
    if (_navigatedToQr || !mounted) return;
    _navigatedToQr = true;
    _countdownTimer?.cancel();
    _pollTimer?.cancel();

    if (autoDetected) {
      final text = _isRoomServiceFlow
          ? '🍾 ¡Consumo Pago Móvil confirmado! Preparando entrega por pasaplatos.'
          : _isExtensionFlow
              ? '⚡ ¡Extensión Pago Móvil verificada! Tu horario QR fue ampliado.'
              : '⚡ ¡Pago Móvil detectado en vivo! Generando tu llave QR...';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.accent,
          content: Text(
            text,
            style: TextStyle(
              color: AppTheme.onAccent,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
    }

    if (_isRoomServiceFlow || widget.extendingReservationId != null) {
      Navigator.of(context).pop(true);
      return;
    }

    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => QrStayScreen(
          api: widget.api,
          reservationId: qrReservationId,
        ),
      ),
    );
  }

  Future<void> _createOrExtendReservation() async {
    setState(() {
      _loading = true;
      _error = null;
      _statusHint = null;
    });

    try {
      final CreatedReservation created;
      if (widget.extendingReservationId != null) {
        created = await widget.api.extendReservation(
          reservationId: widget.extendingReservationId!,
          extraHours: _selectedHours,
        );
      } else {
        created = await widget.api.createReservation(
          roomId: widget.room.id,
          durationHours: _selectedHours,
        );
      }
      if (mounted) {
        setState(() {
          _reservation = created;
        });
        _startTimersForReservation();
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _submitReference() async {
    final resv = _reservation;
    if (resv == null) return;

    setState(() {
      _loading = true;
      _error = null;
      _statusHint = null;
    });

    try {
      final result = await widget.api.submitPaymentReference(
        paymentId: resv.paymentId,
        gatewayRef: _refCtrl.text.trim(),
      );

      if (!mounted) return;

      if (result['status'] == 'APPROVED') {
        final targetId = (result['reservationId'] as String?) ??
            resv.effectiveQrReservationId;
        await _onApprovedNavigate(targetId);
      } else {
        setState(() {
          _statusHint =
              'Referencia registrada. Verificando con el banco en tiempo real...';
        });
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _copyValue(String label, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 2),
        content: Text('$label copiado: $value'),
      ),
    );
  }

  String _formatCountdown(Duration d) {
    final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final resv = _reservation;
    final receptor = resv?.receptorPagoMovil ?? const {};
    final expired = resv != null && _remainingHold.inSeconds <= 0;

    final title = _isRoomServiceFlow
        ? 'Pago Room Service'
        : _isExtensionFlow
            ? 'Extender Estadía · Hab. ${widget.room.name}'
            : 'Reservar Suite ${widget.room.name}';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          AppTheme.themeToggleButton(),
          IconButton(
            tooltip: 'Modo Camuflaje',
            onPressed: StealthCalculatorScreen.enable,
            icon: const Icon(Icons.calculate_outlined, size: 20),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (resv == null) ...[
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: AppTheme.roomTierGradient(widget.room.type),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: AppTheme.roomTierAccent(widget.room.type)
                            .withValues(alpha: 0.35),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.card.withValues(alpha: 0.75),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                AppTheme.roomTierLabel(widget.room.type),
                                style: TextStyle(
                                  color:
                                      AppTheme.roomTierAccent(widget.room.type),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            Row(
                              children: [
                                Icon(
                                  Icons.directions_car_filled_outlined,
                                  size: 16,
                                  color: AppTheme.cyan,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Pase vehicular incluido',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.cyan,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '${widget.hotel.name} · Habitación ${widget.room.name}',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _isExtensionFlow
                              ? 'Amplía tu tiempo sin llamar a recepción. Tu mismo QR seguirá activo.'
                              : 'Elige la duración de tu estadía. Recibirás una llave QR para la barrera y la habitación.',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isExtensionFlow
                                ? 'Horas adicionales'
                                : '1. Elige la duración',
                            style: const TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [1, 2, 3, 4, 6, 24].map((h) {
                              final selected = _selectedHours == h;
                              final label = h == 24
                                  ? '24 Horas (Amanecida)'
                                  : (_isExtensionFlow
                                      ? '+$h hora${h > 1 ? "s" : ""}'
                                      : '$h hora${h > 1 ? "s" : ""}');
                              return ChoiceChip(
                                label: Text(
                                  label,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: selected
                                        ? AppTheme.onPrimary
                                        : AppTheme.textPrimary,
                                  ),
                                ),
                                selected: selected,
                                selectedColor: AppTheme.primary,
                                onSelected: (_) =>
                                    setState(() => _selectedHours = h),
                              );
                            }).toList(),
                          ),
                          const Divider(height: 28),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Total a pagar:',
                                style: TextStyle(color: AppTheme.textSecondary),
                              ),
                              Text(
                                '\$${_estimatedUsd.toStringAsFixed(2)} USD',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.primary,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        _error!,
                        style: TextStyle(color: AppTheme.danger),
                      ),
                    ),
                  ElevatedButton.icon(
                    onPressed: _loading ? null : _createOrExtendReservation,
                    icon: const Icon(Icons.payments_outlined),
                    label: Text(
                      _isExtensionFlow
                          ? 'Continuar al Pago Móvil'
                          : 'Ver datos de Pago Móvil',
                    ),
                  ),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      color: (expired ? AppTheme.danger : AppTheme.gold)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: (expired ? AppTheme.danger : AppTheme.gold)
                            .withValues(alpha: 0.35),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              expired
                                  ? Icons.timer_off_outlined
                                  : Icons.timer_outlined,
                              size: 18,
                              color: expired ? AppTheme.danger : AppTheme.gold,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              expired
                                  ? 'Tiempo de reserva expirado'
                                  : 'Tasa BCV bloqueada por:',
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          _formatCountdown(_remainingHold),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            fontFeatures: const [FontFeature.tabularFigures()],
                            color: expired ? AppTheme.danger : AppTheme.gold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color:
                                      AppTheme.accent.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  Icons.check_circle_outline_rounded,
                                  color: AppTheme.accent,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Datos para tu Pago Móvil',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15,
                                        color: AppTheme.textPrimary,
                                      ),
                                    ),
                                    Text(
                                      'Transfiere el monto exacto en Bs. y tu QR se activará al instante',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppTheme.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 24),
                          if ((receptor['bank'] == null || receptor['phone'] == null || receptor['idNumber'] == null))
                            Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.amber.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.amber.shade700),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.warning_amber_rounded, color: Colors.amber.shade700),
                                  const SizedBox(width: 8),
                                  const Expanded(
                                    child: Text(
                                      'Atención: El hotel no ha completado sus datos bancarios de Pago Móvil. Confirme con recepción antes de transferir.',
                                      style: TextStyle(fontSize: 12, color: Colors.white70),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          _copyableRow(
                            'Banco',
                            '${receptor['bank'] ?? 'N/D'} — ${receptor['bankName'] ?? 'No especificado'}',
                            copyText: (receptor['bank'] ?? '').toString(),
                          ),
                          _copyableRow(
                            'Teléfono',
                            receptor['phone']?.toString() ?? 'No especificado',
                            copyText: receptor['phone']?.toString() ?? '',
                          ),
                          _copyableRow(
                            'RIF / Cédula',
                            receptor['idNumber']?.toString() ?? 'No especificado',
                            copyText: receptor['idNumber']?.toString() ?? '',
                          ),
                          _copyableRow(
                            'Equivalente USD (BCV)',
                            '\$${resv.totalAmount.toStringAsFixed(2)} · Tasa Bs. ${resv.exchangeRate.toStringAsFixed(2)}',
                          ),
                          const SizedBox(height: 12),
                          InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => _copyValue(
                              'Monto exacto Bs.',
                              resv.amountVes.toStringAsFixed(2),
                            ),
                            child: Container(
                              padding: const EdgeInsets.all(15),
                              decoration: BoxDecoration(
                                color: AppTheme.accent.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: AppTheme.accent.withValues(alpha: 0.35),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'MONTO EXACTO A TRANSFERIR',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 11,
                                            letterSpacing: 0.5,
                                            color: AppTheme.accent,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Toca para copiar con decimales',
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            color: AppTheme.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      Text(
                                        'Bs. ${resv.amountVes.toStringAsFixed(2)}',
                                        style: TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w800,
                                          fontFeatures: const [
                                            FontFeature.tabularFigures(),
                                          ],
                                          color: AppTheme.textPrimary,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Icon(
                                        Icons.copy_rounded,
                                        size: 17,
                                        color: AppTheme.primary,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: () {
                                final summary =
                                    'Banco: ${receptor['bank'] ?? '0102'}\n'
                                    'Teléfono: ${receptor['phone'] ?? ''}\n'
                                    'RIF/CI: ${receptor['idNumber'] ?? ''}\n'
                                    'Monto: ${resv.amountVes.toStringAsFixed(2)}';
                                _copyValue('Datos Pago Móvil', summary);
                              },
                              icon:
                                  const Icon(Icons.copy_all_rounded, size: 16),
                              label: const Text('Copiar todos los datos'),
                            ),
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _refCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText:
                                  'Últimos dígitos de referencia (si pagas desde otro teléfono)',
                              hintText: 'Ej: 987654',
                              prefixIcon: Icon(Icons.receipt_long_outlined),
                            ),
                          ),
                          if (_statusHint != null) ...[
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppTheme.accent,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _statusHint!,
                                    style: TextStyle(
                                      color: AppTheme.accent,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          if (_error != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              _error!,
                              style: TextStyle(color: AppTheme.danger),
                            ),
                          ],
                          const SizedBox(height: 18),
                          ElevatedButton.icon(
                            onPressed:
                                (_loading || expired) ? null : _submitReference,
                            icon: _loading
                                ? SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppTheme.onPrimary,
                                    ),
                                  )
                                : const Icon(Icons.verified_rounded),
                            label: Text(
                              _isRoomServiceFlow
                                  ? 'Confirmar Pago de Pedido'
                                  : 'Confirmar Pago y Activar Llave QR',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _copyableRow(String label, String value, {String? copyText}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: AppTheme.textPrimary,
                ),
              ),
              if (copyText != null) ...[
                const SizedBox(width: 6),
                InkWell(
                  onTap: () => _copyValue(label, copyText),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.copy_rounded,
                      size: 15,
                      color: AppTheme.primary,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
