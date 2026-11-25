import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class ScheduledEventAlarmInfo {
  final String eventId;
  final String title;
  final String subtitle;
  final DateTime triggerAt;
  final int minutesBefore;
  final bool fullScreen;
  final bool exactScheduled;
  final int cupMl;

  const ScheduledEventAlarmInfo({
    required this.eventId,
    required this.title,
    required this.subtitle,
    required this.triggerAt,
    required this.minutesBefore,
    required this.fullScreen,
    required this.exactScheduled,
    this.cupMl = 250,
  });
}

/// System-level readiness check for reliable outside-the-app & background notifications.
class BackgroundReminderReadiness {
  final bool notificationsGranted;
  final bool exactAlarmGranted;
  final bool batteryOptimizationIgnored;

  const BackgroundReminderReadiness({
    required this.notificationsGranted,
    required this.exactAlarmGranted,
    required this.batteryOptimizationIgnored,
  });

  static const allReady = BackgroundReminderReadiness(
    notificationsGranted: true,
    exactAlarmGranted: true,
    batteryOptimizationIgnored: true,
  );

  bool get canShowOutsideScreen => notificationsGranted;
  bool get isFullyOptimized =>
      notificationsGranted && exactAlarmGranted && batteryOptimizationIgnored;
}

/// Action tapped by the user directly on an outside-the-app lock-screen / status-bar notification
/// while the Flutter app was in the background or completely closed.
class QueuedBackgroundHealthAction {
  final String type; // 'water_logged' | 'med_taken'
  final int ml;
  final String medId;
  final DateTime loggedAt;

  const QueuedBackgroundHealthAction({
    required this.type,
    this.ml = 0,
    this.medId = '',
    required this.loggedAt,
  });
}

/// Real OS Alarm & Background Notification Bridge (`AlarmManager` + `BroadcastReceiver` + `BOOT_COMPLETED`).
class NativeAlarmSchedulerBridge {
  static const MethodChannel _channel = MethodChannel(
    'vn.lifeos.app/alarm_scheduler',
  );

  static final NativeAlarmSchedulerBridge instance =
      NativeAlarmSchedulerBridge._();

  final Map<String, ScheduledEventAlarmInfo> _inMemorySchedule =
      <String, ScheduledEventAlarmInfo>{};
  final List<QueuedBackgroundHealthAction> _debugQueuedHealthActions =
      <QueuedBackgroundHealthAction>[];
  final List<Map<String, dynamic>> _debugShownNotifications =
      <Map<String, dynamic>>[];
  Map<String, dynamic>? _debugHydrationDaemonConfig;
  BackgroundReminderReadiness? _debugReadinessOverride;

  void Function(Map<String, String> payload)? _ringingListener;
  VoidCallback? _bgHealthActionListener;

  int _stopRingingCount = 0;
  String? _lastStoppedEventId;

  @visibleForTesting
  int get debugStopRingingCount => _stopRingingCount;

  @visibleForTesting
  String? get debugLastStoppedEventId => _lastStoppedEventId;

  @visibleForTesting
  List<Map<String, dynamic>> get debugShownNotifications =>
      List.unmodifiable(_debugShownNotifications);

  @visibleForTesting
  Map<String, dynamic>? get debugHydrationDaemonConfig =>
      _debugHydrationDaemonConfig;

  @visibleForTesting
  void setDebugReadinessOverride(BackgroundReminderReadiness? value) {
    _debugReadinessOverride = value;
  }

  @visibleForTesting
  void simulateBackgroundNotificationActionTap(
    QueuedBackgroundHealthAction action,
  ) {
    _debugQueuedHealthActions.add(action);
    _bgHealthActionListener?.call();
  }

  @visibleForTesting
  void resetDebugCounters() {
    _stopRingingCount = 0;
    _lastStoppedEventId = null;
    _debugShownNotifications.clear();
    _debugQueuedHealthActions.clear();
    _debugHydrationDaemonConfig = null;
    _debugReadinessOverride = null;
  }

  NativeAlarmSchedulerBridge._() {
    if (_useNativeAndroid) {
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'onAlarmRinging' && call.arguments is Map) {
          final raw = Map<Object?, Object?>.from(call.arguments as Map);
          final payload = <String, String>{
            'eventId': (raw['eventId'] ?? '').toString(),
            'title': (raw['title'] ?? 'Báo thức LifeOS').toString(),
            'subtitle': (raw['subtitle'] ?? '').toString(),
          };
          _ringingListener?.call(payload);
        } else if (call.method == 'onBackgroundHealthAction') {
          _bgHealthActionListener?.call();
        }
      });
    }
  }

  bool get _useNativeAndroid => !kIsWeb && Platform.isAndroid;

  void setOnAlarmRingingListener(
    void Function(Map<String, String> payload)? listener,
  ) {
    _ringingListener = listener;
  }

  void setOnBackgroundHealthActionListener(VoidCallback? listener) {
    _bgHealthActionListener = listener;
  }

  Future<Map<String, String>?> consumeInitialAlarmPayload() async {
    if (!_useNativeAndroid) return null;
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
        'consumeInitialAlarmPayload',
      );
      if (raw == null) return null;
      return <String, String>{
        'eventId': (raw['eventId'] ?? '').toString(),
        'title': (raw['title'] ?? 'Báo thức LifeOS').toString(),
        'subtitle': (raw['subtitle'] ?? '').toString(),
      };
    } on MissingPluginException {
      return null;
    }
  }

  Future<BackgroundReminderReadiness> getBackgroundReadiness() async {
    if (_debugReadinessOverride != null) return _debugReadinessOverride!;
    if (!_useNativeAndroid) return BackgroundReminderReadiness.allReady;
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
        'getBackgroundReadiness',
      );
      if (raw == null) return BackgroundReminderReadiness.allReady;
      return BackgroundReminderReadiness(
        notificationsGranted: raw['notificationsGranted'] != false,
        exactAlarmGranted: raw['exactAlarmGranted'] != false,
        batteryOptimizationIgnored: raw['batteryOptimizationIgnored'] != false,
      );
    } on MissingPluginException {
      return BackgroundReminderReadiness.allReady;
    }
  }

  Future<bool> requestNotificationPermission() async {
    if (!_useNativeAndroid) return true;
    try {
      return await _channel.invokeMethod<bool>(
            'requestNotificationPermission',
          ) ??
          true;
    } on MissingPluginException {
      return true;
    }
  }

  Future<void> openNotificationSettings() async {
    if (!_useNativeAndroid) return;
    try {
      await _channel.invokeMethod<bool>('openNotificationSettings');
    } on MissingPluginException {
      // Ignore in test environment
    }
  }

  Future<void> requestIgnoreBatteryOptimizations() async {
    if (!_useNativeAndroid) return;
    try {
      await _channel.invokeMethod<bool>('requestIgnoreBatteryOptimizations');
    } on MissingPluginException {
      // Ignore in test environment
    }
  }

  Future<bool> showImmediateReminderNotification({
    required String eventId,
    required String title,
    required String subtitle,
    int cupMl = 250,
  }) async {
    _debugShownNotifications.add(<String, dynamic>{
      'eventId': eventId,
      'title': title,
      'subtitle': subtitle,
      'cupMl': cupMl,
    });
    if (!_useNativeAndroid) return true;
    try {
      return await _channel.invokeMethod<bool>(
            'showImmediateReminderNotification',
            <String, dynamic>{
              'eventId': eventId,
              'title': title,
              'subtitle': subtitle,
              'cupMl': cupMl,
            },
          ) ??
          true;
    } on MissingPluginException {
      return true;
    }
  }

  Future<void> syncHydrationDaemon({
    required bool enabled,
    required int intervalMinutes,
    required int startHour,
    int startMinute = 0,
    required int endHour,
    int endMinute = 0,
    required int targetWaterMl,
    required int waterMl,
    required int preferredCupMl,
    required String dayKey,
  }) async {
    final payload = <String, dynamic>{
      'enabled': enabled,
      'intervalMinutes': intervalMinutes,
      'startHour': startHour,
      'startMinute': startMinute,
      'endHour': endHour,
      'endMinute': endMinute,
      'targetWaterMl': targetWaterMl,
      'waterMl': waterMl,
      'preferredCupMl': preferredCupMl,
      'dayKey': dayKey,
    };
    _debugHydrationDaemonConfig = payload;
    if (!_useNativeAndroid) return;
    try {
      await _channel.invokeMethod<bool>('syncHydrationDaemon', payload);
    } on MissingPluginException {
      // Ignore in test environment
    }
  }

  Future<void> syncMedicationDaemon({
    required String medId,
    required bool enabled,
    required String name,
    required String dosage,
    required int hour,
    required int minute,
  }) async {
    if (!_useNativeAndroid) return;
    try {
      await _channel
          .invokeMethod<bool>('syncMedicationDaemon', <String, dynamic>{
            'medId': medId,
            'enabled': enabled,
            'name': name,
            'dosage': dosage,
            'hour': hour,
            'minute': minute,
          });
    } on MissingPluginException {
      // Ignore in test environment
    }
  }

  Future<List<QueuedBackgroundHealthAction>>
  drainBackgroundHealthActions() async {
    final out = <QueuedBackgroundHealthAction>[..._debugQueuedHealthActions];
    _debugQueuedHealthActions.clear();

    if (!_useNativeAndroid) return out;
    try {
      final rawList = await _channel.invokeMethod<List<Object?>>(
        'drainBackgroundHealthActions',
      );
      if (rawList != null) {
        for (final item in rawList) {
          if (item is! Map) continue;
          final type = (item['type'] ?? '').toString();
          if (type.isEmpty) continue;
          final ms =
              (item['loggedAtEpochMs'] as num?)?.toInt() ??
              DateTime.now().millisecondsSinceEpoch;
          out.add(
            QueuedBackgroundHealthAction(
              type: type,
              ml: (item['ml'] as num?)?.toInt() ?? 0,
              medId: (item['medId'] ?? '').toString(),
              loggedAt: DateTime.fromMillisecondsSinceEpoch(ms),
            ),
          );
        }
      }
    } on MissingPluginException {
      // Ignore in test environment
    }
    return out;
  }

  Future<bool> canScheduleExactAlarms() async {
    if (!_useNativeAndroid) return true;
    try {
      return await _channel.invokeMethod<bool>('canScheduleExactAlarms') ??
          false;
    } on MissingPluginException {
      return true;
    }
  }

  Future<void> openExactAlarmSettings() async {
    if (!_useNativeAndroid) return;
    try {
      await _channel.invokeMethod<bool>('openExactAlarmSettings');
    } on MissingPluginException {
      // Ignore in test environment
    }
  }

  /// Stops active native alarm ringtone, vibration, WakeLock, and notification.
  Future<void> stopRingingAlarm({String? eventId}) async {
    _stopRingingCount++;
    _lastStoppedEventId = eventId;
    if (!_useNativeAndroid) return;
    try {
      await _channel.invokeMethod<bool>('stopRingingAlarm', <String, dynamic>{
        if (eventId != null) 'eventId': eventId,
      });
    } on MissingPluginException {
      // Ignore in test environment
    }
  }

  /// Triggers a short preview of the native alarm sound & vibration (stopped via [stopRingingAlarm]).
  Future<void> startTestRinging() async {
    if (!_useNativeAndroid) return;
    try {
      await _channel.invokeMethod<bool>('startTestRinging');
    } on MissingPluginException {
      // Ignore in test environment
    }
  }

  Future<ScheduledEventAlarmInfo> scheduleEventAlarm({
    required String eventId,
    required String title,
    required String subtitle,
    required DateTime eventStartsAt,
    required int minutesBefore,
    required bool fullScreen,
    int cupMl = 250,
  }) async {
    final now = DateTime.now();
    final minFuture = now.add(const Duration(seconds: 5));
    final desiredTrigger = eventStartsAt.subtract(
      Duration(minutes: minutesBefore),
    );

    final DateTime safeTrigger;
    if (!desiredTrigger.isBefore(minFuture)) {
      safeTrigger = desiredTrigger;
    } else if (!eventStartsAt.isBefore(minFuture)) {
      safeTrigger = eventStartsAt;
    } else {
      safeTrigger = minFuture;
    }

    var exactScheduled = true;
    var resolvedTrigger = safeTrigger;

    if (_useNativeAndroid) {
      try {
        final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
          'scheduleAlarm',
          <String, dynamic>{
            'eventId': eventId,
            'title': title,
            'subtitle': subtitle,
            'triggerAtEpochMs': safeTrigger.millisecondsSinceEpoch,
            'minutesBefore': minutesBefore,
            'fullScreen': fullScreen,
            'cupMl': cupMl,
          },
        );
        if (raw != null) {
          final ms = (raw['triggerAtEpochMs'] as num?)?.toInt();
          if (ms != null && ms > 0) {
            resolvedTrigger = DateTime.fromMillisecondsSinceEpoch(ms);
          }
          exactScheduled = raw['exactScheduled'] == true;
        }
      } on MissingPluginException {
        // Unit/Widget test harness fallback
      }
    }

    final info = ScheduledEventAlarmInfo(
      eventId: eventId,
      title: title,
      subtitle: subtitle,
      triggerAt: resolvedTrigger,
      minutesBefore: minutesBefore,
      fullScreen: fullScreen,
      exactScheduled: exactScheduled,
      cupMl: cupMl,
    );
    _inMemorySchedule[eventId] = info;
    return info;
  }

  Future<ScheduledEventAlarmInfo?> getScheduledAlarm(String eventId) async {
    if (_useNativeAndroid) {
      try {
        final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
          'getScheduledAlarm',
          <String, dynamic>{'eventId': eventId},
        );
        if (raw != null) {
          final ms = (raw['triggerAtEpochMs'] as num?)?.toInt() ?? 0;
          if (ms > DateTime.now().millisecondsSinceEpoch) {
            final info = ScheduledEventAlarmInfo(
              eventId: eventId,
              title: (raw['title'] ?? '').toString(),
              subtitle: (raw['subtitle'] ?? '').toString(),
              triggerAt: DateTime.fromMillisecondsSinceEpoch(ms),
              minutesBefore: (raw['minutesBefore'] as num?)?.toInt() ?? 0,
              fullScreen: raw['fullScreen'] == true,
              exactScheduled: raw['exactScheduled'] == true,
            );
            _inMemorySchedule[eventId] = info;
            return info;
          }
        }
        _inMemorySchedule.remove(eventId);
        return null;
      } on MissingPluginException {
        // Fallback to in-memory test map
      }
    }
    final cached = _inMemorySchedule[eventId];
    if (cached != null && cached.triggerAt.isAfter(DateTime.now())) {
      return cached;
    }
    _inMemorySchedule.remove(eventId);
    return null;
  }

  Future<List<ScheduledEventAlarmInfo>> listScheduledAlarms() async {
    if (_useNativeAndroid) {
      try {
        final rawList = await _channel.invokeMethod<List<Object?>>(
          'listScheduledAlarms',
        );
        if (rawList != null) {
          final nowMs = DateTime.now().millisecondsSinceEpoch;
          final parsed = <ScheduledEventAlarmInfo>[];
          for (final item in rawList) {
            if (item is! Map) continue;
            final ms = (item['triggerAtEpochMs'] as num?)?.toInt() ?? 0;
            if (ms <= nowMs) continue;
            final id = (item['eventId'] ?? '').toString();
            if (id.isEmpty) continue;
            final info = ScheduledEventAlarmInfo(
              eventId: id,
              title: (item['title'] ?? '').toString(),
              subtitle: (item['subtitle'] ?? '').toString(),
              triggerAt: DateTime.fromMillisecondsSinceEpoch(ms),
              minutesBefore: (item['minutesBefore'] as num?)?.toInt() ?? 0,
              fullScreen: item['fullScreen'] == true,
              exactScheduled: item['exactScheduled'] == true,
            );
            _inMemorySchedule[id] = info;
            parsed.add(info);
          }
          parsed.sort((a, b) => a.triggerAt.compareTo(b.triggerAt));
          return parsed;
        }
      } on MissingPluginException {
        // Fallback to in-memory map
      }
    }
    final now = DateTime.now();
    _inMemorySchedule.removeWhere((_, v) => !v.triggerAt.isAfter(now));
    final list = _inMemorySchedule.values.toList()
      ..sort((a, b) => a.triggerAt.compareTo(b.triggerAt));
    return list;
  }

  Future<void> cancelEventAlarm(String eventId) async {
    _inMemorySchedule.remove(eventId);
    if (_useNativeAndroid) {
      try {
        await _channel.invokeMethod<bool>('cancelAlarm', <String, dynamic>{
          'eventId': eventId,
        });
      } on MissingPluginException {
        // Ignore in test harness
      }
    }
  }

  Future<void> clearAllAlarms() async {
    _inMemorySchedule.clear();
    if (_useNativeAndroid) {
      try {
        await _channel.invokeMethod<bool>('clearAllAlarms');
      } on MissingPluginException {
        // Ignore in test harness
      }
    }
  }
}
