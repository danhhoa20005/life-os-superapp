import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
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
/// Strictly partitioned per account UID (`lifeos_personal_alarms_v2__u_<uid>`) so
/// shared devices never leak alarms across accounts (M10 + ALARM-01).
class PersonalAlarmStore {
  static const String _legacyStorageKey = 'lifeos_personal_alarms_v1';
  static const String legacyQuarantineStorageKey =
      'lifeos_personal_alarms_legacy_quarantine_v1';
  static const String _scopedKeyPrefix = 'lifeos_personal_alarms_v2__u_';
  static const String _standaloneTestUser = '__standalone_test_user__';
  static const Uuid _uuid = Uuid();

  static final PersonalAlarmStore instance = PersonalAlarmStore._();
  PersonalAlarmStore._();

  String? _activeUserId;
  bool _userScopingConfigured = false;
  int _sessionGeneration = 0;
  bool _opRunning = false;
  int _queueEpoch = 0;
  final ListQueue<Completer<void>> _opWaiters = ListQueue<Completer<void>>();

  String? get activeUserId => _activeUserId;

  @visibleForTesting
  int get sessionGeneration => _sessionGeneration;

  static String _scopedStorageKey(String uid) =>
      '$_scopedKeyPrefix${uid.trim()}';

  static String sanitizeUidSegment(String uid) {
    final trimmed = uid.trim();
    if (trimmed.isEmpty) return 'unknown';
    return trimmed.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
  }

  static String osAlarmPrefixForUser(String uid) =>
      'palarm_${sanitizeUidSegment(uid)}_';

  /// UID-namespaced OS alarm identifier (`palarm_<safeUid>_<alarmId>`) so one
  /// account's cancel/resync never collides with or wipes another user's alarms.
  static String osAlarmIdFor(String uid, String alarmId) {
    final prefix = osAlarmPrefixForUser(uid);
    if (alarmId.startsWith(prefix)) return alarmId;
    return '$prefix$alarmId';
  }

  /// Serializes all async state/OS-alarm mutations strictly FIFO without
  /// retaining cross-zone `Future` references while idle (preventing `FakeAsync`
  /// tests after `test()` or `setUp()` from stalling on foreign-zone futures).
  Future<T> _enqueueOp<T>(Future<T> Function() action) async {
    final epoch = _queueEpoch;
    if (_opRunning) {
      final gate = Completer<void>();
      _opWaiters.addLast(gate);
      await gate.future;
      if (epoch != _queueEpoch) {
        return _enqueueOp(action);
      }
    } else {
      _opRunning = true;
    }

    try {
      return await action();
    } finally {
      if (epoch == _queueEpoch) {
        if (_opWaiters.isNotEmpty) {
          _opWaiters.removeFirst().complete();
        } else {
          _opRunning = false;
        }
      }
    }
  }

  @visibleForTesting
  Future<void> flushPendingOperations() {
    if (!_opRunning && _opWaiters.isEmpty) {
      return Future<void>.value();
    }
    return _enqueueOp(() async {});
  }

  String? _resolveUid(String? userId) {
    if (userId != null) {
      final trimmed = userId.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    if (_userScopingConfigured) {
      final active = _activeUserId?.trim();
      return (active == null || active.isEmpty) ? null : active;
    }
    return _standaloneTestUser;
  }

  bool _isActiveOsScope(String uid, {int? expectedEpoch}) =>
      (expectedEpoch == null || _sessionGeneration == expectedEpoch) &&
      (!_userScopingConfigured || _activeUserId == uid);

  static List<PersonalAlarmItem> _decodeAlarmList(String? raw) {
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

  /// Non-destructive quarantine (ALARM-01): moves legacy unscoped
  /// `lifeos_personal_alarms_v1` items into `lifeos_personal_alarms_legacy_quarantine_v1`
  /// instead of permanently destroying user data, then removes the legacy key.
  Future<void> _quarantineLegacyUnscopedKey() async {
    final legacyRaw = await NativeSecureVaultBridge.instance.readSecret(
      _legacyStorageKey,
    );
    if (legacyRaw == null) return;

    final legacyItems = _decodeAlarmList(legacyRaw);
    if (legacyItems.isNotEmpty) {
      final existingQuarantined = _decodeAlarmList(
        await NativeSecureVaultBridge.instance.readSecret(
          legacyQuarantineStorageKey,
        ),
      );
      final mergedById = <String, PersonalAlarmItem>{
        for (final item in existingQuarantined) item.id: item,
        for (final item in legacyItems) item.id: item,
      };
      final sorted = mergedById.values.toList()
        ..sort((a, b) {
          final cmpH = a.hour.compareTo(b.hour);
          return cmpH != 0 ? cmpH : a.minute.compareTo(b.minute);
        });
      await NativeSecureVaultBridge.instance.writeSecret(
        key: legacyQuarantineStorageKey,
        value: jsonEncode(sorted.map((e) => e.toJson()).toList()),
      );
    }
    await NativeSecureVaultBridge.instance.deleteSecret(_legacyStorageKey);
  }

  Future<void> _cancelUserOsAlarms(String uid) async {
    final userPrefix = osAlarmPrefixForUser(uid);
    final alarms = await _readStoredAlarmsForUid(uid);
    final idsToCancel = <String>{
      for (final alarm in alarms) osAlarmIdFor(uid, alarm.id),
      for (final alarm in alarms) alarm.id,
    };
    final osAlarms = await NativeAlarmSchedulerBridge.instance
        .listScheduledAlarms();
    for (final osAlarm in osAlarms) {
      if (osAlarm.eventId.startsWith(userPrefix)) {
        idsToCancel.add(osAlarm.eventId);
      }
    }
    for (final osId in idsToCancel) {
      await NativeAlarmSchedulerBridge.instance.cancelEventAlarm(osId);
    }
  }

  Future<void> _resyncEnabledOsAlarms(
    String uid, {
    required int expectedEpoch,
  }) async {
    if (_sessionGeneration != expectedEpoch || _activeUserId != uid) return;
    final alarms = await _readStoredAlarmsForUid(uid);
    if (_sessionGeneration != expectedEpoch || _activeUserId != uid) return;
    final now = DateTime.now();
    for (final alarm in alarms) {
      if (_sessionGeneration != expectedEpoch || _activeUserId != uid) return;
      if (alarm.enabled) {
        await _syncOsSchedule(uid, alarm, now: now);
      }
    }
  }

  /// Binds personal alarm persistence to [userId] (or clears when null/empty)
  /// and moves any legacy unscoped `lifeos_personal_alarms_v1` key to
  /// non-destructive quarantine.
  ///
  /// Serialized via [_opChain] and guarded by monotonic [_sessionGeneration] so
  /// rapid `A -> B -> A` switches never allow an older async cancel/resync to
  /// wipe the latest active user's OS alarms.
  void setActiveUserId(String? userId) {
    _userScopingConfigured = true;
    final cleaned = userId?.trim();
    final nextUid = (cleaned == null || cleaned.isEmpty) ? null : cleaned;
    final prevUid = _activeUserId;
    final targetEpoch = ++_sessionGeneration;
    _activeUserId = nextUid;
    unawaited(
      _enqueueOp(() async {
        await _quarantineLegacyUnscopedKey();
        if (prevUid != null && prevUid != nextUid && prevUid != _activeUserId) {
          await _cancelUserOsAlarms(prevUid);
        }
        if (nextUid != null &&
            _sessionGeneration == targetEpoch &&
            _activeUserId == nextUid) {
          await _resyncEnabledOsAlarms(nextUid, expectedEpoch: targetEpoch);
        }
      }),
    );
  }

  /// Clears active user session and cancels OS scheduled alarms on sign-out
  /// while preserving the signed-out user's encrypted alarm list in vault.
  Future<void> clearSessionOnSignOut() {
    _userScopingConfigured = true;
    final prevUid = _activeUserId;
    final targetEpoch = ++_sessionGeneration;
    _activeUserId = null;
    return _enqueueOp(() async {
      await _quarantineLegacyUnscopedKey();
      if (prevUid != null && prevUid != _activeUserId) {
        await _cancelUserOsAlarms(prevUid);
      }
      if (_sessionGeneration == targetEpoch && _activeUserId == null) {
        final osAlarms = await NativeAlarmSchedulerBridge.instance
            .listScheduledAlarms();
        for (final osAlarm in osAlarms) {
          if (osAlarm.eventId.startsWith('palarm_')) {
            await NativeAlarmSchedulerBridge.instance.cancelEventAlarm(
              osAlarm.eventId,
            );
          }
        }
      }
    });
  }

  @visibleForTesting
  void resetScopingForTest() {
    _sessionGeneration += 1;
    _queueEpoch += 1;
    _activeUserId = null;
    _userScopingConfigured = false;
    _opRunning = false;
    while (_opWaiters.isNotEmpty) {
      final gate = _opWaiters.removeFirst();
      if (!gate.isCompleted) gate.complete();
    }
  }

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

  Future<List<PersonalAlarmItem>> _readStoredAlarmsForUid(String uid) async {
    final raw = await NativeSecureVaultBridge.instance.readSecret(
      _scopedStorageKey(uid),
    );
    return _decodeAlarmList(raw);
  }

  Future<List<PersonalAlarmItem>> _loadAlarmsUnlocked({String? userId}) async {
    await _quarantineLegacyUnscopedKey();
    final uid = _resolveUid(userId);
    if (uid == null) {
      return const <PersonalAlarmItem>[];
    }
    return _readStoredAlarmsForUid(uid);
  }

  Future<void> _saveAlarmsUnlocked(
    List<PersonalAlarmItem> items, {
    String? userId,
  }) async {
    final uid = _resolveUid(userId);
    if (uid == null) return;
    final sorted = List<PersonalAlarmItem>.from(items)
      ..sort((a, b) {
        final cmpH = a.hour.compareTo(b.hour);
        return cmpH != 0 ? cmpH : a.minute.compareTo(b.minute);
      });
    await NativeSecureVaultBridge.instance.writeSecret(
      key: _scopedStorageKey(uid),
      value: jsonEncode(sorted.map((e) => e.toJson()).toList()),
    );
  }

  Future<List<PersonalAlarmItem>> loadAlarms({String? userId}) {
    return _enqueueOp(() => _loadAlarmsUnlocked(userId: userId));
  }

  Future<void> saveAlarms(List<PersonalAlarmItem> items, {String? userId}) {
    return _enqueueOp(() => _saveAlarmsUnlocked(items, userId: userId));
  }

  /// Loads legacy alarms moved into non-destructive quarantine (`lifeos_personal_alarms_legacy_quarantine_v1`).
  Future<List<PersonalAlarmItem>> loadQuarantinedLegacyAlarms() {
    return _enqueueOp(() async {
      await _quarantineLegacyUnscopedKey();
      final raw = await NativeSecureVaultBridge.instance.readSecret(
        legacyQuarantineStorageKey,
      );
      return _decodeAlarmList(raw);
    });
  }

  /// Explicitly imports quarantined legacy alarms into the active (or specified)
  /// user's scoped alarm store and clears the quarantine slot once imported.
  Future<List<PersonalAlarmItem>> importQuarantinedLegacyAlarmsForActiveUser({
    String? userId,
    DateTime? nowOverride,
  }) {
    return _enqueueOp(() async {
      await _quarantineLegacyUnscopedKey();
      final uid = _resolveUid(userId);
      if (uid == null) {
        return const <PersonalAlarmItem>[];
      }
      final quarantined = _decodeAlarmList(
        await NativeSecureVaultBridge.instance.readSecret(
          legacyQuarantineStorageKey,
        ),
      );
      final current = await _readStoredAlarmsForUid(uid);
      if (quarantined.isEmpty) {
        return current;
      }

      final epoch = _sessionGeneration;
      final mergedById = <String, PersonalAlarmItem>{
        for (final item in quarantined) item.id: item,
        for (final item in current) item.id: item,
      };
      final mergedList = mergedById.values.toList()
        ..sort((a, b) {
          final cmpH = a.hour.compareTo(b.hour);
          return cmpH != 0 ? cmpH : a.minute.compareTo(b.minute);
        });
      await _saveAlarmsUnlocked(mergedList, userId: uid);
      await NativeSecureVaultBridge.instance.deleteSecret(
        legacyQuarantineStorageKey,
      );

      if (_isActiveOsScope(uid, expectedEpoch: epoch)) {
        final now = nowOverride ?? DateTime.now();
        for (final alarm in mergedList) {
          if (_isActiveOsScope(uid, expectedEpoch: epoch) && alarm.enabled) {
            await _syncOsSchedule(uid, alarm, now: now);
          }
        }
      }
      return mergedList;
    });
  }

  /// Explicitly discards quarantined legacy alarms when the user chooses not
  /// to recover them.
  Future<void> discardQuarantinedLegacyAlarms() {
    return _enqueueOp(() async {
      await NativeSecureVaultBridge.instance.deleteSecret(_legacyStorageKey);
      await NativeSecureVaultBridge.instance.deleteSecret(
        legacyQuarantineStorageKey,
      );
    });
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
    String? userId,
  }) {
    return _enqueueOp(() async {
      final id = existingId ?? 'palarm_${_uuid.v4().substring(0, 8)}';
      final cleanLabel = label.trim().isEmpty ? 'Báo thức' : label.trim();
      final days =
          repeatWeekdays.where((d) => d >= 1 && d <= 7).toSet().toList()
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

      final epoch = _sessionGeneration;
      final uid = _resolveUid(userId);
      if (uid == null) {
        return item.copyWith(enabled: false);
      }

      final current = await _loadAlarmsUnlocked(userId: uid);
      final updated = <PersonalAlarmItem>[
        for (final existing in current)
          if (existing.id != id) existing,
        item,
      ];
      await _saveAlarmsUnlocked(updated, userId: uid);
      if (_isActiveOsScope(uid, expectedEpoch: epoch)) {
        await _syncOsSchedule(uid, item, now: nowOverride ?? DateTime.now());
      }
      return item;
    });
  }

  Future<List<PersonalAlarmItem>> toggleAlarm(
    String id,
    bool enabled, {
    DateTime? nowOverride,
    String? userId,
  }) {
    return _enqueueOp(() async {
      final epoch = _sessionGeneration;
      final uid = _resolveUid(userId);
      if (uid == null) {
        return const <PersonalAlarmItem>[];
      }
      final current = await _loadAlarmsUnlocked(userId: uid);
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
      await _saveAlarmsUnlocked(updated, userId: uid);
      if (toggled != null && _isActiveOsScope(uid, expectedEpoch: epoch)) {
        await _syncOsSchedule(uid, toggled, now: nowOverride ?? DateTime.now());
      }
      return _loadAlarmsUnlocked(userId: uid);
    });
  }

  Future<List<PersonalAlarmItem>> deleteAlarm(String id, {String? userId}) {
    return _enqueueOp(() async {
      final epoch = _sessionGeneration;
      final uid = _resolveUid(userId);
      if (uid == null) {
        return const <PersonalAlarmItem>[];
      }
      final current = await _loadAlarmsUnlocked(userId: uid);
      final updated = current.where((a) => a.id != id).toList();
      await _saveAlarmsUnlocked(updated, userId: uid);
      if (_isActiveOsScope(uid, expectedEpoch: epoch)) {
        await NativeAlarmSchedulerBridge.instance.cancelEventAlarm(
          osAlarmIdFor(uid, id),
        );
        await NativeAlarmSchedulerBridge.instance.cancelEventAlarm(id);
      }
      return updated;
    });
  }

  /// Called when an alarm is dismissed on the ringing screen:
  /// - One-time alarms automatically turn off (`enabled = false`).
  /// - Recurring weekday alarms automatically schedule their next matching day!
  Future<void> handleAlarmDismissed(
    String id, {
    DateTime? nowOverride,
    String? userId,
  }) {
    return _enqueueOp(() async {
      if (!id.startsWith('palarm_')) return;
      final epoch = _sessionGeneration;
      final uid = _resolveUid(userId);
      if (uid == null) return;
      final refNow = nowOverride ?? DateTime.now();
      final current = await _loadAlarmsUnlocked(userId: uid);
      final idx = current.indexWhere(
        (a) => a.id == id || osAlarmIdFor(uid, a.id) == id,
      );
      if (idx < 0) return;

      final target = current[idx];
      if (!target.isRecurring) {
        final disabled = target.copyWith(enabled: false);
        final updated = List<PersonalAlarmItem>.from(current)..[idx] = disabled;
        await _saveAlarmsUnlocked(updated, userId: uid);
        if (_isActiveOsScope(uid, expectedEpoch: epoch)) {
          await NativeAlarmSchedulerBridge.instance.cancelEventAlarm(
            osAlarmIdFor(uid, target.id),
          );
          if (id != osAlarmIdFor(uid, target.id)) {
            await NativeAlarmSchedulerBridge.instance.cancelEventAlarm(id);
          }
        }
      } else if (target.enabled &&
          _isActiveOsScope(uid, expectedEpoch: epoch)) {
        await _syncOsSchedule(
          uid,
          target,
          now: refNow.add(const Duration(minutes: 1)),
        );
      }
    });
  }

  Future<void> _syncOsSchedule(
    String uid,
    PersonalAlarmItem alarm, {
    required DateTime now,
  }) async {
    final osAlarmId = osAlarmIdFor(uid, alarm.id);
    if (!alarm.enabled) {
      await NativeAlarmSchedulerBridge.instance.cancelEventAlarm(osAlarmId);
      await NativeAlarmSchedulerBridge.instance.cancelEventAlarm(alarm.id);
      return;
    }
    final nextAt = alarm.computeNextTriggerAt(now);
    await NativeAlarmSchedulerBridge.instance.scheduleEventAlarm(
      eventId: osAlarmId,
      title: alarm.label,
      subtitle: '${alarm.formattedTime} · ${alarm.repeatSummaryVi}',
      eventStartsAt: nextAt,
      minutesBefore: 0,
      fullScreen: true,
    );
  }
}
