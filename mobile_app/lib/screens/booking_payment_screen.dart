import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/api_client.dart';
import '../core/theme.dart';
import '../models/models.dart';
import 'qr_stay_screen.dart';

class BookingPaymentScreen extends StatefulWidget {
  final ApiClient api;
  final HotelModel hotel;
  final RoomModel room;
  final String? extendingReservationId;
  final CreatedReservation? resumeReservation;

  const BookingPaymentScreen({
    super.key,
    required this.api,
    required this.hotel,
    required this.room,
    this.extendingReservationId,
    this.resumeReservation,
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
  Duration _remainingHold = Duration.zero;

  bool get _isExtensionFlow =>
      widget.extendingReservationId != null ||
      (_reservation?.isExtension ?? false);

  double get _estimatedUsd {
    if (_selectedHours >= 24) return widget.room.pricePerNight;
    return widget.room.pricePerHour * _selectedHours;
  }

  @override
  void initState() {
    super.initState();
    if (widget.extendingReservationId != null) {
      _selectedHours = 1;
    }
    if (widget.resumeReservation != null) {
      _reservation = widget.resumeReservation;
      _startTimersForReservation();
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _pollTimer?.cancel();
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

    // Polling cada 3 segundos para detectar conciliación "Cero Clics" o aprobación tras push BDV
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _checkPaymentApprovedSilently();
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
      final detail = await widget.api.fetchReservationDetail(resv.reservationId);
      final payment = detail['payment'] as Map<String, dynamic>?;
      if (payment != null && payment['status'] == 'APPROVED') {
        await _onApprovedNavigate(
          resv.effectiveQrReservationId,
          autoDetected: true,
        );
      }
    } catch (_) {
      // Silencioso en caso de parpadeo puntual de red
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.accent,
          content: Text(
            _isExtensionFlow
                ? '¡Extensión Pago Móvil BDV verificada! Tu horario QR fue ampliado.'
                : '¡Pago Móvil BDV detectado automáticamente! Abriendo tu llave QR...',
            style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
          ),
        ),
      );
    }

    if (widget.extendingReservationId != null) {
      // Si venimos desde QrStayScreen, regresamos con `true` para refrescar el QR extendido
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
    } catch (e) {
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
        final targetId =
            (result['reservationId'] as String?) ?? resv.effectiveQrReservationId;
        await _onApprovedNavigate(targetId);
      } else {
        setState(() {
          _statusHint =
              'Referencia registrada. Esperando confirmación automática de notificación BDV (se abrirá sola)...';
        });
      }
    } catch (e) {
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

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isExtensionFlow
              ? 'Extender Estadía · Hab. ${widget.room.name}'
              : 'Habitación ${widget.room.name}',
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (resv == null) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isExtensionFlow
                                ? '¿Cuántas horas adicionales deseas sumar?'
                                : 'Selecciona la duración de tu estadía',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [1, 2, 3, 4, 6, 24].map((h) {
                              final label = h == 24
                                  ? 'Amanecida (+24h)'
                                  : (_isExtensionFlow ? '+$h h' : '$h horas');
                              return ChoiceChip(
                                label: Text(label),
                                selected: _selectedHours == h,
                                onSelected: (_) =>
                                    setState(() => _selectedHours = h),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Total estimado:',
                                style: TextStyle(color: AppTheme.textSecondary),
                              ),
                              Text(
                                '\$${_estimatedUsd.toStringAsFixed(2)} USD',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.accent,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: AppTheme.danger),
                      ),
                    ),
                  ElevatedButton.icon(
                    onPressed: _loading ? null : _createOrExtendReservation,
                    icon: const Icon(Icons.bolt_rounded),
                    label: Text(
                      _isExtensionFlow
                          ? 'Continuar al Pago Móvil de extensión'
                          : 'Continuar al Pago Móvil automático',
                    ),
                  ),
                ] else ...[
                  // Barra de reloj regresivo de 10 minutos
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: (expired ? AppTheme.danger : AppTheme.primary)
                          .withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: (expired ? AppTheme.danger : AppTheme.primary)
                            .withValues(alpha: 0.4),
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
                              color:
                                  expired ? AppTheme.danger : AppTheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              expired
                                  ? 'Ventana de tasa bloqueada expirada'
                                  : 'Tasa bloqueada garantizada por:',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          _formatCountdown(_remainingHold),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: expired ? AppTheme.danger : AppTheme.accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.flash_on_rounded, color: AppTheme.accent),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Conciliación Instantánea Cero-Clics (BDV)',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    color: AppTheme.accent,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Transfiere exactamente el monto en Bolívares desde tu teléfono registrado. '
                            'Apenas entre el push al Banco de Venezuela, esta pantalla se abrirá sola (o reporta la referencia abajo).',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                          const Divider(height: 24),
                          _copyableRow(
                            'Banco receptor',
                            '${receptor['bank'] ?? '0102'} — ${receptor['bankName'] ?? 'Banco de Venezuela'}',
                            copyText: (receptor['bank'] ?? '0102').toString(),
                          ),
                          _copyableRow(
                            'Teléfono Pago Móvil',
                            receptor['phone']?.toString() ?? '+584121234567',
                            copyText:
                                receptor['phone']?.toString() ?? '+584121234567',
                          ),
                          _copyableRow(
                            'RIF / Cédula',
                            receptor['idNumber']?.toString() ?? 'J-50123456-7',
                            copyText:
                                receptor['idNumber']?.toString() ?? 'J-50123456-7',
                          ),
                          _copyableRow(
                            'Tasa BCV aplicada',
                            'Bs. ${resv.exchangeRate.toStringAsFixed(2)} / USD',
                          ),
                          const SizedBox(height: 10),
                          InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => _copyValue(
                              'Monto en Bs.',
                              resv.amountVes.toStringAsFixed(2),
                            ),
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: AppTheme.accent.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: AppTheme.accent.withValues(alpha: 0.35),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Expanded(
                                    child: Text(
                                      'Monto EXACTO a transferir (toca para copiar):',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      Text(
                                        'Bs. ${resv.amountVes.toStringAsFixed(2)}',
                                        style: const TextStyle(
                                          fontSize: 19,
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.accent,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      const Icon(
                                        Icons.copy_rounded,
                                        size: 16,
                                        color: AppTheme.accent,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
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
                              icon: const Icon(Icons.copy_all_rounded, size: 16),
                              label: const Text('Copiar todos los datos'),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _refCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText:
                                  'Referencia bancaria (opcional si entra Cero-Clics)',
                              hintText: 'Ej: 00987654',
                              prefixIcon: Icon(Icons.receipt_long_outlined),
                            ),
                          ),
                          if (_statusHint != null) ...[
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _statusHint!,
                                    style: const TextStyle(
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
                              style: const TextStyle(color: AppTheme.danger),
                            ),
                          ],
                          const SizedBox(height: 18),
                          ElevatedButton(
                            onPressed:
                                (_loading || expired) ? null : _submitReference,
                            child: _loading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Reportar referencia y obtener QR'),
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
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppTheme.textSecondary)),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
              if (copyText != null) ...[
                const SizedBox(width: 6),
                InkWell(
                  onTap: () => _copyValue(label, copyText),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
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
