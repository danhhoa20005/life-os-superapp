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

  bool get _hasServicesBinding {
    try {
      ServicesBinding.instance;
      return true;
    } catch (_) {
      return false;
    }
  }

  Stream<Map<String, dynamic>> watchIncomingBankNotifications() {
    if (!isSupportedPlatform || !_hasServicesBinding) {
      return const Stream<Map<String, dynamic>>.empty();
    }
    return Stream<Map<String, dynamic>>.multi((controller) {
      StreamSubscription<dynamic>? sub;
      try {
        sub = _eventChannel.receiveBroadcastStream().listen(
          (raw) {
            if (raw is Map) {
              controller.add(Map<String, dynamic>.from(raw));
            }
          },
          onError: (_) {},
        );
      } catch (_) {
        controller.close();
        return;
      }
      controller.onCancel = () async {
        try {
          await sub?.cancel();
        } catch (_) {}
      };
    });
  }
}
