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
import 'package:life_os/core/utils/privacy_mask_formatter.dart';
import 'package:life_os/core/utils/user_behavior_prefs.dart';
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

void _assertZeroOverflowOnCurrentScreen(
  WidgetTester tester,
  String screenLabel,
) {
  final richTexts = find.byType(RichText);
  for (final element in richTexts.evaluate()) {
    final renderObj = element.renderObject;
    if (renderObj is RenderParagraph) {
      expect(
        renderObj.didExceedMaxLines,
        isFalse,
        reason:
            'Truncated text on $screenLabel: "${renderObj.text.toPlainText()}"',
      );
    }
  }
}

void main() {
  setUp(() async {
    await UserBehaviorPrefs.resetForTest();
    NativeAlarmSchedulerBridge.instance.resetDebugCounters();
    NativeDeviceCalendarBridge.setDriverOverride(
      const _NoOpDeviceCalendarDriver(),
    );
  });

  tearDown(() async {
    await UserBehaviorPrefs.resetForTest();
    NativeAlarmSchedulerBridge.instance.resetDebugCounters();
    NativeDeviceCalendarBridge.setDriverOverride(null);
    await sl.reset();
  });

  testWidgets(
    'Redesigned SettingsHubPage & AccountProfilePage: instant search, privacy toggles, 4-layer security score, live password strength & hardware PIN setup at 360x800 @ 112%',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final firestore = FakeFirebaseFirestore();
      final mockUser = MockUser(
        isAnonymous: false,
        uid: 'u_sec_profile_2026',
        email: 'baomat@lifeos.vn',
        displayName: 'Lê Thanh Tùng',
        isEmailVerified: true,
      );
      await firestore.collection('users').doc('u_sec_profile_2026').set({
        'id': 'u_sec_profile_2026',
        'email': 'baomat@lifeos.vn',
        'fullName': 'Lê Thanh Tùng',
        'phoneNumber': '0912345678',
        'timezone': 'Asia/Ho_Chi_Minh',
        'onboardingCompleted': true,
        'availabilityOptIn': false,
        'createdAt': DateTime(2026, 3, 15).toIso8601String(),
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

      // 0. Verify Top Bar Avatar sits flush against the far-right edge & secondary metrics stay hidden behind 'Chi tiết'
      final topAvatarBtn = find.byKey(const Key('open_account_profile_button'));
      expect(topAvatarBtn, findsOneWidget);
      expect(tester.getTopRight(topAvatarBtn).dx, greaterThanOrEqualTo(352.0));

      expect(find.text('Thu tháng'), findsNothing);
      expect(find.text('Chi tháng'), findsNothing);
      await tester.tap(find.byKey(const Key('today_hero_details_toggle')));
      await tester.pumpAndSettle();
      expect(find.text('Thu tháng'), findsOneWidget);
      expect(find.text('Chi tháng'), findsOneWidget);
      await tester.tap(find.byKey(const Key('today_hero_details_toggle')));
      await tester.pumpAndSettle();
      expect(find.text('Thu tháng'), findsNothing);

      // 1. Open SettingsHubPage via Logo Side Drawer footer
      await tester.tap(find.byKey(const Key('open_logo_side_drawer_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('logo_drawer_settings_btn')));
      await tester.pumpAndSettle();

      expect(find.text('Cài đặt'), findsOneWidget);
      // Sensitive email & PIN status are masked/hidden on SettingsHubPage
      expect(find.text('ba•••@lifeos.vn'), findsOneWidget);
      expect(find.text('baomat@lifeos.vn'), findsNothing);
      expect(find.textContaining('Mã PIN:'), findsNothing);
      _assertZeroOverflowOnCurrentScreen(tester, 'SettingsHubPage');

      // 2. Test instant unaccented Vietnamese search inside Settings
      await tester.enterText(
        find.byKey(const Key('settings_search_input')),
        'an so du',
      );
      await tester.pumpAndSettle();
      expect(find.text('Ẩn số dư nhạy cảm'), findsOneWidget);
      expect(find.text('Đồng bộ Google Calendar'), findsNothing);

      // Toggle Hide Balances ON right inside Settings search result
      await tester.tap(find.byKey(const Key('settings_hide_balances_switch')));
      await tester.pumpAndSettle();
      expect(await UserBehaviorPrefs.loadHideBalances(), isTrue);

      // Test empty search reset
      await tester.enterText(
        find.byKey(const Key('settings_search_input')),
        'khongcomucnay',
      );
      await tester.pumpAndSettle();
      expect(find.text('Không tìm thấy mục cài đặt'), findsOneWidget);
      await tester.tap(find.byKey(const Key('settings_search_reset_btn')));
      await tester.pumpAndSettle();
      expect(find.text('Đồng bộ Google Calendar'), findsOneWidget);

      // 3. Navigate from Settings Hero Card to AccountProfilePage
      await tester.tap(find.byKey(const Key('settings_hero_profile_card')));
      await tester.pumpAndSettle();

      expect(find.text('Hồ sơ & Bảo mật Tài khoản'), findsOneWidget);
      expect(
        find.byKey(const Key('account_security_score_card')),
        findsOneWidget,
      );
      // Verify personal email, phone, UID & security controls are masked/collapsed by default
      expect(find.text('ba•••@lifeos.vn'), findsOneWidget);
      expect(find.text('baomat@lifeos.vn'), findsNothing);
      expect(find.text('091•••••78'), findsOneWidget);
      expect(
        find.byWidgetPredicate((w) => w is Text && w.data == '0912345678'),
        findsNothing,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('profile_phone_field')))
            .obscureText,
        isTrue,
      );
      expect(find.text('Mã TK: ••••••'), findsOneWidget);
      expect(find.text('Chưa bật PIN'), findsNothing);
      expect(find.text('Mã PIN bật'), findsNothing);
      _assertZeroOverflowOnCurrentScreen(tester, 'AccountProfilePage');

      // Toggle eye icon to reveal personal identifiers, then hide again
      await tester.tap(find.byKey(const Key('toggle_profile_sensitive_btn')));
      await tester.pumpAndSettle();
      expect(find.text('baomat@lifeos.vn'), findsOneWidget);
      expect(
        find.byWidgetPredicate((w) => w is Text && w.data == '0912345678'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('profile_phone_field')))
            .obscureText,
        isFalse,
      );
      await tester.tap(find.byKey(const Key('toggle_profile_sensitive_btn')));
      await tester.pumpAndSettle();
      expect(find.text('ba•••@lifeos.vn'), findsOneWidget);

      // Expand collapsible security section before configuring Password & App PIN
      await tester.tap(find.byKey(const Key('toggle_security_controls_btn')));
      await tester.pumpAndSettle();
      _assertZeroOverflowOnCurrentScreen(
        tester,
        'AccountProfilePage (Security Expanded)',
      );

      // 4. Open Change Password dialog & verify live 4-bar strength meter updates
      final profileScrollable = find.descendant(
        of: find.byKey(const Key('account_profile_list_view')),
        matching: find.byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
        ),
      );
      final changePwdBtn = find.byKey(const Key('open_change_password_button'));
      await tester.scrollUntilVisible(
        changePwdBtn,
        160,
        scrollable: profileScrollable,
      );
      await tester.ensureVisible(changePwdBtn);
      await tester.pumpAndSettle();
      await tester.tap(changePwdBtn);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('new_password_field')),
        'abc',
      );
      await tester.pumpAndSettle();
      expect(find.text('Độ mạnh: Yếu'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('new_password_field')),
        'BaoMat@2026Pro!',
      );
      await tester.pumpAndSettle();
      expect(find.text('Độ mạnh: Rất mạnh'), findsOneWidget);

      await tester.tap(find.text('Hủy'));
      await tester.pumpAndSettle();

      // 5. Set up 4-digit Hardware Security PIN & verify security score increments!
      final pinRow = find.byKey(const Key('open_app_pin_dialog_btn'));
      await tester.scrollUntilVisible(
        pinRow,
        140,
        scrollable: profileScrollable,
      );
      await tester.ensureVisible(pinRow);
      await tester.pumpAndSettle();
      await tester.tap(pinRow);
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('pin_new_input')), '2468');
      await tester.enterText(
        find.byKey(const Key('pin_confirm_input')),
        '2468',
      );
      await tester.tap(find.byKey(const Key('submit_pin_setup_btn')));
      await tester.pumpAndSettle();

      expect(await UserBehaviorPrefs.hasAppPinCode(), isTrue);
      expect(await UserBehaviorPrefs.verifyAppPinCode('2468'), isTrue);
      expect(await UserBehaviorPrefs.verifyAppPinCode('9999'), isFalse);

      // Scroll back to top & verify Mã PIN bật badge is reflected on Security Score Card
      await tester.scrollUntilVisible(
        find.byKey(const Key('account_security_score_card')),
        -180,
        scrollable: profileScrollable,
      );
      await tester.pumpAndSettle();
      expect(find.text('Mã PIN bật'), findsOneWidget);

      // 6. Toggle family availability sharing switch
      final availSwitch = find.byKey(
        const Key('profile_availability_opt_in_switch'),
      );
      await tester.scrollUntilVisible(
        availSwitch,
        160,
        scrollable: profileScrollable,
      );
      await tester.ensureVisible(availSwitch);
      await tester.pumpAndSettle();
      await tester.tap(availSwitch);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'PrivacyMaskFormatter masks emails, phones, UIDs, invite codes & document reference codes cleanly',
    () {
      expect(
        PrivacyMaskFormatter.maskEmail('baomat@lifeos.vn'),
        'ba•••@lifeos.vn',
      );
      expect(PrivacyMaskFormatter.maskEmail('a@b.vn'), 'a•••@b.vn');
      expect(PrivacyMaskFormatter.maskPhone('0912345678'), '091•••••78');
      expect(PrivacyMaskFormatter.maskUid('u_sec_profile_2026'), '••••••');
      expect(PrivacyMaskFormatter.maskCode('079200012345'), '•••• 2345');
      expect(PrivacyMaskFormatter.maskCode('FAM-8K2P9Q'), 'FAM-••••9Q');
      expect(
        PrivacyMaskFormatter.maskContact('nguoithan@gmail.com'),
        'ng•••@gmail.com',
      );
      expect(PrivacyMaskFormatter.maskContact('0988776655'), '098•••••55');
    },
  );
}
