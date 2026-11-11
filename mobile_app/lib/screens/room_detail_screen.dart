import 'package:flutter/material.dart';
import '../core/api_client.dart';
import '../core/theme.dart';
import '../models/models.dart';
import 'booking_payment_screen.dart';
import 'stealth_screen.dart';

class RoomDetailScreen extends StatefulWidget {
  final ApiClient api;
  final HotelModel hotel;
  final RoomModel room;

  const RoomDetailScreen({
    super.key,
    required this.api,
    required this.hotel,
    required this.room,
  });

  @override
  State<RoomDetailScreen> createState() => _RoomDetailScreenState();
}

class _RoomDetailScreenState extends State<RoomDetailScreen> {
  int _selectedPreview = 0;
  bool _isFavorite = false;

  final List<IconData> _previewIcons = const [
    Icons.bathtub_outlined,
    Icons.king_bed_outlined,
    Icons.wine_bar_outlined,
    Icons.deck_outlined,
  ];

  final List<String> _previewLabels = const [
    'Jacuzzi Privado',
    'Cama King Size',
    'Minibar & Copas',
    'Ambiente Iluminado',
  ];

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    final hotel = widget.hotel;
    final tierAccent = AppTheme.roomTierAccent(room.type);

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: CustomScrollView(
        slivers: [
          // Imagen / Cabecera interactiva con botones flotantes
          SliverAppBar(
            expandedHeight: 330,
            pinned: true,
            backgroundColor: AppTheme.background,
            leading: Padding(
              padding: const EdgeInsets.only(left: 14),
              child: CircleAvatar(
                backgroundColor: Colors.black.withValues(alpha: 0.55),
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 14),
                child: CircleAvatar(
                  backgroundColor: Colors.black.withValues(alpha: 0.55),
                  child: IconButton(
                    icon: Icon(
                      _isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                      color: _isFavorite ? AppTheme.danger : Colors.white,
                      size: 20,
                    ),
                    onPressed: () => setState(() => _isFavorite = !_isFavorite),
                  ),
                ),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFF332A24),
                          const Color(0xFF221A1E),
                          AppTheme.background,
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 100,
                            height: 100,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppTheme.warmBeige.withValues(alpha: 0.12),
                              border: Border.all(color: AppTheme.warmBeige.withValues(alpha: 0.3)),
                            ),
                            child: Icon(
                              _previewIcons[_selectedPreview],
                              size: 50,
                              color: AppTheme.warmBeige,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _previewLabels[_selectedPreview],
                            style: const TextStyle(
                              color: AppTheme.warmBeige,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 16,
                    left: 20,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.star_rounded, color: AppTheme.gold, size: 16),
                          const SizedBox(width: 4),
                          const Text(
                            '5.0',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '· ${AppTheme.roomTierLabel(room.type)}',
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 12,
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

          // Contenido Detallado
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Título y Precio por noche / hora
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Suite ${room.name} · ${hotel.name}',
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(Icons.location_on_outlined, size: 14, color: AppTheme.textSecondary),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    '${hotel.address}, ${hotel.city}',
                                    style: const TextStyle(
                                      color: AppTheme.textSecondary,
                                      fontSize: 12.5,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 14),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(
                                '\$${room.pricePerHour.toStringAsFixed(0)}',
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.warmBeige,
                                ),
                              ),
                              const Text(
                                ' /h',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            'Amanecida \$${room.pricePerNight.toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 18),

                  // Tags de comodidades / servicios (Free WiFi, Desayuno/Room Service, etc.)
                  Row(
                    children: [
                      _featurePill(Icons.wifi_rounded, 'WiFi Privado'),
                      const SizedBox(width: 10),
                      _featurePill(Icons.directions_car_filled_outlined, 'Pase FAAC'),
                      const SizedBox(width: 10),
                      _featurePill(Icons.room_service_outlined, 'Pasaplatos'),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Descripción
                  const Text(
                    'Descripción',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Espacio boutique con total discreción y privacidad absoluta. Diseñado para momentos exclusivos con climatización independiente, acabados en tonos cálidos naturales, servicio directo a la suite mediante pasaplatos sellado y acceso sin contacto en barrera vehicular FAAC.',
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.55,
                      color: AppTheme.textSecondary.withValues(alpha: 0.9),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Vista previa en miniatura (Preview)
                  const Text(
                    'Vistas de la Suite (Preview)',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: List.generate(_previewIcons.length, (idx) {
                      final selected = _selectedPreview == idx;
                      return GestureDetector(
                        onTap: () => setState(() => _selectedPreview = idx),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: AppTheme.card,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: selected ? AppTheme.warmBeige : Colors.white.withValues(alpha: 0.08),
                              width: selected ? 2 : 1,
                            ),
                          ),
                          child: Icon(
                            _previewIcons[idx],
                            color: selected ? AppTheme.warmBeige : AppTheme.textSecondary,
                            size: 28,
                          ),
                        ),
                      );
                    }),
                  ),

                  const SizedBox(height: 36),

                  // Botón de Reserva Booking Now
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.warmBeige,
                      foregroundColor: const Color(0xFF1E1B18),
                      minimumSize: const Size.fromHeight(54),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(22),
                      ),
                      elevation: 0,
                    ),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => BookingPaymentScreen(
                            api: widget.api,
                            hotel: hotel,
                            room: room,
                          ),
                        ),
                      );
                    },
                    child: const Text(
                      'Reservar Ahora (Booking Now)',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _featurePill(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.warmBeige),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
