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
  final String? description;
  final double pricePerHour;
  final double pricePerNight;
  final String currency;
  final List<String> amenities;
  final List<String> photos;
  final String status;

  const RoomModel({
    required this.id,
    required this.name,
    required this.type,
    this.description,
    required this.pricePerHour,
    required this.pricePerNight,
    required this.currency,
    required this.amenities,
    this.photos = const [],
    required this.status,
  });

  bool get isAvailable => status == 'AVAILABLE';
  String? get coverPhoto => photos.isNotEmpty ? photos.first : null;

  factory RoomModel.fromJson(Map<String, dynamic> json) {
    return RoomModel(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      type: (json['type'] as String?) ?? 'STANDARD',
      description: json['description'] as String?,
      pricePerHour: double.tryParse(json['pricePerHour']?.toString() ?? '') ?? 10,
      pricePerNight: double.tryParse(json['pricePerNight']?.toString() ?? '') ?? 50,
      currency: (json['currency'] as String?) ?? 'USD',
      amenities: (json['amenities'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      photos: (json['photos'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .where((s) => s.isNotEmpty)
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
  final double? latitude;
  final double? longitude;
  final double rating;
  final int reviewsCount;
  final List<Map<String, dynamic>> reviews;
  final String? description;
  final String? coverPhoto;
  final List<String> photos;
  final bool faacEnabled;
  final List<RoomModel> rooms;

  const HotelModel({
    required this.id,
    required this.name,
    required this.address,
    required this.city,
    this.latitude,
    this.longitude,
    this.rating = 4.8,
    this.reviewsCount = 40,
    this.reviews = const [],
    this.description,
    this.coverPhoto,
    this.photos = const [],
    this.faacEnabled = true,
    this.rooms = const [],
  });

  String? get effectiveCoverPhoto =>
      (coverPhoto != null && coverPhoto!.isNotEmpty)
          ? coverPhoto
          : (photos.isNotEmpty ? photos.first : null);

  factory HotelModel.fromJson(Map<String, dynamic> json) {
    final roomsJson = json['rooms'] as List<dynamic>? ?? [];
    final reviewsJson = (json['reviews'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();

    return HotelModel(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? 'Hotel',
      address: (json['address'] as String?) ?? '',
      city: (json['city'] as String?) ?? '',
      latitude: json['latitude'] != null
          ? double.tryParse(json['latitude'].toString())
          : 10.4806,
      longitude: json['longitude'] != null
          ? double.tryParse(json['longitude'].toString())
          : -66.9036,
      rating: double.tryParse(json['rating']?.toString() ?? '') ?? 4.8,
      reviewsCount: (json['reviewsCount'] as num?)?.toInt() ?? 40,
      reviews: reviewsJson,
      description: json['description'] as String?,
      coverPhoto: json['coverPhoto'] as String?,
      photos: (json['photos'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .where((s) => s.isNotEmpty)
          .toList(),
      faacEnabled: json['faacEnabled'] != false,
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
  final bool isRoomService;
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
    this.isRoomService = false,
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
      (isExtension || isRoomService) && parentReservationId != null
          ? parentReservationId!
          : reservationId;

  factory CreatedReservation.fromJson(Map<String, dynamic> json) {
    return CreatedReservation(
      reservationId: json['reservationId'] as String,
      parentReservationId: json['parentReservationId'] as String?,
      isExtension: json['isExtension'] == true,
      isRoomService: json['isRoomService'] == true,
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
  final bool isRoomService;
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
    this.isRoomService = false,
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
      isRoomService: isRoomService,
      paymentId: pay['id'] as String,
      totalAmount: totalAmount,
      currency: currency,
      amountVes: double.tryParse(pay['amountVes']?.toString() ?? '') ?? 0.0,
      exchangeRate: double.tryParse(pay['exchangeRate']?.toString() ?? '') ?? 0.0,
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
      isRoomService: json['isRoomService'] == true,
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

class RoomServiceItem {
  final String id;
  final String name;
  final String category;
  final double priceUsd;
  final String description;

  const RoomServiceItem({
    required this.id,
    required this.name,
    required this.category,
    required this.priceUsd,
    required this.description,
  });

  factory RoomServiceItem.fromJson(Map<String, dynamic> json) {
    return RoomServiceItem(
      id: json['id'].toString(),
      name: json['name'].toString(),
      category: (json['category'] ?? 'CONSUMO').toString().trim(),
      priceUsd: double.tryParse(json['priceUsd']?.toString() ?? '') ?? 0,
      description: (json['description'] ?? '').toString(),
    );
  }
}

class RoomServiceOrder {
  final String orderId;
  final String paymentStatus;
  final String deliveryStatus;
  final double totalAmount;
  final List<Map<String, dynamic>> items;
  final DateTime createdAt;

  const RoomServiceOrder({
    required this.orderId,
    required this.paymentStatus,
    required this.deliveryStatus,
    required this.totalAmount,
    required this.items,
    required this.createdAt,
  });

  bool get isDelivered => deliveryStatus == 'DELIVERED_PASATURNO';
  bool get isPaid => paymentStatus == 'APPROVED';

  factory RoomServiceOrder.fromJson(Map<String, dynamic> json) {
    return RoomServiceOrder(
      orderId: json['orderId'].toString(),
      paymentStatus: (json['paymentStatus'] ?? 'PENDING').toString(),
      deliveryStatus: (json['deliveryStatus'] ?? 'AWAITING_PAYMENT').toString(),
      totalAmount: double.tryParse(json['totalAmount']?.toString() ?? '') ?? 0,
      items: ((json['items'] as List<dynamic>?) ?? []).cast<Map<String, dynamic>>(),
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}

class QrAccessData {
  final String qrDataUrl;
  final String rawToken;
  final DateTime validFrom;
  final DateTime validUntil;
  final String hotelId;
  final String hotelName;
  final String roomName;
  final Map<String, dynamic> faac;
  final bool isOfflineCached;

  const QrAccessData({
    required this.qrDataUrl,
    required this.rawToken,
    required this.validFrom,
    required this.validUntil,
    required this.hotelId,
    required this.hotelName,
    required this.roomName,
    this.faac = const {},
    this.isOfflineCached = false,
  });

  bool get faacEnabled => faac['enabled'] != false;
  String get faacModel =>
      (faac['model'] ?? 'FAAC 615 BPR / Placa E615').toString();
  String get faacEntryDevice =>
      (faac['entryDeviceId'] ?? 'faac-entrada-1').toString();
  String get faacExitDevice =>
      (faac['exitDeviceId'] ?? 'faac-salida-1').toString();

  Map<String, dynamic> toJson() => {
        'qrDataUrl': qrDataUrl,
        'rawToken': rawToken,
        'validFrom': validFrom.toIso8601String(),
        'validUntil': validUntil.toIso8601String(),
        'hotelId': hotelId,
        'hotelName': hotelName,
        'roomName': roomName,
        'faac': faac,
        'isOfflineCached': isOfflineCached,
      };

  factory QrAccessData.fromJson(Map<String, dynamic> json) {
    return QrAccessData(
      qrDataUrl: json['qrDataUrl'] as String,
      rawToken: json['rawToken'] as String,
      validFrom: DateTime.parse(json['validFrom'] as String),
      validUntil: DateTime.parse(json['validUntil'] as String),
      hotelId: (json['hotelId'] ?? '').toString(),
      hotelName: json['hotelName'] as String,
      roomName: json['roomName'] as String,
      faac: (json['faac'] as Map<String, dynamic>?) ?? const {},
      isOfflineCached: json['isOfflineCached'] == true,
    );
  }
}
