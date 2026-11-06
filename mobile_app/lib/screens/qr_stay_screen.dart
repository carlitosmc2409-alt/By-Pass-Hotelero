import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/api_client.dart';
import '../core/theme.dart';
import '../models/models.dart';
import 'booking_payment_screen.dart';

class QrStayScreen extends StatefulWidget {
  final ApiClient api;
  final String reservationId;

  const QrStayScreen({
    super.key,
    required this.api,
    required this.reservationId,
  });

  @override
  State<QrStayScreen> createState() => _QrStayScreenState();
}

class _QrStayScreenState extends State<QrStayScreen> {
  bool _loading = true;
  String? _error;
  String? _lockMessage;
  QrAccessData? _qr;
  RoomModel? _roomInfo;
  HotelModel? _hotelInfo;

  @override
  void initState() {
    super.initState();
    _loadQr();
  }

  Future<void> _loadQr() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final qr = await widget.api.fetchQrAccess(widget.reservationId);
      try {
        final detail = await widget.api.fetchReservationDetail(widget.reservationId);
        final roomMap = (detail['room'] as Map<String, dynamic>?) ?? const {};
        final hotelMap = (roomMap['hotel'] as Map<String, dynamic>?) ?? const {};
        _roomInfo = RoomModel.fromJson(roomMap);
        _hotelInfo = HotelModel.fromJson(hotelMap);
      } catch (_) {}

      if (mounted) {
        setState(() {
          _qr = qr;
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

  Uint8List? _decodeQrPng(String dataUrl) {
    final idx = dataUrl.indexOf('base64,');
    if (idx == -1) return null;
    return base64Decode(dataUrl.substring(idx + 7));
  }

  Future<void> _openExtendFlow() async {
    final qr = _qr;
    if (qr == null) return;

    final room = _roomInfo ??
        RoomModel(
          id: '',
          name: qr.roomName,
          type: 'STANDARD',
          pricePerHour: 15,
          pricePerNight: 60,
          currency: 'USD',
          amenities: const [],
          status: 'OCCUPIED',
        );
    final hotel = _hotelInfo ??
        HotelModel(
          id: '',
          name: qr.hotelName,
          address: '',
          city: '',
        );

    final extended = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => BookingPaymentScreen(
          api: widget.api,
          hotel: hotel,
          room: room,
          extendingReservationId: widget.reservationId,
        ),
      ),
    );

    if (extended == true && mounted) {
      await _loadQr();
    }
  }

  Future<void> _simulateDoorOpen() async {
    final qr = _qr;
    if (qr == null) return;
    try {
      final res = await widget.api.simulateDoorScan(qr.rawToken);
      if (mounted) {
        setState(() {
          _lockMessage = '🔓 ${res['message']}';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _lockMessage = '🔒 Acceso denegado: $e';
        });
      }
    }
  }

  Future<void> _checkout() async {
    await widget.api.checkoutReservation(widget.reservationId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Check-out completado. Tu código QR fue invalidado.'),
      ),
    );
    Navigator.of(context).pop();
  }

  String _formatDateTime(DateTime dt) {
    final local = dt.toLocal();
    final dd = local.day.toString().padLeft(2, '0');
    final mo = local.month.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$dd/$mo · $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final qr = _qr;
    final pngBytes = qr != null ? _decodeQrPng(qr.qrDataUrl) : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tu Llave Digital QR'),
        actions: [
          IconButton(
            tooltip: 'Rotar / Actualizar QR',
            onPressed: _loading ? null : _loadQr,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppTheme.danger),
                    ),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 460),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                children: [
                                  const Icon(
                                    Icons.verified_rounded,
                                    color: AppTheme.accent,
                                    size: 42,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Habitación ${qr!.roomName}',
                                    style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    qr.hotelName,
                                    style: const TextStyle(
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  if (pngBytes != null)
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(16),
                                      child: Image.memory(
                                        pngBytes,
                                        width: 240,
                                        height: 240,
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                  const SizedBox(height: 16),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color:
                                          AppTheme.accent.withValues(alpha: 0.14),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      'Válido hasta: ${_formatDateTime(qr.validUntil)}',
                                      style: const TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.accent,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (_lockMessage != null) ...[
                            const SizedBox(height: 14),
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Text(
                                  _lockMessage!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 18),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.accent,
                              foregroundColor: Colors.black,
                            ),
                            onPressed: _openExtendFlow,
                            icon: const Icon(Icons.more_time_rounded),
                            label: const Text(
                              'Extender Estadía (+1h, +2h...) en Privado',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(height: 10),
                          ElevatedButton.icon(
                            onPressed: () async {
                              await Clipboard.setData(
                                ClipboardData(text: qr.rawToken),
                              );
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Token QR copiado al portapapeles para probar en el Lector de Puerta.',
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(Icons.copy_rounded),
                            label: const Text(
                              'Copiar Token para Lector QR de Puerta',
                            ),
                          ),
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            onPressed: _simulateDoorOpen,
                            icon: const Icon(Icons.sensor_door_outlined),
                            label: const Text(
                              'Prueba rápida de apertura desde aquí',
                            ),
                          ),
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.danger,
                            ),
                            onPressed: _checkout,
                            icon: const Icon(Icons.exit_to_app_rounded),
                            label: const Text(
                              'Realizar Check-out y desactivar QR',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
    );
  }
}
