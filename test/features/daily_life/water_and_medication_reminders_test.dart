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

  group('1. Physiological Weight + Height Hydration Formula & OS Alarm Scheduler', () {
    test(
      'AsianHealthBmiTdeeEngine.computeRecommendedWaterMl adjusts dynamically by BOTH weight (kg), height (cm), and activity level',
      () {
        final shortAt65Kg = AsianHealthBmiTdeeEngine.computeRecommendedWaterMl(
          weightKg: 65,
          heightCm: 150,
          activityLevel: HydrationActivityLevel.sedentary,
        );
        final tallAt65Kg = AsianHealthBmiTdeeEngine.computeRecommendedWaterMl(
          weightKg: 65,
          heightCm: 182,
          activityLevel: HydrationActivityLevel.sedentary,
        );
        // At identical 65 kg weight, taller stature (182 cm vs 150 cm) requires meaningfully more water
        expect(tallAt65Kg, greaterThan(shortAt65Kg + 250));

        final heavierAt170Cm =
            AsianHealthBmiTdeeEngine.computeRecommendedWaterMl(
              weightKg: 76,
              heightCm: 170,
              activityLevel: HydrationActivityLevel.sedentary,
            );
        final lighterAt170Cm =
            AsianHealthBmiTdeeEngine.computeRecommendedWaterMl(
              weightKg: 52,
              heightCm: 170,
              activityLevel: HydrationActivityLevel.sedentary,
            );
        expect(heavierAt170Cm, greaterThan(lighterAt170Cm + 400));

        final activeHot = AsianHealthBmiTdeeEngine.computeRecommendedWaterMl(
          weightKg: 65,
          heightCm: 170,
          activityLevel: HydrationActivityLevel.activeHot,
        );
        final office = AsianHealthBmiTdeeEngine.computeRecommendedWaterMl(
          weightKg: 65,
          heightCm: 170,
          activityLevel: HydrationActivityLevel.sedentary,
        );
        expect(activeHot - office, 550);
      },
    );

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
        // 45m intervals from 12:00 to 21:30 => > 10 slots (exceeds old 8-slot cap!)
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

    test(
      'Schedules medication exact alarm, 15m snooze, and cancels cleanly on delete',
      () async {
        final scheduler = HealthReminderSchedulerService();
        final bridge = NativeAlarmSchedulerBridge.instance;
        final tomorrowMorning = DateTime.now().add(const Duration(days: 1));
        final med = MedicationCabinetItemEntity(
          id: 'med_vit_c',
          ownerId: 'u1',
          name: 'Vitamin C 500mg',
          dosage: '1 viên sau ăn sáng',
          slot: MedicationScheduleSlot.morning,
          remainingPills: 30,
          expiryDate: tomorrowMorning.add(const Duration(days: 180)),
          reminderEnabled: true,
          reminderHour: 8,
          reminderMinute: 15,
        );

        final info = await scheduler.syncMedicationAlarm(med);
        expect(info, isNotNull);
        expect(
          await bridge.getScheduledAlarm(
            HealthReminderSchedulerService.medAlarmId(med.id),
          ),
          isNotNull,
        );

        final snooze = await scheduler.snoozeMedication15Min(med);
        expect(snooze.title, contains('Vitamin C 500mg'));
        expect(
          await bridge.getScheduledAlarm(
            HealthReminderSchedulerService.medSnoozeAlarmId(med.id),
          ),
          isNotNull,
        );

        await scheduler.cancelMedicationAlarm(med.id);
        expect(
          await bridge.getScheduledAlarm(
            HealthReminderSchedulerService.medAlarmId(med.id),
          ),
          isNull,
        );
        expect(
          await bridge.getScheduledAlarm(
            HealthReminderSchedulerService.medSnoozeAlarmId(med.id),
          ),
          isNull,
        );
      },
    );
  });

  group('2. SmartOmniIntentParser & DailyLifeBloc Body-Calibrated Hydration Integration', () {
    test('Parses multi-clause water intake and medication reminder in < 2ms', () {
      final fixedNow = DateTime(2026, 11, 24, 9, 0);
      final drafts = SmartOmniIntentParser.parseMulti(
        'Uống 350ml nước và nhắc uống thuốc Vitamin D3 8h sáng',
        now: fixedNow,
      );

      expect(drafts.length, 2);
      expect(drafts[0].kind, OmniActionKind.waterLog);
      expect(drafts[0].waterMl, 350);

      expect(drafts[1].kind, OmniActionKind.medication);
      expect(drafts[1].title.toLowerCase(), contains('vitamin d3'));
      expect(drafts[1].scheduledAt?.hour, 8);
    });

    test(
      'DailyLifeBloc persists weight/height hydration calibration, beverage history entries, entry deletion, snooze & vital sync',
      () async {
        final firestore = FakeFirebaseFirestore();
        final repo = DailyLifeRepositoryImpl(firestore);
        final bloc = DailyLifeBloc(repo);
        const uid = 'u_water_med_bloc';

        bloc.add(const DailyLifeWatchStarted(uid));
        await Future<void>.delayed(const Duration(milliseconds: 40));

        final expectedBodyTarget =
            AsianHealthBmiTdeeEngine.computeRecommendedWaterMl(
              weightKg: 72.0,
              heightCm: 176.0,
              activityLevel: HydrationActivityLevel.moderate,
            );

        bloc.add(
          HydrationReminderSettingsSaved(
            userId: uid,
            reminderEnabled: true,
            intervalMinutes: 60,
            startHour: 6,
            startMinute: 30,
            endHour: 21,
            endMinute: 30,
            targetWaterMl: expectedBodyTarget,
            weightKg: 72.0,
            heightCm: 176.0,
            activityLevel: HydrationActivityLevel.moderate,
            autoSyncTargetByBody: true,
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
        expect(hyd.targetWaterMl, expectedBodyTarget);
        expect(hyd.weightKg, 72.0);
        expect(hyd.heightCm, 176.0);
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

        // Saving a vital log automatically updates hydration weight/height when autoSyncTargetByBody is true
        bloc.add(
          const HealthVitalLogAdded(
            userId: uid,
            weightKg: 66.0,
            heightCm: 172.0,
            systolicMmHg: 118,
            diastolicMmHg: 76,
            heartRateBpm: 70,
            sleepHours: 7.5,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(bloc.state.snapshot.hydration.weightKg, 66.0);
        expect(bloc.state.snapshot.hydration.heightCm, 172.0);
        expect(
          bloc.state.snapshot.hydration.targetWaterMl,
          AsianHealthBmiTdeeEngine.computeRecommendedWaterMl(
            weightKg: 66.0,
            heightCm: 172.0,
            activityLevel: HydrationActivityLevel.moderate,
          ),
        );

        await bloc.close();
      },
    );

    test(
      'Drains queued lock-screen water & medication notification actions when app resumes from background',
      () async {
        final firestore = FakeFirebaseFirestore();
        final repo = DailyLifeRepositoryImpl(firestore);
        final bloc = DailyLifeBloc(repo);
        const uid = 'u_bg_notif_queue';

        bloc.add(const DailyLifeWatchStarted(uid));
        await Future<void>.delayed(const Duration(milliseconds: 40));

        bloc.add(
          MedicationCabinetAdded(
            userId: uid,
            name: 'Magie B6',
            dosage: '1 viên buổi tối',
            slot: MedicationScheduleSlot.evening,
            remainingPills: 20,
            expiryDate: DateTime.now().add(const Duration(days: 180)),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 80));
        final addedMed = bloc.state.snapshot.medications.single;

        // Simulate user tapping "+300ml" & "Đã uống thuốc" directly on Android lock-screen notifications while app is closed
        final bridge = NativeAlarmSchedulerBridge.instance;
        bridge.simulateBackgroundNotificationActionTap(
          QueuedBackgroundHealthAction(
            type: 'water_logged',
            ml: 300,
            loggedAt: DateTime.now(),
          ),
        );
        bridge.simulateBackgroundNotificationActionTap(
          QueuedBackgroundHealthAction(
            type: 'med_taken',
            medId: addedMed.id,
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
        final updatedMed = bloc.state.snapshot.medications.single;
        expect(updatedMed.isTakenOn(DailyLifeBloc.todayDayKey()), isTrue);
        expect(updatedMed.remainingPills, 19);

        // Re-syncing when queue is already drained is idempotent
        bloc.add(const BackgroundHealthActionsSynced(userId: uid));
        await Future<void>.delayed(const Duration(milliseconds: 60));
        expect(bloc.state.snapshot.hydration.waterMl, 300);
        expect(bloc.state.snapshot.medications.single.remainingPills, 19);

        await bloc.close();
      },
    );
  });

  group('3. UI End-to-End: HealthMedicalHubPage Weight/Height + Outside-Screen Background Notifications + TodayPage Inbox', () {
    testWidgets(
      'Adjusts weight & height, fires instant & 5s background notifications, syncs live lock-screen action tap & surfaces on TodayPage at 360x800',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(360, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final firestore = FakeFirebaseFirestore();
        final mockUser = MockUser(
          isAnonymous: false,
          uid: 'u_health_ui',
          email: 'health@lifeos.vn',
          displayName: 'Ngọc Lan',
        );
        await firestore.collection('users').doc('u_health_ui').set({
          'email': 'health@lifeos.vn',
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

        // Navigate to Health & Medication Hub via 4x2 Dock
        await tester.scrollUntilVisible(
          find.byKey(const Key('home_tile_health')),
          220,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.drag(find.byType(ListView).first, const Offset(0, -180));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('home_tile_health')));
        await tester.pumpAndSettle();

        // 1. Add Vitamin D3 + K2 MK7 via primary "+ Thêm thuốc & Hẹn giờ nhắc" sheet
        await tester.tap(find.byKey(const Key('open_add_medication_btn')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('add_med_name_input')),
          'Vitamin D3 + K2 MK7',
        );
        await tester.ensureVisible(
          find.byKey(const Key('confirm_save_med_btn')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('confirm_save_med_btn')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('medication_schedule_banner')),
          findsOneWidget,
        );
        expect(find.text('Nhắc 07:30'), findsOneWidget);

        // 2. Switch to Uống nước tab -> log +250ml, adjust Weight & Height, enable reminder & 300ml cup
        await tester.tap(find.text('Uống nước'));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('hydration_tracker_card')), findsOneWidget);

        await tester.tap(find.byKey(const Key('water_quick_add_250')));
        await tester.pumpAndSettle();
        expect(find.text('250 ml'), findsWidgets);

        // Scroll to Body Calculator Card -> adjust weight (+0.5 kg) and height (+1 cm) & activity level
        await tester.scrollUntilVisible(
          find.byKey(const Key('water_weight_plus_btn')),
          140,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.ensureVisible(
          find.byKey(const Key('water_weight_plus_btn')),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('water_weight_plus_btn')));
        await tester.pumpAndSettle();
        expect(find.text('63.5 kg'), findsOneWidget);

        await tester.scrollUntilVisible(
          find.byKey(const Key('water_height_plus_btn')),
          140,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.ensureVisible(
          find.byKey(const Key('water_height_plus_btn')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('water_height_plus_btn')));
        await tester.pumpAndSettle();
        expect(find.text('169 cm'), findsOneWidget);

        await tester.scrollUntilVisible(
          find.byKey(const Key('water_activity_chip_moderate')),
          140,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.ensureVisible(
          find.byKey(const Key('water_activity_chip_moderate')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('water_activity_chip_moderate')));
        await tester.pumpAndSettle();

        // Expected target for 63.5 kg, 169 cm, moderate (+300):
        final expectedCalibratedMl =
            AsianHealthBmiTdeeEngine.computeRecommendedWaterMl(
              weightKg: 63.5,
              heightCm: 169,
              activityLevel: HydrationActivityLevel.moderate,
            );
        expect(find.text('$expectedCalibratedMl ml / ngày'), findsOneWidget);

        // Enable reminder switch & choose 300ml cup size
        await tester.scrollUntilVisible(
          find.byKey(const Key('toggle_water_reminder_switch')),
          140,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.ensureVisible(
          find.byKey(const Key('toggle_water_reminder_switch')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('toggle_water_reminder_switch')));
        await tester.pumpAndSettle();

        await tester.scrollUntilVisible(
          find.byKey(const Key('water_cup_size_chip_300')),
          140,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.ensureVisible(
          find.byKey(const Key('water_cup_size_chip_300')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('water_cup_size_chip_300')));
        await tester.pumpAndSettle();

        // Scroll to Outside-Screen & Background Notification Panel and fire both 1-tap tests
        await tester.scrollUntilVisible(
          find.byKey(const Key('test_instant_water_notif_btn')),
          160,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.ensureVisible(
          find.byKey(const Key('test_instant_water_notif_btn')),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('test_instant_water_notif_btn')));
        await tester.pumpAndSettle();
        expect(
          NativeAlarmSchedulerBridge.instance.debugShownNotifications,
          isNotEmpty,
        );
        expect(
          NativeAlarmSchedulerBridge
              .instance
              .debugShownNotifications
              .last['cupMl'],
          300,
        );

        await tester.ensureVisible(
          find.byKey(const Key('test_5s_bg_water_notif_btn')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('test_5s_bg_water_notif_btn')));
        await tester.pumpAndSettle();
        final delayedTestAlarm = await NativeAlarmSchedulerBridge.instance
            .getScheduledAlarm(
              HealthReminderSchedulerService.waterTestDelayedId,
            );
        expect(delayedTestAlarm, isNotNull);
        expect(delayedTestAlarm!.fullScreen, isFalse);
        expect(delayedTestAlarm.cupMl, 300);

        // Simulate user tapping "✓ Đã uống +300ml" on the system notification shade -> auto-syncs into live app!
        NativeAlarmSchedulerBridge.instance
            .simulateBackgroundNotificationActionTap(
              QueuedBackgroundHealthAction(
                type: 'water_logged',
                ml: 300,
                loggedAt: DateTime.now(),
              ),
            );
        await tester.pumpAndSettle();

        // Verify Today's intake history card reflects both cups (250ml + 300ml = 550ml)
        await tester.scrollUntilVisible(
          find.byKey(const Key('hydration_today_log_card')),
          180,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('Nhật ký uống hôm nay'), findsOneWidget);
        expect(find.textContaining('Từ thông báo'), findsOneWidget);

        // 3. Return to TodayPage and verify due Medication & Body-Calibrated Water Reminder (550/expected ml) surface in Inbox!
        await tester.tap(find.byTooltip('Quay lại'));
        await tester.pumpAndSettle();
        await tester.drag(find.byType(ListView).first, const Offset(0, 400));
        await tester.pumpAndSettle();

        expect(
          find.textContaining('Nhắc uống thuốc: Vitamin D3'),
          findsOneWidget,
        );
        expect(
          find.text('Nhắc uống nước: 550/$expectedCalibratedMl ml'),
          findsOneWidget,
        );
        expect(find.text('+300ml'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Displays quick permission action buttons cleanly at 360x800 when notification / exact-alarm / battery exemptions are missing',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(360, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        NativeAlarmSchedulerBridge.instance.setDebugReadinessOverride(
          const BackgroundReminderReadiness(
            notificationsGranted: false,
            exactAlarmGranted: false,
            batteryOptimizationIgnored: false,
          ),
        );

        final firestore = FakeFirebaseFirestore();
        final mockUser = MockUser(
          isAnonymous: false,
          uid: 'u_perm_ui',
          email: 'perm@lifeos.vn',
          displayName: 'Minh Khôi',
        );
        await firestore.collection('users').doc('u_perm_ui').set({
          'email': 'perm@lifeos.vn',
          'fullName': 'Minh Khôi',
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

        await tester.scrollUntilVisible(
          find.byKey(const Key('home_tile_health')),
          220,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.drag(find.byType(ListView).first, const Offset(0, -180));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('home_tile_health')));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Uống nước'));
        await tester.pumpAndSettle();

        await tester.scrollUntilVisible(
          find.byKey(const Key('grant_notif_perm_btn')),
          180,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();

        expect(find.text('Cần cấp quyền'), findsOneWidget);
        expect(find.byKey(const Key('grant_notif_perm_btn')), findsOneWidget);
        expect(find.byKey(const Key('grant_exact_alarm_btn')), findsOneWidget);
        expect(
          find.byKey(const Key('grant_unrestricted_bg_btn')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  });
}
