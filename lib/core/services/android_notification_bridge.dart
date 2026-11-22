import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Platform bridge for Android native `NotificationListenerService`.
/// Strictly inactive by default until the user explicitly grants consent and enables packages.
class AndroidNotificationBridge {
  static const MethodChannel _methodChannel = MethodChannel('vn.lifeos.app/bank_listener_methods');
  static const EventChannel _eventChannel = EventChannel('vn.lifeos.app/bank_listener_events');

  bool get isSupportedPlatform => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<bool> isNotificationAccessGranted() async {
    if (!isSupportedPlatform) return false;
    try {
      final granted = await _methodChannel.invokeMethod<bool>('isPermissionGranted');
      return granted ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> openNotificationAccessSettings() async {
    if (!isSupportedPlatform) return;
    try {
      await _methodChannel.invokeMethod<void>('openPermissionSettings');
    } catch (_) {
      // Safe no-op when running in headless test harness or non-native host
    }
  }

  Future<void> syncConsentConfig({
    required bool enabled,
    required List<String> allowedPackages,
  }) async {
    if (!isSupportedPlatform) return;
    try {
      await _methodChannel.invokeMethod<void>('updateConfig', {
        'enabled': enabled,
        'allowedPackages': allowedPackages,
      });
    } catch (_) {
      // Safe no-op in headless unit tests without ServicesBinding
    }
  }

  Stream<Map<String, dynamic>> watchIncomingBankNotifications() {
    if (!isSupportedPlatform) {
      return const Stream<Map<String, dynamic>>.empty();
    }
    return _eventChannel.receiveBroadcastStream().map((raw) {
      if (raw is Map) {
        return Map<String, dynamic>.from(raw);
      }
      return <String, dynamic>{};
    });
  }
}
