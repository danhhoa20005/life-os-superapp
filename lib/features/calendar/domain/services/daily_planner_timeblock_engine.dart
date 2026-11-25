import 'package:equatable/equatable.dart';

enum PlannerCalendarSpace {
  privateSpace('private', 'Riêng tư'),
  workSpace('work', 'Công việc'),
  familySpace('family', 'Gia đình');

  final String code;
  final String labelVi;
  const PlannerCalendarSpace(this.code, this.labelVi);
}

class TimeBlockSlot extends Equatable {
  final String id;
  final String title;
  final String? description;
  final DateTime startsAt;
  final DateTime endsAt;
  final bool isAllDay;
  final PlannerCalendarSpace space;
  final String ownerUserId;
  final bool sharedWithFamily;
  final String? linkedTaskId;
  final String timeZoneId;

  const TimeBlockSlot({
    required this.id,
    required this.title,
    this.description,
    required this.startsAt,
    required this.endsAt,
    this.isAllDay = false,
    this.space = PlannerCalendarSpace.privateSpace,
    required this.ownerUserId,
    this.sharedWithFamily = false,
    this.linkedTaskId,
    this.timeZoneId = 'Asia/Ho_Chi_Minh',
  });

  bool overlapsWith(TimeBlockSlot other) {
    if (isAllDay || other.isAllDay) return false;
    return startsAt.isBefore(other.endsAt) && other.startsAt.isBefore(endsAt);
  }

  /// Redacts private event title & description before projecting into a shared Family busy-view!
  TimeBlockSlot redactedForViewer(String viewerUserId) {
    if (viewerUserId == ownerUserId ||
        space == PlannerCalendarSpace.familySpace ||
        sharedWithFamily) {
      return this;
    }
    return TimeBlockSlot(
      id: id,
      title: 'Khung giờ bận',
      description: null,
      startsAt: startsAt,
      endsAt: endsAt,
      isAllDay: isAllDay,
      space: space,
      ownerUserId: ownerUserId,
      sharedWithFamily: false,
      linkedTaskId: null,
      timeZoneId: timeZoneId,
    );
  }

  @override
  List<Object?> get props => [
    id,
    title,
    description,
    startsAt,
    endsAt,
    isAllDay,
    space,
    ownerUserId,
    sharedWithFamily,
    linkedTaskId,
    timeZoneId,
  ];
}

class ScheduleConflictPair extends Equatable {
  final String firstEventId;
  final String secondEventId;
  final int overlapMinutes;

  const ScheduleConflictPair({
    required this.firstEventId,
    required this.secondEventId,
    required this.overlapMinutes,
  });

  @override
  List<Object?> get props => [firstEventId, secondEventId, overlapMinutes];
}

class DailyPlannerViewModel extends Equatable {
  final DateTime dayStart;
  final List<TimeBlockSlot> allDayItems;
  final List<TimeBlockSlot> timedBlocks;
  final List<ScheduleConflictPair> conflicts;
  final List<({DateTime startsAt, DateTime endsAt})> freeFocusWindows;

  const DailyPlannerViewModel({
    required this.dayStart,
    required this.allDayItems,
    required this.timedBlocks,
    required this.conflicts,
    required this.freeFocusWindows,
  });

  @override
  List<Object?> get props => [
    dayStart,
    allDayItems,
    timedBlocks,
    conflicts,
    freeFocusWindows,
  ];
}

/// Daily Planner, Hourly Time-Blocking, Recurrence Exception (`EXDATE`), Conflict Detection,
/// and Strict Private-Event Redaction Engine (Section 26).
abstract final class DailyPlannerTimeblockEngine {
  static DailyPlannerViewModel buildDayPlan({
    required DateTime targetDay,
    required String viewerUserId,
    required List<TimeBlockSlot> rawBlocks,
    int workDayStartHour = 7,
    int workDayEndHour = 21,
  }) {
    final dayStart = DateTime(targetDay.year, targetDay.month, targetDay.day);
    final dayEnd = dayStart.add(const Duration(days: 1));

    final visible = rawBlocks
        .where(
          (b) => b.startsAt.isBefore(dayEnd) && b.endsAt.isAfter(dayStart),
        )
        .map((b) => b.redactedForViewer(viewerUserId))
        .toList();

    final allDay = visible.where((b) => b.isAllDay).toList();
    final timed = visible.where((b) => !b.isAllDay).toList()
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));

    final conflicts = <ScheduleConflictPair>[];
    for (var i = 0; i < timed.length; i++) {
      for (var j = i + 1; j < timed.length; j++) {
        if (timed[i].overlapsWith(timed[j])) {
          final overlapStart = timed[i].startsAt.isAfter(timed[j].startsAt)
              ? timed[i].startsAt
              : timed[j].startsAt;
          final overlapEnd = timed[i].endsAt.isBefore(timed[j].endsAt)
              ? timed[i].endsAt
              : timed[j].endsAt;
          final mins = overlapEnd.difference(overlapStart).inMinutes;
          if (mins > 0) {
            conflicts.add(
              ScheduleConflictPair(
                firstEventId: timed[i].id,
                secondEventId: timed[j].id,
                overlapMinutes: mins,
              ),
            );
          }
        }
      }
    }

    // Compute >= 30-minute free Time-Blocking windows for scheduling tasks
    final workStart = DateTime(
      dayStart.year,
      dayStart.month,
      dayStart.day,
      workDayStartHour,
    );
    final workEnd = DateTime(
      dayStart.year,
      dayStart.month,
      dayStart.day,
      workDayEndHour,
    );
    final freeWindows = <({DateTime startsAt, DateTime endsAt})>[];
    var cursor = workStart;

    for (final b in timed) {
      if (b.endsAt.isBefore(workStart) || !b.startsAt.isBefore(workEnd)) {
        continue;
      }
      if (b.startsAt.isAfter(cursor)) {
        final gapEnd = b.startsAt.isBefore(workEnd) ? b.startsAt : workEnd;
        if (gapEnd.difference(cursor).inMinutes >= 30) {
          freeWindows.add((startsAt: cursor, endsAt: gapEnd));
        }
      }
      if (b.endsAt.isAfter(cursor)) {
        cursor = b.endsAt;
      }
    }
    if (workEnd.isAfter(cursor) &&
        workEnd.difference(cursor).inMinutes >= 30) {
      freeWindows.add((startsAt: cursor, endsAt: workEnd));
    }

    return DailyPlannerViewModel(
      dayStart: dayStart,
      allDayItems: allDay,
      timedBlocks: timed,
      conflicts: conflicts,
      freeFocusWindows: freeWindows,
    );
  }

  /// Creates a linked `TimeBlockSlot` directly for an open task into the earliest available free window.
  static TimeBlockSlot? scheduleTaskIntoFreeWindow({
    required String taskId,
    required String taskTitle,
    required String ownerUserId,
    required DailyPlannerViewModel dayPlan,
    int durationMinutes = 45,
  }) {
    for (final win in dayPlan.freeFocusWindows) {
      if (win.endsAt.difference(win.startsAt).inMinutes >= durationMinutes) {
        return TimeBlockSlot(
          id: 'tb_$taskId',
          title: taskTitle,
          startsAt: win.startsAt,
          endsAt: win.startsAt.add(Duration(minutes: durationMinutes)),
          space: PlannerCalendarSpace.workSpace,
          ownerUserId: ownerUserId,
          linkedTaskId: taskId,
        );
      }
    }
    return null;
  }

  /// Expands recurring instances while honoring `excludedDayKeys` (`EXDATE`) and `overridesByDayKey`.
  static List<TimeBlockSlot> expandRecurringWithExceptions({
    required TimeBlockSlot master,
    required int intervalDays,
    required int maxOccurrences,
    Set<String> excludedDayKeys = const <String>{},
    Map<String, TimeBlockSlot> overridesByDayKey = const <String, TimeBlockSlot>{},
  }) {
    final duration = master.endsAt.difference(master.startsAt);
    final results = <TimeBlockSlot>[];
    for (var i = 0; i < maxOccurrences; i++) {
      final occStart = master.startsAt.add(Duration(days: i * intervalDays));
      final dayKey =
          '${occStart.year}-${occStart.month.toString().padLeft(2, '0')}-${occStart.day.toString().padLeft(2, '0')}';
      if (excludedDayKeys.contains(dayKey)) {
        continue;
      }
      if (overridesByDayKey.containsKey(dayKey)) {
        results.add(overridesByDayKey[dayKey]!);
        continue;
      }
      results.add(
        TimeBlockSlot(
          id: '${master.id}_$dayKey',
          title: master.title,
          description: master.description,
          startsAt: occStart,
          endsAt: occStart.add(duration),
          isAllDay: master.isAllDay,
          space: master.space,
          ownerUserId: master.ownerUserId,
          sharedWithFamily: master.sharedWithFamily,
          linkedTaskId: master.linkedTaskId,
          timeZoneId: master.timeZoneId,
        ),
      );
    }
    return results;
  }
}
