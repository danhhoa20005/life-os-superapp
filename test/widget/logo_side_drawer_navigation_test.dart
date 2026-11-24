import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:life_os/app/app.dart';
import 'package:life_os/core/di/dependency_injection.dart';
import 'package:life_os/core/services/native_alarm_scheduler_bridge.dart';
import 'package:life_os/core/services/native_device_calendar_bridge.dart';
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

void _expectNoTruncatedTextInDrawer(WidgetTester tester) {
  final drawerFinder = find.byKey(const Key('lifeos_logo_side_drawer'));
  final richTexts = find.descendant(
    of: drawerFinder,
    matching: find.byType(RichText),
  );
  for (final element in richTexts.evaluate()) {
    final renderObj = element.renderObject;
    if (renderObj is RenderParagraph) {
      expect(
        renderObj.didExceedMaxLines,
        isFalse,
        reason:
            'Text truncated inside Logo Side Drawer: "${renderObj.text.toPlainText()}"',
      );
    }
  }
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

  testWidgets(
    'Tapping top-left LifeOS Logo slides open left feature drawer with category tabs, unaccented search, swipe-left dismiss & 1-tap navigation at 360x800',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final firestore = FakeFirebaseFirestore();
      final mockUser = MockUser(
        isAnonymous: false,
        uid: 'u_logo_drawer',
        email: 'drawer@lifeos.vn',
        displayName: 'Hoàng Minh',
      );
      await firestore.collection('users').doc('u_logo_drawer').set({
        'email': 'drawer@lifeos.vn',
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

      // 1. Tap top-left Logo button -> verify genuine left-to-right slide transition!
      expect(
        find.byKey(const Key('open_logo_side_drawer_button')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('open_logo_side_drawer_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));

      final drawerFinder = find.byKey(const Key('lifeos_logo_side_drawer'));
      expect(drawerFinder, findsOneWidget);
      // Mid-flight at 60ms, drawer left edge is negative (sliding in from left!)
      final midFlightDx = tester.getTopLeft(drawerFinder).dx;
      expect(midFlightDx, lessThan(0.0));

      await tester.pumpAndSettle();
      expect(tester.getTopLeft(drawerFinder).dx, closeTo(0.0, 0.01));
      _expectNoTruncatedTextInDrawer(tester);

      // 2. Test category pill tabs inside the drawer
      await tester.tap(find.byKey(const Key('logo_drawer_tab_finance')));
      await tester.pumpAndSettle();
      expect(find.text('Ngân hàng tự động & Mã QR'), findsOneWidget);
      expect(find.text('Bếp gia đình & Giỏ đi chợ'), findsNothing);
      _expectNoTruncatedTextInDrawer(tester);

      await tester.tap(find.byKey(const Key('logo_drawer_tab_health')));
      await tester.pumpAndSettle();
      expect(find.text('Nhắc uống nước & Chạy ngầm'), findsOneWidget);
      expect(find.text('Bếp gia đình & Giỏ đi chợ'), findsOneWidget);

      // Tap "Tất cả" resets tab filter
      await tester.tap(find.byKey(const Key('logo_drawer_tab_all')));
      await tester.pumpAndSettle();
      expect(find.text('Trang chủ Hôm nay'), findsOneWidget);

      // 3. Test unaccented Vietnamese search & 1-tap reset on empty query
      await tester.enterText(
        find.byKey(const Key('logo_drawer_search_input')),
        'dien nuoc evn',
      );
      await tester.pumpAndSettle();
      expect(find.text('Điện nước EVN & Hợp đồng nhà'), findsOneWidget);
      expect(find.text('Trang chủ Hôm nay'), findsNothing);

      await tester.enterText(
        find.byKey(const Key('logo_drawer_search_input')),
        'khongtontai999',
      );
      await tester.pumpAndSettle();
      expect(find.text('Không tìm thấy tính năng phù hợp'), findsOneWidget);
      await tester.tap(find.byKey(const Key('logo_drawer_reset_btn')));
      await tester.pumpAndSettle();
      expect(find.text('Trang chủ Hôm nay'), findsOneWidget);

      // 4. Tap "Nhắc uống nước & Chạy ngầm" -> closes drawer & opens Health Hub on Water tab
      final listScrollable = find.descendant(
        of: find.byKey(const Key('logo_drawer_feature_list')),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        find.byKey(const Key('logo_drawer_item_water_reminder')),
        140,
        scrollable: listScrollable,
      );
      await tester.ensureVisible(
        find.byKey(const Key('logo_drawer_item_water_reminder')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('logo_drawer_item_water_reminder')),
      );
      await tester.pumpAndSettle();

      expect(drawerFinder, findsNothing);
      expect(find.byKey(const Key('hydration_tracker_card')), findsOneWidget);

      // 5. Return to Today, open Logo drawer, switch shell tab to Finance, then swipe left to close!
      await tester.tap(find.byTooltip('Quay lại'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('open_logo_side_drawer_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('logo_drawer_item_finance_root')));
      await tester.pumpAndSettle();

      // Now on FinancePage -> tap Logo again and dismiss by swiping left
      await tester.tap(
        find.byKey(const Key('open_logo_side_drawer_button')).first,
      );
      await tester.pumpAndSettle();
      expect(drawerFinder, findsOneWidget);

      await tester.drag(drawerFinder, const Offset(-240, 0));
      await tester.pumpAndSettle();
      expect(drawerFinder, findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
