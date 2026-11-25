import 'dart:io';
import 'dart:typed_data';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:life_os/app/app.dart';
import 'package:life_os/core/di/dependency_injection.dart';
import 'package:life_os/core/services/native_device_calendar_bridge.dart';
import 'package:life_os/core/services/native_secure_vault_bridge.dart';
import 'package:life_os/core/utils/smart_omni_intent_parser.dart';
import 'package:life_os/core/utils/smart_quick_entry_parser.dart';
import 'package:life_os/core/utils/user_behavior_prefs.dart';
import 'package:life_os/features/financial_ai/data/datasources/financial_ai_local_sync_datasource.dart';
import 'package:life_os/features/financial_ai/data/datasources/gemini_remote_datasource.dart';
import 'package:life_os/features/financial_ai/data/inference/fasttext_classifier.dart';
import 'package:life_os/features/financial_ai/data/normalization/financial_text_normalizer.dart';
import 'package:life_os/features/financial_ai/data/repositories/gemini_copilot_repository_impl.dart';
import 'package:life_os/features/financial_ai/domain/entities/gemini_copilot_entities.dart';
import 'package:life_os/features/transactions/domain/entities/transaction_entities.dart';

class _NoOpCalendarDriver implements DeviceCalendarDriver {
  const _NoOpCalendarDriver();

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

void main() {
  late Uint8List preloadedModelBytes;
  late String preloadedMetaJson;

  setUpAll(() {
    preloadedModelBytes = File(
      'assets/models/vn_financial_fasttext_v1.ftq',
    ).readAsBytesSync();
    preloadedMetaJson = File(
      'assets/models/vn_financial_fasttext_v1_meta.json',
    ).readAsStringSync();
  });

  setUp(() async {
    await NativeSecureVaultBridge.instance.clearAllSecrets();
    await UserBehaviorPrefs.resetForTest();
    NativeDeviceCalendarBridge.setDriverOverride(const _NoOpCalendarDriver());
  });

  tearDown(() async {
    NativeDeviceCalendarBridge.setDriverOverride(null);
    await sl.reset();
  });

  group('1. Colloquial Vietnamese Money & Multi-Clause Local NLU', () {
    test(
      'Parses everyday slang (cành, xị, lít, củ rưỡi, nửa củ, chục, trăm rưỡi) with exact int math',
      () {
        final normalizer = FinancialTextNormalizer();

        final pho = SmartQuickEntryParser.tryParse('Ăn phở 45 cành');
        expect(pho, isNotNull);
        expect(pho!.amountMinor, 45000);
        expect(pho.categoryId, 'cat_food');
        expect(pho.merchant, 'Ăn phở');

        final cf = SmartQuickEntryParser.tryParse('Cà phê 1 xị rưỡi');
        expect(cf, isNotNull);
        expect(cf!.amountMinor, 150000);
        expect(cf.categoryId, 'cat_food');

        final cuoi = SmartQuickEntryParser.tryParse('Mừng cưới 5 lít');
        expect(cuoi, isNotNull);
        expect(cuoi!.amountMinor, 500000);
        expect(cuoi.categoryId, 'cat_family_social');

        final suaXe = SmartQuickEntryParser.tryParse('Sửa xe 1 củ rưỡi');
        expect(suaXe, isNotNull);
        expect(suaXe!.amountMinor, 1500000);
        expect(suaXe.categoryId, 'cat_vehicle_maint');

        final guiXe = SmartQuickEntryParser.tryParse('Gửi xe hai chục');
        expect(guiXe, isNotNull);
        expect(guiXe!.amountMinor, 20000);
        expect(guiXe.categoryId, 'cat_vehicle');

        final bayTramRuoi = normalizer.extractAmounts(
          normalizer.normalizeText('Mua bàn phím bảy trăm rưỡi'),
        );
        expect(bayTramRuoi, isNotEmpty);
        expect(bayTramRuoi.first.amountMinor, 750000);

        // Guard: liquid volume ("2 lít nước") must NOT become 200,000 VND money!
        expect(SmartQuickEntryParser.tryParse('Uống 2 lít nước'), isNull);
        // Guard: vague quantifier ("mấy chục") must NEVER guess an arbitrary amount!
        expect(SmartQuickEntryParser.tryParse('Mua mấy chục cái bánh'), isNull);
      },
    );

    test(
      'Splits comma and "rồi" multi-expense & "sáng mốt" schedule clauses accurately',
      () {
        final fixedNow = DateTime(2026, 11, 24, 9, 0);

        final twoItems = SmartOmniIntentParser.parseMulti(
          'Đổ xăng 70k, cf 25k',
          now: fixedNow,
        );
        expect(twoItems.length, 2);
        expect(twoItems[0].amountMinor, 70000);
        expect(twoItems[0].categoryName, 'Xe cộ & Di chuyển');
        expect(twoItems[1].amountMinor, 25000);
        expect(twoItems[1].categoryName, 'Ăn uống');

        final threeItems = SmartOmniIntentParser.parseMulti(
          'Ăn phở 45 cành, cà phê 1 xị rưỡi rồi đổ xăng 70k',
          now: fixedNow,
        );
        expect(threeItems.length, 3);
        expect(threeItems[0].amountMinor, 45000);
        expect(threeItems[1].amountMinor, 150000);
        expect(threeItems[2].amountMinor, 70000);

        final dayAfterTomorrow = SmartOmniIntentParser.parseMulti(
          'Sáng mốt 9h họp kiến trúc hệ thống',
          now: fixedNow,
        );
        expect(dayAfterTomorrow.length, 1);
        expect(dayAfterTomorrow.first.kind, OmniActionKind.calendarEvent);
        expect(
          dayAfterTomorrow.first.scheduledAt,
          DateTime(2026, 11, 26, 9, 0),
        );
      },
    );
  });

  group('2. Offline Hybrid Engine: FastText + Learned Rule + Local Coaching', () {
    test(
      'Applies learned PersonalizationRule and safe-daily-spend coaching completely offline without API key',
      () async {
        final firestore = FakeFirebaseFirestore();
        final mockAuth = MockFirebaseAuth(
          mockUser: MockUser(uid: 'u_local_pro', email: 'local@lifeos.vn'),
          signedIn: true,
        );
        final localSync = FinancialAiLocalSyncDataSource(firestore);
        await localSync.upsertCorrectionRule(
          userId: 'u_local_pro',
          merchantDisplay: 'Circle K',
          merchantCanonicalKey: 'circle_k',
          selectedCategoryId: 'cat_food',
          selectedCategoryName: 'Ăn uống',
          semanticKey: 'food.drinks',
          directionCondition: 'debit',
          sourceContext: 'any',
          modelVersion: '1.0.0',
        );

        final classifier = FastTextClassifier(
          useWorkerIsolate: false,
          bytesLoader: (_) async => preloadedModelBytes,
          jsonLoader: (_) async => preloadedMetaJson,
        );
        await classifier.initialize();

        final offlineHttp = MockClient(
          (_) async => http.Response('offline', 503),
        );
        final repo = GeminiCopilotRepositoryImpl(
          GeminiRemoteDataSource(httpClient: offlineHttp),
          localClassifier: classifier,
          localSync: localSync,
          normalizer: FinancialTextNormalizer(),
          firebaseAuth: mockAuth,
        );

        final res = await repo.analyzeHybridOmniCommand(
          rawInput: 'Circle K 32k',
          contextSnapshot: const GeminiContextSnapshot(
            monthlyIncomeMinor: 20000000,
            monthlyExpenseMinor: 14000000,
            safeDailyAllowanceMinor: 200000,
          ),
          referenceTime: DateTime(2026, 11, 24, 12, 30),
        );

        expect(res.isSuccess, isTrue);
        res.fold((_) => fail('Expected offline success'), (hybrid) {
          expect(hybrid.usedGeminiCloud, isFalse);
          expect(hybrid.actionDrafts.length, 1);
          final tx = hybrid.actionDrafts.first;
          expect(tx.kind, OmniActionKind.transaction);
          expect(tx.transactionKind, TransactionKind.expense);
          expect(tx.amountMinor, 32000);
          expect(tx.categoryId, 'cat_food');
          expect(tx.categoryName, 'Ăn uống');
          // Verifies rich local coaching mentions remaining safe daily budget (168.000 ₫)
          expect(hybrid.assistantInsightVi, contains('168.000'));
        });

        await classifier.dispose();
      },
    );
  });

  group('3. Local Agent Studio UI @ 360x800 (112% Text Scale)', () {
    testWidgets(
      'Runs Local Sandbox, discloses model telemetry, tunes confidence slider, and teaches manual rule with zero overflow',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(360, 800));
        tester.platformDispatcher.textScaleFactorTestValue = 1.12;
        addTearDown(() {
          tester.platformDispatcher.clearTextScaleFactorTestValue();
          tester.binding.setSurfaceSize(null);
        });

        final firestore = FakeFirebaseFirestore();
        final mockUser = MockUser(
          isAnonymous: false,
          uid: 'u_studio_ui',
          email: 'studio@lifeos.vn',
          displayName: 'Minh Hòa',
        );
        await firestore.collection('users').doc('u_studio_ui').set({
          'email': 'studio@lifeos.vn',
          'fullName': 'Minh Hòa',
          'onboardingCompleted': true,
          'privacy': {'shareSalaryWithFamily': false},
        });
        final auth = MockFirebaseAuth(mockUser: mockUser, signedIn: true);

        await configureDependencies(
          authOverride: auth,
          firestoreOverride: firestore,
          httpClientOverride: MockClient((_) async => http.Response('{}', 200)),
          googleCalendarTokenOverride: ({required interactive}) async => null,
          financialClassifierOverride: FastTextClassifier(
            useWorkerIsolate: false,
            bytesLoader: (_) async => preloadedModelBytes,
            jsonLoader: (_) async => preloadedMetaJson,
          ),
        );

        await tester.pumpWidget(const LifeOsApp());
        await tester.pumpAndSettle();

        // Open AI Assistant -> AI Settings Studio
        await tester.tap(find.byKey(const Key('today_open_gemini_ai_pill')));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Cài đặt AI & Liên kết Gemini'));
        await tester.pumpAndSettle();

        Future<void> centerTarget(Finder target) async {
          final mainScrollable = find
              .descendant(
                of: find.byType(ListView),
                matching: find.byType(Scrollable),
              )
              .first;
          await tester.scrollUntilVisible(
            target,
            140,
            scrollable: mainScrollable,
          );
          await Scrollable.ensureVisible(
            tester.element(target),
            alignment: 0.45,
          );
          await tester.pumpAndSettle();
        }

        // 1. Expand progressive "Chi tiết & Kiểm thử mô hình" disclosure first
        await centerTarget(
          find.byKey(const Key('toggle_local_ai_model_details')),
        );
        await tester.tap(
          find.byKey(const Key('toggle_local_ai_model_details')),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('vn_financial_fasttext_v1'), findsOneWidget);

        // 2. Run live sandbox inside the disclosed section
        await centerTarget(find.byKey(const Key('local_ai_sandbox_input')));
        await tester.enterText(
          find.byKey(const Key('local_ai_sandbox_input')),
          'Ăn phở 45 cành, cf 25k',
        );
        await centerTarget(find.byKey(const Key('local_ai_sandbox_run_btn')));
        await tester.tap(find.byKey(const Key('local_ai_sandbox_run_btn')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('local_ai_sandbox_result')),
          findsOneWidget,
        );

        // 3. Scroll to Confidence Slider & adjust sensitivity
        await centerTarget(find.byKey(const Key('local_ai_confidence_slider')));
        await tester.drag(
          find.byKey(const Key('local_ai_confidence_slider')),
          const Offset(45, 0),
        );
        await tester.pumpAndSettle();

        // 4. Teach a new manual rule ("Circle K" -> "Ăn uống")
        await centerTarget(find.byKey(const Key('btn_add_manual_ai_rule')));
        await tester.tap(find.byKey(const Key('btn_add_manual_ai_rule')));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('manual_rule_keyword_input')),
          'Circle K',
        );
        await tester.tap(find.byKey(const Key('btn_save_manual_ai_rule')));
        await tester.pumpAndSettle();

        expect(find.textContaining('Circle K → Ăn uống'), findsOneWidget);

        // 5. Navigate to /smart-notes-hub and verify mood check-in & old tab label are gone
        final settingsCtx = tester.element(
          find.byKey(const Key('btn_add_manual_ai_rule')),
        );
        GoRouter.of(settingsCtx).push('/smart-notes-hub');
        await tester.pumpAndSettle();

        expect(find.text('Hôm nay tâm trạng của bạn thế nào?'), findsNothing);
        expect(find.text('Sổ tay & Cảm xúc'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
