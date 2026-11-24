import 'dart:async';
import 'package:flutter/material.dart';
import '../core/api_client.dart';
import '../core/theme.dart';

class CleaningDashboardScreen extends StatefulWidget {
  final ApiClient api;
  final VoidCallback onLogout;

  const CleaningDashboardScreen({
    super.key,
    required this.api,
    required this.onLogout,
  });

  @override
  State<CleaningDashboardScreen> createState() => _CleaningDashboardScreenState();
}

class _CleaningDashboardScreenState extends State<CleaningDashboardScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _boardData;
  Timer? _refreshTimer;
  StreamSubscription<Map<String, dynamic>>? _sseSub;
  String _selectedFilter = 'ALL'; // 'ALL', 'CLEANING', 'AVAILABLE', 'MAINTENANCE', 'OCCUPIED'
  String? _updatingRoomId;

  @override
  void initState() {
    super.initState();
    _loadBoard();
    _startRealtimeStream();
    // Auto refresco periódico ultra rápido (cada 3s) como respaldo en vivo
    _refreshTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) _loadBoard(silent: true);
    });
  }

  void _startRealtimeStream() {
    _sseSub?.cancel();
    _sseSub = widget.api.connectRealtimeEvents().listen((evt) {
      if (!mounted) return;
      final type = evt['type']?.toString();
      if (type == 'ROOM_STATUS_CHANGED' ||
          type == 'ROOM_SERVICE_ORDER' ||
          type == 'ROOM_SERVICE_DELIVERED') {
        final payload = evt['payload'] as Map<String, dynamic>? ?? {};
        final roomId = payload['roomId']?.toString();
        final newStatus = payload['status']?.toString();
        final roomName = payload['roomName']?.toString();
        final updatedByRole = payload['updatedByRole']?.toString();

        // 1. Reflejo optimista instantáneo en memoria para cero latencia
        if (roomId != null && newStatus != null && _boardData != null) {
          final rooms = (_boardData!['rooms'] as List<dynamic>?)?.cast<Map<String, dynamic>>();
          if (rooms != null) {
            for (final r in rooms) {
              if (r['id'].toString() == roomId) {
                setState(() {
                  r['status'] = newStatus;
                });
                break;
              }
            }
          }
        }

        // 2. Sincronización completa con el backend
        _loadBoard(silent: true);

        // 3. Notificación informativa discreta si la suite fue modificada por recepción o propietario
        if (updatedByRole != null && updatedByRole != 'CLEANING' && roomName != null && newStatus != null) {
          _showSnack('🔔 Suite $roomName: Estado actualizado a "${_getStatusLabel(newStatus)}" por $updatedByRole.');
        }
      }
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _sseSub?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadBoard({bool silent = false}) async {
    final hotelId = widget.api.currentHotelId;
    if (hotelId == null) {
      if (!silent) {
        setState(() {
          _loading = false;
          _error = 'No se encontró el hotel asignado a esta cuenta.';
        });
      }
      return;
    }

    if (!silent) setState(() => _loading = true);

    try {
      final data = await widget.api.fetchCleaningBoard(hotelId);
      if (mounted) {
        setState(() {
          _boardData = data;
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && !silent) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.redAccent : Colors.teal[800],
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _setRoomStatus(Map<String, dynamic> room, String newStatus) async {
    final roomId = room['id'].toString();
    final roomName = room['name'] ?? room['number'] ?? 'Habitación';
    final label = _getStatusLabel(newStatus);

    setState(() => _updatingRoomId = roomId);

    try {
      await widget.api.updateRoomStatus(roomId: roomId, status: newStatus);
      _showSnack('Suite $roomName: Estado cambiado a "$label". El sistema ya fue notificado.');
      await _loadBoard(silent: true);
    } catch (e) {
      _showSnack('Error al actualizar estado: $e', isError: true);
    } finally {
      if (mounted) setState(() => _updatingRoomId = null);
    }
  }

  String _getStatusLabel(String? status) {
    switch (status) {
      case 'AVAILABLE':
        return 'Lista para Reservar';
      case 'CLEANING':
        return 'En Limpieza / Aseo';
      case 'MAINTENANCE':
        return 'Requiere Mantenimiento';
      case 'OCCUPIED':
        return 'Ocupada por Huésped';
      default:
        return status ?? 'Desconocido';
    }
  }

  Future<void> _handleDeliverOrder(Map<String, dynamic> order) async {
    final orderId = order['id'].toString();
    try {
      await widget.api.deliverRoomServiceOrder(orderId);
      _showSnack('Entrega de room service completada en el pasaplatos.');
      _loadBoard(silent: true);
    } catch (e) {
      _showSnack('Error al entregar pedido: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hotelName = widget.api.currentHotelName ?? 'Hotel';
    final staffName = widget.api.staffName ?? 'Camarería';

    final allRooms = ((_boardData?['rooms'] as List<dynamic>?) ?? [])
        .cast<Map<String, dynamic>>();

    final dirtyRooms = allRooms.isNotEmpty
        ? allRooms.where((r) => r['status'] == 'CLEANING').toList()
        : ((_boardData?['dirtyRooms'] as List<dynamic>?) ?? [])
            .cast<Map<String, dynamic>>();

    final availableRooms = allRooms.isNotEmpty
        ? allRooms.where((r) => r['status'] == 'AVAILABLE').toList()
        : ((_boardData?['availableRooms'] as List<dynamic>?) ?? [])
            .cast<Map<String, dynamic>>();

    final maintenanceRooms = allRooms.isNotEmpty
        ? allRooms.where((r) => r['status'] == 'MAINTENANCE').toList()
        : ((_boardData?['maintenanceRooms'] as List<dynamic>?) ?? [])
            .cast<Map<String, dynamic>>();

    final occupiedRooms = allRooms.isNotEmpty
        ? allRooms.where((r) => r['status'] == 'OCCUPIED').toList()
        : ((_boardData?['occupiedRooms'] as List<dynamic>?) ?? [])
            .cast<Map<String, dynamic>>();

    final expiringSoon = allRooms.isNotEmpty
        ? allRooms.where((r) => r['expiringSoon'] == true).toList()
        : ((_boardData?['expiringSoon'] as List<dynamic>?) ?? [])
            .cast<Map<String, dynamic>>();

    final pendingDeliveries =
        ((_boardData?['pendingDeliveries'] as List<dynamic>?) ?? [])
            .cast<Map<String, dynamic>>();

    // Filtrado activo de habitaciones
    final List<Map<String, dynamic>> displayedRooms;
    switch (_selectedFilter) {
      case 'CLEANING':
        displayedRooms = dirtyRooms;
        break;
      case 'AVAILABLE':
        displayedRooms = availableRooms;
        break;
      case 'MAINTENANCE':
        displayedRooms = maintenanceRooms;
        break;
      case 'OCCUPIED':
        displayedRooms = occupiedRooms;
        break;
      case 'ALL':
      default:
        displayedRooms = allRooms;
        break;
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.cleaning_services_rounded, size: 20, color: Colors.amberAccent),
                const SizedBox(width: 8),
                Text(
                  hotelName,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            Text(
              'Panel Operativo de Limpieza y Habitaciones · $staffName',
              style: TextStyle(
                fontSize: 11.5,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Cambiar tema',
            onPressed: AppTheme.toggleTheme,
            icon: Icon(
              isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
            ),
          ),
          IconButton(
            tooltip: 'Actualizar',
            onPressed: () => _loadBoard(),
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: 'Cerrar sesión',
            onPressed: widget.onLogout,
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: _loading && _boardData == null
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _boardData == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline_rounded, size: 48, color: Colors.redAccent),
                        const SizedBox(height: 12),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: () => _loadBoard(),
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => _loadBoard(silent: true),
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // Banner instructivo superior
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E2838) : const Color(0xFFE8F4FD),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Colors.blueAccent.withAlpha(60),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline_rounded, color: Colors.blueAccent, size: 22),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '💡 Notifica al sistema: pulsa "Estoy Limpiando" al iniciar el aseo para bloquear reservas temporales, y "Habitación Lista" al terminar para habilitarla inmediatamente a los clientes.',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: isDark ? Colors.white70 : Colors.blueGrey[800],
                                  height: 1.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Resumen de estado de limpieza (Tappable para filtrar)
                      Row(
                        children: [
                          Expanded(
                            child: _buildMetricTile(
                              icon: Icons.cleaning_services_rounded,
                              color: Colors.amber[800]!,
                              label: 'Por Limpiar',
                              value: '${dirtyRooms.length}',
                              isSelected: _selectedFilter == 'CLEANING',
                              onTap: () => setState(() => _selectedFilter = _selectedFilter == 'CLEANING' ? 'ALL' : 'CLEANING'),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: _buildMetricTile(
                              icon: Icons.check_circle_outline_rounded,
                              color: Colors.green,
                              label: 'Listas',
                              value: '${availableRooms.length}',
                              isSelected: _selectedFilter == 'AVAILABLE',
                              onTap: () => setState(() => _selectedFilter = _selectedFilter == 'AVAILABLE' ? 'ALL' : 'AVAILABLE'),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: _buildMetricTile(
                              icon: Icons.build_rounded,
                              color: Colors.blueGrey,
                              label: 'Mantenimiento',
                              value: '${maintenanceRooms.length}',
                              isSelected: _selectedFilter == 'MAINTENANCE',
                              onTap: () => setState(() => _selectedFilter = _selectedFilter == 'MAINTENANCE' ? 'ALL' : 'MAINTENANCE'),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: _buildMetricTile(
                              icon: Icons.door_sliding_outlined,
                              color: Colors.indigoAccent,
                              label: 'Ocupadas',
                              value: '${occupiedRooms.length}',
                              isSelected: _selectedFilter == 'OCCUPIED',
                              onTap: () => setState(() => _selectedFilter = _selectedFilter == 'OCCUPIED' ? 'ALL' : 'OCCUPIED'),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: _buildMetricTile(
                              icon: Icons.timer_outlined,
                              color: Colors.orange,
                              label: 'Salidas <15m',
                              value: '${expiringSoon.length}',
                              isSelected: false,
                              onTap: () {},
                            ),
                          ),
                        ],
                      ),

                      // Entregas de pasaplatos
                      if (pendingDeliveries.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            const Icon(Icons.flatware_rounded, color: Colors.indigoAccent, size: 20),
                            const SizedBox(width: 8),
                            const Text(
                              'Entregas Pendientes en Pasaplatos',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.indigoAccent.withAlpha(40),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '${pendingDeliveries.length}',
                                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigoAccent),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        for (final ord in pendingDeliveries)
                          Card(
                            elevation: 2,
                            margin: const EdgeInsets.only(bottom: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: BorderSide(color: Colors.indigoAccent.withAlpha(100)),
                            ),
                            child: ListTile(
                              leading: const CircleAvatar(
                                backgroundColor: Colors.indigoAccent,
                                child: Icon(Icons.room_service_rounded, color: Colors.white),
                              ),
                              title: Text(
                                '${ord['roomName'] ?? 'Suite'} · Orden #${ord['id'].toString().substring(0, 6)}',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              subtitle: Text(
                                'Dejar en la compuerta pasaplatos de la suite.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark ? Colors.white70 : Colors.black54,
                                ),
                              ),
                              trailing: ElevatedButton.icon(
                                onPressed: () => _handleDeliverOrder(ord),
                                icon: const Icon(Icons.check, size: 16),
                                label: const Text('Entregado'),
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo),
                              ),
                            ),
                          ),
                      ],

                      // Próximas salidas ≤ 15 min
                      if (expiringSoon.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            const Icon(Icons.notification_important_rounded, color: Colors.orange, size: 20),
                            const SizedBox(width: 8),
                            const Text(
                              'Próximas Salidas (≤ 15 Minutos)',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                            ),
                            const Spacer(),
                            Text(
                              'Atenta para aseo',
                              style: TextStyle(fontSize: 12, color: Colors.orange[800], fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        for (final exp in expiringSoon)
                          Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Colors.orange.withAlpha(40),
                                child: const Icon(Icons.hourglass_top_rounded, color: Colors.orange),
                              ),
                              title: Text(
                                '${exp['name'] ?? 'Suite'} (${exp['roomType']?['name'] ?? 'Estándar'})',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              subtitle: const Text(
                                'Huésped finalizando estadía. Se pondrá en limpieza automáticamente al hacer checkout.',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          ),
                      ],

                      // Barra de filtros de habitaciones
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          const Icon(Icons.meeting_room_rounded, size: 20, color: Colors.amber),
                          const SizedBox(width: 8),
                          const Text(
                            'Control Operativo de Suites',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          const Spacer(),
                          Text(
                            '${displayedRooms.length} de ${allRooms.length}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white60 : Colors.black54,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _buildFilterChip('ALL', 'Todas (${allRooms.length})'),
                            const SizedBox(width: 8),
                            _buildFilterChip('CLEANING', '🧹 En Limpieza (${dirtyRooms.length})', color: Colors.amber[800]),
                            const SizedBox(width: 8),
                            _buildFilterChip('AVAILABLE', '✅ Listas para Reservar (${availableRooms.length})', color: Colors.green),
                            const SizedBox(width: 8),
                            _buildFilterChip('MAINTENANCE', '🛠️ Mantenimiento (${maintenanceRooms.length})', color: Colors.blueGrey),
                            const SizedBox(width: 8),
                            _buildFilterChip('OCCUPIED', '🔒 Ocupadas (${occupiedRooms.length})', color: Colors.indigoAccent),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Lista de habitaciones
                      if (displayedRooms.isEmpty)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(28),
                            child: Column(
                              children: [
                                Icon(
                                  _selectedFilter == 'CLEANING'
                                      ? Icons.sentiment_very_satisfied_rounded
                                      : Icons.info_outline_rounded,
                                  size: 48,
                                  color: Colors.green[400],
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  _selectedFilter == 'CLEANING'
                                      ? '¡Excelente trabajo! No hay habitaciones pendientes de limpieza en este momento.'
                                      : 'No hay habitaciones con el filtro seleccionado.',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                ),
                                if (_selectedFilter != 'ALL') ...[
                                  const SizedBox(height: 10),
                                  TextButton(
                                    onPressed: () => setState(() => _selectedFilter = 'ALL'),
                                    child: const Text('Ver todas las habitaciones'),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        )
                      else
                        for (final r in displayedRooms)
                          _buildRoomCard(r, isDark),

                      const SizedBox(height: 30),
                    ],
                  ),
                ),
    );
  }

  Widget _buildFilterChip(String filterKey, String label, {Color? color}) {
    final isSelected = _selectedFilter == filterKey;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? Colors.white : null,
        ),
      ),
      selected: isSelected,
      selectedColor: color ?? Theme.of(context).colorScheme.primary,
      onSelected: (_) => setState(() => _selectedFilter = filterKey),
    );
  }

  Widget _buildRoomCard(Map<String, dynamic> room, bool isDark) {
    final status = room['status'] as String? ?? 'UNKNOWN';
    final roomId = room['id'].toString();
    final roomName = room['name'] ?? room['number'] ?? 'Suite';
    final typeName = room['roomType']?['name'] ?? room['type'] ?? 'Estándar';
    final floor = room['floorNumber'] != null ? 'Piso ${room['floorNumber']}' : null;
    final isUpdating = _updatingRoomId == roomId;

    Color statusColor;
    IconData statusIcon;
    String statusTitle;
    String statusExplanation;

    switch (status) {
      case 'CLEANING':
        statusColor = Colors.amber[800]!;
        statusIcon = Icons.cleaning_services_rounded;
        statusTitle = 'EN LIMPIEZA / ASEO PENDIENTE';
        statusExplanation = 'Habitación bloqueada temporalmente en el sistema. Al terminar el aseo, pulsa "Habitación Lista" para que los clientes puedan reservarla.';
        break;
      case 'AVAILABLE':
        statusColor = Colors.green[700]!;
        statusIcon = Icons.check_circle_rounded;
        statusTitle = 'LISTA Y DISPONIBLE PARA RESERVAR';
        statusExplanation = 'Habitación impecable y abierta a reservaciones. Si vas a asearla o desinfectarla, pulsa "Estoy Limpiando" para reservarla para aseo.';
        break;
      case 'MAINTENANCE':
        statusColor = Colors.blueGrey[600]!;
        statusIcon = Icons.build_circle_rounded;
        statusTitle = 'BLOQUEADA POR MANTENIMIENTO';
        statusExplanation = 'Avería o reparación en curso. Cuando la suite esté arreglada y aseada, pulsa "Habitación Lista" para reactivarla.';
        break;
      case 'OCCUPIED':
        statusColor = Colors.indigo;
        statusIcon = Icons.door_front_door_rounded;
        statusTitle = 'OCUPADA POR HUÉSPED';
        statusExplanation = 'Huésped alojado en la habitación. Espera a su checkout para que el sistema la marque automáticamente como pendiente de aseo.';
        break;
      default:
        statusColor = Colors.grey;
        statusIcon = Icons.help_outline_rounded;
        statusTitle = status;
        statusExplanation = 'Estado actual de la suite.';
    }

    return Card(
      elevation: status == 'CLEANING' ? 3 : 1,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: statusColor.withAlpha(status == 'CLEANING' ? 180 : 80),
          width: status == 'CLEANING' ? 1.8 : 1.2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cabecera de la habitación
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: statusColor.withAlpha(35),
                  child: Icon(statusIcon, color: statusColor, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            roomName,
                            style: const TextStyle(
                              fontSize: 16.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (floor != null) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: isDark ? Colors.white10 : Colors.black12,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                floor,
                                style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ],
                      ),
                      Text(
                        'Tipo: $typeName',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
                // Badge de estado actual
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withAlpha(30),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: statusColor.withAlpha(90)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, size: 13, color: statusColor),
                      const SizedBox(width: 5),
                      Text(
                        statusTitle,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: statusColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),
            Text(
              statusExplanation,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white70 : Colors.black87,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 12),

            // Botones de acción táctiles e intuitivos
            if (isUpdating)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                      SizedBox(width: 10),
                      Text('Notificando al sistema...', style: TextStyle(fontSize: 12.5, fontStyle: FontStyle.italic)),
                    ],
                  ),
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  // Botón 1: "Estoy Limpiando"
                  if (status != 'CLEANING' && status != 'OCCUPIED')
                    ElevatedButton.icon(
                      onPressed: () => _setRoomStatus(room, 'CLEANING'),
                      icon: const Icon(Icons.cleaning_services_rounded, size: 16),
                      label: const Text('🧹 Estoy Limpiando'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber[800],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      ),
                    ),

                  // Botón 2: "Habitación Lista (Para Reservar)"
                  if (status != 'AVAILABLE' && status != 'OCCUPIED')
                    ElevatedButton.icon(
                      onPressed: () => _setRoomStatus(room, 'AVAILABLE'),
                      icon: const Icon(Icons.check_circle_outline_rounded, size: 17),
                      label: const Text('✅ Habitación Lista (Para Reservar)'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green[700],
                        foregroundColor: Colors.white,
                        elevation: status == 'CLEANING' ? 3 : 1,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                    ),

                  // Botón 3: "Requiere Mantenimiento"
                  if (status != 'MAINTENANCE' && status != 'OCCUPIED')
                    OutlinedButton.icon(
                      onPressed: () => _setRoomStatus(room, 'MAINTENANCE'),
                      icon: const Icon(Icons.build_rounded, size: 15),
                      label: const Text('🛠️ Requiere Mantenimiento'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.blueGrey,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                      ),
                    ),

                  // Si está ocupada, mensaje informativo
                  if (status == 'OCCUPIED')
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.indigo.withAlpha(20),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.lock_clock_rounded, size: 14, color: Colors.indigo),
                          SizedBox(width: 6),
                          Text(
                            'Bloqueada por privacidad del huésped hasta su salida.',
                            style: TextStyle(fontSize: 11.5, color: Colors.indigo, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricTile({
    required IconData icon,
    required Color color,
    required String label,
    required String value,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Card(
        elevation: isSelected ? 4 : 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: isSelected ? color : Colors.transparent,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          child: Column(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(height: 3),
              Text(
                value,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
