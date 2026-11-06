import 'package:flutter/material.dart';
import '../core/owner_api.dart';
import '../core/owner_theme.dart';

class OwnerDashboardScreen extends StatefulWidget {
  final OwnerApiClient api;
  final VoidCallback onLogout;

  const OwnerDashboardScreen({
    super.key,
    required this.api,
    required this.onLogout,
  });

  @override
  State<OwnerDashboardScreen> createState() => _OwnerDashboardScreenState();
}

class _OwnerDashboardScreenState extends State<OwnerDashboardScreen> {
  static const Map<String, String> _banks = {
    '0102': '0102 · Banco de Venezuela (Piloto Automático)',
    '0134': '0134 · Banesco',
    '0105': '0105 · Mercantil',
    '0108': '0108 · Provincial',
    '0172': '0172 · Bancamiga',
    '0191': '0191 · BNC',
  };

  List<Map<String, dynamic>> _hotels = [];
  String? _selectedHotelId;
  Map<String, dynamic>? _dashboard;
  bool _loading = true;
  String? _error;
  String _roomFilter = 'ALL';

  // Controladores para pestaña Cuenta Receptora Pago Móvil
  String _selectedBankCode = '0102';
  final _payPhoneCtrl = TextEditingController();
  final _payIdCtrl = TextEditingController();
  final _payHolderCtrl = TextEditingController();
  bool _savingPaymentInfo = false;

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  @override
  void dispose() {
    _payPhoneCtrl.dispose();
    _payIdCtrl.dispose();
    _payHolderCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final hotels = await widget.api.fetchMyHotels();
      if (!mounted) return;
      _hotels = hotels;
      if (hotels.isEmpty) {
        setState(() {
          _dashboard = null;
          _loading = false;
        });
        return;
      }

      _selectedHotelId ??= hotels.first['id'] as String;
      await _refreshDashboard();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _refreshDashboard() async {
    final hotelId = _selectedHotelId;
    if (hotelId == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await widget.api.fetchHotelDashboard(hotelId);
      if (!mounted) return;

      final hotel = (data['hotel'] as Map<String, dynamic>?) ?? {};
      final paymentInfo = (hotel['paymentInfo'] as Map<String, dynamic>?) ?? {};

      final bank = (paymentInfo['bank'] ?? '0102').toString();
      _selectedBankCode = _banks.containsKey(bank) ? bank : '0102';
      _payPhoneCtrl.text = (paymentInfo['phone'] ?? '').toString();
      _payIdCtrl.text = (paymentInfo['idNumber'] ?? '').toString();
      _payHolderCtrl.text =
          (paymentInfo['holderName'] ?? hotel['name'] ?? '').toString();

      setState(() {
        _dashboard = data;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: isError ? OwnerTheme.occupied : OwnerTheme.available,
        content: Text(
          message,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Future<void> _changeRoomStatus(
    Map<String, dynamic> room,
    String newStatus,
  ) async {
    final roomId = room['id'] as String;
    final currentStatus = room['status'] as String? ?? 'AVAILABLE';

    if (currentStatus == 'OCCUPIED' && newStatus != 'OCCUPIED') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: OwnerTheme.card,
          title: const Text('¿Finalizar estadía activa?'),
          content: Text(
            'La habitación "${room['name']}" figura ocupada. Si el huésped ya se retiró, '
            'esto cerrará la reserva activa, invalidará su QR y enviará la habitación a ${_statusLabel(newStatus)}.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Confirmar'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    try {
      await widget.api.updateRoomStatus(roomId, newStatus);
      _showSnack('Habitación actualizada a ${_statusLabel(newStatus)}');
      await _refreshDashboard();
    } catch (e) {
      _showSnack(e.toString(), isError: true);
    }
  }

  Future<void> _openCreateRoomDialog() async {
    final hotelId = _selectedHotelId;
    if (hotelId == null) return;

    final nameCtrl = TextEditingController();
    final hourPriceCtrl = TextEditingController(text: '15');
    final nightPriceCtrl = TextEditingController(text: '45');
    final amenitiesCtrl =
        TextEditingController(text: 'Aire acondicionado, TV, Estacionamiento privado');
    String selectedType = 'STANDARD';

    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: OwnerTheme.card,
              title: const Text('Nueva Habitación'),
              content: SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Nombre o Número (ej: Suite 204)',
                        ),
                      ),
                      const SizedBox(height: 12),
                      InputDecorator(
                        decoration: const InputDecoration(labelText: 'Categoría'),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: selectedType,
                            isExpanded: true,
                            dropdownColor: OwnerTheme.surface,
                            items: const [
                              DropdownMenuItem(value: 'STANDARD', child: Text('Estándar')),
                              DropdownMenuItem(value: 'DELUXE', child: Text('Deluxe')),
                              DropdownMenuItem(value: 'SUITE', child: Text('Suite')),
                              DropdownMenuItem(value: 'PREMIUM', child: Text('Premium / Jacuzzi')),
                            ],
                            onChanged: (v) {
                              if (v != null) {
                                setDialogState(() => selectedType = v);
                              }
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: hourPriceCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(
                                labelText: 'Precio x Hora (USD)',
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: nightPriceCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(
                                labelText: 'Precio Amanecida (USD)',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: amenitiesCtrl,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Comodidades (separadas por coma)',
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
                    final name = nameCtrl.text.trim();
                    final perHour = double.tryParse(hourPriceCtrl.text.trim());
                    final perNight = double.tryParse(nightPriceCtrl.text.trim());
                    if (name.isEmpty || perHour == null || perNight == null) {
                      return;
                    }
                    final amenities = amenitiesCtrl.text
                        .split(',')
                        .map((s) => s.trim())
                        .where((s) => s.isNotEmpty)
                        .toList();
                    try {
                      await widget.api.createRoom(
                        hotelId: hotelId,
                        name: name,
                        type: selectedType,
                        pricePerHour: perHour,
                        pricePerNight: perNight,
                        amenities: amenities,
                      );
                      if (ctx.mounted) Navigator.of(ctx).pop(true);
                    } catch (e) {
                      _showSnack(e.toString(), isError: true);
                    }
                  },
                  child: const Text('Crear Habitación'),
                ),
              ],
            );
          },
        );
      },
    );

    if (created == true) {
      _showSnack('Habitación creada exitosamente');
      await _refreshDashboard();
    }
  }

  Future<void> _savePaymentInfo() async {
    final hotelId = _selectedHotelId;
    if (hotelId == null) return;

    final phone = _payPhoneCtrl.text.trim();
    final idNumber = _payIdCtrl.text.trim();
    final holderName = _payHolderCtrl.text.trim();

    if (phone.length < 10 || idNumber.length < 5) {
      _showSnack('Completa un teléfono y RIF/Cédula válidos.', isError: true);
      return;
    }

    setState(() => _savingPaymentInfo = true);
    try {
      final bankName = (_banks[_selectedBankCode] ?? 'Banco de Venezuela')
          .split('·')
          .last
          .replaceAll('(Piloto Automático)', '')
          .trim();

      await widget.api.updateHotelPaymentInfo(
        hotelId: hotelId,
        bank: _selectedBankCode,
        bankName: bankName,
        phone: phone,
        idNumber: idNumber,
        holderName: holderName.isEmpty ? 'Propietario' : holderName,
      );
      _showSnack('Cuenta receptora Pago Móvil actualizada');
      await _refreshDashboard();
    } catch (e) {
      _showSnack(e.toString(), isError: true);
    } finally {
      if (mounted) {
        setState(() => _savingPaymentInfo = false);
      }
    }
  }

  Future<void> _handleManualPaymentAction(String paymentId, bool confirm) async {
    try {
      if (confirm) {
        await widget.api.confirmPaymentManually(paymentId);
        _showSnack('Pago aprobado manualmente y QR habilitado.');
      } else {
        await widget.api.rejectPaymentManually(paymentId);
        _showSnack('Pago rechazado y reserva cancelada.');
      }
      await _refreshDashboard();
    } catch (e) {
      _showSnack(e.toString(), isError: true);
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'AVAILABLE':
        return OwnerTheme.available;
      case 'OCCUPIED':
        return OwnerTheme.occupied;
      case 'CLEANING':
        return OwnerTheme.cleaning;
      case 'MAINTENANCE':
        return OwnerTheme.maintenance;
      default:
        return OwnerTheme.textSecondary;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'AVAILABLE':
        return 'Disponible';
      case 'OCCUPIED':
        return 'Ocupada';
      case 'CLEANING':
        return 'En Limpieza';
      case 'MAINTENANCE':
        return 'Mantenimiento';
      case 'DISABLED':
        return 'Deshabilitada';
      default:
        return status;
    }
  }

  String _formatShortDateTime(dynamic isoString) {
    if (isoString == null) return 'N/D';
    final dt = DateTime.tryParse(isoString.toString())?.toLocal();
    if (dt == null) return isoString.toString();
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    final dd = dt.day.toString().padLeft(2, '0');
    final mo = dt.month.toString().padLeft(2, '0');
    return '$dd/$mo $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final hotel = (_dashboard?['hotel'] as Map<String, dynamic>?) ?? {};
    final hotelName = (hotel['name'] ?? 'Panel del Propietario').toString();

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              const Icon(Icons.shield_moon_rounded, color: OwnerTheme.primary),
              const SizedBox(width: 10),
              Flexible(
                child: _hotels.length > 1
                    ? DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedHotelId,
                          dropdownColor: OwnerTheme.surface,
                          items: _hotels
                              .map(
                                (h) => DropdownMenuItem<String>(
                                  value: h['id'] as String,
                                  child: Text(
                                    h['name'].toString(),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: OwnerTheme.textPrimary,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (val) {
                            if (val != null && val != _selectedHotelId) {
                              setState(() => _selectedHotelId = val);
                              _refreshDashboard();
                            }
                          },
                        ),
                      )
                    : Text(
                        hotelName,
                        overflow: TextOverflow.ellipsis,
                      ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: OwnerTheme.available.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: OwnerTheme.available.withValues(alpha: 0.4),
                  ),
                ),
                child: const Text(
                  'BDV Auto-Verify',
                  style: TextStyle(
                    color: OwnerTheme.available,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Actualizar en vivo',
              onPressed: _loading ? null : _refreshDashboard,
              icon: const Icon(Icons.refresh_rounded),
            ),
            IconButton(
              tooltip: 'Cerrar sesión',
              onPressed: widget.onLogout,
              icon: const Icon(Icons.logout_rounded),
            ),
            const SizedBox(width: 6),
          ],
          bottom: const TabBar(
            indicatorColor: OwnerTheme.primary,
            labelColor: OwnerTheme.textPrimary,
            unselectedLabelColor: OwnerTheme.textSecondary,
            tabs: [
              Tab(
                icon: Icon(Icons.grid_view_rounded, size: 20),
                text: 'Habitaciones',
              ),
              Tab(
                icon: Icon(Icons.bolt_rounded, size: 20),
                text: 'Pagos y BDV',
              ),
              Tab(
                icon: Icon(Icons.account_balance_rounded, size: 20),
                text: 'Cuenta Receptora',
              ),
            ],
          ),
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _dashboard == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _dashboard == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: OwnerTheme.occupied),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadInitial,
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    if (_hotels.isEmpty) {
      return const Center(
        child: Text('No tienes hoteles registrados aún en esta cuenta.'),
      );
    }

    return TabBarView(
      children: [
        _buildRoomsTab(),
        _buildFinanceTab(),
        _buildPaymentSettingsTab(),
      ],
    );
  }

  Widget _buildRoomsTab() {
    final metrics = (_dashboard?['metrics'] as Map<String, dynamic>?) ?? {};
    final allRooms =
        ((_dashboard?['rooms'] as List<dynamic>?) ?? []).cast<Map<String, dynamic>>();

    final filteredRooms = _roomFilter == 'ALL'
        ? allRooms
        : allRooms.where((r) => r['status'] == _roomFilter).toList();

    final totalRooms = metrics['totalRooms'] ?? 0;
    final occupiedRooms = metrics['occupiedRooms'] ?? 0;
    final availableRooms = metrics['availableRooms'] ?? 0;
    final cleaningRooms = metrics['cleaningRooms'] ?? 0;
    final revTodayUsd = (metrics['revenueTodayUsd'] ?? 0).toString();
    final revTodayVes = (metrics['revenueTodayVes'] ?? 0).toString();
    final approvedToday = metrics['approvedCountToday'] ?? 0;
    final revMonthUsd = (metrics['revenueMonthUsd'] ?? 0).toString();
    final revMonthVes = (metrics['revenueMonthVes'] ?? 0).toString();
    final pendingCount = (metrics['pendingReviewCount'] ?? 0) as int;

    return RefreshIndicator(
      onRefresh: _refreshDashboard,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              _KpiCard(
                title: 'Ocupación Actual',
                value: '$occupiedRooms / $totalRooms',
                subtitle: '$availableRooms libres · $cleaningRooms en limpieza',
                icon: Icons.meeting_room_rounded,
                accent: OwnerTheme.primary,
              ),
              _KpiCard(
                title: 'Ingresos Hoy (Directos)',
                value: '\$$revTodayUsd USD',
                subtitle: 'Bs. $revTodayVes · $approvedToday cobros',
                icon: Icons.trending_up_rounded,
                accent: OwnerTheme.available,
              ),
              _KpiCard(
                title: 'Acumulado del Mes',
                value: '\$$revMonthUsd USD',
                subtitle: 'Bs. $revMonthVes conciliados',
                icon: Icons.calendar_month_rounded,
                accent: OwnerTheme.primary,
              ),
              _KpiCard(
                title: 'Revisión Manual',
                value: '$pendingCount',
                subtitle: pendingCount == 0
                    ? '100% automatizado sin pendientes'
                    : 'Pagos esperando verificación',
                icon: Icons.verified_rounded,
                accent: pendingCount == 0 ? OwnerTheme.available : OwnerTheme.cleaning,
              ),
            ],
          ),
          const SizedBox(height: 22),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildFilterChip('ALL', 'Todas (${allRooms.length})'),
                  _buildFilterChip('AVAILABLE', 'Libres ($availableRooms)'),
                  _buildFilterChip('OCCUPIED', 'Ocupadas ($occupiedRooms)'),
                  _buildFilterChip('CLEANING', 'Limpieza ($cleaningRooms)'),
                  _buildFilterChip('MAINTENANCE', 'Mantenimiento'),
                ],
              ),
              ElevatedButton.icon(
                onPressed: _openCreateRoomDialog,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Nueva Habitación'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (filteredRooms.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(28),
                child: Center(
                  child: Text(
                    'No hay habitaciones en este filtro.',
                    style: TextStyle(color: OwnerTheme.textSecondary),
                  ),
                ),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final maxW = constraints.maxWidth;
                final cols = maxW >= 1050
                    ? 3
                    : maxW >= 680
                        ? 2
                        : 1;
                final spacing = 14.0;
                final cardWidth = (maxW - (cols - 1) * spacing) / cols;

                return Wrap(
                  spacing: spacing,
                  runSpacing: spacing,
                  children: filteredRooms
                      .map(
                        (room) => SizedBox(
                          width: cardWidth,
                          child: _buildRoomCard(room),
                        ),
                      )
                      .toList(),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String value, String label) {
    final selected = _roomFilter == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _roomFilter = value),
      selectedColor: OwnerTheme.primary.withValues(alpha: 0.25),
      labelStyle: TextStyle(
        color: selected ? OwnerTheme.textPrimary : OwnerTheme.textSecondary,
        fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
      ),
    );
  }

  Widget _buildRoomCard(Map<String, dynamic> room) {
    final status = (room['status'] ?? 'AVAILABLE').toString();
    final color = _statusColor(status);
    final activeRes = room['activeReservation'] as Map<String, dynamic>?;
    final amenities =
        ((room['amenities'] as List<dynamic>?) ?? []).map((e) => e.toString()).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    (room['name'] ?? 'Habitación').toString(),
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: color.withValues(alpha: 0.45)),
                  ),
                  child: Text(
                    _statusLabel(status),
                    style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${room['type']} · \$${room['pricePerHour']}/h · \$${room['pricePerNight']}/noche',
              style: const TextStyle(
                color: OwnerTheme.textSecondary,
                fontSize: 13,
              ),
            ),
            if (amenities.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: amenities.take(4).map((a) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: OwnerTheme.surface,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      a,
                      style: const TextStyle(
                        fontSize: 11,
                        color: OwnerTheme.textSecondary,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
            if (activeRes != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: OwnerTheme.occupied.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: OwnerTheme.occupied.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.timer_outlined,
                      size: 16,
                      color: OwnerTheme.occupied,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Salida QR prevista: ${_formatShortDateTime(activeRes['checkOut'])} (${activeRes['durationHours']}h · Huésped anónimo)',
                        style: const TextStyle(
                          fontSize: 12,
                          color: OwnerTheme.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (status != 'AVAILABLE' && status != 'OCCUPIED')
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: OwnerTheme.available,
                      minimumSize: const Size(110, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    onPressed: () => _changeRoomStatus(room, 'AVAILABLE'),
                    icon: const Icon(Icons.check_circle_outline, size: 16),
                    label: const Text('Habilitar'),
                  ),
                if (status == 'AVAILABLE') ...[
                  OutlinedButton.icon(
                    onPressed: () => _changeRoomStatus(room, 'CLEANING'),
                    icon: const Icon(Icons.cleaning_services_outlined, size: 15),
                    label: const Text('Limpieza'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _changeRoomStatus(room, 'MAINTENANCE'),
                    icon: const Icon(Icons.build_outlined, size: 15),
                    label: const Text('Mantenimiento'),
                  ),
                ],
                if (status == 'OCCUPIED')
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: OwnerTheme.cleaning,
                    ),
                    onPressed: () => _changeRoomStatus(room, 'CLEANING'),
                    icon: const Icon(Icons.exit_to_app_rounded, size: 16),
                    label: const Text('Liberar a Limpieza'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFinanceTab() {
    final bankEvents = ((_dashboard?['recentBankEvents'] as List<dynamic>?) ?? [])
        .cast<Map<String, dynamic>>();
    final reservations = ((_dashboard?['recentReservations'] as List<dynamic>?) ?? [])
        .cast<Map<String, dynamic>>();

    return RefreshIndicator(
      onRefresh: _refreshDashboard,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Notificaciones Bancarias Recibidas (Banco de Venezuela)',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(
            'Cada Pago Móvil entrante se coteja automáticamente por monto exacto en Bs. y referencia contra las reservas activas.',
            style: TextStyle(color: OwnerTheme.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 12),
          if (bankEvents.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'Aún no se han recibido eventos bancarios en este hotel.',
                  style: TextStyle(color: OwnerTheme.textSecondary),
                ),
              ),
            )
          else
            ...bankEvents.map((ev) {
              final matched = ev['matchedPaymentId'] != null;
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: (matched ? OwnerTheme.available : OwnerTheme.cleaning)
                        .withValues(alpha: 0.18),
                    child: Icon(
                      matched ? Icons.bolt_rounded : Icons.schedule_rounded,
                      color: matched ? OwnerTheme.available : OwnerTheme.cleaning,
                    ),
                  ),
                  title: Text(
                    'Bs. ${(ev['amountVes'] as num).toStringAsFixed(2)} · Ref ${ev['reference']}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    'Origen: ${ev['source']} · Emisor: ${ev['payerPhone'] ?? 'N/D'} · ${_formatShortDateTime(ev['receivedAt'])}',
                    style: const TextStyle(color: OwnerTheme.textSecondary, fontSize: 12),
                  ),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: (matched ? OwnerTheme.available : OwnerTheme.cleaning)
                          .withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      matched ? 'Conciliado' : 'Sin asignar',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: matched ? OwnerTheme.available : OwnerTheme.cleaning,
                      ),
                    ),
                  ),
                ),
              );
            }),
          const SizedBox(height: 24),
          const Text(
            'Reservas y Cobros Recientes (Identidad Protegida)',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(
            'Por privacidad del huésped no se exhiben nombres ni documentos; todo ingreso va directo a tu cuenta receptora.',
            style: TextStyle(color: OwnerTheme.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 12),
          if (reservations.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'Sin reservas registradas todavía.',
                  style: TextStyle(color: OwnerTheme.textSecondary),
                ),
              ),
            )
          else
            ...reservations.map((res) {
              final room = (res['room'] as Map<String, dynamic>?) ?? {};
              final payment = res['payment'] as Map<String, dynamic>?;
              final payStatus = (payment?['status'] ?? 'NONE').toString();
              final autoVerified = payment?['autoVerified'] == true;
              final needsAction =
                  payStatus == 'PENDING_REVIEW' || payStatus == 'PENDING';

              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              '${room['name'] ?? 'Habitación'} · ${res['durationHours']}h · \$${res['totalAmount']} USD',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          _buildPaymentBadge(payStatus, autoVerified),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Reserva: ${res['status']} · Entrada: ${_formatShortDateTime(res['checkIn'])} · Salida: ${_formatShortDateTime(res['checkOut'])}',
                        style: const TextStyle(
                          color: OwnerTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      if (payment != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Monto Bs: ${payment['amountVes'] ?? 'N/D'} · Ref: ${payment['gatewayRef'] ?? 'Pendiente'} · Vía: ${payment['gateway']}',
                          style: const TextStyle(
                            color: OwnerTheme.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                      if (needsAction && payment != null) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          children: [
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: OwnerTheme.available,
                                minimumSize: const Size(110, 34),
                              ),
                              onPressed: () => _handleManualPaymentAction(
                                payment['id'] as String,
                                true,
                              ),
                              icon: const Icon(Icons.check, size: 16),
                              label: const Text('Aprobar Manual'),
                            ),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: OwnerTheme.occupied,
                              ),
                              onPressed: () => _handleManualPaymentAction(
                                payment['id'] as String,
                                false,
                              ),
                              icon: const Icon(Icons.close, size: 16),
                              label: const Text('Rechazar'),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildPaymentBadge(String payStatus, bool autoVerified) {
    Color color = OwnerTheme.textSecondary;
    String label = payStatus;

    if (payStatus == 'APPROVED') {
      color = OwnerTheme.available;
      label = autoVerified ? 'Auto-verificado BDV' : 'Aprobado Manual';
    } else if (payStatus == 'PENDING_REVIEW' || payStatus == 'PENDING') {
      color = OwnerTheme.cleaning;
      label = payStatus == 'PENDING_REVIEW' ? 'En Revisión' : 'Esperando Pago';
    } else if (payStatus == 'FAILED') {
      color = OwnerTheme.occupied;
      label = 'Rechazado';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildPaymentSettingsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.account_balance_rounded, color: OwnerTheme.primary),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Cuenta Receptora Directa (Pago Móvil)',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Los huéspedes envían el Pago Móvil directamente a estos datos sin pasar por cuentas de terceros. '
                    'Con Banco de Venezuela (0102), la app conciliadora valida la notificación push al instante.',
                    style: TextStyle(
                      color: OwnerTheme.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 20),
                  InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Banco Receptor',
                      prefixIcon: Icon(Icons.account_balance_outlined),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedBankCode,
                        isExpanded: true,
                        dropdownColor: OwnerTheme.surface,
                        items: _banks.entries
                            .map(
                              (e) => DropdownMenuItem<String>(
                                value: e.key,
                                child: Text(e.value),
                              ),
                            )
                            .toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _selectedBankCode = val);
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _payPhoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Teléfono afiliado a Pago Móvil (ej: +584141234567)',
                      prefixIcon: Icon(Icons.phone_android_rounded),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _payIdCtrl,
                    decoration: const InputDecoration(
                      labelText: 'RIF o Cédula del Titular (ej: J-40123456-7 o V-12345678)',
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _payHolderCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nombre o Razón Social del Titular',
                      prefixIcon: Icon(Icons.business_rounded),
                    ),
                  ),
                  const SizedBox(height: 22),
                  ElevatedButton.icon(
                    onPressed: _savingPaymentInfo ? null : _savePaymentInfo,
                    icon: _savingPaymentInfo
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_rounded),
                    label: const Text('Guardar Datos de Cobro'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color accent;

  const _KpiCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 265,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: accent, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: OwnerTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      value,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: OwnerTheme.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
