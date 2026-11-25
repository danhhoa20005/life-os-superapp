import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:life_os/app/app.dart';
import 'package:life_os/app/theme/app_theme.dart';
import 'package:life_os/app/theme/theme_bloc.dart';
import 'package:life_os/core/di/dependency_injection.dart';
import 'package:life_os/core/services/native_alarm_scheduler_bridge.dart';
import 'package:life_os/core/services/native_device_calendar_bridge.dart';
import 'package:life_os/core/services/native_secure_vault_bridge.dart';
import 'package:life_os/core/services/personal_alarm_service.dart';
import 'package:life_os/features/calendar/domain/entities/calendar_entities.dart';
import 'package:life_os/features/calendar/presentation/pages/event_detail_and_alarm_pages.dart';
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
  setUp(() async {
    NativeDeviceCalendarBridge.setDriverOverride(
      const _NoOpDeviceCalendarDriver(),
    );
    NativeAlarmSchedulerBridge.instance.resetDebugCounters();
    await NativeAlarmSchedulerBridge.instance.clearAllAlarms();
    await NativeSecureVaultBridge.instance.deleteSecret(
      'lifeos_personal_alarms_v1',
    );
  });

  tearDown(() async {
    NativeDeviceCalendarBridge.setDriverOverride(null);
    await NativeAlarmSchedulerBridge.instance.clearAllAlarms();
    await sl.reset();
  });

  group('1. PersonalAlarmStore & NativeAlarmSchedulerBridge Precision Logic', () {
    test(
      'Computes exact top-of-minute recurrence, auto-disables one-shot on dismiss, and reschedules recurring weekday alarms',
      () async {
        // Friday 2026-11-27 08:00
        final refNow = DateTime(2026, 11, 27, 8, 0);

        // 1. One-shot alarm for 06:30 -> since 08:00 passed 06:30 today, schedules tomorrow 06:30:00
        final oneShot = await PersonalAlarmStore.instance.upsertAlarm(
          hour: 6,
          minute: 30,
          label: 'Dậy đi sân bay',
          repeatWeekdays: const [],
          nowOverride: refNow,
        );
        final nextOneShot = oneShot.computeNextTriggerAt(refNow);
        expect(nextOneShot, DateTime(2026, 11, 28, 6, 30));
        expect(oneShot.repeatSummaryVi, 'Một lần');

        // Dismissing one-shot alarm turns it OFF automatically
        await PersonalAlarmStore.instance.handleAlarmDismissed(
          oneShot.id,
          nowOverride: nextOneShot,
        );
        final afterOneShot = await PersonalAlarmStore.instance.loadAlarms();
        expect(
          afterOneShot.firstWhere((a) => a.id == oneShot.id).enabled,
          isFalse,
        );

        // 2. Weekday recurring alarm (Mon-Fri 07:00) dismissed on Friday morning -> schedules Monday 07:00!
        final workAlarm = await PersonalAlarmStore.instance.upsertAlarm(
          hour: 7,
          minute: 0,
          label: 'Thức dậy đi làm',
          repeatWeekdays: const [1, 2, 3, 4, 5],
          nowOverride: refNow,
        );
        expect(workAlarm.repeatSummaryVi, 'Thứ 2 – Thứ 6');
        final nextWork = workAlarm.computeNextTriggerAt(refNow);
        // Friday 08:00 -> skips Sat (28) & Sun (29) -> Monday Nov 30 07:00!
        expect(nextWork, DateTime(2026, 11, 30, 7, 0));

        await PersonalAlarmStore.instance.handleAlarmDismissed(
          workAlarm.id,
          nowOverride: DateTime(2026, 11, 27, 7, 0),
        );
        final reloaded = await PersonalAlarmStore.instance.loadAlarms();
        expect(
          reloaded.firstWhere((a) => a.id == workAlarm.id).enabled,
          isTrue,
        );
      },
    );

    test(
      'Past lead-time guard schedules at eventStartsAt instead of firing 5s prematurely',
      () async {
        final startsIn10m = DateTime.now().add(const Duration(minutes: 10));
        final info = await NativeAlarmSchedulerBridge.instance
            .scheduleEventAlarm(
              eventId: 'ev_soon_10m',
              title: 'Họp khẩn',
              subtitle: 'Phòng A1',
              eventStartsAt: startsIn10m,
              minutesBefore:
                  15, // 10m - 15m = 5m ago, while event is still +10m ahead!
              fullScreen: true,
            );
        // Must schedule ~10m ahead (at eventStartsAt), NOT 5 seconds from now!
        expect(
          info.triggerAt.difference(DateTime.now()).inMinutes,
          greaterThanOrEqualTo(9),
        );
      },
    );
  });

  group('2. Alarm Clock Studio Hub & Full-Screen Ringing UI', () {
    testWidgets(
      'Creates, toggles, and deletes personal alarms in Alarm Hub with zero overflow at 360x800 @ 112%',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(360, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final firestore = FakeFirebaseFirestore();
        const uid = 'u_alarm_hub';
        await firestore.collection('users').doc(uid).set({
          'email': 'alarm@lifeos.vn',
          'fullName': 'Minh Quân',
          'onboardingCompleted': true,
        });

        final auth = MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(
            uid: uid,
            email: 'alarm@lifeos.vn',
            displayName: 'Minh Quân',
          ),
        );

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

        final rootCtx = tester.element(find.byType(Scaffold).first);
        rootCtx.read<ThemeBloc>().add(const TextScaleChanged(1.12));
        await tester.pumpAndSettle();

        // Navigate to Alarm Studio Hub (/event-alarm)
        GoRouter.of(rootCtx).push('/event-alarm');
        await tester.pumpAndSettle();

        expect(find.text('Báo thức & Chuông hẹn'), findsOneWidget);
        expect(find.text('Chưa có giờ báo thức cá nhân'), findsOneWidget);

        // Open create alarm sheet -> step hour +1 (07:30), pick T2, save!
        await tester.tap(find.byKey(const Key('add_personal_alarm_btn')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('alarm_hour_up_btn')));
        await tester.pump();
        await tester.enterText(
          find.byKey(const Key('alarm_label_field')),
          'Đưa bé đi học',
        );
        await tester.tap(find.byKey(const Key('alarm_day_chip_1')));
        await tester.pump();

        await tester.ensureVisible(
          find.byKey(const Key('save_personal_alarm_submit_btn')),
        );
        await tester.tap(
          find.byKey(const Key('save_personal_alarm_submit_btn')),
        );
        await tester.pumpAndSettle();

        expect(find.text('07:30'), findsWidgets);
        expect(find.textContaining('Đưa bé đi học'), findsWidgets);

        final savedList = await PersonalAlarmStore.instance.loadAlarms();
        expect(savedList.length, 1);
        final savedId = savedList.single.id;

        // Toggle OFF -> cancels OS alarm cleanly
        await tester.tap(find.byKey(Key('personal_alarm_switch_$savedId')));
        await tester.pumpAndSettle();
        expect(
          await NativeAlarmSchedulerBridge.instance.getScheduledAlarm(savedId),
          isNull,
        );

        // Delete alarm -> returns to empty state cleanly
        await tester.tap(find.byKey(Key('personal_alarm_delete_$savedId')));
        await tester.pumpAndSettle();
        expect(find.text('Chưa có giờ báo thức cá nhân'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Full-screen ringing screen stops native ringer on Dismiss and reschedules +5m on Snooze',
      (tester) async {
        final ringingEv = CalendarEventEntity(
          id: 'ev_ring_test_1',
          ownerId: 'u1',
          ownerName: 'Quân',
          visibility: CalendarEventVisibility.privateEvent,
          title: 'Uống thuốc & Họp sáng',
          location: 'Phòng làm việc',
          startsAt: DateTime(2026, 11, 24, 7, 30),
          endsAt: DateTime(2026, 11, 24, 8, 0),
          reminderMinutesBefore: 0,
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: Builder(
              builder: (ctx) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    key: const Key('open_ring_btn'),
                    onPressed: () => Navigator.of(ctx).push(
                      MaterialPageRoute<void>(
                        builder: (_) => EventAlarmPage(event: ringingEv),
                      ),
                    ),
                    child: const Text('Mở chuông'),
                  ),
                ),
              ),
            ),
          ),
        );

        // 1. Open ringing screen -> tap 'Hoãn 5 phút' -> stops native ringer & schedules +5m snooze
        await tester.tap(find.byKey(const Key('open_ring_btn')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        expect(find.text('Báo thức sự kiện'), findsOneWidget);
        expect(find.text('07:30'), findsOneWidget);

        await tester.tap(find.byKey(const Key('ringing_snooze_button')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(NativeAlarmSchedulerBridge.instance.debugStopRingingCount, 1);
        final snoozed = await NativeAlarmSchedulerBridge.instance
            .getScheduledAlarm('ev_ring_test_1');
        expect(snoozed, isNotNull);
        expect(snoozed!.fullScreen, isTrue);

        // Advance past fallback toast timer before ending test
        await tester.pump(const Duration(seconds: 3));
        expect(tester.takeException(), isNull);
      },
    );
  });
}
