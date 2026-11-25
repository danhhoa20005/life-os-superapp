import 'dart:io';
import 'dart:typed_data';

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
import 'package:life_os/core/di/dependency_injection.dart';
import 'package:life_os/core/widgets/lifeos_top_toast.dart';
import 'package:life_os/features/authentication/presentation/bloc/auth_bloc.dart';
import 'package:life_os/features/authentication/presentation/bloc/auth_event.dart';
import 'package:life_os/features/authentication/presentation/bloc/auth_state.dart';
import 'package:life_os/features/financial_ai/data/datasources/financial_ai_local_sync_datasource.dart';
import 'package:life_os/features/financial_ai/data/extraction/financial_entity_extractor.dart';
import 'package:life_os/features/financial_ai/data/inference/fasttext_classifier.dart';
import 'package:life_os/features/financial_ai/data/normalization/financial_text_normalizer.dart';
import 'package:life_os/features/financial_ai/data/repositories/financial_ai_repository_impl.dart';
import 'package:life_os/features/financial_ai/domain/entities/financial_ai_entities.dart';
import 'package:life_os/features/financial_ai/domain/repositories/financial_ai_repository.dart';
import 'package:life_os/features/financial_ai/presentation/bloc/financial_ai_bloc.dart';
import 'package:life_os/features/financial_ai/presentation/pages/financial_ai_assistant_page.dart';
import 'package:life_os/features/financial_ai/presentation/pages/financial_ai_settings_page.dart';
import 'package:life_os/features/notifications/data/repositories/notifications_repository_impl.dart';
import 'package:life_os/features/notifications/domain/entities/notification_entities.dart';
import 'package:life_os/features/transactions/data/datasources/transaction_remote_datasource.dart';
import 'package:life_os/features/transactions/data/repositories/transaction_repository_impl.dart';
import 'package:life_os/features/transactions/domain/entities/transaction_entities.dart';
import 'package:life_os/features/transactions/domain/repositories/transaction_repository.dart';
import 'package:life_os/features/transactions/presentation/bloc/transaction_bloc.dart';
import 'package:life_os/features/transactions/presentation/bloc/transaction_event.dart';

void _assertZeroVisualOverflow(
  WidgetTester tester, {
  required String contextLabel,
}) {
  final renderObjects = tester.allRenderObjects.toList();
  for (final ro in renderObjects) {
    if (ro is RenderParagraph && ro.didExceedMaxLines) {
      fail(
        '[$contextLabel] RenderParagraph exceeded maxLines: "${ro.text.toPlainText()}"',
      );
    }
  }
}

void main() {
  Future<Uint8List> loadDiskModelBytes(String path) => File(path).readAsBytes();
  Future<String> loadDiskMetaJson(String path) => File(path).readAsString();

  group('Phase 18.3 — End-to-End Offline Financial AI Integration & Widget Tests', () {
    late FakeFirebaseFirestore fakeFirestore;
    late FastTextClassifier diskClassifier;
    late Uint8List preloadedModelBytes;
    late String preloadedMetaJson;

    setUpAll(() async {
      preloadedModelBytes = await File(
        FastTextClassifier.defaultModelAsset,
      ).readAsBytes();
      preloadedMetaJson = await File(
        FastTextClassifier.defaultMetaAsset,
      ).readAsString();
      diskClassifier = FastTextClassifier(
        bytesLoader: loadDiskModelBytes,
        jsonLoader: loadDiskMetaJson,
      );
      await diskClassifier.initialize();
    });

    tearDownAll(() async {
      await diskClassifier.dispose();
    });

    setUp(() async {
      fakeFirestore = FakeFirebaseFirestore();
    });

    test(
      'Personalization Engine learns merchant corrections, enforces strict family user isolation, and invalidates deleted categories',
      () async {
        const aliceId = 'uid_alice_01';
        const bobId = 'uid_bob_family_member_02';

        final txRepo = TransactionRepositoryImpl(
          TransactionRemoteDataSource(fakeFirestore),
        );
        final aiRepo = FinancialAiRepositoryImpl(
          classifier: diskClassifier,
          normalizer: FinancialTextNormalizer(
            clock: FixedFinancialClock(DateTime(2026, 11, 23, 12, 0)),
          ),
          extractor: FinancialEntityExtractor(
            FinancialTextNormalizer(
              clock: FixedFinancialClock(DateTime(2026, 11, 23, 12, 0)),
            ),
          ),
          localSync: FinancialAiLocalSyncDataSource(fakeFirestore),
          transactionRepository: txRepo,
          firestore: fakeFirestore,
        );

        const aliceWallets = <WalletEntity>[
          WalletEntity(
            id: 'w_alice_cash',
            ownerId: aliceId,
            name: 'Ví Alice',
            type: WalletType.cash,
            balanceMinor: 1000000,
          ),
        ];
        const aliceCategories = <CategoryEntity>[
          CategoryEntity(
            id: 'cat_alice_food',
            ownerId: aliceId,
            name: 'Ăn uống',
            direction: 'debit',
            iconKey: 'restaurant',
          ),
          CategoryEntity(
            id: 'cat_alice_shop',
            ownerId: aliceId,
            name: 'Chợ & Mua sắm',
            direction: 'debit',
            iconKey: 'shopping_bag',
          ),
        ];

        const bobWallets = <WalletEntity>[
          WalletEntity(
            id: 'w_bob_cash',
            ownerId: bobId,
            name: 'Ví Bob',
            type: WalletType.cash,
            balanceMinor: 1000000,
          ),
        ];
        const bobCategories = <CategoryEntity>[
          CategoryEntity(
            id: 'cat_bob_food',
            ownerId: bobId,
            name: 'Ăn uống',
            direction: 'debit',
            iconKey: 'restaurant',
          ),
          CategoryEntity(
            id: 'cat_bob_shop',
            ownerId: bobId,
            name: 'Chợ & Mua sắm',
            direction: 'debit',
            iconKey: 'shopping_bag',
          ),
        ];

        // 1. Alice teaches Circle K -> Ăn uống (cat_alice_food)
        final ruleRes = await aiRepo.saveCategoryCorrection(
          userId: aliceId,
          merchantDisplay: 'Circle K',
          merchantCanonicalKey: 'circle k',
          selectedCategoryId: 'cat_alice_food',
          selectedCategoryName: 'Ăn uống',
          semanticKey: 'food.meals',
        );
        expect(ruleRes.isSuccess, isTrue);

        // 2. Alice's next Circle K transaction uses her personalized rule
        final aliceNext = await aiRepo.analyzeText(
          userId: aliceId,
          text: 'Circle K 32k',
          knownWallets: aliceWallets,
          knownCategories: aliceCategories,
        );
        final aliceCand = aliceNext.fold<TransactionCandidate>(
          (f) => fail(f.message),
          (v) => v.candidates.single,
        );
        expect(aliceCand.resolvedCategoryId, 'cat_alice_food');
        expect(
          aliceCand.topPrediction.origin,
          ClassifierInferenceOrigin.personalizationRule,
        );

        // 3. Family member Bob does NOT inherit Alice's private personalization rule!
        final bobNext = await aiRepo.analyzeText(
          userId: bobId,
          text: 'Circle K 32k',
          familyId: 'shared_family_01',
          knownWallets: bobWallets,
          knownCategories: bobCategories,
        );
        final bobCand = bobNext.fold<TransactionCandidate>(
          (f) => fail(f.message),
          (v) => v.candidates.single,
        );
        expect(
          bobCand.topPrediction.origin,
          isNot(ClassifierInferenceOrigin.personalizationRule),
        );
        expect(bobCand.appliedPersonalizationRuleId, isNull);

        // 4. If Alice deletes `cat_alice_food`, her stale rule is safely bypassed (never assigns deleted ID!)
        final aliceAfterCatDeleted = await aiRepo.analyzeText(
          userId: aliceId,
          text: 'Circle K 32k',
          knownWallets: aliceWallets,
          knownCategories: const [
            CategoryEntity(
              id: 'cat_alice_shop',
              ownerId: aliceId,
              name: 'Chợ & Mua sắm',
              direction: 'debit',
              iconKey: 'shopping_bag',
            ),
          ],
        );
        final safeCand = aliceAfterCatDeleted.fold<TransactionCandidate>(
          (f) => fail(f.message),
          (v) => v.candidates.single,
        );
        expect(safeCand.resolvedCategoryId, isNot('cat_alice_food'));
      },
    );

    test(
      'Internal Transfer & Idempotent Confirmation preserve exact double-wallet accounting without inflating income/expense',
      () async {
        const uid = 'uid_accounting_01';
        await fakeFirestore
            .collection('users')
            .doc(uid)
            .collection('wallets')
            .doc('w_mb')
            .set({
              'id': 'w_mb',
              'ownerId': uid,
              'name': 'MBBank',
              'type': 'bank',
              'bankCode': 'MB',
              'balanceMinor': 10000000,
              'isEstimatedBalance': false,
            });
        await fakeFirestore
            .collection('users')
            .doc(uid)
            .collection('wallets')
            .doc('w_vcb')
            .set({
              'id': 'w_vcb',
              'ownerId': uid,
              'name': 'Vietcombank',
              'type': 'bank',
              'bankCode': 'VCB',
              'balanceMinor': 5000000,
              'isEstimatedBalance': false,
            });

        final txRepo = TransactionRepositoryImpl(
          TransactionRemoteDataSource(fakeFirestore),
        );
        final aiRepo = FinancialAiRepositoryImpl(
          classifier: diskClassifier,
          normalizer: FinancialTextNormalizer(),
          extractor: FinancialEntityExtractor(FinancialTextNormalizer()),
          localSync: FinancialAiLocalSyncDataSource(fakeFirestore),
          transactionRepository: txRepo,
          firestore: fakeFirestore,
        );

        final analysisRes = await aiRepo.analyzeText(
          userId: uid,
          text: 'Chuyển 2 triệu từ MB sang Vietcombank của tôi',
        );
        final transferCandidate = analysisRes.fold<TransactionCandidate>(
          (f) => fail(f.message),
          (v) => v.candidates.single,
        );
        expect(
          transferCandidate.transactionType,
          FinancialTransactionType.internalTransfer,
        );
        expect(transferCandidate.sourceWalletId, 'w_mb');
        expect(transferCandidate.destinationWalletId, 'w_vcb');

        // Confirm once + retry with same operationId (idempotency check)
        const opId = 'op_idempotent_transfer_01';
        final confirm1 = await aiRepo.confirmCandidateDraft(
          userId: uid,
          candidate: transferCandidate,
          operationId: opId,
        );
        expect(confirm1.isSuccess, isTrue);

        final confirmRetry = await aiRepo.confirmCandidateDraft(
          userId: uid,
          candidate: transferCandidate,
          operationId: opId,
        );
        expect(confirmRetry.isSuccess, isTrue);

        // Verify MB = 8,000,000 (-2tr once!), VCB = 7,000,000 (+2tr once!), total = 15,000,000 unchanged!
        final mbDoc = await fakeFirestore
            .collection('users')
            .doc(uid)
            .collection('wallets')
            .doc('w_mb')
            .get();
        final vcbDoc = await fakeFirestore
            .collection('users')
            .doc(uid)
            .collection('wallets')
            .doc('w_vcb')
            .get();
        expect(mbDoc.data()!['balanceMinor'], 8000000);
        expect(vcbDoc.data()!['balanceMinor'], 7000000);

        final txDocs = await fakeFirestore
            .collection('users')
            .doc(uid)
            .collection('transactions')
            .get();
        expect(txDocs.docs.length, 1);
        expect(txDocs.docs.single.data()['kind'], 'transfer');
      },
    );

    test(
      'Android Bank Notification ingestion enriches category via Offline AI + Personalization and blocks duplicate/OTP payloads',
      () async {
        const uid = 'uid_bank_notif_01';
        await fakeFirestore
            .collection('users')
            .doc(uid)
            .collection('wallets')
            .doc('wallet_vcb')
            .set({
              'id': 'wallet_vcb',
              'ownerId': uid,
              'name': 'VCB Digibank',
              'type': 'bank',
              'bankCode': 'VCB',
              'balanceMinor': 5000000,
              'isEstimatedBalance': false,
            });
        await fakeFirestore
            .collection('users')
            .doc(uid)
            .collection('categories')
            .doc('cat_food')
            .set({
              'id': 'cat_food',
              'ownerId': uid,
              'name': 'Ăn uống',
              'direction': 'debit',
              'iconKey': 'restaurant',
            });
        await fakeFirestore
            .collection('users')
            .doc(uid)
            .collection('consents')
            .doc('android_notification')
            .set({
              'enabled': true,
              'autoConfirmSignals': false,
              'syncObservedBalance': true,
              'allowedPackages': ['com.VCB'],
            });

        final mockAuth = MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: uid, email: 'vcb@lifeos.vn'),
        );
        await sl.reset();
        await configureDependencies(
          authOverride: mockAuth,
          firestoreOverride: fakeFirestore,
          httpClientOverride: MockClient((_) async => http.Response('{}', 404)),
        );
        sl.allowReassignment = true;
        final txRepo = sl<TransactionRepository>();
        final aiRepo = FinancialAiRepositoryImpl(
          classifier: diskClassifier,
          normalizer: FinancialTextNormalizer(),
          extractor: FinancialEntityExtractor(FinancialTextNormalizer()),
          localSync: FinancialAiLocalSyncDataSource(fakeFirestore),
          transactionRepository: txRepo,
          firestore: fakeFirestore,
        );
        sl.registerSingleton<FinancialAiRepository>(aiRepo);

        // Teach personalization rule: HIGHLANDS COFFEE -> Ăn uống
        await aiRepo.saveCategoryCorrection(
          userId: uid,
          merchantDisplay: 'HIGHLANDS COFFEE',
          merchantCanonicalKey: 'highlands coffee',
          selectedCategoryId: 'cat_food',
          selectedCategoryName: 'Ăn uống',
          semanticKey: 'food.drinks',
        );

        final notifDataSource = NotificationsRemoteDataSource(
          firestore: fakeFirestore,
          firebaseAuth: mockAuth,
          bridge: sl(),
          financialAiRepository: aiRepo,
        );

        // 1. OTP message MUST be blocked immediately
        final otpOutcome = await notifDataSource.ingestAndroidNotification(
          userId: uid,
          defaultWalletId: 'wallet_vcb',
          packageName: 'com.VCB',
          title: 'VCB SmartOTP',
          body: 'Ma OTP xac thuc giao dich 500,000 VND cua quy khach la 481920',
          postedAt: DateTime(2026, 11, 23, 9, 10),
        );
        expect(otpOutcome.kind, IngestionOutcomeKind.blockedOtpOrSecret);

        // 2. Real VCB debit notification -> classified & personalized to 'Ăn uống'
        final postedTime = DateTime(2026, 11, 23, 9, 15);
        final firstOutcome = await notifDataSource.ingestAndroidNotification(
          userId: uid,
          defaultWalletId: 'wallet_vcb',
          packageName: 'com.VCB',
          title: 'VCB Digibank',
          body:
              'SD TK 0011009988776 -55,000VND luc 23-11-2026 09:15:00. SD 4,945,000VND. ND: THANH TOAN HIGHLANDS COFFEE',
          postedAt: postedTime,
          notificationId: 'notif_vcb_001',
        );
        expect(firstOutcome.transactionId, isNotNull);

        final createdTxDoc = await fakeFirestore
            .collection('users')
            .doc(uid)
            .collection('transactions')
            .doc(firstOutcome.transactionId!)
            .get();
        expect(createdTxDoc.data()!['amountMinor'], 55000);
        expect(createdTxDoc.data()!['categoryName'], 'Ăn uống');

        // 3. Duplicate notification arriving 10 seconds later -> deduplicated (still 1 transaction!)
        final dupOutcome = await notifDataSource.ingestAndroidNotification(
          userId: uid,
          defaultWalletId: 'wallet_vcb',
          packageName: 'com.VCB',
          title: 'VCB Digibank',
          body:
              'SD TK 0011009988776 -55,000VND luc 23-11-2026 09:15:00. SD 4,945,000VND. ND: THANH TOAN HIGHLANDS COFFEE',
          postedAt: postedTime.add(const Duration(seconds: 10)),
          notificationId: 'notif_vcb_001_retry',
        );
        expect(dupOutcome.kind, IngestionOutcomeKind.duplicateIgnored);

        final allTx = await fakeFirestore
            .collection('users')
            .doc(uid)
            .collection('transactions')
            .get();
        expect(allTx.docs.length, 1);
      },
    );

    testWidgets(
      'FinancialAiAssistantPage & FinancialAiSettingsPage render cleanly at 360x800 @ 112% text scale, preview multi-drafts, and confirm to ledger',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        const uid = 'uid_ui_e2e_01';
        await fakeFirestore.collection('users').doc(uid).set({
          'id': uid,
          'email': 'hoa@lifeos.vn',
          'fullName': 'Danh Hòa',
          'onboardingCompleted': true,
          'availabilityOptIn': false,
        });
        await fakeFirestore
            .collection('users')
            .doc(uid)
            .collection('wallets')
            .doc('w_cash')
            .set({
              'id': 'w_cash',
              'ownerId': uid,
              'name': 'Ví tiền mặt',
              'type': 'cash',
              'balanceMinor': 2500000,
              'isEstimatedBalance': false,
            });
        await fakeFirestore
            .collection('users')
            .doc(uid)
            .collection('categories')
            .doc('cat_vehicle')
            .set({
              'id': 'cat_vehicle',
              'ownerId': uid,
              'name': 'Xe cộ & Di chuyển',
              'direction': 'debit',
              'iconKey': 'directions_car',
            });
        await fakeFirestore
            .collection('users')
            .doc(uid)
            .collection('categories')
            .doc('cat_food')
            .set({
              'id': 'cat_food',
              'ownerId': uid,
              'name': 'Ăn uống',
              'direction': 'debit',
              'iconKey': 'restaurant',
            });

        final mockAuth = MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(
            uid: uid,
            email: 'hoa@lifeos.vn',
            displayName: 'Danh Hòa',
          ),
        );
        await sl.reset();
        await configureDependencies(
          authOverride: mockAuth,
          firestoreOverride: fakeFirestore,
          httpClientOverride: MockClient((_) async => http.Response('{}', 404)),
        );
        sl.allowReassignment = true;
        final widgetSafeClassifier = FastTextClassifier(
          useWorkerIsolate: false,
          bytesLoader: (_) async => preloadedModelBytes,
          jsonLoader: (_) async => preloadedMetaJson,
        );
        final aiRepo = FinancialAiRepositoryImpl(
          classifier: widgetSafeClassifier,
          normalizer: FinancialTextNormalizer(
            clock: FixedFinancialClock(DateTime(2026, 11, 23, 15, 0)),
          ),
          extractor: FinancialEntityExtractor(
            FinancialTextNormalizer(
              clock: FixedFinancialClock(DateTime(2026, 11, 23, 15, 0)),
            ),
          ),
          localSync: FinancialAiLocalSyncDataSource(fakeFirestore),
          transactionRepository: sl<TransactionRepository>(),
          firestore: fakeFirestore,
        );
        sl.registerSingleton<FinancialAiRepository>(aiRepo);

        final authBloc = sl<AuthBloc>()..add(const AuthSubscriptionRequested());
        await tester.pumpAndSettle();
        expect(authBloc.state.status, AuthStatus.authenticated);

        final txListBloc = sl<TransactionListBloc>()
          ..add(
            const TransactionsSubscriptionRequested(
              userId: uid,
              monthKey: '2026-11',
            ),
          );
        final txActionBloc = sl<TransactionActionBloc>();
        final aiBloc = FinancialAiBloc(
          repository: aiRepo,
          analyzeText: sl(),
          confirmDraft: sl(),
          saveCorrection: sl(),
          getPendingDrafts: sl(),
        )..add(const FinancialAiInitialized(uid));

        await tester.pumpWidget(
          MultiBlocProvider(
            providers: [
              BlocProvider<AuthBloc>.value(value: authBloc),
              BlocProvider<TransactionListBloc>.value(value: txListBloc),
              BlocProvider<TransactionActionBloc>.value(value: txActionBloc),
              BlocProvider<FinancialAiBloc>.value(value: aiBloc),
            ],
            child: MediaQuery(
              data: const MediaQueryData(
                size: Size(360, 800),
                textScaler: TextScaler.linear(1.12),
              ),
              child: MaterialApp(
                theme: AppTheme.light(),
                builder: (_, child) => LifeOsTopToastHost(child: child!),
                home: const FinancialAiAssistantPage(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        _assertZeroVisualOverflow(
          tester,
          contextLabel: 'FinancialAiAssistantPage Idle',
        );

        // Dispatch multi-transaction sentence into FinancialAiBloc
        aiBloc.add(
          const FinancialTextSubmitted(
            userId: uid,
            text: 'Chiều qua tôi đổ xăng 70k và mua nước 15 nghìn',
            preferredWalletId: 'w_cash',
          ),
        );
        await tester.pump(const Duration(milliseconds: 120));
        await tester.pumpAndSettle();

        expect(aiBloc.state.activeCandidates.length, 2);
        final pageScrollable = find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first;
        await tester.scrollUntilVisible(
          find.textContaining('70.000'),
          200,
          scrollable: pageScrollable,
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('70.000'), findsWidgets);
        _assertZeroVisualOverflow(
          tester,
          contextLabel: 'FinancialAiAssistantPage Draft Card 1 @ 112%',
        );
        await tester.scrollUntilVisible(
          find.textContaining('15.000'),
          200,
          scrollable: pageScrollable,
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('15.000'), findsWidgets);
        _assertZeroVisualOverflow(
          tester,
          contextLabel: 'FinancialAiAssistantPage 2 Draft Cards @ 112%',
        );

        // Confirm all drafts -> writes 2 transactions to ledger!
        aiBloc.add(const FinancialDraftConfirmed(userId: uid));
        await tester.pump(const Duration(milliseconds: 120));
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();

        final txSnap = await fakeFirestore
            .collection('users')
            .doc(uid)
            .collection('transactions')
            .get();
        expect(txSnap.docs.length, 2);

        final walletSnap = await fakeFirestore
            .collection('users')
            .doc(uid)
            .collection('wallets')
            .doc('w_cash')
            .get();
        // 2,500,000 - 70,000 - 15,000 = 2,415,000
        expect(walletSnap.data()!['balanceMinor'], 2415000);

        // Also render FinancialAiSettingsPage at 360x800 @ 112% scale
        await aiRepo.saveCategoryCorrection(
          userId: uid,
          merchantDisplay: 'Circle K',
          merchantCanonicalKey: 'circle k',
          selectedCategoryId: 'cat_food',
          selectedCategoryName: 'Ăn uống',
          semanticKey: 'food.meals',
        );
        await tester.pumpWidget(
          MultiBlocProvider(
            providers: [
              BlocProvider<AuthBloc>.value(value: authBloc),
              BlocProvider<FinancialAiBloc>.value(value: aiBloc),
            ],
            child: MediaQuery(
              data: const MediaQueryData(
                size: Size(360, 800),
                textScaler: TextScaler.linear(1.12),
              ),
              child: MaterialApp(
                theme: AppTheme.light(),
                builder: (_, child) => LifeOsTopToastHost(child: child!),
                home: const FinancialAiSettingsPage(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.textContaining('Circle K'),
          200,
          scrollable: find
              .descendant(
                of: find.byType(ListView),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('Circle K'), findsWidgets);
        _assertZeroVisualOverflow(
          tester,
          contextLabel: 'FinancialAiSettingsPage @ 112%',
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );

    testWidgets(
      'Full LifeOsApp navigates cleanly to /financial-ai via Finance tab header button',
      (tester) async {
        const uid = 'uid_router_ai_01';
        await fakeFirestore.collection('users').doc(uid).set({
          'id': uid,
          'email': 'router@lifeos.vn',
          'fullName': 'Minh Khoa',
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
              'balanceMinor': 12000000,
              'isEstimatedBalance': false,
            });

        final mockAuth = MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(
            uid: uid,
            email: 'router@lifeos.vn',
            displayName: 'Minh Khoa',
          ),
        );
        await sl.reset();
        await configureDependencies(
          authOverride: mockAuth,
          firestoreOverride: fakeFirestore,
          httpClientOverride: MockClient((_) async => http.Response('{}', 404)),
        );
        sl.allowReassignment = true;
        final widgetSafeClassifier = FastTextClassifier(
          useWorkerIsolate: false,
          bytesLoader: (_) async => preloadedModelBytes,
          jsonLoader: (_) async => preloadedMetaJson,
        );
        final aiRepo = FinancialAiRepositoryImpl(
          classifier: widgetSafeClassifier,
          normalizer: FinancialTextNormalizer(),
          extractor: FinancialEntityExtractor(FinancialTextNormalizer()),
          localSync: FinancialAiLocalSyncDataSource(fakeFirestore),
          transactionRepository: sl<TransactionRepository>(),
          firestore: fakeFirestore,
        );
        sl.registerSingleton<FinancialAiRepository>(aiRepo);

        await tester.pumpWidget(const LifeOsApp());
        await tester.pumpAndSettle();

        await tester.tap(find.text('Tài chính'));
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const Key('open_financial_ai_assistant_btn')),
        );
        await tester.pumpAndSettle();

        expect(find.byType(FinancialAiAssistantPage), findsOneWidget);
      },
    );
  });
}
