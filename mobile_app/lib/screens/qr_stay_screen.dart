import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../core/api_client.dart';
import '../core/theme.dart';
import '../models/models.dart';

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

  Future<void> _simulateDoorOpen() async {
    final qr = _qr;
    if (qr == null) return;
    try {
      final res = await widget.api.simulateDoorScan(qr.rawToken);
      if (mounted) {
        setState(() {
          _lockMessage = '🔓 Cerradura habitación ${res['roomName']}: ${res['message']}';
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

  @override
  Widget build(BuildContext context) {
    final qr = _qr;
    final pngBytes = qr != null ? _decodeQrPng(qr.qrDataUrl) : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tu Llave Digital QR'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Text(_error!, style: const TextStyle(color: AppTheme.danger)),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            children: [
                              const Icon(
                                Icons.check_circle_rounded,
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
                                style: const TextStyle(color: AppTheme.textSecondary),
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
                              Text(
                                'Válido hasta: ${qr.validUntil.toLocal()}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppTheme.textSecondary,
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
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      ElevatedButton.icon(
                        onPressed: _simulateDoorOpen,
                        icon: const Icon(Icons.sensor_door_outlined),
                        label: const Text('Simular escaneo QR en la cerradura'),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _checkout,
                        icon: const Icon(Icons.exit_to_app_rounded),
                        label: const Text('Realizar Check-out y desactivar QR'),
                      ),
                    ],
                  ),
                ),
    );
  }
}
