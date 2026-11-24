import 'dart:async';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/bdv_bridge_service.dart';
import '../core/owner_api.dart';
import '../core/owner_theme.dart';
import '../core/smart_photo.dart';

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
  bool _bridgeAllowTestSources = false;
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
  Timer? _periodicSyncTimer;

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
    // Sincronización continua de respaldo (cada 4s) para reflejar cambios en tiempo real de camareras/recepción
    _periodicSyncTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted) _refreshDashboard(silent: true);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _periodicSyncTimer?.cancel();
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
          style: const TextStyle(
            color: Colors.white,
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

    String selectedRole = 'RECEPTIONIST';
    final nameCtrl = TextEditingController();
    final identifierCtrl = TextEditingController(); // username or alias
    final secretCtrl = TextEditingController(); // password or pin
    final phoneCtrl = TextEditingController();
    final emailCtrl = TextEditingController();

    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          backgroundColor: OwnerTheme.card,
          title: Row(
            children: [
              Icon(
                selectedRole == 'RECEPTIONIST'
                    ? Icons.support_agent_rounded
                    : Icons.cleaning_services_rounded,
                color: selectedRole == 'RECEPTIONIST'
                    ? OwnerTheme.gold
                    : OwnerTheme.cleaning,
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Crear Cuenta de Personal',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Seleccione el tipo de cuenta para este colaborador. Ambos tipos inician sesión desde el portal único (localhost:8081).',
                    style: TextStyle(fontSize: 12.5, color: OwnerTheme.textSecondary),
                  ),
                  const SizedBox(height: 14),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment<String>(
                        value: 'RECEPTIONIST',
                        icon: Icon(Icons.support_agent_outlined, size: 18),
                        label: Text('Recepcionista'),
                      ),
                      ButtonSegment<String>(
                        value: 'CLEANING',
                        icon: Icon(Icons.cleaning_services_outlined, size: 18),
                        label: Text('Limpieza'),
                      ),
                    ],
                    selected: {selectedRole},
                    onSelectionChanged: (newSelection) {
                      setDlgState(() {
                        selectedRole = newSelection.first;
                        identifierCtrl.clear();
                        secretCtrl.clear();
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      labelText: selectedRole == 'RECEPTIONIST'
                          ? 'Nombre Completo del Recepcionista'
                          : 'Nombre o Identificador (ej: Turno Mañana)',
                      prefixIcon: const Icon(Icons.badge_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: identifierCtrl,
                    decoration: InputDecoration(
                      labelText: selectedRole == 'RECEPTIONIST'
                          ? 'Usuario de Acceso (ej: juan.recepcion)'
                          : 'Alias Único (ej: camarera1)',
                      prefixIcon: const Icon(Icons.account_circle_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: secretCtrl,
                    obscureText: true,
                    keyboardType: selectedRole == 'CLEANING'
                        ? TextInputType.number
                        : TextInputType.text,
                    decoration: InputDecoration(
                      labelText: selectedRole == 'RECEPTIONIST'
                          ? 'Contraseña (mínimo 6 caracteres)'
                          : 'PIN Numérico (4 a 6 dígitos)',
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                    ),
                  ),
                  if (selectedRole == 'RECEPTIONIST') ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: phoneCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Teléfono de Contacto (opcional)',
                        prefixIcon: Icon(Icons.phone_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Correo Electrónico (opcional)',
                        prefixIcon: Icon(Icons.alternate_email_outlined),
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: OwnerTheme.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: OwnerTheme.border),
                    ),
                    child: Text(
                      selectedRole == 'RECEPTIONIST'
                          ? 'ℹ️ El recepcionista puede asistir a clientes, validar pagos manuales en contingencia, destrabar cerraduras o barreras FAAC y gestionar entregas.'
                          : 'ℹ️ El personal de limpieza solo tiene acceso a las habitaciones a limpiar, cuenta regresiva de checkout (<15 min) y pasaplatos.',
                      style: TextStyle(fontSize: 11.5, color: OwnerTheme.textSecondary),
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
                final idVal = identifierCtrl.text.trim();
                final secret = secretCtrl.text.trim();

                if (name.isEmpty || idVal.isEmpty || secret.isEmpty) {
                  _showSnack('Por favor complete todos los campos obligatorios.', isError: true);
                  return;
                }

                try {
                  await widget.api.createStaff(
                    hotelId: hotelId,
                    role: selectedRole,
                    name: name,
                    alias: selectedRole == 'CLEANING' ? idVal : null,
                    username: selectedRole == 'RECEPTIONIST' ? idVal : null,
                    pin: selectedRole == 'CLEANING' ? secret : null,
                    password: selectedRole == 'RECEPTIONIST' ? secret : null,
                    phone: phoneCtrl.text.trim().isNotEmpty ? phoneCtrl.text.trim() : null,
                    email: emailCtrl.text.trim().isNotEmpty ? emailCtrl.text.trim() : null,
                  );
                  if (ctx.mounted) Navigator.of(ctx).pop(true);
                } catch (e) {
                  _showSnack(e.toString(), isError: true);
                }
              },
              child: const Text('Crear Cuenta'),
            ),
          ],
        ),
      ),
    );

    if (created == true) {
      _showSnack('Cuenta de personal creada exitosamente.');
      await _refreshDashboard();
    }
  }

  Future<void> _deleteStaff(String staffId) async {
    final hotelId = _selectedHotelId;
    if (hotelId == null) return;
    try {
      await widget.api.deleteStaff(hotelId: hotelId, staffId: staffId);
      _showSnack('Credencial revocada con éxito.');
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

  static const List<Map<String, String>> _sampleRoomPhotos = [
    {
      'label': 'Suite King Boutique',
      'url':
          'https://images.unsplash.com/photo-1618773928121-c32242e63f39?auto=format&fit=crop&w=900&q=80',
    },
    {
      'label': 'Jacuzzi & Spa',
      'url':
          'https://images.unsplash.com/photo-1584622650111-993a426fbf0a?auto=format&fit=crop&w=900&q=80',
    },
    {
      'label': 'Habitación Cálida',
      'url':
          'https://images.unsplash.com/photo-1631049307264-da0ec9d70304?auto=format&fit=crop&w=900&q=80',
    },
    {
      'label': 'Lounge & Minibar',
      'url':
          'https://images.unsplash.com/photo-1560448204-603b3fc33ddc?auto=format&fit=crop&w=900&q=80',
    },
  ];

  static const List<Map<String, String>> _sampleHotelPhotos = [
    {
      'label': 'Fachada Boutique',
      'url':
          'https://images.unsplash.com/photo-1566073771259-6a8506099945?auto=format&fit=crop&w=1000&q=80',
    },
    {
      'label': 'Lobby & Recepción',
      'url':
          'https://images.unsplash.com/photo-1582719508461-905c673771fd?auto=format&fit=crop&w=1000&q=80',
    },
    {
      'label': 'Exterior Nocturno',
      'url':
          'https://images.unsplash.com/photo-1542314831-068cd1dbfeeb?auto=format&fit=crop&w=1000&q=80',
    },
  ];

  Future<String?> _pickImageAsDataUrl() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return null;
      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) return null;
      if (bytes.length > 4 * 1024 * 1024) {
        _showSnack(
          'La imagen supera 4 MB. Elige una foto más ligera o usa un enlace.',
          isError: true,
        );
        return null;
      }
      final ext = (file.extension ?? 'jpg').toLowerCase();
      final mime = ext == 'png'
          ? 'image/png'
          : ext == 'webp'
              ? 'image/webp'
              : 'image/jpeg';
      return 'data:$mime;base64,${base64Encode(bytes)}';
    } on Object catch (e) {
      _showSnack('No se pudo abrir el archivo: $e', isError: true);
      return null;
    }
  }

  Future<void> _openHotelPhotosDialog() async {
    final hotel = (_dashboard?['hotel'] as Map<String, dynamic>?) ?? {};
    final hotelId = _selectedHotelId;
    if (hotelId == null) return;

    final existingCover = (hotel['coverPhoto'] ?? '').toString().trim();
    final existingList = ((hotel['photos'] as List<dynamic>?) ?? [])
        .map((e) => e.toString().trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final List<String> photos = [
      if (existingCover.isNotEmpty && !existingList.contains(existingCover))
        existingCover,
      ...existingList,
    ];
    final descCtrl = TextEditingController(
      text: (hotel['description'] ?? '').toString(),
    );
    final urlCtrl = TextEditingController();

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        bool saving = false;
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: OwnerTheme.card,
              title: Row(
                children: [
                  Icon(Icons.photo_library_outlined, color: OwnerTheme.gold),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text('Fotos y Portada del Hotel'),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 500),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Sube fotos de la fachada, estacionamiento o áreas comunes para que el cliente conozca el hotel antes de reservar. La primera foto será la portada principal.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: OwnerTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 14),
                      if (photos.isEmpty)
                        Container(
                          height: 110,
                          decoration: BoxDecoration(
                            color: OwnerTheme.surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: OwnerTheme.border),
                          ),
                          child: Center(
                            child: Text(
                              'Sin fotos del hotel aún. Sube una desde tu dispositivo o pega un enlace.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                color: OwnerTheme.textSecondary,
                              ),
                            ),
                          ),
                        )
                      else
                        SizedBox(
                          height: 125,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: photos.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 10),
                            itemBuilder: (_, idx) {
                              final src = photos[idx];
                              return Stack(
                                children: [
                                  Container(
                                    width: 165,
                                    height: 125,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: idx == 0
                                            ? OwnerTheme.gold
                                            : OwnerTheme.border,
                                        width: idx == 0 ? 2 : 1,
                                      ),
                                    ),
                                    child: SmartPhoto(
                                      source: src,
                                      width: 165,
                                      height: 125,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  if (idx == 0)
                                    Positioned(
                                      bottom: 6,
                                      left: 6,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.black
                                              .withValues(alpha: 0.72),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          'PORTADA',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w800,
                                            color: OwnerTheme.gold,
                                          ),
                                        ),
                                      ),
                                    ),
                                  Positioned(
                                    top: 6,
                                    right: 6,
                                    child: InkWell(
                                      onTap: () {
                                        setDialogState(() {
                                          photos.removeAt(idx);
                                        });
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: Colors.black
                                              .withValues(alpha: 0.7),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.close_rounded,
                                          size: 15,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: OwnerTheme.cyan,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () async {
                              final dataUrl = await _pickImageAsDataUrl();
                              if (dataUrl != null) {
                                setDialogState(() => photos.add(dataUrl));
                              }
                            },
                            icon: const Icon(
                              Icons.upload_file_rounded,
                              size: 17,
                            ),
                            label: const Text('Subir Foto desde Dispositivo'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: urlCtrl,
                              decoration: const InputDecoration(
                                labelText: 'O pegar URL de imagen (https://...)',
                                prefixIcon: Icon(Icons.link_rounded),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: () {
                              final u = urlCtrl.text.trim();
                              if (u.isNotEmpty) {
                                setDialogState(() {
                                  photos.add(u);
                                  urlCtrl.clear();
                                });
                              }
                            },
                            child: const Text('Añadir'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Galería rápida de muestra (1 clic):',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: OwnerTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: _sampleHotelPhotos.map((sample) {
                          return ActionChip(
                            avatar: Icon(
                              Icons.add_photo_alternate_outlined,
                              size: 15,
                              color: OwnerTheme.gold,
                            ),
                            label: Text(
                              sample['label']!,
                              style: const TextStyle(fontSize: 11.5),
                            ),
                            onPressed: () {
                              final u = sample['url']!;
                              if (!photos.contains(u)) {
                                setDialogState(() => photos.add(u));
                              }
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: descCtrl,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Descripción breve del hotel',
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
                ElevatedButton.icon(
                  onPressed: saving
                      ? null
                      : () async {
                          setDialogState(() => saving = true);
                          try {
                            await widget.api.updateHotelPhotos(
                              hotelId: hotelId,
                              coverPhoto:
                                  photos.isNotEmpty ? photos.first : null,
                              photos: photos,
                              description: descCtrl.text.trim(),
                            );
                            if (ctx.mounted) Navigator.of(ctx).pop(true);
                          } on Object catch (e) {
                            setDialogState(() => saving = false);
                            _showSnack(e.toString(), isError: true);
                          }
                        },
                  icon: const Icon(Icons.save_outlined, size: 17),
                  label: const Text('Guardar Fotos del Hotel'),
                ),
              ],
            );
          },
        );
      },
    );

    if (saved == true) {
      _showSnack('Fotos del hotel actualizadas.');
      await _refreshDashboard();
    }
  }

  Future<void> _openRoomEditorDialog({Map<String, dynamic>? existingRoom}) async {
    final hotelId = _selectedHotelId;
    if (hotelId == null) return;

    final isEditing = existingRoom != null;
    final nameCtrl = TextEditingController(
      text: isEditing ? (existingRoom['name'] ?? '').toString() : '',
    );
    final descCtrl = TextEditingController(
      text: isEditing
          ? (existingRoom['description'] ?? '').toString()
          : 'Espacio boutique con total discreción, climatización independiente, estacionamiento privado con barrera QR y servicio por pasaplatos.',
    );
    final hourPriceCtrl = TextEditingController(
      text: isEditing ? (existingRoom['pricePerHour'] ?? '15').toString() : '15',
    );
    final nightPriceCtrl = TextEditingController(
      text:
          isEditing ? (existingRoom['pricePerNight'] ?? '45').toString() : '45',
    );
    final existingAmenities =
        ((existingRoom?['amenities'] as List<dynamic>?) ?? [])
            .map((e) => e.toString())
            .toList();
    final amenitiesCtrl = TextEditingController(
      text: isEditing && existingAmenities.isNotEmpty
          ? existingAmenities.join(', ')
          : 'Aire acondicionado, TV, Estacionamiento privado, Pasaplatos',
    );
    final List<String> photos =
        ((existingRoom?['photos'] as List<dynamic>?) ?? [])
            .map((e) => e.toString().trim())
            .where((s) => s.isNotEmpty)
            .toList();
    final photoUrlCtrl = TextEditingController();

    String selectedType = isEditing
        ? (existingRoom['type'] ?? 'SUITE').toString()
        : 'SUITE';
    if (!const ['STANDARD', 'DELUXE', 'SUITE', 'PREMIUM']
        .contains(selectedType)) {
      selectedType = 'SUITE';
    }

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        bool saving = false;
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: OwnerTheme.card,
              title: Row(
                children: [
                  Icon(
                    isEditing
                        ? Icons.photo_camera_back_outlined
                        : Icons.add_home_work_outlined,
                    color: OwnerTheme.gold,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      isEditing
                          ? 'Fotos y Detalles · Suite ${existingRoom['name']}'
                          : 'Nueva Habitación / Suite',
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Sección destacada de Fotografías de la Habitación
                      Text(
                        'Fotografías de la Habitación (${photos.length})',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Estas fotos se muestran al cliente en el catálogo y en la vista previa antes de reservar.',
                        style: TextStyle(
                          fontSize: 12,
                          color: OwnerTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (photos.isEmpty)
                        Container(
                          height: 100,
                          decoration: BoxDecoration(
                            color: OwnerTheme.surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: OwnerTheme.border),
                          ),
                          child: Center(
                            child: Text(
                              'Sin fotos aún. Sube una imagen o elige una de muestra abajo.',
                              style: TextStyle(
                                fontSize: 12,
                                color: OwnerTheme.textSecondary,
                              ),
                            ),
                          ),
                        )
                      else
                        SizedBox(
                          height: 115,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: photos.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 10),
                            itemBuilder: (_, idx) {
                              return Stack(
                                children: [
                                  Container(
                                    width: 150,
                                    height: 115,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: idx == 0
                                            ? OwnerTheme.gold
                                            : OwnerTheme.border,
                                        width: idx == 0 ? 2 : 1,
                                      ),
                                    ),
                                    child: SmartPhoto(
                                      source: photos[idx],
                                      width: 150,
                                      height: 115,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  if (idx == 0)
                                    Positioned(
                                      bottom: 6,
                                      left: 6,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 7,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.black
                                              .withValues(alpha: 0.72),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          'PRINCIPAL',
                                          style: TextStyle(
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w800,
                                            color: OwnerTheme.gold,
                                          ),
                                        ),
                                      ),
                                    ),
                                  Positioned(
                                    top: 5,
                                    right: 5,
                                    child: InkWell(
                                      onTap: () {
                                        setDialogState(() {
                                          photos.removeAt(idx);
                                        });
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: Colors.black
                                              .withValues(alpha: 0.7),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.close_rounded,
                                          size: 14,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: OwnerTheme.cyan,
                              foregroundColor: Colors.white,
                              minimumSize: const Size(180, 38),
                            ),
                            onPressed: () async {
                              final dataUrl = await _pickImageAsDataUrl();
                              if (dataUrl != null) {
                                setDialogState(() => photos.add(dataUrl));
                              }
                            },
                            icon: const Icon(
                              Icons.upload_file_rounded,
                              size: 16,
                            ),
                            label: const Text('Subir Foto desde Dispositivo'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: photoUrlCtrl,
                              decoration: const InputDecoration(
                                labelText: 'O pegar URL de foto (https://...)',
                                prefixIcon: Icon(Icons.link_rounded),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: () {
                              final u = photoUrlCtrl.text.trim();
                              if (u.isNotEmpty) {
                                setDialogState(() {
                                  photos.add(u);
                                  photoUrlCtrl.clear();
                                });
                              }
                            },
                            child: const Text('Añadir'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: _sampleRoomPhotos.map((sample) {
                          return ActionChip(
                            avatar: Icon(
                              Icons.add_photo_alternate_outlined,
                              size: 14,
                              color: OwnerTheme.gold,
                            ),
                            label: Text(
                              sample['label']!,
                              style: const TextStyle(fontSize: 11),
                            ),
                            onPressed: () {
                              final u = sample['url']!;
                              if (!photos.contains(u)) {
                                setDialogState(() => photos.add(u));
                              }
                            },
                          );
                        }).toList(),
                      ),
                      const Divider(height: 24),
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
                        controller: descCtrl,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Descripción para el cliente',
                        ),
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
                ElevatedButton.icon(
                  onPressed: saving
                      ? null
                      : () async {
                          final name = nameCtrl.text.trim();
                          final perHour =
                              double.tryParse(hourPriceCtrl.text.trim());
                          final perNight =
                              double.tryParse(nightPriceCtrl.text.trim());
                          if (name.isEmpty ||
                              perHour == null ||
                              perNight == null) {
                            return;
                          }
                          final amenities = amenitiesCtrl.text
                              .split(',')
                              .map((s) => s.trim())
                              .where((s) => s.isNotEmpty)
                              .toList();
                          setDialogState(() => saving = true);
                          try {
                            if (isEditing) {
                              await widget.api.updateRoom(
                                roomId: existingRoom['id'].toString(),
                                name: name,
                                type: selectedType,
                                pricePerHour: perHour,
                                pricePerNight: perNight,
                                amenities: amenities,
                                description: descCtrl.text.trim(),
                                photos: photos,
                              );
                            } else {
                              await widget.api.createRoom(
                                hotelId: hotelId,
                                name: name,
                                type: selectedType,
                                pricePerHour: perHour,
                                pricePerNight: perNight,
                                amenities: amenities,
                                description: descCtrl.text.trim(),
                                photos: photos,
                              );
                            }
                            if (ctx.mounted) Navigator.of(ctx).pop(true);
                          } on Object catch (e) {
                            setDialogState(() => saving = false);
                            _showSnack(e.toString(), isError: true);
                          }
                        },
                  icon: const Icon(Icons.save_outlined, size: 17),
                  label: Text(isEditing ? 'Guardar Cambios' : 'Crear Suite'),
                ),
              ],
            );
          },
        );
      },
    );

    if (saved == true) {
      _showSnack(
        isEditing
            ? 'Fotos y datos de la suite actualizados'
            : 'Suite creada exitosamente',
      );
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
    if (confirm) {
      await _openManualPaymentDialog(preselectedPaymentId: paymentId);
      return;
    }

    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Rechazar comprobante?'),
        content: const Text(
          'Esta acción marcará el pago como fallido y cancelará la reserva asociada.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Volver'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: OwnerTheme.occupied,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Rechazar Pago'),
          ),
        ],
      ),
    );

    if (proceed != true) return;

    try {
      await widget.api.rejectPaymentManually(paymentId);
      _showSnack('Pago rechazado y reserva cancelada.');
      await _refreshDashboard();
    } catch (e) {
      _showSnack(e.toString(), isError: true);
    }
  }

  Future<void> _openManualPaymentDialog({
    String? preselectedPaymentId,
    Map<String, dynamic>? paymentData,
    String? roomName,
    String? guestDesc,
  }) async {
    final reservations =
        ((_dashboard?['recentReservations'] as List<dynamic>?) ?? [])
            .cast<Map<String, dynamic>>();

    final pendingList = reservations.where((r) {
      final p = r['payment'];
      return p != null &&
          (p['status'] == 'PENDING' || p['status'] == 'PENDING_REVIEW');
    }).toList();

    if (preselectedPaymentId == null && pendingList.isEmpty) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.check_circle_outline, color: OwnerTheme.available),
              const SizedBox(width: 8),
              const Text('Sin pagos pendientes'),
            ],
          ),
          content: const Text(
            'En este momento no hay reservas esperando verificación de pago. Todas las reservas activas están al día.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Entendido'),
            ),
          ],
        ),
      );
      return;
    }

    String chosenPaymentId = preselectedPaymentId ??
        (pendingList.isNotEmpty
            ? pendingList.first['payment']['id'].toString()
            : '');

    Map<String, dynamic>? currentRes;
    if (preselectedPaymentId != null) {
      currentRes = reservations.firstWhere(
        (r) => r['payment']?['id'] == preselectedPaymentId,
        orElse: () => <String, dynamic>{},
      );
    } else if (pendingList.isNotEmpty) {
      currentRes = pendingList.first;
    }

    String selectedGateway = 'PAGO_MOVIL';
    String selectedReason = 'Notificaciones BDV inactivas / en mantenimiento';
    final refCtrl = TextEditingController(
      text: (paymentData?['gatewayRef'] ??
              currentRes?['payment']?['gatewayRef'] ??
              '')
          .toString(),
    );
    final notesCtrl = TextEditingController();
    bool isSubmitting = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            final activePay = currentRes?['payment'];
            final activeRoom = currentRes?['room']?['name']?.toString() ??
                roomName ??
                'Habitación';
            final activeVes = activePay?['amountVes'] != null
                ? 'Bs. ${(activePay!['amountVes'] as num).toStringAsFixed(2)}'
                : 'Monto por calcular';
            final activeUsd = currentRes?['totalAmount'] != null
                ? '\$${(currentRes!['totalAmount'] as num).toStringAsFixed(2)}'
                : '';

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: OwnerTheme.gold.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.handshake_outlined,
                      color: OwnerTheme.gold,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Registro Manual de Pago',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 480,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: OwnerTheme.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: OwnerTheme.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Habitación $activeRoom',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: OwnerTheme.available.withValues(
                                      alpha: 0.2,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '$activeUsd ($activeVes)',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12.5,
                                      color: OwnerTheme.available,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (guestDesc != null && guestDesc.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                guestDesc,
                                style: TextStyle(
                                  color: OwnerTheme.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (preselectedPaymentId == null &&
                          pendingList.length > 1) ...[
                        const SizedBox(height: 14),
                        const Text(
                          'Seleccionar Reserva Pendiente:',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        DropdownButtonFormField<String>(
                          value: chosenPaymentId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          items: pendingList.map((r) {
                            final p = r['payment'];
                            final rm = r['room']?['name'] ?? 'Hab';
                            final pid = p['id'].toString();
                            return DropdownMenuItem<String>(
                              value: pid,
                              child: Text(
                                'Hab. $rm · \$${r['totalAmount']} (ID: ${pid.substring(0, 8)})',
                              ),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val == null) return;
                            setDialogState(() {
                              chosenPaymentId = val;
                              currentRes = pendingList.firstWhere(
                                (r) => r['payment']?['id'] == val,
                                orElse: () => <String, dynamic>{},
                              );
                              refCtrl.text =
                                  (currentRes?['payment']?['gatewayRef'] ?? '')
                                      .toString();
                            });
                          },
                        ),
                      ],
                      const SizedBox(height: 16),
                      const Text(
                        'Método de Pago Utilizado:',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        value: selectedGateway,
                        decoration: const InputDecoration(
                          isDense: true,
                          prefixIcon: Icon(Icons.payment_outlined, size: 19),
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'PAGO_MOVIL',
                            child: Text('Pago Móvil (Comprobante / WhatsApp)'),
                          ),
                          DropdownMenuItem(
                            value: 'CASH',
                            child: Text('Efectivo en Recepción (USD / Bs)'),
                          ),
                          DropdownMenuItem(
                            value: 'ZELLE',
                            child: Text('Zelle USD'),
                          ),
                          DropdownMenuItem(
                            value: 'BINANCE_PAY',
                            child: Text('Binance Pay / Cripto'),
                          ),
                        ],
                        onChanged: (val) {
                          if (val == null) return;
                          setDialogState(() {
                            selectedGateway = val;
                            if (val == 'CASH' && refCtrl.text.isEmpty) {
                              refCtrl.text = 'EFECTIVO-REC';
                            }
                          });
                        },
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: refCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Referencia / N° de Comprobante *',
                          hintText: 'Ej: 00998811 o EFECTIVO',
                          prefixIcon: Icon(Icons.tag_rounded, size: 19),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Causa de Contingencia / Observación:',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        value: selectedReason,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value:
                                'Notificaciones BDV inactivas / en mantenimiento',
                            child: Text('Notificaciones BDV en mantenimiento'),
                          ),
                          DropdownMenuItem(
                            value:
                                'Comprobante verificado por WhatsApp / captura',
                            child: Text('Comprobante verificado por WhatsApp'),
                          ),
                          DropdownMenuItem(
                            value: 'Pago en efectivo recibido en recepción',
                            child: Text('Pago en efectivo en recepción'),
                          ),
                          DropdownMenuItem(
                            value: 'Transferencia externa de otro banco',
                            child: Text('Transferencia de otro banco'),
                          ),
                          DropdownMenuItem(
                            value:
                                'Aprobación de cortesía o ajuste administrativo',
                            child: Text('Aprobación de cortesía / ajuste'),
                          ),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() => selectedReason = val);
                          }
                        },
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: notesCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Nota interna adicional (opcional)',
                          hintText:
                              'Ej: Recibido por recepcionista turno mañana',
                          prefixIcon: Icon(Icons.note_alt_outlined, size: 19),
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.pop(ctx),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: OwnerTheme.available,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          final ref = refCtrl.text.trim();
                          if (ref.isEmpty) {
                            _showSnack(
                              'Por favor ingresa un número de referencia o identificador',
                              isError: true,
                            );
                            return;
                          }
                          setDialogState(() => isSubmitting = true);
                          try {
                            final notesCombined =
                                notesCtrl.text.trim().isNotEmpty
                                    ? '${notesCtrl.text.trim()} (Causa: $selectedReason)'
                                    : 'Causa: $selectedReason';

                            await widget.api.confirmPaymentManually(
                              chosenPaymentId,
                              gateway: selectedGateway,
                              gatewayRef: ref,
                              notes: notesCombined,
                              reason: selectedReason,
                            );

                            if (ctx.mounted) Navigator.pop(ctx);
                            _showSnack(
                              '¡Pago confirmado! La habitación fue activada y el QR del huésped está listo.',
                            );
                            await _refreshDashboard();
                          } catch (err) {
                            setDialogState(() => isSubmitting = false);
                            _showSnack(err.toString(), isError: true);
                          }
                        },
                  icon: isSubmitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check_circle_outline, size: 18),
                  label: Text(
                    isSubmitting ? 'Procesando...' : 'Confirmar y Activar QR',
                  ),
                ),
              ],
            );
          },
        );
      },
    );
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
              Icon(Icons.shield_moon_rounded, color: OwnerTheme.gold),
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
                                    style: TextStyle(
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
                  _sseLive ? '● En línea' : '● Sync',
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
            OwnerTheme.themeToggleButton(),
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
            dividerColor: OwnerTheme.border,
            tabs: [
              const Tab(
                icon: Icon(Icons.grid_view_rounded, size: 19),
                text: 'Suites y Estado',
              ),
              Tab(
                icon: Badge(
                  backgroundColor: OwnerTheme.gold,
                  isLabelVisible: pendingDeliveriesCount > 0,
                  label: Text(
                    '$pendingDeliveriesCount',
                    style: TextStyle(
                      color: OwnerTheme.onPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  child: const Icon(
                    Icons.directions_car_filled_outlined,
                    size: 19,
                  ),
                ),
                text: 'Operaciones y Barreras',
              ),
              const Tab(
                icon: Icon(Icons.payments_outlined, size: 19),
                text: 'Ingresos y Pagos',
              ),
              const Tab(
                icon: Icon(Icons.phonelink_ring_rounded, size: 19),
                text: 'Puente Android',
              ),
              const Tab(
                icon: Icon(Icons.account_balance_rounded, size: 19),
                text: 'Datos de Cobro',
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
              Icon(
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
                    Icon(
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
                          style: TextStyle(
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
                        foregroundColor: Colors.white,
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
                        side: BorderSide(color: OwnerTheme.cyan),
                        minimumSize: const Size(146, 40),
                      ),
                      onPressed: _pulsingFaac
                          ? null
                          : () => _manualFaacPulse('EXIT'),
                      icon: Icon(
                        Icons.logout_rounded,
                        size: 17,
                        color: OwnerTheme.cyan,
                      ),
                      label: Text(
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
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _openHotelPhotosDialog,
                    icon: Icon(
                      Icons.photo_library_outlined,
                      size: 17,
                      color: OwnerTheme.gold,
                    ),
                    label: const Text('Fotos del Hotel'),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => _openRoomEditorDialog(),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Nueva Suite'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (filteredRooms.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
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
    final photos = ((room['photos'] as List<dynamic>?) ?? [])
        .map((e) => e.toString().trim())
        .where((s) => s.isNotEmpty)
        .toList();

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            onTap: () => _openRoomEditorDialog(existingRoom: room),
            child: Stack(
              children: [
                SizedBox(
                  height: 135,
                  width: double.infinity,
                  child: photos.isNotEmpty
                      ? SmartPhoto(
                          source: photos.first,
                          height: 135,
                          width: double.infinity,
                        )
                      : Container(
                          color: OwnerTheme.surface,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.add_a_photo_outlined,
                                color: OwnerTheme.textSecondary,
                                size: 28,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Toca para subir fotos de esta habitación',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: OwnerTheme.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
                Positioned(
                  bottom: 8,
                  right: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.photo_camera_outlined,
                          size: 13.5,
                          color: OwnerTheme.gold,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          photos.isEmpty
                              ? 'Subir Fotos'
                              : '${photos.length} foto${photos.length > 1 ? "s" : ""}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
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
                  style: TextStyle(
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
                          style: TextStyle(
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
                      color: (expiringSoon
                              ? OwnerTheme.cleaning
                              : OwnerTheme.occupied)
                          .withValues(alpha: 0.13),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: (expiringSoon
                                ? OwnerTheme.cleaning
                                : OwnerTheme.occupied)
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
                            style: TextStyle(
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
                    OutlinedButton.icon(
                      onPressed: () =>
                          _openRoomEditorDialog(existingRoom: room),
                      icon: Icon(
                        Icons.add_a_photo_outlined,
                        size: 15,
                        color: OwnerTheme.gold,
                      ),
                      label: const Text('Fotos / Editar'),
                    ),
                    if (status != 'AVAILABLE' && status != 'OCCUPIED')
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: OwnerTheme.available,
                          foregroundColor: Colors.white,
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
                        icon: const Icon(
                          Icons.cleaning_services_outlined,
                          size: 15,
                        ),
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
        ],
      ),
    );
  }

  Widget _buildOperationsTab() {
    final hotel = (_dashboard?['hotel'] as Map<String, dynamic>?) ?? {};
    final cleaningStaff = ((hotel['cleaningStaff'] as List<dynamic>?) ?? [])
        .cast<Map<String, dynamic>>();
    final receptionStaff = ((hotel['receptionStaff'] as List<dynamic>?) ?? [])
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
                  Row(
                    children: [
                      Icon(Icons.room_service_rounded, color: OwnerTheme.gold),
                      const SizedBox(width: 10),
                      const Expanded(
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
                  Text(
                    'Pedidos ya pagados con Pago Móvil BDV desde la habitación. Al marcarlos como entregados, el teléfono del huésped recibe aviso en vivo.',
                    style: TextStyle(
                      color: OwnerTheme.textSecondary,
                      fontSize: 12.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (pendingDeliveries.isEmpty)
                    Text(
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
                                      style: TextStyle(
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
                                foregroundColor: Colors.white,
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
                      Row(
                        children: [
                          Icon(
                            Icons.directions_car_filled_rounded,
                            color: OwnerTheme.cyan,
                          ),
                          const SizedBox(width: 10),
                          const Text(
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
                  Text(
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
                            Expanded(
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
                          Text(
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
                                    style: TextStyle(
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
                                      child: Text(
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
                              icon: Icon(
                                Icons.network_check_rounded,
                                size: 17,
                                color: OwnerTheme.cyan,
                              ),
                              label: Text(
                                _testingRelay
                                    ? 'Probando Relé...'
                                    : 'Diagnóstico Relé IP (Dry-Run)',
                                style: TextStyle(color: OwnerTheme.cyan),
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: _copyEsp32ProvisioningHeader,
                              icon: Icon(
                                Icons.copy_all_rounded,
                                size: 17,
                                color: OwnerTheme.gold,
                              ),
                              label: Text(
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

          // 3. Gestión de Personal (Recepcionistas y Limpieza)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Icon(
                              Icons.manage_accounts_rounded,
                              color: OwnerTheme.gold,
                              size: 26,
                            ),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                'Personal & Cuentas Operativas (Recepción y Limpieza)',
                                style: TextStyle(
                                  fontSize: 16.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: _openCreateStaffDialog,
                        icon: const Icon(Icons.person_add_alt_1_rounded, size: 17),
                        label: const Text('Crear Personal'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: OwnerTheme.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: OwnerTheme.border),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.vpn_key_rounded, size: 16, color: Colors.blueAccent),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Código de este hotel para inicio de sesión en el portal único (localhost:8081): ${hotel['slug'] ?? hotel['id'] ?? ''}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Recepcionistas
                  Row(
                    children: [
                      Icon(Icons.support_agent_rounded, size: 18, color: OwnerTheme.gold),
                      const SizedBox(width: 8),
                      const Text(
                        'Recepcionistas / Soporte de Emergencia',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: OwnerTheme.gold.withAlpha(40),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${receptionStaff.length}',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: OwnerTheme.gold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (receptionStaff.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 12),
                      child: Text(
                        'No hay recepcionistas registrados. Cree uno para asistir clientes cuando la automatización falle.',
                        style: TextStyle(color: OwnerTheme.textSecondary, fontSize: 12.5),
                      ),
                    )
                  else
                    for (final r in receptionStaff)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: OwnerTheme.surface,
                          child: Icon(
                            Icons.support_agent_rounded,
                            color: OwnerTheme.gold,
                          ),
                        ),
                        title: Text(
                          '${r['name']} · Usuario: ${r['username']}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          'Teléfono: ${r['phone'] ?? 'N/A'} · Email: ${r['email'] ?? 'N/A'} · Asistencia de puertas, pagos y FAAC',
                          style: TextStyle(
                            fontSize: 12,
                            color: OwnerTheme.textSecondary,
                          ),
                        ),
                        trailing: IconButton(
                          tooltip: 'Revocar recepcionista',
                          onPressed: () => _deleteStaff(r['id'].toString()),
                          icon: Icon(
                            Icons.delete_outline_rounded,
                            color: OwnerTheme.occupied,
                          ),
                        ),
                      ),

                  const Divider(height: 28),

                  // Personal de Limpieza
                  Row(
                    children: [
                      Icon(Icons.cleaning_services_rounded, size: 18, color: OwnerTheme.cleaning),
                      const SizedBox(width: 8),
                      const Text(
                        'Personal de Camarería / Limpieza (Cero Finanzas)',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: OwnerTheme.cleaning.withAlpha(40),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${cleaningStaff.length}',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: OwnerTheme.cleaning),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (cleaningStaff.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Text(
                        'No hay personal de limpieza registrado.',
                        style: TextStyle(color: OwnerTheme.textSecondary, fontSize: 12.5),
                      ),
                    )
                  else
                    for (final s in cleaningStaff)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: OwnerTheme.surface,
                          child: Icon(
                            Icons.badge_outlined,
                            color: OwnerTheme.cleaning,
                          ),
                        ),
                        title: Text(
                          '${s['name']} · Alias: ${s['alias']}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          'Acceso exclusivo a estado de habitaciones (<15m) y pasaplatos',
                          style: TextStyle(
                            fontSize: 12,
                            color: OwnerTheme.textSecondary,
                          ),
                        ),
                        trailing: IconButton(
                          tooltip: 'Revocar personal de limpieza',
                          onPressed: () => _deleteStaff(s['id'].toString()),
                          icon: Icon(
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
                              style: TextStyle(
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

  Widget _buildBdvContingencyCard(List<Map<String, dynamic>> reservations) {
    final pendingList = reservations.where((r) {
      final p = r['payment'];
      return p != null &&
          (p['status'] == 'PENDING' || p['status'] == 'PENDING_REVIEW');
    }).toList();
    final pendingCount = pendingList.length;

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: OwnerTheme.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: pendingCount > 0
              ? OwnerTheme.cleaning
              : OwnerTheme.border,
          width: pendingCount > 0 ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: (pendingCount > 0
                          ? OwnerTheme.cleaning
                          : OwnerTheme.gold)
                      .withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.support_agent_rounded,
                  color: pendingCount > 0
                      ? OwnerTheme.cleaning
                      : OwnerTheme.gold,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Módulo de Contingencia y Cobro Manual',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (pendingCount > 0) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: OwnerTheme.cleaning,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '$pendingCount por validar',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Usa este apartado si las notificaciones push del Banco de Venezuela fallan por mantenimiento o si el huésped paga en efectivo en recepción.',
                      style: TextStyle(
                        color: OwnerTheme.textSecondary,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: pendingCount > 0
                  ? OwnerTheme.gold
                  : OwnerTheme.surface,
              foregroundColor: pendingCount > 0
                  ? OwnerTheme.onPrimary
                  : OwnerTheme.textPrimary,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: OwnerTheme.border),
              ),
            ),
            onPressed: () => _openManualPaymentDialog(),
            icon: const Icon(Icons.add_task_rounded, size: 18),
            label: Text(
              pendingCount > 0
                  ? 'Registrar Pago / Resolver $pendingCount Pendientes'
                  : 'Registrar Pago Manual (Contingencia BDV / Efectivo)',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
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
          _buildBdvContingencyCard(reservations),
          const Text(
            'Notificaciones Bancarias Recibidas (Banco de Venezuela)',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'Cada Pago Móvil entrante se coteja automáticamente por monto exacto en Bs., teléfono o referencia contra reservas, extensiones y consumos de pasaplatos.',
            style: TextStyle(color: OwnerTheme.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 12),
          if (bankEvents.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
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
                    style: TextStyle(
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
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
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
                        style: TextStyle(
                          color: OwnerTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      if (payment != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Monto Bs: ${payment['amountVes'] ?? 'N/D'} · Ref: ${payment['gatewayRef'] ?? 'Pendiente'}',
                          style: TextStyle(
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
                                foregroundColor: Colors.white,
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                  Row(
                    children: [
                      Icon(Icons.account_balance_rounded, color: OwnerTheme.gold),
                      const SizedBox(width: 10),
                      const Expanded(
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
                  Text(
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
                          Icon(
                            Icons.currency_exchange_rounded,
                            size: 18,
                            color: OwnerTheme.available,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Tasa BCV activa en el sistema: Bs. $currentRate / USD',
                              style: TextStyle(
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
          const SizedBox(height: 16),
          _buildIcalSyncCard(hotel),
          const SizedBox(height: 16),
          _buildOwnerGoogleMapsCard(hotel),
          const SizedBox(height: 16),
          _buildOwnerReviewsCard(hotel),
        ],
      ),
    ),
  ),
);
  }

  Widget _buildIcalSyncCard(Map<String, dynamic> hotel) {
    final hotelId = (hotel['id'] ?? '').toString();
    final baseUrl = OwnerApiClient.baseUrl.replaceAll('/api/v1', '');
    final icalUrl = '$baseUrl/api/v1/integrations/ical/$hotelId.ics';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.sync_alt_rounded, color: OwnerTheme.cyan),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Sincronización con Booking.com y Airbnb (iCal)',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Sincroniza tus habitaciones automáticamente con las grandes OTAs para evitar sobreventa (overbooking). '
              'StayPass exporta tus reservas en tiempo real en formato estándar iCalendar RFC 5545.',
              style: TextStyle(color: OwnerTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: OwnerTheme.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: OwnerTheme.border),
              ),
              child: Row(
                children: [
                  const Icon(Icons.link_rounded, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SelectableText(
                      icalUrl,
                      style: const TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Copiar enlace iCal',
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: icalUrl));
                      _showSnack('¡Enlace iCal copiado al portapapeles!');
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: OwnerTheme.cyan.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, size: 18, color: OwnerTheme.cyan),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Pega este enlace en Booking.com Extranet > Calendario > Sincronizar o en Airbnb > Disponibilidad > Importar Calendario.',
                      style: TextStyle(fontSize: 12, color: OwnerTheme.cyan),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOwnerGoogleMapsCard(Map<String, dynamic> hotel) {
    final lat = double.tryParse((hotel['latitude'] ?? 10.4806).toString()) ?? 10.4806;
    final lng = double.tryParse((hotel['longitude'] ?? -66.9036).toString()) ?? -66.9036;
    final address = (hotel['address'] ?? 'Av. Principal, Chacao').toString();
    final city = (hotel['city'] ?? 'Caracas').toString();
    final mapsUrl = 'https://www.google.com/maps/search/?api=1&query=$lat,$lng';
    final directionsUrl = 'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.place_rounded, color: OwnerTheme.available),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Localización y Google Maps',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Tus coordenadas GPS permiten a los huéspedes abrir la ruta directa en Google Maps o Waze con 1 toque al reservar.',
              style: TextStyle(color: OwnerTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: OwnerTheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: OwnerTheme.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.location_city_rounded, size: 16, color: OwnerTheme.textSecondary),
                      const SizedBox(width: 8),
                      Text(
                        '$address, $city',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.gps_fixed_rounded, size: 16, color: OwnerTheme.available),
                      const SizedBox(width: 8),
                      Text(
                        'Coordenadas: $lat° N, $lng° W',
                        style: TextStyle(fontSize: 12.5, color: OwnerTheme.available, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: OwnerTheme.available,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    final uri = Uri.parse(mapsUrl);
                    try {
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      } else {
                        await launchUrl(uri);
                      }
                    } catch (_) {}
                  },
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: const Text('Ver Pin en Google Maps'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    final uri = Uri.parse(directionsUrl);
                    try {
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      } else {
                        await launchUrl(uri);
                      }
                    } catch (_) {}
                  },
                  icon: const Icon(Icons.directions_rounded, size: 16),
                  label: const Text('Probar Ruta GPS'),
                ),
                IconButton(
                  tooltip: 'Copiar coordenadas GPS',
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: '$lat,$lng'));
                    _showSnack('Coordenadas GPS copiadas.');
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOwnerReviewsCard(Map<String, dynamic> hotel) {
    final rating = double.tryParse((hotel['rating'] ?? 4.7).toString()) ?? 4.7;
    final count = (hotel['reviewsCount'] as num?)?.toInt() ?? 41;
    final reviews = (hotel['reviews'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.star_rounded, color: OwnerTheme.gold),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Reputación y Opiniones de Huéspedes',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: OwnerTheme.gold.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.star_rounded, size: 16, color: OwnerTheme.gold),
                      const SizedBox(width: 4),
                      Text(
                        rating.toStringAsFixed(1),
                        style: TextStyle(
                          color: OwnerTheme.gold,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Basado en $count opiniones verificadas. La privacidad del huésped está resguardada con nombres protegidos.',
              style: TextStyle(color: OwnerTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 14),
            if (reviews.isEmpty)
              Text('Aún no hay reseñas registradas.', style: TextStyle(color: OwnerTheme.textSecondary))
            else
              ...reviews.take(3).map((r) {
                final rRating = (r['rating'] as num?)?.toInt() ?? 5;
                final rTags = (r['tags'] as List<dynamic>? ?? []).cast<String>();
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: OwnerTheme.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: OwnerTheme.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            r['guestName']?.toString() ?? 'Huésped',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          Row(
                            children: List.generate(
                              5,
                              (i) => Icon(
                                i < rRating ? Icons.star_rounded : Icons.star_border_rounded,
                                size: 14,
                                color: OwnerTheme.gold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (rTags.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 6,
                          children: rTags.map((t) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: OwnerTheme.gold.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              t,
                              style: TextStyle(fontSize: 10, color: OwnerTheme.gold, fontWeight: FontWeight.bold),
                            ),
                          )).toList(),
                        ),
                      ],
                      if ((r['comment'] ?? '').toString().isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          r['comment'].toString(),
                          style: TextStyle(fontSize: 12, color: OwnerTheme.textPrimary),
                        ),
                      ],
                    ],
                  ),
                );
              }),
          ],
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
                          Icon(
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
                        style: TextStyle(
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
                      Row(
                        children: [
                          Icon(Icons.bolt_rounded, color: OwnerTheme.available),
                          const SizedBox(width: 8),
                          const Expanded(
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
                      Text(
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
                      style: TextStyle(
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
                      style: TextStyle(
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
