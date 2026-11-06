import 'package:flutter/material.dart';
import '../core/api_client.dart';
import '../core/theme.dart';
import '../models/models.dart';
import 'booking_payment_screen.dart';

class HotelsScreen extends StatefulWidget {
  final ApiClient api;
  final VoidCallback onLogout;

  const HotelsScreen({
    super.key,
    required this.api,
    required this.onLogout,
  });

  @override
  State<HotelsScreen> createState() => _HotelsScreenState();
}

class _HotelsScreenState extends State<HotelsScreen> {
  bool _loading = true;
  String? _error;
  GuestProfile? _profile;
  List<HotelModel> _hotels = const [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final profile = await widget.api.fetchGuestProfile();
      final list = await widget.api.fetchHotels();
      final fullHotels = <HotelModel>[];
      for (final h in list) {
        fullHotels.add(await widget.api.fetchHotelDetail(h.id));
      }
      if (mounted) {
        setState(() {
          _profile = profile;
          _hotels = fullHotels;
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
    final paymentProfile = _profile?.paymentProfile;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Habitaciones disponibles'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _loadData,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: 'Cerrar sesión',
            onPressed: widget.onLogout,
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, style: const TextStyle(color: AppTheme.danger)),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _loadData,
                          child: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (paymentProfile != null)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.verified_user_rounded,
                                color: AppTheme.accent,
                                size: 28,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Pago Móvil Frecuente Verificado',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.accent,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      '${paymentProfile.bankName ?? paymentProfile.bankCode} · Cédula ${paymentProfile.cedulaMasked} · Tlf ${paymentProfile.phoneMasked}',
                                      style: const TextStyle(
                                        fontSize: 12.5,
                                        color: AppTheme.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    for (final hotel in _hotels) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              hotel.name,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${hotel.address} · ${hotel.city}',
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      for (final room in hotel.rooms)
                        Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Habitación ${room.name} (${room.type})',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: room.isAvailable
                                            ? AppTheme.accent.withValues(alpha: 0.15)
                                            : AppTheme.warning.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        room.isAvailable ? 'Disponible' : 'Ocupada',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: room.isAvailable
                                              ? AppTheme.accent
                                              : AppTheme.warning,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  children: room.amenities
                                      .map(
                                        (a) => Chip(
                                          label: Text(
                                            a,
                                            style: const TextStyle(fontSize: 11.5),
                                          ),
                                          visualDensity: VisualDensity.compact,
                                        ),
                                      )
                                      .toList(),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      '\$${room.pricePerHour.toStringAsFixed(0)} / hora  ·  \$${room.pricePerNight.toStringAsFixed(0)} / noche',
                                      style: const TextStyle(
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.textPrimary,
                                      ),
                                    ),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        minimumSize: const Size(130, 42),
                                      ),
                                      onPressed: room.isAvailable
                                          ? () async {
                                              await Navigator.of(context).push(
                                                MaterialPageRoute(
                                                  builder: (_) => BookingPaymentScreen(
                                                    api: widget.api,
                                                    hotel: hotel,
                                                    room: room,
                                                  ),
                                                ),
                                              );
                                              _loadData();
                                            }
                                          : null,
                                      child: const Text('Reservar'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
    );
  }
}
