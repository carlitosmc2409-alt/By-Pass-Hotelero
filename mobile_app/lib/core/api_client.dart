import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/models.dart';

class ApiException implements Exception {
  final int statusCode;
  final String message;

  const ApiException(this.statusCode, this.message);

  @override
  String toString() => message;
}

class ApiClient {
  // En Android Emulator usar http://10.0.2.2:3000/api/v1
  // En Web / Desktop usar http://localhost:3000/api/v1
  static String baseUrl = const String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:3000/api/v1',
  );

  String? _accessToken;

  void setAccessToken(String? token) {
    _accessToken = token;
  }

  Map<String, String> _headers({bool jsonBody = true}) {
    return {
      if (jsonBody) 'Content-Type': 'application/json',
      if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
    };
  }

  Future<Map<String, dynamic>> _decodeObj(http.Response res) async {
    final decoded = res.body.isNotEmpty ? jsonDecode(res.body) : {};
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return decoded as Map<String, dynamic>;
    }
    final msg = (decoded is Map && decoded['message'] != null)
        ? decoded['message'].toString()
        : 'Error HTTP ${res.statusCode}';
    throw ApiException(res.statusCode, msg);
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
    _accessToken = token;
    return token;
  }

  Future<GuestProfile> fetchGuestProfile() async {
    final res = await http.get(
      Uri.parse('$baseUrl/auth/guest/me'),
      headers: _headers(jsonBody: false),
    );
    final data = await _decodeObj(res);
    return GuestProfile.fromJson(data);
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

  Future<CreatedReservation> createReservation({
    required String roomId,
    required int durationHours,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/reservations'),
      headers: _headers(),
      body: jsonEncode({
        'roomId': roomId,
        'checkIn': DateTime.now().toUtc().toIso8601String(),
        'durationHours': durationHours,
        'gateway': 'PAGO_MOVIL',
      }),
    );
    final data = await _decodeObj(res);
    return CreatedReservation.fromJson(data);
  }

  Future<Map<String, dynamic>> submitPaymentReference({
    required String paymentId,
    required String gatewayRef,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/payments/$paymentId/submit-proof'),
      headers: _headers(),
      body: jsonEncode({
        'gatewayRef': gatewayRef,
      }),
    );
    return _decodeObj(res);
  }

  Future<QrAccessData> fetchQrAccess(String reservationId) async {
    final res = await http.get(
      Uri.parse('$baseUrl/access/qr/$reservationId'),
      headers: _headers(jsonBody: false),
    );
    final data = await _decodeObj(res);
    return QrAccessData.fromJson(data);
  }

  Future<Map<String, dynamic>> simulateDoorScan(String rawToken) async {
    final res = await http.post(
      Uri.parse('$baseUrl/access/validate'),
      headers: _headers(),
      body: jsonEncode({
        'token': rawToken,
        'deviceId': 'lock-demo-flutter',
      }),
    );
    return _decodeObj(res);
  }

  Future<void> checkoutReservation(String reservationId) async {
    final res = await http.post(
      Uri.parse('$baseUrl/access/checkout'),
      headers: _headers(),
      body: jsonEncode({
        'reservationId': reservationId,
      }),
    );
    await _decodeObj(res);
  }
}
