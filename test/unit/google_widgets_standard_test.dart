import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:life_os/app/app.dart';
import 'package:life_os/core/di/dependency_injection.dart';

void main() {
  group('Google Material You (M3) Native Android AppWidget Compliance', () {
    test('All 4 widget_info XMLs declare previewLayout, targetCellWidth/Height & resize support', () {
      const infoFiles = [
        'android/app/src/main/res/xml/widget_info_voice_quick.xml',
        'android/app/src/main/res/xml/widget_info_wealth_net_worth.xml',
        'android/app/src/main/res/xml/widget_info_group_split.xml',
        'android/app/src/main/res/xml/widget_info_daily_safe_spend.xml',
      ];

      for (final path in infoFiles) {
        final xml = File(path).readAsStringSync();
        expect(xml, contains('android:previewLayout="@layout/widget_'), reason: path);
        expect(xml, contains('android:targetCellWidth='), reason: path);
        expect(xml, contains('android:targetCellHeight='), reason: path);
        expect(xml, contains('android:minResizeWidth='), reason: path);
        expect(xml, contains('android:widgetFeatures='), reason: path);
      }
    });

    test('All 4 widget layouts use @android:id/background, Day/Night @color/widget_* & zero emojis', () {
      const layoutFiles = [
        'android/app/src/main/res/layout/widget_voice_quick.xml',
        'android/app/src/main/res/layout/widget_wealth_net_worth.xml',
        'android/app/src/main/res/layout/widget_group_split.xml',
        'android/app/src/main/res/layout/widget_daily_safe_spend.xml',
      ];

      for (final path in layoutFiles) {
        final xml = File(path).readAsStringSync();
        expect(xml, contains('android:id="@android:id/background"'), reason: path);
        expect(xml, contains('android:clipToOutline="true"'), reason: path);
        expect(xml, contains('@drawable/bg_widget_m3_surface'), reason: path);
        expect(xml, contains('@color/widget_text_primary'), reason: path);
        expect(xml.contains('🎙'), isFalse, reason: 'Emoji found in $path');
        expect(xml.contains('⇄'), isFalse, reason: 'Emoji found in $path');
      }

      expect(File('android/app/src/main/res/values/colors.xml').existsSync(), isTrue);
      expect(File('android/app/src/main/res/values-night/colors.xml').existsSync(), isTrue);
      expect(File('android/app/src/main/res/values-v31/dimens.xml').existsSync(), isTrue);
    });

    testWidgets('HomeWidgetsStudioPage renders all 4 Google Material 3 Widgets cleanly', (tester) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mockUser = MockUser(
        isAnonymous: false,
        uid: 'uid_m3_widgets',
        email: 'widget@lifeos.vn',
        displayName: 'Nguyễn Minh',
        isEmailVerified: true,
      );
      final mockAuth = MockFirebaseAuth(mockUser: mockUser, signedIn: true);
      final fakeFirestore = FakeFirebaseFirestore();
      await fakeFirestore.collection('users').doc('uid_m3_widgets').set({
        'id': 'uid_m3_widgets',
        'email': 'widget@lifeos.vn',
        'fullName': 'Nguyễn Minh',
        'onboardingCompleted': true,
        'availabilityOptIn': false,
        'createdAt': DateTime.now().toIso8601String(),
      });

      await configureDependencies(
        authOverride: mockAuth,
        firestoreOverride: fakeFirestore,
        httpClientOverride: MockClient((_) async => http.Response('{}', 404)),
      );

      await tester.pumpWidget(const LifeOsApp());
      await tester.pumpAndSettle();

      // Open Kho Dịch vụ 360° -> 4 Widget Chính
      await tester.scrollUntilVisible(
        find.byKey(const Key('home_tile_all_services')),
        220,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('home_tile_all_services')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('4 Widget Chính'));
      await tester.pumpAndSettle();

      expect(find.text('4 Widget Chuẩn Google M3'), findsOneWidget);
      expect(find.textContaining('THANH TÌM KIẾM & GIỌNG NÓI PIXEL'), findsOneWidget);
      expect(find.byKey(const Key('sync_widgets_now_button')), findsOneWidget);
    });
  });
}
