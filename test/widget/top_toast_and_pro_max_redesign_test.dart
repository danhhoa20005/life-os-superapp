import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:life_os/app/app.dart';
import 'package:life_os/app/theme/app_theme.dart';
import 'package:life_os/app/theme/theme_bloc.dart';
import 'package:life_os/core/constants/app_assets.dart';
import 'package:life_os/core/di/dependency_injection.dart';
import 'package:life_os/core/error/app_exception.dart';
import 'package:life_os/core/widgets/lifeos_top_toast.dart';
import 'package:life_os/core/widgets/liquid_glass.dart';
import 'package:life_os/features/family/domain/entities/family_entities.dart';
import 'package:life_os/features/family/domain/repositories/family_repository.dart';

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
      'Nano Banana Pro 3D Icons & Bank Card Skins (v3.13): All 26 icons + 7 clean bank card skins exist and map accurately',
      () {
        expect(AppAssets.allBananaIcons.length, 26);
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
  });
}
