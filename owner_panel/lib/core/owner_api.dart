import 'dart:convert';
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

  static String baseUrl = const String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:3000/api/v1',
  );

  String? _accessToken;
  String? _refreshToken;

  bool get hasToken => _accessToken != null && _accessToken!.isNotEmpty;

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
      final access = prefs.getString(_kAccessKey);
      final refresh = prefs.getString(_kRefreshKey);
      if (access != null && access.isNotEmpty) {
        _accessToken = access;
        _refreshToken = refresh;
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<void> _persistTokens(String access, String? refresh) async {
    _accessToken = access;
    if (refresh != null) _refreshToken = refresh;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kAccessKey, access);
      if (refresh != null) {
        await prefs.setString(_kRefreshKey, refresh);
      }
    } catch (_) {}
  }

  Future<void> _clearStoredTokens() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kAccessKey);
      await prefs.remove(_kRefreshKey);
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
          await _persistTokens(newAccess, newRefresh ?? rt);
          return true;
        }
      }
    } catch (_) {}
    return false;
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
    await _persistTokens(token, refreshToken);
    return token;
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

  Future<void> updateRoomStatus(String roomId, String status) async {
    await _sendWithRefresh(
      () => http.patch(
        Uri.parse('$baseUrl/rooms/$roomId/status'),
        headers: _headers(),
        body: jsonEncode({'status': status}),
      ),
    );
  }

  Future<void> createRoom({
    required String hotelId,
    required String name,
    required String type,
    required double pricePerHour,
    required double pricePerNight,
    required List<String> amenities,
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

  Future<void> confirmPaymentManually(String paymentId) async {
    await _sendWithRefresh(
      () => http.post(
        Uri.parse('$baseUrl/payments/$paymentId/confirm'),
        headers: _headers(),
        body: jsonEncode({}),
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
