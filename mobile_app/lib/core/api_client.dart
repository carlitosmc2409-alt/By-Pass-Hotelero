import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';

class ApiException implements Exception {
  final int statusCode;
  final String message;

  const ApiException(this.statusCode, this.message);

  @override
  String toString() => message;
}

class ApiClient {
  static const _kAccessKey = 'staypass_guest_access_token';
  static const _kRefreshKey = 'staypass_guest_refresh_token';
  static const _kRoleKey = 'staypass_user_role';
  static const _kHotelIdKey = 'staypass_staff_hotel_id';
  static const _kHotelNameKey = 'staypass_staff_hotel_name';
  static const _kStaffNameKey = 'staypass_staff_name';
  static const _kCustomApiUrlKey = 'staypass_custom_api_url';

  static const String _compiledBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  );

  static String baseUrl = _resolveInitialBaseUrl();

  static String _resolveInitialBaseUrl() {
    if (_compiledBaseUrl.isNotEmpty) return _compiledBaseUrl;
    if (kIsWeb && Uri.base.host.isNotEmpty) {
      if (Uri.base.host.contains('vercel.app') || Uri.base.scheme == 'https') {
        return '${Uri.base.origin}/api/v1';
      }
      return 'https://by-pass-hotelero.vercel.app/api/v1';
    }
    return 'https://by-pass-hotelero.vercel.app/api/v1';
  }

  static Future<void> setCustomBaseUrl(String url) async {
    final clean = url.trim().replaceAll(RegExp(r'/+$'), '');
    if (clean.isEmpty) return;
    baseUrl = clean;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kCustomApiUrlKey, clean);
    } catch (_) {}
  }

  String? _accessToken;
  String? _refreshToken;
  String _currentRole = 'GUEST';
  String? _currentHotelId;
  String? _currentHotelName;
  String? _staffName;

  String? get accessToken => _accessToken;
  bool get hasToken => _accessToken != null && _accessToken!.isNotEmpty;
  String get currentRole => _currentRole;
  String? get currentHotelId => _currentHotelId;
  String? get currentHotelName => _currentHotelName;
  String? get staffName => _staffName;

  void setAccessToken(String? token) {
    _accessToken = token;
    if (token == null) {
      _refreshToken = null;
      _clearStoredTokens();
    }
  }

  Future<bool> restoreSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedUrl = prefs.getString(_kCustomApiUrlKey);
      if (savedUrl != null && savedUrl.isNotEmpty) {
        baseUrl = savedUrl;
      }
      final access = prefs.getString(_kAccessKey);
      final refresh = prefs.getString(_kRefreshKey);
      _currentRole = prefs.getString(_kRoleKey) ?? 'GUEST';
      _currentHotelId = prefs.getString(_kHotelIdKey);
      _currentHotelName = prefs.getString(_kHotelNameKey);
      _staffName = prefs.getString(_kStaffNameKey);

      if (access != null && access.isNotEmpty) {
        _accessToken = access;
        _refreshToken = refresh;
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<void> _persistTokens(
    String access,
    String? refresh, {
    String role = 'GUEST',
    String? hotelId,
    String? hotelName,
    String? staffName,
  }) async {
    _accessToken = access;
    if (refresh != null) _refreshToken = refresh;
    _currentRole = role;
    _currentHotelId = hotelId;
    _currentHotelName = hotelName;
    _staffName = staffName;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kAccessKey, access);
      await prefs.setString(_kRoleKey, role);
      if (refresh != null) {
        await prefs.setString(_kRefreshKey, refresh);
      } else {
        await prefs.remove(_kRefreshKey);
      }
      if (hotelId != null) {
        await prefs.setString(_kHotelIdKey, hotelId);
      } else {
        await prefs.remove(_kHotelIdKey);
      }
      if (hotelName != null) {
        await prefs.setString(_kHotelNameKey, hotelName);
      } else {
        await prefs.remove(_kHotelNameKey);
      }
      if (staffName != null) {
        await prefs.setString(_kStaffNameKey, staffName);
      } else {
        await prefs.remove(_kStaffNameKey);
      }
    } catch (_) {}
  }

  Future<void> _clearStoredTokens() async {
    _currentRole = 'GUEST';
    _currentHotelId = null;
    _currentHotelName = null;
    _staffName = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kAccessKey);
      await prefs.remove(_kRefreshKey);
      await prefs.remove(_kRoleKey);
      await prefs.remove(_kHotelIdKey);
      await prefs.remove(_kHotelNameKey);
      await prefs.remove(_kStaffNameKey);
    } catch (_) {}
  }

  Future<void> logout() async {
    final rt = _refreshToken;
    _accessToken = null;
    _refreshToken = null;
    await _clearStoredTokens();
    if (rt != null && rt.isNotEmpty) {
      try {
        await http.post(
          Uri.parse('$baseUrl/auth/logout'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'refreshToken': rt}),
        );
      } catch (_) {}
    }
  }

  Map<String, String> _headers({bool jsonBody = true}) {
    return {
      if (jsonBody) 'Content-Type': 'application/json',
      if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
    };
  }

  Future<bool> _tryRefresh() async {
    final rt = _refreshToken;
    if (rt == null || rt.isEmpty) return false;
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/auth/refresh'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refreshToken': rt}),
      );
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final newAccess = data['accessToken'] as String?;
        final newRefresh = data['refreshToken'] as String?;
        if (newAccess != null && newAccess.isNotEmpty) {
          await _persistTokens(newAccess, newRefresh ?? rt);
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  Future<http.Response> _authorizedSend(
    Future<http.Response> Function() requestFn,
  ) async {
    var res = await requestFn();
    if (res.statusCode == 401 && await _tryRefresh()) {
      res = await requestFn();
    }
    return res;
  }

  /// Abre un stream SSE en tiempo real contra `/api/v1/events/stream` compatible con Web y Android.
  Stream<Map<String, dynamic>> connectRealtimeEvents() {
    late StreamController<Map<String, dynamic>> controller;
    http.Client? client;
    bool cancelled = false;

    Future<void> runLoop() async {
      while (!cancelled) {
        final token = _accessToken;
        if (token == null || token.isEmpty) break;
        client = http.Client();
        try {
          final uri = Uri.parse(
            '$baseUrl/events/stream?token=${Uri.encodeQueryComponent(token)}',
          );
          final req = http.Request('GET', uri);
          req.headers['Accept'] = 'text/event-stream';
          final streamed = await client!.send(req);

          if (streamed.statusCode == 401) {
            final ok = await _tryRefresh();
            if (!ok) break;
            continue;
          }
          if (streamed.statusCode != 200) {
            await Future<void>.delayed(const Duration(seconds: 5));
            continue;
          }

          await for (final line in streamed.stream
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
            if (cancelled) break;
            if (line.startsWith('data:')) {
              final raw = line.substring(5).trim();
              if (raw.isNotEmpty) {
                try {
                  final decoded = jsonDecode(raw);
                  if (decoded is Map<String, dynamic> && !controller.isClosed) {
                    controller.add(decoded);
                  }
                } catch (_) {}
              }
            }
          }
        } catch (_) {
          // Reintentar silenciosamente tras micro-cortes
        } finally {
          client?.close();
          client = null;
        }
        if (!cancelled) {
          await Future<void>.delayed(const Duration(seconds: 4));
        }
      }
    }

    controller = StreamController<Map<String, dynamic>>.broadcast(
      onListen: () {
        cancelled = false;
        runLoop();
      },
      onCancel: () {
        cancelled = true;
        client?.close();
      },
    );

    return controller.stream;
  }

  Future<dynamic> _decodeAny(http.Response res) async {
    final decoded = res.body.isNotEmpty ? jsonDecode(res.body) : {};
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return decoded;
    }
    final msg = (decoded is Map && decoded['message'] != null)
        ? decoded['message'].toString()
        : 'Error HTTP ${res.statusCode}';
    throw ApiException(res.statusCode, msg);
  }

  Future<Map<String, dynamic>> _decodeObj(http.Response res) async {
    return (await _decodeAny(res)) as Map<String, dynamic>;
  }

  Future<List<BankOption>> fetchBanks() async {
    final res = await http.get(
      Uri.parse('$baseUrl/auth/banks'),
      headers: _headers(jsonBody: false),
    );
    if (res.statusCode != 200) {
      throw ApiException(res.statusCode, 'No se pudo cargar la lista de bancos');
    }
    final list = jsonDecode(res.body) as List<dynamic>;
    return list
        .map((e) => BankOption.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> registerGuest({
    required String fullName,
    required String phone,
    required String cedula,
    required String paymentBank,
    required String paymentPhone,
    required String paymentCedula,
    required String password,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/auth/guest/register'),
      headers: _headers(),
      body: jsonEncode({
        'fullName': fullName,
        'phone': phone,
        'cedula': cedula,
        'paymentBank': paymentBank,
        'paymentPhone': paymentPhone,
        'paymentCedula': paymentCedula,
        'password': password,
      }),
    );
    return _decodeObj(res);
  }

  Future<Map<String, dynamic>> verifyGuestOtp({
    required String phone,
    required String code,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/auth/guest/verify-otp'),
      headers: _headers(),
      body: jsonEncode({
        'phone': phone,
        'code': code,
        'purpose': 'PHONE_VERIFICATION',
      }),
    );
    return _decodeObj(res);
  }

  Future<String> loginGuest({
    required String phone,
    required String password,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/auth/guest/login'),
      headers: _headers(),
      body: jsonEncode({
        'phone': phone,
        'password': password,
      }),
    );
    final data = await _decodeObj(res);
    final token = data['accessToken'] as String;
    final refresh = data['refreshToken'] as String?;
    await _persistTokens(token, refresh, role: 'GUEST');
    return token;
  }

  Future<Map<String, dynamic>> loginReceptionist({
    required String hotelCode,
    required String username,
    required String password,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/auth/receptionist/login'),
      headers: _headers(),
      body: jsonEncode({
        'hotelCode': hotelCode,
        'username': username,
        'password': password,
      }),
    );
    final data = await _decodeObj(res);
    final token = data['accessToken'] as String;
    final hotelId = data['hotelId'] as String;
    final hotelName = data['hotelName'] as String? ?? 'Hotel';
    final user = data['username'] as String? ?? username;

    await _persistTokens(
      token,
      null,
      role: 'RECEPTIONIST',
      hotelId: hotelId,
      hotelName: hotelName,
      staffName: user,
    );
    return data;
  }

  Future<Map<String, dynamic>> loginCleaningStaff({
    required String hotelCode,
    required String alias,
    required String pin,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/auth/cleaning/login'),
      headers: _headers(),
      body: jsonEncode({
        'hotelCode': hotelCode,
        'alias': alias,
        'pin': pin,
      }),
    );
    final data = await _decodeObj(res);
    final token = data['accessToken'] as String;
    final hotelId = data['hotelId'] as String;
    final hotelName = data['hotelName'] as String? ?? 'Hotel';
    final staff = data['staffName'] as String? ?? alias;

    await _persistTokens(
      token,
      null,
      role: 'CLEANING',
      hotelId: hotelId,
      hotelName: hotelName,
      staffName: staff,
    );
    return data;
  }

  Future<GuestProfile> fetchGuestProfile() async {
    final res = await _authorizedSend(
      () => http.get(
        Uri.parse('$baseUrl/auth/guest/me'),
        headers: _headers(jsonBody: false),
      ),
    );
    final data = await _decodeObj(res);
    return GuestProfile.fromJson(data);
  }

  Future<void> updatePaymentProfile({
    required String paymentBank,
    required String paymentPhone,
    required String paymentCedula,
  }) async {
    final res = await _authorizedSend(
      () => http.put(
        Uri.parse('$baseUrl/auth/guest/payment-profile'),
        headers: _headers(),
        body: jsonEncode({
          'paymentBank': paymentBank,
          'paymentPhone': paymentPhone,
          'paymentCedula': paymentCedula,
        }),
      ),
    );
    await _decodeObj(res);
  }

  Future<List<HotelModel>> fetchHotels() async {
    final res = await http.get(
      Uri.parse('$baseUrl/hotels'),
      headers: _headers(jsonBody: false),
    );
    final data = await _decodeObj(res);
    final list = data['data'] as List<dynamic>? ?? [];
    return list
        .map((e) => HotelModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<HotelModel> fetchHotelDetail(String hotelId) async {
    final res = await http.get(
      Uri.parse('$baseUrl/hotels/$hotelId'),
      headers: _headers(jsonBody: false),
    );
    final data = await _decodeObj(res);
    return HotelModel.fromJson(data);
  }

  Future<List<RoomServiceItem>> fetchHotelMenu(String hotelId) async {
    final res = await http.get(
      Uri.parse('$baseUrl/hotels/$hotelId/menu'),
      headers: _headers(jsonBody: false),
    );
    final data = await _decodeObj(res);
    final items = (data['items'] as List<dynamic>?) ?? [];
    return items
        .map((e) => RoomServiceItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<GuestReservationSummary>> fetchMyReservations() async {
    final res = await _authorizedSend(
      () => http.get(
        Uri.parse('$baseUrl/reservations/my'),
        headers: _headers(jsonBody: false),
      ),
    );
    final list = (await _decodeAny(res)) as List<dynamic>;
    return list
        .map((e) => GuestReservationSummary.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> fetchReservationDetail(String reservationId) async {
    final res = await _authorizedSend(
      () => http.get(
        Uri.parse('$baseUrl/reservations/$reservationId'),
        headers: _headers(jsonBody: false),
      ),
    );
    return _decodeObj(res);
  }

  Future<CreatedReservation> createReservation({
    required String roomId,
    required int durationHours,
  }) async {
    final res = await _authorizedSend(
      () => http.post(
        Uri.parse('$baseUrl/reservations'),
        headers: _headers(),
        body: jsonEncode({
          'roomId': roomId,
          'checkIn': DateTime.now().toUtc().toIso8601String(),
          'durationHours': durationHours,
          'gateway': 'PAGO_MOVIL',
        }),
      ),
    );
    final data = await _decodeObj(res);
    return CreatedReservation.fromJson(data);
  }

  Future<CreatedReservation> extendReservation({
    required String reservationId,
    required int extraHours,
  }) async {
    final res = await _authorizedSend(
      () => http.post(
        Uri.parse('$baseUrl/reservations/$reservationId/extend'),
        headers: _headers(),
        body: jsonEncode({
          'extraHours': extraHours,
          'gateway': 'PAGO_MOVIL',
        }),
      ),
    );
    final data = await _decodeObj(res);
    return CreatedReservation.fromJson(data);
  }

  Future<CreatedReservation> createRoomServiceOrder({
    required String reservationId,
    required List<Map<String, dynamic>> items,
    String? guestNote,
  }) async {
    final res = await _authorizedSend(
      () => http.post(
        Uri.parse('$baseUrl/reservations/$reservationId/room-service'),
        headers: _headers(),
        body: jsonEncode({
          'items': items,
          if (guestNote != null && guestNote.isNotEmpty) 'guestNote': guestNote,
          'gateway': 'PAGO_MOVIL',
        }),
      ),
    );
    final data = await _decodeObj(res);
    return CreatedReservation.fromJson(data);
  }

  Future<List<RoomServiceOrder>> fetchRoomServiceOrders(
    String reservationId,
  ) async {
    final res = await _authorizedSend(
      () => http.get(
        Uri.parse('$baseUrl/reservations/$reservationId/orders'),
        headers: _headers(jsonBody: false),
      ),
    );
    final list = (await _decodeAny(res)) as List<dynamic>;
    return list
        .map((e) => RoomServiceOrder.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> submitPaymentReference({
    required String paymentId,
    required String gatewayRef,
  }) async {
    final res = await _authorizedSend(
      () => http.post(
        Uri.parse('$baseUrl/payments/${paymentId}/submit-proof'),
        headers: _headers(),
        body: jsonEncode({
          'gatewayRef': gatewayRef,
        }),
      ),
    );
    return _decodeObj(res);
  }

  Future<QrAccessData> fetchQrAccess(String reservationId) async {
    final cacheKey = 'offline_qr_$reservationId';
    try {
      final res = await _authorizedSend(
        () => http.get(
          Uri.parse('$baseUrl/access/qr/$reservationId'),
          headers: _headers(jsonBody: false),
        ),
      );
      final data = await _decodeObj(res);
      final qr = QrAccessData.fromJson(data);

      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(cacheKey, jsonEncode(qr.toJson()));
      } catch (_) {}

      return qr;
    } catch (e) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final cachedStr = prefs.getString(cacheKey);
        if (cachedStr != null && cachedStr.isNotEmpty) {
          final cachedMap = jsonDecode(cachedStr) as Map<String, dynamic>;
          final cachedQr = QrAccessData.fromJson({
            ...cachedMap,
            'isOfflineCached': true,
          });
          if (DateTime.now().isBefore(cachedQr.validUntil)) {
            return cachedQr;
          }
        }
      } catch (_) {}
      rethrow;
    }
  }

  Future<Map<String, dynamic>> submitReview({
    required String reservationId,
    required int rating,
    List<String> tags = const [],
    String comment = '',
  }) async {
    final res = await _authorizedSend(
      () => http.post(
        Uri.parse('$baseUrl/reviews/reservation/$reservationId'),
        headers: _headers(),
        body: jsonEncode({
          'rating': rating,
          'tags': tags,
          'comment': comment,
        }),
      ),
    );
    return _decodeObj(res);
  }

  Future<Map<String, dynamic>> fetchHotelReviews(String hotelId) async {
    final res = await http.get(
      Uri.parse('$baseUrl/reviews/hotel/$hotelId'),
      headers: _headers(jsonBody: false),
    );
    return _decodeObj(res);
  }

  Future<Map<String, dynamic>> openFaacBarrier({
    required String reservationId,
    required String direction, // 'ENTRY' | 'EXIT'
  }) async {
    final res = await _authorizedSend(
      () => http.post(
        Uri.parse('$baseUrl/access/faac/open'),
        headers: _headers(),
        body: jsonEncode({
          'reservationId': reservationId,
          'direction': direction,
        }),
      ),
    );
    return _decodeObj(res);
  }

  Future<Map<String, dynamic>> simulateDoorScan(
    String rawToken, {
    String deviceId = 'lock-demo-flutter',
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/access/validate'),
      headers: _headers(),
      body: jsonEncode({
        'token': rawToken,
        'deviceId': deviceId,
      }),
    );
    return _decodeObj(res);
  }

  Future<void> checkoutReservation(String reservationId) async {
    final res = await _authorizedSend(
      () => http.post(
        Uri.parse('$baseUrl/access/checkout'),
        headers: _headers(),
        body: jsonEncode({
          'reservationId': reservationId,
        }),
      ),
    );
    await _decodeObj(res);
  }

  // --- MÉTODOS DE RECEPCIÓN / SOPORTE DE EMERGENCIA ---

  Future<Map<String, dynamic>> fetchReceptionBoard(String hotelId) async {
    final res = await _authorizedSend(
      () => http.get(
        Uri.parse('$baseUrl/hotels/$hotelId/reception-board'),
        headers: _headers(jsonBody: false),
      ),
    );
    return _decodeObj(res);
  }

  Future<Map<String, dynamic>> pulseFaacBarrier({
    required String hotelId,
    required String direction, // 'ENTRY' | 'EXIT'
  }) async {
    final res = await _authorizedSend(
      () => http.post(
        Uri.parse('$baseUrl/access/faac/owner-pulse'),
        headers: _headers(),
        body: jsonEncode({
          'hotelId': hotelId,
          'direction': direction,
        }),
      ),
    );
    return _decodeObj(res);
  }

  Future<Map<String, dynamic>> testIotRelay({
    required String hotelId,
    String direction = 'ENTRY',
    bool dryRun = false,
  }) async {
    final res = await _authorizedSend(
      () => http.post(
        Uri.parse('$baseUrl/access/iot/test-relay'),
        headers: _headers(),
        body: jsonEncode({
          'hotelId': hotelId,
          'direction': direction,
          'dryRun': dryRun,
        }),
      ),
    );
    return _decodeObj(res);
  }

  Future<Map<String, dynamic>> confirmManualPayment({
    required String paymentId,
    required String gatewayRef,
    String gateway = 'MANUAL_RECEPTION',
    String? notes,
    String? reason,
  }) async {
    final res = await _authorizedSend(
      () => http.post(
        Uri.parse('$baseUrl/payments/confirm-manual'),
        headers: _headers(),
        body: jsonEncode({
          'paymentId': paymentId,
          'gateway': gateway,
          'gatewayRef': gatewayRef,
          if (notes != null) 'notes': notes,
          if (reason != null) 'reason': reason,
        }),
      ),
    );
    return _decodeObj(res);
  }

  // --- MÉTODOS DE LIMPIEZA & CAMARERÍA ---

  Future<Map<String, dynamic>> fetchCleaningBoard(String hotelId) async {
    final res = await _authorizedSend(
      () => http.get(
        Uri.parse('$baseUrl/hotels/$hotelId/cleaning-board'),
        headers: _headers(jsonBody: false),
      ),
    );
    return _decodeObj(res);
  }

  Future<Map<String, dynamic>> updateRoomStatus({
    required String roomId,
    required String status,
  }) async {
    final endpoint = _currentRole == 'CLEANING' ? 'cleaning-status' : 'status';
    final res = await _authorizedSend(
      () => http.put(
        Uri.parse('$baseUrl/rooms/$roomId/$endpoint'),
        headers: _headers(),
        body: jsonEncode({'status': status}),
      ),
    );
    return _decodeObj(res);
  }

  Future<Map<String, dynamic>> deliverRoomServiceOrder(String orderId) async {
    final res = await _authorizedSend(
      () => http.put(
        Uri.parse('$baseUrl/reservations/orders/$orderId/deliver'),
        headers: _headers(jsonBody: false),
      ),
    );
    return _decodeObj(res);
  }
}
