import 'package:intl/intl.dart';

import '../../features/daily_life/domain/entities/daily_life_entities.dart';
import 'native_alarm_scheduler_bridge.dart';

/// Schedules and cancels real OS-level alarms & outside-the-screen background notifications
/// (`NativeAlarmSchedulerBridge` / Android `AlarmManager` + `BroadcastReceiver` + `BOOT_COMPLETED`).
class HealthReminderSchedulerService {
  static final DateFormat _dayKeyFmt = DateFormat('yyyy-MM-dd');
  static const int _maxWaterAlarmSlots = 24;
  static const String waterSnoozeEventId = 'water_snooze_15m';
  static const String waterTestImmediateId = 'water_test_now';
  static const String waterTestDelayedId = 'water_test_5s';

  final NativeAlarmSchedulerBridge _alarmBridge;

  HealthReminderSchedulerService({NativeAlarmSchedulerBridge? alarmBridge})
    : _alarmBridge = alarmBridge ?? NativeAlarmSchedulerBridge.instance;

  static String waterAlarmId(int slotIndex) => 'water_rem_$slotIndex';

  Future<List<ScheduledEventAlarmInfo>> syncHydrationReminders(
    HydrationReminderStatusEntity status, {
    DateTime? now,
  }) async {
    for (var i = 0; i < _maxWaterAlarmSlots; i++) {
      await _alarmBridge.cancelEventAlarm(waterAlarmId(i));
    }
    await _alarmBridge.cancelEventAlarm(waterSnoozeEventId);

    final refNow = now ?? DateTime.now();
    final dayKey = status.dayKey.isEmpty
        ? _dayKeyFmt.format(refNow)
        : status.dayKey;

    if (!status.reminderEnabled) {
      await _alarmBridge.syncHydrationDaemon(
        enabled: false,
        intervalMinutes: status.intervalMinutes,
        startHour: status.startHour,
        startMinute: status.startMinute,
        endHour: status.endHour,
        endMinute: status.endMinute,
        targetWaterMl: status.targetWaterMl,
        waterMl: status.waterMl,
        preferredCupMl: status.preferredCupMl,
        dayKey: dayKey,
      );
      return const <ScheduledEventAlarmInfo>[];
    }

    final slots = status.upcomingScheduleAt(
      refNow,
      maxSlots: _maxWaterAlarmSlots,
    );
    final cupPerSlot = status.suggestedMlPerSlot(refNow);
    final scheduled = <ScheduledEventAlarmInfo>[];

    for (var i = 0; i < slots.length; i++) {
      final subtitle = status.isGoalReached
          ? 'Khởi đầu ngày mới khỏe khoắn với 1 cốc nước ấm ~${status.preferredCupMl} ml nhé!'
          : 'Uống thêm ~$cupPerSlot ml · Còn thiếu ${status.remainingMl} ml để đạt chuẩn ${status.targetWaterMl} ml.';
      final info = await _alarmBridge.scheduleEventAlarm(
        eventId: waterAlarmId(i),
        title:
            'Đến giờ uống nước (${status.waterMl}/${status.targetWaterMl} ml)',
        subtitle: subtitle,
        eventStartsAt: slots[i],
        minutesBefore: 0,
        fullScreen: false,
        cupMl: status.preferredCupMl,
      );
      scheduled.add(info);
    }

    // Sync autonomous background daemon AFTER scheduling today's explicit slots
    await _alarmBridge.syncHydrationDaemon(
      enabled: true,
      intervalMinutes: status.intervalMinutes,
      startHour: status.startHour,
      startMinute: status.startMinute,
      endHour: status.endHour,
      endMinute: status.endMinute,
      targetWaterMl: status.targetWaterMl,
      waterMl: status.waterMl,
      preferredCupMl: status.preferredCupMl,
      dayKey: dayKey,
    );

    return scheduled;
  }

  Future<ScheduledEventAlarmInfo> snoozeWaterReminder(
    HydrationReminderStatusEntity status, {
    int minutes = 15,
    DateTime? now,
  }) async {
    final safeMins = minutes.clamp(5, 120);
    final triggerAt = (now ?? DateTime.now()).add(Duration(minutes: safeMins));
    return _alarmBridge.scheduleEventAlarm(
      eventId: waterSnoozeEventId,
      title:
          'Nhắc lại uống nước (${status.waterMl}/${status.targetWaterMl} ml)',
      subtitle:
          'Đã dời $safeMins phút · Uống 1 cốc ~${status.preferredCupMl} ml để đủ nước nhé!',
      eventStartsAt: triggerAt,
      minutesBefore: 0,
      fullScreen: false,
      cupMl: status.preferredCupMl,
    );
  }

  /// Fires an outside-the-app Android notification immediately or after a short background delay
  /// so the user can lock the screen and verify real background heads-up notifications & action buttons.
  Future<bool> sendTestWaterNotification(
    HydrationReminderStatusEntity status, {
    int delaySeconds = 0,
  }) async {
    final cup = status.preferredCupMl;
    if (delaySeconds <= 0) {
      return _alarmBridge.showImmediateReminderNotification(
        eventId: waterTestImmediateId,
        title:
            'Đến giờ uống nước (${status.waterMl}/${status.targetWaterMl} ml)',
        subtitle:
            'Bấm "✓ Đã uống +${cup}ml" ngay trên thông báo này mà không cần mở ứng dụng!',
        cupMl: cup,
      );
    }
    await _alarmBridge.scheduleEventAlarm(
      eventId: waterTestDelayedId,
      title: 'Đến giờ uống nước (${status.waterMl}/${status.targetWaterMl} ml)',
      subtitle:
          'Thông báo chạy ngầm sau ${delaySeconds}s · Bấm "✓ Đã uống +${cup}ml" ngay trên màn hình khóa!',
      eventStartsAt: DateTime.now().add(Duration(seconds: delaySeconds)),
      minutesBefore: 0,
      fullScreen: false,
      cupMl: cup,
    );
    return true;
  }
}
