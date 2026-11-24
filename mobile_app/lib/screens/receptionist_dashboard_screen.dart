import 'dart:async';
import 'package:flutter/material.dart';
import '../core/api_client.dart';
import '../core/theme.dart';

class ReceptionistDashboardScreen extends StatefulWidget {
  final ApiClient api;
  final VoidCallback onLogout;

  const ReceptionistDashboardScreen({
    super.key,
    required this.api,
    required this.onLogout,
  });

  @override
  State<ReceptionistDashboardScreen> createState() =>
      _ReceptionistDashboardScreenState();
}

class _ReceptionistDashboardScreenState
    extends State<ReceptionistDashboardScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _boardData;
  Timer? _refreshTimer;
  StreamSubscription<Map<String, dynamic>>? _sseSub;

  @override
  void initState() {
    super.initState();
    _loadBoard();
    _startRealtimeStream();
    // Auto refresco ultra rápido cada 3 segundos como respaldo en vivo
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
          type == 'PAYMENT_APPROVED' ||
          type == 'NEW_RESERVATION' ||
          type == 'CHECK_IN' ||
          type == 'CHECK_OUT' ||
          type == 'ROOM_SERVICE_ORDER' ||
          type == 'ROOM_SERVICE_DELIVERED' ||
          type == 'FAAC_BARRIER_PULSE') {
        final payload = evt['payload'] as Map<String, dynamic>? ?? {};
        final roomId = payload['roomId']?.toString();
        final newStatus = payload['status']?.toString();
        final roomName = payload['roomName']?.toString();
        final updatedByRole = payload['updatedByRole']?.toString();

        // Actualización optimista inmediata en memoria de la grilla de suites
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

        // Recarga completa en segundo plano
        _loadBoard(silent: true);

        if (type == 'ROOM_STATUS_CHANGED' && updatedByRole != null && updatedByRole != 'RECEPTIONIST' && roomName != null) {
          _showSnack('🔔 Suite $roomName actualizada a "$newStatus" por $updatedByRole.');
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
          _error = 'No se encontró el ID del hotel para esta cuenta.';
        });
      }
      return;
    }

    if (!silent) setState(() => _loading = true);

    try {
      final data = await widget.api.fetchReceptionBoard(hotelId);
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
        backgroundColor: isError ? Colors.redAccent : Colors.teal,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _handleFaacPulse(String direction) async {
    final hotelId = widget.api.currentHotelId;
    if (hotelId == null) return;

    final dirLabel = direction == 'ENTRY' ? 'ENTRADA' : 'SALIDA';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Pulso Barrera FAAC ($dirLabel)'),
        content: Text(
          '¿Desea enviar un pulso de relé manual al automatismo FAAC de $dirLabel? Use esto para permitir el paso de un vehículo si el código QR o el lector tuvo algún fallo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
            child: const Text('Enviar Pulso'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await widget.api.pulseFaacBarrier(hotelId: hotelId, direction: direction);
      _showSnack('Pulso de relé enviado a barrera FAAC ($dirLabel).');
    } catch (e) {
      _showSnack('Error al accionar barrera: $e', isError: true);
    }
  }

  Future<void> _handleEmergencyDoorUnlock(Map<String, dynamic> room) async {
    final hotelId = widget.api.currentHotelId;
    if (hotelId == null) return;

    final roomName = room['name'] ?? room['number'] ?? 'Habitación';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.lock_open_rounded, color: Colors.amber),
            const SizedBox(width: 8),
            Text('Destrabar $roomName'),
          ],
        ),
        content: Text(
          '¿Desea enviar un pulso de apertura inmediata a la cerradura electrónica de $roomName para asistir al huésped?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber[800]),
            child: const Text('Destrabar Cerradura'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await widget.api.testIotRelay(
        hotelId: hotelId,
        direction: 'ENTRY',
        dryRun: false,
      );
      _showSnack('Cerradura de $roomName destrabada con éxito.');
      _loadBoard(silent: true);
    } catch (e) {
      _showSnack('Error al destrabar cerradura: $e', isError: true);
    }
  }

  Future<void> _openManualPaymentDialog({Map<String, dynamic>? preselected}) async {
    final pendingPayments = ((_boardData?['pendingPayments'] as List<dynamic>?) ?? [])
        .cast<Map<String, dynamic>>();

    String? selectedPaymentId = preselected?['id']?.toString() ??
        (pendingPayments.isNotEmpty ? pendingPayments.first['id']?.toString() : null);

    final refCtrl = TextEditingController();
    final reasonCtrl = TextEditingController(text: 'Contingencia BDV / Validación en mostrador');
    final notesCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.payment_rounded, color: Colors.teal),
              SizedBox(width: 8),
              Text('Aprobar Pago en Contingencia'),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Si el Banco de Venezuela u otro medio automático está caído, ingrese la referencia manual verificada por captura de pantalla o comprobante físico para liberar el acceso del huésped de inmediato.',
                    style: TextStyle(fontSize: 12.5),
                  ),
                  const SizedBox(height: 14),
                  if (pendingPayments.isNotEmpty) ...[
                    DropdownButtonFormField<String>(
                      value: selectedPaymentId,
                      decoration: const InputDecoration(labelText: 'Pago / Reserva Pendiente'),
                      items: pendingPayments.map((p) {
                        final res = p['reservation'] as Map<String, dynamic>?;
                        final guest = res?['guest'] as Map<String, dynamic>?;
                        final room = res?['room'] as Map<String, dynamic>?;
                        final amount = p['amountUsd'] ?? p['amountBs'] ?? '0';
                        return DropdownMenuItem<String>(
                          value: p['id'].toString(),
                          child: Text(
                            '${room?['name'] ?? 'Suite'} · ${guest?['fullName'] ?? 'Huésped'} (\$${amount})',
                            style: const TextStyle(fontSize: 13),
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        setDlgState(() => selectedPaymentId = val);
                      },
                    ),
                  ] else ...[
                    TextField(
                      decoration: const InputDecoration(
                        labelText: 'ID del Pago',
                        hintText: 'Ingrese ID de pago si no está en la lista',
                      ),
                      onChanged: (val) => selectedPaymentId = val.trim(),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: refCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Referencia Bancaria / Comprobante (Obligatorio)',
                      prefixIcon: Icon(Icons.receipt_long_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: reasonCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Motivo de Aprobación Manual',
                      prefixIcon: Icon(Icons.info_outline),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notesCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Notas Adicionales (Opcional)',
                      prefixIcon: Icon(Icons.note_alt_outlined),
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
                if (selectedPaymentId == null || selectedPaymentId!.isEmpty) {
                  _showSnack('Seleccione o ingrese un ID de pago.', isError: true);
                  return;
                }
                if (refCtrl.text.trim().isEmpty) {
                  _showSnack('La referencia bancaria es obligatoria.', isError: true);
                  return;
                }

                try {
                  await widget.api.confirmManualPayment(
                    paymentId: selectedPaymentId!,
                    gatewayRef: refCtrl.text.trim(),
                    reason: reasonCtrl.text.trim(),
                    notes: notesCtrl.text.trim().isNotEmpty ? notesCtrl.text.trim() : null,
                  );
                  if (ctx.mounted) Navigator.of(ctx).pop(true);
                } catch (e) {
                  _showSnack('Error al confirmar pago: $e', isError: true);
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
              child: const Text('Confirmar & Liberar QR'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      _showSnack('Pago manual aprobado con éxito. El huésped ya tiene su llave QR habilitada.');
      _loadBoard(silent: true);
    }
  }

  Future<void> _openMaintenanceDialog({Map<String, dynamic>? preselectedRoom}) async {
    final rooms = ((_boardData?['rooms'] as List<dynamic>?) ?? [])
        .cast<Map<String, dynamic>>();

    String? selectedRoomId = preselectedRoom?['id']?.toString() ??
        (rooms.isNotEmpty ? rooms.first['id']?.toString() : null);

    final reasonCtrl = TextEditingController(text: 'Avería / Inspección técnica reportada por recepción');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.build_rounded, color: Colors.orange),
              SizedBox(width: 8),
              Text('Reportar: Requiere Mantenimiento'),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Al marcar una suite con "Requiere Mantenimiento", el sistema la bloquea inmediatamente para nuevas reservas y notifica al personal de limpieza que no realice aseo de rutina.',
                  style: TextStyle(fontSize: 12.5),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  value: selectedRoomId,
                  decoration: const InputDecoration(labelText: 'Suite a poner en mantenimiento'),
                  items: rooms.map((r) {
                    final name = r['name'] ?? r['number'] ?? 'Habitación';
                    final status = _getStatusLabel(r['status']?.toString());
                    return DropdownMenuItem<String>(
                      value: r['id'].toString(),
                      child: Text('$name ($status)', style: const TextStyle(fontSize: 13)),
                    );
                  }).toList(),
                  onChanged: (val) {
                    setDlgState(() => selectedRoomId = val);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: reasonCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Detalle o Motivo (opcional)',
                    prefixIcon: Icon(Icons.handyman_outlined),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (selectedRoomId == null) {
                  _showSnack('Seleccione una habitación.', isError: true);
                  return;
                }
                try {
                  await widget.api.updateRoomStatus(roomId: selectedRoomId!, status: 'MAINTENANCE');
                  if (ctx.mounted) Navigator.of(ctx).pop(true);
                } catch (e) {
                  _showSnack('Error al cambiar a mantenimiento: $e', isError: true);
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[800]),
              child: const Text('Confirmar Mantenimiento'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      _showSnack('La suite ha sido puesta en Mantenimiento con éxito.');
      _loadBoard(silent: true);
    }
  }

  Future<void> _showRoomStatusSelectorDialog(Map<String, dynamic> room) async {
    final roomId = room['id'].toString();
    final currentStatus = room['status']?.toString() ?? 'AVAILABLE';
    final roomName = room['name'] ?? room['number'] ?? 'Habitación';

    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.published_with_changes_rounded, color: Colors.teal),
            const SizedBox(width: 8),
            Text('Estado: $roomName'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Estado actual: ${_getStatusLabel(currentStatus)}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              icon: const Icon(Icons.build_rounded, size: 18),
              label: const Text('Requiere Mantenimiento'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey),
              onPressed: () => Navigator.of(ctx).pop('MAINTENANCE'),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              icon: const Icon(Icons.cleaning_services_rounded, size: 18),
              label: const Text('Enviar a Limpieza'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.amber[800]),
              onPressed: () => Navigator.of(ctx).pop('CLEANING'),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
              label: const Text('Marcar Disponible'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green[700]),
              onPressed: () => Navigator.of(ctx).pop('AVAILABLE'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );

    if (selected != null && selected != currentStatus) {
      try {
        await widget.api.updateRoomStatus(roomId: roomId, status: selected);
        _showSnack('Suite $roomName actualizada a ${_getStatusLabel(selected)}.');
        _loadBoard(silent: true);
      } catch (e) {
        _showSnack('Error al cambiar estado: $e', isError: true);
      }
    }
  }

  Future<void> _handleChangeRoomStatus(Map<String, dynamic> room) async {
    await _showRoomStatusSelectorDialog(room);
  }

  Future<void> _handleDeliverOrder(Map<String, dynamic> order) async {
    final orderId = order['id'].toString();
    try {
      await widget.api.deliverRoomServiceOrder(orderId);
      _showSnack('Pedido marcado como entregado en pasaplatos.');
      _loadBoard(silent: true);
    } catch (e) {
      _showSnack('Error al entregar pedido: $e', isError: true);
    }
  }

  Color _getStatusColor(String? status) {
    switch (status) {
      case 'AVAILABLE':
        return Colors.green;
      case 'OCCUPIED':
        return Colors.redAccent;
      case 'CLEANING':
        return Colors.amber[700]!;
      case 'MAINTENANCE':
        return Colors.blueGrey;
      default:
        return Colors.grey;
    }
  }

  String _getStatusLabel(String? status) {
    switch (status) {
      case 'AVAILABLE':
        return 'Disponible';
      case 'OCCUPIED':
        return 'Ocupada';
      case 'CLEANING':
        return 'En Limpieza';
      case 'MAINTENANCE':
        return 'Mantenimiento';
      default:
        return status ?? 'Desconocido';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hotelName = widget.api.currentHotelName ?? 'Hotel';
    final staffName = widget.api.staffName ?? 'Recepcionista';

    final rooms = ((_boardData?['rooms'] as List<dynamic>?) ?? [])
        .cast<Map<String, dynamic>>();
    final pendingPayments = ((_boardData?['pendingPayments'] as List<dynamic>?) ?? [])
        .cast<Map<String, dynamic>>();
    final pendingOrders = ((_boardData?['pendingOrders'] as List<dynamic>?) ?? [])
        .cast<Map<String, dynamic>>();
    final metrics = (_boardData?['metrics'] as Map<String, dynamic>?) ?? {};

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.support_agent_rounded, size: 20, color: Colors.tealAccent),
                const SizedBox(width: 8),
                Text(
                  hotelName,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            Text(
              'Panel de Recepción & Asistencia · $staffName',
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
                      // Tarjeta de Asistencia de Emergencia Inmediata
                      Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: Colors.teal.withAlpha(80)),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.shield_rounded, color: Colors.teal),
                                  SizedBox(width: 8),
                                  Text(
                                    'Comandos Rápidos de Emergencia & Contingencia',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Accione remotamente los componentes de acceso o apruebe pagos si el huésped presenta inconvenientes con la automatización.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark ? Colors.white70 : Colors.black54,
                                ),
                              ),
                              const SizedBox(height: 14),
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: [
                                  ElevatedButton.icon(
                                    onPressed: () => _handleFaacPulse('ENTRY'),
                                    icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                                    label: const Text('Abrir FAAC Entrada'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.teal[700],
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                                  ElevatedButton.icon(
                                    onPressed: () => _handleFaacPulse('EXIT'),
                                    icon: const Icon(Icons.arrow_downward_rounded, size: 18),
                                    label: const Text('Abrir FAAC Salida'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.teal[800],
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                                  ElevatedButton.icon(
                                    onPressed: () => _openMaintenanceDialog(),
                                    icon: const Icon(Icons.build_rounded, size: 18),
                                    label: const Text('Requiere Mantenimiento'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.blueGrey[700],
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                                  ElevatedButton.icon(
                                    onPressed: () => _openManualPaymentDialog(),
                                    icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                                    label: const Text('Validar Pago Manual'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.amber[800],
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Tarjetas de Métricas Rápidas
                      Row(
                        children: [
                          Expanded(
                            child: _buildMetricTile(
                              icon: Icons.meeting_room_rounded,
                              color: Colors.green,
                              label: 'Disponibles',
                              value: '${metrics['availableRooms'] ?? rooms.where((x) => x['status'] == 'AVAILABLE').length}',
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: _buildMetricTile(
                              icon: Icons.hotel_rounded,
                              color: Colors.redAccent,
                              label: 'Ocupadas',
                              value: '${metrics['occupiedRooms'] ?? rooms.where((x) => x['status'] == 'OCCUPIED').length}',
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: _buildMetricTile(
                              icon: Icons.cleaning_services_rounded,
                              color: Colors.amber[700]!,
                              label: 'En Limpieza',
                              value: '${metrics['cleaningRooms'] ?? rooms.where((x) => x['status'] == 'CLEANING').length}',
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: _buildMetricTile(
                              icon: Icons.build_rounded,
                              color: Colors.blueGrey,
                              label: 'Mantenimiento',
                              value: '${rooms.where((x) => x['status'] == 'MAINTENANCE').length}',
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: _buildMetricTile(
                              icon: Icons.payment_rounded,
                              color: Colors.purple,
                              label: 'Por Cobrar',
                              value: '${metrics['pendingPaymentsCount'] ?? 0}',
                            ),
                          ),
                        ],
                      ),

                      if (pendingPayments.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 20),
                            const SizedBox(width: 8),
                            const Text(
                              'Pagos en Contingencia / Verificación Pendiente',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                            ),
                            const Spacer(),
                            Text(
                              '${pendingPayments.length} pendientes',
                              style: const TextStyle(fontSize: 12, color: Colors.orange),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        for (final p in pendingPayments)
                          Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: const CircleAvatar(
                                backgroundColor: Colors.orange,
                                child: Icon(Icons.receipt_long_rounded, color: Colors.white),
                              ),
                              title: Text(
                                '${p['reservation']?['room']?['name'] ?? 'Habitación'} · \$${p['amountUsd'] ?? 0} (${p['amountBs'] ?? 0} Bs)',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              subtitle: Text(
                                'Huésped: ${p['reservation']?['guest']?['fullName'] ?? 'N/A'} · Tel: ${p['reservation']?['guest']?['phone'] ?? 'N/A'}\nRef: ${p['gatewayRef'] ?? 'No confirmada'} · Estado: ${p['status']}',
                                style: const TextStyle(fontSize: 12),
                              ),
                              trailing: ElevatedButton(
                                onPressed: () => _openManualPaymentDialog(preselected: p),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.teal,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                ),
                                child: const Text('Aprobar'),
                              ),
                            ),
                          ),
                      ],

                      if (pendingOrders.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            const Icon(Icons.room_service_rounded, color: Colors.indigoAccent, size: 20),
                            const SizedBox(width: 8),
                            const Text(
                              'Pedidos Pasaplatos en Espera',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                            ),
                            const Spacer(),
                            Text(
                              '${pendingOrders.length} por entregar',
                              style: const TextStyle(fontSize: 12, color: Colors.indigoAccent),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        for (final ord in pendingOrders)
                          Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: const CircleAvatar(
                                backgroundColor: Colors.indigoAccent,
                                child: Icon(Icons.flatware_rounded, color: Colors.white),
                              ),
                              title: Text(
                                '${ord['reservation']?['room']?['name'] ?? 'Suite'} · Orden #${ord['id'].toString().substring(0, 6)}',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              subtitle: Text(
                                'Total: \$${ord['totalUsd'] ?? 0} · Estado: ${ord['status']}',
                                style: const TextStyle(fontSize: 12),
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

                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.bed_rounded, color: Colors.teal, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'Habitaciones & Control en Tiempo Real',
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          Text(
                            '${rooms.length} Suites',
                            style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.black54),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // Grilla de Habitaciones
                      LayoutBuilder(
                        builder: (ctx, constraints) {
                          final crossAxisCount = constraints.maxWidth > 600 ? 3 : 2;
                          return GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: crossAxisCount,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                              childAspectRatio: 1.15,
                            ),
                            itemCount: rooms.length,
                            itemBuilder: (ctx, i) {
                              final r = rooms[i];
                              final status = r['status']?.toString() ?? 'AVAILABLE';
                              final color = _getStatusColor(status);
                              final name = r['name'] ?? r['number'] ?? 'Habitación';
                              final type = r['roomType']?['name'] ?? 'Estándar';

                              return Card(
                                elevation: 2,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  side: BorderSide(color: color.withAlpha(120), width: 1.5),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(10),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              name,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: color.withAlpha(40),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              _getStatusLabel(status),
                                              style: TextStyle(
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.bold,
                                                color: color,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      Text(
                                        type,
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          color: isDark ? Colors.white60 : Colors.black54,
                                        ),
                                      ),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.end,
                                        children: [
                                          IconButton(
                                            tooltip: 'Destrabar cerradura',
                                            icon: const Icon(Icons.lock_open_rounded, size: 18),
                                            color: Colors.amber[800],
                                            onPressed: () => _handleEmergencyDoorUnlock(r),
                                          ),
                                          IconButton(
                                            tooltip: 'Requiere Mantenimiento',
                                            icon: const Icon(Icons.build_rounded, size: 18),
                                            color: Colors.blueGrey,
                                            onPressed: () => _openMaintenanceDialog(preselectedRoom: r),
                                          ),
                                          IconButton(
                                            tooltip: 'Cambiar estado',
                                            icon: const Icon(Icons.published_with_changes_rounded, size: 18),
                                            color: Colors.teal,
                                            onPressed: () => _handleChangeRoomStatus(r),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                      const SizedBox(height: 30),
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
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(fontSize: 10.5),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
