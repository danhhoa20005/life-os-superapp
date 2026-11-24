import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_os/features/financial_ai/data/datasources/financial_ai_local_sync_datasource.dart';
import 'package:life_os/features/financial_ai/data/extraction/financial_entity_extractor.dart';
import 'package:life_os/features/financial_ai/data/inference/fake_financial_classifier.dart';
import 'package:life_os/features/financial_ai/data/inference/fasttext_classifier.dart';
import 'package:life_os/features/financial_ai/data/inference/rule_based_classifier.dart';
import 'package:life_os/features/financial_ai/data/inference/taxonomy_catalog.dart';
import 'package:life_os/features/financial_ai/data/normalization/financial_text_normalizer.dart';
import 'package:life_os/features/financial_ai/data/repositories/financial_ai_repository_impl.dart';
import 'package:life_os/features/financial_ai/domain/entities/financial_ai_entities.dart';
import 'package:life_os/features/transactions/data/datasources/transaction_remote_datasource.dart';
import 'package:life_os/features/transactions/data/repositories/transaction_repository_impl.dart';
import 'package:life_os/features/transactions/domain/entities/transaction_entities.dart';

void main() {
  final fixedRefTime = DateTime(2026, 11, 23, 14, 30); // Monday 23/11/2026
  final fixedClock = FixedFinancialClock(fixedRefTime);

  const testWallets = <WalletEntity>[
    WalletEntity(
      id: 'w_cash',
      ownerId: 'u_test',
      name: 'Ví tiền mặt',
      type: WalletType.cash,
      balanceMinor: 2500000,
    ),
    WalletEntity(
      id: 'w_mb',
      ownerId: 'u_test',
      name: 'MBBank',
      type: WalletType.bank,
      bankCode: 'MB',
      balanceMinor: 15000000,
    ),
    WalletEntity(
      id: 'w_vcb',
      ownerId: 'u_test',
      name: 'Vietcombank',
      type: WalletType.bank,
      bankCode: 'VCB',
      balanceMinor: 8200000,
    ),
  ];

  const testCategories = <CategoryEntity>[
    CategoryEntity(
      id: 'cat_food',
      ownerId: 'u_test',
      name: 'Ăn uống',
      direction: 'debit',
      iconKey: 'restaurant',
    ),
    CategoryEntity(
      id: 'cat_vehicle',
      ownerId: 'u_test',
      name: 'Xe cộ & Di chuyển',
      direction: 'debit',
      iconKey: 'directions_car',
    ),
    CategoryEntity(
      id: 'cat_health',
      ownerId: 'u_test',
      name: 'Sức khỏe & Giáo dục',
      direction: 'debit',
      iconKey: 'medical_services',
    ),
    CategoryEntity(
      id: 'cat_shopping',
      ownerId: 'u_test',
      name: 'Chợ & Mua sắm',
      direction: 'debit',
      iconKey: 'shopping_bag',
    ),
    CategoryEntity(
      id: 'cat_salary',
      ownerId: 'u_test',
      name: 'Lương & Thu nhập',
      direction: 'credit',
      iconKey: 'payments',
    ),
    CategoryEntity(
      id: 'cat_other_inc',
      ownerId: 'u_test',
      name: 'Thu nhập khác',
      direction: 'credit',
      iconKey: 'savings',
    ),
  ];

  Future<Uint8List> loadRealModelBytes(String assetPath) async {
    return File(assetPath).readAsBytes();
  }

  Future<String> loadRealMetaJson(String assetPath) async {
    return File(assetPath).readAsString();
  }

  group('Phase 4 — FinancialTextNormalizer Unit Tests', () {
    late FinancialTextNormalizer normalizer;

    setUp(() {
      normalizer = FinancialTextNormalizer(clock: fixedClock);
    });

    test('handles accented, unaccented, and common Vietnamese abbreviations', () {
      expect(
        normalizer.normalizeText('Ăn sáng hết 35 nghìn'),
        contains('35 nghìn'),
      );
      expect(
        normalizer.normalizeText('an sang het 35 nghin'),
        contains('35 nghin'),
      );
      expect(normalizer.normalizeText('cf 30k'), contains('cà phê'));
      expect(normalizer.normalizeText('ck 500k cho mẹ'), contains('chuyển khoản'));
      expect(normalizer.normalizeText('do xang 70k'), contains('xăng'));
      expect(normalizer.normalizeText('mua tai nghe tgdd 350k'), contains('thế giới di động'));
    });

    test('parses all monetary formats in exact integer minor units (zero floating point drift)', () {
      final cases = <(String input, int expectedMinor, String expectedCurrency, bool expectedAmbiguous)>[
        ('mua bánh 50k', 50000, 'VND', false),
        ('cà phê 50K', 50000, 'VND', false),
        ('ăn trưa 50 nghìn', 50000, 'VND', false),
        ('ăn tối 50 ngàn', 50000, 'VND', false),
        ('tiền nước 50.000', 50000, 'VND', false),
        ('tiền gửi xe 50,000đ', 50000, 'VND', false),
        ('mua áo 1tr', 1000000, 'VND', false),
        ('đóng học 1 triệu', 1000000, 'VND', false),
        ('mua giày 1tr5', 1500000, 'VND', false),
        ('mua sắm 1.5 triệu', 1500000, 'VND', false),
        ('mua sắm 1,5 triệu', 1500000, 'VND', false),
        ('sửa xe 2 triệu 300 nghìn', 2300000, 'VND', false),
        ('thanh toán 125000 VND', 125000, 'VND', false),
        ('nhận lương mười hai triệu', 12000000, 'VND', false),
        ('mua app \$12.50', 1250, 'USD', false),
        ('mua bánh 1.500', 1500, 'VND', true), // Ambiguous bare <10k separator!
      ];

      for (final (input, expectedMinor, expectedCurrency, expectedAmbiguous) in cases) {
        final normalized = normalizer.normalizeText(input);
        final amounts = normalizer.extractAmounts(normalized);
        expect(amounts, isNotEmpty, reason: 'Failed to parse amount in: "$input"');
        expect(amounts.first.amountMinor, expectedMinor, reason: 'Wrong minor amount for: "$input"');
        expect(amounts.first.currencyCode, expectedCurrency, reason: 'Wrong currency for: "$input"');
        expect(amounts.first.isAmbiguous, expectedAmbiguous, reason: 'Wrong ambiguity flag for: "$input"');
      }
    });

    test('resolves relative Vietnamese dates deterministically via FinancialClock', () {
      // Reference: Monday 2026-11-23 14:30
      final homNay = normalizer.extractRelativeDate('hôm nay ăn trưa 50k')!;
      expect(homNay.resolvedDateTime.year, 2026);
      expect(homNay.resolvedDateTime.month, 11);
      expect(homNay.resolvedDateTime.day, 23);

      final homQua = normalizer.extractRelativeDate('hôm qua mua đồ 300k')!;
      expect(homQua.resolvedDateTime.day, 22);

      final homKia = normalizer.extractRelativeDate('hôm kia đổ xăng 70k')!;
      expect(homKia.resolvedDateTime.day, 21);

      final sangNay = normalizer.extractRelativeDate('sáng nay uống cf 30k')!;
      expect(sangNay.resolvedDateTime.day, 23);
      expect(sangNay.resolvedDateTime.hour, 8);

      final toiQua = normalizer.extractRelativeDate('tối qua ăn lẩu 450k')!;
      expect(toiQua.resolvedDateTime.day, 22);
      expect(toiQua.resolvedDateTime.hour, 20);

      final ngay15 = normalizer.extractRelativeDate('ngày 15 đóng tiền nhà 4tr')!;
      expect(ngay15.resolvedDateTime.day, 15);
      expect(ngay15.resolvedDateTime.month, 11);

      final thuHaiTuanTruoc = normalizer.extractRelativeDate('thứ hai tuần trước mua sách 120k')!;
      expect(thuHaiTuanTruoc.resolvedDateTime.day, 16);
      expect(thuHaiTuanTruoc.resolvedDateTime.month, 11);

      final thangTruoc = normalizer.extractRelativeDate('tháng trước mua bàn phím 900k')!;
      expect(thangTruoc.resolvedDateTime.month, 10);
    });
  });

  group('Phase 9, 18.2 & 19 — Real Offline FastText Worker Isolate, 22 Mandatory Sentences & Benchmark', () {
    late FastTextClassifier realClassifier;
    late FinancialTextNormalizer normalizer;
    late FinancialEntityExtractor extractor;
    late FakeFirebaseFirestore fakeFirestore;
    late FinancialAiRepositoryImpl repository;

    setUpAll(() async {
      realClassifier = FastTextClassifier(
        bytesLoader: loadRealModelBytes,
        jsonLoader: loadRealMetaJson,
      );
      await realClassifier.initialize();
    });

    tearDownAll(() async {
      await realClassifier.dispose();
    });

    setUp(() async {
      normalizer = FinancialTextNormalizer(clock: fixedClock);
      extractor = FinancialEntityExtractor(normalizer);
      fakeFirestore = FakeFirebaseFirestore();
      final txRepo = TransactionRepositoryImpl(
        TransactionRemoteDataSource(fakeFirestore),
      );
      final localSync = FinancialAiLocalSyncDataSource(fakeFirestore);
      repository = FinancialAiRepositoryImpl(
        classifier: realClassifier,
        normalizer: normalizer,
        extractor: extractor,
        localSync: localSync,
        transactionRepository: txRepo,
        firestore: fakeFirestore,
      );
    });

    test('loads real quantized vn_financial_fasttext_v1.ftq inside Worker Isolate without fallback', () {
      final meta = realClassifier.metadata;
      expect(meta.usingRuleFallback, isFalse);
      expect(meta.numClasses, 30);
      expect(meta.sizeBytes, greaterThan(400000));
      expect(meta.sizeBytes, lessThan(1024 * 1024));
      expect(meta.sha256.length, 64);
    });

    test('degrades gracefully to RuleBasedClassifier when model file is missing or corrupted', () async {
      final missingClassifier = FastTextClassifier(
        bytesLoader: (_) async => throw StateError('Asset missing'),
        jsonLoader: (_) async => throw StateError('Meta missing'),
      );
      await missingClassifier.initialize();
      expect(missingClassifier.metadata.usingRuleFallback, isTrue);
      final missingRes = await missingClassifier.classify('đổ xăng petrolimex');
      expect(missingRes.topPrediction.semanticKey, 'transport.fuel');
      expect(
        missingRes.topPrediction.origin,
        ClassifierInferenceOrigin.deterministicRuleFallback,
      );
      await missingClassifier.dispose();

      final corruptClassifier = FastTextClassifier(
        bytesLoader: (_) async => Uint8List.fromList([0x01, 0x02, 0x03, 0x04, 0x05]),
        jsonLoader: (_) async => '{}',
      );
      await corruptClassifier.initialize();
      expect(corruptClassifier.metadata.usingRuleFallback, isTrue);
      final corruptRes = await corruptClassifier.classify('nhận lương tháng');
      expect(corruptRes.topPrediction.semanticKey, 'income.salary');
      await corruptClassifier.dispose();
    });

    test('FakeFinancialClassifier provides deterministic test-double behavior', () async {
      final fake = FakeFinancialClassifier(
        cannedResponses: {'bánh mì phượng': ('food.meals', 0.96)},
      );
      await fake.initialize();
      final r = await fake.classify('mua bánh mì phượng hội an');
      expect(r.topPrediction.semanticKey, 'food.meals');
      expect(r.topPrediction.probability, closeTo(0.96, 1e-6));
    });

    test('passes all 22 mandatory Vietnamese financial utterances + external transfer + OTP block', () async {
      Future<FinancialAnalysisResult> runAnalyze(String utterance) async {
        final res = await repository.analyzeText(
          userId: 'u_test',
          text: utterance,
          source: FinancialInputSource.manualText,
          preferredWalletId: 'w_cash',
          referenceTime: fixedRefTime,
          knownWallets: testWallets,
          knownCategories: testCategories,
        );
        return res.fold<FinancialAnalysisResult>(
          (f) => fail('Unexpected failure for "$utterance": ${f.message}'),
          (v) => v,
        );
      }

      // 1. an sang 35k
      final r1 = await runAnalyze('an sang 35k');
      expect(r1.candidates.length, 1);
      expect(r1.candidates.single.transactionType, FinancialTransactionType.expense);
      expect(r1.candidates.single.amountMinor, 35000);
      expect(r1.candidates.single.topPrediction.semanticKey, startsWith('food.'));
      expect(r1.candidates.single.resolvedCategoryId, 'cat_food');
      expect(r1.request.originalText, 'an sang 35k');

      // 2. ăn sáng 35 nghìn
      final r2 = await runAnalyze('ăn sáng 35 nghìn');
      expect(r2.candidates.single.amountMinor, 35000);
      expect(r2.candidates.single.topPrediction.semanticKey, startsWith('food.'));

      // 3. cafe 25k
      final r3 = await runAnalyze('cafe 25k');
      expect(r3.candidates.single.amountMinor, 25000);
      expect(r3.candidates.single.topPrediction.semanticKey, 'food.drinks');

      // 4. cf 30k
      final r4 = await runAnalyze('cf 30k');
      expect(r4.candidates.single.amountMinor, 30000);
      expect(r4.candidates.single.topPrediction.semanticKey, 'food.drinks');

      // 5. do xang 70k
      final r5 = await runAnalyze('do xang 70k');
      expect(r5.candidates.single.amountMinor, 70000);
      expect(r5.candidates.single.topPrediction.semanticKey, 'transport.fuel');
      expect(r5.candidates.single.resolvedCategoryId, 'cat_vehicle');

      // 6. đổ xăng 70 nghìn
      final r6 = await runAnalyze('đổ xăng 70 nghìn');
      expect(r6.candidates.single.amountMinor, 70000);
      expect(r6.candidates.single.topPrediction.semanticKey, 'transport.fuel');

      // 7. mua thuốc 120k
      final r7 = await runAnalyze('mua thuốc 120k');
      expect(r7.candidates.single.amountMinor, 120000);
      expect(r7.candidates.single.topPrediction.semanticKey, startsWith('health.'));
      expect(r7.candidates.single.resolvedCategoryId, 'cat_health');

      // 8. nhận lương 12tr
      final r8 = await runAnalyze('nhận lương 12tr');
      expect(r8.candidates.single.transactionType, FinancialTransactionType.income);
      expect(r8.candidates.single.amountMinor, 12000000);
      expect(r8.candidates.single.topPrediction.semanticKey, 'income.salary');
      expect(r8.candidates.single.resolvedCategoryId, 'cat_salary');

      // 9. thưởng 500k
      final r9 = await runAnalyze('thưởng 500k');
      expect(r9.candidates.single.transactionType, FinancialTransactionType.income);
      expect(r9.candidates.single.amountMinor, 500000);
      expect(r9.candidates.single.topPrediction.semanticKey, 'income.bonus');

      // 10. mua sắm 1tr5
      final r10 = await runAnalyze('mua sắm 1tr5');
      expect(r10.candidates.single.transactionType, FinancialTransactionType.expense);
      expect(r10.candidates.single.amountMinor, 1500000);
      expect(r10.candidates.single.topPrediction.semanticKey, startsWith('shopping.'));
      expect(r10.candidates.single.resolvedCategoryId, 'cat_shopping');

      // 11. đi taxi 85k
      final r11 = await runAnalyze('đi taxi 85k');
      expect(r11.candidates.single.amountMinor, 85000);
      expect(r11.candidates.single.topPrediction.semanticKey, 'transport.ride_hailing');

      // 12. hôm qua mua đồ 300k
      final r12 = await runAnalyze('hôm qua mua đồ 300k');
      expect(r12.candidates.single.amountMinor, 300000);
      expect(r12.candidates.single.hasExplicitDate, isTrue);
      expect(r12.candidates.single.occurredAt.day, 22);

      // 13. chi 50k ăn trưa
      final r13 = await runAnalyze('chi 50k ăn trưa');
      expect(r13.candidates.single.transactionType, FinancialTransactionType.expense);
      expect(r13.candidates.single.amountMinor, 50000);
      expect(r13.candidates.single.topPrediction.semanticKey, startsWith('food.'));

      // 14. nhận 200k từ bạn
      final r14 = await runAnalyze('nhận 200k từ bạn');
      expect(r14.candidates.single.transactionType.expectedDirection, 'credit');
      expect(r14.candidates.single.amountMinor, 200000);

      // 15. chuyển 2tr từ MB sang VCB của tôi -> internalTransfer
      final r15 = await runAnalyze('chuyển 2tr từ MB sang VCB của tôi');
      expect(r15.candidates.single.transactionType, FinancialTransactionType.internalTransfer);
      expect(r15.candidates.single.amountMinor, 2000000);
      expect(r15.candidates.single.sourceWalletId, 'w_mb');
      expect(r15.candidates.single.destinationWalletId, 'w_vcb');

      // 16. rút ATM 500k -> internalTransfer (Bank -> Cash)
      final r16 = await runAnalyze('rút ATM 500k');
      expect(r16.candidates.single.transactionType, FinancialTransactionType.internalTransfer);
      expect(r16.candidates.single.amountMinor, 500000);
      expect(r16.candidates.single.destinationWalletId, 'w_cash');

      // 17. shop hoàn tiền 120k -> refund
      final r17 = await runAnalyze('shop hoàn tiền 120k');
      expect(r17.candidates.single.transactionType, FinancialTransactionType.refund);
      expect(r17.candidates.single.amountMinor, 120000);

      // 18. mua sách 150k và uống nước 25k -> 2 separate drafts!
      final r18 = await runAnalyze('mua sách 150k và uống nước 25k');
      expect(r18.candidates.length, 2);
      expect(r18.candidates[0].amountMinor, 150000);
      expect(r18.candidates[1].amountMinor, 25000);
      expect(r18.requiresConfirmation, isTrue);

      // 19. chiều nay ăn 45k đổ xăng 70k -> 2 separate drafts without conjunction!
      final r19 = await runAnalyze('chiều nay ăn 45k đổ xăng 70k');
      expect(r19.candidates.length, 2);
      expect(r19.candidates[0].amountMinor, 45000);
      expect(r19.candidates[1].amountMinor, 70000);
      expect(r19.requiresConfirmation, isTrue);

      // 20. còn 2 triệu trong tài khoản -> NON-TRANSACTION (0 drafts!)
      final r20 = await runAnalyze('còn 2 triệu trong tài khoản');
      expect(r20.candidates, isEmpty);
      expect(r20.nonTransactionReason, isNotNull);

      // 21. tôi không mua gì hôm nay -> NON-TRANSACTION (0 drafts!)
      final r21 = await runAnalyze('tôi không mua gì hôm nay');
      expect(r21.candidates, isEmpty);
      expect(r21.nonTransactionReason, isNotNull);

      // 22. hủy giao dịch 100k vừa nhập -> NON-TRANSACTION (0 drafts!)
      final r22 = await runAnalyze('hủy giao dịch 100k vừa nhập');
      expect(r22.candidates, isEmpty);
      expect(r22.nonTransactionReason, isNotNull);

      // Extra Phase 6 check: externalTransfer vs internalTransfer
      final rExt = await runAnalyze('Chuyển 500k cho mẹ');
      expect(rExt.candidates.single.transactionType, FinancialTransactionType.externalTransfer);
      expect(rExt.candidates.single.amountMinor, 500000);

      // Extra Phase 17 check: OTP / secret message must NEVER create a transaction
      final rOtp = await runAnalyze('Mã OTP xác thực giao dịch 500k của bạn là 482910');
      expect(rOtp.candidates, isEmpty);
    });

    test('never invents fake categoryId when user categories do not contain predicted group', () {
      const sparseUserCategories = <CategoryEntity>[
        CategoryEntity(
          id: 'cat_only_food',
          ownerId: 'u_test',
          name: 'Ăn uống',
          direction: 'debit',
          iconKey: 'restaurant',
        ),
      ];
      final resolved = FinancialTaxonomyCatalog.resolveAgainstUserCategories(
        semanticKey: 'education',
        direction: 'debit',
        userCategories: sparseUserCategories,
      );
      expect(resolved.categoryId, isNull);
      expect(resolved.hasExactUserCategory, isFalse);
      expect(resolved.suggestedCategoryName, isNotEmpty);
    });

    test('executes comparative Dart Worker Isolate benchmark (Rule vs FastText vs Personalized)', () async {
      // Measure cold-start of a fresh FastTextClassifier Worker Isolate
      final coldSw = Stopwatch()..start();
      final freshClassifier = FastTextClassifier(
        bytesLoader: loadRealModelBytes,
        jsonLoader: loadRealMetaJson,
      );
      await freshClassifier.initialize();
      coldSw.stop();
      final coldStartMs = coldSw.elapsedMicroseconds / 1000.0;

      final ruleOnly = RuleBasedClassifier();
      await ruleOnly.initialize();

      // 20 realistic Vietnamese expressions across the 30-label taxonomy
      const evalSamples = <(String text, String expectedPrefix)>[
        ('phở thìn lò đúc', 'food.meals'),
        ('trà đào cam sả the coffee house', 'food.drinks'),
        ('đổ đầy bình ron 95', 'transport.fuel'),
        ('cuốc xe xanh sm đi sân bay', 'transport.ride_hailing'),
        ('thay nhớt motul xe tay ga', 'transport.maintenance'),
        ('đi chợ mua thịt heo rau cải', 'food.groceries'),
        ('thanh toán hóa đơn điện lực miền nam', 'housing.utilities'),
        ('gia hạn gói cước cáp quang viettel', 'housing.utilities'),
        ('đóng tiền thuê căn hộ tháng 11', 'housing.rent'),
        ('mua vitamin tổng hợp pharmacity', 'health.medicine'),
        ('khám răng nha khoa paris', 'health.hospital'),
        ('đặt đơn hàng lazada mall', 'shopping.'),
        ('mua tai nghe bluetooth anker', 'shopping.electronics'),
        ('mua vé xem phim cgv cuối tuần', 'entertainment'),
        ('gia hạn gói youtube premium', 'subscriptions'),
        ('đăng ký khóa luyện thi toeic', 'education'),
        ('mừng đám cưới đồng nghiệp công ty', 'gifts'),
        ('tiền lương chuyển khoản tháng 11', 'income.salary'),
        ('thưởng hoàn thành dự án quý 4', 'income.bonus'),
        ('tiền thanh toán dự án thiết kế web ngoài giờ', 'income.freelance'),
      ];

      var ruleCorrect = 0;
      var fastTextCorrect = 0;
      final warmLatenciesMicros = <int>[];

      // Warm-up 5 iterations
      for (var i = 0; i < 5; i++) {
        await freshClassifier.classify(normalizer.toClassifierInput(evalSamples[i].$1));
      }

      for (var pass = 0; pass < 5; pass++) {
        for (final (raw, expectedPrefix) in evalSamples) {
          final norm = normalizer.toClassifierInput(raw);
          if (pass == 0) {
            final rRes = await ruleOnly.classify(norm);
            if (rRes.topPrediction.semanticKey.startsWith(expectedPrefix)) {
              ruleCorrect++;
            }
          }
          final sw = Stopwatch()..start();
          final ftRes = await freshClassifier.classify(norm);
          sw.stop();
          warmLatenciesMicros.add(sw.elapsedMicroseconds);
          if (pass == 0 &&
              ftRes.topPrediction.semanticKey.startsWith(expectedPrefix)) {
            fastTextCorrect++;
          }
        }
      }

      await freshClassifier.dispose();

      warmLatenciesMicros.sort();
      final p50Ms = warmLatenciesMicros[warmLatenciesMicros.length ~/ 2] / 1000.0;
      final p95Ms =
          warmLatenciesMicros[(warmLatenciesMicros.length * 95) ~/ 100] / 1000.0;

      // Also test Personalization boost on ambiguous convenience-store merchant ("Circle K")
      await repository.saveCategoryCorrection(
        userId: 'u_test',
        merchantDisplay: 'Circle K',
        merchantCanonicalKey: 'circle k',
        selectedCategoryId: 'cat_food',
        selectedCategoryName: 'Ăn uống',
        semanticKey: 'food.meals',
      );
      final personalizedRes = await repository.analyzeText(
        userId: 'u_test',
        text: 'Circle K 45.000đ',
        knownWallets: testWallets,
        knownCategories: testCategories,
      );
      final personalizedCand = personalizedRes.fold<TransactionCandidate>(
        (f) => fail(f.message),
        (v) => v.candidates.single,
      );
      expect(personalizedCand.resolvedCategoryId, 'cat_food');
      expect(
        personalizedCand.topPrediction.origin,
        ClassifierInferenceOrigin.personalizationRule,
      );

      final report = <String, Object>{
        'measuredOn': 'Dart VM Worker Isolate (Windows x64 Host)',
        'coldStartMs': double.parse(coldStartMs.toStringAsFixed(3)),
        'warmIsolateRoundtripP50Ms': double.parse(p50Ms.toStringAsFixed(4)),
        'warmIsolateRoundtripP95Ms': double.parse(p95Ms.toStringAsFixed(4)),
        'totalWarmIterations': warmLatenciesMicros.length,
        'colloquialSuiteSize': evalSamples.length,
        'ruleOnlySuiteAccuracy': double.parse(
          (ruleCorrect / evalSamples.length).toStringAsFixed(4),
        ),
        'rulePlusFastTextSuiteAccuracy': double.parse(
          (fastTextCorrect / evalSamples.length).toStringAsFixed(4),
        ),
      };

      final outFile = File('tools/financial_ai/artifacts/dart_runtime_benchmark.json');
      outFile.parent.createSync(recursive: true);
      outFile.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));

      expect(coldStartMs, lessThan(2000.0));
      expect(p95Ms, lessThan(25.0));
      expect(fastTextCorrect, greaterThanOrEqualTo(ruleCorrect));
    });
  });
}
