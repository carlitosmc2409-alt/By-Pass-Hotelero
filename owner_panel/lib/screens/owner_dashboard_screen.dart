import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/bdv_bridge_service.dart';
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

class _OwnerDashboardScreenState extends State<OwnerDashboardScreen>
    with WidgetsBindingObserver {
  static const Map<String, String> _banks = {
    '0102': '0102 · Banco de Venezuela (Piloto Automático)',
    '0134': '0134 · Banesco',
    '0105': '0105 · Mercantil',
    '0108': '0108 · Provincial',
    '0172': '0172 · Bancamiga',
    '0191': '0191 · BNC',
  };

  final BdvBridgeService _bridgeService = BdvBridgeService();
  BdvBridgeStatus _bridgeStatus = BdvBridgeStatus.unsupported();
  final _bridgeApiUrlCtrl =
      TextEditingController(text: OwnerApiClient.baseUrl);
  final _simulatedPushCtrl = TextEditingController(
    text: 'PagomovilBDV recibido por Bs. 1.000,00 del 0412-9876543 Ref: 00334455',
  );
  bool _bridgeAllowTestSources = true;
  bool _sendingSimulatedPush = false;

  List<Map<String, dynamic>> _hotels = [];
  String? _selectedHotelId;
  Map<String, dynamic>? _dashboard;
  bool _loading = true;
  bool _sseLive = false;
  bool _pulsingFaac = false;
  String? _error;
  String _roomFilter = 'ALL';
  StreamSubscription<Map<String, dynamic>>? _sseSub;

  // Controladores Cuenta Receptora Pago Móvil
  String _selectedBankCode = '0102';
  final _payPhoneCtrl = TextEditingController();
  final _payIdCtrl = TextEditingController();
  final _payHolderCtrl = TextEditingController();
  final _fallbackRateCtrl = TextEditingController();
  bool _savingPaymentInfo = false;

  // Controladores Barrera Vehicular FAAC
  bool _faacEnabled = true;
  final _faacModelCtrl = TextEditingController();
  final _faacEntryIdCtrl = TextEditingController();
  final _faacExitIdCtrl = TextEditingController();
  final _faacPulseMsCtrl = TextEditingController();
  final _faacGraceMinsCtrl = TextEditingController();
  final _faacWebhookCtrl = TextEditingController();
  bool _savingFaac = false;
  bool _testingRelay = false;
  Map<String, dynamic>? _lastRelayDiagnostic;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadInitial();
    _refreshBridgeStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sseSub?.cancel();
    _bridgeApiUrlCtrl.dispose();
    _simulatedPushCtrl.dispose();
    _payPhoneCtrl.dispose();
    _payIdCtrl.dispose();
    _payHolderCtrl.dispose();
    _fallbackRateCtrl.dispose();
    _faacModelCtrl.dispose();
    _faacEntryIdCtrl.dispose();
    _faacExitIdCtrl.dispose();
    _faacPulseMsCtrl.dispose();
    _faacGraceMinsCtrl.dispose();
    _faacWebhookCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshBridgeStatus();
    }
  }

  void _connectSseForSelectedHotel() {
    _sseSub?.cancel();
    final hid = _selectedHotelId;
    if (hid == null || hid.isEmpty) return;

    _sseSub = widget.api.connectRealtimeEvents(hotelId: hid).listen((event) {
      if (!mounted) return;
      final type = event['type']?.toString() ?? '';
      if (type == 'CONNECTED') {
        setState(() => _sseLive = true);
        return;
      }
      if (type == 'FAAC_BARRIER_PULSE') {
        final dir = event['direction'] == 'EXIT' ? 'SALIDA' : 'ENTRADA';
        _showSnack('🚗 Pulso Barrera FAAC ($dir) activado en vivo');
      } else if (type == 'PAYMENT_APPROVED') {
        _showSnack('⚡ Nuevo Pago Móvil conciliado y QR habilitado');
      } else if (type == 'ROOM_SERVICE_ORDER') {
        _showSnack('🍾 Nuevo pedido Room Service pagado para Pasaplatos');
      }
      if (const {
        'PAYMENT_APPROVED',
        'BANK_EVENT_RECEIVED',
        'ROOM_STATUS_CHANGED',
        'ROOM_SERVICE_ORDER',
        'ROOM_SERVICE_DELIVERED',
        'FAAC_BARRIER_PULSE',
        'FAAC_RELAY_ACK',
        'IOT_DEVICE_HEARTBEAT',
        'DOOR_UNLOCK_PULSE',
      }.contains(type)) {
        _refreshDashboard(silent: true);
      }
    });
  }

  Future<void> _refreshBridgeStatus() async {
    final st = await _bridgeService.getStatus();
    if (!mounted) return;
    setState(() {
      _bridgeStatus = st;
      if (st.apiBaseUrl.isNotEmpty) {
        _bridgeApiUrlCtrl.text = st.apiBaseUrl;
      }
      _bridgeAllowTestSources = st.allowTestSources;
    });
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
      _connectSseForSelectedHotel();
      await _refreshDashboard();
    } on OwnerApiException catch (e) {
      if (e.statusCode == 401) {
        widget.onLogout();
        return;
      }
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _refreshDashboard({bool silent = false}) async {
    final hotelId = _selectedHotelId;
    if (hotelId == null) return;

    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final data = await widget.api.fetchHotelDashboard(hotelId);
      if (!mounted) return;

      final hotel = (data['hotel'] as Map<String, dynamic>?) ?? {};
      final paymentInfo =
          (hotel['paymentInfo'] as Map<String, dynamic>?) ?? {};
      final faac = (hotel['faac'] as Map<String, dynamic>?) ?? {};

      if (!silent) {
        final bank = (paymentInfo['bank'] ?? '0102').toString();
        _selectedBankCode = _banks.containsKey(bank) ? bank : '0102';
        _payPhoneCtrl.text = (paymentInfo['phone'] ?? '').toString();
        _payIdCtrl.text = (paymentInfo['idNumber'] ?? '').toString();
        _payHolderCtrl.text =
            (paymentInfo['holderName'] ?? hotel['name'] ?? '').toString();
        final fbRate = paymentInfo['fallbackExchangeRate'];
        _fallbackRateCtrl.text = fbRate != null ? fbRate.toString() : '';

        _faacEnabled = faac['enabled'] != false;
        _faacModelCtrl.text =
            (faac['model'] ?? 'FAAC 615 BPR / Placa E615').toString();
        _faacEntryIdCtrl.text =
            (faac['entryDeviceId'] ?? 'faac-entrada-1').toString();
        _faacExitIdCtrl.text =
            (faac['exitDeviceId'] ?? 'faac-salida-1').toString();
        _faacPulseMsCtrl.text = (faac['pulseDurationMs'] ?? 1000).toString();
        _faacGraceMinsCtrl.text = (faac['exitGraceMinutes'] ?? 15).toString();
        _faacWebhookCtrl.text = (faac['relayWebhookUrl'] ?? '').toString();
      }

      setState(() {
        _dashboard = data;
        _loading = false;
      });
    } catch (e) {
      if (mounted && !silent) {
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
          style: TextStyle(
            color: isError ? Colors.white : Colors.black,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Future<void> _manualFaacPulse(String direction) async {
    final hotelId = _selectedHotelId;
    if (hotelId == null || _pulsingFaac) return;
    setState(() => _pulsingFaac = true);
    try {
      final res = await widget.api.pulseFaacBarrier(
        hotelId: hotelId,
        direction: direction,
      );
      _showSnack(res['message']?.toString() ?? 'Pulso FAAC enviado');
    } catch (e) {
      _showSnack(e.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _pulsingFaac = false);
    }
  }

  Future<void> _saveFaacConfig() async {
    final hotelId = _selectedHotelId;
    if (hotelId == null) return;
    setState(() => _savingFaac = true);
    try {
      await widget.api.updateHotelOperations(
        hotelId: hotelId,
        faac: {
          'enabled': _faacEnabled,
          'model': _faacModelCtrl.text.trim(),
          'entryDeviceId': _faacEntryIdCtrl.text.trim(),
          'exitDeviceId': _faacExitIdCtrl.text.trim(),
          'pulseDurationMs':
              int.tryParse(_faacPulseMsCtrl.text.trim()) ?? 1000,
          'exitGraceMinutes':
              int.tryParse(_faacGraceMinsCtrl.text.trim()) ?? 15,
          'relayWebhookUrl': _faacWebhookCtrl.text.trim(),
        },
      );
      _showSnack('Configuración de Barreras FAAC guardada.');
      await _refreshDashboard();
    } catch (e) {
      _showSnack(e.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _savingFaac = false);
    }
  }

  Future<void> _runRelayDiagnostic({bool dryRun = true}) async {
    final hotelId = _selectedHotelId;
    if (hotelId == null || _testingRelay) return;
    setState(() => _testingRelay = true);
    try {
      final res = await widget.api.testFaacRelay(
        hotelId: hotelId,
        direction: 'ENTRY',
        dryRun: dryRun,
      );
      if (!mounted) return;
      setState(() => _lastRelayDiagnostic = res);
      final ok = res['reachable'] == true;
      _showSnack(
        res['message']?.toString() ??
            (ok ? 'Controladora FAAC en línea' : 'Controladora no accesible'),
        isError: !ok,
      );
      await _refreshDashboard(silent: true);
    } catch (e) {
      _showSnack(e.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _testingRelay = false);
    }
  }

  Future<void> _copyEsp32ProvisioningHeader() async {
    final hotel = (_dashboard?['hotel'] as Map<String, dynamic>?) ?? {};
    final hotelId = (hotel['id'] ?? '').toString();
    final iotToken = (hotel['iotHardwareToken'] ?? '').toString();
    final entryId = _faacEntryIdCtrl.text.trim().isEmpty
        ? 'faac-entrada-1'
        : _faacEntryIdCtrl.text.trim();
    final exitId = _faacExitIdCtrl.text.trim().isEmpty
        ? 'faac-salida-1'
        : _faacExitIdCtrl.text.trim();
    final pulseMs = int.tryParse(_faacPulseMsCtrl.text.trim()) ?? 1000;

    final snippet = '''
// ============================================================================
// StayPass QR · Credenciales de Aprovisionamiento ESP32 + Lector GM65 + FAAC
// Hotel: ${hotel['name'] ?? 'Motel'}
// Pegar en hardware_iot/esp32_faac_totem/esp32_faac_totem.ino
// ============================================================================
const char* API_BASE_URL   = "${OwnerApiClient.baseUrl}";
const char* HOTEL_ID       = "$hotelId";
const char* IOT_TOKEN      = "$iotToken";
const char* DEVICE_ID      = "$entryId"; // o "$exitId" para tótem de salida
const uint32_t RELAY_PULSE_MS = $pulseMs; // Bornera J5: OPEN-A + GND
''';

    await Clipboard.setData(ClipboardData(text: snippet));
    _showSnack('📋 Configuración C++ para ESP32 copiada al portapapeles.');
  }

  Future<void> _deliverRoomService(String orderId, String roomName) async {
    try {
      await widget.api.deliverRoomServiceOrder(orderId);
      _showSnack('🛎️ Pedido marcado como entregado en pasaplatos ($roomName)');
      await _refreshDashboard(silent: true);
    } catch (e) {
      _showSnack(e.toString(), isError: true);
    }
  }

  Future<void> _openCreateStaffDialog() async {
    final hotelId = _selectedHotelId;
    if (hotelId == null) return;

    final nameCtrl = TextEditingController();
    final aliasCtrl = TextEditingController();
    final pinCtrl = TextEditingController();

    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: OwnerTheme.card,
        title: const Text('Nueva Credencial de Limpieza (Cero Finanzas)'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'El personal ingresa con Alias + PIN y solo ve qué suites limpiar, próximas salidas (≤15m) y entregas en pasaplatos.',
                style: TextStyle(fontSize: 12.5, color: OwnerTheme.textSecondary),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nombre o Turno (ej: Turno Nocturno)',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: aliasCtrl,
                decoration: const InputDecoration(
                  labelText: 'Alias único (ej: camarera2)',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: pinCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'PIN numérico (mínimo 4 dígitos)',
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
              try {
                await widget.api.createCleaningStaff(
                  hotelId: hotelId,
                  name: nameCtrl.text.trim(),
                  alias: aliasCtrl.text.trim(),
                  pin: pinCtrl.text.trim(),
                );
                if (ctx.mounted) Navigator.of(ctx).pop(true);
              } catch (e) {
                _showSnack(e.toString(), isError: true);
              }
            },
            child: const Text('Crear Credencial'),
          ),
        ],
      ),
    );

    if (created == true) {
      _showSnack('Credencial operativa creada.');
      await _refreshDashboard();
    }
  }

  Future<void> _deleteStaff(String staffId) async {
    final hotelId = _selectedHotelId;
    if (hotelId == null) return;
    try {
      await widget.api.deleteCleaningStaff(hotelId: hotelId, staffId: staffId);
      _showSnack('Credencial revocada.');
      await _refreshDashboard();
    } catch (e) {
      _showSnack(e.toString(), isError: true);
    }
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
            'La suite "${room['name']}" figura ocupada. Si el huésped ya se retiró, '
            'esto cerrará la reserva activa, invalidará su QR y enviará la suite a ${_statusLabel(newStatus)}.',
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
      _showSnack('Suite actualizada a ${_statusLabel(newStatus)}');
      await _refreshDashboard(silent: true);
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
    final amenitiesCtrl = TextEditingController(
      text: 'Aire acondicionado, TV, Estacionamiento privado, Pasaplatos',
    );
    String selectedType = 'SUITE';

    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: OwnerTheme.card,
              title: const Text('Nueva Habitación / Suite'),
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
                          labelText: 'Nombre o Número (ej: 204)',
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
                              DropdownMenuItem(
                                value: 'STANDARD',
                                child: Text('Estándar'),
                              ),
                              DropdownMenuItem(
                                value: 'DELUXE',
                                child: Text('Deluxe'),
                              ),
                              DropdownMenuItem(
                                value: 'SUITE',
                                child: Text('Suite Boutique'),
                              ),
                              DropdownMenuItem(
                                value: 'PREMIUM',
                                child: Text('Premium / Jacuzzi VIP'),
                              ),
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
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
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
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              decoration: const InputDecoration(
                                labelText: 'Amanecida 24h (USD)',
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
                  child: const Text('Crear Suite'),
                ),
              ],
            );
          },
        );
      },
    );

    if (created == true) {
      _showSnack('Suite creada exitosamente');
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

      final fallbackRate = double.tryParse(
        _fallbackRateCtrl.text.trim().replaceAll(',', '.'),
      );

      await widget.api.updateHotelPaymentInfo(
        hotelId: hotelId,
        bank: _selectedBankCode,
        bankName: bankName,
        phone: phone,
        idNumber: idNumber,
        holderName: holderName.isEmpty ? 'Propietario' : holderName,
        fallbackExchangeRate: fallbackRate,
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
    final metrics = (_dashboard?['metrics'] as Map<String, dynamic>?) ?? {};
    final hotelName = (hotel['name'] ?? 'Panel Ejecutivo').toString();
    final pendingDeliveriesCount =
        (metrics['pendingDeliveriesCount'] as num?)?.toInt() ?? 0;

    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              const Icon(Icons.shield_moon_rounded, color: OwnerTheme.gold),
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
                              _connectSseForSelectedHotel();
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
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: (_sseLive ? OwnerTheme.available : OwnerTheme.cleaning)
                      .withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _sseLive ? '● SSE EN VIVO' : '● SYNC',
                  style: TextStyle(
                    color: _sseLive ? OwnerTheme.available : OwnerTheme.cleaning,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Actualizar en vivo',
              onPressed: _loading ? null : () => _refreshDashboard(),
              icon: const Icon(Icons.refresh_rounded),
            ),
            IconButton(
              tooltip: 'Cerrar sesión',
              onPressed: widget.onLogout,
              icon: const Icon(Icons.logout_rounded),
            ),
            const SizedBox(width: 6),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            indicatorColor: OwnerTheme.gold,
            labelColor: OwnerTheme.gold,
            unselectedLabelColor: OwnerTheme.textSecondary,
            tabs: [
              const Tab(
                icon: Icon(Icons.grid_view_rounded, size: 19),
                text: 'Suites & FAAC',
              ),
              Tab(
                icon: Badge(
                  backgroundColor: OwnerTheme.gold,
                  isLabelVisible: pendingDeliveriesCount > 0,
                  label: Text(
                    '$pendingDeliveriesCount',
                    style: const TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  child: const Icon(
                    Icons.directions_car_filled_outlined,
                    size: 19,
                  ),
                ),
                text: 'FAAC · Pasaplatos · Staff',
              ),
              const Tab(
                icon: Icon(Icons.bolt_rounded, size: 19),
                text: 'Pagos y BDV',
              ),
              const Tab(
                icon: Icon(Icons.phonelink_ring_rounded, size: 19),
                text: 'Puente Android',
              ),
              const Tab(
                icon: Icon(Icons.account_balance_rounded, size: 19),
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
              const Icon(
                Icons.error_outline,
                size: 48,
                color: OwnerTheme.occupied,
              ),
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
        _buildOperationsTab(),
        _buildFinanceTab(),
        _buildBdvBridgeTab(),
        _buildPaymentSettingsTab(),
      ],
    );
  }

  Widget _buildRoomsTab() {
    final metrics = (_dashboard?['metrics'] as Map<String, dynamic>?) ?? {};
    final hotel = (_dashboard?['hotel'] as Map<String, dynamic>?) ?? {};
    final faac = (hotel['faac'] as Map<String, dynamic>?) ?? {};
    final allRooms = ((_dashboard?['rooms'] as List<dynamic>?) ?? [])
        .cast<Map<String, dynamic>>();

    final filteredRooms = _roomFilter == 'ALL'
        ? allRooms
        : allRooms.where((r) => r['status'] == _roomFilter).toList();

    final totalRooms = metrics['totalRooms'] ?? 0;
    final occupiedRooms = metrics['occupiedRooms'] ?? 0;
    final availableRooms = metrics['availableRooms'] ?? 0;
    final cleaningRooms = metrics['cleaningRooms'] ?? 0;
    final expiringSoonRooms = metrics['expiringSoonRooms'] ?? 0;
    final revTodayUsd = (metrics['revenueTodayUsd'] ?? 0).toString();
    final revTodayVes = (metrics['revenueTodayVes'] ?? 0).toString();
    final approvedToday = metrics['approvedCountToday'] ?? 0;
    final revMonthUsd = (metrics['revenueMonthUsd'] ?? 0).toString();
    final revMonthVes = (metrics['revenueMonthVes'] ?? 0).toString();
    final pendingDeliveries = metrics['pendingDeliveriesCount'] ?? 0;

    return RefreshIndicator(
      onRefresh: () => _refreshDashboard(),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              _KpiCard(
                title: 'Ocupación en Vivo',
                value: '$occupiedRooms / $totalRooms',
                subtitle:
                    '$availableRooms libres · $cleaningRooms limpieza · $expiringSoonRooms ≤15m',
                icon: Icons.king_bed_rounded,
                accent: OwnerTheme.cyan,
              ),
              _KpiCard(
                title: 'Ingresos Hoy (BDV Directo)',
                value: '\$$revTodayUsd USD',
                subtitle: 'Bs. $revTodayVes · $approvedToday operaciones',
                icon: Icons.trending_up_rounded,
                accent: OwnerTheme.available,
              ),
              _KpiCard(
                title: 'Acumulado Mensual',
                value: '\$$revMonthUsd USD',
                subtitle: 'Bs. $revMonthVes conciliados',
                icon: Icons.calendar_month_rounded,
                accent: OwnerTheme.gold,
              ),
              _KpiCard(
                title: 'Pasaplatos Pendientes',
                value: '$pendingDeliveries',
                subtitle: pendingDeliveries == 0
                    ? 'Sin entregas pendientes'
                    : 'Pedidos Room Service pagados',
                icon: Icons.room_service_rounded,
                accent: pendingDeliveries == 0
                    ? OwnerTheme.available
                    : OwnerTheme.gold,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Barra de Control Rápido de Barreras Vehiculares FAAC
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: OwnerTheme.card,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: OwnerTheme.cyan.withValues(alpha: 0.35),
              ),
            ),
            child: Wrap(
              spacing: 14,
              runSpacing: 10,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.directions_car_filled_rounded,
                      color: OwnerTheme.cyan,
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Control Remoto Barreras FAAC · ${faac['model'] ?? 'FAAC 615 BPR'}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          'Entrada: ${faac['entryDeviceId'] ?? 'faac-entrada-1'} · Salida: ${faac['exitDeviceId'] ?? 'faac-salida-1'} (+${faac['exitGraceMinutes'] ?? 15}m gracia)',
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: OwnerTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: OwnerTheme.cyan,
                        foregroundColor: Colors.black,
                        minimumSize: const Size(150, 40),
                      ),
                      onPressed: _pulsingFaac
                          ? null
                          : () => _manualFaacPulse('ENTRY'),
                      icon: const Icon(Icons.login_rounded, size: 17),
                      label: const Text('Abrir Entrada FAAC'),
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: OwnerTheme.cyan),
                        minimumSize: const Size(146, 40),
                      ),
                      onPressed: _pulsingFaac
                          ? null
                          : () => _manualFaacPulse('EXIT'),
                      icon: const Icon(
                        Icons.logout_rounded,
                        size: 17,
                        color: OwnerTheme.cyan,
                      ),
                      label: const Text(
                        'Abrir Salida FAAC',
                        style: TextStyle(color: OwnerTheme.cyan),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

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
                label: const Text('Nueva Suite'),
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
                    'No hay suites en este filtro.',
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
                const spacing = 14.0;
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
      selectedColor: OwnerTheme.gold.withValues(alpha: 0.25),
      labelStyle: TextStyle(
        color: selected ? OwnerTheme.gold : OwnerTheme.textSecondary,
        fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
      ),
    );
  }

  Widget _buildRoomCard(Map<String, dynamic> room) {
    final status = (room['status'] ?? 'AVAILABLE').toString();
    final color = _statusColor(status);
    final activeRes = room['activeReservation'] as Map<String, dynamic>?;
    final expiringSoon = room['expiringSoon'] == true;
    final minsLeft = room['minutesRemaining'];
    final amenities = ((room['amenities'] as List<dynamic>?) ?? [])
        .map((e) => e.toString())
        .toList();

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
                    'Suite ${(room['name'] ?? 'Habitación')}',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
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
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${room['type']} · \$${room['pricePerHour']}/h · \$${room['pricePerNight']}/amanecida',
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
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
                  color: (expiringSoon ? OwnerTheme.cleaning : OwnerTheme.occupied)
                      .withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color:
                        (expiringSoon ? OwnerTheme.cleaning : OwnerTheme.occupied)
                            .withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      expiringSoon
                          ? Icons.warning_amber_rounded
                          : Icons.timer_outlined,
                      size: 17,
                      color: expiringSoon
                          ? OwnerTheme.cleaning
                          : OwnerTheme.occupied,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        expiringSoon
                            ? '⚠️ Vence en ~$minsLeft min · Salida: ${_formatShortDateTime(activeRes['checkOut'])}'
                            : 'Salida QR: ${_formatShortDateTime(activeRes['checkOut'])} (${activeRes['durationHours']}h · Anónimo)',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
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
                      foregroundColor: Colors.black,
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

  Widget _buildOperationsTab() {
    final hotel = (_dashboard?['hotel'] as Map<String, dynamic>?) ?? {};
    final staffList = ((hotel['cleaningStaff'] as List<dynamic>?) ?? [])
        .cast<Map<String, dynamic>>();
    final iotDevices = ((_dashboard?['iotDevices'] as List<dynamic>?) ?? [])
        .cast<Map<String, dynamic>>();
    final pendingDeliveries =
        ((_dashboard?['pendingDeliveries'] as List<dynamic>?) ?? [])
            .cast<Map<String, dynamic>>();
    final accessLogs =
        ((_dashboard?['recentAccessLogs'] as List<dynamic>?) ?? [])
            .cast<Map<String, dynamic>>();

    return RefreshIndicator(
      onRefresh: () => _refreshDashboard(),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // 1. Entregas en Pasaplatos / Esclusa
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.room_service_rounded, color: OwnerTheme.gold),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Pedidos Anónimos · Entrega por Pasaplatos / Esclusa',
                          style: TextStyle(
                            fontSize: 16.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Pedidos ya pagados con Pago Móvil BDV desde la habitación. Al marcarlos como entregados, el teléfono del huésped recibe aviso en vivo.',
                    style: TextStyle(
                      color: OwnerTheme.textSecondary,
                      fontSize: 12.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (pendingDeliveries.isEmpty)
                    const Text(
                      'No hay entregas pendientes en pasaplatos en este momento.',
                      style: TextStyle(color: OwnerTheme.textSecondary),
                    )
                  else
                    for (final d in pendingDeliveries)
                      Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: OwnerTheme.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: OwnerTheme.gold.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Suite ${d['roomName']} · ${(d['items'] as List<dynamic>? ?? []).map((i) => "${i['qty']}x ${i['name']}").join(", ")}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  if (d['guestNote']?.toString().isNotEmpty ??
                                      false)
                                    Text(
                                      'Nota: ${d['guestNote']}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: OwnerTheme.gold,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: OwnerTheme.available,
                                foregroundColor: Colors.black,
                                minimumSize: const Size(145, 38),
                              ),
                              onPressed: () => _deliverRoomService(
                                d['orderId'].toString(),
                                d['roomName'].toString(),
                              ),
                              icon: const Icon(Icons.check_rounded, size: 16),
                              label: const Text('En Pasaplatos'),
                            ),
                          ],
                        ),
                      ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 18),

          // 2. Configuración Hardware Barreras FAAC
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.directions_car_filled_rounded,
                            color: OwnerTheme.cyan,
                          ),
                          SizedBox(width: 10),
                          Text(
                            'Integración de Barreras Vehiculares FAAC',
                            style: TextStyle(
                              fontSize: 16.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      Switch(
                        value: _faacEnabled,
                        activeThumbColor: OwnerTheme.cyan,
                        onChanged: (v) => setState(() => _faacEnabled = v),
                      ),
                    ],
                  ),
                  const Text(
                    'Conecta el mismo código QR del huésped a los tótems de entrada/salida y al contacto seco OPEN-A + GND de tu central FAAC (615 BPR, 620, B614 o B680H).',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: OwnerTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _faacModelCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Modelo Barrera / Tarjeta Controladora FAAC',
                      prefixIcon: Icon(Icons.memory_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _faacEntryIdCtrl,
                          decoration: const InputDecoration(
                            labelText: 'ID Tótem QR Entrada',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _faacExitIdCtrl,
                          decoration: const InputDecoration(
                            labelText: 'ID Tótem QR Salida',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _faacPulseMsCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Pulso Relé OPEN-A (ms)',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _faacGraceMinsCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Gracia Salida Vehicular (min)',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _faacWebhookCtrl,
                    decoration: const InputDecoration(
                      labelText:
                          'Webhook Relé IP / ESP32 (ej: http://localhost:3090/rpc/pulse o http://192.168.1.50/rpc/pulse)',
                      prefixIcon: Icon(Icons.lan_outlined),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Bloque de Pre-Instalación: Telemetría IoT + Diagnóstico sin abrir + Aprovisionamiento ESP32
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: OwnerTheme.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: OwnerTheme.cyan.withValues(alpha: 0.28),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Expanded(
                              child: Text(
                                '📡 Controladoras IoT & Lector Óptico GM65 (Pre-Instalación / En Vivo)',
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w800,
                                  color: OwnerTheme.cyan,
                                ),
                              ),
                            ),
                            Text(
                              '${iotDevices.where((d) => d['online'] == true).length} en línea',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: iotDevices.any((d) => d['online'] == true)
                                    ? OwnerTheme.available
                                    : OwnerTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (iotDevices.isEmpty)
                          const Text(
                            'Sin tótems físicos detectados aún. El emulador virtual (:3090) o tu placa ESP32 aparecerán aquí automáticamente al enviar su primer heartbeat.',
                            style: TextStyle(
                              fontSize: 12,
                              color: OwnerTheme.textSecondary,
                            ),
                          )
                        else
                          for (final dev in iotDevices)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Icon(
                                    Icons.circle,
                                    size: 9,
                                    color: dev['online'] == true
                                        ? OwnerTheme.available
                                        : OwnerTheme.textSecondary,
                                  ),
                                  Text(
                                    '${dev['deviceId']}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                  Text(
                                    '· ${dev['opticalReader'] ?? 'GM65'} · SAFE: ${dev['safePhotocell'] ?? 'CLEAR'} · RSSI ${dev['rssiDbm'] ?? '-'} dBm · Pulsos: ${dev['pulseCount'] ?? 0}',
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      color: OwnerTheme.textSecondary,
                                    ),
                                  ),
                                  if (dev['emulated'] == true)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 7,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: OwnerTheme.gold
                                            .withValues(alpha: 0.16),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Text(
                                        'EMULADOR :3090',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          color: OwnerTheme.gold,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                        if (_lastRelayDiagnostic != null) ...[
                          const SizedBox(height: 10),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: (_lastRelayDiagnostic!['reachable'] == true
                                      ? OwnerTheme.available
                                      : OwnerTheme.occupied)
                                  .withValues(alpha: 0.13),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${_lastRelayDiagnostic!['message'] ?? ''} '
                              '(${_lastRelayDiagnostic!['latencyMs'] ?? '-'} ms)',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color:
                                    _lastRelayDiagnostic!['reachable'] == true
                                        ? OwnerTheme.available
                                        : OwnerTheme.occupied,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 10,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _testingRelay
                                  ? null
                                  : () => _runRelayDiagnostic(dryRun: true),
                              icon: const Icon(
                                Icons.network_check_rounded,
                                size: 17,
                                color: OwnerTheme.cyan,
                              ),
                              label: Text(
                                _testingRelay
                                    ? 'Probando Relé...'
                                    : 'Diagnóstico Relé IP (Dry-Run)',
                                style: const TextStyle(color: OwnerTheme.cyan),
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: _copyEsp32ProvisioningHeader,
                              icon: const Icon(
                                Icons.copy_all_rounded,
                                size: 17,
                                color: OwnerTheme.gold,
                              ),
                              label: const Text(
                                'Copiar Header ESP32 (.ino)',
                                style: TextStyle(color: OwnerTheme.gold),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton.icon(
                      onPressed: _savingFaac ? null : _saveFaacConfig,
                      icon: const Icon(Icons.save_outlined, size: 18),
                      label: const Text('Guardar Parámetros FAAC'),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 18),

          // 3. Personal de Limpieza (CLEANING)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Expanded(
                        child: Row(
                          children: [
                            Icon(
                              Icons.cleaning_services_rounded,
                              color: OwnerTheme.cleaning,
                            ),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Personal de Limpieza (Rol Cero Finanzas)',
                                style: TextStyle(
                                  fontSize: 16.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _openCreateStaffDialog,
                        icon: const Icon(Icons.person_add_alt_1_rounded, size: 17),
                        label: const Text('Nuevo PIN'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Código de este hotel para el login operativo: ${hotel['slug'] ?? hotel['id'] ?? ''}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: OwnerTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (staffList.isEmpty)
                    const Text(
                      'No hay credenciales creadas.',
                      style: TextStyle(color: OwnerTheme.textSecondary),
                    )
                  else
                    for (final s in staffList)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const CircleAvatar(
                          backgroundColor: OwnerTheme.surface,
                          child: Icon(
                            Icons.badge_outlined,
                            color: OwnerTheme.gold,
                          ),
                        ),
                        title: Text(
                          '${s['name']} · Alias: ${s['alias']}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: const Text(
                          'Acceso exclusivo a estado de limpieza y pasaplatos',
                          style: TextStyle(
                            fontSize: 12,
                            color: OwnerTheme.textSecondary,
                          ),
                        ),
                        trailing: IconButton(
                          tooltip: 'Revocar credencial',
                          onPressed: () => _deleteStaff(s['id'].toString()),
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            color: OwnerTheme.occupied,
                          ),
                        ),
                      ),
                ],
              ),
            ),
          ),

          if (accessLogs.isNotEmpty) ...[
            const SizedBox(height: 18),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Bitácora Reciente de Barreras FAAC y Cerraduras QR',
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    for (final l in accessLogs.take(8))
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                '[${l['deviceId'] ?? 'IoT'}] Suite ${l['roomName']} · ${l['event']}',
                                style: const TextStyle(fontSize: 12.5),
                              ),
                            ),
                            Text(
                              _formatShortDateTime(l['createdAt']),
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: OwnerTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
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

  Widget _buildFinanceTab() {
    final bankEvents = ((_dashboard?['recentBankEvents'] as List<dynamic>?) ?? [])
        .cast<Map<String, dynamic>>();
    final reservations =
        ((_dashboard?['recentReservations'] as List<dynamic>?) ?? [])
            .cast<Map<String, dynamic>>();

    return RefreshIndicator(
      onRefresh: () => _refreshDashboard(),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Notificaciones Bancarias Recibidas (Banco de Venezuela)',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(
            'Cada Pago Móvil entrante se coteja automáticamente por monto exacto en Bs., teléfono o referencia contra reservas, extensiones y consumos de pasaplatos.',
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
                    backgroundColor:
                        (matched ? OwnerTheme.available : OwnerTheme.cleaning)
                            .withValues(alpha: 0.18),
                    child: Icon(
                      matched ? Icons.bolt_rounded : Icons.schedule_rounded,
                      color:
                          matched ? OwnerTheme.available : OwnerTheme.cleaning,
                    ),
                  ),
                  title: Text(
                    'Bs. ${(ev['amountVes'] as num).toStringAsFixed(2)} · Ref ${ev['reference']}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    'Origen: ${ev['source']} · ${_formatShortDateTime(ev['receivedAt'])}',
                    style: const TextStyle(
                      color: OwnerTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color:
                          (matched ? OwnerTheme.available : OwnerTheme.cleaning)
                              .withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      matched ? 'Conciliado' : 'Sin asignar',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: matched
                            ? OwnerTheme.available
                            : OwnerTheme.cleaning,
                      ),
                    ),
                  ),
                ),
              );
            }),
          const SizedBox(height: 24),
          const Text(
            'Operaciones Recientes (Identidad del Huésped Protegida)',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          if (reservations.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'Sin operaciones registradas todavía.',
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
              final kind = (res['kind'] ?? 'STAY').toString();
              final kindLabel = kind == 'ROOM_SERVICE'
                  ? '🍾 Room Service'
                  : kind == 'EXTENSION'
                      ? '⏱ Extensión'
                      : '🔑 Estadía';
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
                              '$kindLabel · Suite ${room['name'] ?? ''} · \$${res['totalAmount']} USD',
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
                        'Estado: ${res['status']} · Salida: ${_formatShortDateTime(res['checkOut'])}',
                        style: const TextStyle(
                          color: OwnerTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      if (payment != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Monto Bs: ${payment['amountVes'] ?? 'N/D'} · Ref: ${payment['gatewayRef'] ?? 'Pendiente'}',
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
                                foregroundColor: Colors.black,
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
    final hotel = (_dashboard?['hotel'] as Map<String, dynamic>?) ?? {};
    final currentRate = hotel['currentExchangeRate'];

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
                      Icon(Icons.account_balance_rounded, color: OwnerTheme.gold),
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
                    'Los huéspedes transfieren directamente a tu cuenta sin intermediarios. '
                    'Con Banco de Venezuela (0102), las reservas, extensiones y consumos por pasaplatos se concilian solos.',
                    style: TextStyle(
                      color: OwnerTheme.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  if (currentRate != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: OwnerTheme.available.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: OwnerTheme.available.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.currency_exchange_rounded,
                            size: 18,
                            color: OwnerTheme.available,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Tasa BCV activa en el sistema: Bs. $currentRate / USD',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: OwnerTheme.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
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
                      labelText:
                          'Teléfono afiliado a Pago Móvil (ej: +584141234567)',
                      prefixIcon: Icon(Icons.phone_android_rounded),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _payIdCtrl,
                    decoration: const InputDecoration(
                      labelText: 'RIF o Cédula del Titular (ej: J-40123456-7)',
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
                  const SizedBox(height: 14),
                  TextField(
                    controller: _fallbackRateCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Tasa Bs/USD de Respaldo (opcional)',
                      prefixIcon: Icon(Icons.currency_exchange_rounded),
                    ),
                  ),
                  const SizedBox(height: 22),
                  ElevatedButton.icon(
                    onPressed: _savingPaymentInfo ? null : _savePaymentInfo,
                    icon: const Icon(Icons.save_rounded),
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

  Future<void> _configureAndroidBridge(bool enabled) async {
    final hotel = (_dashboard?['hotel'] as Map<String, dynamic>?) ?? {};
    final hotelId = (hotel['id'] ?? '').toString();
    final bridgeToken = (hotel['bdvBridgeToken'] ?? '').toString();
    final apiUrl = _bridgeApiUrlCtrl.text.trim();

    if (hotelId.isEmpty || bridgeToken.isEmpty || apiUrl.isEmpty) {
      _showSnack(
        'Faltan credenciales del puente o URL del servidor.',
        isError: true,
      );
      return;
    }

    try {
      final updated = await _bridgeService.configure(
        enabled: enabled,
        apiBaseUrl: apiUrl,
        hotelId: hotelId,
        bridgeToken: bridgeToken,
        allowTestSources: _bridgeAllowTestSources,
      );
      if (!mounted) return;
      setState(() => _bridgeStatus = updated);
      _showSnack(
        enabled
            ? 'Puente Android BDV activado en segundo plano.'
            : 'Puente Android BDV pausado.',
      );
    } catch (e) {
      _showSnack(e.toString(), isError: true);
    }
  }

  Future<void> _sendSimulatedBdvPush() async {
    final hotel = (_dashboard?['hotel'] as Map<String, dynamic>?) ?? {};
    final hotelId = (hotel['id'] ?? '').toString();
    final bridgeToken = (hotel['bdvBridgeToken'] ?? '').toString();
    final rawText = _simulatedPushCtrl.text.trim();

    if (hotelId.isEmpty || bridgeToken.isEmpty || rawText.isEmpty) {
      _showSnack('Escribe el texto de notificación BDV a enviar.', isError: true);
      return;
    }

    setState(() => _sendingSimulatedPush = true);
    try {
      final res = await widget.api.sendBdvPushWithBridgeToken(
        hotelId: hotelId,
        bridgeToken: bridgeToken,
        rawText: rawText,
      );
      final rec = res['reconciliation'] as Map<String, dynamic>?;
      final matched = rec?['matched'] == true;
      final zeroClick = rec?['zeroClick'] == true;
      _showSnack(
        matched
            ? (zeroClick
                ? '¡Conciliación Zero-Click! Operación aprobada sin referencia.'
                : 'Push BDV conciliado al instante y llave QR activa.')
            : 'Push BDV registrado (Bs. ${res['amountVes']} · Ref ${res['reference']}).',
      );
      await _refreshDashboard(silent: true);
    } catch (e) {
      _showSnack(e.toString(), isError: true);
    } finally {
      if (mounted) {
        setState(() => _sendingSimulatedPush = false);
      }
    }
  }

  Widget _buildBdvBridgeTab() {
    final hotel = (_dashboard?['hotel'] as Map<String, dynamic>?) ?? {};
    final isAndroid = BdvBridgeService.isAndroidNative;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.phonelink_ring_rounded,
                            color: OwnerTheme.gold,
                            size: 26,
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Agente Lector Android (NotificationListenerService)',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: (isAndroid &&
                                          _bridgeStatus.permissionGranted &&
                                          _bridgeStatus.enabled
                                      ? OwnerTheme.available
                                      : OwnerTheme.cleaning)
                                  .withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Text(
                              isAndroid
                                  ? (_bridgeStatus.permissionGranted &&
                                          _bridgeStatus.enabled
                                      ? 'Escuchando en 2do Plano'
                                      : 'Configuración Pendiente')
                                  : 'Modo Navegador Web',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isAndroid &&
                                        _bridgeStatus.permissionGranted &&
                                        _bridgeStatus.enabled
                                    ? OwnerTheme.available
                                    : OwnerTheme.cleaning,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        isAndroid
                            ? 'Este dispositivo captura las notificaciones push de BDVApp / PagoClave y las envía firmadas para "${hotel['name'] ?? 'tu hotel'}".'
                            : 'En el teléfono Android donde recibes tus Pago Móvil BDV, instala el APK de "StayPass Panel" para conciliación 24/7 con cola SQLite offline.',
                        style: const TextStyle(
                          color: OwnerTheme.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                      if (isAndroid) ...[
                        const SizedBox(height: 18),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _bridgeStatus.permissionGranted
                                  ? 'Permiso Notificaciones: Concedido'
                                  : 'Permiso Notificaciones: Pendiente',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: _bridgeStatus.permissionGranted
                                    ? OwnerTheme.available
                                    : OwnerTheme.cleaning,
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: () =>
                                  _bridgeService.openNotificationSettings(),
                              icon: const Icon(Icons.settings_outlined, size: 16),
                              label: const Text('Permisos Android'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _bridgeApiUrlCtrl,
                          decoration: const InputDecoration(
                            labelText: 'URL del Servidor API',
                            prefixIcon: Icon(Icons.cloud_outlined),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                            'Aceptar notificaciones de prueba (WhatsApp/SMS con formato BDV)',
                            style: TextStyle(fontSize: 13),
                          ),
                          value: _bridgeAllowTestSources,
                          onChanged: (val) {
                            setState(() => _bridgeAllowTestSources = val);
                          },
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: OwnerTheme.available,
                                foregroundColor: Colors.black,
                              ),
                              onPressed: () => _configureAndroidBridge(true),
                              icon: const Icon(Icons.play_arrow_rounded),
                              label: const Text('Activar Puente Android'),
                            ),
                            if (_bridgeStatus.enabled)
                              OutlinedButton.icon(
                                onPressed: () => _configureAndroidBridge(false),
                                icon: const Icon(Icons.pause_rounded),
                                label: const Text('Pausar'),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.bolt_rounded, color: OwnerTheme.available),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Simulador en Vivo de Push BDV (x-hotel-bridge-token)',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Envía una notificación push BDV firmada para probar la conciliación Zero-Click en vivo sobre reservas, extensiones o consumos de pasaplatos.',
                        style: TextStyle(
                          color: OwnerTheme.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _simulatedPushCtrl,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Texto crudo de la notificación push BDV',
                          prefixIcon: Icon(Icons.notifications_active_outlined),
                        ),
                      ),
                      const SizedBox(height: 14),
                      ElevatedButton.icon(
                        onPressed:
                            _sendingSimulatedPush ? null : _sendSimulatedBdvPush,
                        icon: const Icon(Icons.send_to_mobile_rounded),
                        label: const Text('Disparar Push BDV al Webhook'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
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
                        fontWeight: FontWeight.w800,
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
