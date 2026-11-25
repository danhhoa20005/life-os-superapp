import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:life_os/app/app.dart';
import 'package:life_os/app/theme/theme_bloc.dart';
import 'package:life_os/core/constants/app_assets.dart';
import 'package:life_os/core/di/dependency_injection.dart';
import 'package:life_os/core/services/native_device_calendar_bridge.dart';
import 'package:life_os/core/widgets/pro_max_widgets.dart';
import 'package:life_os/features/financial_ai/data/inference/fasttext_classifier.dart';

class _NoOpCalDriver implements DeviceCalendarDriver {
  const _NoOpCalDriver();

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
    NativeDeviceCalendarBridge.setDriverOverride(const _NoOpCalDriver());
  });

  tearDown(() async {
    NativeDeviceCalendarBridge.setDriverOverride(null);
    await sl.reset();
  });

  group('1. Nano Banana Pro 3D Asset Integrity & Glyph Mapping', () {
    test('Every registered 3D icon, bank card skin & 3D hero asset exists on disk and is non-empty', () {
      final allPaths = <String>[
        ...AppAssets.allBananaIcons,
        ...AppAssets.allBankCardSkins,
        AppAssets.hero3dWealthVault,
        AppAssets.hero3dWelcomeEcosystem,
        AppAssets.icMotionPhysics3d,
      ];
      expect(AppAssets.allBananaIcons.length, greaterThanOrEqualTo(32));

      for (final assetPath in allPaths) {
        final file = File(assetPath);
        expect(
          file.existsSync(),
          isTrue,
          reason: 'Missing 3D asset on disk: $assetPath',
        );
        expect(
          file.lengthSync(),
          greaterThan(1024),
          reason: 'Corrupt/empty 3D asset: $assetPath',
        );
      }
    });

    test('resolveBananaIconForGlyph maps all core, AI, alarm, appearance & navigation glyphs to 3D icons', () {
      expect(
        AppAssets.resolveBananaIconForGlyph(Icons.home_rounded),
        AppAssets.icNavToday,
      );
      expect(
        AppAssets.resolveBananaIconForGlyph(
          Icons.account_balance_wallet_rounded,
        ),
        AppAssets.icNavFinance,
      );
      expect(
        AppAssets.resolveBananaIconForGlyph(Icons.menu_rounded),
        AppAssets.icSysAllServices,
      );
      expect(
        AppAssets.resolveBananaIconForGlyph(Icons.auto_awesome_rounded),
        AppAssets.ic3dAiSpark,
      );
      expect(
        AppAssets.resolveBananaIconForGlyph(
          Icons.notifications_active_outlined,
        ),
        AppAssets.ic3dAlarmBell,
      );
      expect(
        AppAssets.resolveBananaIconForGlyph(Icons.palette_outlined),
        AppAssets.ic3dAppearanceStudio,
      );
      expect(
        AppAssets.resolveBananaIconForGlyph(Icons.auto_awesome_motion_rounded),
        AppAssets.icMotionPhysics3d,
      );
    });
  });

  group('2. 3D UI Surface & 3D Icon Rendering Across Shell, Home, Finance & Menu', () {
    testWidgets(
      'Renders 3D BananaGlassIcon across 5-tab bottom bar, Today 3D Emerald Vault Hero, Finance categories, and Menu grid with zero overflow at 360x800 @ 112%',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(360, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final firestore = FakeFirebaseFirestore();
        const uid = 'u_3d_verify';
        await firestore.collection('users').doc(uid).set({
          'email': '3d@lifeos.vn',
          'fullName': 'Bảo Châu',
          'onboardingCompleted': true,
        });
        await firestore
            .collection('users')
            .doc(uid)
            .collection('wallets')
            .doc('w1')
            .set({
              'id': 'w1',
              'ownerId': uid,
              'name': 'Vietcombank',
              'type': 'bank',
              'bankCode': 'VCB',
              'balanceMinor': 15000000,
              'currencyCode': 'VND',
            });
        await firestore
            .collection('users')
            .doc(uid)
            .collection('transactions')
            .doc('tx1')
            .set({
              'id': 'tx1',
              'userId': uid,
              'walletId': 'w1',
              'walletName': 'Vietcombank',
              'categoryId': 'cat_food',
              'categoryName': 'Ăn uống & Cafe',
              'kind': 'expense',
              'direction': 'debit',
              'amountMinor': 65000,
              'merchant': 'Phở Thìn',
              'verification': 'confirmed',
              'occurredAt': DateTime.now().toIso8601String(),
              'monthKey':
                  '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, "0")}',
            });

        final auth = MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(
            uid: uid,
            email: '3d@lifeos.vn',
            displayName: 'Bảo Châu',
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

        // TodayPage + 5-Tab Bottom Bar must display abundant 3D BananaGlassIcons & ProHeroGradientCard
        expect(find.byType(ProHeroGradientCard), findsWidgets);
        expect(
          find.byType(BananaGlassIcon),
          findsAtLeastNWidgets(10),
        );
        expect(tester.takeException(), isNull);

        // Navigate to Finance tab -> wallet skin + scroll to 2D category badge (`BananaGlassIcon`)
        // (4 symmetrical bottom-bar 2D tab icons + center `+` button + category badge = >= 5)
        await tester.tap(find.text('Tài chính'));
        await tester.pumpAndSettle();
        expect(find.byType(ProWalletCreditCard), findsWidgets);
        await tester.drag(find.byType(ListView).first, const Offset(0, -280));
        await tester.pumpAndSettle();
        expect(find.text('Phở Thìn'), findsOneWidget);
        expect(find.byType(BananaGlassIcon), findsAtLeastNWidgets(5));
        expect(
          find.byKey(const Key('lifeos_center_quick_add_fab')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);

        // Navigate to Menu directory via top Menu button -> all 21 service items render 2D icons cleanly
        await tester.tap(find.byKey(const Key('open_menu_directory_button')));
        await tester.pumpAndSettle();
        expect(find.byType(BananaGlassIcon), findsAtLeastNWidgets(10));
        expect(tester.takeException(), isNull);
      },
    );
  });
}
