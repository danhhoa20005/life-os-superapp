import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:life_os/app/app.dart';
import 'package:life_os/app/theme/app_theme.dart';
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
      expect(violations, isEmpty, reason: 'Found legacy bottom showSnackBar in: $violations');
    });

    test('Zero confusing developer/accounting jargon remains in UI presentation pages', () {
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
          .where((f) => f.path.contains('presentation') && f.path.endsWith('.dart'))
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
      expect(violations, isEmpty, reason: 'Found wordy/technical UI jargon: $violations');
    });

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
          mockUser: MockUser(uid: uid, email: 'minh@lifeos.vn', displayName: 'Nguyễn Minh'),
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
  });
}
