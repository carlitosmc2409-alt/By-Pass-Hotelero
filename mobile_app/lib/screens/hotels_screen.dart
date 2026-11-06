import 'package:flutter/material.dart';
import '../core/api_client.dart';
import '../core/theme.dart';
import '../models/models.dart';
import 'booking_payment_screen.dart';
import 'qr_stay_screen.dart';

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
  List<GuestReservationSummary> _myReservations = const [];
  List<BankOption> _banks = const [
    BankOption(code: '0102', name: 'Banco de Venezuela'),
    BankOption(code: '0134', name: 'Banesco'),
    BankOption(code: '0105', name: 'Mercantil'),
    BankOption(code: '0108', name: 'Provincial'),
    BankOption(code: '0172', name: 'Bancamiga'),
    BankOption(code: '0191', name: 'BNC'),
  ];

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
      if (mounted) setState(() => _error = e.toString());
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
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
                        'Estos datos cifrados permiten que el sistema reconozca tus pagos al instante sin que escribas referencias.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<String>(
                        value: selectedBank,
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

  String _formatShortTime(DateTime dt) {
    final local = dt.toLocal();
    final dd = local.day.toString().padLeft(2, '0');
    final mo = local.month.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$dd/$mo $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final activeStay = _myReservations.where((r) => r.isActive).firstOrNull;
    final pendingStay =
        _myReservations.where((r) => r.isAwaitingPayment).firstOrNull;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('StayPass QR'),
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
          bottom: TabBar(
            indicatorColor: AppTheme.accent,
            tabs: [
              const Tab(
                icon: Icon(Icons.meeting_room_outlined, size: 19),
                text: 'Habitaciones',
              ),
              Tab(
                icon: Badge(
                  isLabelVisible: activeStay != null || pendingStay != null,
                  child: const Icon(Icons.qr_code_2_rounded, size: 19),
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
                      _buildMyStaysTab(),
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

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (activeStay != null) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppTheme.accent.withValues(alpha: 0.45),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.vpn_key_rounded, color: AppTheme.accent),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Estadía Activa · Habitación ${activeStay.room.name} (${activeStay.hotel.name})',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Salida prevista: ${_formatShortTime(activeStay.checkOut)}',
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.accent,
                          foregroundColor: Colors.black,
                          minimumSize: const Size(140, 40),
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
                        label: const Text(
                          'Abrir mi Llave QR',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      OutlinedButton.icon(
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
                        label: const Text('+ Extender Horas'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
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
                      ? 'Extensión pendiente de pago · Hab. ${pendingStay.room.name}'
                      : 'Reserva pendiente de pago · Hab. ${pendingStay.room.name}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  'Bs. ${pendingStay.payment?['amountVes'] ?? pendingStay.totalAmount} · Toca para continuar',
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
            const SizedBox(height: 12),
          ],
          if (paymentProfile != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    const Icon(
                      Icons.verified_user_rounded,
                      color: AppTheme.accent,
                      size: 26,
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
                    IconButton(
                      tooltip: 'Editar cuenta frecuente',
                      onPressed: _openEditPaymentProfileDialog,
                      icon: const Icon(Icons.edit_outlined, size: 20),
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

  Widget _buildMyStaysTab() {
    if (_myReservations.isEmpty) {
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
        itemCount: _myReservations.length,
        itemBuilder: (context, idx) {
          final r = _myReservations[idx];
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
                            : AppTheme.primary)
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
                          : AppTheme.primary,
                ),
              ),
              title: Text(
                '${r.hotel.name} · Habitación ${r.room.name}',
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
                        minimumSize: const Size(90, 36),
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
                      child: const Text('Ver QR'),
                    )
                  : r.isAwaitingPayment
                      ? OutlinedButton(
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
