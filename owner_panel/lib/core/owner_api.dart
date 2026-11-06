import 'dart:convert';
import 'package:http/http.dart' as http;

class OwnerApiException implements Exception {
  final int statusCode;
  final String message;

  const OwnerApiException(this.statusCode, this.message);

  @override
  String toString() => message;
}

class OwnerApiClient {
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
    _accessToken = token;
    return token;
  }

  Future<List<Map<String, dynamic>>> fetchMyHotels() async {
    final res = await http.get(
      Uri.parse('$baseUrl/hotels/my'),
      headers: _headers(jsonBody: false),
    );
    final list = await _decode(res) as List<dynamic>;
    return list.cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> fetchHotelDashboard(String hotelId) async {
    final res = await http.get(
      Uri.parse('$baseUrl/hotels/$hotelId/dashboard'),
      headers: _headers(jsonBody: false),
    );
    return (await _decode(res)) as Map<String, dynamic>;
  }

  Future<void> updateRoomStatus(String roomId, String status) async {
    final res = await http.patch(
      Uri.parse('$baseUrl/rooms/$roomId/status'),
      headers: _headers(),
      body: jsonEncode({'status': status}),
    );
    await _decode(res);
  }

  Future<void> createRoom({
    required String hotelId,
    required String name,
    required String type,
    required double pricePerHour,
    required double pricePerNight,
    required List<String> amenities,
  }) async {
    final res = await http.post(
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
    );
    await _decode(res);
  }

  Future<void> updateHotelPaymentInfo({
    required String hotelId,
    required String bank,
    required String bankName,
    required String phone,
    required String idNumber,
    required String holderName,
  }) async {
    final res = await http.put(
      Uri.parse('$baseUrl/hotels/$hotelId'),
      headers: _headers(),
      body: jsonEncode({
        'paymentInfo': {
          'bank': bank,
          'bankName': bankName,
          'phone': phone,
          'idNumber': idNumber,
          'holderName': holderName,
        },
      }),
    );
    await _decode(res);
  }

  Future<void> confirmPaymentManually(String paymentId) async {
    final res = await http.post(
      Uri.parse('$baseUrl/payments/$paymentId/confirm'),
      headers: _headers(),
      body: jsonEncode({}),
    );
    await _decode(res);
  }

  Future<void> rejectPaymentManually(String paymentId) async {
    final res = await http.post(
      Uri.parse('$baseUrl/payments/$paymentId/reject'),
      headers: _headers(),
      body: jsonEncode({}),
    );
    await _decode(res);
  }
}
