import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:life_os/app/app.dart';
import 'package:life_os/core/di/dependency_injection.dart';
import 'package:life_os/core/services/native_home_widget_bridge.dart';
import 'package:life_os/core/utils/user_behavior_prefs.dart';
import 'package:life_os/features/transactions/presentation/bloc/transaction_bloc.dart';

void main() {
  setUp(() async {
    await UserBehaviorPrefs.resetForTest();
  });

  group('Google Material You (M3) Interactive On-Home-Screen AppWidgets', () {
    test(
      'All 4 widget_info XMLs declare previewLayout, targetCellWidth/Height & resize support',
      () {
        const infoFiles = [
          'android/app/src/main/res/xml/widget_info_voice_quick.xml',
          'android/app/src/main/res/xml/widget_info_wealth_net_worth.xml',
          'android/app/src/main/res/xml/widget_info_group_split.xml',
          'android/app/src/main/res/xml/widget_info_daily_safe_spend.xml',
        ];

        for (final path in infoFiles) {
          final xml = File(path).readAsStringSync();
          expect(
            xml,
            contains('android:previewLayout="@layout/widget_'),
            reason: path,
          );
          expect(xml, contains('android:targetCellWidth='), reason: path);
          expect(xml, contains('android:targetCellHeight='), reason: path);
          expect(xml, contains('android:minResizeWidth='), reason: path);
          expect(xml, contains('android:widgetFeatures='), reason: path);
        }
      },
    );

    test(
      'All 4 widget layouts use @android:id/background, Day/Night @color/widget_* & zero emojis',
      () {
        const layoutFiles = [
          'android/app/src/main/res/layout/widget_voice_quick.xml',
          'android/app/src/main/res/layout/widget_wealth_net_worth.xml',
          'android/app/src/main/res/layout/widget_group_split.xml',
          'android/app/src/main/res/layout/widget_daily_safe_spend.xml',
        ];

        for (final path in layoutFiles) {
          final xml = File(path).readAsStringSync();
          expect(
            xml,
            contains('android:id="@android:id/background"'),
            reason: path,
          );
          expect(xml, contains('android:clipToOutline="true"'), reason: path);
          expect(xml, contains('@drawable/bg_widget_m3_surface'), reason: path);
          expect(xml, contains('@color/widget_text_primary'), reason: path);
          expect(xml.contains('🎙'), isFalse, reason: 'Emoji found in $path');
          expect(xml.contains('⇄'), isFalse, reason: 'Emoji found in $path');
        }

        expect(
          File('android/app/src/main/res/values/colors.xml').existsSync(),
          isTrue,
        );
        expect(
          File('android/app/src/main/res/values-night/colors.xml').existsSync(),
          isTrue,
        );
        expect(
          File('android/app/src/main/res/values-v31/dimens.xml').existsSync(),
          isTrue,
        );
      },
    );

    test(
      'Native Kotlin widgets execute via BroadcastReceiver & Translucent Overlay without root MainActivity traps',
      () {
        final kotlinCode = File(
          'android/app/src/main/kotlin/vn/lifeos/app/life_os/LifeOsHomeWidgets.kt',
        ).readAsStringSync();
        final manifestXml = File(
          'android/app/src/main/AndroidManifest.xml',
        ).readAsStringSync();

        // Uses BroadcastReceiver & Floating Overlay on Home Screen
        expect(kotlinCode, contains('PendingIntent.getBroadcast'));
        expect(kotlinCode, contains('class LifeOsWidgetActionReceiver'));
        expect(kotlinCode, contains('class LifeOsWidgetQuickOverlayActivity'));

        // Never attaches click listeners to root containers that yank user into MainActivity
        expect(kotlinCode.contains('R.id.widget_voice_root'), isFalse);
        expect(kotlinCode.contains('R.id.widget_wealth_root'), isFalse);
        expect(kotlinCode.contains('R.id.widget_group_root'), isFalse);
        expect(kotlinCode.contains('R.id.widget_safe_root'), isFalse);

        // Registered properly in AndroidManifest.xml
        expect(manifestXml, contains('android:name=".LifeOsWidgetActionReceiver"'));
        expect(
          manifestXml,
          contains('android:name=".LifeOsWidgetQuickOverlayActivity"'),
        );
        expect(
          manifestXml,
          contains('android:theme="@style/WidgetFloatingOverlayTheme"'),
        );
      },
    );

    testWidgets(
      'Outside Home-Screen widget actions queue & auto-commit into Firestore + BLoCs with 1-tap Undo',
      (tester) async {
        tester.view.physicalSize = const Size(430, 932);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final mockUser = MockUser(
          isAnonymous: false,
          uid: 'uid_bg_widgets',
          email: 'bgwidget@lifeos.vn',
          displayName: 'Trần Minh',
          isEmailVerified: true,
        );
        final mockAuth = MockFirebaseAuth(mockUser: mockUser, signedIn: true);
        final fakeFirestore = FakeFirebaseFirestore();
        await fakeFirestore.collection('users').doc('uid_bg_widgets').set({
          'id': 'uid_bg_widgets',
          'email': 'bgwidget@lifeos.vn',
          'fullName': 'Trần Minh',
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

        final bridge = sl<NativeHomeWidgetBridge>();

        // 1. Simulate outside Home-Screen 1-tap expense (+Cà phê 35k)
        bridge.simulateHomeScreenWidgetCommand(
          const QueuedHomeWidgetCommand(
            id: 'cmd_coffee_35k',
            kind: 'expense',
            commandText: 'Cà phê 35000đ',
            label: 'Cà phê',
            amountMinor: 35000,
          ),
        );
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 60));
        }
        await tester.pumpAndSettle();

        final txSnapAfterCreate = await fakeFirestore
            .collection('users')
            .doc('uid_bg_widgets')
            .collection('transactions')
            .get();
        final shellCtx = tester.element(
          find.byKey(const Key('lifeos_liquid_glass_bottom_dock')),
        );
        final actState = shellCtx.read<TransactionActionBloc>().state;
        expect(
          txSnapAfterCreate.docs.any(
            (d) =>
                d.data()['merchant'] == 'Cà phê' &&
                d.data()['amountMinor'] == 35000,
          ),
          isTrue,
          reason:
              'Docs: ${txSnapAfterCreate.docs.map((d) => d.data()).toList()}, '
              'ActionStatus: ${actState.status}, Failure: ${actState.failure?.message}',
        );

        // 2. Simulate outside Home-Screen 1-tap Group Split (+Ăn chung 150k / 3 người)
        bridge.simulateHomeScreenWidgetCommand(
          const QueuedHomeWidgetCommand(
            id: 'cmd_split_150k',
            kind: 'group_split',
            commandText: 'Ăn chung 150k chia đều 3 người',
            label: 'Ăn chung',
            amountMinor: 150000,
            memberCount: 3,
          ),
        );
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 60));
        }
        await tester.pumpAndSettle();

        final familiesSnap = await fakeFirestore.collection('families').get();
        expect(familiesSnap.docs, isNotEmpty);

        // 3. Simulate outside Home-Screen 1-tap Undo of Cà phê 35k
        bridge.simulateHomeScreenWidgetCommand(
          const QueuedHomeWidgetCommand(
            id: 'cmd_undo_1',
            kind: 'undo',
            commandText: '',
            targetCommandId: 'cmd_coffee_35k',
          ),
        );
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 60));
        }
        await tester.pumpAndSettle();

        final txSnapAfterUndo = await fakeFirestore
            .collection('users')
            .doc('uid_bg_widgets')
            .collection('transactions')
            .get();
        expect(txSnapAfterUndo.docs.length, greaterThanOrEqualTo(1));
      },
    );

    testWidgets(
      'HomeWidgetsStudioPage renders & operates all 4 Google Material 3 Widgets interactively in-place',
      (tester) async {
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
        expect(
          find.textContaining('THANH TÌM KIẾM & GIỌNG NÓI PIXEL'),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('sync_widgets_now_button')),
          findsOneWidget,
        );

        // Interact with Widget 1 in-place (+Cà phê 35k -> Hoàn tác) without leaving page
        await tester.scrollUntilVisible(
          find.byKey(const Key('studio_voice_chip_35k')),
          180,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('studio_voice_chip_35k')));
        await tester.pumpAndSettle();
        expect(find.textContaining('Đã ghi: Cà phê'), findsOneWidget);
        expect(find.text('4 Widget Chuẩn Google M3'), findsOneWidget);

        await tester.tap(find.byKey(const Key('studio_voice_undo_btn')));
        await tester.pumpAndSettle();
        expect(find.textContaining('Đã hoàn tác: Cà phê'), findsOneWidget);

        // Interact with Widget 2 in-place (Privacy mask + View mode cycle)
        await tester.scrollUntilVisible(
          find.byKey(const Key('studio_wealth_mask_btn')),
          180,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('studio_wealth_mask_btn')));
        await tester.pumpAndSettle();
        expect(find.text('Hiện số'), findsOneWidget);

        await tester.tap(find.byKey(const Key('studio_wealth_mode_btn')));
        await tester.pumpAndSettle();
        expect(find.text('Dư ròng tháng này'), findsOneWidget);

        // Interact with Widget 3 in-place (+1 member -> 4 người)
        await tester.scrollUntilVisible(
          find.byKey(const Key('studio_group_plus_btn')),
          180,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('studio_group_plus_btn')));
        await tester.pumpAndSettle();
        expect(find.text('4 người'), findsOneWidget);

        // Interact with Widget 4 in-place (Switch to Water mode -> +250ml)
        await tester.scrollUntilVisible(
          find.byKey(const Key('studio_safe_mode_toggle_btn')),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('studio_safe_mode_toggle_btn')));
        await tester.pumpAndSettle();
        expect(find.text('Nước uống hôm nay'), findsOneWidget);

        await tester.tap(find.byKey(const Key('studio_safe_action_1_btn')));
        await tester.pumpAndSettle();
        // Still right on HomeWidgetsStudioPage — never pushed away!
        expect(find.text('4 Widget Chuẩn Google M3'), findsOneWidget);
      },
    );
  });
}
