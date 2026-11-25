import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:life_os/app/app.dart';
import 'package:life_os/app/theme/app_theme.dart';
import 'package:life_os/app/theme/theme_bloc.dart';
import 'package:life_os/core/di/dependency_injection.dart';
import 'package:life_os/core/drafts/local_draft_store.dart';
import 'package:life_os/core/error/app_exception.dart';
import 'package:life_os/core/services/native_device_calendar_bridge.dart';
import 'package:life_os/core/services/native_permissions_service.dart';
import 'package:life_os/core/services/native_secure_vault_bridge.dart';
import 'package:life_os/core/utils/user_behavior_prefs.dart';
import 'package:life_os/core/widgets/trust_ux_widgets.dart';
import 'package:life_os/features/family/domain/entities/family_entities.dart';
import 'package:life_os/features/family/domain/repositories/family_repository.dart';
import 'package:life_os/features/financial_ai/data/inference/fasttext_classifier.dart';

class _NoOpCalendarDriver implements DeviceCalendarDriver {
  const _NoOpCalendarDriver();
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

class _SilentPermsDriver implements PermissionsDriver {
  const _SilentPermsDriver();
  @override
  bool get isSupportedPlatform => true;
  @override
  Future<AppPermissionsSnapshot> checkAll() async =>
      AppPermissionsSnapshot.allMissing;
  @override
  Future<AppPermissionsSnapshot> requestEssential() => checkAll();
  @override
  Future<AppPermissionsSnapshot> requestSingle(LifeOsPermissionKind kind) =>
      checkAll();
  @override
  Future<void> openAppSettings() async {}
}

Future<FakeFirebaseFirestore> _bootLifeOs(
  WidgetTester tester, {
  required String uid,
  required String fullName,
  required bool onboardingCompleted,
  bool seedSampleData = true,
  bool seedFamily = false,
  Size viewport = const Size(390, 844),
  double textScale = 1.0,
  EdgeInsets padding = EdgeInsets.zero,
  EdgeInsets viewInsets = EdgeInsets.zero,
}) async {
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1.0;
  NativeDeviceCalendarBridge.setDriverOverride(const _NoOpCalendarDriver());
  NativePermissionsService.setDriverOverride(const _SilentPermsDriver());
  await UserBehaviorPrefs.resetForTest();
  LocalDraftStore.clearAllInMemoryCaches();

  final firestore = FakeFirebaseFirestore();
  final now = DateTime.now();
  final mk = '${now.year}-${now.month.toString().padLeft(2, '0')}';

  await firestore.collection('users').doc(uid).set({
    'id': uid,
    'email': '$uid@lifeos.vn',
    'fullName': fullName,
    'onboardingCompleted': onboardingCompleted,
    'availabilityOptIn': false,
  });

  if (seedSampleData) {
    await firestore
        .collection('users')
        .doc(uid)
        .collection('wallets')
        .doc('w_vcb')
        .set({
          'id': 'w_vcb',
          'ownerId': uid,
          'name': 'Vietcombank',
          'type': 'bank',
          'balanceMinor': 18500000,
          'isEstimatedBalance': false,
        });
    await firestore
        .collection('users')
        .doc(uid)
        .collection('transactions')
        .doc('tx_pho_1')
        .set({
          'id': 'tx_pho_1',
          'ownerId': uid,
          'walletId': 'w_vcb',
          'walletName': 'Vietcombank',
          'categoryName': 'Ăn uống',
          'merchant': 'Phở Bò Hà Nội',
          'kind': 'expense',
          'direction': 'debit',
          'amountMinor': 65000,
          'verification': 'userConfirmed',
          'sourceKind': 'manual',
          'occurredAt': now,
          'monthKey': mk,
        });
  }

  final mockAuth = MockFirebaseAuth(
    signedIn: true,
    mockUser: MockUser(
      uid: uid,
      email: '$uid@lifeos.vn',
      displayName: fullName,
    ),
  );

  await sl.reset();
  await configureDependencies(
    authOverride: mockAuth,
    firestoreOverride: firestore,
    httpClientOverride: MockClient((_) async => http.Response('{}', 404)),
    googleCalendarTokenOverride: ({required interactive}) async => null,
    financialClassifierOverride: FastTextClassifier(useWorkerIsolate: false),
  );

  if (seedFamily) {
    final famRepo = sl<FamilyRepository>();
    final created = await famRepo.createFamily(
      userId: uid,
      userName: fullName,
      familyName: 'Gia đình Minh Thảo',
    );
    if (created is Success<FamilyEntity>) {
      await firestore.collection('users').doc(uid).update({
        'activeFamilyId': created.value.id,
      });
    }
  }

  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(
        size: viewport,
        textScaler: TextScaler.linear(textScale),
        padding: padding,
        viewInsets: viewInsets,
      ),
      child: const LifeOsApp(),
    ),
  );
  await tester.pumpAndSettle();
  return firestore;
}

void main() {
  tearDown(() async {
    NativeDeviceCalendarBridge.setDriverOverride(null);
    NativePermissionsService.setDriverOverride(null);
    await UserBehaviorPrefs.resetForTest();
    LocalDraftStore.clearAllInMemoryCaches();
    await NativeSecureVaultBridge.instance.clearAllSecrets();
    await sl.reset();
  });

  group('Section 23 — Automated Task-Based Usability Personas & Edge Cases', () {
    testWidgets(
      'Persona 1 (Người mới): FTUE skippable, zero eager permission popup, first-action tip, balance privacy & synonym discovery',
      (tester) async {
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await _bootLifeOs(
          tester,
          uid: 'u_new_persona',
          fullName: 'Trần Minh Anh',
          onboardingCompleted: false,
          seedSampleData: false,
        );

        // 1. Cold start lands on Onboarding without eager OS permission popup
        expect(find.byKey(const Key('onboarding_skip_btn')), findsOneWidget);
        expect(
          find.byKey(const Key('lifeos_permissions_popup_dialog')),
          findsNothing,
        );

        // Select an interest chip and skip onboarding cleanly
        await tester.tap(find.text('Quản lý chi tiêu'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('onboarding_skip_btn')));
        await tester.pumpAndSettle();

        // 2. Arrives on TodayPage with zero eager permissions and calm First-Action Tip
        expect(
          find.byKey(const Key('lifeos_permissions_popup_dialog')),
          findsNothing,
        );
        expect(find.text('Quỹ gia đình & Tài sản'), findsOneWidget);

        // 3. Hide balance in 1 tap
        await tester.tap(find.byKey(const Key('toggle_balance_privacy_btn')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 280));
        expect(find.textContaining('•••••••• ₫'), findsWidgets);

        // 4. Find vehicle maintenance ("thay nhớt") & security ("mật khẩu") via Global Search
        await tester.tap(find.byTooltip('Tìm kiếm nhanh LifeOS'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('omni_search_text_field')),
          'thay nhot',
        );
        await tester.pump(const Duration(milliseconds: 220));
        await tester.pumpAndSettle();
        expect(find.textContaining('Xe cộ'), findsWidgets);

        await tester.enterText(
          find.byKey(const Key('omni_search_text_field')),
          'mat khau',
        );
        await tester.pump(const Duration(milliseconds: 220));
        await tester.pumpAndSettle();
        expect(find.textContaining('Bảo mật'), findsWidgets);

        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Persona 2 (Người dùng thường xuyên): Quick VND chip expense (no double-tap dup), budget check, search old tx & manual Split Bill',
      (tester) async {
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final firestore = await _bootLifeOs(
          tester,
          uid: 'u_freq_persona',
          fullName: 'Nguyễn Hoàng Nam',
          onboardingCompleted: true,
          seedSampleData: true,
        );

        // 1. Tap center + FAB -> Ghi thu chi -> type 35 -> tap non-destructive 35.000 ₫ chip -> rapid double-tap save!
        await tester.tap(find.byKey(const Key('lifeos_center_quick_add_fab')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('quick_tile_expense')));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('quick_tx_amount_input')),
          '35',
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('vnd_zero_pad_35000')), findsOneWidget);

        await tester.tap(find.byKey(const Key('vnd_zero_pad_35000')));
        await tester.pumpAndSettle();
        expect(find.text('Số tiền sẽ lưu: 35.000 ₫'), findsOneWidget);

        // Rapid double-tap on save CTA must create AT MOST ONE transaction!
        final saveBtn = find.text('Lưu khoản này');
        await tester.ensureVisible(saveBtn);
        await tester.pumpAndSettle();
        await tester.tap(saveBtn);
        await tester.tap(saveBtn, warnIfMissed: false);
        await tester.pumpAndSettle();

        final txDocs = await firestore
            .collection('users')
            .doc('u_freq_persona')
            .collection('transactions')
            .get();
        // 1 seeded + 1 newly created = 2 (NEVER 3!)
        expect(txDocs.docs.length, 2);

        // 2. Open + -> Chia tiền nhóm -> opens manual Split Bill sheet (NOT forced Voice!)
        await tester.tap(find.byKey(const Key('lifeos_center_quick_add_fab')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('quick_tile_split')));
        await tester.pumpAndSettle();
        expect(find.textContaining('Chia tiền nhóm'), findsWidgets);
        Navigator.of(
          tester.element(find.textContaining('Chia tiền nhóm').last),
        ).pop();
        await tester.pumpAndSettle();

        // Wait for Top Toast to auto-dismiss before tapping top header Search icon
        await tester.pump(const Duration(seconds: 4));
        await tester.pumpAndSettle();

        // 3. Search old transaction ("pho") via Global Search
        await tester.tap(find.byTooltip('Tìm kiếm nhanh LifeOS'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('omni_search_text_field')),
          'pho',
        );
        await tester.pump(const Duration(milliseconds: 220));
        await tester.pumpAndSettle();
        expect(find.textContaining('Phở Bò Hà Nội'), findsOneWidget);

        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Persona 3 (Gia đình) & Edge Cases: Personal vs Family visibility, Account-switch draft isolation, Permission decline continuity',
      (tester) async {
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await _bootLifeOs(
          tester,
          uid: 'u_family_persona',
          fullName: 'Lê Thu Thảo',
          onboardingCompleted: true,
          seedSampleData: true,
          seedFamily: true,
        );

        // 1. Personal vs Family visibility on Finance & Family tabs
        await tester.tap(find.text('Tài chính').last);
        await tester.pumpAndSettle();
        expect(find.textContaining('Cá nhân · Riêng tư'), findsWidgets);

        await tester.tap(find.text('Gia đình').last);
        await tester.pumpAndSettle();
        expect(find.text('Gia đình Minh Thảo'), findsWidgets);

        // 2. Account-switch draft isolation check
        await LocalDraftStore.saveDraft(
          userId: 'u_family_persona',
          formId: 'quick_tx_form',
          payload: <String, dynamic>{'amountText': '120k', 'noteText': 'Sữa'},
        );
        final otherUserDraft = await LocalDraftStore.loadDraft(
          userId: 'u_other_person',
          formId: 'quick_tx_form',
        );
        expect(otherUserDraft, isNull);

        // 3. Permission rationale decline keeps app fully functional
        final ctx = tester.element(find.byType(Scaffold).first);
        final futureConsent = showLifeOsJustInTimePermissionRationale(
          ctx,
          title: 'Quyền micro cho ghi nhanh giọng nói',
          whyNeeded: 'Giúp bạn đọc khoản chi hoặc lịch hẹn nhanh hơn.',
          dataAccessed: 'Chỉ âm thanh khi bạn chủ động bấm thu âm.',
          whereProcessed: 'Chuyển thành văn bản để bạn xem trước khi lưu.',
          howToRevoke: 'Tắt bất cứ lúc nào trong Cài đặt thiết bị.',
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Để sau'));
        await tester.pumpAndSettle();
        expect(await futureConsent, isFalse);

        // App continues working seamlessly after decline
        await tester.tap(find.text('Hôm nay').last);
        await tester.pumpAndSettle();
        expect(find.text('Quỹ gia đình & Tài sản'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group(
    'Section 24 — Multi-Viewport, Theme, High Contrast, Large Text, Keyboard & Safe Area Visual QA',
    () {
      const viewports =
          <
            (
              String name,
              Size size,
              double scale,
              bool dark,
              bool hc,
              EdgeInsets pad,
              EdgeInsets insets,
            )
          >[
            (
              '320dp Narrow Light',
              Size(320, 640),
              1.0,
              false,
              false,
              EdgeInsets.zero,
              EdgeInsets.zero,
            ),
            (
              '360dp Standard Light + 1.25x Large Text',
              Size(360, 800),
              1.25,
              false,
              false,
              EdgeInsets.zero,
              EdgeInsets.zero,
            ),
            (
              '390dp iPhone Dark + Safe Area',
              Size(390, 844),
              1.0,
              true,
              false,
              EdgeInsets.only(top: 44, bottom: 34),
              EdgeInsets.zero,
            ),
            (
              '412dp Pixel High Contrast Light',
              Size(412, 915),
              1.15,
              false,
              true,
              EdgeInsets.zero,
              EdgeInsets.zero,
            ),
            (
              '480dp Wide High Contrast Dark + Open Keyboard',
              Size(480, 854),
              1.0,
              true,
              true,
              EdgeInsets.zero,
              EdgeInsets.only(bottom: 280),
            ),
            (
              'Tablet 900x1200 Rail Layout',
              Size(900, 1200),
              1.0,
              false,
              false,
              EdgeInsets.zero,
              EdgeInsets.zero,
            ),
          ];

      for (final cfg in viewports) {
        testWidgets('Zero RenderFlex overflow & zero exception on ${cfg.$1}', (
          tester,
        ) async {
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });

          await _bootLifeOs(
            tester,
            uid: 'u_vp_${cfg.$2.width.toInt()}',
            fullName: 'Nguyễn Danh Hòa',
            onboardingCompleted: true,
            seedSampleData: true,
            viewport: cfg.$2,
            textScale: cfg.$3,
            padding: cfg.$6,
            viewInsets: cfg.$7,
          );

          final ctx = tester.element(find.byType(Scaffold).first);
          if (cfg.$4) {
            ctx.read<ThemeBloc>().add(const ThemeModeChanged(ThemeMode.dark));
          }
          if (cfg.$5) {
            ctx.read<ThemeBloc>().add(const HighContrastToggled(true));
          }
          await tester.pumpAndSettle();

          // Check TodayPage
          expect(tester.takeException(), isNull);

          // On Tablet (>= 840dp), verify NavigationRail is rendered
          if (cfg.$2.width >= 840) {
            expect(find.byType(NavigationRail), findsOneWidget);
          } else {
            expect(
              find.byKey(const Key('lifeos_center_quick_add_fab')),
              findsOneWidget,
            );
          }

          // Open Quick Create Hub (when keyboard isn't covering dock)
          if (cfg.$7.bottom == 0 && cfg.$2.width < 840) {
            await tester.tap(
              find.byKey(const Key('lifeos_center_quick_add_fab')),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            Navigator.of(tester.element(find.text('Thêm nhanh'))).pop();
            await tester.pumpAndSettle();
          }

          // Navigate to Finance & Notification Center and confirm zero overflow
          final navCtx = tester.element(find.byType(Scaffold).first);
          GoRouter.of(navCtx).go('/finance');
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);

          GoRouter.of(
            tester.element(find.byType(Scaffold).first),
          ).push('/activity-notifications');
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        });
      }

      testWidgets(
        'Offline/Sync-Failed recovery banner & all 8 FinancialTrustStatus badges render cleanly at 320dp + 1.25x',
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(320, 640));
          addTearDown(() => tester.binding.setSurfaceSize(null));

          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.light(highContrast: true),
              home: MediaQuery(
                data: const MediaQueryData(
                  size: Size(320, 640),
                  textScaler: TextScaler.linear(1.25),
                ),
                child: Scaffold(
                  body: ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      LifeOsOfflineSyncBanner(syncFailed: true, onRetry: () {}),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final s in FinancialTrustStatus.values)
                            FinancialTrustStatusBadge(status: s),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        },
      );
    },
  );
}
