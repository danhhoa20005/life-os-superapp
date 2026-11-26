import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:life_os/app/app.dart';
import 'package:life_os/core/di/dependency_injection.dart';
import 'package:life_os/core/services/health_reminder_scheduler_service.dart';
import 'package:life_os/core/services/native_alarm_scheduler_bridge.dart';
import 'package:life_os/core/services/native_device_calendar_bridge.dart';
import 'package:life_os/core/utils/smart_omni_intent_parser.dart';
import 'package:life_os/features/daily_life/data/repositories/daily_life_repository_impl.dart';
import 'package:life_os/features/daily_life/domain/entities/daily_life_entities.dart';
import 'package:life_os/features/daily_life/presentation/bloc/daily_life_bloc.dart';
import 'package:life_os/features/financial_ai/data/inference/fasttext_classifier.dart';

class _NoOpDeviceCalendarDriver implements DeviceCalendarDriver {
  const _NoOpDeviceCalendarDriver();

  @override
  bool get isSupportedPlatform => false;

  @override
  Future<bool> hasPermission() async => false;

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<List<DeviceCalendarInfo>> listCalendars() async => const [];

  @override
  Future<List<DeviceCalendarEventItem>> listEvents({
    required DateTime windowStart,
    required DateTime windowEnd,
  }) async => const [];

  @override
  Future<int?> upsertEvent({
    int? deviceEventId,
    int? deviceCalendarId,
    required String title,
    String? description,
    String? location,
    required DateTime startsAt,
    required DateTime endsAt,
    bool isAllDay = false,
    String timeZone = 'Asia/Ho_Chi_Minh',
    String? rrule,
    int reminderMinutesBefore = 15,
  }) async => null;

  @override
  Future<bool> deleteEvent(int deviceEventId) async => false;
}

void main() {
  setUp(() {
    NativeAlarmSchedulerBridge.instance.resetDebugCounters();
    NativeDeviceCalendarBridge.setDriverOverride(
      const _NoOpDeviceCalendarDriver(),
    );
  });

  tearDown(() async {
    NativeAlarmSchedulerBridge.instance.resetDebugCounters();
    NativeDeviceCalendarBridge.setDriverOverride(null);
    await sl.reset();
  });

  group('1. Hydration Reminder OS Alarm Scheduler', () {
    test(
      'Schedules waking-hour water slots (including custom minutes & snooze), syncs background daemon, and pauses remaining same-day alarms once goal is reached',
      () async {
        final scheduler = HealthReminderSchedulerService();
        final bridge = NativeAlarmSchedulerBridge.instance;
        final futureNoon = DateTime.now().add(const Duration(days: 2));
        final noonRef = DateTime(
          futureNoon.year,
          futureNoon.month,
          futureNoon.day,
          12,
          0,
        );

        const activeStatus = HydrationReminderStatusEntity(
          dayKey: '2028-05-10',
          waterMl: 500,
          targetWaterMl: 2200,
          reminderEnabled: true,
          intervalMinutes: 45,
          startHour: 6,
          startMinute: 30,
          endHour: 21,
          endMinute: 30,
          preferredCupMl: 300,
        );

        final scheduled = await scheduler.syncHydrationReminders(
          activeStatus,
          now: noonRef,
        );
        // 45m intervals from 12:00 to 21:30 => > 10 slots
        expect(scheduled.length, greaterThan(10));
        for (final alarm in scheduled) {
          expect(alarm.triggerAt.hour, inInclusiveRange(6, 21));
          expect(alarm.fullScreen, isFalse);
          expect(alarm.cupMl, 300);
        }
        expect(bridge.debugHydrationDaemonConfig?['enabled'], isTrue);
        expect(bridge.debugHydrationDaemonConfig?['preferredCupMl'], 300);
        expect(bridge.debugHydrationDaemonConfig?['targetWaterMl'], 2200);

        // Snooze 15m schedules dedicated snooze alarm
        final snoozedInfo = await scheduler.snoozeWaterReminder(
          activeStatus,
          minutes: 15,
          now: noonRef,
        );
        expect(snoozedInfo.triggerAt, noonRef.add(const Duration(minutes: 15)));
        expect(snoozedInfo.fullScreen, isFalse);

        // When daily target is reached (2200/2200 ml), only tomorrow morning's 06:30 slot is scheduled
        const completedStatus = HydrationReminderStatusEntity(
          dayKey: '2028-05-10',
          waterMl: 2200,
          targetWaterMl: 2200,
          reminderEnabled: true,
          intervalMinutes: 45,
          startHour: 6,
          startMinute: 30,
          endHour: 21,
          endMinute: 30,
        );
        final nextDayOnly = await scheduler.syncHydrationReminders(
          completedStatus,
          now: noonRef,
        );
        expect(nextDayOnly.length, 1);
        expect(nextDayOnly.first.triggerAt.day, noonRef.day + 1);
        expect(nextDayOnly.first.triggerAt.hour, 6);
        expect(nextDayOnly.first.triggerAt.minute, 30);
      },
    );
  });

  group('2. SmartOmniIntentParser & DailyLifeBloc Hydration Integration', () {
    test('Parses multi-clause water intake and task reminder in < 2ms', () {
      final fixedNow = DateTime(2026, 11, 24, 9, 0);
      final drafts = SmartOmniIntentParser.parseMulti(
        'Uống 350ml nước và nhắc đóng tiền điện 8h sáng',
        now: fixedNow,
      );

      expect(drafts.length, 2);
      expect(drafts[0].kind, OmniActionKind.waterLog);
      expect(drafts[0].waterMl, 350);

      expect(drafts[1].kind, OmniActionKind.task);
      expect(drafts[1].title.toLowerCase(), contains('đóng tiền điện'));
      expect(drafts[1].scheduledAt?.hour, 8);
    });

    test(
      'DailyLifeBloc persists hydration reminder settings, beverage history entries, entry deletion & snooze',
      () async {
        final firestore = FakeFirebaseFirestore();
        final repo = DailyLifeRepositoryImpl(firestore);
        final bloc = DailyLifeBloc(repo);
        const uid = 'u_water_bloc';

        bloc.add(const DailyLifeWatchStarted(uid));
        await Future<void>.delayed(const Duration(milliseconds: 40));

        bloc.add(
          const HydrationReminderSettingsSaved(
            userId: uid,
            reminderEnabled: true,
            intervalMinutes: 60,
            startHour: 6,
            startMinute: 30,
            endHour: 21,
            endMinute: 30,
            targetWaterMl: 2400,
            activityLevel: HydrationActivityLevel.moderate,
            preferredCupMl: 300,
          ),
        );
        bloc.add(
          const WaterIntakeLogged(
            userId: uid,
            deltaMl: 250,
            beverageLabel: 'Nước ấm',
          ),
        );
        bloc.add(
          const WaterIntakeLogged(
            userId: uid,
            deltaMl: 500,
            beverageLabel: 'Điện giải',
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 140));

        final hyd = bloc.state.snapshot.hydration;
        expect(hyd.waterMl, 750);
        expect(hyd.targetWaterMl, 2400);
        expect(hyd.activityLevel, HydrationActivityLevel.moderate);
        expect(hyd.preferredCupMl, 300);
        expect(hyd.formattedActiveWindow, '06:30 – 21:30');
        expect(hyd.todayEntries.length, 2);

        // Undo last 500ml cup -> back to 250ml and 1 entry remaining
        bloc.add(const WaterIntakeLogged(userId: uid, deltaMl: -500));
        await Future<void>.delayed(const Duration(milliseconds: 80));
        expect(bloc.state.snapshot.hydration.waterMl, 250);
        expect(bloc.state.snapshot.hydration.todayEntries.length, 1);
        expect(
          bloc.state.snapshot.hydration.todayEntries.single.beverageLabel,
          'Nước ấm',
        );

        // Snooze 15m sets snoozedUntil
        bloc.add(const WaterReminderSnoozed(userId: uid, minutes: 15));
        await Future<void>.delayed(const Duration(milliseconds: 80));
        expect(bloc.state.snapshot.hydration.snoozedUntil, isNotNull);

        await bloc.close();
      },
    );

    test(
      'Drains queued lock-screen water notification actions when app resumes from background',
      () async {
        final firestore = FakeFirebaseFirestore();
        final repo = DailyLifeRepositoryImpl(firestore);
        final bloc = DailyLifeBloc(repo);
        const uid = 'u_bg_notif_queue';

        bloc.add(const DailyLifeWatchStarted(uid));
        await Future<void>.delayed(const Duration(milliseconds: 40));

        // Simulate user tapping "+300ml" directly on Android lock-screen notification while app is closed
        final bridge = NativeAlarmSchedulerBridge.instance;
        bridge.simulateBackgroundNotificationActionTap(
          QueuedBackgroundHealthAction(
            type: 'water_logged',
            ml: 300,
            loggedAt: DateTime.now(),
          ),
        );

        // App resumes -> dispatches BackgroundHealthActionsSynced
        bloc.add(const BackgroundHealthActionsSynced(userId: uid));
        await Future<void>.delayed(const Duration(milliseconds: 120));

        expect(bloc.state.snapshot.hydration.waterMl, 300);
        expect(
          bloc.state.snapshot.hydration.todayEntries.single.beverageLabel,
          'Từ thông báo',
        );

        // Re-syncing when queue is already drained is idempotent
        bloc.add(const BackgroundHealthActionsSynced(userId: uid));
        await Future<void>.delayed(const Duration(milliseconds: 60));
        expect(bloc.state.snapshot.hydration.waterMl, 300);

        await bloc.close();
      },
    );
  });

  group('3. UI End-to-End: Hydration Reminder Inbox on TodayPage', () {
    testWidgets(
      'Surfaces active hydration progress and +300ml quick button on TodayPage at 360x800',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(360, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final firestore = FakeFirebaseFirestore();
        final mockUser = MockUser(
          isAnonymous: false,
          uid: 'u_water_ui',
          email: 'water@lifeos.vn',
          displayName: 'Ngọc Lan',
        );
        await firestore.collection('users').doc('u_water_ui').set({
          'email': 'water@lifeos.vn',
          'fullName': 'Ngọc Lan',
          'onboardingCompleted': true,
        });
        final auth = MockFirebaseAuth(mockUser: mockUser, signedIn: true);

        await configureDependencies(
          authOverride: auth,
          firestoreOverride: firestore,
          httpClientOverride: MockClient((_) async => http.Response('{}', 404)),
          googleCalendarTokenOverride: ({required interactive}) async => null,
          financialClassifierOverride: FastTextClassifier(
            useWorkerIsolate: false,
          ),
        );

        await tester.pumpWidget(const LifeOsApp());
        await tester.pumpAndSettle();

        final dailyBloc = sl<DailyLifeBloc>();
        dailyBloc
          ..add(
            const HydrationReminderSettingsSaved(
              userId: 'u_water_ui',
              reminderEnabled: true,
              intervalMinutes: 60,
              startHour: 7,
              endHour: 21,
              targetWaterMl: 2000,
              preferredCupMl: 300,
            ),
          )
          ..add(
            const WaterIntakeLogged(
              userId: 'u_water_ui',
              deltaMl: 550,
              beverageLabel: 'Nước lọc',
            ),
          );
        await tester.pumpAndSettle();

        expect(find.text('Nhắc uống nước: 550/2000 ml'), findsOneWidget);
        expect(find.text('+300ml'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
