import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:life_os/app/app.dart';
import 'package:life_os/app/theme/app_theme.dart';
import 'package:life_os/core/di/dependency_injection.dart';
import 'package:life_os/core/motion/lifeos_motion.dart';
import 'package:life_os/core/services/native_device_calendar_bridge.dart';
import 'package:life_os/core/services/native_permissions_service.dart';
import 'package:life_os/core/utils/user_behavior_prefs.dart';
import 'package:life_os/core/widgets/lifeos_permissions_popup.dart';
import 'package:life_os/core/widgets/trust_ux_widgets.dart';
import 'package:life_os/features/financial_ai/data/inference/fasttext_classifier.dart';

class _NoOpCalendarDriver implements DeviceCalendarDriver {
  const _NoOpCalendarDriver();
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

class _FakePermissionsDriver implements PermissionsDriver {
  AppPermissionsSnapshot state;
  int requestEssentialCalls = 0;
  final List<LifeOsPermissionKind> requestedSingles = <LifeOsPermissionKind>[];

  _FakePermissionsDriver(this.state);

  @override
  bool get isSupportedPlatform => true;

  @override
  Future<AppPermissionsSnapshot> checkAll() async => state;

  @override
  Future<AppPermissionsSnapshot> requestEssential() async {
    requestEssentialCalls++;
    state = state.copyWith(
      notifications: true,
      microphone: true,
      calendar: true,
    );
    return state;
  }

  @override
  Future<AppPermissionsSnapshot> requestSingle(
    LifeOsPermissionKind kind,
  ) async {
    requestedSingles.add(kind);
    state = switch (kind) {
      LifeOsPermissionKind.notifications => state.copyWith(notifications: true),
      LifeOsPermissionKind.microphone => state.copyWith(microphone: true),
      LifeOsPermissionKind.calendar => state.copyWith(calendar: true),
      LifeOsPermissionKind.exactAlarm => state.copyWith(exactAlarm: true),
      LifeOsPermissionKind.batteryUnrestricted => state.copyWith(
        batteryUnrestricted: true,
      ),
      LifeOsPermissionKind.bankNotificationListener => state.copyWith(
        bankNotificationListener: true,
      ),
    };
    return state;
  }

  @override
  Future<void> openAppSettings() async {}
}

void main() {
  setUp(() async {
    await UserBehaviorPrefs.resetForTest();
    NativeDeviceCalendarBridge.setDriverOverride(const _NoOpCalendarDriver());
  });

  tearDown(() async {
    NativePermissionsService.setDriverOverride(null);
    NativeDeviceCalendarBridge.setDriverOverride(null);
    await UserBehaviorPrefs.resetForTest();
    await sl.reset();
  });

  group('Device Permissions & Just-in-Time Rationale UX', () {
    testWidgets(
      'Never auto-prompts permissions on cold launch; opens on demand from Settings Hub with 4-part rationale & grants cleanly at 360x800 @ 112%',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(360, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final fakePerms = _FakePermissionsDriver(
          AppPermissionsSnapshot.allMissing,
        );
        NativePermissionsService.setDriverOverride(fakePerms);

        final firestore = FakeFirebaseFirestore();
        final mockUser = MockUser(
          isAnonymous: false,
          uid: 'u_perm_popup',
          email: 'perm@lifeos.vn',
          displayName: 'Hoàng Minh',
        );
        await firestore.collection('users').doc('u_perm_popup').set({
          'email': 'perm@lifeos.vn',
          'fullName': 'Hoàng Minh',
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

        await tester.pumpWidget(
          const MediaQuery(
            data: MediaQueryData(
              size: Size(360, 800),
              textScaler: TextScaler.linear(1.12),
            ),
            child: LifeOsApp(),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Cold launch NEVER triggers eager OS permission popup or requests
        expect(
          find.byKey(const Key('lifeos_permissions_popup_dialog')),
          findsNothing,
        );
        expect(fakePerms.requestEssentialCalls, 0);
        expect(fakePerms.requestedSingles, isEmpty);

        // 2. Navigate via Logo Side Drawer -> Settings Hub -> Quyền hạn Thiết bị
        await tester.tap(find.byKey(const Key('open_logo_side_drawer_button')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('logo_drawer_settings_btn')));
        await tester.pumpAndSettle();

        await tester.ensureVisible(
          find.byKey(const Key('settings_permissions_popup_row')),
        );
        await tester.tap(
          find.byKey(const Key('settings_permissions_popup_row')),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('lifeos_permissions_popup_dialog')),
          findsOneWidget,
        );
        expect(find.text('Cấp quyền thiết bị'), findsOneWidget);
        expect(find.text('Đã bật 0/6'), findsOneWidget);
        expect(find.textContaining('Vì sao cần:'), findsWidgets);
        expect(find.textContaining('Dữ liệu truy cập:'), findsWidgets);
        expect(find.textContaining('Xử lý tại máy:'), findsWidgets);
        expect(find.textContaining('Cách tắt trong Cài đặt:'), findsWidgets);
        expect(
          find.byKey(const Key('perm_item_notifications')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('perm_item_microphone')), findsOneWidget);
        expect(find.byKey(const Key('perm_item_calendar')), findsOneWidget);
        expect(tester.takeException(), isNull);

        // 3. Expand progressive disclosure for advanced permissions & grant Exact Alarm
        await tester.ensureVisible(
          find.byKey(const Key('perm_popup_advanced_toggle')),
        );
        await tester.tap(find.byKey(const Key('perm_popup_advanced_toggle')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('perm_item_exactAlarm')), findsOneWidget);
        await tester.ensureVisible(
          find.byKey(const Key('perm_action_exactAlarm')),
        );
        await tester.tap(find.byKey(const Key('perm_action_exactAlarm')));
        await tester.pumpAndSettle();

        expect(
          fakePerms.requestedSingles,
          contains(LifeOsPermissionKind.exactAlarm),
        );
        expect(find.text('Đã bật 1/6'), findsOneWidget);

        // 4. Tap primary CTA "Cấp nhanh quyền cơ bản" -> grants all 3 essential permissions (4/6 total)
        await tester.ensureVisible(
          find.byKey(const Key('permissions_popup_grant_essential_btn')),
        );
        await tester.tap(
          find.byKey(const Key('permissions_popup_grant_essential_btn')),
        );
        await tester.pumpAndSettle();

        expect(fakePerms.requestEssentialCalls, 1);
        expect(find.text('Đã bật 4/6'), findsOneWidget);
        expect(find.text('Hoàn tất thiết lập'), findsOneWidget);

        // 5. Tap "Hoàn tất thiết lập" -> closes popup cleanly
        await tester.tap(
          find.byKey(const Key('permissions_popup_grant_essential_btn')),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('lifeos_permissions_popup_dialog')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Respects Reduce Motion, closes on "Để sau" & close icon, and re-opens on demand from Settings Hub',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(360, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final fakePerms = _FakePermissionsDriver(
          const AppPermissionsSnapshot(
            notifications: false,
            microphone: true,
            calendar: false,
            exactAlarm: true,
            batteryUnrestricted: false,
            bankNotificationListener: false,
          ),
        );
        NativePermissionsService.setDriverOverride(fakePerms);

        final firestore = FakeFirebaseFirestore();
        final mockUser = MockUser(
          isAnonymous: false,
          uid: 'u_perm_later',
          email: 'later@lifeos.vn',
          displayName: 'Minh Thư',
        );
        await firestore.collection('users').doc('u_perm_later').set({
          'email': 'later@lifeos.vn',
          'fullName': 'Minh Thư',
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

        await tester.pumpWidget(
          LifeOsMotionScope.overrideForTest(
            preferences: const LifeOsMotionPreferences(
              platformReduceMotion: true,
            ),
            child: const LifeOsApp(),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('lifeos_permissions_popup_dialog')),
          findsNothing,
        );

        // Open Settings Hub -> tap "Quyền hạn Thiết bị" row to open popup on demand
        await tester.tap(find.byKey(const Key('open_logo_side_drawer_button')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('logo_drawer_settings_btn')));
        await tester.pumpAndSettle();

        await tester.ensureVisible(
          find.byKey(const Key('settings_permissions_popup_row')),
        );
        await tester.tap(
          find.byKey(const Key('settings_permissions_popup_row')),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('lifeos_permissions_popup_dialog')),
          findsOneWidget,
        );
        expect(find.text('Đã bật 2/6'), findsOneWidget);

        await tester.ensureVisible(
          find.byKey(const Key('permissions_popup_later_btn')),
        );
        await tester.tap(find.byKey(const Key('permissions_popup_later_btn')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('lifeos_permissions_popup_dialog')),
          findsNothing,
        );

        // Re-open and test close icon
        await tester.ensureVisible(
          find.byKey(const Key('settings_permissions_popup_row')),
        );
        await tester.tap(
          find.byKey(const Key('settings_permissions_popup_row')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('permissions_popup_close_icon_btn')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('lifeos_permissions_popup_dialog')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'Direct showLifeOsPermissionsPopup works standalone in Dark mode',
      (tester) async {
        final fakePerms = _FakePermissionsDriver(
          AppPermissionsSnapshot.allMissing,
        );
        NativePermissionsService.setDriverOverride(fakePerms);

        await tester.pumpWidget(
          MaterialApp(
            themeMode: ThemeMode.dark,
            darkTheme: AppTheme.dark(),
            home: Scaffold(
              body: Builder(
                builder: (ctx) => Center(
                  child: ElevatedButton(
                    onPressed: () => showLifeOsPermissionsPopup(ctx),
                    child: const Text('Mở Popup'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Mở Popup'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('lifeos_permissions_popup_dialog')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'showLifeOsJustInTimePermissionRationale displays 4 Section 13 answers & handles Consent / Decline without blocking',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(360, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        bool? lastResult;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(360, 800),
                textScaler: TextScaler.linear(1.12),
              ),
              child: Scaffold(
                body: Builder(
                  builder: (ctx) => Center(
                    child: FilledButton(
                      onPressed: () async {
                        lastResult = await showLifeOsJustInTimePermissionRationale(
                          ctx,
                          title: 'Quyền Lịch thiết bị',
                          whyNeeded:
                              'Đồng bộ lịch hẹn cá nhân và nhắc việc đúng giờ.',
                          dataAccessed:
                              'Chỉ đọc tiêu đề và giờ sự kiện bạn chọn.',
                          whereProcessed:
                              'Xử lý trực tiếp trên thiết bị của bạn.',
                          howToRevoke:
                              'Tắt bất cứ lúc nào trong Cài đặt > Quyền ứng dụng.',
                        );
                      },
                      child: const Text('Hỏi quyền'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Hỏi quyền'));
        await tester.pumpAndSettle();

        expect(find.text('Vì sao cần quyền?'), findsOneWidget);
        expect(find.text('Dữ liệu nào được truy cập?'), findsOneWidget);
        expect(find.text('Dữ liệu được xử lý ở đâu?'), findsOneWidget);
        expect(find.text('Làm thế nào để tắt quyền?'), findsOneWidget);

        await tester.tap(find.text('Để sau'));
        await tester.pumpAndSettle();
        expect(lastResult, isFalse);

        await tester.tap(find.text('Hỏi quyền'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Đồng ý cấp quyền'));
        await tester.pumpAndSettle();
        expect(lastResult, isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
