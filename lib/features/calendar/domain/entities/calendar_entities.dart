import 'package:equatable/equatable.dart';

enum CalendarEventVisibility { privateEvent, sharedEvent }

enum CalendarProviderSource {
  lifeOsPrivate,
  lifeOsFamily,
  googleCalendar,
  deviceCalendar,
}

enum CalendarSyncStatus {
  localOnly,
  synced,
  pendingUpload,
  pendingDelete,
  syncConflict,
}

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
      RecurrenceFrequency.daily =>
        interval == 1 ? 'Hằng ngày' : 'Mỗi $interval ngày',
      RecurrenceFrequency.weekly =>
        interval == 1 ? 'Hằng tuần' : 'Mỗi $interval tuần',
      RecurrenceFrequency.monthly =>
        interval == 1 ? 'Hằng tháng' : 'Mỗi $interval tháng',
      RecurrenceFrequency.yearly =>
        interval == 1 ? 'Hằng năm' : 'Mỗi $interval năm',
    };
    final daysSuffix =
        (frequency == RecurrenceFrequency.weekly && byWeekDays.isNotEmpty)
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
            if (!dayCandidate.isBefore(windowStart) &&
                !dayCandidate.isAfter(windowEnd)) {
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
          RecurrenceFrequency.weekly => cursor.add(
            Duration(days: 7 * safeInterval),
          ),
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
  final int? deviceCalendarId;
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
    this.deviceCalendarId,
    this.lastSyncedAt,
  });

  bool get isGoogleSynced =>
      source == CalendarProviderSource.googleCalendar ||
      (googleCalendarId != null && googleCalendarId!.isNotEmpty);

  bool get isDeviceSynced =>
      source == CalendarProviderSource.deviceCalendar ||
      deviceCalendarId != null;

  bool get isExternalSynced => isGoogleSynced || isDeviceSynced;

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
    int? deviceCalendarId,
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
      googleSyncToken: clearSyncToken
          ? null
          : (googleSyncToken ?? this.googleSyncToken),
      deviceCalendarId: deviceCalendarId ?? this.deviceCalendarId,
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
    isReadOnly,
    source,
    googleCalendarId,
    googleSyncToken,
    deviceCalendarId,
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
  final int? deviceEventId;
  final int? deviceCalendarId;
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
    this.deviceEventId,
    this.deviceCalendarId,
    this.syncStatus = CalendarSyncStatus.localOnly,
    this.updatedAt,
  });

  bool get isRecurring => recurrence.isRecurring;

  bool get isLinkedWithGoogle =>
      googleEventId != null && googleEventId!.isNotEmpty;

  bool get isLinkedWithDeviceCalendar =>
      deviceEventId != null && deviceEventId! > 0;

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
    int? deviceEventId,
    int? deviceCalendarId,
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
      reminderMinutesBefore:
          reminderMinutesBefore ?? this.reminderMinutesBefore,
      recurrence: recurrence ?? this.recurrence,
      googleEventId: googleEventId ?? this.googleEventId,
      googleCalendarId: googleCalendarId ?? this.googleCalendarId,
      googleEtag: googleEtag ?? this.googleEtag,
      deviceEventId: deviceEventId ?? this.deviceEventId,
      deviceCalendarId: deviceCalendarId ?? this.deviceCalendarId,
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
    deviceEventId,
    deviceCalendarId,
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
  final String sourceLabel;

  const GoogleCalendarSyncReport({
    required this.calendarsSynced,
    required this.pulledUpserted,
    required this.pulledDeleted,
    required this.pushedUpserted,
    required this.pushedDeleted,
    required this.usedIncrementalSyncToken,
    required this.syncedAt,
    this.sourceLabel = 'Google Calendar',
  });

  String get summaryVi {
    return 'Đã đồng bộ $sourceLabel: cập nhật $pulledUpserted sự kiện, '
        'gửi lên $pushedUpserted sự kiện.';
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
    sourceLabel,
  ];
}

/// Canonical merged calendar group that collapses duplicate / identical calendars
/// across LifeOS local, Android `CalendarContract` (`devcal_*`), and Google Calendar API.
class DeduplicatedCalendarGroup extends Equatable {
  final String groupKey;
  final String displayTitle;
  final ManagedCalendarEntity representative;
  final List<ManagedCalendarEntity> members;
  final Set<String> memberIds;
  final bool isPrimaryGroup;
  final bool isSystemFeed;

  const DeduplicatedCalendarGroup({
    required this.groupKey,
    required this.displayTitle,
    required this.representative,
    required this.members,
    required this.memberIds,
    required this.isPrimaryGroup,
    required this.isSystemFeed,
  });

  String get canonicalId => representative.id;

  bool get isSelected => members.any((m) => m.isSelected);

  bool get isReadOnly =>
      !isPrimaryGroup && members.every((m) => m.isReadOnly);

  bool get isDeletable =>
      !isPrimaryGroup &&
      !isSystemFeed &&
      members.any((m) => !m.isPrimary && m.id != 'primary' && !m.isReadOnly);

  bool matchesCalendarId(String? calendarId) {
    if (calendarId == null || calendarId.isEmpty) return false;
    if (isPrimaryGroup && calendarId == 'primary') return true;
    return memberIds.contains(calendarId);
  }

  @override
  List<Object?> get props => [
    groupKey,
    displayTitle,
    representative,
    members,
    memberIds,
    isPrimaryGroup,
    isSystemFeed,
  ];
}

class CalendarListDeduplicator {
  const CalendarListDeduplicator._();

  static const Set<String> _genericPersonalSummaries = <String>{
    'lich ca nhan',
    'lich ca nhan chinh',
    'lich ca nhan tren dien thoai',
    'ca nhan',
    'lich cua toi',
    'my calendar',
    'calendar',
    'lich',
    'events',
    'su kien',
    'lich thiet bi',
    'lich lifeos',
    'lich google',
    'pc sync',
    'samsung calendar',
  };

  static const Map<String, String> _viFoldMap = <String, String>{
    'à': 'a', 'á': 'a', 'ạ': 'a', 'ả': 'a', 'ã': 'a',
    'â': 'a', 'ầ': 'a', 'ấ': 'a', 'ậ': 'a', 'ẩ': 'a', 'ẫ': 'a',
    'ă': 'a', 'ằ': 'a', 'ắ': 'a', 'ặ': 'a', 'ẳ': 'a', 'ẵ': 'a',
    'è': 'e', 'é': 'e', 'ẹ': 'e', 'ẻ': 'e', 'ẽ': 'e',
    'ê': 'e', 'ề': 'e', 'ế': 'e', 'ệ': 'e', 'ể': 'e', 'ễ': 'e',
    'ì': 'i', 'í': 'i', 'ị': 'i', 'ỉ': 'i', 'ĩ': 'i',
    'ò': 'o', 'ó': 'o', 'ọ': 'o', 'ỏ': 'o', 'õ': 'o',
    'ô': 'o', 'ồ': 'o', 'ố': 'o', 'ộ': 'o', 'ổ': 'o', 'ỗ': 'o',
    'ơ': 'o', 'ờ': 'o', 'ớ': 'o', 'ợ': 'o', 'ở': 'o', 'ỡ': 'o',
    'ù': 'u', 'ú': 'u', 'ụ': 'u', 'ủ': 'u', 'ũ': 'u',
    'ư': 'u', 'ừ': 'u', 'ứ': 'u', 'ự': 'u', 'ử': 'u', 'ữ': 'u',
    'ỳ': 'y', 'ý': 'y', 'ỵ': 'y', 'ỷ': 'y', 'ỹ': 'y',
    'đ': 'd',
  };

  static String normalizeText(String raw) {
    final lower = raw.trim().toLowerCase();
    if (lower.isEmpty) return '';
    final sb = StringBuffer();
    for (var i = 0; i < lower.length; i++) {
      final ch = lower[i];
      sb.write(_viFoldMap[ch] ?? ch);
    }
    return sb
        .toString()
        .replaceAll(RegExp(r'[^a-z0-9@._]+'), ' ')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  static bool _isHolidayCalendar(ManagedCalendarEntity cal, String norm) {
    final gId = (cal.googleCalendarId ?? '').toLowerCase();
    if (gId.contains('holiday@group.v.calendar.google.com')) return true;
    return norm.contains('ngay le') ||
        norm.contains('holidays in') ||
        norm.contains('public holiday') ||
        norm == 'le tet';
  }

  static bool _isBirthdayCalendar(ManagedCalendarEntity cal, String norm) {
    final gId = (cal.googleCalendarId ?? '').toLowerCase();
    if (gId.contains('contacts@group.v.calendar.google.com')) return true;
    return norm == 'sinh nhat' ||
        norm.contains('sinh nhat ') ||
        norm == 'birthdays' ||
        norm == 'birthday' ||
        norm == 'contacts' ||
        norm == 'danh ba';
  }

  static String canonicalGroupKey(
    ManagedCalendarEntity cal, {
    Set<String> primaryEmails = const <String>{},
  }) {
    final norm = normalizeText(cal.summary);
    if (_isHolidayCalendar(cal, norm)) return '__holiday__';
    if (_isBirthdayCalendar(cal, norm)) return '__birthday__';

    if (cal.isPrimary || cal.id == 'primary') return '__primary__';
    if (!cal.isReadOnly && _genericPersonalSummaries.contains(norm)) {
      return '__primary__';
    }
    final rawTrimmed = cal.summary.trim().toLowerCase();
    if (!cal.isReadOnly &&
        rawTrimmed.contains('@') &&
        (primaryEmails.isEmpty || primaryEmails.contains(rawTrimmed))) {
      return '__primary__';
    }
    return 'custom:${norm.isEmpty ? cal.id : norm}';
  }

  static int _sourcePriority(ManagedCalendarEntity cal) {
    if (cal.id == 'primary') return 0;
    if (cal.isPrimary) return 1;
    return switch (cal.source) {
      CalendarProviderSource.googleCalendar => 2,
      CalendarProviderSource.lifeOsPrivate => 3,
      CalendarProviderSource.lifeOsFamily => 4,
      CalendarProviderSource.deviceCalendar => 5,
    };
  }

  /// Collapses duplicate / equivalent calendars into clean canonical groups.
  static List<DeduplicatedCalendarGroup> group(
    List<ManagedCalendarEntity> rawCalendars,
  ) {
    if (rawCalendars.isEmpty) return const <DeduplicatedCalendarGroup>[];

    final primaryEmails = <String>{};
    for (final cal in rawCalendars) {
      if (cal.isPrimary || cal.id == 'primary') {
        final s = cal.summary.trim().toLowerCase();
        final d = (cal.description ?? '').trim().toLowerCase();
        if (s.contains('@')) primaryEmails.add(s);
        if (d.contains('@')) primaryEmails.add(d);
      }
    }
    // If no explicit email was on `primary`, adopt the first writable email calendar as primary alias
    if (primaryEmails.isEmpty) {
      for (final cal in rawCalendars) {
        final s = cal.summary.trim().toLowerCase();
        if (!cal.isReadOnly && s.contains('@')) {
          primaryEmails.add(s);
          break;
        }
      }
    }

    final buckets = <String, List<ManagedCalendarEntity>>{};
    for (final cal in rawCalendars) {
      final key = canonicalGroupKey(cal, primaryEmails: primaryEmails);
      buckets.putIfAbsent(key, () => <ManagedCalendarEntity>[]).add(cal);
    }

    final groups = <DeduplicatedCalendarGroup>[];
    for (final entry in buckets.entries) {
      final key = entry.key;
      final members = List<ManagedCalendarEntity>.from(entry.value)
        ..sort((a, b) => _sourcePriority(a).compareTo(_sourcePriority(b)));
      final rep = members.first;
      final isPrimaryGroup = key == '__primary__';
      final isHoliday = key == '__holiday__';
      final isBirthday = key == '__birthday__';
      final isSystemFeed =
          isHoliday || isBirthday || (!isPrimaryGroup && rep.isReadOnly);

      final displayTitle = switch (key) {
        '__primary__' => 'Lịch cá nhân',
        '__holiday__' => 'Ngày lễ Việt Nam',
        '__birthday__' => 'Sinh nhật',
        _ => rep.summary.trim().isEmpty ? 'Bộ lịch riêng' : rep.summary.trim(),
      };

      final ids = <String>{
        for (final m in members) m.id,
        if (isPrimaryGroup) 'primary',
      };

      groups.add(
        DeduplicatedCalendarGroup(
          groupKey: key,
          displayTitle: displayTitle,
          representative: rep,
          members: List<ManagedCalendarEntity>.unmodifiable(members),
          memberIds: Set<String>.unmodifiable(ids),
          isPrimaryGroup: isPrimaryGroup,
          isSystemFeed: isSystemFeed,
        ),
      );
    }

    groups.sort((a, b) {
      if (a.isPrimaryGroup != b.isPrimaryGroup) {
        return a.isPrimaryGroup ? -1 : 1;
      }
      if (a.isSystemFeed != b.isSystemFeed) {
        return a.isSystemFeed ? 1 : -1;
      }
      return a.displayTitle.compareTo(b.displayTitle);
    });

    return groups;
  }

  /// Removes duplicate events pulled from identical calendars (e.g., two Holiday feeds).
  static List<CalendarEventEntity> deduplicateEvents(
    List<CalendarEventEntity> source,
  ) {
    if (source.length <= 1) return source;
    final bySignature = <String, CalendarEventEntity>{};
    for (final ev in source) {
      final normTitle = normalizeText(ev.title);
      final startBucket = ev.isAllDay
          ? '${ev.startsAt.year}-${ev.startsAt.month}-${ev.startsAt.day}-allday'
          : '${ev.startsAt.year}-${ev.startsAt.month}-${ev.startsAt.day}-${ev.startsAt.hour}:${ev.startsAt.minute}';
      final sig = '${ev.visibility.name}|$normTitle|$startBucket';
      final existing = bySignature[sig];
      if (existing == null) {
        bySignature[sig] = ev;
      } else {
        // Prefer Google-linked or LifeOS-authored record over raw `devcal_*` clone
        final preferCurrent =
            (!existing.isLinkedWithGoogle && ev.isLinkedWithGoogle) ||
            (existing.id.startsWith('devcal_') && !ev.id.startsWith('devcal_'));
        if (preferCurrent) {
          bySignature[sig] = ev;
        }
      }
    }
    return bySignature.values.toList();
  }
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
