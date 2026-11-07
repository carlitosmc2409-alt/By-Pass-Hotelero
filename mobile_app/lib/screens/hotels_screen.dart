import 'dart:async';
import 'package:flutter/material.dart';
import '../core/api_client.dart';
import '../core/theme.dart';
import '../models/models.dart';
import 'booking_payment_screen.dart';
import 'qr_stay_screen.dart';
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
    _loadData();
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
          const SnackBar(
            backgroundColor: AppTheme.accent,
            content: Text(
              '🛎️ ¡Tu pedido ya está listo en el pasaplatos de tu habitación!',
              style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
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
        _loadData(silent: true);
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
      } catch (_) {}

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
    } catch (e) {
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
            const Text(
              'Al tocar el ícono de calculadora, toda la app se convierte al instante en una "Calculadora Rápida" real. Escribe tu PIN y pulsa "=" para regresar.',
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
                    SnackBar(content: Text('PIN de camuflaje actualizado ($next).')),
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
                      const Text(
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
                    } catch (e) {
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
    _loadData();
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
              const Icon(Icons.qr_code_2_rounded, color: AppTheme.gold, size: 22),
              const SizedBox(width: 8),
              const Text('StayPass QR'),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: (_sseLive ? AppTheme.accent : AppTheme.textSecondary)
                      .withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _sseLive ? '● EN VIVO' : '● SYNC',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: _sseLive ? AppTheme.accent : AppTheme.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: _privacyMask
                  ? 'Mostrar nombres reales'
                  : 'Ocultar nombres en pantalla',
              onPressed: () => setState(() => _privacyMask = !_privacyMask),
              icon: Icon(
                _privacyMask
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_outlined,
                color: _privacyMask ? AppTheme.gold : AppTheme.textSecondary,
                size: 20,
              ),
            ),
            IconButton(
              tooltip: 'Modo Camuflaje (Calculadora)',
              onPressed: StealthCalculatorScreen.enable,
              onLongPress: _openStealthPinSettings,
              icon: const Icon(
                Icons.calculate_outlined,
                color: AppTheme.gold,
                size: 21,
              ),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded),
              onSelected: (v) {
                if (v == 'refresh') _loadData();
                if (v == 'pin') _openStealthPinSettings();
                if (v == 'payment') _openEditPaymentProfileDialog();
                if (v == 'logout') widget.onLogout();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'pin',
                  child: Text('Configurar PIN de Camuflaje'),
                ),
                PopupMenuItem(
                  value: 'payment',
                  child: Text('Editar Pago Móvil Frecuente'),
                ),
                PopupMenuItem(
                  value: 'refresh',
                  child: Text('Sincronizar ahora'),
                ),
                PopupMenuItem(
                  value: 'logout',
                  child: Text('Cerrar sesión'),
                ),
              ],
            ),
          ],
          bottom: TabBar(
            indicatorColor: AppTheme.gold,
            labelColor: AppTheme.gold,
            unselectedLabelColor: AppTheme.textSecondary,
            tabs: [
              const Tab(
                icon: Icon(Icons.king_bed_outlined, size: 19),
                text: 'Suites & Acceso FAAC',
              ),
              Tab(
                icon: Badge(
                  backgroundColor: AppTheme.accent,
                  isLabelVisible: activeStay != null || pendingStay != null,
                  child: const Icon(Icons.vpn_key_outlined, size: 19),
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
                            style: const TextStyle(color: AppTheme.danger),
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
          if (activeStay != null) ...[
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    (expiringSoon ? AppTheme.warning : AppTheme.accent)
                        .withValues(alpha: 0.18),
                    AppTheme.card,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: (expiringSoon ? AppTheme.warning : AppTheme.accent)
                      .withValues(alpha: 0.5),
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
                            color:
                                expiringSoon ? AppTheme.warning : AppTheme.accent,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            expiringSoon
                                ? '⚠️ VENCIMIENTO PRÓXIMO'
                                : 'ESTADÍA VIP ACTIVA',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 11.5,
                              letterSpacing: 0.7,
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
                          color: Colors.black.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '⏱ ${_formatLiveRemaining(activeStay.checkOut)}',
                          style: TextStyle(
                            fontFamily: 'monospace',
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
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Salida: ${_formatShortTime(activeStay.checkOut)} · Pase Barrera FAAC habilitado (+15m gracia de salida)',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  if (expiringSoon) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.warning.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppTheme.warning.withValues(alpha: 0.45),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Alerta silenciosa ≤15 min: extiende en 1 toque sin llamar a recepción:',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ActionChip(
                            backgroundColor: AppTheme.gold,
                            label: const Text(
                              '+1h',
                              style: TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            onPressed: () => _quickExtendStay(activeStay, 1),
                          ),
                          const SizedBox(width: 6),
                          ActionChip(
                            backgroundColor: AppTheme.gold,
                            label: const Text(
                              '+2h',
                              style: TextStyle(
                                color: Colors.black,
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
                          foregroundColor: Colors.black,
                          minimumSize: const Size(175, 42),
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
                          _loadData();
                        },
                        icon: const Icon(Icons.qr_code_rounded, size: 18),
                        label: const Text('Llave QR & FAAC'),
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(145, 42),
                          side: BorderSide(
                            color: AppTheme.gold.withValues(alpha: 0.45),
                          ),
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
                          _loadData();
                        },
                        icon: const Icon(
                          Icons.room_service_outlined,
                          size: 18,
                          color: AppTheme.gold,
                        ),
                        label: const Text(
                          'Room Service',
                          style: TextStyle(color: AppTheme.gold),
                        ),
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
                          _loadData();
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
                leading: const Icon(
                  Icons.pending_actions_rounded,
                  color: AppTheme.warning,
                ),
                title: Text(
                  pendingStay.isExtension
                      ? 'Extensión pendiente · Hab. ${pendingStay.room.name}'
                      : 'Reserva con tasa bloqueada · Hab. ${pendingStay.room.name}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  'Bs. ${pendingStay.payment?['amountVes'] ?? pendingStay.totalAmount} · Toca para abrir Pago Móvil',
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
                  _loadData();
                },
              ),
            ),
            const SizedBox(height: 14),
          ],
          if (paymentProfile != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.07),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.verified_user_rounded,
                    color: AppTheme.accent,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Billetera Cero-Clics Activa (BDV)',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: AppTheme.accent,
                          ),
                        ),
                        Text(
                          '${paymentProfile.bankName ?? paymentProfile.bankCode} · CI ${paymentProfile.cedulaMasked} · ${paymentProfile.phoneMasked}',
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: _openEditPaymentProfileDialog,
                    child: const Text('Cambiar'),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          for (final hotel in _hotels) ...[
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
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _maskLabel(
                            '${hotel.address} · ${hotel.city}',
                            fallback: 'Ubicación protegida en pantalla',
                          ),
                          style: const TextStyle(
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
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: AppTheme.cyan.withValues(alpha: 0.35),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.directions_car_filled_outlined,
                            size: 14,
                            color: AppTheme.cyan,
                          ),
                          SizedBox(width: 5),
                          Text(
                            'Barrera FAAC QR',
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
            for (final room in hotel.rooms) _buildBoutiqueRoomCard(hotel, room),
          ],
        ],
      ),
    );
  }

  Widget _buildBoutiqueRoomCard(HotelModel hotel, RoomModel room) {
    final tierAccent = AppTheme.roomTierAccent(room.type);
    final isCleaning = room.status == 'CLEANING';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: room.isAvailable
              ? tierAccent.withValues(alpha: 0.28)
              : Colors.white.withValues(alpha: 0.06),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
                        letterSpacing: 1.0,
                        color: tierAccent,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _maskLabel(
                        'Suite ${room.name}',
                        fallback: 'Suite Privada •••',
                      ),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: (room.isAvailable
                            ? AppTheme.accent
                            : isCleaning
                                ? AppTheme.cyan
                                : AppTheme.warning)
                        .withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    room.isAvailable
                        ? 'Disponible Ahora'
                        : isCleaning
                            ? 'Acondicionando'
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
                    _miniTag(Icons.directions_car_outlined, 'Garaje / FAAC'),
                    _miniTag(Icons.room_service_outlined, 'Pasaplatos'),
                    ...room.amenities.map((a) => _miniTag(Icons.star_outline, a)),
                  ],
                ),
                const SizedBox(height: 16),
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
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.gold,
                              ),
                            ),
                            const Text(
                              ' / hora',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          'Amanecida 24h: \$${room.pricePerNight.toStringAsFixed(0)} USD',
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(148, 44),
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
                      icon: const Icon(Icons.qr_code_rounded, size: 17),
                      label: const Text('Reservar'),
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

  Widget _miniTag(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppTheme.textSecondary),
          const SizedBox(width: 4),
          Text(
            text,
            style: const TextStyle(
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
      return const Center(
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
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                ),
              ),
              isThreeLine: true,
              trailing: r.isActive
                  ? ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.accent,
                        foregroundColor: Colors.black,
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
                        _loadData();
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
                            _loadData();
                          },
                          child: const Text('Pagar'),
                        )
                      : null,
            ),
          );
        },
      ),
    );
  }
}
