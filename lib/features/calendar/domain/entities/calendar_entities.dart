import 'package:equatable/equatable.dart';

enum CalendarEventVisibility { privateEvent, sharedEvent }

enum CalendarProviderSource { lifeOsPrivate, lifeOsFamily, googleCalendar }

enum CalendarSyncStatus { localOnly, synced, pendingUpload, pendingDelete, syncConflict }

enum RecurrenceFrequency { none, daily, weekly, monthly, yearly }

/// RFC 5545 RRULE value object compatible with Google Calendar API v3 `recurrence` array.
class CalendarRecurrenceRule extends Equatable {
  static const List<String> allWeekDayCodes = <String>[
    'MO',
    'TU',
    'WE',
    'TH',
    'FR',
    'SA',
    'SU',
  ];

  static const CalendarRecurrenceRule none = CalendarRecurrenceRule();

  final RecurrenceFrequency frequency;
  final int interval;
  final List<String> byWeekDays;
  final int? count;
  final DateTime? until;

  const CalendarRecurrenceRule({
    this.frequency = RecurrenceFrequency.none,
    this.interval = 1,
    this.byWeekDays = const <String>[],
    this.count,
    this.until,
  });

  bool get isRecurring => frequency != RecurrenceFrequency.none;

  /// Encodes to exact RFC 5545 `RRULE:...` string required by Google Calendar API v3.
  String? toRruleString() {
    if (!isRecurring) return null;
    final parts = <String>[
      'FREQ=${frequency.name.toUpperCase()}',
      if (interval > 1) 'INTERVAL=$interval',
    ];
    if (frequency == RecurrenceFrequency.weekly && byWeekDays.isNotEmpty) {
      final normalized = byWeekDays
          .map((d) => d.trim().toUpperCase())
          .where(allWeekDayCodes.contains)
          .toSet()
          .toList();
      if (normalized.isNotEmpty) {
        parts.add('BYDAY=${normalized.join(',')}');
      }
    }
    if (count != null && count! > 0) {
      parts.add('COUNT=$count');
    } else if (until != null) {
      final u = until!.toUtc();
      final y = u.year.toString().padLeft(4, '0');
      final m = u.month.toString().padLeft(2, '0');
      final d = u.day.toString().padLeft(2, '0');
      parts.add('UNTIL=$y$m${d}T235959Z');
    }
    return 'RRULE:${parts.join(';')}';
  }

  /// Parses an RFC 5545 `RRULE:...` string (e.g. from Google Calendar API v3) into a domain rule.
  factory CalendarRecurrenceRule.fromRruleString(String? raw) {
    if (raw == null || raw.trim().isEmpty) return CalendarRecurrenceRule.none;
    var body = raw.trim();
    if (body.toUpperCase().startsWith('RRULE:')) {
      body = body.substring(6);
    }
    final kv = <String, String>{};
    for (final segment in body.split(';')) {
      final idx = segment.indexOf('=');
      if (idx <= 0) continue;
      final k = segment.substring(0, idx).trim().toUpperCase();
      final v = segment.substring(idx + 1).trim();
      kv[k] = v;
    }

    final freq = switch (kv['FREQ']?.toUpperCase()) {
      'DAILY' => RecurrenceFrequency.daily,
      'WEEKLY' => RecurrenceFrequency.weekly,
      'MONTHLY' => RecurrenceFrequency.monthly,
      'YEARLY' => RecurrenceFrequency.yearly,
      _ => RecurrenceFrequency.none,
    };
    if (freq == RecurrenceFrequency.none) return CalendarRecurrenceRule.none;

    final interval = int.tryParse(kv['INTERVAL'] ?? '1') ?? 1;
    final count = kv['COUNT'] != null ? int.tryParse(kv['COUNT']!) : null;
    final byDayRaw = kv['BYDAY'];
    final byDays = byDayRaw != null && byDayRaw.isNotEmpty
        ? byDayRaw
            .split(',')
            .map((s) => s.replaceAll(RegExp(r'[^A-Za-z]'), '').toUpperCase())
            .where(allWeekDayCodes.contains)
            .toList()
        : const <String>[];

    DateTime? parsedUntil;
    final untilRaw = kv['UNTIL'];
    if (untilRaw != null && untilRaw.length >= 8) {
      final y = int.tryParse(untilRaw.substring(0, 4));
      final m = int.tryParse(untilRaw.substring(4, 6));
      final d = int.tryParse(untilRaw.substring(6, 8));
      if (y != null && m != null && d != null) {
        parsedUntil = DateTime.utc(y, m, d, 23, 59, 59);
      }
    }

    return CalendarRecurrenceRule(
      frequency: freq,
      interval: interval < 1 ? 1 : interval,
      byWeekDays: byDays,
      count: count,
      until: parsedUntil,
    );
  }

  static String weekDayCodeForDate(DateTime dt) {
    return allWeekDayCodes[(dt.weekday - 1).clamp(0, 6)];
  }

  static String weekDayLabelVi(String code) {
    return switch (code.toUpperCase()) {
      'MO' => 'T2',
      'TU' => 'T3',
      'WE' => 'T4',
      'TH' => 'T5',
      'FR' => 'T6',
      'SA' => 'T7',
      'SU' => 'CN',
      _ => code,
    };
  }

  String get humanReadableVi {
    if (!isRecurring) return 'Không lặp';
    final base = switch (frequency) {
      RecurrenceFrequency.none => 'Không lặp',
      RecurrenceFrequency.daily => interval == 1 ? 'Hằng ngày' : 'Mỗi $interval ngày',
      RecurrenceFrequency.weekly => interval == 1 ? 'Hằng tuần' : 'Mỗi $interval tuần',
      RecurrenceFrequency.monthly => interval == 1 ? 'Hằng tháng' : 'Mỗi $interval tháng',
      RecurrenceFrequency.yearly => interval == 1 ? 'Hằng năm' : 'Mỗi $interval năm',
    };
    final daysSuffix = (frequency == RecurrenceFrequency.weekly && byWeekDays.isNotEmpty)
        ? ' (${byWeekDays.map(weekDayLabelVi).join(', ')})'
        : '';
    final limitSuffix = count != null && count! > 0
        ? ' · $count lần'
        : until != null
            ? ' · đến ${until!.day.toString().padLeft(2, '0')}/${until!.month.toString().padLeft(2, '0')}/${until!.year}'
            : '';
    return '$base$daysSuffix$limitSuffix';
  }

  /// Generates recurring start timestamps falling inside `[windowStart, windowEnd]`.
  List<DateTime> expandOccurrences({
    required DateTime firstStart,
    required DateTime windowStart,
    required DateTime windowEnd,
    int maxInstances = 60,
  }) {
    if (!isRecurring) {
      if (!firstStart.isBefore(windowStart) && !firstStart.isAfter(windowEnd)) {
        return <DateTime>[firstStart];
      }
      return const <DateTime>[];
    }

    final results = <DateTime>[];
    var generatedTotal = 0;
    var cursor = firstStart;
    final safeInterval = interval < 1 ? 1 : interval;

    while (!cursor.isAfter(windowEnd) && results.length < maxInstances) {
      if (until != null && cursor.toUtc().isAfter(until!)) break;
      if (count != null && generatedTotal >= count!) break;

      if (frequency == RecurrenceFrequency.weekly && byWeekDays.isNotEmpty) {
        final weekMonday = cursor.subtract(Duration(days: cursor.weekday - 1));
        for (var offset = 0; offset < 7; offset++) {
          final dayCandidate = DateTime(
            weekMonday.year,
            weekMonday.month,
            weekMonday.day + offset,
            firstStart.hour,
            firstStart.minute,
          );
          if (dayCandidate.isBefore(firstStart)) continue;
          if (until != null && dayCandidate.toUtc().isAfter(until!)) break;
          if (count != null && generatedTotal >= count!) break;

          final code = weekDayCodeForDate(dayCandidate);
          if (byWeekDays.contains(code)) {
            generatedTotal++;
            if (!dayCandidate.isBefore(windowStart) && !dayCandidate.isAfter(windowEnd)) {
              results.add(dayCandidate);
            }
          }
        }
        cursor = weekMonday.add(Duration(days: 7 * safeInterval));
      } else {
        generatedTotal++;
        if (!cursor.isBefore(windowStart) && !cursor.isAfter(windowEnd)) {
          results.add(cursor);
        }
        cursor = switch (frequency) {
          RecurrenceFrequency.daily => cursor.add(Duration(days: safeInterval)),
          RecurrenceFrequency.weekly => cursor.add(Duration(days: 7 * safeInterval)),
          RecurrenceFrequency.monthly => DateTime(
              cursor.year,
              cursor.month + safeInterval,
              cursor.day,
              cursor.hour,
              cursor.minute,
            ),
          RecurrenceFrequency.yearly => DateTime(
              cursor.year + safeInterval,
              cursor.month,
              cursor.day,
              cursor.hour,
              cursor.minute,
            ),
          RecurrenceFrequency.none => windowEnd.add(const Duration(days: 1)),
        };
      }
    }
    return results;
  }

  @override
  List<Object?> get props => [frequency, interval, byWeekDays, count, until];
}

class ManagedCalendarEntity extends Equatable {
  final String id;
  final String ownerId;
  final String summary;
  final String? description;
  final String timeZone;
  final String colorHex;
  final bool isPrimary;
  final bool isSelected;
  final bool isReadOnly;
  final CalendarProviderSource source;
  final String? googleCalendarId;
  final String? googleSyncToken;
  final DateTime? lastSyncedAt;

  const ManagedCalendarEntity({
    required this.id,
    required this.ownerId,
    required this.summary,
    this.description,
    this.timeZone = 'Asia/Ho_Chi_Minh',
    this.colorHex = '#0B7A2A',
    this.isPrimary = false,
    this.isSelected = true,
    this.isReadOnly = false,
    this.source = CalendarProviderSource.lifeOsPrivate,
    this.googleCalendarId,
    this.googleSyncToken,
    this.lastSyncedAt,
  });

  bool get isGoogleSynced =>
      source == CalendarProviderSource.googleCalendar ||
      (googleCalendarId != null && googleCalendarId!.isNotEmpty);

  ManagedCalendarEntity copyWith({
    String? summary,
    String? description,
    String? timeZone,
    String? colorHex,
    bool? isPrimary,
    bool? isSelected,
    bool? isReadOnly,
    CalendarProviderSource? source,
    String? googleCalendarId,
    String? googleSyncToken,
    bool clearSyncToken = false,
    DateTime? lastSyncedAt,
  }) {
    return ManagedCalendarEntity(
      id: id,
      ownerId: ownerId,
      summary: summary ?? this.summary,
      description: description ?? this.description,
      timeZone: timeZone ?? this.timeZone,
      colorHex: colorHex ?? this.colorHex,
      isPrimary: isPrimary ?? this.isPrimary,
      isSelected: isSelected ?? this.isSelected,
      isReadOnly: isReadOnly ?? this.isReadOnly,
      source: source ?? this.source,
      googleCalendarId: googleCalendarId ?? this.googleCalendarId,
      googleSyncToken: clearSyncToken ? null : (googleSyncToken ?? this.googleSyncToken),
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        ownerId,
        summary,
        description,
        timeZone,
        colorHex,
        isPrimary,
        isSelected,
        source,
        googleCalendarId,
        googleSyncToken,
        lastSyncedAt,
      ];
}

class CalendarEventEntity extends Equatable {
  final String id;
  final String calendarId;
  final String ownerId;
  final String ownerName;
  final String? familyId;
  final CalendarEventVisibility visibility;
  final String title;
  final String? description;
  final String? location;
  final DateTime startsAt;
  final DateTime endsAt;
  final bool isAllDay;
  final String timeZone;
  final String? colorHex;
  final int reminderMinutesBefore;
  final CalendarRecurrenceRule recurrence;
  final String? googleEventId;
  final String? googleCalendarId;
  final String? googleEtag;
  final CalendarSyncStatus syncStatus;
  final DateTime? updatedAt;

  const CalendarEventEntity({
    required this.id,
    this.calendarId = 'primary',
    required this.ownerId,
    required this.ownerName,
    this.familyId,
    required this.visibility,
    required this.title,
    this.description,
    this.location,
    required this.startsAt,
    required this.endsAt,
    this.isAllDay = false,
    this.timeZone = 'Asia/Ho_Chi_Minh',
    this.colorHex,
    this.reminderMinutesBefore = 30,
    this.recurrence = CalendarRecurrenceRule.none,
    this.googleEventId,
    this.googleCalendarId,
    this.googleEtag,
    this.syncStatus = CalendarSyncStatus.localOnly,
    this.updatedAt,
  });

  bool get isRecurring => recurrence.isRecurring;

  bool get isLinkedWithGoogle => googleEventId != null && googleEventId!.isNotEmpty;

  CalendarEventEntity copyWith({
    String? calendarId,
    CalendarEventVisibility? visibility,
    String? title,
    String? description,
    String? location,
    DateTime? startsAt,
    DateTime? endsAt,
    bool? isAllDay,
    String? timeZone,
    String? colorHex,
    int? reminderMinutesBefore,
    CalendarRecurrenceRule? recurrence,
    String? googleEventId,
    String? googleCalendarId,
    String? googleEtag,
    CalendarSyncStatus? syncStatus,
    DateTime? updatedAt,
  }) {
    return CalendarEventEntity(
      id: id,
      calendarId: calendarId ?? this.calendarId,
      ownerId: ownerId,
      ownerName: ownerName,
      familyId: familyId,
      visibility: visibility ?? this.visibility,
      title: title ?? this.title,
      description: description ?? this.description,
      location: location ?? this.location,
      startsAt: startsAt ?? this.startsAt,
      endsAt: endsAt ?? this.endsAt,
      isAllDay: isAllDay ?? this.isAllDay,
      timeZone: timeZone ?? this.timeZone,
      colorHex: colorHex ?? this.colorHex,
      reminderMinutesBefore: reminderMinutesBefore ?? this.reminderMinutesBefore,
      recurrence: recurrence ?? this.recurrence,
      googleEventId: googleEventId ?? this.googleEventId,
      googleCalendarId: googleCalendarId ?? this.googleCalendarId,
      googleEtag: googleEtag ?? this.googleEtag,
      syncStatus: syncStatus ?? this.syncStatus,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        calendarId,
        ownerId,
        ownerName,
        familyId,
        visibility,
        title,
        description,
        location,
        startsAt,
        endsAt,
        isAllDay,
        timeZone,
        colorHex,
        reminderMinutesBefore,
        recurrence,
        googleEventId,
        googleCalendarId,
        googleEtag,
        syncStatus,
        updatedAt,
      ];
}

class GoogleCalendarSyncReport extends Equatable {
  final int calendarsSynced;
  final int pulledUpserted;
  final int pulledDeleted;
  final int pushedUpserted;
  final int pushedDeleted;
  final bool usedIncrementalSyncToken;
  final DateTime syncedAt;

  const GoogleCalendarSyncReport({
    required this.calendarsSynced,
    required this.pulledUpserted,
    required this.pulledDeleted,
    required this.pushedUpserted,
    required this.pushedDeleted,
    required this.usedIncrementalSyncToken,
    required this.syncedAt,
  });

  String get summaryVi {
    final mode = usedIncrementalSyncToken ? 'Delta SyncToken' : 'Full Sync';
    return 'Đồng bộ Google Calendar ($mode): $calendarsSynced lịch · '
        'tải về $pulledUpserted, đẩy lên $pushedUpserted, xóa $pulledDeleted/$pushedDeleted sự kiện.';
  }

  @override
  List<Object?> get props => [
        calendarsSynced,
        pulledUpserted,
        pulledDeleted,
        pushedUpserted,
        pushedDeleted,
        usedIncrementalSyncToken,
        syncedAt,
      ];
}

class BusySlotEntity extends Equatable {
  final String id;
  final String ownerId;
  final String ownerName;
  final DateTime startsAt;
  final DateTime endsAt;

  const BusySlotEntity({
    required this.id,
    required this.ownerId,
    required this.ownerName,
    required this.startsAt,
    required this.endsAt,
  });

  @override
  List<Object?> get props => [id, ownerId, ownerName, startsAt, endsAt];
}
