import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/api_client.dart';
import '../core/theme.dart';
import '../models/models.dart';
import 'booking_payment_screen.dart';
import 'stealth_screen.dart';

class QrStayScreen extends StatefulWidget {
  final ApiClient api;
  final String reservationId;
  final bool openRoomServiceOnStart;

  const QrStayScreen({
    super.key,
    required this.api,
    required this.reservationId,
    this.openRoomServiceOnStart = false,
  });

  @override
  State<QrStayScreen> createState() => _QrStayScreenState();
}

class _QrStayScreenState extends State<QrStayScreen> {
  bool _loading = true;
  bool _faacTotemHighContrast = false;
  bool _simulateLowTimeAlert = false;
  bool _busyAction = false;
  String? _error;
  String? _hardwareFeedback;
  QrAccessData? _qr;
  RoomModel? _roomInfo;
  HotelModel? _hotelInfo;
  List<RoomServiceOrder> _orders = const [];

  Timer? _clockTimer;
  StreamSubscription<Map<String, dynamic>>? _sseSub;

  @override
  void initState() {
    super.initState();
    unawaited(
      _loadAll().then((_) {
        if (widget.openRoomServiceOnStart && mounted && _qr != null) {
          unawaited(_openRoomServiceSheet());
        }
      }),
    );
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _qr != null) setState(() {});
    });
    _subscribeEvents();
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _sseSub?.cancel();
    super.dispose();
  }

  void _subscribeEvents() {
    _sseSub = widget.api.connectRealtimeEvents().listen((event) {
      if (!mounted) return;
      final type = event['type']?.toString() ?? '';
      if (type == 'ROOM_SERVICE_DELIVERED') {
        setState(() {
          _hardwareFeedback =
              '🛎️ ¡Tu pedido fue depositado en el pasaplatos de tu habitación!';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.accent,
            content: Text(
              '🛎️ ¡Tu pedido ya está en el pasaplatos! Retíralo con total privacidad.',
              style: TextStyle(
                color: AppTheme.onAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );
        unawaited(_refreshOrders());
      } else if (type == 'FAAC_BARRIER_PULSE') {
        final dir = event['direction'] == 'EXIT' ? 'SALIDA' : 'ENTRADA';
        final ms = event['pulseDurationMs'] ?? 1000;
        setState(() {
          _hardwareFeedback =
              '🚗 Barrera ($dir) abierta · Pulso enviado (${ms}ms)';
        });
      } else if (type == 'DOOR_UNLOCK_PULSE') {
        setState(() {
          _hardwareFeedback =
              '🔓 Cerradura electrónica de la suite desbloqueada';
        });
      } else if (type == 'PAYMENT_APPROVED' || type == 'ROOM_SERVICE_ORDER') {
        unawaited(_loadAll(silent: true));
      }
    });
  }

  Future<void> _loadAll({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final qr = await widget.api.fetchQrAccess(widget.reservationId);
      try {
        final detail =
            await widget.api.fetchReservationDetail(widget.reservationId);
        final roomMap = (detail['room'] as Map<String, dynamic>?) ?? const {};
        final hotelMap =
            (roomMap['hotel'] as Map<String, dynamic>?) ?? const {};
        _roomInfo = RoomModel.fromJson(roomMap);
        _hotelInfo = HotelModel.fromJson(hotelMap);
      } on Object {
        // Ignora fallo secundario
      }

      List<RoomServiceOrder> orders = const [];
      try {
        orders = await widget.api.fetchRoomServiceOrders(widget.reservationId);
      } on Object {
        // Ignora fallo secundario
      }

      if (mounted) {
        setState(() {
          _qr = qr;
          _orders = orders;
        });
      }
    } on Object catch (e) {
      if (mounted && !silent) {
        setState(() {
          _error = e.toString();
        });
      }
    } finally {
      if (mounted && !silent) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _refreshOrders() async {
    try {
      final orders =
          await widget.api.fetchRoomServiceOrders(widget.reservationId);
      if (mounted) setState(() => _orders = orders);
    } on Object {
      // Ignora fallo transitorio
    }
  }

  Uint8List? _decodeQrPng(String dataUrl) {
    final idx = dataUrl.indexOf('base64,');
    if (idx == -1) return null;
    return base64Decode(dataUrl.substring(idx + 7));
  }

  RoomModel _resolvedRoom(QrAccessData qr) {
    return _roomInfo ??
        RoomModel(
          id: '',
          name: qr.roomName,
          type: 'SUITE',
          pricePerHour: 15,
          pricePerNight: 60,
          currency: 'USD',
          amenities: const [],
          status: 'OCCUPIED',
        );
  }

  HotelModel _resolvedHotel(QrAccessData qr) {
    return _hotelInfo ??
        HotelModel(
          id: qr.hotelId,
          name: qr.hotelName,
          address: '',
          city: '',
        );
  }

  Future<void> _openExtendFlow({int? quickHours}) async {
    final qr = _qr;
    if (qr == null) return;

    final extended = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => BookingPaymentScreen(
          api: widget.api,
          hotel: _resolvedHotel(qr),
          room: _resolvedRoom(qr),
          extendingReservationId: widget.reservationId,
          initialHours: quickHours,
          autoStartHold: quickHours != null,
        ),
      ),
    );

    if (extended == true && mounted) {
      setState(() => _simulateLowTimeAlert = false);
      await _loadAll();
    }
  }

  Future<void> _triggerRemoteFaac(String direction) async {
    setState(() => _busyAction = true);
    try {
      final res = await widget.api.openFaacBarrier(
        reservationId: widget.reservationId,
        direction: direction,
      );
      if (mounted) {
        setState(() {
          _hardwareFeedback = '🚗 ${res['message']}';
        });
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _hardwareFeedback = '⚠️ Barrera: $e';
        });
      }
    } finally {
      if (mounted) setState(() => _busyAction = false);
    }
  }

  Future<void> _simulateScanOnDevice(String deviceId, String label) async {
    final qr = _qr;
    if (qr == null) return;
    setState(() => _busyAction = true);
    try {
      final res = await widget.api.simulateDoorScan(
        qr.rawToken,
        deviceId: deviceId,
      );
      if (mounted) {
        setState(() {
          _hardwareFeedback = '✅ [$label] ${res['message']}';
        });
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _hardwareFeedback = '🔒 [$label] Acceso denegado: $e';
        });
      }
    } finally {
      if (mounted) setState(() => _busyAction = false);
    }
  }

  Future<void> _openRoomServiceSheet() async {
    final qr = _qr;
    if (qr == null || qr.hotelId.isEmpty) return;

    List<RoomServiceItem> menu = [];
    try {
      menu = await widget.api.fetchHotelMenu(qr.hotelId);
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo cargar el menú: $e')),
      );
      return;
    }

    if (!mounted) return;

    final Map<String, int> cart = {};
    final noteCtrl = TextEditingController();

    final createdOrder = await showModalBottomSheet<CreatedReservation>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        bool submitting = false;
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            double totalUsd = 0;
            for (final item in menu) {
              final qty = cart[item.id] ?? 0;
              totalUsd += item.priceUsd * qty;
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 560),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '🍾 Room Service por Pasaplatos',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Entrega discreta en la esclusa de tu habitación.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const Divider(height: 20),
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: menu.length,
                        itemBuilder: (_, idx) {
                          final item = menu[idx];
                          final qty = cart[item.id] ?? 0;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppTheme.surface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: qty > 0
                                    ? AppTheme.primary
                                    : AppTheme.border,
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                        ),
                                      ),
                                      if (item.description.isNotEmpty)
                                        Text(
                                          item.description,
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            color: AppTheme.textSecondary,
                                          ),
                                        ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '\$${item.priceUsd.toStringAsFixed(2)} USD',
                                        style: TextStyle(
                                          color: AppTheme.primary,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Row(
                                  children: [
                                    IconButton(
                                      onPressed: qty > 0
                                          ? () => setModalState(() {
                                                if (qty == 1) {
                                                  cart.remove(item.id);
                                                } else {
                                                  cart[item.id] = qty - 1;
                                                }
                                              })
                                          : null,
                                      icon: const Icon(
                                        Icons.remove_circle_outline,
                                      ),
                                    ),
                                    Text(
                                      '$qty',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 15,
                                      ),
                                    ),
                                    IconButton(
                                      onPressed: () => setModalState(() {
                                        cart[item.id] = qty + 1;
                                      }),
                                      icon: Icon(
                                        Icons.add_circle_rounded,
                                        color: AppTheme.primary,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: noteCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Nota opcional (ej: extra hielo)',
                        prefixIcon: Icon(Icons.notes_rounded),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: (totalUsd <= 0 || submitting)
                          ? null
                          : () async {
                              setModalState(() => submitting = true);
                              try {
                                final itemsPayload = cart.entries
                                    .map((e) => {'id': e.key, 'qty': e.value})
                                    .toList();
                                final order =
                                    await widget.api.createRoomServiceOrder(
                                  reservationId: widget.reservationId,
                                  items: itemsPayload,
                                  guestNote: noteCtrl.text.trim(),
                                );
                                if (ctx.mounted) {
                                  Navigator.of(ctx).pop(order);
                                }
                              } on Object catch (err) {
                                setModalState(() => submitting = false);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(err.toString())),
                                  );
                                }
                              }
                            },
                      icon: const Icon(Icons.payments_outlined),
                      label: Text(
                        totalUsd <= 0
                            ? 'Selecciona productos del menú'
                            : 'Pagar \$${totalUsd.toStringAsFixed(2)} USD con Pago Móvil',
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (createdOrder != null && mounted) {
      final paid = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => BookingPaymentScreen(
            api: widget.api,
            hotel: _resolvedHotel(qr),
            room: _resolvedRoom(qr),
            resumeReservation: createdOrder,
          ),
        ),
      );
      if (paid == true && mounted) {
        await _refreshOrders();
      }
    }
  }

  Future<void> _checkout() async {
    await widget.api.checkoutReservation(widget.reservationId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Check-out completado. Tu llave QR fue desactivada.'),
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

  String _formatCountdown(DateTime until) {
    final diff = until.difference(DateTime.now());
    if (diff.isNegative) return '00:00:00';
    final hh = diff.inHours.toString().padLeft(2, '0');
    final mm = diff.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = diff.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$hh:$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final qr = _qr;
    final pngBytes = qr != null ? _decodeQrPng(qr.qrDataUrl) : null;
    final remainingMins = qr != null
        ? qr.validUntil.difference(DateTime.now()).inMinutes
        : 999;
    final isAlertActive =
        _simulateLowTimeAlert || (remainingMins <= 15 && remainingMins >= -15);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi Llave QR'),
        actions: [
          AppTheme.themeToggleButton(),
          IconButton(
            tooltip: 'Modo Camuflaje (Calculadora)',
            onPressed: StealthCalculatorScreen.enable,
            icon: Icon(
              Icons.calculate_outlined,
              color: AppTheme.textSecondary,
              size: 20,
            ),
          ),
          IconButton(
            tooltip: 'Actualizar QR',
            onPressed: _loading ? null : () => _loadAll(),
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
                      style: TextStyle(color: AppTheme.danger),
                    ),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (qr?.isOfflineCached == true) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: Colors.blueAccent.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: Colors.blueAccent.withValues(alpha: 0.4),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.wifi_off_rounded,
                                    color: Colors.blueAccent,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Modo Offline Activo · Resiliencia Criptográfica',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12.5,
                                            color: Colors.blueAccent,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Tu llave QR local está firmada y sigue siendo 100% válida para el escáner del tótem y la puerta.',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: AppTheme.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          if (isAlertActive && qr != null) ...[
                            Container(
                              padding: const EdgeInsets.all(14),
                              margin: const EdgeInsets.only(bottom: 14),
                              decoration: BoxDecoration(
                                color: AppTheme.warning.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color:
                                      AppTheme.warning.withValues(alpha: 0.45),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.timer_outlined,
                                        color: AppTheme.warning,
                                        size: 19,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Quedan menos de 15 min de estadía',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                            color: AppTheme.warning,
                                            fontSize: 13.5,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '¿Deseas quedarte más tiempo? Extiende con un toque o sal con tu vehículo (+15 min de gracia en barrera).',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            minimumSize: const Size(0, 40),
                                          ),
                                          onPressed: () =>
                                              _openExtendFlow(quickHours: 1),
                                          child: const Text('+1 Hora'),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: OutlinedButton(
                                          style: OutlinedButton.styleFrom(
                                            minimumSize: const Size(0, 40),
                                          ),
                                          onPressed: () =>
                                              _openExtendFlow(quickHours: 2),
                                          child: const Text('+2 Horas'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],

                          // Tarjeta Principal de Pase QR
                          Container(
                            decoration: BoxDecoration(
                              color: _faacTotemHighContrast
                                  ? Colors.white
                                  : AppTheme.card,
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(
                                color: _faacTotemHighContrast
                                    ? AppTheme.cyan
                                    : AppTheme.border,
                                width: _faacTotemHighContrast ? 2 : 1,
                              ),
                            ),
                            padding: const EdgeInsets.all(22),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'SUITE ${qr!.roomName}',
                                          style: TextStyle(
                                            fontSize: 22,
                                            fontWeight: FontWeight.w900,
                                            color: _faacTotemHighContrast
                                                ? Colors.black
                                                : AppTheme.textPrimary,
                                          ),
                                        ),
                                        Text(
                                          qr.hotelName,
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            color: _faacTotemHighContrast
                                                ? Colors.black87
                                                : AppTheme.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 11,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _faacTotemHighContrast
                                            ? const Color(0xFF1E2226)
                                            : AppTheme.surface,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        '⏱ ${_formatCountdown(qr.validUntil)}',
                                        style: TextStyle(
                                          fontFeatures: const [
                                            FontFeature.tabularFigures(),
                                          ],
                                          fontWeight: FontWeight.w800,
                                          fontSize: 13.5,
                                          color: _faacTotemHighContrast
                                              ? Colors.white
                                              : AppTheme.accent,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 18),
                                if (pngBytes != null)
                                  Container(
                                    padding: EdgeInsets.all(
                                      _faacTotemHighContrast ? 16 : 12,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: Colors.black
                                            .withValues(alpha: 0.08),
                                      ),
                                    ),
                                    child: Image.memory(
                                      pngBytes,
                                      width: _faacTotemHighContrast ? 260 : 224,
                                      height:
                                          _faacTotemHighContrast ? 260 : 224,
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                const SizedBox(height: 14),
                                Text(
                                  _faacTotemHighContrast
                                      ? '☀️ Alto brillo activo · Acerca el teléfono al lector de la barrera'
                                      : 'Válido en Barrera Vehicular y Puerta hasta ${_formatDateTime(qr.validUntil)}',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: _faacTotemHighContrast
                                        ? Colors.black87
                                        : AppTheme.accent,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                SwitchListTile.adaptive(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  activeThumbColor: AppTheme.cyan,
                                  value: _faacTotemHighContrast,
                                  onChanged: (v) => setState(
                                    () => _faacTotemHighContrast = v,
                                  ),
                                  title: Text(
                                    'Modo Lector Exterior (Alto Contraste)',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: _faacTotemHighContrast
                                          ? Colors.black
                                          : AppTheme.textPrimary,
                                    ),
                                  ),
                                  subtitle: Text(
                                    'Útil bajo luz del sol frente a la barrera vehicular',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: _faacTotemHighContrast
                                          ? Colors.black54
                                          : AppTheme.textSecondary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          if (_hardwareFeedback != null) ...[
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: AppTheme.cyan.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: AppTheme.cyan.withValues(alpha: 0.35),
                                ),
                              ),
                              child: Text(
                                _hardwareFeedback!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],

                          // Control Rápido de Barreras Vehiculares
                          const SizedBox(height: 16),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(18),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.directions_car_filled_rounded,
                                        color: AppTheme.cyan,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              'Acceso Vehicular Rápido',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w800,
                                                fontSize: 15.5,
                                              ),
                                            ),
                                            Text(
                                              'Abre la barrera desde tu teléfono al llegar o salir',
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
                                  const SizedBox(height: 14),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: ElevatedButton.icon(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: AppTheme.cyan,
                                            foregroundColor: Colors.white,
                                            minimumSize: const Size(0, 44),
                                          ),
                                          onPressed: _busyAction
                                              ? null
                                              : () =>
                                                  _triggerRemoteFaac('ENTRY'),
                                          icon: const Icon(
                                            Icons.login_rounded,
                                            size: 18,
                                          ),
                                          label: const Text('Abrir Entrada'),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          style: OutlinedButton.styleFrom(
                                            minimumSize: const Size(0, 44),
                                          ),
                                          onPressed: _busyAction
                                              ? null
                                              : () =>
                                                  _triggerRemoteFaac('EXIT'),
                                          icon: Icon(
                                            Icons.logout_rounded,
                                            size: 18,
                                            color: AppTheme.cyan,
                                          ),
                                          label: const Text('Abrir Salida'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // Room Service por Pasaplatos
                          const SizedBox(height: 14),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(18),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.room_service_outlined,
                                            color: AppTheme.primary,
                                          ),
                                          const SizedBox(width: 8),
                                          const Text(
                                            'Pedidos a la Habitación',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 15.5,
                                            ),
                                          ),
                                        ],
                                      ),
                                      TextButton.icon(
                                        onPressed: _openRoomServiceSheet,
                                        icon: const Icon(
                                          Icons.add_shopping_cart_rounded,
                                          size: 17,
                                        ),
                                        label: const Text('Pedir'),
                                      ),
                                    ],
                                  ),
                                  Text(
                                    'Solicita bebidas o snacks con Pago Móvil y recíbelos por el pasaplatos.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                  if (_orders.isNotEmpty) ...[
                                    const Divider(height: 20),
                                    for (final ord in _orders)
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 8),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Expanded(
                                              child: Text(
                                                ord.items
                                                    .map(
                                                      (i) =>
                                                          '${i['qty']}x ${i['name']}',
                                                    )
                                                    .join(', '),
                                                style: const TextStyle(
                                                  fontSize: 12.5,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 9,
                                                vertical: 4,
                                              ),
                                              decoration: BoxDecoration(
                                                color: (ord.isDelivered
                                                        ? AppTheme.accent
                                                        : ord.isPaid
                                                            ? AppTheme.gold
                                                            : AppTheme.warning)
                                                    .withValues(alpha: 0.15),
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              child: Text(
                                                ord.isDelivered
                                                    ? '🛎️ En Pasaplatos'
                                                    : ord.isPaid
                                                        ? '👨‍🍳 Preparando'
                                                        : '⏳ Por pagar',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700,
                                                  color: ord.isDelivered
                                                      ? AppTheme.accent
                                                      : ord.isPaid
                                                          ? AppTheme.gold
                                                          : AppTheme.warning,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: () => _openExtendFlow(),
                            icon: const Icon(Icons.more_time_rounded),
                            label: const Text('Extender Tiempo de Estadía'),
                          ),
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.danger,
                            ),
                            onPressed: _checkout,
                            icon: const Icon(
                              Icons.exit_to_app_rounded,
                              size: 18,
                            ),
                            label: const Text('Finalizar Estadía (Check-out)'),
                          ),

                          const SizedBox(height: 14),
                          // Herramientas de prueba colapsadas para mantener una UI limpia
                          Card(
                            child: ExpansionTile(
                              shape: const Border(),
                              leading: Icon(
                                Icons.science_outlined,
                                size: 19,
                                color: AppTheme.textSecondary,
                              ),
                              title: Text(
                                'Opciones de Prueba y Simulación',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                              childrenPadding: const EdgeInsets.fromLTRB(
                                16,
                                0,
                                16,
                                14,
                              ),
                              children: [
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        minimumSize: const Size(140, 38),
                                      ),
                                      onPressed: _busyAction
                                          ? null
                                          : () => _simulateScanOnDevice(
                                                qr.faacEntryDevice,
                                                'Tótem FAAC',
                                              ),
                                      icon: const Icon(
                                        Icons.qr_code_scanner_rounded,
                                        size: 16,
                                      ),
                                      label: const Text('Simular Lector FAAC'),
                                    ),
                                    OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        minimumSize: const Size(140, 38),
                                      ),
                                      onPressed: _busyAction
                                          ? null
                                          : () => _simulateScanOnDevice(
                                                'lock-room-${qr.roomName}',
                                                'Puerta Suite',
                                              ),
                                      icon: const Icon(
                                        Icons.sensor_door_outlined,
                                        size: 16,
                                      ),
                                      label: const Text('Simular Puerta Suite'),
                                    ),
                                    OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        minimumSize: const Size(140, 38),
                                      ),
                                      onPressed: () => setState(
                                        () => _simulateLowTimeAlert =
                                            !_simulateLowTimeAlert,
                                      ),
                                      icon: const Icon(
                                        Icons.notifications_active_outlined,
                                        size: 16,
                                      ),
                                      label: const Text('Probar Alerta ≤15m'),
                                    ),
                                    OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        minimumSize: const Size(140, 38),
                                      ),
                                      onPressed: () async {
                                        await Clipboard.setData(
                                          ClipboardData(text: qr.rawToken),
                                        );
                                        if (!context.mounted) return;
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Token QR copiado al portapapeles.',
                                            ),
                                          ),
                                        );
                                      },
                                      icon: const Icon(
                                        Icons.copy_rounded,
                                        size: 16,
                                      ),
                                      label: const Text('Copiar Token QR'),
                                    ),
                                  ],
                                ),
                              ],
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
