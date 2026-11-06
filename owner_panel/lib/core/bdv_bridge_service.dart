import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class BdvBridgeStatus {
  final bool supported;
  final bool permissionGranted;
  final bool enabled;
  final String apiBaseUrl;
  final String hotelId;
  final bool allowTestSources;
  final int forwardedCount;
  final int pendingQueueCount;
  final String lastEventSummary;
  final String lastForwardedAt;
  final String lastError;

  const BdvBridgeStatus({
    required this.supported,
    required this.permissionGranted,
    required this.enabled,
    required this.apiBaseUrl,
    required this.hotelId,
    required this.allowTestSources,
    required this.forwardedCount,
    required this.pendingQueueCount,
    required this.lastEventSummary,
    required this.lastForwardedAt,
    required this.lastError,
  });

  factory BdvBridgeStatus.unsupported() {
    return const BdvBridgeStatus(
      supported: false,
      permissionGranted: false,
      enabled: false,
      apiBaseUrl: '',
      hotelId: '',
      allowTestSources: true,
      forwardedCount: 0,
      pendingQueueCount: 0,
      lastEventSummary: '',
      lastForwardedAt: '',
      lastError: '',
    );
  }

  factory BdvBridgeStatus.fromMap(Map<dynamic, dynamic> map) {
    return BdvBridgeStatus(
      supported: map['supported'] == true,
      permissionGranted: map['permissionGranted'] == true,
      enabled: map['enabled'] == true,
      apiBaseUrl: (map['apiBaseUrl'] ?? '').toString(),
      hotelId: (map['hotelId'] ?? '').toString(),
      allowTestSources: map['allowTestSources'] != false,
      forwardedCount: (map['forwardedCount'] as num?)?.toInt() ?? 0,
      pendingQueueCount: (map['pendingQueueCount'] as num?)?.toInt() ?? 0,
      lastEventSummary: (map['lastEventSummary'] ?? '').toString(),
      lastForwardedAt: (map['lastForwardedAt'] ?? '').toString(),
      lastError: (map['lastError'] ?? '').toString(),
    );
  }
}

class BdvBridgeService {
  static const MethodChannel _channel =
      MethodChannel('com.staypass.owner/bdv_bridge');

  static bool get isAndroidNative =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<BdvBridgeStatus> getStatus() async {
    if (!isAndroidNative) {
      return BdvBridgeStatus.unsupported();
    }
    try {
      final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>('getStatus');
      if (raw == null) return BdvBridgeStatus.unsupported();
      return BdvBridgeStatus.fromMap(raw);
    } catch (_) {
      return BdvBridgeStatus.unsupported();
    }
  }

  Future<BdvBridgeStatus> configure({
    required bool enabled,
    required String apiBaseUrl,
    required String hotelId,
    required String bridgeToken,
    required bool allowTestSources,
  }) async {
    if (!isAndroidNative) {
      return BdvBridgeStatus.unsupported();
    }
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'configure',
      {
        'enabled': enabled,
        'apiBaseUrl': apiBaseUrl,
        'hotelId': hotelId,
        'bridgeToken': bridgeToken,
        'allowTestSources': allowTestSources,
      },
    );
    if (raw == null) return BdvBridgeStatus.unsupported();
    return BdvBridgeStatus.fromMap(raw);
  }

  Future<BdvBridgeStatus> flushQueue() async {
    if (!isAndroidNative) {
      return BdvBridgeStatus.unsupported();
    }
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>('flushQueue');
    if (raw == null) return BdvBridgeStatus.unsupported();
    return BdvBridgeStatus.fromMap(raw);
  }

  Future<void> openNotificationSettings() async {
    if (!isAndroidNative) return;
    await _channel.invokeMethod<void>('openNotificationSettings');
  }
}
