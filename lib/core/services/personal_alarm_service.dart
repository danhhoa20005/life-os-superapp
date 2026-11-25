import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

import 'native_alarm_scheduler_bridge.dart';
import 'native_secure_vault_bridge.dart';

/// Standalone Apple-Clock style personal alarm with exact `HH:mm:00` scheduling,
/// optional weekday recurrence (`1 = Thứ Hai .. 7 = Chủ Nhật`), and snooze interval.
class PersonalAlarmItem extends Equatable {
  final String id;
  final int hour;
  final int minute;
  final String label;
  final List<int> repeatWeekdays;
  final int snoozeMinutes;
  final bool enabled;

  const PersonalAlarmItem({
    required this.id,
    required this.hour,
    required this.minute,
    required this.label,
    this.repeatWeekdays = const <int>[],
    this.snoozeMinutes = 5,
    this.enabled = true,
  });

  bool get isRecurring => repeatWeekdays.isNotEmpty;

  String get formattedTime =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  static String shortWeekdayVi(int weekday) => switch (weekday) {
    DateTime.monday => 'T2',
    DateTime.tuesday => 'T3',
    DateTime.wednesday => 'T4',
    DateTime.thursday => 'T5',
    DateTime.friday => 'T6',
    DateTime.saturday => 'T7',
    DateTime.sunday => 'CN',
    _ => 'T$weekday',
  };

  String get repeatSummaryVi {
    if (repeatWeekdays.isEmpty) return 'Một lần';
    final sorted = repeatWeekdays.toSet().toList()..sort();
    if (sorted.length == 7) return 'Hằng ngày';
    if (sorted.length == 5 &&
        sorted[0] == 1 &&
        sorted[1] == 2 &&
        sorted[2] == 3 &&
        sorted[3] == 4 &&
        sorted[4] == 5) {
      return 'Thứ 2 – Thứ 6';
    }
    if (sorted.length == 2 && sorted[0] == 6 && sorted[1] == 7) {
      return 'Cuối tuần';
    }
    return sorted.map(shortWeekdayVi).join(', ');
  }

  /// Computes the exact next top-of-minute (`second = 0`) trigger timestamp strictly after [now].
  DateTime computeNextTriggerAt(DateTime now) {
    final safeHour = hour.clamp(0, 23);
    final safeMin = minute.clamp(0, 59);

    if (repeatWeekdays.isEmpty) {
      final todayCandidate = DateTime(
        now.year,
        now.month,
        now.day,
        safeHour,
        safeMin,
      );
      if (todayCandidate.isAfter(now)) {
        return todayCandidate;
      }
      return DateTime(now.year, now.month, now.day + 1, safeHour, safeMin);
    }

    final validDays = repeatWeekdays.where((d) => d >= 1 && d <= 7).toSet();
    for (var offset = 0; offset <= 7; offset++) {
      final candidate = DateTime(
        now.year,
        now.month,
        now.day + offset,
        safeHour,
        safeMin,
      );
      if (validDays.contains(candidate.weekday) && candidate.isAfter(now)) {
        return candidate;
      }
    }
    return DateTime(now.year, now.month, now.day + 1, safeHour, safeMin);
  }

  PersonalAlarmItem copyWith({
    int? hour,
    int? minute,
    String? label,
    List<int>? repeatWeekdays,
    int? snoozeMinutes,
    bool? enabled,
  }) {
    final normalizedDays = repeatWeekdays != null
        ? (repeatWeekdays.where((d) => d >= 1 && d <= 7).toSet().toList()
            ..sort())
        : this.repeatWeekdays;
    return PersonalAlarmItem(
      id: id,
      hour: (hour ?? this.hour).clamp(0, 23),
      minute: (minute ?? this.minute).clamp(0, 59),
      label: label ?? this.label,
      repeatWeekdays: List<int>.unmodifiable(normalizedDays),
      snoozeMinutes: snoozeMinutes ?? this.snoozeMinutes,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'hour': hour,
    'minute': minute,
    'label': label,
    'repeatWeekdays': repeatWeekdays,
    'snoozeMinutes': snoozeMinutes,
    'enabled': enabled,
  };

  factory PersonalAlarmItem.fromJson(Map<String, dynamic> json) {
    final rawDays = json['repeatWeekdays'];
    final days = rawDays is List
        ? (rawDays
              .whereType<num>()
              .map((n) => n.toInt())
              .where((d) => d >= 1 && d <= 7)
              .toSet()
              .toList()
            ..sort())
        : const <int>[];
    return PersonalAlarmItem(
      id: (json['id'] as String?) ?? 'palarm_default',
      hour: ((json['hour'] as num?)?.toInt() ?? 6).clamp(0, 23),
      minute: ((json['minute'] as num?)?.toInt() ?? 30).clamp(0, 59),
      label: ((json['label'] as String?)?.trim().isNotEmpty ?? false)
          ? (json['label'] as String).trim()
          : 'Báo thức',
      repeatWeekdays: List<int>.unmodifiable(days),
      snoozeMinutes: ((json['snoozeMinutes'] as num?)?.toInt() ?? 5).clamp(
        1,
        30,
      ),
      enabled: (json['enabled'] as bool?) ?? true,
    );
  }

  @override
  List<Object?> get props => [
    id,
    hour,
    minute,
    label,
    repeatWeekdays,
    snoozeMinutes,
    enabled,
  ];
}

/// Persistent manager synchronizing personal alarms with OS `AlarmManager.setAlarmClock`.
class PersonalAlarmStore {
  static const String _storageKey = 'lifeos_personal_alarms_v1';
  static const Uuid _uuid = Uuid();

  static final PersonalAlarmStore instance = PersonalAlarmStore._();
  PersonalAlarmStore._();

  static String formatCountdownVi(DateTime target, DateTime now) {
    final diff = target.difference(now);
    if (diff.inSeconds <= 60) {
      return 'Đổ chuông trong chưa đầy 1 phút';
    }
    final totalMins = (diff.inSeconds / 60).ceil();
    final days = totalMins ~/ (24 * 60);
    final remAfterDays = totalMins % (24 * 60);
    final hours = remAfterDays ~/ 60;
    final mins = remAfterDays % 60;

    if (days > 0) {
      return hours > 0
          ? 'Đổ chuông sau $days ngày $hours giờ'
          : 'Đổ chuông sau $days ngày';
    }
    if (hours > 0) {
      return mins > 0
          ? 'Đổ chuông sau $hours giờ $mins phút'
          : 'Đổ chuông sau $hours giờ';
    }
    return 'Đổ chuông sau $mins phút';
  }

  Future<List<PersonalAlarmItem>> loadAlarms() async {
    final raw = await NativeSecureVaultBridge.instance.readSecret(_storageKey);
    if (raw == null || raw.trim().isEmpty) {
      return const <PersonalAlarmItem>[];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <PersonalAlarmItem>[];
      final list =
          decoded
              .whereType<Map<dynamic, dynamic>>()
              .map(
                (m) => PersonalAlarmItem.fromJson(Map<String, dynamic>.from(m)),
              )
              .toList()
            ..sort((a, b) {
              final cmpH = a.hour.compareTo(b.hour);
              return cmpH != 0 ? cmpH : a.minute.compareTo(b.minute);
            });
      return list;
    } catch (_) {
      return const <PersonalAlarmItem>[];
    }
  }

  Future<void> _persist(List<PersonalAlarmItem> items) async {
    final sorted = List<PersonalAlarmItem>.from(items)
      ..sort((a, b) {
        final cmpH = a.hour.compareTo(b.hour);
        return cmpH != 0 ? cmpH : a.minute.compareTo(b.minute);
      });
    await NativeSecureVaultBridge.instance.writeSecret(
      key: _storageKey,
      value: jsonEncode(sorted.map((e) => e.toJson()).toList()),
    );
  }

  Future<PersonalAlarmItem> upsertAlarm({
    String? existingId,
    required int hour,
    required int minute,
    required String label,
    List<int> repeatWeekdays = const <int>[],
    int snoozeMinutes = 5,
    bool enabled = true,
    DateTime? nowOverride,
  }) async {
    final current = await loadAlarms();
    final id = existingId ?? 'palarm_${_uuid.v4().substring(0, 8)}';
    final cleanLabel = label.trim().isEmpty ? 'Báo thức' : label.trim();
    final days = repeatWeekdays.where((d) => d >= 1 && d <= 7).toSet().toList()
      ..sort();

    final item = PersonalAlarmItem(
      id: id,
      hour: hour.clamp(0, 23),
      minute: minute.clamp(0, 59),
      label: cleanLabel,
      repeatWeekdays: List<int>.unmodifiable(days),
      snoozeMinutes: snoozeMinutes.clamp(1, 30),
      enabled: enabled,
    );

    final updated = <PersonalAlarmItem>[
      for (final existing in current)
        if (existing.id != id) existing,
      item,
    ];
    await _persist(updated);
    await _syncOsSchedule(item, now: nowOverride ?? DateTime.now());
    return item;
  }

  Future<List<PersonalAlarmItem>> toggleAlarm(
    String id,
    bool enabled, {
    DateTime? nowOverride,
  }) async {
    final current = await loadAlarms();
    final updated = <PersonalAlarmItem>[];
    PersonalAlarmItem? toggled;
    for (final item in current) {
      if (item.id == id) {
        toggled = item.copyWith(enabled: enabled);
        updated.add(toggled);
      } else {
        updated.add(item);
      }
    }
    await _persist(updated);
    if (toggled != null) {
      await _syncOsSchedule(toggled, now: nowOverride ?? DateTime.now());
    }
    return loadAlarms();
  }

  Future<List<PersonalAlarmItem>> deleteAlarm(String id) async {
    final current = await loadAlarms();
    final updated = current.where((a) => a.id != id).toList();
    await _persist(updated);
    await NativeAlarmSchedulerBridge.instance.cancelEventAlarm(id);
    return updated;
  }

  /// Called when an alarm is dismissed on the ringing screen:
  /// - One-time alarms automatically turn off (`enabled = false`).
  /// - Recurring weekday alarms automatically schedule their next matching day!
  Future<void> handleAlarmDismissed(String id, {DateTime? nowOverride}) async {
    if (!id.startsWith('palarm_')) return;
    final refNow = nowOverride ?? DateTime.now();
    final current = await loadAlarms();
    final idx = current.indexWhere((a) => a.id == id);
    if (idx < 0) return;

    final target = current[idx];
    if (!target.isRecurring) {
      final disabled = target.copyWith(enabled: false);
      final updated = List<PersonalAlarmItem>.from(current)..[idx] = disabled;
      await _persist(updated);
      await NativeAlarmSchedulerBridge.instance.cancelEventAlarm(id);
    } else if (target.enabled) {
      await _syncOsSchedule(
        target,
        now: refNow.add(const Duration(minutes: 1)),
      );
    }
  }

  Future<void> _syncOsSchedule(
    PersonalAlarmItem alarm, {
    required DateTime now,
  }) async {
    if (!alarm.enabled) {
      await NativeAlarmSchedulerBridge.instance.cancelEventAlarm(alarm.id);
      return;
    }
    final nextAt = alarm.computeNextTriggerAt(now);
    await NativeAlarmSchedulerBridge.instance.scheduleEventAlarm(
      eventId: alarm.id,
      title: alarm.label,
      subtitle: '${alarm.formattedTime} · ${alarm.repeatSummaryVi}',
      eventStartsAt: nextAt,
      minutesBefore: 0,
      fullScreen: true,
    );
  }
}
