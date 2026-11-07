import 'dart:async';
import 'package:flutter/material.dart';
import '../core/owner_api.dart';
import '../core/owner_theme.dart';

/// Tablero exclusivo para el rol `CLEANING` (Camareras / Operaciones):
/// Cero visibilidad de montos USD/Bs, eventos bancarios o identidad de huéspedes.
class CleaningBoardScreen extends StatefulWidget {
  final OwnerApiClient api;
  final VoidCallback onLogout;

  const CleaningBoardScreen({
    super.key,
    required this.api,
    required this.onLogout,
  });

  @override
  State<CleaningBoardScreen> createState() => _CleaningBoardScreenState();
}

class _CleaningBoardScreenState extends State<CleaningBoardScreen> {
  bool _loading = true;
  bool _sseLive = false;
  String? _error;
  Map<String, dynamic>? _board;
  StreamSubscription<Map<String, dynamic>>? _sseSub;

  @override
  void initState() {
    super.initState();
    _loadBoard();
    _connectEvents();
  }

  @override
  void dispose() {
    _sseSub?.cancel();
    super.dispose();
  }

  void _connectEvents() {
    final hid = widget.api.cleaningHotelId;
    _sseSub = widget.api.connectRealtimeEvents(hotelId: hid).listen((event) {
      if (!mounted) return;
      final type = event['type']?.toString() ?? '';
      if (type == 'CONNECTED') {
        setState(() => _sseLive = true);
        return;
      }
      if (const {
        'ROOM_STATUS_CHANGED',
        'ROOM_SERVICE_ORDER',
        'ROOM_SERVICE_DELIVERED',
      }.contains(type)) {
        _loadBoard(silent: true);
      }
    });
  }

  Future<void> _loadBoard({bool silent = false}) async {
    final hid = widget.api.cleaningHotelId;
    if (hid == null || hid.isEmpty) {
      widget.onLogout();
      return;
    }

    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final data = await widget.api.fetchCleaningBoard(hid);
      if (mounted) {
        setState(() => _board = data);
      }
    } on OwnerApiException catch (e) {
      if (e.statusCode == 401 || e.statusCode == 403) {
        widget.onLogout();
        return;
      }
      if (mounted && !silent) setState(() => _error = e.toString());
    } catch (e) {
      if (mounted && !silent) setState(() => _error = e.toString());
    } finally {
      if (mounted && !silent) setState(() => _loading = false);
    }
  }

  Future<void> _markRoomReady(String roomId, String roomName) async {
    try {
      await widget.api.updateRoomCleaningStatus(roomId, 'AVAILABLE');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: OwnerTheme.available,
          content: Text(
            '✅ Suite $roomName habilitada para nuevas reservas QR.',
            style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
          ),
        ),
      );
      await _loadBoard(silent: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: OwnerTheme.occupied, content: Text(e.toString())),
      );
    }
  }

  Future<void> _deliverOrder(String orderId, String roomName) async {
    try {
      await widget.api.deliverRoomServiceOrder(orderId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: OwnerTheme.available,
          content: Text(
            '🛎️ Pedido entregado en pasaplatos de Habitación $roomName.',
            style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
          ),
        ),
      );
      await _loadBoard(silent: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: OwnerTheme.occupied, content: Text(e.toString())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final hotel = (_board?['hotel'] as Map<String, dynamic>?) ?? {};
    final summary = (_board?['summary'] as Map<String, dynamic>?) ?? {};
    final rooms =
        ((_board?['rooms'] as List<dynamic>?) ?? []).cast<Map<String, dynamic>>();
    final deliveries = ((_board?['pendingDeliveries'] as List<dynamic>?) ?? [])
        .cast<Map<String, dynamic>>();

    // Ordenar primero las habitaciones en CLEANING, luego las ocupadas próximas a salir
    final sortedRooms = [...rooms]..sort((a, b) {
        int rank(Map<String, dynamic> r) {
          if (r['status'] == 'CLEANING') return 0;
          if (r['expiringSoon'] == true) return 1;
          if (r['status'] == 'OCCUPIED') return 2;
          return 3;
        }

        return rank(a).compareTo(rank(b));
      });

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(
              Icons.cleaning_services_rounded,
              color: OwnerTheme.gold,
              size: 21,
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                'Operaciones · ${hotel['name'] ?? widget.api.cleaningHotelName ?? 'Hotel'}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: (_sseLive ? OwnerTheme.available : OwnerTheme.textSecondary)
                    .withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _sseLive ? '● EN VIVO' : '● SYNC',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: _sseLive ? OwnerTheme.available : OwnerTheme.textSecondary,
                ),
              ),
            ),
          ],
        ),
        actions: [
          if (widget.api.staffName != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  widget.api.staffName!,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: OwnerTheme.textSecondary,
                  ),
                ),
              ),
            ),
          IconButton(
            tooltip: 'Actualizar',
            onPressed: () => _loadBoard(),
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: 'Cerrar turno',
            onPressed: widget.onLogout,
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!, style: const TextStyle(color: OwnerTheme.occupied)),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _loadBoard,
                        child: const Text('Reintentar'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadBoard,
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _statPill(
                            'Por Acondicionar',
                            '${summary['cleaningCount'] ?? 0}',
                            OwnerTheme.cleaning,
                            Icons.cleaning_services_rounded,
                          ),
                          _statPill(
                            'Salidas ≤15 min',
                            '${summary['expiringSoonCount'] ?? 0}',
                            OwnerTheme.occupied,
                            Icons.timer_outlined,
                          ),
                          _statPill(
                            'Entregas Pasaplatos',
                            '${summary['pendingDeliveriesCount'] ?? 0}',
                            OwnerTheme.gold,
                            Icons.room_service_outlined,
                          ),
                          _statPill(
                            'Suites Listas',
                            '${summary['availableCount'] ?? 0}',
                            OwnerTheme.available,
                            Icons.check_circle_outline,
                          ),
                        ],
                      ),
                      if (deliveries.isNotEmpty) ...[
                        const SizedBox(height: 22),
                        const Text(
                          '🛎️ Pedidos Pagados · Depositar en Pasaplatos / Esclusa',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: OwnerTheme.gold,
                          ),
                        ),
                        const SizedBox(height: 10),
                        for (final d in deliveries)
                          Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              leading: CircleAvatar(
                                backgroundColor:
                                    OwnerTheme.gold.withValues(alpha: 0.16),
                                child: const Icon(
                                  Icons.room_service_rounded,
                                  color: OwnerTheme.gold,
                                ),
                              ),
                              title: Text(
                                'Suite ${d['roomName']} · ${(d['items'] as List<dynamic>? ?? []).map((i) => "${i['qty']}x ${i['name']}").join(", ")}',
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                              subtitle: Text(
                                (d['guestNote']?.toString().isNotEmpty ?? false)
                                    ? 'Nota del huésped: ${d['guestNote']}'
                                    : 'Depositar en esclusa sin tocar la puerta interior',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: OwnerTheme.textSecondary,
                                ),
                              ),
                              trailing: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: OwnerTheme.available,
                                  foregroundColor: Colors.black,
                                  minimumSize: const Size(140, 40),
                                ),
                                onPressed: () => _deliverOrder(
                                  d['orderId'].toString(),
                                  d['roomName'].toString(),
                                ),
                                icon: const Icon(Icons.check_rounded, size: 17),
                                label: const Text('En Pasaplatos'),
                              ),
                            ),
                          ),
                      ],
                      const SizedBox(height: 22),
                      const Text(
                        'Estado Operativo de Habitaciones (Sin Datos Financieros)',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 12),
                      for (final r in sortedRooms) _buildCleaningRoomRow(r),
                    ],
                  ),
                ),
    );
  }

  Widget _statPill(String label, String val, Color color, IconData icon) {
    return Container(
      width: 210,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: OwnerTheme.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                val,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
              ),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: OwnerTheme.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCleaningRoomRow(Map<String, dynamic> r) {
    final status = (r['status'] ?? 'AVAILABLE').toString();
    final isCleaning = status == 'CLEANING';
    final isOccupied = status == 'OCCUPIED';
    final expiringSoon = r['expiringSoon'] == true;
    final mins = r['minutesRemaining'];

    final color = isCleaning
        ? OwnerTheme.cleaning
        : isOccupied
            ? (expiringSoon ? OwnerTheme.occupied : OwnerTheme.cyan)
            : OwnerTheme.available;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.16),
          child: Icon(
            isCleaning
                ? Icons.cleaning_services_rounded
                : isOccupied
                    ? Icons.lock_clock_outlined
                    : Icons.check_circle_outline,
            color: color,
          ),
        ),
        title: Text(
          'Suite ${r['name']} (${r['type']})',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          isCleaning
              ? 'HUÉSPED RETIRADO · Requiere limpieza y reposición de lencería'
              : isOccupied
                  ? (expiringSoon
                      ? '⚠️ Salida próxima en ~${mins ?? 0} min · Preparar carrito'
                      : 'Ocupada · Tiempo restante estimado: ${mins ?? "--"} min')
                  : 'Lista y habilitada para check-in QR',
          style: TextStyle(
            fontSize: 12.5,
            color: expiringSoon ? OwnerTheme.cleaning : OwnerTheme.textSecondary,
          ),
        ),
        trailing: isCleaning
            ? ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: OwnerTheme.available,
                  foregroundColor: Colors.black,
                  minimumSize: const Size(148, 40),
                ),
                onPressed: () =>
                    _markRoomReady(r['id'].toString(), r['name'].toString()),
                icon: const Icon(Icons.done_all_rounded, size: 17),
                label: const Text('Habilitar Suite'),
              )
            : null,
      ),
    );
  }
}
