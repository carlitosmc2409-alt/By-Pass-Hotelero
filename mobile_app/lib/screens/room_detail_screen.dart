import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/api_client.dart';
import '../core/smart_photo.dart';
import '../core/theme.dart';
import '../models/models.dart';
import 'booking_payment_screen.dart';

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

  Future<void> _openGoogleMaps() async {
    final lat = widget.hotel.latitude ?? 10.4806;
    final lng = widget.hotel.longitude ?? -66.9036;
    final url = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(url);
      }
    } catch (_) {}
  }

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
    'Ambiente Cálido',
  ];

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    final hotel = widget.hotel;
    final isDark = AppTheme.isDark;

    // Galería combinada: fotos de la habitación + fotos del hotel
    final List<String> galleryPhotos = [
      ...room.photos,
      if (hotel.effectiveCoverPhoto != null &&
          !room.photos.contains(hotel.effectiveCoverPhoto))
        hotel.effectiveCoverPhoto!,
      ...hotel.photos.where((p) => !room.photos.contains(p)),
    ];
    final hasPhotos = galleryPhotos.isNotEmpty;
    final safeIdx = hasPhotos
        ? _selectedPreview.clamp(0, galleryPhotos.length - 1)
        : _selectedPreview.clamp(0, _previewIcons.length - 1);

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 320,
            pinned: true,
            backgroundColor: AppTheme.background,
            leading: Padding(
              padding: const EdgeInsets.only(left: 14),
              child: CircleAvatar(
                backgroundColor: AppTheme.card.withValues(alpha: 0.85),
                child: IconButton(
                  icon: Icon(
                    Icons.arrow_back_ios_new_rounded,
                    size: 17,
                    color: AppTheme.textPrimary,
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: CircleAvatar(
                  backgroundColor: AppTheme.card.withValues(alpha: 0.85),
                  child: AppTheme.themeToggleButton(
                    iconColor: AppTheme.textPrimary,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 14),
                child: CircleAvatar(
                  backgroundColor: AppTheme.card.withValues(alpha: 0.85),
                  child: IconButton(
                    icon: Icon(
                      _isFavorite
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      color:
                          _isFavorite ? AppTheme.danger : AppTheme.textPrimary,
                      size: 19,
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
                  if (hasPhotos) ...[
                    SmartPhoto(
                      source: galleryPhotos[safeIdx],
                      fit: BoxFit.cover,
                    ),
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.black.withValues(alpha: 0.15),
                            Colors.black.withValues(alpha: 0.55),
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                    ),
                  ] else
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isDark
                              ? [
                                  const Color(0xFF2B241F),
                                  const Color(0xFF1F1C1A),
                                  AppTheme.background,
                                ]
                              : [
                                  const Color(0xFFEBE2D6),
                                  const Color(0xFFF3EFE8),
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
                              width: 96,
                              height: 96,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppTheme.primary.withValues(alpha: 0.14),
                                border: Border.all(
                                  color:
                                      AppTheme.primary.withValues(alpha: 0.35),
                                ),
                              ),
                              child: Icon(
                                _previewIcons[safeIdx],
                                size: 46,
                                color: AppTheme.primary,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _previewLabels[safeIdx],
                              style: TextStyle(
                                color: AppTheme.primary,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  Positioned(
                    bottom: 16,
                    left: 20,
                    right: 20,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.card.withValues(alpha: 0.90),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: AppTheme.border),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.star_rounded,
                                color: AppTheme.gold,
                                size: 16,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '5.0',
                                style: TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '· ${AppTheme.roomTierLabel(room.type)}',
                                style: TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (hasPhotos)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.65),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              'Foto ${safeIdx + 1} de ${galleryPhotos.length}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            InkWell(
                              onTap: _openGoogleMaps,
                              borderRadius: BorderRadius.circular(6),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.place_rounded,
                                    size: 15,
                                    color: AppTheme.accent,
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      '${hotel.address}, ${hotel.city} · Ver en Google Maps ↗',
                                      style: TextStyle(
                                        color: AppTheme.accent,
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
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
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.primary,
                                ),
                              ),
                              Text(
                                ' /h',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            '24h: \$${room.pricePerNight.toStringAsFixed(0)}',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _featurePill(Icons.wifi_rounded, 'WiFi Privado'),
                      _featurePill(
                        Icons.directions_car_filled_outlined,
                        'Barrera QR',
                      ),
                      _featurePill(Icons.room_service_outlined, 'Pasaplatos'),
                      ...room.amenities
                          .take(4)
                          .map((a) => _featurePill(Icons.check_rounded, a)),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    hasPhotos
                        ? 'Galería Fotográfica de la Habitación y Hotel'
                        : 'Ambientes de la Suite',
                    style: TextStyle(
                      fontSize: 16.5,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (hasPhotos)
                    SizedBox(
                      height: 82,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: galleryPhotos.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 10),
                        itemBuilder: (_, idx) {
                          final selected = safeIdx == idx;
                          return GestureDetector(
                            onTap: () => setState(() => _selectedPreview = idx),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 160),
                              width: 110,
                              height: 82,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: selected
                                      ? AppTheme.primary
                                      : AppTheme.border,
                                  width: selected ? 2.5 : 1,
                                ),
                              ),
                              child: SmartPhoto(
                                source: galleryPhotos[idx],
                                width: 110,
                                height: 82,
                                borderRadius: BorderRadius.circular(11),
                              ),
                            ),
                          );
                        },
                      ),
                    )
                  else
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(_previewIcons.length, (idx) {
                        final selected = safeIdx == idx;
                        return GestureDetector(
                          onTap: () => setState(() => _selectedPreview = idx),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              color: AppTheme.card,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: selected
                                    ? AppTheme.primary
                                    : AppTheme.border,
                                width: selected ? 2 : 1,
                              ),
                            ),
                            child: Icon(
                              _previewIcons[idx],
                              color: selected
                                  ? AppTheme.primary
                                  : AppTheme.textSecondary,
                              size: 26,
                            ),
                          ),
                        );
                      }),
                    ),
                  const SizedBox(height: 24),
                  Text(
                    'Acerca de esta suite',
                    style: TextStyle(
                      fontSize: 16.5,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    (room.description != null &&
                            room.description!.trim().isNotEmpty)
                        ? room.description!
                        : 'Espacio diseñado con total discreción y comodidad. Cuenta con climatización independiente, ingreso directo con código QR en barrera vehicular y puerta de la habitación, y servicio a la habitación por pasaplatos.',
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.55,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton(
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
                    child: const Text('Continuar a Reserva y Pago'),
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
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.primary),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
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
