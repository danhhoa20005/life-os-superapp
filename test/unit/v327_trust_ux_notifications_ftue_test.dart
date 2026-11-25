import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:life_os/app/app.dart';
import 'package:life_os/app/theme/app_colors.dart';
import 'package:life_os/app/theme/app_spacing.dart';
import 'package:life_os/app/theme/app_theme.dart';
import 'package:life_os/app/theme/app_typography.dart';
import 'package:life_os/app/theme/theme_bloc.dart';
import 'package:life_os/core/di/dependency_injection.dart';
import 'package:life_os/core/services/fcm_banking_messaging_service.dart';
import 'package:life_os/core/services/native_permissions_service.dart';
import 'package:life_os/core/services/native_secure_vault_bridge.dart';
import 'package:life_os/core/utils/user_behavior_prefs.dart';
import 'package:life_os/core/widgets/lifeos_design_system.dart';
import 'package:life_os/core/widgets/pro_max_widgets.dart';
import 'package:life_os/core/widgets/status_widgets.dart';
import 'package:life_os/core/widgets/trust_ux_widgets.dart';
import 'package:life_os/features/authentication/presentation/pages/auth_pages.dart';
import 'package:life_os/features/financial_ai/data/inference/fasttext_classifier.dart';
import 'package:life_os/features/notifications/domain/repositories/notifications_repository.dart';
import 'package:life_os/features/notifications/domain/services/smart_inbox_engine.dart';
import 'package:life_os/features/notifications/presentation/bloc/notification_ingestion_bloc.dart';

double _contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = math.max(la, lb);
  final darker = math.min(la, lb);
  return (lighter + 0.05) / (darker + 0.05);
}

class _TrackingFcmDriver implements FcmPlatformDriver {
  int requestCalls = 0;
  bool permissionGranted = true;
  final _registeredCtrl = StreamController<String>.broadcast();
  final _fgCtrl = StreamController<IncomingBankingPushPayload>.broadcast();
  final _openedCtrl = StreamController<IncomingBankingPushPayload>.broadcast();

  @override
  Future<bool> requestPushPermission() async {
    requestCalls++;
    return permissionGranted;
  }

  @override
  Future<void> registerDevice() async {
    _registeredCtrl.add('test_token_1');
  }

  @override
  Future<void> unregisterDevice() async {}

  @override
  Stream<String> get onRegistered => _registeredCtrl.stream;

  @override
  Stream<IncomingBankingPushPayload> get onForegroundMessage => _fgCtrl.stream;

  @override
  Stream<IncomingBankingPushPayload> get onMessageOpenedApp =>
      _openedCtrl.stream;

  @override
  Future<IncomingBankingPushPayload?> getInitialTerminatedMessage() async =>
      null;

  Future<void> dispose() async {
    await _registeredCtrl.close();
    await _fgCtrl.close();
    await _openedCtrl.close();
  }
}

void main() {
  tearDown(() async {
    NativePermissionsService.setDriverOverride(null);
    await NativeSecureVaultBridge.instance.deleteSecret(
      'ux_onboarding_skipped_v1__u_u_ftue_test',
    );
    await NativeSecureVaultBridge.instance.deleteSecret(
      'ux_user_interests_v1__u_u_ftue_test',
    );
    await UserBehaviorPrefs.resetForTest();
    await sl.reset();
  });

  group('Design System 2.0, Contrast & Accessibility Tokens', () {
    test('AppSpacing scale includes xl2=40 & 48dp hit targets', () {
      expect(AppSpacing.xxs, 4.0);
      expect(AppSpacing.xs, 8.0);
      expect(AppSpacing.sm, 12.0);
      expect(AppSpacing.md, 16.0);
      expect(AppSpacing.lg, 20.0);
      expect(AppSpacing.xl, 24.0);
      expect(AppSpacing.xxl, 32.0);
      expect(AppSpacing.xl2, 40.0);
      expect(AppSpacing.minHitTarget, 48.0);
      expect(AppSpacing.buttonHeightM, 48.0);
    });

    test('WCAG 2.2 AA/AAA contrast & Dark mode luminance guard hold', () {
      const light = TammySemanticColors.light;
      const dark = TammySemanticColors.dark;
      const hcLight = TammySemanticColors.highContrastLight;
      const hcDark = TammySemanticColors.highContrastDark;

      expect(light.primary, const Color(0xFF0B7A2A));
      expect(light.warning, const Color(0xFFB45309));
      expect(_contrastRatio(light.primary, light.onPrimary), greaterThan(4.5));
      expect(
        _contrastRatio(light.warning, const Color(0xFFFFFFFF)),
        greaterThan(4.5),
      );

      expect(dark.primary, const Color(0xFF19C23E));
      expect(dark.onPrimary, const Color(0xFF021608));
      expect(_contrastRatio(dark.primary, dark.onPrimary), greaterThan(7.0));
      expect(dark.background.computeLuminance(), greaterThan(0.006));
      expect(dark.surface.computeLuminance(), greaterThan(0.015));

      expect(
        _contrastRatio(hcLight.textPrimary, hcLight.background),
        greaterThan(10.0),
      );
      expect(
        _contrastRatio(hcLight.textSecondary, hcLight.surface),
        greaterThan(7.0),
      );
      expect(
        _contrastRatio(hcDark.textPrimary, hcDark.background),
        greaterThan(10.0),
      );
      expect(
        _contrastRatio(hcDark.textSecondary, hcDark.surface),
        greaterThan(7.0),
      );

      final numStyle = AppTypography.financialNumber(light);
      expect(
        numStyle.fontFeatures,
        contains(const FontFeature.tabularFigures()),
      );

      final hcLightTheme = AppTheme.light(highContrast: true);
      expect(
        hcLightTheme.iconButtonTheme.style?.minimumSize?.resolve({}),
        const Size(48, 48),
      );
      expect(
        hcLightTheme.filledButtonTheme.style?.foregroundColor?.resolve({}),
        hcLight.onPrimary,
      );
    });

    testWidgets(
      'LifeOsApp preserves OS textScaler >= 1.3 and exposes High Contrast toggle in Appearance sheet',
      (tester) async {
        final firestore = FakeFirebaseFirestore();
        final mockUser = MockUser(
          isAnonymous: false,
          uid: 'u_a11y_scale',
          email: 'a11y@lifeos.vn',
          displayName: 'Lan Anh',
        );
        await firestore.collection('users').doc('u_a11y_scale').set({
          'email': 'a11y@lifeos.vn',
          'fullName': 'Lan Anh',
          'onboardingCompleted': true,
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
              size: Size(430, 932),
              textScaler: TextScaler.linear(1.35),
            ),
            child: LifeOsApp(),
          ),
        );
        await tester.pumpAndSettle();

        final ctx = tester.element(find.byType(Scaffold).first);
        expect(MediaQuery.textScalerOf(ctx).scale(10.0), closeTo(13.5, 0.01));

        // Open appearance sheet and toggle High Contrast
        unawaited(showLifeOsAppearanceSheet(ctx));
        await tester.pumpAndSettle();

        final highContrastSwitch = find.byKey(
          const Key('appearance_high_contrast_switch'),
        );
        expect(highContrastSwitch, findsOneWidget);
        await tester.ensureVisible(highContrastSwitch);
        await tester.tap(highContrastSwitch);
        await tester.pumpAndSettle();

        expect(BlocProvider.of<ThemeBloc>(ctx).state.highContrast, isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('Financial Trust UX & State Clarity Widgets', () {
    testWidgets(
      'All 8 FinancialTrustStatus badges, DataVisibilityBadge, CloudSyncIndicator, OfflineSyncBanner & ProFintechStatementTile render cleanly',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(360, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        var retryCount = 0;

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
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final s in FinancialTrustStatus.values)
                          FinancialTrustStatusBadge(status: s),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        DataVisibilityBadge(isFamilyShared: false),
                        DataVisibilityBadge(isFamilyShared: true),
                        CloudSyncIndicator(
                          hasPendingWrites: false,
                          syncFailed: true,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    LifeOsOfflineSyncBanner(
                      syncFailed: true,
                      onRetry: () => retryCount++,
                    ),
                    const SizedBox(height: 12),
                    const ProFintechStatementTile(
                      merchant: 'Giao dịch đã hoàn',
                      categoryName: 'Mua sắm',
                      timeLabel: '10:30',
                      amountMinor: 250000,
                      isCredit: false,
                      isTransfer: false,
                      isReversed: true,
                      isVerified: true,
                    ),
                    const SizedBox(height: 8),
                    const ProFintechStatementTile(
                      merchant: 'VCB Tự động',
                      categoryName: 'Ăn uống',
                      timeLabel: '11:00',
                      amountMinor: 65000,
                      isCredit: false,
                      isTransfer: false,
                      isProvisional: true,
                      isVerified: false,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        for (final s in FinancialTrustStatus.values) {
          expect(find.text(s.labelVi), findsWidgets);
        }
        expect(find.text('Cá nhân · Riêng tư'), findsOneWidget);
        expect(find.text('Gia đình · Chia sẻ'), findsOneWidget);
        expect(find.text('Đồng bộ thất bại'), findsWidgets);

        await tester.tap(find.text('Thử đồng bộ lại'));
        await tester.pumpAndSettle();
        expect(retryCount, 1);

        // Reversed statement tile must NEVER render verified icon
        final reversedTile = find.byWidgetPredicate(
          (w) => w is ProFintechStatementTile && w.isReversed,
        );
        expect(
          find.descendant(
            of: reversedTile,
            matching: find.byIcon(Icons.verified_rounded),
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: reversedTile,
            matching: find.byIcon(Icons.undo_rounded),
          ),
          findsNWidgets(2),
        );
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('Notification Experience Engine 2.0 & Consent Behavior', () {
    test(
      'Quiet hours wrap overnight 22:00-07:00, filter disabledKinds, keep critical tier active & build digest',
      () {
        const prefs = NotificationExperiencePrefs(
          quietHoursEnabled: true,
          quietStartHour: 22,
          quietEndHour: 7,
          dailyDigestEnabled: true,
          digestHour: 20,
          disabledKinds: {SmartInboxKind.medicationReminder},
        );

        expect(
          prefs.isWithinQuietHours(DateTime(2026, 11, 25, 23, 30)),
          isTrue,
        );
        expect(prefs.isWithinQuietHours(DateTime(2026, 11, 26, 2, 15)), isTrue);
        expect(prefs.isWithinQuietHours(DateTime(2026, 11, 26, 6, 59)), isTrue);
        expect(prefs.isWithinQuietHours(DateTime(2026, 11, 26, 7, 0)), isFalse);
        expect(
          prefs.isWithinQuietHours(DateTime(2026, 11, 26, 14, 0)),
          isFalse,
        );

        final roundtrip = NotificationExperiencePrefs.fromJson(prefs.toJson());
        expect(roundtrip, prefs);

        final quietNow = DateTime(2026, 11, 25, 23, 30);
        final snap = SmartInboxEngine.build(
          referenceNow: quietNow,
          prefs: prefs,
          rawCandidates: [
            SmartInboxItem(
              dedupKey: 'tx::rev_1',
              kind: SmartInboxKind.bankProvisional,
              tier: SmartInboxTier.critical,
              titleVi: 'Giao dịch đảo bút toán',
              subtitleVi: '-500.000 ₫',
              timestamp: quietNow,
              targetRoute: '/finance',
              primaryActionLabelVi: 'Xem',
            ),
            SmartInboxItem(
              dedupKey: 'task::t1',
              kind: SmartInboxKind.taskOpen,
              tier: SmartInboxTier.actionable,
              titleVi: 'Đóng tiền điện',
              subtitleVi: 'Hôm nay',
              timestamp: quietNow,
              targetRoute: '/tasks-board',
              primaryActionLabelVi: 'Mở',
            ),
            SmartInboxItem(
              dedupKey: 'med::m1',
              kind: SmartInboxKind.medicationReminder,
              tier: SmartInboxTier.timeSensitive,
              titleVi: 'Vitamin D3',
              subtitleVi: 'Bị tắt loại thông báo này',
              timestamp: quietNow,
              targetRoute: '/health-hub',
              primaryActionLabelVi: 'Xem',
            ),
          ],
        );

        expect(snap.isQuietHoursActive, isTrue);
        expect(snap.activeItems.map((e) => e.dedupKey), ['tx::rev_1']);
        expect(snap.quietDeferredItems.map((e) => e.dedupKey), ['task::t1']);
        expect(snap.digestSummaryVi, contains('2 mục'));
      },
    );

    test(
      'NotificationIngestionBloc does NOT eagerly request push permission on NotificationsCenterStarted; prompts only on explicit consent/request',
      () async {
        final db = FakeFirebaseFirestore();
        final auth = MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: 'u_fcm_jit'),
        );
        await configureDependencies(
          authOverride: auth,
          firestoreOverride: db,
          httpClientOverride: MockClient((_) async => http.Response('{}', 404)),
        );

        final trackingDriver = _TrackingFcmDriver();
        addTearDown(trackingDriver.dispose);
        final fcm = FcmBankingMessagingService(
          firestore: db,
          driver: trackingDriver,
        );

        final bloc = NotificationIngestionBloc(
          repository: sl<NotificationsRepository>(),
          fcmService: fcm,
        );
        addTearDown(bloc.close);

        bloc.add(const NotificationsCenterStarted('u_fcm_jit'));
        await Future<void>.delayed(const Duration(milliseconds: 80));
        expect(trackingDriver.requestCalls, 0);

        bloc.add(
          const ConsentConfigUpdated(
            userId: 'u_fcm_jit',
            enabled: true,
            allowedPackages: ['com.VCB'],
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 80));
        expect(trackingDriver.requestCalls, 1);

        bloc.add(const PushNotificationPermissionRequested('u_fcm_jit'));
        await Future<void>.delayed(const Duration(milliseconds: 80));
        expect(trackingDriver.requestCalls, 2);
      },
    );
  });

  group('FTUE Onboarding, Honest Password Reset & Zero Exception Leaks', () {
    testWidgets(
      'OnboardingPrivacyPage saves interest chips + skip flag cleanly without prefilled fake invite/avatars',
      (tester) async {
        final firestore = FakeFirebaseFirestore();
        const uid = 'u_ftue_test';
        final mockUser = MockUser(
          isAnonymous: false,
          uid: uid,
          email: 'ftue@lifeos.vn',
          displayName: 'Ngọc Hà',
        );
        await firestore.collection('users').doc(uid).set({
          'email': 'ftue@lifeos.vn',
          'fullName': 'Ngọc Hà',
          'onboardingCompleted': false,
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

        expect(find.textContaining('Xin chào Ngọc Hà!'), findsOneWidget);
        expect(find.text('Chọn nhu cầu quan tâm'), findsOneWidget);
        expect(find.text('Lịch trình'), findsOneWidget);
        expect(find.text('GD-F7K9M2'), findsNothing);
        expect(find.text('Minh'), findsNothing);

        await tester.tap(find.byKey(const Key('onboarding_interest_family')));
        await tester.pumpAndSettle();

        final savedInterestsRaw = await NativeSecureVaultBridge.instance
            .readSecret('ux_user_interests_v1__u_$uid');
        expect(savedInterestsRaw, isNotNull);
        final savedInterests = (jsonDecode(savedInterestsRaw!) as List)
            .map((e) => e.toString())
            .toSet();
        expect(savedInterests, contains('family'));

        await tester.tap(find.byKey(const Key('onboarding_skip_btn')));
        await tester.pumpAndSettle();

        expect(
          await NativeSecureVaultBridge.instance.readSecret(
            'ux_onboarding_skipped_v1__u_$uid',
          ),
          '1',
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'VerifyOtpPage and ResetPasswordPage present honest Firebase email link guidance with zero fake 3847 OTP bypass',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: const VerifyOtpPage(email: 'bao@lifeos.vn'),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Kiểm tra email xác minh'), findsOneWidget);
        expect(find.text('3'), findsNothing);
        expect(find.text('8'), findsNothing);
        expect(find.text('4'), findsNothing);
        expect(find.text('7'), findsNothing);

        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.light(), home: const ResetPasswordPage()),
        );
        await tester.pumpAndSettle();

        expect(find.text('Đặt lại mật khẩu qua Email'), findsOneWidget);
        expect(find.text('✓ Đã cập nhật mật khẩu mới an toàn.'), findsNothing);
      },
    );

    test('Zero raw \$e / err.toString exception leaks in hardened files', () {
      const guardedFiles = [
        'lib/features/daily_life/presentation/bloc/daily_life_bloc.dart',
        'lib/features/daily_life/data/repositories/daily_life_repository_impl.dart',
        'lib/features/pro_utilities/data/repositories/pro_utilities_repository_impl.dart',
        'lib/features/documents/data/repositories/document_vault_repository_impl.dart',
      ];
      final rawExceptionPattern = RegExp(
        r'UnexpectedFailure\([^\)]*(\$e\b|\$\{e|err\.toString)',
        dotAll: true,
      );
      for (final path in guardedFiles) {
        final content = File(path).readAsStringSync();
        expect(
          rawExceptionPattern.hasMatch(content),
          isFalse,
          reason: 'Raw exception leaked into UnexpectedFailure in $path',
        );
      }
    });
  });
}
