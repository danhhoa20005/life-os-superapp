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

  const ScheduledEventAlarmInfo({
    required this.eventId,
    required this.title,
    required this.subtitle,
    required this.triggerAt,
    required this.minutesBefore,
    required this.fullScreen,
    required this.exactScheduled,
  });
}

/// Real OS Alarm & Reminder Scheduler Bridge (`AlarmManager` + `BOOT_COMPLETED` on Android).
/// Replaces SnackBar-only mock reminders with genuine OS-level scheduled alarms.
class NativeAlarmSchedulerBridge {
  static const MethodChannel _channel = MethodChannel(
    'vn.lifeos.app/alarm_scheduler',
  );

  static final NativeAlarmSchedulerBridge instance =
      NativeAlarmSchedulerBridge._();

  final Map<String, ScheduledEventAlarmInfo> _inMemorySchedule =
      <String, ScheduledEventAlarmInfo>{};
  void Function(Map<String, String> payload)? _ringingListener;

  NativeAlarmSchedulerBridge._() {
    if (_useNativeAndroid) {
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'onAlarmRinging' && call.arguments is Map) {
          final raw = Map<Object?, Object?>.from(call.arguments as Map);
          final payload = <String, String>{
            'eventId': (raw['eventId'] ?? '').toString(),
            'title': (raw['title'] ?? 'Nhắc lịch trình LifeOS').toString(),
            'subtitle': (raw['subtitle'] ?? '').toString(),
          };
          _ringingListener?.call(payload);
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

  Future<Map<String, String>?> consumeInitialAlarmPayload() async {
    if (!_useNativeAndroid) return null;
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
        'consumeInitialAlarmPayload',
      );
      if (raw == null) return null;
      return <String, String>{
        'eventId': (raw['eventId'] ?? '').toString(),
        'title': (raw['title'] ?? 'Nhắc lịch trình LifeOS').toString(),
        'subtitle': (raw['subtitle'] ?? '').toString(),
      };
    } on MissingPluginException {
      return null;
    }
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

  Future<ScheduledEventAlarmInfo> scheduleEventAlarm({
    required String eventId,
    required String title,
    required String subtitle,
    required DateTime eventStartsAt,
    required int minutesBefore,
    required bool fullScreen,
  }) async {
    final desiredTrigger = eventStartsAt.subtract(
      Duration(minutes: minutesBefore),
    );
    final minFuture = DateTime.now().add(const Duration(seconds: 5));
    final safeTrigger = desiredTrigger.isBefore(minFuture)
        ? minFuture
        : desiredTrigger;

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
              minutesBefore: (raw['minutesBefore'] as num?)?.toInt() ?? 15,
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
