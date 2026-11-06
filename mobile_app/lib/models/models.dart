class BankOption {
  final String code;
  final String name;

  const BankOption({required this.code, required this.name});

  factory BankOption.fromJson(Map<String, dynamic> json) {
    return BankOption(
      code: json['code'] as String,
      name: json['name'] as String,
    );
  }
}

class PaymentProfile {
  final String bankCode;
  final String? bankName;
  final String? cedulaMasked;
  final String? phoneMasked;

  const PaymentProfile({
    required this.bankCode,
    this.bankName,
    this.cedulaMasked,
    this.phoneMasked,
  });

  factory PaymentProfile.fromJson(Map<String, dynamic> json) {
    return PaymentProfile(
      bankCode: json['bankCode'] as String,
      bankName: json['bankName'] as String?,
      cedulaMasked: json['cedulaMasked'] as String?,
      phoneMasked: json['phoneMasked'] as String?,
    );
  }
}

class GuestProfile {
  final String id;
  final String fullName;
  final String phone;
  final String? cedula;
  final PaymentProfile? paymentProfile;

  const GuestProfile({
    required this.id,
    required this.fullName,
    required this.phone,
    this.cedula,
    this.paymentProfile,
  });

  factory GuestProfile.fromJson(Map<String, dynamic> json) {
    return GuestProfile(
      id: json['id'] as String,
      fullName: json['fullName'] as String,
      phone: json['phone'] as String,
      cedula: json['cedula'] as String?,
      paymentProfile: json['paymentProfile'] != null
          ? PaymentProfile.fromJson(json['paymentProfile'] as Map<String, dynamic>)
          : null,
    );
  }
}

class RoomModel {
  final String id;
  final String name;
  final String type;
  final double pricePerHour;
  final double pricePerNight;
  final String currency;
  final List<String> amenities;
  final String status;

  const RoomModel({
    required this.id,
    required this.name,
    required this.type,
    required this.pricePerHour,
    required this.pricePerNight,
    required this.currency,
    required this.amenities,
    required this.status,
  });

  bool get isAvailable => status == 'AVAILABLE';

  factory RoomModel.fromJson(Map<String, dynamic> json) {
    return RoomModel(
      id: json['id'] as String,
      name: json['name'] as String,
      type: (json['type'] as String?) ?? 'STANDARD',
      pricePerHour: double.parse(json['pricePerHour'].toString()),
      pricePerNight: double.parse(json['pricePerNight'].toString()),
      currency: (json['currency'] as String?) ?? 'USD',
      amenities: (json['amenities'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      status: (json['status'] as String?) ?? 'AVAILABLE',
    );
  }
}

class HotelModel {
  final String id;
  final String name;
  final String address;
  final String city;
  final String? description;
  final List<RoomModel> rooms;

  const HotelModel({
    required this.id,
    required this.name,
    required this.address,
    required this.city,
    this.description,
    this.rooms = const [],
  });

  factory HotelModel.fromJson(Map<String, dynamic> json) {
    final roomsJson = json['rooms'] as List<dynamic>? ?? [];
    return HotelModel(
      id: json['id'] as String,
      name: json['name'] as String,
      address: (json['address'] as String?) ?? '',
      city: (json['city'] as String?) ?? '',
      description: json['description'] as String?,
      rooms: roomsJson
          .map((r) => RoomModel.fromJson(r as Map<String, dynamic>))
          .toList(),
    );
  }
}

class CreatedReservation {
  final String reservationId;
  final String? parentReservationId;
  final bool isExtension;
  final String paymentId;
  final double totalAmount;
  final String currency;
  final double amountVes;
  final double exchangeRate;
  final DateTime paymentExpiresAt;
  final Map<String, dynamic> receptorPagoMovil;
  final DateTime checkIn;
  final DateTime checkOut;

  const CreatedReservation({
    required this.reservationId,
    this.parentReservationId,
    this.isExtension = false,
    required this.paymentId,
    required this.totalAmount,
    required this.currency,
    required this.amountVes,
    required this.exchangeRate,
    required this.paymentExpiresAt,
    required this.receptorPagoMovil,
    required this.checkIn,
    required this.checkOut,
  });

  String get effectiveQrReservationId =>
      isExtension && parentReservationId != null
          ? parentReservationId!
          : reservationId;

  factory CreatedReservation.fromJson(Map<String, dynamic> json) {
    return CreatedReservation(
      reservationId: json['reservationId'] as String,
      parentReservationId: json['parentReservationId'] as String?,
      isExtension: json['isExtension'] == true,
      paymentId: json['paymentId'] as String,
      totalAmount: double.parse(json['totalAmount'].toString()),
      currency: (json['currency'] as String?) ?? 'USD',
      amountVes: double.parse(json['amountVes'].toString()),
      exchangeRate: double.parse(json['exchangeRate'].toString()),
      paymentExpiresAt: DateTime.parse(json['paymentExpiresAt'] as String),
      receptorPagoMovil:
          (json['receptorPagoMovil'] as Map<String, dynamic>?) ?? const {},
      checkIn: DateTime.parse(json['checkIn'] as String),
      checkOut: DateTime.parse(json['checkOut'] as String),
    );
  }
}

class GuestReservationSummary {
  final String id;
  final String status;
  final int durationHours;
  final double totalAmount;
  final String currency;
  final DateTime checkIn;
  final DateTime checkOut;
  final bool isExtension;
  final String? parentReservationId;
  final RoomModel room;
  final HotelModel hotel;
  final Map<String, dynamic>? payment;
  final Map<String, dynamic> hotelPaymentInfo;

  const GuestReservationSummary({
    required this.id,
    required this.status,
    required this.durationHours,
    required this.totalAmount,
    required this.currency,
    required this.checkIn,
    required this.checkOut,
    required this.isExtension,
    this.parentReservationId,
    required this.room,
    required this.hotel,
    this.payment,
    required this.hotelPaymentInfo,
  });

  bool get isActive => status == 'ACTIVE';
  bool get isAwaitingPayment =>
      status == 'PENDING_PAYMENT' || status == 'PAYMENT_PENDING_REVIEW';

  CreatedReservation? toResumableReservation() {
    final pay = payment;
    if (pay == null || pay['id'] == null) return null;
    final expStr = pay['expiresAt']?.toString();
    final expiresAt = expStr != null
        ? DateTime.parse(expStr)
        : DateTime.now().add(const Duration(minutes: 5));
    return CreatedReservation(
      reservationId: id,
      parentReservationId: parentReservationId,
      isExtension: isExtension,
      paymentId: pay['id'] as String,
      totalAmount: totalAmount,
      currency: currency,
      amountVes: double.tryParse(pay['amountVes']?.toString() ?? '') ?? totalAmount,
      exchangeRate: double.tryParse(pay['exchangeRate']?.toString() ?? '') ?? 50.0,
      paymentExpiresAt: expiresAt,
      receptorPagoMovil: hotelPaymentInfo,
      checkIn: checkIn,
      checkOut: checkOut,
    );
  }

  factory GuestReservationSummary.fromJson(Map<String, dynamic> json) {
    final roomMap = (json['room'] as Map<String, dynamic>?) ?? const {};
    final hotelMap = (roomMap['hotel'] as Map<String, dynamic>?) ?? const {};
    return GuestReservationSummary(
      id: json['id'] as String,
      status: (json['status'] as String?) ?? 'PENDING_PAYMENT',
      durationHours: (json['durationHours'] as num?)?.toInt() ?? 1,
      totalAmount: double.parse(json['totalAmount'].toString()),
      currency: (json['currency'] as String?) ?? 'USD',
      checkIn: DateTime.parse(json['checkIn'] as String),
      checkOut: DateTime.parse(json['checkOut'] as String),
      isExtension: json['isExtension'] == true,
      parentReservationId: json['parentReservationId'] as String?,
      room: RoomModel(
        id: (roomMap['id'] as String?) ?? '',
        name: (roomMap['name'] as String?) ?? '',
        type: (roomMap['type'] as String?) ?? 'STANDARD',
        pricePerHour: double.tryParse(roomMap['pricePerHour']?.toString() ?? '') ?? 10,
        pricePerNight: double.tryParse(roomMap['pricePerNight']?.toString() ?? '') ?? 50,
        currency: (json['currency'] as String?) ?? 'USD',
        amenities: const [],
        status: 'OCCUPIED',
      ),
      hotel: HotelModel(
        id: (hotelMap['id'] as String?) ?? '',
        name: (hotelMap['name'] as String?) ?? 'Motel',
        address: (hotelMap['address'] as String?) ?? '',
        city: (hotelMap['city'] as String?) ?? '',
      ),
      payment: json['payment'] as Map<String, dynamic>?,
      hotelPaymentInfo:
          (hotelMap['paymentInfo'] as Map<String, dynamic>?) ?? const {},
    );
  }
}

class QrAccessData {
  final String qrDataUrl;
  final String rawToken;
  final DateTime validFrom;
  final DateTime validUntil;
  final String hotelName;
  final String roomName;

  const QrAccessData({
    required this.qrDataUrl,
    required this.rawToken,
    required this.validFrom,
    required this.validUntil,
    required this.hotelName,
    required this.roomName,
  });

  factory QrAccessData.fromJson(Map<String, dynamic> json) {
    return QrAccessData(
      qrDataUrl: json['qrDataUrl'] as String,
      rawToken: json['rawToken'] as String,
      validFrom: DateTime.parse(json['validFrom'] as String),
      validUntil: DateTime.parse(json['validUntil'] as String),
      hotelName: json['hotelName'] as String,
      roomName: json['roomName'] as String,
    );
  }
}
