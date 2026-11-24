import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:life_os/app/app.dart';
import 'package:life_os/app/theme/app_colors.dart';
import 'package:life_os/app/theme/app_theme.dart';
import 'package:life_os/app/theme/theme_bloc.dart';
import 'package:life_os/core/constants/app_assets.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:life_os/core/di/dependency_injection.dart';
import 'package:life_os/core/error/app_exception.dart';
import 'package:life_os/core/services/native_device_calendar_bridge.dart';
import 'package:life_os/core/widgets/lifeos_top_toast.dart';
import 'package:life_os/core/widgets/liquid_glass.dart';
import 'package:life_os/core/widgets/pro_max_widgets.dart';
import 'package:life_os/features/authentication/presentation/bloc/auth_bloc.dart';
import 'package:life_os/features/authentication/presentation/bloc/auth_event.dart';
import 'package:life_os/features/calendar/domain/entities/calendar_entities.dart';
import 'package:life_os/features/dashboard/presentation/pages/today_page.dart';
import 'package:life_os/features/family/domain/entities/family_entities.dart';
import 'package:life_os/features/family/domain/repositories/family_repository.dart';
import 'package:life_os/features/transactions/presentation/bloc/transaction_bloc.dart';
import 'package:life_os/features/transactions/presentation/bloc/transaction_event.dart';
import 'package:life_os/features/transactions/presentation/pages/auto_tx_and_report_pages.dart';
import 'package:life_os/features/vehicles/domain/entities/vehicle_entities.dart';
import 'package:life_os/features/vehicles/domain/repositories/vehicle_repository.dart';

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
          'GitHub Releases',
          'Xem trên GitHub',
          'Google OAuth',
          'Sao chép mã EMVCo',
          'Mô phỏng nhận tiền tự động ngay',
          'Kiểm tra thông báo (Không tạo giao dịch thật)',
          'kiểm thử thủ công',
          'Cloud Functions',
          'Liquid Cash',
          'Wealth Vault',
          'Loại bút toán',
          'Bộ nhận diện thương hiệu LifeOS',
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

        // Verify squarer Apple HIG Notification Platter geometry (13px continuous squircle, bright 3D porcelain)
        final glassSurface = tester.widget<LiquidGlassSurface>(bannerFinder);
        expect(glassSurface.borderRadius, LifeOsTopToast.applePlatterRadius);
        expect(glassSurface.borderRadius, lessThanOrEqualTo(14.0));
        expect(glassSurface.accentRimColor, isNull);
        expect(glassSurface.tintColor, const Color(0xFFFFFFFF));

        // Verify lifted Dark Mode palette is comfortable & never pitch-black
        expect(
          TammySemanticColors.dark.background.computeLuminance(),
          greaterThan(0.006),
        );
        expect(
          TammySemanticColors.dark.surface.computeLuminance(),
          greaterThan(0.015),
        );

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
          googleCalendarTokenOverride: ({required interactive}) async => null,
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
        NativeDeviceCalendarBridge.setDriverOverride(
          const _NoOpDeviceCalendarDriver(),
        );
        addTearDown(() {
          NativeDeviceCalendarBridge.setDriverOverride(null);
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
          googleCalendarTokenOverride: ({required interactive}) async => null,
        );

        void expectZeroTruncatedParagraphs(String screenName) {
          final truncated = <String>[];
          for (final element in find.byType(RichText).evaluate()) {
            final renderObj = element.renderObject;
            if (renderObj is RenderParagraph && renderObj.didExceedMaxLines) {
              truncated.add(renderObj.text.toPlainText());
            }
          }
          expect(
            truncated,
            isEmpty,
            reason:
                'Found truncated (...) text on $screenName at 360x800 @ 112%: $truncated',
          );
          expect(tester.takeException(), isNull);
        }

        await tester.pumpWidget(const LifeOsApp());
        await tester.pumpAndSettle();

        // Switch app-wide font scale to Large (112%)
        final scaffoldCtx = tester.element(find.byType(Scaffold).first);
        scaffoldCtx.read<ThemeBloc>().add(const TextScaleChanged(1.12));
        await tester.pumpAndSettle();
        expectZeroTruncatedParagraphs('Hôm nay (TodayPage)');

        // Open Center `+` Quick Sheet and verify zero `...` truncation on Bento cards
        await tester.tap(find.byKey(const Key('lifeos_center_quick_add_fab')));
        await tester.pumpAndSettle();
        expectZeroTruncatedParagraphs('Bảng Thêm nhanh (+)');
        Navigator.of(tester.element(find.text('Thêm nhanh'))).pop();
        await tester.pumpAndSettle();

        // Open All Services 360° Directory and verify crisp labels, zero truncation & zero overflow
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
        expectZeroTruncatedParagraphs('Tất cả Dịch vụ 360°');

        // Pop back to Home and traverse all 4 symmetrical tabs + sub-tabs + pushed Vehicles/Assets hub
        await tester.tap(find.byTooltip('Quay lại'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Tài chính').last);
        await tester.pumpAndSettle();
        expectZeroTruncatedParagraphs('Tài chính — Sổ thu chi');
        await tester.tap(find.byKey(const Key('finance_tools_tab')));
        await tester.pumpAndSettle();
        expectZeroTruncatedParagraphs('Tài chính — Công cụ');

        await tester.tap(find.text('Lịch & Việc').last);
        await tester.pumpAndSettle();
        expectZeroTruncatedParagraphs('Lịch & Việc — Lịch trình');
        await tester.tap(find.byKey(const Key('planning_tools_tab')));
        await tester.pumpAndSettle();
        expectZeroTruncatedParagraphs('Lịch & Việc — Thói quen & Sổ');

        await tester.tap(find.text('Gia đình').last);
        await tester.pumpAndSettle();
        expectZeroTruncatedParagraphs('Gia đình — Tiện ích nhà');

        // Inside Gia đình tab (solo mode), verify clearly separated Vehicles & Living hub opens AssetsPage cleanly
        final vehiclesTile = find.byKey(const Key('family_hub_vehicles_tile'));
        expect(vehiclesTile, findsOneWidget);
        await tester.tap(vehiclesTile);
        await tester.pumpAndSettle();
        expect(find.text('Xe cộ & Hóa đơn'), findsOneWidget);
        expectZeroTruncatedParagraphs('Xe cộ & Hóa đơn');
        await tester.tap(find.byTooltip('Quay lại'));
        await tester.pumpAndSettle();
      },
    );

    test(
      'Strictly ZERO TextOverflow.ellipsis remains anywhere in lib/ UI & presentation files',
      () {
        final dartFiles = Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))
            .toList();

        final offenders = <String>[];
        for (final f in dartFiles) {
          final content = f.readAsStringSync();
          if (content.contains('TextOverflow')) {
            offenders.add(f.path);
          }
        }
        expect(
          offenders,
          isEmpty,
          reason: 'Found TextOverflow truncation in: $offenders',
        );
      },
    );

    testWidgets(
      'Apple Liquid Glass Design System (v3.12): Floating dock refracts with extendBody=true & cards use 120 FPS specular rims across Light & Dark modes',
      (tester) async {
        for (final theme in [AppTheme.light(), AppTheme.dark()]) {
          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              home: Scaffold(
                extendBody: true,
                body: const Center(
                  child: LiquidGlassSurface(
                    key: Key('sample_specular_card'),
                    material: LiquidGlassMaterial.card,
                    padding: EdgeInsets.all(16),
                    child: Text('Thẻ Liquid Glass 120 FPS'),
                  ),
                ),
                bottomNavigationBar: LiquidGlassSurface(
                  key: const Key('sample_floating_dock'),
                  material: LiquidGlassMaterial.floatingDock,
                  borderRadius: 32,
                  child: SizedBox(
                    height: 68,
                    child: Center(
                      child: LiquidGlassJewelButton(
                        tooltip: 'Thêm nhanh',
                        onTap: () {},
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          // Floating dock uses live BackdropFilter refraction:
          expect(
            find.descendant(
              of: find.byKey(const Key('sample_floating_dock')),
              matching: find.byType(BackdropFilter),
            ),
            findsOneWidget,
          );
          // Scrollable card uses GPU specular rim WITHOUT per-card BackdropFilter jank:
          expect(
            find.descendant(
              of: find.byKey(const Key('sample_specular_card')),
              matching: find.byType(BackdropFilter),
            ),
            findsNothing,
          );
          expect(find.byType(LiquidGlassJewelButton), findsOneWidget);
          expect(tester.takeException(), isNull);
        }

        final routerSrc = File('lib/app/app_router.dart').readAsStringSync();
        expect(routerSrc.contains('extendBody: true'), isTrue);
        expect(
          routerSrc.contains("Key('lifeos_liquid_glass_bottom_dock')"),
          isTrue,
        );
      },
    );

    test(
      'Nano Banana Pro 3D Icons & Bank Card Skins (v3.14): All 27 icons (incl. 3D Scooter) + 7 clean bank card skins exist and map accurately',
      () {
        expect(AppAssets.allBananaIcons.length, 27);
        expect(AppAssets.allBankCardSkins.length, 7);

        for (final path in [
          ...AppAssets.allBananaIcons,
          ...AppAssets.allBankCardSkins,
        ]) {
          final file = File(path);
          expect(
            file.existsSync(),
            isTrue,
            reason: 'Missing Nano Banana asset on disk: $path',
          );
          expect(file.lengthSync(), greaterThan(1024));
        }

        expect(
          AppAssets.resolveBankCardSkin(walletTypeKey: 'bank', bankCode: 'VCB'),
          AppAssets.cardVcbEmerald,
        );
        expect(
          AppAssets.resolveBankCardSkin(walletTypeKey: 'bank', bankCode: 'TCB'),
          AppAssets.cardTcbCrimson,
        );
        expect(
          AppAssets.resolveBankCardSkin(walletTypeKey: 'bank', bankCode: 'MBB'),
          AppAssets.cardMbbRoyal,
        );
        expect(
          AppAssets.resolveBankCardSkin(
            walletTypeKey: 'bank',
            bankCode: 'BIDV',
          ),
          AppAssets.cardBidvTeal,
        );
        expect(
          AppAssets.resolveBankCardSkin(walletTypeKey: 'bank', bankCode: 'TPB'),
          AppAssets.cardTpbViolet,
        );
        expect(
          AppAssets.resolveBankCardSkin(walletTypeKey: 'creditCard'),
          AppAssets.cardBlackTitanium,
        );
        expect(
          AppAssets.resolveBankCardSkin(walletTypeKey: 'savings'),
          AppAssets.cardSavingsGold,
        );
        expect(
          AppAssets.resolveBananaIconForGlyph(Icons.qr_code_2_rounded),
          AppAssets.icSysVietQr,
        );
        expect(
          AppAssets.resolveBananaIconForGlyph(Icons.apps_rounded),
          AppAssets.icSysAllServices,
        );
      },
    );

    testWidgets(
      'Invited Members Lifecycle (v3.13): Targeted invite, chat-paste code extraction, preview, join transition, revoke & Vietnamese roles work end-to-end',
      (tester) async {
        tester.view.physicalSize = const Size(430, 932);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final fakeFirestore = FakeFirebaseFirestore();
        const ownerUid = 'uid_owner_minh';
        const inviteeUid = 'uid_invitee_lan';

        await fakeFirestore.collection('users').doc(ownerUid).set({
          'id': ownerUid,
          'email': 'minh@lifeos.vn',
          'fullName': 'Nguyễn Minh',
          'onboardingCompleted': true,
          'availabilityOptIn': false,
        });
        await fakeFirestore.collection('users').doc(inviteeUid).set({
          'id': inviteeUid,
          'email': 'lan@lifeos.vn',
          'fullName': 'Trần Lan',
          'onboardingCompleted': true,
          'availabilityOptIn': false,
        });

        final mockAuth = MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(
            uid: ownerUid,
            email: 'minh@lifeos.vn',
            displayName: 'Nguyễn Minh',
          ),
        );

        await sl.reset();
        await configureDependencies(
          authOverride: mockAuth,
          firestoreOverride: fakeFirestore,
          httpClientOverride: MockClient((_) async => http.Response('{}', 404)),
          googleCalendarTokenOverride: ({required interactive}) async => null,
        );

        final familyRepo = sl<FamilyRepository>();
        final createdFam =
            (await familyRepo.createFamily(
                      userId: ownerUid,
                      userName: 'Nguyễn Minh',
                      familyName: 'Tổ ấm Minh & Lan',
                    )
                    as Success<FamilyEntity>)
                .value;

        // 1. Create a targeted invitation for Trần Lan
        final inviteCode =
            (await familyRepo.createInviteCode(
                      userId: ownerUid,
                      familyId: createdFam.id,
                      familyName: createdFam.name,
                      invitedByName: 'Nguyễn Minh',
                      inviteeName: 'Trần Lan',
                      inviteeContact: 'lan@lifeos.vn',
                    )
                    as Success<String>)
                .value;

        // Verify code extraction from full Zalo/SMS chat text + previewInviteCode
        final pastedZaloText =
            'Chào Trần Lan, mời bạn tham gia nhóm "Tổ ấm Minh & Lan" trên ứng dụng LifeOS. Nhập mã mời: ${inviteCode.toLowerCase()} (hiệu lực 7 ngày).';
        expect(
          FamilyInviteCodeExtractor.extractCode(pastedZaloText),
          inviteCode,
        );

        final previewRes = await familyRepo.previewInviteCode(
          inviteCode: pastedZaloText,
        );
        expect(previewRes, isA<Success<FamilyPendingInviteEntity>>());
        final preview =
            (previewRes as Success<FamilyPendingInviteEntity>).value;
        expect(preview.familyName, 'Tổ ấm Minh & Lan');
        expect(preview.inviteeName, 'Trần Lan');
        expect(preview.invitedByName, 'Nguyễn Minh');

        // 2. Mount app as Owner and verify "Thành viên được mời (1)" & Vietnamese role "Trưởng nhóm"
        await fakeFirestore.collection('users').doc(ownerUid).update({
          'activeFamilyId': createdFam.id,
        });
        await tester.pumpWidget(const LifeOsApp());
        await tester.pumpAndSettle();

        await tester.tap(find.text('Gia đình').last);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('family_members_tab')));
        await tester.pumpAndSettle();

        expect(find.text('Thành viên được mời (1)'), findsOneWidget);
        expect(find.text('Trần Lan'), findsOneWidget);
        expect(find.text('Trưởng nhóm'), findsWidgets);
        // Raw English enum label 'owner' must never appear!
        expect(find.text('owner'), findsNothing);

        // 3. Invitee joins via pasted message -> moves from pending (0) to official members (2)!
        final joinedRes = await familyRepo.joinFamilyByInvite(
          userId: inviteeUid,
          userName: 'Trần Lan',
          inviteCode: pastedZaloText,
        );
        expect(joinedRes, isA<Success<FamilyEntity>>());
        await tester.pumpAndSettle();

        expect(find.text('Thành viên được mời (0)'), findsOneWidget);
        expect(find.text('Thành viên chính thức (2)'), findsOneWidget);
        expect(find.text('Thành viên'), findsWidgets);

        // 4. Create & revoke a second invite -> joining with revoked code is rejected
        final secondCode =
            (await familyRepo.createInviteCode(
                      userId: ownerUid,
                      familyId: createdFam.id,
                      familyName: createdFam.name,
                      invitedByName: 'Nguyễn Minh',
                      inviteeName: 'Phạm Hùng',
                    )
                    as Success<String>)
                .value;
        await tester.pumpAndSettle();
        expect(find.text('Thành viên được mời (1)'), findsOneWidget);

        await tester.tap(find.byKey(Key('revoke_invite_$secondCode')));
        await tester.pumpAndSettle();
        expect(find.text('Thành viên được mời (0)'), findsOneWidget);

        final rejectedJoin = await familyRepo.joinFamilyByInvite(
          userId: 'uid_hung',
          userName: 'Phạm Hùng',
          inviteCode: secondCode,
        );
        expect(rejectedJoin, isA<Err<FamilyEntity>>());

        // 5. Owner promotes Trần Lan to Quản trị (admin)
        final roleRes = await familyRepo.updateMemberRole(
          actorUserId: ownerUid,
          familyId: createdFam.id,
          targetUserId: inviteeUid,
          newRole: HouseholdRole.admin,
        );
        expect(roleRes, isA<Success<void>>());
        await tester.pumpAndSettle();
        expect(find.text('Quản trị'), findsWidgets);
        expect(tester.takeException(), isNull);
      },
    );

    test(
      'OEM Motorcycle Maintenance Spec Catalog (v3.14): Accurate JASO MB vs MA2, ml capacities, coolant rules & EV LFP schedules across 12 lines',
      () {
        expect(MotorcycleSpecCatalog.allProfiles.length, 12);

        // 1. Air-cooled Honda Vision 110: JASO MB, 650-700 ml, NO coolant!
        final vision = MotorcycleSpecCatalog.resolveForVehicle(
          vehicleName: 'Honda Vision 2024',
        );
        expect(vision.profileKey, 'honda_esp_vision_110');
        expect(vision.category, VehicleCategory.scooter);
        expect(vision.oilGradeSpec, contains('JASO MB'));
        expect(vision.engineOilCapacity, contains('650 – 700 ml'));
        expect(vision.gearOilCapacity, isNotNull);
        expect(
          vision.components.any(
            (c) => c.kind == MaintenanceComponentKind.coolant,
          ),
          isFalse,
        );

        // 2. Liquid-cooled Honda Air Blade 160: JASO MB, 800 ml, 120 ml gear oil, HAS coolant
        final ab = MotorcycleSpecCatalog.resolveForVehicle(
          vehicleName: 'Honda Air Blade 160',
        );
        expect(ab.profileKey, 'honda_esp_plus_125_160');
        expect(ab.engineOilCapacity, contains('800 ml'));
        expect(ab.gearOilCapacity, contains('120 ml'));
        expect(
          ab.components.any((c) => c.kind == MaintenanceComponentKind.coolant),
          isTrue,
        );

        // 3. Manual clutch Honda Winner X: 1.100 ml JASO MA2, chain care every 600 km, NO gear oil
        final winner = MotorcycleSpecCatalog.resolveForVehicle(
          vehicleName: 'Honda Winner X V4',
        );
        expect(winner.profileKey, 'honda_winner_x');
        expect(winner.category, VehicleCategory.manualClutch);
        expect(winner.oilGradeSpec, contains('JASO MA2'));
        expect(winner.engineOilCapacity, contains('1.100 ml'));
        expect(winner.gearOilCapacity, isNull);
        expect(
          winner.components.any(
            (c) =>
                c.kind == MaintenanceComponentKind.chainAndSprocket &&
                c.intervalKm == 600,
          ),
          isTrue,
        );

        // 4. Vespa Sprint i-Get: 5W-40 Fully Synthetic, 1.200-1.300 ml + oil filter + 250-270 ml gear oil
        final vespa = MotorcycleSpecCatalog.resolveForVehicle(
          vehicleName: 'Vespa Sprint 125',
        );
        expect(vespa.profileKey, 'piaggio_vespa_iget');
        expect(vespa.oilGradeSpec, contains('5W-40'));
        expect(vespa.engineOilCapacity, contains('1.200 ml'));
        expect(vespa.gearOilCapacity, contains('270 ml'));
        expect(
          vespa.components.any(
            (c) => c.kind == MaintenanceComponentKind.oilFilter,
          ),
          isTrue,
        );

        // 5. VinFast Evo200 Electric: 0 ml oil, LFP battery check every 5,000 km, NO engine oil
        final evo = MotorcycleSpecCatalog.resolveForVehicle(
          vehicleName: 'VinFast Evo200',
        );
        expect(evo.profileKey, 'vinfast_ev_scooter');
        expect(evo.category, VehicleCategory.electricMoto);
        expect(evo.engineOilCapacity, contains('0 ml'));
        expect(
          evo.components.any(
            (c) => c.kind == MaintenanceComponentKind.engineOil,
          ),
          isFalse,
        );
        expect(
          evo.components.any(
            (c) =>
                c.kind == MaintenanceComponentKind.evBatteryAndMotor &&
                c.intervalKm == 5000,
          ),
          isTrue,
        );

        // 6. Motorcycles never require Đăng kiểm; only Car does
        expect(VehicleCategory.scooter.requiresPeriodicInspection, isFalse);
        expect(VehicleCategory.underbone.requiresPeriodicInspection, isFalse);
        expect(
          VehicleCategory.manualClutch.requiresPeriodicInspection,
          isFalse,
        );
        expect(
          VehicleCategory.electricMoto.requiresPeriodicInspection,
          isFalse,
        );
        expect(VehicleCategory.car.requiresPeriodicInspection, isTrue);
        expect(
          AppAssets.resolveBananaIconForGlyph(Icons.two_wheeler_rounded),
          AppAssets.icCatScooter,
        );
      },
    );

    testWidgets(
      'Motorcycle Per-Component ODO Tracking & UI (v3.14): Logging gear oil preserves engine oil countdown, renders OEM specs & zero truncation at 360x800 @ 112%',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1.0;
        tester.platformDispatcher.textScaleFactorTestValue = 1.12;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          tester.platformDispatcher.clearTextScaleFactorTestValue();
        });

        final fakeFirestore = FakeFirebaseFirestore();
        const uid = 'uid_rider_vision';
        await fakeFirestore.collection('users').doc(uid).set({
          'id': uid,
          'email': 'rider@lifeos.vn',
          'fullName': 'Hoàng Nam',
          'onboardingCompleted': true,
          'availabilityOptIn': false,
        });
        await fakeFirestore
            .collection('users')
            .doc(uid)
            .collection('wallets')
            .doc('wallet_main')
            .set({
              'id': 'wallet_main',
              'ownerId': uid,
              'name': 'Ví tiền mặt',
              'type': 'cash',
              'balanceMinor': 2000000,
              'currencyCode': 'VND',
            });

        final mockAuth = MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(
            uid: uid,
            email: 'rider@lifeos.vn',
            displayName: 'Hoàng Nam',
          ),
        );

        await sl.reset();
        await configureDependencies(
          authOverride: mockAuth,
          firestoreOverride: fakeFirestore,
          httpClientOverride: MockClient((_) async => http.Response('{}', 404)),
          googleCalendarTokenOverride: ({required interactive}) async => null,
        );

        final vehRepo = sl<VehicleRepository>();
        final createRes = await vehRepo.createVehicle(
          userId: uid,
          isFamilyShared: false,
          name: 'Honda Vision trắng',
          plateNumber: '59T2-686.86',
          currentOdometerKm: 5800,
          serviceIntervalKm: 2000,
          serviceIntervalDays: 90,
          category: VehicleCategory.scooter,
          modelProfileKey: 'honda_esp_vision_110',
        );
        expect(createRes, isA<Success<void>>());

        final vList =
            (await vehRepo.watchVehicles(userId: uid).first
                    as Success<List<VehicleEntity>>)
                .value;
        expect(vList.length, 1);
        var vision = vList.single;
        expect(vision.isMotorcycle, isTrue);

        // Advance ODO to 7,900 km -> engine oil (5800 + 2000 = 7800) & gear oil (0 + 6000 = 6000) overdue!
        await vehRepo.updateOdometer(vehicle: vision, newOdometerKm: 7900);
        vision =
            (await vehRepo.watchVehicles(userId: uid).first
                    as Success<List<VehicleEntity>>)
                .value
                .single;
        final checklistAt7900 = vision.evaluateComponentChecklist();
        final oilAt7900 = checklistAt7900.firstWhere(
          (c) => c.spec.key == 'engine_oil',
        );
        final gearAt7900 = checklistAt7900.firstWhere(
          (c) => c.spec.key == 'gear_oil',
        );
        final beltAt7900 = checklistAt7900.firstWhere(
          (c) => c.spec.key == 'cvt_belt',
        );
        expect(oilAt7900.dueState, VehicleDueState.overdue);
        expect(gearAt7900.dueState, VehicleDueState.overdue);
        // CVT belt (8000 km interval, remaining 100 km <= 600 warn) -> dueSoon!
        expect(beltAt7900.dueState, VehicleDueState.dueSoon);

        // Log ONLY gear oil at 7,900 km -> gear oil resets to healthy (next 13,900 km),
        // while engine oil MUST remain overdue at lastServiceOdometerKm = 5,800 km!
        await vehRepo.recordMaintenance(
          vehicle: vision,
          serviceTitle: 'Thay nhớt láp 70ml',
          odometerKm: 7900,
          costMinor: 55000,
          componentKey: 'gear_oil',
          walletIdForExpense: 'wallet_main',
        );
        vision =
            (await vehRepo.watchVehicles(userId: uid).first
                    as Success<List<VehicleEntity>>)
                .value
                .single;
        expect(vision.lastServiceOdometerKm, 5800);
        expect(vision.componentLastKm['gear_oil'], 7900);
        expect(
          vision
              .evaluateComponentChecklist()
              .firstWhere((c) => c.spec.key == 'gear_oil')
              .dueState,
          VehicleDueState.healthy,
        );
        expect(
          vision
              .evaluateComponentChecklist()
              .firstWhere((c) => c.spec.key == 'engine_oil')
              .dueState,
          VehicleDueState.overdue,
        );

        // Now log engine oil at 7,950 km -> resets primary engine oil cycle!
        await vehRepo.recordMaintenance(
          vehicle: vision,
          serviceTitle: 'Thay nhớt máy Honda JASO MB 700ml',
          odometerKm: 7950,
          costMinor: 135000,
          componentKey: 'engine_oil',
          walletIdForExpense: 'wallet_main',
        );
        vision =
            (await vehRepo.watchVehicles(userId: uid).first
                    as Success<List<VehicleEntity>>)
                .value
                .single;
        expect(vision.lastServiceOdometerKm, 7950);
        expect(vision.nextDueKm, 9950);

        final hist =
            (await vehRepo.watchMaintenanceHistory(vehicle: vision).first
                    as Success<List<MaintenanceRecordEntity>>)
                .value;
        expect(hist.length, 2);

        // Mount full app -> navigate to Xe cộ & Hóa đơn -> verify OEM specs & zero truncation!
        await tester.pumpWidget(const LifeOsApp());
        await tester.pumpAndSettle();

        await tester.tap(find.text('Gia đình').last);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('family_hub_vehicles_tile')));
        await tester.pumpAndSettle();

        expect(find.text('Honda Vision 110 (eSP)'), findsOneWidget);
        // Motorcycle must NOT show car periodic inspection ("Hạn đăng kiểm định kỳ (Ô tô)"):
        expect(find.text('Hạn đăng kiểm định kỳ (Ô tô)'), findsNothing);

        final truncated = <String>[];
        for (final ro in tester.allRenderObjects) {
          if (ro is RenderParagraph && ro.didExceedMaxLines) {
            truncated.add(ro.text.toPlainText());
          }
        }
        expect(
          truncated,
          isEmpty,
          reason: 'Found truncated text on Motorcycle AssetsPage: $truncated',
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Sliding Bottom Dock (v3.15): Liquid Glass capsule stretches mid-flight on tap & scrubs smoothly under horizontal finger drag',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        var activeIndex = 0;
        var centerJewelTapped = false;
        final visitedDuringDrag = <int>[];

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: StatefulBuilder(
              builder: (context, setHostState) {
                return Scaffold(
                  extendBody: true,
                  body: Center(child: Text('Tab đang chọn: $activeIndex')),
                  bottomNavigationBar: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: LiquidGlassSlidingDock(
                      dockKey: const Key('test_sliding_dock'),
                      selectedIndex: activeIndex,
                      items: [
                        LiquidGlassDockItem(
                          branchIndex: 0,
                          label: 'Hôm nay',
                          iconBuilder: (_, __, c) =>
                              Icon(Icons.home_rounded, color: c, size: 22),
                        ),
                        LiquidGlassDockItem(
                          branchIndex: 1,
                          label: 'Tài chính',
                          iconBuilder: (_, __, c) =>
                              Icon(Icons.bar_chart_rounded, color: c, size: 22),
                        ),
                        LiquidGlassDockItem(
                          branchIndex: 2,
                          label: 'Lịch & Việc',
                          iconBuilder: (_, __, c) => Icon(
                            Icons.calendar_today_rounded,
                            color: c,
                            size: 22,
                          ),
                        ),
                        LiquidGlassDockItem(
                          branchIndex: 3,
                          label: 'Gia đình',
                          iconBuilder: (_, __, c) =>
                              Icon(Icons.groups_rounded, color: c, size: 22),
                        ),
                      ],
                      onDestinationSelected: (idx) {
                        visitedDuringDrag.add(idx);
                        setHostState(() => activeIndex = idx);
                      },
                      centerJewel: LiquidGlassJewelButton(
                        tooltip: 'Thêm nhanh',
                        onTap: () => centerJewelTapped = true,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        final pillFinder = find.byKey(const Key('lifeos_sliding_dock_pill'));
        expect(pillFinder, findsOneWidget);

        // 1. Tap from Tab 0 (Hôm nay) -> Tab 3 (Gia đình) and verify mid-flight droplet stretch!
        final rectAt0 = tester.getRect(pillFinder);
        await tester.tap(find.text('Gia đình'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 180));

        final rectMidFlight = tester.getRect(pillFinder);
        expect(rectMidFlight.left, greaterThan(rectAt0.left + 40));
        expect(
          rectMidFlight.width,
          greaterThan(rectAt0.width + 6),
          reason: 'Liquid Glass capsule should stretch horizontally mid-slide',
        );

        await tester.pumpAndSettle();
        final rectAt3 = tester.getRect(pillFinder);
        expect(rectAt3.left, greaterThan(rectAt0.left + 200));
        expect(activeIndex, 3);

        // 2. Slide finger horizontally from right (Gia đình) across center `+` to left (Hôm nay)
        visitedDuringDrag.clear();
        final startPos = tester.getCenter(find.text('Gia đình'));
        final endPos = tester.getCenter(find.text('Hôm nay'));
        final gesture = await tester.startGesture(startPos);
        await tester.pump();

        const steps = 12;
        for (var i = 1; i <= steps; i++) {
          final pos = Offset.lerp(startPos, endPos, i / steps)!;
          await gesture.moveTo(pos);
          await tester.pump(const Duration(milliseconds: 16));
        }
        await gesture.up();
        await tester.pumpAndSettle();

        expect(visitedDuringDrag, containsAllInOrder([2, 1, 0]));
        expect(activeIndex, 0);
        expect(centerJewelTapped, isFalse);
        final rectBackAt0 = tester.getRect(pillFinder);
        expect((rectBackAt0.left - rectAt0.left).abs(), lessThan(1.5));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Upcoming Schedule Card: Auto-rotates every 6s AND switches instantly on tap across Tuần -> Tháng -> Năm',
      (tester) async {
        final refNow = DateTime(2026, 11, 24, 9, 0);
        final sampleEvents = <CalendarEventEntity>[
          // 1. Event in 2 days -> counted in Week, Month, Year
          CalendarEventEntity(
            id: 'ev_w1',
            ownerId: 'u1',
            ownerName: 'Hòa',
            calendarId: 'primary',
            visibility: CalendarEventVisibility.privateEvent,
            title: 'Họp dự án tuần này',
            startsAt: refNow.add(const Duration(days: 2)),
            endsAt: refNow.add(const Duration(days: 2, hours: 1)),
          ),
          // 2. Event in 18 days -> counted in Month & Year (not Week)
          CalendarEventEntity(
            id: 'ev_m1',
            ownerId: 'u1',
            ownerName: 'Hòa',
            calendarId: 'primary',
            visibility: CalendarEventVisibility.privateEvent,
            title: 'Khám sức khỏe tháng tới',
            startsAt: refNow.add(const Duration(days: 18)),
            endsAt: refNow.add(const Duration(days: 18, hours: 2)),
          ),
          // 3. Event in 120 days -> counted in Year only
          CalendarEventEntity(
            id: 'ev_y1',
            ownerId: 'u1',
            ownerName: 'Hòa',
            calendarId: 'primary',
            visibility: CalendarEventVisibility.sharedEvent,
            title: 'Du lịch gia đình năm tới',
            startsAt: refNow.add(const Duration(days: 120)),
            endsAt: refNow.add(const Duration(days: 120, hours: 4)),
          ),
        ];

        final weekCnt = UpcomingScheduleCycleCard.countUpcomingInWindow(
          sampleEvents,
          refNow,
          const Duration(days: 7),
        );
        final monthCnt = UpcomingScheduleCycleCard.countUpcomingInWindow(
          sampleEvents,
          refNow,
          const Duration(days: 30),
        );
        final yearCnt = UpcomingScheduleCycleCard.countUpcomingInWindow(
          sampleEvents,
          refNow,
          const Duration(days: 365),
        );
        expect(weekCnt, 1);
        expect(monthCnt, 2);
        expect(yearCnt, 3);

        UpcomingScheduleHorizon? longPressedHorizon;

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(360, 800),
                textScaler: TextScaler.linear(1.12),
              ),
              child: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 108,
                    child: UpcomingScheduleCycleCard(
                      cardKey: const Key('upcoming_schedule_cycle_card'),
                      weekCount: weekCnt,
                      monthCount: monthCnt,
                      yearCount: yearCnt,
                      onLongPressOpenPlanning: (h) => longPressedHorizon = h,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Initial state: Tuần (01)
        expect(find.text('Lịch sắp tới'), findsOneWidget);
        expect(find.text('Tuần'), findsOneWidget);
        expect(find.text('01'), findsOneWidget);

        // 1. Auto-rotation after 6s -> Tháng (02)
        await tester.pump(const Duration(seconds: 6));
        await tester.pumpAndSettle();
        expect(find.text('Tháng'), findsOneWidget);
        expect(find.text('02'), findsOneWidget);

        // 2. Auto-rotation after another 6s -> Năm (03)
        await tester.pump(const Duration(seconds: 6));
        await tester.pumpAndSettle();
        expect(find.text('Năm'), findsOneWidget);
        expect(find.text('03'), findsOneWidget);

        // 3. Auto-rotation after another 6s -> loops back to Tuần (01)
        await tester.pump(const Duration(seconds: 6));
        await tester.pumpAndSettle();
        expect(find.text('Tuần'), findsOneWidget);
        expect(find.text('01'), findsOneWidget);

        // 4. Advance 4s (not yet 6s), then TAP card -> switches immediately to Tháng & resets 6s timer!
        await tester.pump(const Duration(seconds: 4));
        await tester.tap(find.byKey(const Key('upcoming_schedule_cycle_card')));
        await tester.pumpAndSettle();
        expect(find.text('Tháng'), findsOneWidget);
        expect(find.text('02'), findsOneWidget);

        // Because timer was reset on tap, advancing 3s must stay on Tháng (not jump at 4+3=7s!)
        await tester.pump(const Duration(seconds: 3));
        await tester.pumpAndSettle();
        expect(find.text('Tháng'), findsOneWidget);

        // Tap again -> Năm (03), tap again -> Tuần (01)
        await tester.tap(find.byKey(const Key('upcoming_schedule_cycle_card')));
        await tester.pumpAndSettle();
        expect(find.text('Năm'), findsOneWidget);
        expect(find.text('03'), findsOneWidget);

        await tester.longPress(
          find.byKey(const Key('upcoming_schedule_cycle_card')),
        );
        await tester.pumpAndSettle();
        expect(longPressedHorizon, UpcomingScheduleHorizon.year);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Interactive ProDonutChart & ProCashflowPulseCard: Tap legend/day updates live KPI readouts with zero overflow at 360x800 @ 112%',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1.0;
        NativeDeviceCalendarBridge.setDriverOverride(
          const _NoOpDeviceCalendarDriver(),
        );
        addTearDown(() {
          NativeDeviceCalendarBridge.setDriverOverride(null);
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(360, 800),
                textScaler: TextScaler.linear(1.12),
              ),
              child: Scaffold(
                body: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const ProDonutChart(
                      totalExpenseMinor: 5000000,
                      slices: [
                        ProDonutSlice(
                          label: 'Ăn uống',
                          amountMinor: 2500000,
                          pct: 50.0,
                          color: Color(0xFF0D9488),
                        ),
                        ProDonutSlice(
                          label: 'Di chuyển',
                          amountMinor: 1500000,
                          pct: 30.0,
                          color: Color(0xFF2563EB),
                        ),
                        ProDonutSlice(
                          label: 'Hóa đơn',
                          amountMinor: 1000000,
                          pct: 20.0,
                          color: Color(0xFF7C3AED),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    ProCashflowPulseCard(
                      dailyIncomesMinor: const [0, 0, 12000000, 0, 0, 0, 500000],
                      dailyExpensesMinor: const [120000, 0, 350000, 85000, 0, 210000, 95000],
                      liquidAssetsMinor: 18500000,
                      savingsAssetsMinor: 45000000,
                      dailySafeToSpendMinor: 420000,
                      financialHealthScore: 86,
                      referenceDate: DateTime(2026, 11, 24),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Default Donut center readout displays total expense ('Tổng chi' & '5.000.000 ₫')
        expect(find.text('Tổng chi'), findsOneWidget);
        expect(find.text('5.000.000 ₫'), findsOneWidget);

        // 2. Tap legend item #1 ('Di chuyển') -> center updates to '1.500.000 ₫' & '30.0% tỷ trọng'
        await tester.tap(find.byKey(const Key('pro_donut_legend_1')));
        await tester.pumpAndSettle();
        expect(find.text('Tổng chi'), findsNothing);
        expect(find.text('1.500.000 ₫'), findsOneWidget);
        expect(find.text('30.0% tỷ trọng'), findsOneWidget);

        // 3. Tap legend item #1 again -> restores 'Tổng chi'
        await tester.tap(find.byKey(const Key('pro_donut_legend_1')));
        await tester.pumpAndSettle();
        expect(find.text('Tổng chi'), findsOneWidget);

        // 4. Tap day #6 (today: 24/11) on ProCashflowPulseCard -> shows exact Thu/Chi pill
        await tester.tap(find.byKey(const Key('pro_cashflow_day_6')));
        await tester.pumpAndSettle();
        expect(find.textContaining('24/11'), findsOneWidget);
        expect(find.textContaining('Thu +500k ₫'), findsOneWidget);
        expect(find.textContaining('Chi -95k ₫'), findsOneWidget);

        final truncated = <String>[];
        for (final ro in tester.allRenderObjects) {
          if (ro is RenderParagraph && ro.didExceedMaxLines) {
            truncated.add(ro.text.toPlainText());
          }
        }
        expect(truncated, isEmpty, reason: 'Unexpected truncated text: $truncated');
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'FinanceReportPage Multi-Period Charts (Tháng · Tuần · Năm): Plots real cross-month data with zero overflow at 360x800 @ 112%',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1.0;
        NativeDeviceCalendarBridge.setDriverOverride(
          const _NoOpDeviceCalendarDriver(),
        );
        addTearDown(() {
          NativeDeviceCalendarBridge.setDriverOverride(null);
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final fakeFirestore = FakeFirebaseFirestore();
        const uid = 'uid_chart_report';
        await fakeFirestore.collection('users').doc(uid).set({
          'id': uid,
          'email': 'chart@lifeos.vn',
          'fullName': 'Minh Châu',
          'onboardingCompleted': true,
        });
        await fakeFirestore
            .collection('users')
            .doc(uid)
            .collection('wallets')
            .doc('wallet_main')
            .set({
              'id': 'wallet_main',
              'ownerId': uid,
              'name': 'Ví chính',
              'type': 'bank',
              'balanceMinor': 20000000,
              'currencyCode': 'VND',
            });

        final txCol = fakeFirestore
            .collection('users')
            .doc(uid)
            .collection('transactions');

        // 1. March 2026 salary (+15M) -> visible in 'Năm' (2026), excluded in 'Tháng' (2026-11) & 'Tuần'
        await txCol.doc('tx_mar_inc').set({
          'id': 'tx_mar_inc',
          'ownerId': uid,
          'walletId': 'wallet_main',
          'categoryName': 'Lương',
          'merchant': 'Công ty ABC',
          'kind': 'income',
          'direction': 'credit',
          'amountMinor': 15000000,
          'verification': 'userConfirmed',
          'sourceKind': 'manual',
          'occurredAt': Timestamp.fromDate(DateTime(2026, 3, 15, 9, 0)),
          'monthKey': '2026-03',
        });

        // 2. Early Nov 2026 utility bill (-1.2M on 05/11) -> visible in 'Tháng' (2026-11) & 'Năm', excluded in 'Tuần' (23/11–29/11)
        await txCol.doc('tx_nov_early').set({
          'id': 'tx_nov_early',
          'ownerId': uid,
          'walletId': 'wallet_main',
          'categoryName': 'Hóa đơn',
          'merchant': 'EVN Điện lực',
          'kind': 'expense',
          'direction': 'debit',
          'amountMinor': 1200000,
          'verification': 'userConfirmed',
          'sourceKind': 'manual',
          'occurredAt': Timestamp.fromDate(DateTime(2026, 11, 5, 14, 0)),
          'monthKey': '2026-11',
        });

        // 3. Current week Tuesday 24/11/2026 dining (-450k) -> visible in 'Tuần', 'Tháng', AND 'Năm'!
        await txCol.doc('tx_nov_week').set({
          'id': 'tx_nov_week',
          'ownerId': uid,
          'walletId': 'wallet_main',
          'categoryName': 'Ăn uống',
          'merchant': 'Phở Thìn',
          'kind': 'expense',
          'direction': 'debit',
          'amountMinor': 450000,
          'verification': 'userConfirmed',
          'sourceKind': 'manual',
          'occurredAt': Timestamp.fromDate(DateTime(2026, 11, 24, 12, 30)),
          'monthKey': '2026-11',
        });

        final mockAuth = MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(
            uid: uid,
            email: 'chart@lifeos.vn',
            displayName: 'Minh Châu',
          ),
        );

        await sl.reset();
        await configureDependencies(
          authOverride: mockAuth,
          firestoreOverride: fakeFirestore,
          httpClientOverride: MockClient((_) async => http.Response('{}', 404)),
          googleCalendarTokenOverride: ({required interactive}) async => null,
        );

        final authBloc = sl<AuthBloc>()..add(const AuthSubscriptionRequested());
        final txListBloc = sl<TransactionListBloc>()
          ..add(
            const TransactionsSubscriptionRequested(
              userId: uid,
              monthKey: '2026-11',
            ),
          );

        await tester.pumpWidget(
          MultiBlocProvider(
            providers: [
              BlocProvider<AuthBloc>.value(value: authBloc),
              BlocProvider<TransactionListBloc>.value(value: txListBloc),
            ],
            child: MaterialApp(
              theme: AppTheme.light(),
              home: MediaQuery(
                data: const MediaQueryData(
                  size: Size(360, 800),
                  textScaler: TextScaler.linear(1.12),
                ),
                child: FinanceReportPage(
                  referenceDate: DateTime(2026, 11, 24, 15, 0),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // A. Default 'Tháng' (2026-11): 2 transactions, total expense 1.650.000 ₫
        expect(find.text('Kỳ báo cáo: 2026-11'), findsOneWidget);
        expect(find.text('2 giao dịch'), findsOneWidget);
        expect(find.text('1.650.000 ₫'), findsAtLeastNWidgets(1));

        // Tap bucket 0 ('01–07') -> inspects Week 1 (-1.2 tr)
        await tester.tap(find.byKey(const Key('report_bucket_label_0')));
        await tester.pumpAndSettle();
        expect(find.textContaining('Tuần 1 (01–07)'), findsOneWidget);
        expect(find.textContaining('Chi -1.2 tr'), findsOneWidget);

        // B. Switch to 'Tuần' (23/11–29/11): 1 transaction (-450.000 ₫)
        await tester.tap(find.text('Tuần'));
        await tester.pumpAndSettle();
        expect(find.text('Kỳ tuần: 23/11–29/11'), findsOneWidget);
        expect(find.text('1 giao dịch'), findsOneWidget);
        expect(find.text('450.000 ₫'), findsAtLeastNWidgets(1));

        // C. Switch to 'Năm' (2026): all 3 transactions (+15.000.000 ₫ Thu, -1.650.000 ₫ Chi, 12 month labels T1..T12)
        await tester.tap(find.text('Năm'));
        await tester.pumpAndSettle();
        expect(find.text('Kỳ năm: 2026'), findsOneWidget);
        expect(find.text('3 giao dịch'), findsOneWidget);
        expect(find.text('Đỉnh: 15 tr'), findsOneWidget);
        expect(find.text('T12'), findsOneWidget);

        await tester.drag(
          find.byKey(const Key('finance_report_list_view')),
          const Offset(0, -360),
        );
        await tester.pumpAndSettle();
        expect(find.text('15.000.000 ₫'), findsOneWidget);
        expect(find.text('+13.350.000 ₫'), findsOneWidget);

        final truncated = <String>[];
        for (final ro in tester.allRenderObjects) {
          if (ro is RenderParagraph && ro.didExceedMaxLines) {
            truncated.add(ro.text.toPlainText());
          }
        }
        expect(
          truncated,
          isEmpty,
          reason: 'Found truncated text on FinanceReportPage: $truncated',
        );
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );

    testWidgets(
      'Redesigned Work Schedule & Tasks (Lịch & Việc): Context-aware header, adaptive Week/Year views, unified events + tasks agenda, and priority task creation with zero overflow at 360x800 @ 112%',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1.0;
        NativeDeviceCalendarBridge.setDriverOverride(
          const _NoOpDeviceCalendarDriver(),
        );
        addTearDown(() {
          NativeDeviceCalendarBridge.setDriverOverride(null);
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final fakeFirestore = FakeFirebaseFirestore();
        const uid = 'uid_planning_ux';
        await fakeFirestore.collection('users').doc(uid).set({
          'id': uid,
          'email': 'work@lifeos.vn',
          'fullName': 'Ngọc Anh',
          'onboardingCompleted': true,
          'availabilityOptIn': false,
        });

        final mockAuth = MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(
            uid: uid,
            email: 'work@lifeos.vn',
            displayName: 'Ngọc Anh',
          ),
        );

        await sl.reset();
        await configureDependencies(
          authOverride: mockAuth,
          firestoreOverride: fakeFirestore,
          httpClientOverride: MockClient((_) async => http.Response('{}', 404)),
          googleCalendarTokenOverride: ({required interactive}) async => null,
        );

        await tester.pumpWidget(const LifeOsApp());
        await tester.pumpAndSettle();

        final scaffoldCtx = tester.element(find.byType(Scaffold).first);
        scaffoldCtx.read<ThemeBloc>().add(const TextScaleChanged(1.12));
        await tester.pumpAndSettle();

        // Navigate to Lịch & Việc tab
        await tester.tap(find.text('Lịch & Việc').last);
        await tester.pumpAndSettle();

        // 1. On Tab 0 ('Lịch trình'), header primary CTA is contextual: 'Thêm lịch'
        expect(find.text('Thêm lịch'), findsOneWidget);
        expect(find.text('Thêm việc'), findsNothing);

        // 2. Create a Calendar Event via progressive-disclosure dialog
        await tester.tap(find.byKey(const Key('open_create_event_button')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('event_title_field')),
          'Họp kế hoạch tuần',
        );
        // Expand optional details to verify location field works cleanly
        await tester.tap(find.byKey(const Key('toggle_event_advanced_options')));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const Key('event_location_field')));
        await tester.enterText(
          find.byKey(const Key('event_location_field')),
          'Phòng họp A2',
        );
        await tester.tap(find.byKey(const Key('submit_event_dialog_button')));
        await tester.pump();
        await tester.pump(const Duration(seconds: 3));
        await tester.pumpAndSettle();

        // Scroll slightly to bring the agenda card into full view on 360x800 @ 112%
        await tester.drag(
          find.byKey(const Key('calendar_events_list_view')),
          const Offset(0, -240),
        );
        await tester.pumpAndSettle();

        // Verify SINGLE unified occurrence in agenda (zero duplicate event list!)
        expect(find.text('Họp kế hoạch tuần'), findsOneWidget);
        expect(find.text('Phòng họp A2'), findsOneWidget);

        // 3. Switch to Tab 1 ('Công việc') -> header CTA switches to 'Thêm việc'
        await tester.tap(find.byKey(const Key('planning_tasks_tab')));
        await tester.pumpAndSettle();
        expect(find.text('Thêm việc'), findsOneWidget);

        // Create a high-priority task due today
        await tester.tap(
          find.byKey(const Key('open_create_task_header_button')),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('create_task_title_field')),
          'Gửi báo cáo tiến độ',
        );
        await tester.tap(find.byKey(const Key('task_priority_high')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('submit_create_task_button')));
        await tester.pumpAndSettle();

        expect(find.text('Gửi báo cáo tiến độ'), findsOneWidget);
        expect(find.text('Quan trọng'), findsOneWidget);

        // Toggle grouped board view ('Nhóm') and back to list ('Danh sách')
        await tester.tap(find.byKey(const Key('task_view_mode_toggle')));
        await tester.pumpAndSettle();
        expect(find.text('Đang thực hiện'), findsOneWidget);
        await tester.tap(find.byKey(const Key('task_view_mode_toggle')));
        await tester.pumpAndSettle();

        // 4. Switch back to Tab 0 ('Lịch trình'): verify unified agenda shows BOTH the event AND today's task!
        await tester.tap(find.byKey(const Key('planning_calendar_tab')));
        await tester.pumpAndSettle();
        expect(find.text('Họp kế hoạch tuần'), findsOneWidget);
        expect(find.text('Gửi báo cáo tiến độ'), findsOneWidget);

        // 5. Switch to 'Tuần' (compact 7-day strip) & 'Năm' (12-month overview -> tap month -> jumps to 'Tháng')
        await tester.tap(find.text('Tuần'));
        await tester.pumpAndSettle();
        expect(find.text('Họp kế hoạch tuần'), findsOneWidget);

        await tester.tap(find.text('Năm'));
        await tester.pumpAndSettle();
        expect(find.text('Thg 12'), findsOneWidget);

        final truncated = <String>[];
        for (final ro in tester.allRenderObjects) {
          if (ro is RenderParagraph && ro.didExceedMaxLines) {
            truncated.add(ro.text.toPlainText());
          }
        }
        expect(
          truncated,
          isEmpty,
          reason: 'Found truncated text on redesigned PlanningPage: $truncated',
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Zero 1-Word-Per-Line Vertical Text Stacking across all core & utility screens at 360x800 @ 112% font scale',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1.0;
        NativeDeviceCalendarBridge.setDriverOverride(
          const _NoOpDeviceCalendarDriver(),
        );
        addTearDown(() {
          NativeDeviceCalendarBridge.setDriverOverride(null);
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final fakeFirestore = FakeFirebaseFirestore();
        const uid = 'uid_no_vertical_stack';
        final now = DateTime.now();
        final currentMk =
            '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';

        await fakeFirestore.collection('users').doc(uid).set({
          'id': uid,
          'email': 'hoa.nguyen@lifeos.vn',
          'fullName': 'Nguyễn Danh Hòa',
          'onboardingCompleted': true,
          'availabilityOptIn': true,
        });
        await fakeFirestore.collection('users').doc('uid_member_2').set({
          'id': 'uid_member_2',
          'email': 'lan.tran@lifeos.vn',
          'fullName': 'Trần Ngọc Lan',
          'onboardingCompleted': true,
          'availabilityOptIn': false,
        });

        await fakeFirestore
            .collection('users')
            .doc(uid)
            .collection('wallets')
            .doc('wallet_vcb')
            .set({
              'id': 'wallet_vcb',
              'ownerId': uid,
              'name': 'Vietcombank Lương',
              'type': 'bank',
              'balanceMinor': 128500000,
              'currencyCode': 'VND',
            });

        final txCol = fakeFirestore
            .collection('users')
            .doc(uid)
            .collection('transactions');
        await txCol.doc('tx_confirmed_1').set({
          'id': 'tx_confirmed_1',
          'ownerId': uid,
          'walletId': 'wallet_vcb',
          'walletName': 'Vietcombank Lương',
          'categoryName': 'Việc nhà & Gia dụng',
          'merchant': 'Bách Hóa Xanh Quận 7',
          'kind': 'expense',
          'direction': 'debit',
          'amountMinor': 1450000,
          'balanceAfterMinor': 127050000,
          'verification': 'userConfirmed',
          'sourceKind': 'manual',
          'occurredAt': Timestamp.fromDate(now),
          'monthKey': currentMk,
        });
        await txCol.doc('tx_provisional_1').set({
          'id': 'tx_provisional_1',
          'ownerId': uid,
          'walletId': 'wallet_vcb',
          'walletName': 'Vietcombank Lương',
          'categoryName': 'Xe cộ & Di chuyển',
          'merchant': 'Cây xăng Petrolimex Số 12',
          'kind': 'expense',
          'direction': 'debit',
          'amountMinor': 85000,
          'verification': 'provisional',
          'sourceKind': 'androidNotification',
          'occurredAt': Timestamp.fromDate(now),
          'monthKey': currentMk,
        });

        final mockAuth = MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(
            uid: uid,
            email: 'hoa.nguyen@lifeos.vn',
            displayName: 'Nguyễn Danh Hòa',
          ),
        );

        await sl.reset();
        await configureDependencies(
          authOverride: mockAuth,
          firestoreOverride: fakeFirestore,
          httpClientOverride: MockClient((_) async => http.Response('{}', 404)),
          googleCalendarTokenOverride: ({required interactive}) async => null,
        );

        final familyRepo = sl<FamilyRepository>();
        final createdFam =
            (await familyRepo.createFamily(
                      userId: uid,
                      userName: 'Nguyễn Danh Hòa',
                      familyName: 'Tổ ấm Gia đình Hòa & Lan',
                    )
                    as Success<FamilyEntity>)
                .value;
        final joinCode =
            (await familyRepo.createInviteCode(
                      userId: uid,
                      familyId: createdFam.id,
                      familyName: createdFam.name,
                      invitedByName: 'Nguyễn Danh Hòa',
                      inviteeName: 'Trần Ngọc Lan',
                    )
                    as Success<String>)
                .value;
        await familyRepo.joinFamilyByInvite(
          userId: 'uid_member_2',
          userName: 'Trần Ngọc Lan',
          inviteCode: joinCode,
        );
        await familyRepo.createInviteCode(
          userId: uid,
          familyId: createdFam.id,
          familyName: createdFam.name,
          invitedByName: 'Nguyễn Danh Hòa',
          inviteeName: 'Phạm Minh Khôi',
          inviteeContact: '0909 888 999',
        );

        await sl<VehicleRepository>().createVehicle(
          userId: uid,
          familyId: createdFam.id,
          isFamilyShared: true,
          name: 'Honda Air Blade 160',
          plateNumber: '59X3-686.86',
          currentOdometerKm: 8450,
          serviceIntervalKm: 2000,
          serviceIntervalDays: 120,
          category: VehicleCategory.scooter,
          modelProfileKey: 'honda_esp_plus_125_160',
        );

        await tester.pumpWidget(const LifeOsApp());
        await tester.pumpAndSettle();

        final rootCtx = tester.element(find.byType(Scaffold).first);
        rootCtx.read<ThemeBloc>().add(const TextScaleChanged(1.12));
        await tester.pumpAndSettle();

        final stackingViolations = <String>[];
        final truncationViolations = <String>[];

        void scanScreen(String screenName) {
          final ex = tester.takeException();
          if (ex != null) {
            stackingViolations.add('[$screenName] Flutter exception: $ex');
          }
          for (final element in find.byType(RichText).evaluate()) {
            final ro = element.renderObject;
            if (ro is! RenderParagraph || !ro.attached || !ro.hasSize) continue;
            final plain = ro.text.toPlainText().trim();
            if (plain.isEmpty) continue;

            if (ro.didExceedMaxLines) {
              truncationViolations.add('[$screenName] "$plain"');
            }

            if (plain.contains('\n')) continue;
            final tp = TextPainter(
              text: ro.text,
              textDirection: ro.textDirection,
              textScaler: ro.textScaler,
              textAlign: ro.textAlign,
            )..layout(maxWidth: ro.size.width + 0.5);
            final lines = tp.computeLineMetrics();
            tp.dispose();
            if (lines.length < 2) continue;

            final words = plain
                .split(RegExp(r'\s+'))
                .where((w) => w.isNotEmpty)
                .toList();
            if (words.length < 2) {
              // A single unbroken word split across multiple lines!
              stackingViolations.add(
                '[$screenName] Single word split across ${lines.length} lines (w=${ro.size.width.toStringAsFixed(1)}): "$plain"',
              );
              continue;
            }

            // 1. Short 2-word Vietnamese labels (<= 9 chars, e.g. 'Sức khỏe', 'Điện nước', 'Thu tháng')
            // must NEVER split into 2 vertical lines of 1 word per line!
            if (words.length == 2 && plain.length <= 9 && lines.length >= 2) {
              stackingViolations.add(
                '[$screenName] Short 2-word label split 1-word-per-line (w=${ro.size.width.toStringAsFixed(1)}, lines=${lines.length}): "$plain"',
              );
              continue;
            }

            // 2. Multi-word phrases wrapping into >= 3 lines with <= 1.15 words/line or crushed width < 66px
            final wordsPerLine = words.length / lines.length;
            if ((lines.length >= 3 && wordsPerLine <= 1.15) ||
                ro.size.width < 66.0) {
              stackingViolations.add(
                '[$screenName] Vertical 1-word-per-line stacking (w=${ro.size.width.toStringAsFixed(1)}, lines=${lines.length}, words=${words.length}): "$plain"',
              );
            }
          }
        }

        // 1. Shell Tab 0: Hôm nay (TodayPage) + scroll bottom
        scanScreen('TodayPage (Top)');
        await tester.drag(find.byType(ListView).first, const Offset(0, -450));
        await tester.pumpAndSettle();
        scanScreen('TodayPage (Bottom)');

        // 2. Shell Tab 1: Tài chính (4 sub-tabs)
        await tester.tap(find.text('Tài chính').last);
        await tester.pumpAndSettle();
        scanScreen('FinancePage: Sổ thu chi (Top)');
        await tester.drag(
          find.byKey(const Key('transactions_list_view')),
          const Offset(0, -520),
        );
        await tester.pumpAndSettle();
        scanScreen('FinancePage: Sổ thu chi (Charts & Categories)');

        await tester.tap(find.text('Ngân sách').first);
        await tester.pumpAndSettle();
        scanScreen('FinancePage: Ngân sách');

        await tester.tap(find.byKey(const Key('finance_analytics_tab')));
        await tester.pumpAndSettle();
        scanScreen('FinancePage: Phân tích');

        await tester.tap(find.byKey(const Key('finance_tools_tab')));
        await tester.pumpAndSettle();
        scanScreen('FinancePage: Công cụ');

        // 3. Shell Tab 2: Lịch & Việc
        await tester.tap(find.text('Lịch & Việc').last);
        await tester.pumpAndSettle();
        scanScreen('PlanningPage: Lịch trình');
        await tester.tap(find.byKey(const Key('planning_tasks_tab')));
        await tester.pumpAndSettle();
        scanScreen('PlanningPage: Công việc');

        // 4. Shell Tab 3: Gia đình (Active family sub-tabs)
        await tester.tap(find.text('Gia đình').last);
        await tester.pumpAndSettle();
        scanScreen('FamilyPage: Chia tiền & Cân đối');
        await tester.tap(find.byKey(const Key('family_assets_life_tab')));
        await tester.pumpAndSettle();
        scanScreen('FamilyPage: Tiện ích nhà');
        await tester.tap(find.byKey(const Key('family_members_tab')));
        await tester.pumpAndSettle();
        scanScreen('FamilyPage: Thành viên & Lời mời');
        await tester.tap(find.byKey(const Key('family_shopping_tab')));
        await tester.pumpAndSettle();
        scanScreen('FamilyPage: Mua sắm');

        // 5. Push every major detail & utility route and scan!
        final routesToScan = <(String route, String label)>[
          ('/super-app-hub', 'SuperAppDirectoryPage'),
          ('/assets', 'AssetsPage (Xe cộ & Hóa đơn)'),
          ('/family-funds', 'FamilyFundsPage'),
          ('/pro-utilities', 'ProUtilitiesHubPage'),
          ('/subscriptions-warranty', 'SubscriptionsWarrantyPage'),
          ('/habits-focus', 'HabitsFocusPage'),
          ('/social-ledger-travel', 'SocialLedgerTravelPage'),
          ('/wealth-tools', 'WealthToolsPage'),
          ('/health-hub', 'HealthMedicalHubPage'),
          ('/health-hub?tab=water', 'HealthMedicalHubPage (Uống nước)'),
          ('/kitchen-groceries', 'KitchenGroceriesPage'),
          ('/home-living', 'HomeLivingUtilitiesPage'),
          ('/smart-notes-hub', 'SmartNotesSalaryPage'),
          ('/home-widgets', 'HomeWidgetsStudioPage'),
          ('/notifications-privacy', 'NotificationsPrivacyPage'),
          ('/auto-tx-review', 'AutoTxReviewPage'),
          ('/finance-report', 'FinanceReportPage'),
          ('/financial-ai', 'FinancialAiAssistantPage'),
          ('/financial-ai-settings', 'FinancialAiSettingsPage'),
          ('/settings-hub', 'SettingsHubPage'),
        ];

        for (final (route, label) in routesToScan) {
          final navCtx = tester.element(find.byType(Scaffold).first);
          GoRouter.of(navCtx).push(route);
          await tester.pumpAndSettle();
          scanScreen(label);

          final afterCtx = tester.element(find.byType(Scaffold).last);
          if (GoRouter.of(afterCtx).canPop()) {
            GoRouter.of(afterCtx).pop();
            await tester.pumpAndSettle();
          }
        }

        expect(
          truncationViolations,
          isEmpty,
          reason: 'Found truncated text: ${truncationViolations.join('\n')}',
        );
        expect(
          stackingViolations,
          isEmpty,
          reason:
              'Found vertical 1-word-per-line stacking:\n${stackingViolations.join('\n')}',
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  });
}

class _NoOpDeviceCalendarDriver implements DeviceCalendarDriver {
  const _NoOpDeviceCalendarDriver();

  @override
  bool get isSupportedPlatform => false;

  @override
  Future<bool> hasPermission() async => false;

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<List<DeviceCalendarInfo>> listCalendars() async =>
      const <DeviceCalendarInfo>[];

  @override
  Future<List<DeviceCalendarEventItem>> listEvents({
    required DateTime windowStart,
    required DateTime windowEnd,
  }) async => const <DeviceCalendarEventItem>[];

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
