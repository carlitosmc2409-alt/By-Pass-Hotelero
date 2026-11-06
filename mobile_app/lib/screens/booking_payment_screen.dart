import 'package:flutter/material.dart';
import '../core/api_client.dart';
import '../core/theme.dart';
import '../models/models.dart';
import 'qr_stay_screen.dart';

class BookingPaymentScreen extends StatefulWidget {
  final ApiClient api;
  final HotelModel hotel;
  final RoomModel room;

  const BookingPaymentScreen({
    super.key,
    required this.api,
    required this.hotel,
    required this.room,
  });

  @override
  State<BookingPaymentScreen> createState() => _BookingPaymentScreenState();
}

class _BookingPaymentScreenState extends State<BookingPaymentScreen> {
  int _selectedHours = 2;
  bool _loading = false;
  String? _error;
  CreatedReservation? _reservation;
  final _refCtrl = TextEditingController();

  double get _estimatedUsd {
    if (_selectedHours >= 24) return widget.room.pricePerNight;
    return widget.room.pricePerHour * _selectedHours;
  }

  Future<void> _createReservation() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final created = await widget.api.createReservation(
        roomId: widget.room.id,
        durationHours: _selectedHours,
      );
      if (mounted) {
        setState(() {
          _reservation = created;
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

  Future<void> _submitReference() async {
    final resv = _reservation;
    if (resv == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await widget.api.submitPaymentReference(
        paymentId: resv.paymentId,
        gatewayRef: _refCtrl.text.trim(),
      );

      if (!mounted) return;

      if (result['status'] == 'APPROVED') {
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => QrStayScreen(
              api: widget.api,
              reservationId: resv.reservationId,
            ),
          ),
        );
      } else {
        setState(() {
          _error = result['message']?.toString() ??
              'La referencia aún no coincide con el monto o emisor esperado.';
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

  @override
  Widget build(BuildContext context) {
    final resv = _reservation;
    final receptor = resv?.receptorPagoMovil ?? const {};

    return Scaffold(
      appBar: AppBar(
        title: Text('Habitación ${widget.room.name}'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
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
                      const Text(
                        'Selecciona la duración de tu estadía',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [1, 2, 3, 4, 6, 24].map((h) {
                          final label = h == 24 ? 'Noche completa (24h)' : '$h horas';
                          return ChoiceChip(
                            label: Text(label),
                            selected: _selectedHours == h,
                            onSelected: (_) => setState(() => _selectedHours = h),
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
                  child: Text(_error!, style: const TextStyle(color: AppTheme.danger)),
                ),
              ElevatedButton.icon(
                onPressed: _loading ? null : _createReservation,
                icon: const Icon(Icons.bolt_rounded),
                label: const Text('Continuar al Pago Móvil automático'),
              ),
            ] else ...[
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
                          Text(
                            'Verificación Instantánea (Estilo Cashea)',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: AppTheme.accent,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Transfiere exactamente el monto en Bolívares indicado abajo desde tu cuenta afiliada. El sistema validará la notificación del Banco de Venezuela al instante.',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const Divider(height: 26),
                      _infoRow('Banco receptor',
                          '${receptor['bank'] ?? '0102'} — ${receptor['bankName'] ?? 'Banco de Venezuela'}'),
                      _infoRow('Teléfono Pago Móvil', receptor['phone']?.toString() ?? '+584121234567'),
                      _infoRow('RIF / Cédula', receptor['idNumber']?.toString() ?? 'J-50123456-7'),
                      _infoRow('Tasa BCV aplicada', 'Bs. ${resv.exchangeRate.toStringAsFixed(2)} / USD'),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppTheme.accent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Monto EXACTO a transferir:',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            Text(
                              'Bs. ${resv.amountVes.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.accent,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      TextField(
                        controller: _refCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Número de referencia (últimos 6-8 dígitos)',
                          hintText: 'Ej: 00987654',
                          prefixIcon: Icon(Icons.receipt_long_outlined),
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(_error!, style: const TextStyle(color: AppTheme.danger)),
                      ],
                      const SizedBox(height: 18),
                      ElevatedButton(
                        onPressed: _loading ? null : _submitReference,
                        child: _loading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
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
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppTheme.textSecondary)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
