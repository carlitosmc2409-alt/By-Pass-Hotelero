import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class OwnerApiException implements Exception {
  final int statusCode;
  final String message;

  const OwnerApiException(this.statusCode, this.message);

  @override
  String toString() => message;
}

class OwnerApiClient {
  static const _kAccessKey = 'staypass_owner_access_token';
  static const _kRefreshKey = 'staypass_owner_refresh_token';
  static const _kRoleKey = 'staypass_panel_role';
  static const _kCleaningHotelIdKey = 'staypass_cleaning_hotel_id';
  static const _kCleaningHotelNameKey = 'staypass_cleaning_hotel_name';
  static const _kStaffNameKey = 'staypass_cleaning_staff_name';
  static const _kCustomApiUrlKey = 'staypass_owner_custom_api_url';

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
  String _role = 'OWNER';
  String? _cleaningHotelId;
  String? _cleaningHotelName;
  String? _staffName;

  bool get hasToken => _accessToken != null && _accessToken!.isNotEmpty;
  String get role => _role;
  bool get isCleaningRole => _role == 'CLEANING';
  String? get cleaningHotelId => _cleaningHotelId;
  String? get cleaningHotelName => _cleaningHotelName;
  String? get staffName => _staffName;

  void setAccessToken(String? token) {
    _accessToken = token;
    if (token == null) {
      _refreshToken = null;
      _role = 'OWNER';
      _cleaningHotelId = null;
      _cleaningHotelName = null;
      _staffName = null;
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
      final savedRole = prefs.getString(_kRoleKey) ?? 'OWNER';
      if (access != null && access.isNotEmpty) {
        _accessToken = access;
        _refreshToken = refresh;
        _role = savedRole;
        _cleaningHotelId = prefs.getString(_kCleaningHotelIdKey);
        _cleaningHotelName = prefs.getString(_kCleaningHotelNameKey);
        _staffName = prefs.getString(_kStaffNameKey);
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<void> _persistSession({
    required String access,
    String? refresh,
    required String role,
    String? cleaningHotelId,
    String? cleaningHotelName,
    String? staffName,
  }) async {
    _accessToken = access;
    _refreshToken = refresh;
    _role = role;
    _cleaningHotelId = cleaningHotelId;
    _cleaningHotelName = cleaningHotelName;
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
      if (cleaningHotelId != null) {
        await prefs.setString(_kCleaningHotelIdKey, cleaningHotelId);
      }
      if (cleaningHotelName != null) {
        await prefs.setString(_kCleaningHotelNameKey, cleaningHotelName);
      }
      if (staffName != null) {
        await prefs.setString(_kStaffNameKey, staffName);
      }
    } catch (_) {}
  }

  Future<void> _clearStoredTokens() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kAccessKey);
      await prefs.remove(_kRefreshKey);
      await prefs.remove(_kRoleKey);
      await prefs.remove(_kCleaningHotelIdKey);
      await prefs.remove(_kCleaningHotelNameKey);
      await prefs.remove(_kStaffNameKey);
    } catch (_) {}
  }

  Future<void> logout() async {
    final rt = _refreshToken;
    _accessToken = null;
    _refreshToken = null;
    _role = 'OWNER';
    _cleaningHotelId = null;
    _cleaningHotelName = null;
    _staffName = null;
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

  Future<bool> _tryRefreshToken() async {
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
          await _persistSession(
            access: newAccess,
            refresh: newRefresh ?? rt,
            role: _role,
            cleaningHotelId: _cleaningHotelId,
            cleaningHotelName: _cleaningHotelName,
            staffName: _staffName,
          );
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  Stream<Map<String, dynamic>> connectRealtimeEvents({String? hotelId}) {
    late StreamController<Map<String, dynamic>> controller;
    http.Client? client;
    bool cancelled = false;

    Future<void> runLoop() async {
      while (!cancelled) {
        final token = _accessToken;
        if (token == null || token.isEmpty) break;
        client = http.Client();
        try {
          final hidParam = (hotelId != null && hotelId.isNotEmpty)
              ? '&hotelId=${Uri.encodeQueryComponent(hotelId)}'
              : '';
          final uri = Uri.parse(
            '$baseUrl/events/stream?token=${Uri.encodeQueryComponent(token)}$hidParam',
          );
          final req = http.Request('GET', uri);
          req.headers['Accept'] = 'text/event-stream';
          final streamed = await client!.send(req);

          if (streamed.statusCode == 401) {
            final ok = await _tryRefreshToken();
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
          // Reconexión automática silenciosa
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

  Future<dynamic> _sendWithRefresh(
    Future<http.Response> Function() requestFn, {
    bool allowRefresh = true,
  }) async {
    var res = await requestFn();
    if (res.statusCode == 401 && allowRefresh && _refreshToken != null) {
      final refreshed = await _tryRefreshToken();
      if (refreshed) {
        res = await requestFn();
      }
    }
    return _decode(res);
  }

  Future<dynamic> _decode(http.Response res) async {
    final decoded = res.body.isNotEmpty ? jsonDecode(res.body) : {};
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return decoded;
    }
    final msg = (decoded is Map && decoded['message'] != null)
        ? decoded['message'].toString()
        : 'Error HTTP ${res.statusCode}';
    throw OwnerApiException(res.statusCode, msg);
  }

  Future<String> loginOwner({
    required String email,
    required String password,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/auth/owner/login'),
      headers: _headers(),
      body: jsonEncode({
        'email': email,
        'password': password,
      }),
    );
    final data = await _decode(res) as Map<String, dynamic>;
    final token = data['accessToken'] as String;
    final refreshToken = data['refreshToken'] as String?;
    await _persistSession(
      access: token,
      refresh: refreshToken,
      role: 'OWNER',
    );
    return token;
  }

  Future<Map<String, dynamic>> loginCleaning({
    String? hotelCode,
    required String alias,
    required String pin,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/auth/cleaning/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        if (hotelCode != null && hotelCode.trim().isNotEmpty)
          'hotelCode': hotelCode.trim(),
        'alias': alias.trim(),
        'pin': pin.trim(),
      }),
    );
    final data = await _decode(res) as Map<String, dynamic>;
    await _persistSession(
      access: data['accessToken'] as String,
      role: 'CLEANING',
      cleaningHotelId: data['hotelId']?.toString(),
      cleaningHotelName: data['hotelName']?.toString(),
      staffName: data['staffName']?.toString(),
    );
    return data;
  }

  Future<List<Map<String, dynamic>>> fetchMyHotels() async {
    final list = await _sendWithRefresh(
      () => http.get(
        Uri.parse('$baseUrl/hotels/my'),
        headers: _headers(jsonBody: false),
      ),
    ) as List<dynamic>;
    return list.cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> fetchHotelDashboard(String hotelId) async {
    final data = await _sendWithRefresh(
      () => http.get(
        Uri.parse('$baseUrl/hotels/$hotelId/dashboard'),
        headers: _headers(jsonBody: false),
      ),
    );
    return data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> fetchCleaningBoard(String hotelId) async {
    final data = await _sendWithRefresh(
      () => http.get(
        Uri.parse('$baseUrl/hotels/$hotelId/cleaning-board'),
        headers: _headers(jsonBody: false),
      ),
      allowRefresh: false,
    );
    return data as Map<String, dynamic>;
  }

  Future<void> updateRoomStatus(String roomId, String status) async {
    await _sendWithRefresh(
      () => http.patch(
        Uri.parse('$baseUrl/rooms/$roomId/status'),
        headers: _headers(),
        body: jsonEncode({'status': status}),
      ),
    );
  }

  Future<void> updateRoomCleaningStatus(String roomId, String status) async {
    await _sendWithRefresh(
      () => http.patch(
        Uri.parse('$baseUrl/rooms/$roomId/cleaning-status'),
        headers: _headers(),
        body: jsonEncode({'status': status}),
      ),
      allowRefresh: false,
    );
  }

  Future<void> deliverRoomServiceOrder(String orderId) async {
    await _sendWithRefresh(
      () => http.patch(
        Uri.parse('$baseUrl/reservations/$orderId/deliver-order'),
        headers: _headers(),
        body: jsonEncode({}),
      ),
    );
  }

  Future<Map<String, dynamic>> pulseFaacBarrier({
    required String hotelId,
    required String direction, // 'ENTRY' | 'EXIT'
  }) async {
    final data = await _sendWithRefresh(
      () => http.post(
        Uri.parse('$baseUrl/access/faac/owner-pulse'),
        headers: _headers(),
        body: jsonEncode({
          'hotelId': hotelId,
          'direction': direction,
        }),
      ),
    );
    return data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> testFaacRelay({
    required String hotelId,
    String direction = 'ENTRY',
    bool dryRun = true,
  }) async {
    final data = await _sendWithRefresh(
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
    return data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateHotelOperations({
    required String hotelId,
    Map<String, dynamic>? faac,
    List<Map<String, dynamic>>? roomServiceMenu,
  }) async {
    final data = await _sendWithRefresh(
      () => http.put(
        Uri.parse('$baseUrl/hotels/$hotelId/operations'),
        headers: _headers(),
        body: jsonEncode({
          if (faac != null) 'faac': faac,
          if (roomServiceMenu != null) 'roomServiceMenu': roomServiceMenu,
        }),
      ),
    );
    return data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> createStaff({
    required String hotelId,
    required String role, // 'RECEPTIONIST' | 'CLEANING'
    required String name,
    String? alias,
    String? username,
    String? pin,
    String? password,
    String? phone,
    String? email,
  }) async {
    final effectiveAlias = alias ?? username ?? '';
    final effectivePin = pin ?? password ?? '';
    final effectiveUsername = username ?? alias ?? '';
    final effectivePassword = password ?? pin ?? '';

    final data = await _sendWithRefresh(
      () => http.post(
        Uri.parse('$baseUrl/hotels/$hotelId/staff'),
        headers: _headers(),
        body: jsonEncode({
          'role': role,
          'name': name,
          'alias': effectiveAlias,
          'username': effectiveUsername,
          'pin': effectivePin,
          'password': effectivePassword,
          if (phone != null && phone.isNotEmpty) 'phone': phone,
          if (email != null && email.isNotEmpty) 'email': email,
        }),
      ),
    );
    return data as Map<String, dynamic>;
  }

  Future<void> deleteStaff({
    required String hotelId,
    required String staffId,
  }) async {
    await _sendWithRefresh(
      () => http.delete(
        Uri.parse('$baseUrl/hotels/$hotelId/staff/$staffId'),
        headers: _headers(jsonBody: false),
      ),
    );
  }

  Future<Map<String, dynamic>> createCleaningStaff({
    required String hotelId,
    required String name,
    required String alias,
    required String pin,
  }) => createStaff(hotelId: hotelId, role: 'CLEANING', name: name, alias: alias, pin: pin);

  Future<void> deleteCleaningStaff({
    required String hotelId,
    required String staffId,
  }) => deleteStaff(hotelId: hotelId, staffId: staffId);

  Future<void> createRoom({
    required String hotelId,
    required String name,
    required String type,
    required double pricePerHour,
    required double pricePerNight,
    required List<String> amenities,
    String? description,
    List<String>? photos,
  }) async {
    await _sendWithRefresh(
      () => http.post(
        Uri.parse('$baseUrl/rooms'),
        headers: _headers(),
        body: jsonEncode({
          'hotelId': hotelId,
          'name': name,
          'type': type,
          'pricePerHour': pricePerHour,
          'pricePerNight': pricePerNight,
          'amenities': amenities,
          if (description != null) 'description': description,
          if (photos != null) 'photos': photos,
        }),
      ),
    );
  }

  Future<void> updateRoom({
    required String roomId,
    String? name,
    String? type,
    double? pricePerHour,
    double? pricePerNight,
    List<String>? amenities,
    String? description,
    List<String>? photos,
  }) async {
    await _sendWithRefresh(
      () => http.put(
        Uri.parse('$baseUrl/rooms/$roomId'),
        headers: _headers(),
        body: jsonEncode({
          if (name != null) 'name': name,
          if (type != null) 'type': type,
          if (pricePerHour != null) 'pricePerHour': pricePerHour,
          if (pricePerNight != null) 'pricePerNight': pricePerNight,
          if (amenities != null) 'amenities': amenities,
          if (description != null) 'description': description,
          if (photos != null) 'photos': photos,
        }),
      ),
    );
  }

  Future<void> updateHotelPhotos({
    required String hotelId,
    String? coverPhoto,
    List<String>? photos,
    String? description,
  }) async {
    await _sendWithRefresh(
      () => http.put(
        Uri.parse('$baseUrl/hotels/$hotelId'),
        headers: _headers(),
        body: jsonEncode({
          'coverPhoto': coverPhoto,
          if (photos != null) 'photos': photos,
          if (description != null && description.isNotEmpty)
            'description': description,
        }),
      ),
    );
  }

  Future<void> updateHotelPaymentInfo({
    required String hotelId,
    required String bank,
    required String bankName,
    required String phone,
    required String idNumber,
    required String holderName,
    double? fallbackExchangeRate,
  }) async {
    final paymentInfo = <String, dynamic>{
      'bank': bank,
      'bankName': bankName,
      'phone': phone,
      'idNumber': idNumber,
      'holderName': holderName,
      if (fallbackExchangeRate != null && fallbackExchangeRate > 0)
        'fallbackExchangeRate': fallbackExchangeRate,
    };

    await _sendWithRefresh(
      () => http.put(
        Uri.parse('$baseUrl/hotels/$hotelId'),
        headers: _headers(),
        body: jsonEncode({'paymentInfo': paymentInfo}),
      ),
    );
  }

  Future<void> confirmPaymentManually(
    String paymentId, {
    String? gateway,
    String? gatewayRef,
    String? notes,
    String? reason,
  }) async {
    await _sendWithRefresh(
      () => http.post(
        Uri.parse('$baseUrl/payments/$paymentId/confirm'),
        headers: _headers(),
        body: jsonEncode({
          if (gateway != null) 'gateway': gateway,
          if (gatewayRef != null) 'gatewayRef': gatewayRef,
          if (notes != null) 'notes': notes,
          if (reason != null) 'reason': reason,
        }),
      ),
    );
  }

  Future<void> rejectPaymentManually(String paymentId) async {
    await _sendWithRefresh(
      () => http.post(
        Uri.parse('$baseUrl/payments/$paymentId/reject'),
        headers: _headers(),
        body: jsonEncode({}),
      ),
    );
  }

  Future<Map<String, dynamic>> sendBdvPushWithBridgeToken({
    required String hotelId,
    required String bridgeToken,
    required String rawText,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/payments/webhook/bdv-notification'),
      headers: {
        'Content-Type': 'application/json',
        'x-hotel-bridge-token': bridgeToken,
      },
      body: jsonEncode({
        'hotelId': hotelId,
        'rawText': rawText,
        'source': 'BDV_NOTIFICATION',
      }),
    );
    return (await _decode(res)) as Map<String, dynamic>;
  }
}
