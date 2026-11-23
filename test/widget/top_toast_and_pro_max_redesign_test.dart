import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:life_os/app/app.dart';
import 'package:life_os/app/theme/app_theme.dart';
import 'package:life_os/app/theme/theme_bloc.dart';
import 'package:life_os/core/di/dependency_injection.dart';
import 'package:life_os/core/widgets/lifeos_top_toast.dart';

void main() {
  group('Top Toast Standard & UI/UX Pro Max Redesign Verification (v3.1.0+16)', () {
    test('Zero bottom showSnackBar calls remain anywhere in lib/', () {
      final dartFiles = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();

      final violations = <String>[];
      for (final f in dartFiles) {
        final content = f.readAsStringSync();
        if (content.contains('.showSnackBar(')) {
          violations.add(f.path);
        }
      }
      expect(
        violations,
        isEmpty,
        reason: 'Found legacy bottom showSnackBar in: $violations',
      );
    });

    test(
      'Zero confusing developer/accounting jargon remains in UI presentation pages',
      () {
        const bannedUiJargon = <String>[
          'BankNotificationListenerService',
          'BIÊN LAI SỔ CÁI ĐÃ ĐỐI SOÁT',
          'BÚT TOÁN ĐÃ ĐẢO NGƯỢC',
          'Chuẩn RFC 5545 RRULE',
          'Hạ tầng Firebase Cloud (life-os-vn-2026)',
          'Thay thế Rocket Money',
          'Zero-OTP',
          'Khử trùng lặp SHA-256',
        ];
        final uiFiles = Directory('lib/features')
            .listSync(recursive: true)
            .whereType<File>()
            .where(
              (f) =>
                  f.path.contains('presentation') && f.path.endsWith('.dart'),
            )
            .toList();

        final violations = <String>[];
        for (final f in uiFiles) {
          final content = f.readAsStringSync();
          for (final term in bannedUiJargon) {
            if (content.contains(term)) {
              violations.add('${f.path}: "$term"');
            }
          }
        }
        expect(
          violations,
          isEmpty,
          reason: 'Found wordy/technical UI jargon: $violations',
        );
      },
    );

    testWidgets(
      'LifeOsTopToast renders strictly at the TOP of the screen, triggers actions & auto-dismisses cleanly',
      (tester) async {
        var actionTapped = false;

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            builder: (_, child) => LifeOsTopToastHost(child: child!),
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: ElevatedButton(
                    key: const Key('trigger_top_toast_btn'),
                    onPressed: () {
                      LifeOsTopToast.show(
                        context,
                        '✓ Đã ghi nhận giao dịch 250.000 ₫ vào Ví chính.',
                        actionLabel: 'Hoàn tác',
                        onAction: () => actionTapped = true,
                      );
                    },
                    child: const Text('Hiện Toast'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.byKey(const Key('trigger_top_toast_btn')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 260));

        final bannerFinder = find.byKey(const Key('lifeos_top_toast_banner'));
        expect(bannerFinder, findsOneWidget);
        expect(find.text('Thành công'), findsOneWidget);
        expect(find.textContaining('250.000 ₫'), findsOneWidget);

        // Verify Top Toast is positioned at the TOP of the 600px viewport (dy < 80px), NOT bottom!
        final topLeft = tester.getTopLeft(bannerFinder);
        expect(topLeft.dy, lessThan(80.0));

        // Tap optional action button
        await tester.tap(find.text('Hoàn tác'));
        await tester.pumpAndSettle();
        expect(actionTapped, isTrue);
        expect(bannerFinder, findsNothing);
      },
    );

    testWidgets(
      'Redesigned TodayPage renders Emerald Hero Card, Balance Privacy Toggle + Top Toast & Floating Glass Dock',
      (tester) async {
        final fakeFirestore = FakeFirebaseFirestore();
        const uid = 'uid_redesign_v31';
        await fakeFirestore.collection('users').doc(uid).set({
          'id': uid,
          'email': 'minh@lifeos.vn',
          'fullName': 'Nguyễn Minh',
          'onboardingCompleted': true,
          'availabilityOptIn': false,
        });
        await fakeFirestore
            .collection('users')
            .doc(uid)
            .collection('wallets')
            .doc('wallet_bank_default')
            .set({
              'id': 'wallet_bank_default',
              'ownerId': uid,
              'name': 'Vietcombank',
              'type': 'bank',
              'balanceMinor': 18500000,
              'isEstimatedBalance': false,
            });

        final mockAuth = MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(
            uid: uid,
            email: 'minh@lifeos.vn',
            displayName: 'Nguyễn Minh',
          ),
        );

        await sl.reset();
        await configureDependencies(
          authOverride: mockAuth,
          firestoreOverride: fakeFirestore,
          httpClientOverride: MockClient((_) async => http.Response('{}', 404)),
        );

        await tester.pumpWidget(const LifeOsApp());
        await tester.pumpAndSettle();

        expect(find.text('Tổng tài sản ròng cá nhân'), findsOneWidget);
        expect(find.text('Việc cần chú ý'), findsOneWidget);

        // Tap 1-Tap Eye Privacy Toggle -> masks balance & shows Top Toast at top of screen!
        await tester.tap(find.byKey(const Key('toggle_balance_privacy_btn')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 260));

        expect(find.textContaining('•••••••• ₫'), findsWidgets);
        final toastFinder = find.byKey(const Key('lifeos_top_toast_banner'));
        expect(toastFinder, findsOneWidget);
        expect(tester.getTopLeft(toastFinder).dy, lessThan(90.0));

        // Advance past auto-dismiss timer
        await tester.pump(const Duration(seconds: 2));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );

    test(
      'UI/UX Pro Max v3.4: Home & Directory use LifeOsResponsiveIconGrid and Vietnamese wallet badges',
      () {
        final todaySrc = File(
          'lib/features/dashboard/presentation/pages/today_page.dart',
        ).readAsStringSync();
        final dirSrc = File(
          'lib/features/daily_life/presentation/pages/super_app_directory_page.dart',
        ).readAsStringSync();
        final proMaxSrc = File(
          'lib/core/widgets/pro_max_widgets.dart',
        ).readAsStringSync();

        expect(todaySrc.contains('GridView.count'), isFalse);
        expect(todaySrc.contains('LifeOsResponsiveIconGrid'), isTrue);
        expect(dirSrc.contains('GridView.count'), isFalse);
        expect(dirSrc.contains('LifeOsResponsiveIconGrid'), isTrue);

        for (final englishBadge in const [
          'LIQUID CASH',
          'WEALTH VAULT',
          'NAPAS247',
        ]) {
          expect(proMaxSrc.contains(englishBadge), isFalse);
        }
      },
    );

    testWidgets(
      'UI/UX Pro Max v3.4: Narrow 360x800 phone + 112% Large Font Scale renders all 5 tabs & All Services with ZERO overflow',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final fakeFirestore = FakeFirebaseFirestore();
        const uid = 'uid_pro_max_v34';
        await fakeFirestore.collection('users').doc(uid).set({
          'id': uid,
          'email': 'hoa@lifeos.vn',
          'fullName': 'Nguyễn Danh Hòa',
          'onboardingCompleted': true,
          'availabilityOptIn': false,
        });
        await fakeFirestore
            .collection('users')
            .doc(uid)
            .collection('wallets')
            .doc('wallet_bank_default')
            .set({
              'id': 'wallet_bank_default',
              'ownerId': uid,
              'name': 'Tài khoản Vietcombank Gia đình',
              'type': 'bank',
              'balanceMinor': 128500000,
              'isEstimatedBalance': false,
            });

        final mockAuth = MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(
            uid: uid,
            email: 'hoa@lifeos.vn',
            displayName: 'Nguyễn Danh Hòa',
          ),
        );

        await sl.reset();
        await configureDependencies(
          authOverride: mockAuth,
          firestoreOverride: fakeFirestore,
          httpClientOverride: MockClient((_) async => http.Response('{}', 404)),
        );

        await tester.pumpWidget(const LifeOsApp());
        await tester.pumpAndSettle();

        // Switch app-wide font scale to Large (112%)
        final scaffoldCtx = tester.element(find.byType(Scaffold).first);
        scaffoldCtx.read<ThemeBloc>().add(const TextScaleChanged(1.12));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        // Open All Services 360° Directory and verify crisp labels & zero overflow
        final allServicesCard = find.byKey(const Key('home_tile_all_services'));
        await tester.scrollUntilVisible(
          allServicesCard,
          220,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(allServicesCard);
        await tester.pumpAndSettle();
        expect(find.text('Sổ thu chi'), findsOneWidget);
        expect(find.text('Lương Gross–Net'), findsOneWidget);
        expect(tester.takeException(), isNull);

        // Pop back to Home and traverse all 4 symmetrical tabs + pushed Vehicles/Assets hub at 360px + 112% font
        await tester.tap(find.byTooltip('Quay lại'));
        await tester.pumpAndSettle();

        for (final tabLabel in const ['Tài chính', 'Lịch & Việc', 'Gia đình']) {
          await tester.tap(find.text(tabLabel).last);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }

        // Inside Gia đình tab (solo mode), verify clearly separated Vehicles & Living hub opens AssetsPage cleanly
        final vehiclesTile = find.byKey(const Key('family_hub_vehicles_tile'));
        expect(vehiclesTile, findsOneWidget);
        await tester.tap(vehiclesTile);
        await tester.pumpAndSettle();
        expect(find.text('Xe cộ & Hóa đơn'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('Quay lại'));
        await tester.pumpAndSettle();
      },
    );
  });
}
