import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:life_os/app/app.dart';
import 'package:life_os/app/theme/theme_bloc.dart';
import 'package:life_os/core/di/dependency_injection.dart';
import 'package:life_os/core/services/native_device_calendar_bridge.dart';
import 'package:life_os/features/calendar/domain/entities/calendar_entities.dart';
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
    NativeDeviceCalendarBridge.setDriverOverride(
      const _NoOpDeviceCalendarDriver(),
    );
  });

  tearDown(() async {
    NativeDeviceCalendarBridge.setDriverOverride(null);
    await sl.reset();
  });

  group('1. CalendarListDeduplicator Domain Logic', () {
    test(
      'Collapses identical primary, email, custom, and holiday calendars + deduplicates holiday events',
      () {
        const rawCalendars = <ManagedCalendarEntity>[
          ManagedCalendarEntity(
            id: 'primary',
            ownerId: 'u1',
            summary: 'Lịch Cá nhân Chính',
            isPrimary: true,
          ),
          ManagedCalendarEntity(
            id: 'devcal_1',
            ownerId: 'u1',
            summary: 'hoa@gmail.com',
            source: CalendarProviderSource.deviceCalendar,
            deviceCalendarId: 1,
          ),
          ManagedCalendarEntity(
            id: 'devcal_2',
            ownerId: 'u1',
            summary: 'My calendar',
            source: CalendarProviderSource.deviceCalendar,
            deviceCalendarId: 2,
          ),
          ManagedCalendarEntity(
            id: 'devcal_3',
            ownerId: 'u1',
            summary: 'Ngày lễ ở Việt Nam',
            isReadOnly: true,
            source: CalendarProviderSource.deviceCalendar,
            deviceCalendarId: 3,
          ),
          ManagedCalendarEntity(
            id: 'vi_holiday_gcal',
            ownerId: 'u1',
            summary: 'Holidays in Vietnam',
            isReadOnly: true,
            source: CalendarProviderSource.googleCalendar,
            googleCalendarId:
                'vi.vietnamese#holiday@group.v.calendar.google.com',
          ),
          ManagedCalendarEntity(
            id: 'devcal_5',
            ownerId: 'u1',
            summary: 'Lịch Dự án Công ty',
            source: CalendarProviderSource.deviceCalendar,
            deviceCalendarId: 5,
          ),
          ManagedCalendarEntity(
            id: 'gcal_proj',
            ownerId: 'u1',
            summary: 'Lịch dự án công ty',
            source: CalendarProviderSource.googleCalendar,
            googleCalendarId: 'proj@group.calendar.google.com',
          ),
        ];

        final groups = CalendarListDeduplicator.group(rawCalendars);
        expect(groups.length, 3);
        expect(groups[0].displayTitle, 'Lịch cá nhân');
        expect(groups[0].isPrimaryGroup, isTrue);
        expect(
          groups[0].memberIds,
          containsAll(<String>['primary', 'devcal_1', 'devcal_2']),
        );

        expect(groups[1].displayTitle, 'Lịch dự án công ty');
        expect(groups[1].isSystemFeed, isFalse);
        expect(
          groups[1].memberIds,
          containsAll(<String>['devcal_5', 'gcal_proj']),
        );

        expect(groups[2].displayTitle, 'Ngày lễ Việt Nam');
        expect(groups[2].isSystemFeed, isTrue);
        expect(
          groups[2].memberIds,
          containsAll(<String>['devcal_3', 'vi_holiday_gcal']),
        );

        // Duplicate holiday events across two synced accounts collapse to 1
        final holidayDay = DateTime(2026, 9, 2);
        final rawEvents = <CalendarEventEntity>[
          CalendarEventEntity(
            id: 'devcal_ev_1',
            calendarId: 'devcal_3',
            ownerId: 'u1',
            ownerName: 'Hòa',
            visibility: CalendarEventVisibility.privateEvent,
            title: 'Quốc khánh',
            startsAt: holidayDay,
            endsAt: holidayDay.add(const Duration(days: 1)),
            isAllDay: true,
          ),
          CalendarEventEntity(
            id: 'gcal_ev_1',
            calendarId: 'vi_holiday_gcal',
            ownerId: 'u1',
            ownerName: 'Hòa',
            visibility: CalendarEventVisibility.privateEvent,
            title: 'Quốc Khánh',
            startsAt: holidayDay,
            endsAt: holidayDay.add(const Duration(days: 1)),
            isAllDay: true,
            googleEventId: 'g_92',
          ),
        ];
        final dedupedEvents = CalendarListDeduplicator.deduplicateEvents(
          rawEvents,
        );
        expect(dedupedEvents.length, 1);
        expect(dedupedEvents.single.id, 'gcal_ev_1');
      },
    );
  });

  group('2. PlanningPage UI: Hidden Inline Calendar Strip & Deduplicated Sheet', () {
    testWidgets(
      'Hides duplicate calendar chips from main screen, collapses system feeds in sheet, and hides single-item calendar dropdown in event dialog',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(360, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final firestore = FakeFirebaseFirestore();
        const uid = 'u_clean_cal';
        await firestore.collection('users').doc(uid).set({
          'email': 'hoa@lifeos.vn',
          'fullName': 'Danh Hòa',
          'onboardingCompleted': true,
        });

        // Seed duplicate-looking calendars in Firestore (as if synced earlier)
        final calCol = firestore
            .collection('users')
            .doc(uid)
            .collection('calendars');
        await calCol.doc('primary').set({
          'id': 'primary',
          'ownerId': uid,
          'summary': 'Lịch Cá nhân Chính',
          'colorHex': '#0B7A2A',
          'isPrimary': true,
          'isSelected': true,
          'isReadOnly': false,
          'source': 'lifeOsPrivate',
        });
        await calCol.doc('devcal_2').set({
          'id': 'devcal_2',
          'ownerId': uid,
          'summary': 'My calendar',
          'colorHex': '#0B7A2A',
          'isPrimary': false,
          'isSelected': true,
          'isReadOnly': false,
          'source': 'deviceCalendar',
        });
        await calCol.doc('devcal_3').set({
          'id': 'devcal_3',
          'ownerId': uid,
          'summary': 'Ngày lễ ở Việt Nam',
          'colorHex': '#1971C2',
          'isPrimary': false,
          'isSelected': true,
          'isReadOnly': true,
          'source': 'deviceCalendar',
        });
        await calCol.doc('gcal_holiday').set({
          'id': 'gcal_holiday',
          'ownerId': uid,
          'summary': 'Holidays in Vietnam',
          'colorHex': '#1971C2',
          'isPrimary': false,
          'isSelected': true,
          'isReadOnly': true,
          'source': 'googleCalendar',
          'googleCalendarId':
              'vi.vietnamese#holiday@group.v.calendar.google.com',
        });

        final auth = MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(
            uid: uid,
            email: 'hoa@lifeos.vn',
            displayName: 'Danh Hòa',
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

        GoRouter.of(rootCtx).go('/planning');
        await tester.pumpAndSettle();

        // 1. Main Lịch trình screen hides the noisy inline calendar list!
        expect(find.text('Lịch Cá nhân Chính'), findsNothing);
        expect(find.text('My calendar'), findsNothing);
        expect(find.text('Ngày lễ ở Việt Nam'), findsNothing);
        expect(find.text('Holidays in Vietnam'), findsNothing);
        expect(
          find.byKey(const Key('open_calendars_sheet_chip')),
          findsOneWidget,
        );

        // 2. Event creation dialog hides the redundant 1-option 'Thuộc bộ lịch' dropdown!
        await tester.tap(find.byKey(const Key('open_create_event_button')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('toggle_event_advanced_options')),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('event_calendar_dropdown')), findsNothing);
        await tester.tap(find.text('Hủy'));
        await tester.pumpAndSettle();

        // 3. Opening 'Bộ lịch' sheet shows 1 merged 'Lịch cá nhân' and keeps holiday feeds collapsed
        await tester.tap(find.byKey(const Key('open_calendars_sheet_chip')));
        await tester.pumpAndSettle();

        expect(find.text('Lịch cá nhân'), findsOneWidget);
        expect(find.text('Ngày lễ Việt Nam'), findsNothing);
        expect(
          find.byKey(const Key('system_calendars_expansion_tile')),
          findsOneWidget,
        );

        // Expand system feeds -> merged into 1 single 'Ngày lễ Việt Nam' row!
        await tester.tap(
          find.byKey(const Key('system_calendars_expansion_tile')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Ngày lễ Việt Nam'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
