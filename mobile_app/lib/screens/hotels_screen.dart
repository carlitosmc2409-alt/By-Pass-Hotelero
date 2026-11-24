import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/api_client.dart';
import '../core/smart_photo.dart';
import '../core/theme.dart';
import '../models/models.dart';
import 'booking_payment_screen.dart';
import 'qr_stay_screen.dart';
import 'room_detail_screen.dart';
import 'stealth_screen.dart';

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
  bool _privacyMask = false;
  bool _sseLive = false;
  String _searchQuery = '';
  String _selectedCategory = 'ALL';
  String? _error;
  GuestProfile? _profile;
  List<HotelModel> _hotels = const [];
  List<GuestReservationSummary> _myReservations = const [];
  List<BankOption> _banks = const [
    BankOption(code: '0102', name: 'Banco de Venezuela'),
    BankOption(code: '0134', name: 'Banesco'),
    BankOption(code: '0105', name: 'Mercantil'),
    BankOption(code: '0108', name: 'Provincial'),
    BankOption(code: '0172', name: 'Bancamiga'),
    BankOption(code: '0191', name: 'BNC'),
  ];

  Timer? _clockTimer;
  StreamSubscription<Map<String, dynamic>>? _sseSub;

  @override
  void initState() {
    super.initState();
    unawaited(_loadData());
    _startClock();
    _connectRealtime();
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _sseSub?.cancel();
    super.dispose();
  }

  void _startClock() {
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _myReservations.any((r) => r.isActive)) {
        setState(() {});
      }
    });
  }

  void _connectRealtime() {
    _sseSub = widget.api.connectRealtimeEvents().listen((event) {
      if (!mounted) return;
      final type = event['type']?.toString() ?? '';
      if (type == 'CONNECTED') {
        setState(() => _sseLive = true);
        return;
      }
      if (type == 'ROOM_SERVICE_DELIVERED') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.accent,
            content: Text(
              '🛎️ ¡Tu pedido ya está listo en el pasaplatos de tu habitación!',
              style: TextStyle(
                color: AppTheme.onAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );
      }
      if (const {
        'PAYMENT_APPROVED',
        'ROOM_STATUS_CHANGED',
        'ROOM_SERVICE_ORDER',
        'ROOM_SERVICE_DELIVERED',
      }.contains(type)) {
        unawaited(_loadData(silent: true));
      }
    });
  }

  Future<void> _loadData({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final results = await Future.wait([
        widget.api.fetchGuestProfile(),
        widget.api.fetchHotels(),
        widget.api.fetchMyReservations(),
      ]);
      try {
        final bankList = await widget.api.fetchBanks();
        if (bankList.isNotEmpty) _banks = bankList;
      } on Object {
        // Ignora fallo secundario de bancos
      }

      if (mounted) {
        setState(() {
          _profile = results[0] as GuestProfile;
          _hotels = results[1] as List<HotelModel>;
          _myReservations = results[2] as List<GuestReservationSummary>;
        });
      }
    } on ApiException catch (e) {
      if (e.statusCode == 401) {
        widget.onLogout();
        return;
      }
      if (mounted && !silent) setState(() => _error = e.toString());
    } on Object catch (e) {
      if (mounted && !silent) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted && !silent) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _openStealthPinSettings() async {
    final currentPin = await StealthCalculatorScreen.getSavedPin();
    if (!mounted) return;
    final ctrl = TextEditingController(text: currentPin);

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Configurar Modo Camuflaje'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Al tocar el ícono de calculadora, la app se convierte al instante en una calculadora funcional. Escribe tu PIN y pulsa "=" para regresar.',
              style: TextStyle(fontSize: 12.5, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: const InputDecoration(
                labelText: 'PIN numérico privado',
                prefixIcon: Icon(Icons.pin_outlined),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              final next = ctrl.text.trim();
              if (next.length >= 4) {
                await StealthCalculatorScreen.savePin(next);
                if (ctx.mounted) Navigator.of(ctx).pop();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('PIN de camuflaje actualizado ($next).'),
                    ),
                  );
                }
              }
            },
            child: const Text('Guardar PIN'),
          ),
        ],
      ),
    );
  }

  Future<void> _openEditPaymentProfileDialog() async {
    final profile = _profile;
    if (profile == null) return;

    String selectedBank = profile.paymentProfile?.bankCode ?? '0102';
    if (!_banks.any((b) => b.code == selectedBank)) {
      selectedBank = '0102';
    }
    final cedulaCtrl = TextEditingController(text: profile.cedula ?? '');
    final phoneCtrl = TextEditingController(text: profile.phone);

    final updated = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('Actualizar Pago Móvil Frecuente'),
              content: SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Estos datos cifrados permiten que el sistema reconozca tus pagos BDV al instante sin enviar capturas ni escribir referencias.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<String>(
                        initialValue: selectedBank,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Banco emisor',
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
                        onChanged: (v) {
                          if (v != null) {
                            setDialogState(() => selectedBank = v);
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: cedulaCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Cédula titular (ej: V-20123456)',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: phoneCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Teléfono afiliado (+58412...)',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    try {
                      await widget.api.updatePaymentProfile(
                        paymentBank: selectedBank,
                        paymentPhone: phoneCtrl.text.trim(),
                        paymentCedula: cedulaCtrl.text.trim(),
                      );
                      if (ctx.mounted) Navigator.of(ctx).pop(true);
                    } on Object catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(e.toString())),
                        );
                      }
                    }
                  },
                  child: const Text('Guardar'),
                ),
              ],
            );
          },
        );
      },
    );

    if (updated == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Datos de Pago Móvil frecuente actualizados.'),
        ),
      );
      await _loadData();
    }
  }

  String _maskLabel(String original, {String fallback = 'Reserva Privada •••'}) {
    return _privacyMask ? fallback : original;
  }

  String _formatShortTime(DateTime dt) {
    final local = dt.toLocal();
    final dd = local.day.toString().padLeft(2, '0');
    final mo = local.month.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$dd/$mo $hh:$mm';
  }

  String _formatLiveRemaining(DateTime checkOut) {
    final diff = checkOut.difference(DateTime.now());
    if (diff.isNegative) return '00:00:00';
    final hh = diff.inHours.toString().padLeft(2, '0');
    final mm = diff.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = diff.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$hh:$mm:$ss';
  }

  Future<void> _openGoogleMaps(HotelModel hotel) async {
    final lat = hotel.latitude ?? 10.4806;
    final lng = hotel.longitude ?? -66.9036;
    final url = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(url);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo abrir Google Maps: $e')),
        );
      }
    }
  }

  Future<void> _openGoogleMapsDirections(HotelModel hotel) async {
    final lat = hotel.latitude ?? 10.4806;
    final lng = hotel.longitude ?? -66.9036;
    final url = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng');
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(url);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo iniciar navegación: $e')),
        );
      }
    }
  }

  void _copyLocation(HotelModel hotel) {
    final lat = hotel.latitude ?? 10.4806;
    final lng = hotel.longitude ?? -66.9036;
    Clipboard.setData(ClipboardData(
      text: '${hotel.name}\nDirección: ${hotel.address}, ${hotel.city}\nCoordenadas GPS: $lat, $lng\nhttps://maps.google.com/?q=$lat,$lng',
    ));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('📍 Dirección y coordenadas GPS copiadas al portapapeles.'),
      ),
    );
  }

  Future<void> _openReviewsModal(HotelModel hotel) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.gold,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          hotel.rating.toStringAsFixed(1),
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            color: Colors.black,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Opiniones Verificadas',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${hotel.reviewsCount} huéspedes verificados han calificado esta propiedad',
                style: TextStyle(fontSize: 12.5, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 16),
              if (hotel.reviews.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: Text(
                      'Todas las opiniones registradas destacan la discreción y velocidad de check-in.',
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                  ),
                )
              else
                ...hotel.reviews.take(5).map((rev) {
                  final tags = (rev['tags'] as List<dynamic>? ?? []).cast<String>();
                  final rating = (rev['rating'] as num?)?.toInt() ?? 5;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              rev['guestName']?.toString() ?? 'Huésped',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            Row(
                              children: List.generate(
                                5,
                                (i) => Icon(
                                  i < rating ? Icons.star_rounded : Icons.star_border_rounded,
                                  size: 14,
                                  color: AppTheme.gold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (tags.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            children: tags.map((t) => Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppTheme.gold.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                t,
                                style: TextStyle(fontSize: 10, color: AppTheme.gold, fontWeight: FontWeight.bold),
                              ),
                            )).toList(),
                          ),
                        ],
                        if ((rev['comment'] ?? '').toString().isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            rev['comment'].toString(),
                            style: TextStyle(fontSize: 12, color: AppTheme.textPrimary),
                          ),
                        ],
                      ],
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openReviewDialog(GuestReservationSummary stay) async {
    int selectedRating = 5;
    final Set<String> selectedTags = {
      'Limpieza Impecable',
      'Privacidad Total',
      'Check-in Rápido',
    };
    final commentCtrl = TextEditingController();

    final tagsOptions = [
      'Limpieza Impecable',
      'Privacidad Total',
      'Check-in Rápido',
      'WiFi Veloz',
      'Pago Móvil Instantáneo',
      'Pasaplatos Discreto',
      'Jacuzzi Excelente',
      'Aire Frío 100%',
    ];

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: Row(
                children: [
                  Icon(Icons.star_rate_rounded, color: AppTheme.gold),
                  const SizedBox(width: 8),
                  const Text('Calificar Estadía'),
                ],
              ),
              content: SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tu opinión es 100% anónima para terceros y ayuda a mantener el estándar de calidad.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: List.generate(5, (idx) {
                            final star = idx + 1;
                            return IconButton(
                              iconSize: 32,
                              onPressed: () => setDialogState(() => selectedRating = star),
                              icon: Icon(
                                star <= selectedRating
                                    ? Icons.star_rounded
                                    : Icons.star_border_rounded,
                                color: AppTheme.gold,
                              ),
                            );
                          }),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Lo mejor de tu experiencia (1 toque):',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: tagsOptions.map((tag) {
                          final isChecked = selectedTags.contains(tag);
                          return FilterChip(
                            label: Text(tag, style: const TextStyle(fontSize: 11)),
                            selected: isChecked,
                            selectedColor: AppTheme.gold.withValues(alpha: 0.25),
                            checkmarkColor: AppTheme.gold,
                            onSelected: (val) {
                              setDialogState(() {
                                if (val) {
                                  selectedTags.add(tag);
                                } else {
                                  selectedTags.remove(tag);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: commentCtrl,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Comentario opcional',
                          hintText: '¿Qué tal la suite y la discreción?',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.gold,
                    foregroundColor: Colors.black,
                  ),
                  onPressed: () async {
                    try {
                      await widget.api.submitReview(
                        reservationId: stay.id,
                        rating: selectedRating,
                        tags: selectedTags.toList(),
                        comment: commentCtrl.text.trim(),
                      );
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('¡Gracias! Tu calificación fue registrada.'),
                          ),
                        );
                      }
                      await _loadData(silent: true);
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Error: $e')),
                        );
                      }
                    }
                  },
                  child: const Text('Enviar Calificación'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildGoogleMapsSection(HotelModel hotel) {
    final lat = hotel.latitude ?? 10.4806;
    final lng = hotel.longitude ?? -66.9036;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            color: AppTheme.surface,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.map_rounded,
                      size: 18,
                      color: AppTheme.accent,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Ubicación & Google Maps',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'GPS: ${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.accent,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.place_rounded,
                      color: AppTheme.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _maskLabel(
                              hotel.address,
                              fallback: 'Dirección protegida •••',
                            ),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            '${hotel.city}, Venezuela · Entrada vehicular directa y discreta por rampa sin recepción.',
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
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: AppTheme.onPrimary,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () => _openGoogleMaps(hotel),
                      icon: const Icon(Icons.open_in_new_rounded, size: 16),
                      label: const Text('Abrir en Google Maps'),
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.accent,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () => _openGoogleMapsDirections(hotel),
                      icon: const Icon(Icons.directions_rounded, size: 16),
                      label: const Text('Cómo Llegar (Ruta)'),
                    ),
                    IconButton(
                      tooltip: 'Copiar dirección',
                      onPressed: () => _copyLocation(hotel),
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      style: IconButton.styleFrom(
                        backgroundColor: AppTheme.surface,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHotelReputationBadge(HotelModel hotel) {
    return InkWell(
      onTap: () => _openReviewsModal(hotel),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.gold.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppTheme.gold.withValues(alpha: 0.30),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.gold,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.star_rounded, size: 14, color: Colors.black87),
                  const SizedBox(width: 3),
                  Text(
                    hotel.rating.toStringAsFixed(1),
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Excelente · ${hotel.reviewsCount} opiniones verificadas de huéspedes',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 18, color: AppTheme.gold),
          ],
        ),
      ),
    );
  }

  Future<void> _quickExtendStay(
    GuestReservationSummary stay,
    int extraHours,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BookingPaymentScreen(
          api: widget.api,
          hotel: stay.hotel,
          room: stay.room,
          extendingReservationId: stay.id,
          initialHours: extraHours,
          autoStartHold: true,
        ),
      ),
    );
    unawaited(_loadData());
  }

  @override
  Widget build(BuildContext context) {
    final mainReservations =
        _myReservations.where((r) => !r.isRoomService).toList();
    final activeStay = mainReservations.where((r) => r.isActive).firstOrNull;
    final pendingStay =
        mainReservations.where((r) => r.isAwaitingPayment).firstOrNull;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              Icon(Icons.qr_code_2_rounded, color: AppTheme.primary, size: 22),
              const SizedBox(width: 8),
              const Text('StayPass'),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (_sseLive ? AppTheme.accent : AppTheme.textSecondary)
                      .withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _sseLive ? '● En línea' : '● Sync',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: _sseLive ? AppTheme.accent : AppTheme.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            AppTheme.themeToggleButton(),
            IconButton(
              tooltip: _privacyMask
                  ? 'Mostrar nombres reales'
                  : 'Ocultar nombres en pantalla',
              onPressed: () => setState(() => _privacyMask = !_privacyMask),
              icon: Icon(
                _privacyMask
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_outlined,
                color: _privacyMask ? AppTheme.primary : AppTheme.textSecondary,
                size: 20,
              ),
            ),
            IconButton(
              tooltip: 'Modo Camuflaje (Calculadora)',
              onPressed: StealthCalculatorScreen.enable,
              onLongPress: _openStealthPinSettings,
              icon: Icon(
                Icons.calculate_outlined,
                color: AppTheme.textSecondary,
                size: 21,
              ),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded),
              onSelected: (v) {
                if (v == 'theme') AppTheme.toggleTheme();
                if (v == 'refresh') _loadData();
                if (v == 'pin') _openStealthPinSettings();
                if (v == 'payment') _openEditPaymentProfileDialog();
                if (v == 'logout') widget.onLogout();
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'theme',
                  child: Text(
                    AppTheme.isDark
                        ? 'Cambiar a Tema Claro'
                        : 'Cambiar a Tema Oscuro',
                  ),
                ),
                const PopupMenuItem(
                  value: 'payment',
                  child: Text('Editar Pago Móvil Frecuente'),
                ),
                const PopupMenuItem(
                  value: 'pin',
                  child: Text('Configurar PIN de Camuflaje'),
                ),
                const PopupMenuItem(
                  value: 'refresh',
                  child: Text('Sincronizar ahora'),
                ),
                const PopupMenuItem(
                  value: 'logout',
                  child: Text('Cerrar sesión'),
                ),
              ],
            ),
          ],
          bottom: TabBar(
            indicatorColor: AppTheme.primary,
            labelColor: AppTheme.primary,
            unselectedLabelColor: AppTheme.textSecondary,
            dividerColor: AppTheme.border,
            tabs: [
              const Tab(
                icon: Icon(Icons.apartment_rounded, size: 19),
                text: 'Hoteles y Suites',
              ),
              Tab(
                icon: Badge(
                  backgroundColor: AppTheme.accent,
                  isLabelVisible: activeStay != null || pendingStay != null,
                  child: const Icon(Icons.calendar_month_outlined, size: 19),
                ),
                text: 'Mis Estadías',
              ),
            ],
          ),
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
                          Text(
                            _error!,
                            style: TextStyle(color: AppTheme.danger),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _loadData,
                            child: const Text('Reintentar'),
                          ),
                        ],
                      ),
                    ),
                  )
                : TabBarView(
                    children: [
                      _buildExploreTab(activeStay, pendingStay),
                      _buildMyStaysTab(mainReservations),
                    ],
                  ),
      ),
    );
  }

  Widget _buildExploreTab(
    GuestReservationSummary? activeStay,
    GuestReservationSummary? pendingStay,
  ) {
    final paymentProfile = _profile?.paymentProfile;
    final remainingMinutes = activeStay != null
        ? activeStay.checkOut.difference(DateTime.now()).inMinutes
        : 999;
    final expiringSoon =
        activeStay != null && remainingMinutes <= 15 && remainingMinutes >= -15;

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Barra de búsqueda interactiva y simple
          TextField(
            onChanged: (v) => setState(() => _searchQuery = v.trim()),
            decoration: InputDecoration(
              hintText: 'Buscar hotel, suite o comodidad...',
              prefixIcon: Icon(
                Icons.search_rounded,
                color: AppTheme.primary,
                size: 20,
              ),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 18),
                      onPressed: () => setState(() => _searchQuery = ''),
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 12),

          // Filtros rápidos amigables
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _categoryPill('ALL', Icons.grid_view_rounded, 'Todas'),
                const SizedBox(width: 8),
                _categoryPill(
                  'AVAILABLE',
                  Icons.check_circle_outline_rounded,
                  'Disponibles ahora',
                ),
                const SizedBox(width: 8),
                _categoryPill('SUITE', Icons.king_bed_outlined, 'Suites'),
                const SizedBox(width: 8),
                _categoryPill('PREMIUM', Icons.hot_tub_outlined, 'Jacuzzi VIP'),
              ],
            ),
          ),
          const SizedBox(height: 16),

          if (activeStay != null) ...[
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppTheme.card,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: (expiringSoon ? AppTheme.warning : AppTheme.accent)
                      .withValues(alpha: 0.45),
                  width: 1.4,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.vpn_key_rounded,
                            color: expiringSoon
                                ? AppTheme.warning
                                : AppTheme.accent,
                            size: 19,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            expiringSoon
                                ? 'VENCIMIENTO PRÓXIMO'
                                : 'ESTADÍA ACTIVA',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 11.5,
                              letterSpacing: 0.5,
                              color: expiringSoon
                                  ? AppTheme.warning
                                  : AppTheme.accent,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.surface,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '⏱ ${_formatLiveRemaining(activeStay.checkOut)}',
                          style: TextStyle(
                            fontFeatures: const [FontFeature.tabularFigures()],
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            color: expiringSoon
                                ? AppTheme.warning
                                : AppTheme.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _maskLabel(
                      'Habitación ${activeStay.room.name} · ${activeStay.hotel.name}',
                      fallback: 'Suite Privada Activa •••',
                    ),
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Salida: ${_formatShortTime(activeStay.checkOut)} · Pase Barrera QR habilitado',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  if (expiringSoon) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.warning.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppTheme.warning.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Quedan menos de 15 min. Extiende con un toque:',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ActionChip(
                            backgroundColor: AppTheme.primary,
                            label: Text(
                              '+1h',
                              style: TextStyle(
                                color: AppTheme.onPrimary,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            onPressed: () => _quickExtendStay(activeStay, 1),
                          ),
                          const SizedBox(width: 6),
                          ActionChip(
                            backgroundColor: AppTheme.primary,
                            label: Text(
                              '+2h',
                              style: TextStyle(
                                color: AppTheme.onPrimary,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            onPressed: () => _quickExtendStay(activeStay, 2),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.accent,
                          foregroundColor: AppTheme.onAccent,
                          minimumSize: const Size(165, 42),
                        ),
                        onPressed: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => QrStayScreen(
                                api: widget.api,
                                reservationId: activeStay.id,
                              ),
                            ),
                          );
                          unawaited(_loadData());
                        },
                        icon: const Icon(Icons.qr_code_rounded, size: 18),
                        label: const Text('Ver Llave QR'),
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(140, 42),
                        ),
                        onPressed: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => QrStayScreen(
                                api: widget.api,
                                reservationId: activeStay.id,
                                openRoomServiceOnStart: true,
                              ),
                            ),
                          );
                          unawaited(_loadData());
                        },
                        icon: Icon(
                          Icons.room_service_outlined,
                          size: 18,
                          color: AppTheme.primary,
                        ),
                        label: const Text('Room Service'),
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(125, 42),
                        ),
                        onPressed: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => BookingPaymentScreen(
                                api: widget.api,
                                hotel: activeStay.hotel,
                                room: activeStay.room,
                                extendingReservationId: activeStay.id,
                              ),
                            ),
                          );
                          unawaited(_loadData());
                        },
                        icon: const Icon(Icons.more_time_rounded, size: 18),
                        label: const Text('+ Extender'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (pendingStay != null) ...[
            Card(
              child: ListTile(
                leading: Icon(
                  Icons.pending_actions_rounded,
                  color: AppTheme.warning,
                ),
                title: Text(
                  pendingStay.isExtension
                      ? 'Extensión pendiente · Hab. ${pendingStay.room.name}'
                      : 'Reserva pendiente de pago · Hab. ${pendingStay.room.name}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  'Bs. ${pendingStay.payment?['amountVes'] ?? pendingStay.totalAmount} · Toca para completar Pago Móvil',
                  style: const TextStyle(fontSize: 12.5),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () async {
                  final resumable = pendingStay.toResumableReservation();
                  if (resumable == null) return;
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => BookingPaymentScreen(
                        api: widget.api,
                        hotel: pendingStay.hotel,
                        room: pendingStay.room,
                        resumeReservation: resumable,
                      ),
                    ),
                  );
                  unawaited(_loadData());
                },
              ),
            ),
            const SizedBox(height: 14),
          ],
          if (paymentProfile != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.border),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.verified_user_outlined,
                    color: AppTheme.accent,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Pago Móvil Frecuente Configurado',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        Text(
                          '${paymentProfile.bankName ?? paymentProfile.bankCode} · CI ${paymentProfile.cedulaMasked} · ${paymentProfile.phoneMasked}',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: _openEditPaymentProfileDialog,
                    child: const Text('Editar'),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          for (final hotel in _hotels) ...[
            Builder(
              builder: (context) {
                final filteredRooms = hotel.rooms.where((room) {
                  if (_selectedCategory == 'AVAILABLE' && !room.isAvailable) {
                    return false;
                  }
                  if (_selectedCategory == 'SUITE' &&
                      room.type.toUpperCase() != 'SUITE') {
                    return false;
                  }
                  if (_selectedCategory == 'PREMIUM' &&
                      room.type.toUpperCase() != 'PREMIUM') {
                    return false;
                  }
                  if (_searchQuery.isNotEmpty) {
                    final q = _searchQuery.toLowerCase();
                    final matchHotel = hotel.name.toLowerCase().contains(q) ||
                        hotel.city.toLowerCase().contains(q);
                    final matchRoom = room.name.toLowerCase().contains(q) ||
                        room.type.toLowerCase().contains(q) ||
                        room.amenities
                            .any((a) => a.toLowerCase().contains(q));
                    return matchHotel || matchRoom;
                  }
                  return true;
                }).toList();

                if (filteredRooms.isEmpty) {
                  return const SizedBox.shrink();
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (hotel.effectiveCoverPhoto != null && !_privacyMask)
                      Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        height: 120,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppTheme.border),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            SmartPhoto(
                              source: hotel.effectiveCoverPhoto,
                              fit: BoxFit.cover,
                            ),
                            Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.black.withValues(alpha: 0.72),
                                    Colors.black.withValues(alpha: 0.15),
                                  ],
                                  begin: Alignment.bottomLeft,
                                  end: Alignment.topRight,
                                ),
                              ),
                            ),
                            Positioned(
                              bottom: 12,
                              left: 14,
                              right: 14,
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
                                          hotel.name,
                                          style: const TextStyle(
                                            fontSize: 19,
                                            fontWeight: FontWeight.w800,
                                            color: Colors.white,
                                          ),
                                        ),
                                        Text(
                                          '${hotel.address} · ${hotel.city}',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.white70,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (hotel.faacEnabled)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.black
                                            .withValues(alpha: 0.65),
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons
                                                .directions_car_filled_outlined,
                                            size: 13.5,
                                            color: Colors.white,
                                          ),
                                          SizedBox(width: 5),
                                          Text(
                                            'Barrera QR',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _maskLabel(
                                      hotel.name,
                                      fallback: 'Establecimiento Boutique •••',
                                    ),
                                    style: TextStyle(
                                      fontSize: 19,
                                      fontWeight: FontWeight.w800,
                                      color: AppTheme.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _maskLabel(
                                      '${hotel.address} · ${hotel.city}',
                                      fallback: 'Ubicación protegida en pantalla',
                                    ),
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (hotel.faacEnabled)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.cyan.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: AppTheme.cyan.withValues(alpha: 0.28),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.directions_car_filled_outlined,
                                      size: 14,
                                      color: AppTheme.cyan,
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      'Acceso Vehicular QR',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.cyan,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 6),
                    _buildHotelReputationBadge(hotel),
                    _buildGoogleMapsSection(hotel),
                    for (final room in filteredRooms)
                      _buildBoutiqueRoomCard(hotel, room),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBoutiqueRoomCard(HotelModel hotel, RoomModel room) {
    final tierAccent = AppTheme.roomTierAccent(room.type);
    final isCleaning = room.status == 'CLEANING';

    return GestureDetector(
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => RoomDetailScreen(
              api: widget.api,
              hotel: hotel,
              room: room,
            ),
          ),
        );
        unawaited(_loadData());
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: room.isAvailable
                ? tierAccent.withValues(alpha: 0.30)
                : AppTheme.border,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (room.coverPhoto != null && !_privacyMask)
              SizedBox(
                height: 155,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    SmartPhoto(
                      source: room.coverPhoto,
                      fit: BoxFit.cover,
                    ),
                    if (room.photos.length > 1)
                      Positioned(
                        top: 10,
                        right: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.65),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.photo_library_outlined,
                                size: 13,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${room.photos.length} fotos',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                gradient: AppTheme.roomTierGradient(room.type),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppTheme.roomTierLabel(room.type).toUpperCase(),
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                          color: tierAccent,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _maskLabel(
                          'Suite ${room.name}',
                          fallback: 'Suite Privada •••',
                        ),
                        style: TextStyle(
                          fontSize: 17.5,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: (room.isAvailable
                              ? AppTheme.accent
                              : isCleaning
                                  ? AppTheme.cyan
                                  : AppTheme.warning)
                          .withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      room.isAvailable
                          ? 'Disponible'
                          : isCleaning
                              ? 'En preparación'
                              : 'Ocupada',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: room.isAvailable
                            ? AppTheme.accent
                            : isCleaning
                                ? AppTheme.cyan
                                : AppTheme.warning,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      _miniTag(Icons.directions_car_outlined, 'Estacionamiento'),
                      _miniTag(Icons.room_service_outlined, 'Room Service'),
                      ...room.amenities
                          .take(3)
                          .map((a) => _miniTag(Icons.check_rounded, a)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(
                                '\$${room.pricePerHour.toStringAsFixed(0)}',
                                style: TextStyle(
                                  fontSize: 21,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.primary,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                              Text(
                                ' / hora',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            '24 horas: \$${room.pricePerNight.toStringAsFixed(0)} USD',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(138, 42),
                        ),
                        onPressed: room.isAvailable
                            ? () async {
                                await Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => RoomDetailScreen(
                                      api: widget.api,
                                      hotel: hotel,
                                      room: room,
                                    ),
                                  ),
                                );
                                unawaited(_loadData());
                              }
                            : null,
                        icon: const Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 14,
                        ),
                        label: const Text('Reservar'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _categoryPill(String id, IconData icon, String label) {
    final isSelected = _selectedCategory == id;
    return GestureDetector(
      onTap: () => setState(() => _selectedCategory = id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primary : AppTheme.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? AppTheme.primary : AppTheme.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: isSelected ? AppTheme.onPrimary : AppTheme.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: isSelected ? AppTheme.onPrimary : AppTheme.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniTag(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12.5, color: AppTheme.textSecondary),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 11.5,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMyStaysTab(List<GuestReservationSummary> stays) {
    if (stays.isEmpty) {
      return Center(
        child: Text(
          'Aún no tienes estadías registradas.',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: stays.length,
        itemBuilder: (context, idx) {
          final r = stays[idx];
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              leading: CircleAvatar(
                backgroundColor: (r.isActive
                        ? AppTheme.accent
                        : r.isAwaitingPayment
                            ? AppTheme.warning
                            : AppTheme.gold)
                    .withValues(alpha: 0.16),
                child: Icon(
                  r.isActive
                      ? Icons.qr_code_2_rounded
                      : r.isAwaitingPayment
                          ? Icons.schedule_rounded
                          : Icons.history_rounded,
                  color: r.isActive
                      ? AppTheme.accent
                      : r.isAwaitingPayment
                          ? AppTheme.warning
                          : AppTheme.gold,
                ),
              ),
              title: Text(
                _maskLabel(
                  '${r.hotel.name} · Suite ${r.room.name}',
                  fallback: 'Suite Reservada •••',
                ),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                '${r.durationHours}h · \$${r.totalAmount.toStringAsFixed(0)} USD · Salida: ${_formatShortTime(r.checkOut)}\nEstado: ${r.status}',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                ),
              ),
              isThreeLine: true,
              trailing: r.isActive
                  ? ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.accent,
                        foregroundColor: AppTheme.onAccent,
                        minimumSize: const Size(94, 38),
                      ),
                      onPressed: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => QrStayScreen(
                              api: widget.api,
                              reservationId: r.id,
                            ),
                          ),
                        );
                        unawaited(_loadData());
                      },
                      child: const Text('Abrir QR'),
                    )
                  : r.isAwaitingPayment
                      ? OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(86, 38),
                          ),
                          onPressed: () async {
                            final resumable = r.toResumableReservation();
                            if (resumable == null) return;
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => BookingPaymentScreen(
                                  api: widget.api,
                                  hotel: r.hotel,
                                  room: r.room,
                                  resumeReservation: resumable,
                                ),
                              ),
                            );
                            unawaited(_loadData());
                          },
                          child: const Text('Pagar'),
                        )
                      : OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.gold,
                            side: BorderSide(
                              color: AppTheme.gold.withValues(alpha: 0.5),
                            ),
                            minimumSize: const Size(100, 36),
                          ),
                          onPressed: () => _openReviewDialog(r),
                          icon: const Icon(Icons.star_rounded, size: 16),
                          label: const Text('Calificar'),
                        ),
            ),
          );
        },
      ),
    );
  }
}
