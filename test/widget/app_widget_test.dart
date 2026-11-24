import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:life_os/app/app.dart';
import 'package:life_os/app/theme/app_theme.dart';
import 'package:life_os/core/constants/app_assets.dart';
import 'package:life_os/core/di/dependency_injection.dart';
import 'package:life_os/core/services/native_app_updater_bridge.dart';
import 'package:life_os/features/authentication/presentation/pages/splash_page.dart';

void main() {
  testWidgets(
    'Branded SplashPage renders Nano Banana artwork, logo & Tammy x Apple typography cleanly',
    (tester) async {
      for (final path in <String>[
        AppAssets.logo,
        AppAssets.splashHero,
        AppAssets.authHero,
        AppAssets.onboardingPrivacy,
        AppAssets.dashboardBanner,
        AppAssets.financeIllustration,
        AppAssets.familySplitIllustration,
        AppAssets.planningAssetsIllustration,
        ...AppAssets.allBananaIcons,
      ]) {
        expect(File(path).existsSync(), isTrue, reason: 'Missing asset $path');
      }

      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light(), home: const SplashPage()),
      );
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byKey(const Key('life_os_splash_page')), findsOneWidget);
      expect(find.text('Life OS'), findsOneWidget);
      expect(
        find.text('Tài chính Cá nhân · Hội nhóm · Gia đình'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Full LifeOsApp UI flow: Auth Guard -> Sign Up -> Privacy Onboarding -> 5-Tab Tammy x Apple Shell & Finance Recording',
    (tester) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mockAuth = MockFirebaseAuth();
      final fakeFirestore = FakeFirebaseFirestore();
      await configureDependencies(
        authOverride: mockAuth,
        firestoreOverride: fakeFirestore,
        httpClientOverride: MockClient((_) async => http.Response('{}', 404)),
      );

      await tester.pumpWidget(const LifeOsApp());
      await tester.pumpAndSettle();

      // 1. Unauthenticated user is guarded and routed to LoginPage (with Google Sign-In + Email)
      expect(find.text('Email đăng nhập'), findsOneWidget);
      expect(find.byKey(const Key('google_sign_in_button')), findsOneWidget);
      expect(find.byKey(const Key('go_to_register_button')), findsOneWidget);

      // 2. Navigate to RegisterPage and create an account with full validation
      final goRegisterFinder = find.byKey(const Key('go_to_register_button'));
      await tester.ensureVisible(goRegisterFinder);
      await tester.tap(goRegisterFinder);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('google_sign_up_button')), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('register_name_field')),
        'Trần Lan',
      );
      await tester.enterText(
        find.byKey(const Key('register_email_field')),
        'lan@lifeos.vn',
      );
      await tester.enterText(
        find.byKey(const Key('register_phone_field')),
        '0909123456',
      );
      await tester.enterText(
        find.byKey(const Key('register_password_field')),
        'Password123!',
      );
      await tester.enterText(
        find.byKey(const Key('register_confirm_password_field')),
        'Password123!',
      );

      final registerSubmit = find.byKey(const Key('register_submit_button'));
      await tester.ensureVisible(registerSubmit);
      await tester.tap(registerSubmit);
      await tester.pumpAndSettle();

      // 3. Routed to Privacy-First Onboarding Page
      expect(find.textContaining('Xin chào Trần Lan'), findsOneWidget);
      final onboardingBtn = find.byKey(const Key('complete_onboarding_button'));
      await tester.ensureVisible(onboardingBtn);
      await tester.tap(onboardingBtn);
      await tester.pumpAndSettle();

      // 4. Arrives on TodayPage with strictly 4 symmetrical bottom navigation tabs + Center `+`
      expect(find.text('Hôm nay'), findsWidgets);
      expect(find.text('Tài chính'), findsOneWidget);
      expect(find.text('Lịch & Việc'), findsOneWidget);
      expect(find.text('Gia đình'), findsOneWidget);
      expect(
        find.byKey(const Key('lifeos_center_quick_add_fab')),
        findsOneWidget,
      );
      expect(find.text('Tài sản'), findsNothing);

      // 5. Switch to Finance tab and record a real expense through BLoC -> UseCase -> Firestore
      await tester.tap(find.text('Tài chính'));
      await tester.pumpAndSettle();

      expect(find.text('Ví tiền mặt'), findsOneWidget);

      await tester.tap(find.byKey(const Key('open_add_tx_button')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('tx_amount_input')), '85000');
      await tester.enterText(
        find.byKey(const Key('tx_merchant_input')),
        'Phở Hòa Pasteur',
      );
      await tester.tap(find.byKey(const Key('submit_tx_dialog_button')));
      await tester.pumpAndSettle();

      expect(find.text('Phở Hòa Pasteur'), findsOneWidget);
      expect(find.textContaining('-85.000 ₫'), findsWidgets);

      // 6. Switch to Personal Analytics & Income Allocation tab and verify breakdown + allocator render
      final analyticsTab = find.byKey(const Key('finance_analytics_tab'));
      await tester.ensureVisible(analyticsTab);
      await tester.tap(analyticsTab);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Chỉ số Sức khỏe Tài chính Cá nhân'),
        findsOneWidget,
      );
      await tester.drag(
        find.byKey(const Key('analytics_list_view')),
        const Offset(0, -700),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Bộ Chia & Phân bổ Thu nhập'), findsOneWidget);

      // 7. Switch to Gia đình & Hội nhóm tab, create space & record a shared expense split
      await tester.tap(find.text('Gia đình'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open_create_space_button')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Căn hộ Ở ghép Q7');
      await tester.tap(find.text('Tạo'));
      await tester.pumpAndSettle();

      final splitBtn = find.byKey(const Key('open_add_split_bill_button'));
      await tester.ensureVisible(splitBtn);
      await tester.tap(splitBtn);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('split_bill_title_input')),
        'Ăn tối & Nước lau nhà',
      );
      await tester.enterText(
        find.byKey(const Key('split_bill_amount_input')),
        '240000',
      );
      await tester.tap(find.byKey(const Key('submit_split_bill_button')));
      await tester.pumpAndSettle();

      await tester.drag(
        find.byKey(const Key('split_bills_list_view')),
        const Offset(0, -350),
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const Key('split_bills_list_view')),
          matching: find.textContaining('Ăn tối & Nước lau nhà'),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    '1-Tap Google Sign-In / Sign-Up initializes Personal Space, Onboarding & Account Profile Page',
    (tester) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final googleMockUser = MockUser(
        isAnonymous: false,
        uid: 'uid_google_hoa',
        email: 'danhhoa.google@gmail.com',
        displayName: 'Danh Hòa Google',
        photoURL: '',
        isEmailVerified: true,
      );
      final mockAuth = MockFirebaseAuth(mockUser: googleMockUser);
      final fakeFirestore = FakeFirebaseFirestore();
      await fakeFirestore.collection('app_config').doc('release_manifest').set({
        'latestVersion': '1.1.0',
        'latestBuildNumber': 2,
        'minSupportedVersion': '1.0.0',
        'releaseTitle': 'Life OS v1.1.0 — Bản nâng cấp Siêu ứng dụng',
        'changelog': <String>[
          'Thêm cơ chế cập nhật OTA tự động trực tiếp từ GitHub Releases',
          'Tích hợp Mã QR quyết toán nhóm chuẩn VietQR / SePay',
        ],
        'htmlReleaseUrl':
            'https://github.com/danhhoa20005/life-os-superapp/releases/tag/v1.1.0',
      });

      await configureDependencies(
        authOverride: mockAuth,
        firestoreOverride: fakeFirestore,
        updaterBridgeOverride: const NativeAppUpdaterBridge(
          fixedInstalledMeta: InstalledAppMeta(
            versionName: '1.0.0',
            buildNumber: 1,
            packageName: 'vn.lifeos.app.life_os',
            abi: 'arm64-v8a',
          ),
        ),
        googleAuthOverride: (auth) =>
            auth.signInWithPopup(GoogleAuthProvider()),
        httpClientOverride: MockClient(
          (_) async => http.Response(
            '{"tag_name":"v1.1.0+2","name":"Life OS v1.1.0","body":"- OTA Auto Update\\n- VietQR Settlement","html_url":"https://github.com/danhhoa20005/life-os-superapp/releases/tag/v1.1.0"}',
            200,
          ),
        ),
      );

      await tester.pumpWidget(const LifeOsApp());
      await tester.pumpAndSettle();

      // Tap 1-Tap Google Sign-In button on LoginPage
      final googleBtn = find.byKey(const Key('google_sign_in_button'));
      expect(googleBtn, findsOneWidget);
      await tester.tap(googleBtn);
      await tester.pumpAndSettle();

      // Verify new Google user is routed to Onboarding with Google displayName
      expect(find.textContaining('Xin chào Danh Hòa Google'), findsOneWidget);
      final onboardingBtn = find.byKey(const Key('complete_onboarding_button'));
      await tester.ensureVisible(onboardingBtn);
      await tester.tap(onboardingBtn);
      await tester.pumpAndSettle();

      // Verify OTA In-App Update Banner automatically detected v1.1.0 on TodayPage!
      expect(find.byKey(const Key('ota_app_update_banner')), findsOneWidget);
      expect(find.textContaining('v1.1.0'), findsWidgets);

      // Open Account & Security Profile page via top-right avatar button
      final profileBtn = find.byKey(const Key('open_account_profile_button'));
      expect(profileBtn, findsOneWidget);
      await tester.tap(profileBtn);
      await tester.pumpAndSettle();

      expect(find.text('Hồ sơ & Bảo mật Tài khoản'), findsOneWidget);
      // Sensitive email is masked by default until user taps eye toggle
      expect(find.text('da•••@gmail.com'), findsOneWidget);
      expect(find.text('danhhoa.google@gmail.com'), findsNothing);
      expect(find.text('Đã liên kết'), findsOneWidget);

      await tester.tap(find.byKey(const Key('toggle_profile_sensitive_btn')));
      await tester.pumpAndSettle();
      expect(find.text('danhhoa.google@gmail.com'), findsOneWidget);

      // Update display name in Profile & save
      await tester.enterText(
        find.byKey(const Key('profile_name_field')),
        'Danh Hòa Pro',
      );
      final saveBtn = find.byKey(const Key('save_profile_button'));
      await tester.ensureVisible(saveBtn);
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      expect(find.text('Danh Hòa Pro'), findsWidgets);
    },
  );
}
