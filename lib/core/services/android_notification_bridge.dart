import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Platform bridge for Android native `NotificationListenerService` + Durable SQLite ACK Queue (`F10` / `BG-01`).
/// Strictly inactive by default until the user explicitly grants consent and enables packages.
class AndroidNotificationBridge {
  static const MethodChannel _methodChannel = MethodChannel(
    'vn.lifeos.app/bank_listener_methods',
  );
  static const EventChannel _eventChannel = EventChannel(
    'vn.lifeos.app/bank_listener_events',
  );

  /// Test-only durable queue simulation supporting crash-before-ACK & 100+ burst verification (`BG-01`).
  final Map<String, Map<String, dynamic>> _simulatedDurableQueue =
      <String, Map<String, dynamic>>{};
  int _debugClearQueueCallCount = 0;
  bool? _debugLastSyncedConsentEnabled;
  List<String>? _debugLastSyncedAllowedPackages;

  bool get isSupportedPlatform => !kIsWeb && Platform.isAndroid;

  bool get _hasServicesBinding {
    try {
      ServicesBinding.instance;
      return true;
    } catch (_) {
      return false;
    }
  }

  @visibleForTesting
  void simulateBackgroundBankSignal({
    required String notificationKey,
    required String packageName,
    required String title,
    required String body,
    required int postedAtEpochMs,
  }) {
    _simulatedDurableQueue.putIfAbsent(
      notificationKey,
      () => <String, dynamic>{
        'notificationKey': notificationKey,
        'packageName': packageName,
        'title': title,
        'body': body,
        'postedAtEpochMs': postedAtEpochMs,
      },
    );
  }

  @visibleForTesting
  int get debugPendingUnacknowledgedCount => _simulatedDurableQueue.length;

  @visibleForTesting
  int get debugClearQueueCallCount => _debugClearQueueCallCount;

  @visibleForTesting
  bool? get debugLastSyncedConsentEnabled => _debugLastSyncedConsentEnabled;

  @visibleForTesting
  List<String>? get debugLastSyncedAllowedPackages =>
      _debugLastSyncedAllowedPackages == null
      ? null
      : List.unmodifiable(_debugLastSyncedAllowedPackages!);

  Future<bool> isNotificationAccessGranted() async {
    if (!isSupportedPlatform || !_hasServicesBinding) return false;
    try {
      final granted = await _methodChannel.invokeMethod<bool>(
        'isPermissionGranted',
      );
      return granted ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> isPostNotificationsGranted() async {
    if (!isSupportedPlatform || !_hasServicesBinding) return false;
    try {
      final granted = await _methodChannel.invokeMethod<bool>(
        'isPostNotificationsGranted',
      );
      return granted ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> requestPostNotificationsPermission() async {
    if (!isSupportedPlatform || !_hasServicesBinding) return;
    try {
      await _methodChannel.invokeMethod<bool>(
        'requestPostNotificationsPermission',
      );
    } catch (_) {}
  }

  Future<bool> isBatteryOptimizationIgnored() async {
    if (!isSupportedPlatform || !_hasServicesBinding) return true;
    try {
      final ignored = await _methodChannel.invokeMethod<bool>(
        'isBatteryOptimizationIgnored',
      );
      return ignored ?? true;
    } catch (_) {
      return true;
    }
  }

  Future<void> openNotificationAccessSettings() async {
    if (!isSupportedPlatform || !_hasServicesBinding) return;
    try {
      await _methodChannel.invokeMethod<void>('openPermissionSettings');
    } catch (_) {}
  }

  Future<void> syncConsentConfig({
    required bool enabled,
    required List<String> allowedPackages,
    bool? voiceSoundboxEnabled,
  }) async {
    _debugLastSyncedConsentEnabled = enabled;
    _debugLastSyncedAllowedPackages = List<String>.from(allowedPackages);
    if (!isSupportedPlatform || !_hasServicesBinding) return;
    try {
      await _methodChannel.invokeMethod<void>('updateConfig', {
        'enabled': enabled,
        'allowedPackages': allowedPackages,
        if (voiceSoundboxEnabled != null)
          'voiceSoundboxEnabled': voiceSoundboxEnabled,
      });
    } catch (_) {}
  }

  Future<void> speakSoundboxAnnouncement(String message) async {
    if (!isSupportedPlatform || !_hasServicesBinding) return;
    try {
      await _methodChannel.invokeMethod<bool>('speakSoundbox', {
        'message': message,
      });
    } catch (_) {}
  }

  /// Claims unacknowledged background notifications WITHOUT deleting them from persistent storage.
  /// Items are deleted ONLY when [acknowledgeQueuedNotification] is called after Firestore commit!
  Future<List<Map<String, dynamic>>>
  drainQueuedBackgroundNotifications() async {
    final results = <Map<String, dynamic>>[
      ..._simulatedDurableQueue.values.map((m) => Map<String, dynamic>.from(m)),
    ];
    if (!isSupportedPlatform || !_hasServicesBinding) {
      return results;
    }
    try {
      final rawList = await _methodChannel.invokeMethod<List<dynamic>>(
        'drainQueuedNotifications',
      );
      if (rawList != null) {
        results.addAll(
          rawList.whereType<Map<dynamic, dynamic>>().map(
            (m) => Map<String, dynamic>.from(m),
          ),
        );
      }
    } catch (_) {}
    return results;
  }

  /// Explicitly acknowledges and removes committed notifications from the durable SQLite queue (`F10` / `BG-01`).
  Future<void> acknowledgeQueuedNotification(String notificationKey) async {
    if (notificationKey.isEmpty) return;
    _simulatedDurableQueue.remove(notificationKey);
    if (!isSupportedPlatform || !_hasServicesBinding) return;
    try {
      await _methodChannel.invokeMethod<int>(
        'acknowledgeQueuedNotifications',
        <String, dynamic>{
          'keys': <String>[notificationKey],
        },
      );
    } catch (_) {}
  }

  /// Clears ALL queued bank notifications and resets listener consent preferences on sign-out or account deletion.
  Future<void> clearAllQueuedNotifications() async {
    _debugClearQueueCallCount += 1;
    _simulatedDurableQueue.clear();
    if (!isSupportedPlatform || !_hasServicesBinding) return;
    try {
      await _methodChannel.invokeMethod<dynamic>('clearBankSignalQueue');
    } catch (_) {}
  }

  Stream<Map<String, dynamic>> watchIncomingBankNotifications() {
    if (!isSupportedPlatform || !_hasServicesBinding) {
      return const Stream<Map<String, dynamic>>.empty();
    }
    return Stream<Map<String, dynamic>>.multi((controller) {
      StreamSubscription<dynamic>? sub;
      try {
        sub = _eventChannel.receiveBroadcastStream().listen((raw) {
          if (raw is Map) {
            controller.add(Map<String, dynamic>.from(raw));
          }
        }, onError: (_) {});
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
