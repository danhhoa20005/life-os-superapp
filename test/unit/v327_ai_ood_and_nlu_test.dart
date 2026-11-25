import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_os/core/utils/smart_money_split_ai_engine.dart';
import 'package:life_os/core/utils/smart_omni_intent_parser.dart';
import 'package:life_os/core/utils/voice_financial_nlp_engine.dart';
import 'package:life_os/features/financial_ai/data/datasources/financial_ai_local_sync_datasource.dart';
import 'package:life_os/features/financial_ai/data/extraction/financial_entity_extractor.dart';
import 'package:life_os/features/financial_ai/data/inference/fasttext_binary_model.dart';
import 'package:life_os/features/financial_ai/data/inference/fasttext_classifier.dart';
import 'package:life_os/features/financial_ai/data/inference/taxonomy_catalog.dart';
import 'package:life_os/features/financial_ai/data/normalization/financial_text_normalizer.dart';
import 'package:life_os/features/financial_ai/data/personalization/confidence_policy_engine.dart';
import 'package:life_os/features/financial_ai/data/repositories/financial_ai_repository_impl.dart';
import 'package:life_os/features/financial_ai/domain/entities/financial_ai_entities.dart';
import 'package:life_os/features/transactions/data/datasources/transaction_remote_datasource.dart';
import 'package:life_os/features/transactions/data/repositories/transaction_repository_impl.dart';
import 'package:life_os/features/transactions/domain/entities/transaction_entities.dart';

void main() {
  late Uint8List finModelBytes;
  late String finMetaJson;
  late Map<String, dynamic> finMetaMap;
  late FastTextBinaryModel finBinaryModel;

  late Uint8List splitModelBytes;
  late String splitMetaJson;
  late Map<String, dynamic> splitMetaMap;
  late FastTextBinaryModel splitBinaryModel;

  late FinancialTextNormalizer normalizer;

  final fixedNow = DateTime(2026, 11, 25, 10, 0);

  setUpAll(() {
    finModelBytes = File(
      'assets/models/vn_financial_fasttext_v1.ftq',
    ).readAsBytesSync();
    finMetaJson = File(
      'assets/models/vn_financial_fasttext_v1_meta.json',
    ).readAsStringSync();
    finMetaMap = jsonDecode(finMetaJson) as Map<String, dynamic>;
    finBinaryModel = FastTextBinaryModel.parseAndVerify(
      finModelBytes,
      expectedSha256: finMetaMap['sha256'] as String,
    );

    splitModelBytes = File(
      SmartMoneySplitAiEngine.modelAssetPath,
    ).readAsBytesSync();
    splitMetaJson = File(
      SmartMoneySplitAiEngine.metadataAssetPath,
    ).readAsStringSync();
    splitMetaMap = jsonDecode(splitMetaJson) as Map<String, dynamic>;
    splitBinaryModel = FastTextBinaryModel.parseAndVerify(
      splitModelBytes,
      expectedSha256: splitMetaMap['sha256'] as String,
    );

    normalizer = FinancialTextNormalizer(clock: FixedFinancialClock(fixedNow));
  });

  group('1. Explicit __ood__ Binary Contract & Calibration Sanity', () {
    test('verifies LFTQ v1 headers, SHA-256, explicit __ood__ class, positive OOD bias, and T* >= 0.85', () {
      expect(finBinaryModel.hasExplicitOodClass, isTrue);
      expect(finBinaryModel.numClasses, 30);
      expect(finBinaryModel.totalClasses, 31);
      expect(finBinaryModel.labels.last, CategoryPrediction.oodSemanticKey);
      expect(finBinaryModel.temperature, greaterThanOrEqualTo(0.85));
      expect(finModelBytes.length, lessThan(1024 * 1024));

      final finOodBias = finBinaryModel.biasB[finBinaryModel.oodClassIndex];
      expect(finOodBias, greaterThan(0.0));

      expect(splitBinaryModel.hasExplicitOodClass, isTrue);
      expect(splitBinaryModel.numClasses, 12);
      expect(splitBinaryModel.totalClasses, 13);
      expect(splitBinaryModel.labels.last, CategoryPrediction.oodSemanticKey);
      expect(splitBinaryModel.temperature, greaterThanOrEqualTo(0.85));
      expect(splitModelBytes.length, lessThan(450 * 1024));

      final splitOodBias =
          splitBinaryModel.biasB[splitBinaryModel.oodClassIndex];
      expect(splitOodBias, greaterThan(0.0));
    });

    test('never maps __ood__ onto "other" in TaxonomyCatalog or ConfidencePolicyEngine', () {
      final oodSpec = FinancialTaxonomyCatalog.bySemanticKey(
        CategoryPrediction.oodSemanticKey,
      );
      expect(oodSpec.semanticKey, CategoryPrediction.oodSemanticKey);
      expect(oodSpec.direction, 'unknown');

      final resolved = FinancialTaxonomyCatalog.resolveAgainstUserCategories(
        semanticKey: CategoryPrediction.oodSemanticKey,
        direction: 'debit',
        userCategories: const [
          CategoryEntity(
            id: 'cat_other_exp',
            ownerId: 'u_1',
            name: 'Chi tiêu khác',
            direction: 'debit',
            iconKey: 'category',
          ),
        ],
      );
      expect(resolved.categoryId, isNull);
      expect(resolved.hasExactUserCategory, isFalse);

      const dummyEntity = ExtractedFinancialEntity(
        rawSegment: 'xyz 50k',
        normalizedSegment: 'xyz 50k',
        classifierInput: 'xyz',
        amountMinor: 50000,
        transactionType: FinancialTransactionType.expense,
        description: 'Xyz',
        amountConfidence: 0.95,
        typeConfidence: 0.90,
        merchantConfidence: 0.45,
      );
      final conf = ConfidencePolicyEngine.evaluate(
        extracted: dummyEntity,
        topPrediction: const CategoryPrediction(
          semanticKey: CategoryPrediction.oodSemanticKey,
          suggestedDisplayName: 'Ngoài phạm vi tài chính (OOD)',
          probability: 0.88,
          origin: ClassifierInferenceOrigin.fastTextIsolateInt8,
        ),
        source: FinancialInputSource.manualText,
        modelMeta: const FinancialModelMetadata(
          modelId: 'vn_financial_fasttext_v1',
          modelVersion: '3.0.0',
          architecture: 'FastText',
          sizeBytes: 1000,
          sha256: 'abc',
          numClasses: 30,
          totalOutputClasses: 31,
        ),
        hasValidSourceWallet: true,
        hasValidDestinationWalletIfTransfer: true,
        hasResolvedUserCategory: false,
        isDuplicateCandidate: false,
        allFlags: const [],
        oodProbability: 0.88,
      );
      expect(conf.tier, ConfidenceTier.unknown);
      expect(conf.canAutoPostUnderPolicy, isFalse);
      expect(conf.categoryConfidence, 0.0);
    });
  });

  group('2. Financial AI — >=95% Runtime OOD Rejection (64 Unseen Multi-Stratum Prompts) & 0% False Auto-Assign', () {
    test('rejects >=95% of 64 unseen multi-stratum OOD prompts in FastTextClassifier & classifies ID inputs accurately', () async {
      final classifier = FastTextClassifier(
        bytesLoader: (_) async => finModelBytes,
        jsonLoader: (_) async => finMetaJson,
      );
      await classifier.initialize();
      addTearDown(classifier.dispose);

      expect(classifier.metadata.usingRuleFallback, isFalse);
      expect(classifier.metadata.numClasses, 30);
      expect(classifier.metadata.totalOutputClasses, 31);

      const unseenOodPrompts = <String>[
        // Stratum (a): chatter, weather, traffic, greetings, tricky homonyms (16)
        'kẹt xe đoạn lê văn lương kéo dài cả tiếng',
        'ngoài ngã tư nguyễn xiển đang ùn tắc giao thông',
        'cả phòng nghỉ giải lao mười lăm phút uống nước',
        'alo đầu dây bên kia tín hiệu yếu quá',
        'sáng nào cũng uống hai ly nước lọc ấm',
        'bé nhà mình ăn nói lễ phép ai cũng khen',
        'cuối tuần rủ nhóm chạy bộ quanh công viên',
        'tối nay anh em tụ tập xem bóng đá ngoại hạng',
        'bác lương cạnh nhà vừa đi du lịch về',
        'du bao thoi tiet thu do ngay mai nang nhe',
        'ket xe ngoai nga tu den do lau qua',
        'nghi giai lao giua buoi chieu cho do moi',
        'chuc ca nha buoi toi ngu ngon giac',
        'chieu nay troi nhieu may gio mat de chiu',
        'cau thu tien ve ghi ban phut cuoi tran',
        'ngoi ban tra tien sanh cho khach den',
        // Stratum (b): non-financial LifeOS commands (16)
        'tạo lịch họp thiết kế sprint lúc 14 giờ chiều mai',
        'đặt báo thức 5 giờ 30 sáng mai đi tập thể dục',
        'nhắc uống 2 viên kẽm và vitamin sau bữa tối',
        'ghi nhật ký uống 350ml nước lọc buổi trưa',
        'cập nhật odo xe air blade đạt 22.000 km',
        'danh sách đi chợ cần mua gừng sả ớt tỏi hành',
        'ghi chú ý tưởng cải tiến giao diện biểu đồ',
        'nhắc khóa van gas trước lúc đi công tác',
        'dat bao thuc bay gio kem muoi lam sang',
        'nhac uong thuoc bo mat luc tam gio toi',
        'uong bon tram ml nuoc tinh khiet sau tap',
        'cap nhat cong to met xe vision 16000 km',
        'tao lich hen kham rang chieu thu sau',
        'ghi chu danh sach do dung can mang theo',
        'nhac goi dien hoi tham ba ngoai toi nay',
        'dat lich hop phong ky thuat sang thu tu',
        // Stratum (c): English, mixed slang, gibberish, code, short fragments (16)
        'hello everyone wish you a productive week ahead',
        'could you please forward the presentation deck',
        'ok bro check slack giùm mình nhánh hotfix nhé',
        'deploy bản mới lên server test xong hết rồi',
        'tyuiop ghjklm vbnmxc qazwsx',
        'blabla wibble wobble flubber',
        'for row in rows: total += row.count',
        'SELECT user_id, created_at FROM sessions LIMIT 10',
        'git rebase --abort && git status',
        'chào buổi sáng nhé',
        'cảm ơn bạn rất nhiều',
        'vâng mình hiểu rồi',
        'tạm biệt hẹn tuần sau',
        'alo nghe rõ không',
        '12345 67890',
        '!!!',
        // Stratum (d): negated, hypothetical, balance inquiry, OTP/PIN (16)
        'đừng ghi khoản ăn tối 150k vừa nói nhé',
        'không lưu giao dịch mua sách 90k này vào sổ',
        'hủy giao dịch chuyển khoản 500k vừa tạo nhầm',
        'tôi định mua chiếc xe máy điện 28 triệu',
        'nếu mua điện thoại mới 18 triệu thì có nên không',
        'dự định tháng sau đổi máy giặt tầm 10 triệu',
        'số dư tài khoản ngân hàng còn lại bao nhiêu',
        'trong ví tiền mặt hiện còn 2 triệu rưỡi',
        'tổng chi tiêu tuần này của mình bao nhiêu rồi',
        'mã OTP là 482910 tuyệt đối không chia sẻ',
        'mã xác thực OTP giao dịch 300k là 918273',
        'mã PIN thẻ tín dụng mới là 384920',
        'dung ghi khoan uong tra sua 45k nay nhe',
        'toi khong chi tieu khoan nao hom nay ca',
        'so du trong the atm hien con bao nhieu',
        'ma pin xac nhan dang nhap cua ban la 748291',
      ];

      var rejected = 0;
      var falseAutoAssign = 0;
      final missed = <String>[];

      for (final prompt in unseenOodPrompts) {
        final norm = normalizer.toClassifierInput(prompt);
        final res = await classifier.classify(norm);
        if (res.isOutOfDomain) {
          rejected++;
        } else {
          missed.add('$prompt -> ${res.topPrediction.semanticKey} (${res.topPrediction.probability.toStringAsFixed(3)})');
          if (res.topPrediction.probability >= classifier.metadata.highConfidenceThreshold) {
            falseAutoAssign++;
          }
        }
      }

      final rejectionRate = rejected / unseenOodPrompts.length;
      expect(
        rejectionRate,
        greaterThanOrEqualTo(0.95),
        reason: 'Missed OOD prompts (${missed.length}): ${missed.join(' | ')}',
      );
      expect(falseAutoAssign, equals(0));

      // Verify genuine Vietnamese expense/income inputs classify accurately and are NOT rejected
      const inDomainCases = <(String input, String expectedLabel)>[
        ('ăn sáng bún bò huế 55k', 'food.meals'),
        ('uống cà phê muối 35k', 'food.drinks'),
        ('đi chợ mua thịt heo rau củ 180k', 'food.groceries'),
        ('đổ xăng petrolimex 70k', 'transport.fuel'),
        ('gọi taxi xanh sm ra sân bay 180k', 'transport.ride_hailing'),
        ('thay nhớt xe máy honda vision 150k', 'transport.maintenance'),
        ('thanh toán tiền điện evn 920k', 'housing.utilities'),
        ('mua thuốc cảm cúm nhà thuốc long châu 95k', 'health.medicine'),
        ('nhận lương chính thức tháng 11 22tr', 'income.salary'),
        ('nhận tiền thưởng đạt kpi quý 5tr', 'income.bonus'),
      ];

      for (final (raw, expectedLabel) in inDomainCases) {
        final res = await classifier.classify(normalizer.toClassifierInput(raw));
        expect(
          res.isOutOfDomain,
          isFalse,
          reason: 'Valid input "$raw" falsely rejected as OOD (oodProb=${res.oodProbability})',
        );
        expect(res.topPrediction.semanticKey, expectedLabel);
        expect(res.topPrediction.probability, greaterThanOrEqualTo(0.52));
      }
    });

    test('FinancialAiRepositoryImpl blocks non-transactions and guards any OOD classifier output as unknown', () async {
      final firestore = FakeFirebaseFirestore();
      final classifier = FastTextClassifier(
        bytesLoader: (_) async => finModelBytes,
        jsonLoader: (_) async => finMetaJson,
      );
      await classifier.initialize();
      addTearDown(classifier.dispose);

      final repo = FinancialAiRepositoryImpl(
        classifier: classifier,
        normalizer: normalizer,
        extractor: FinancialEntityExtractor(normalizer),
        localSync: FinancialAiLocalSyncDataSource(firestore),
        transactionRepository: TransactionRepositoryImpl(
          TransactionRemoteDataSource(firestore),
        ),
        firestore: firestore,
      );

      for (final blockedInput in const [
        'đừng ghi khoản ăn trưa 50k',
        'tôi định mua xe 30 triệu',
        'số dư còn 2 triệu trong tài khoản',
        'mã OTP xác thực là 482910',
      ]) {
        final res = await repo.analyzeText(
          userId: 'u_ood_check',
          text: blockedInput,
          referenceTime: fixedNow,
        );
        res.fold(
          (f) => fail('Unexpected failure for "$blockedInput": ${f.message}'),
          (analysis) {
            expect(analysis.candidates, isEmpty, reason: blockedInput);
            expect(analysis.nonTransactionReason, isNotNull);
          },
        );
      }

      // Unrecognized gibberish even with a monetary token must NEVER map to 'other' or auto-post!
      final gibRes = await repo.analyzeText(
        userId: 'u_ood_check',
        text: 'zxcvbnm qwerty 50k',
        referenceTime: fixedNow,
        knownWallets: const [
          WalletEntity(
            id: 'w_cash',
            ownerId: 'u_ood_check',
            name: 'Tiền mặt',
            type: WalletType.cash,
            balanceMinor: 500000,
          ),
        ],
        knownCategories: const [
          CategoryEntity(
            id: 'cat_other_exp',
            ownerId: 'u_ood_check',
            name: 'Chi tiêu khác',
            direction: 'debit',
            iconKey: 'category',
          ),
        ],
      );
      gibRes.fold(
        (f) => fail(f.message),
        (analysis) {
          expect(analysis.candidates.length, 1);
          final cand = analysis.candidates.single;
          expect(cand.topPrediction.semanticKey, CategoryPrediction.oodSemanticKey);
          expect(cand.resolvedCategoryId, isNull);
          expect(cand.confidence.tier, ConfidenceTier.unknown);
          expect(cand.confidence.canAutoPostUnderPolicy, isFalse);
          expect(cand.requiresConfirmation, isTrue);
        },
      );
    });
  });

  group('3. Money Split AI — >=95% OOD & Near-OOD Rejection (64 Prompts) + Split/Alloc Accuracy', () {
    test('rejects >=95% of 64 unseen chatter + single-person transaction near-OOD prompts', () {
      const splitOodPrompts = <String>[
        // Chatter, weather, homonyms, LifeOS, English, gibberish, OTP (40)
        'kẹt xe ngoài ngã tư kéo dài suốt hai mươi phút',
        'hôm nay thời tiết nắng dịu mát mẻ quá',
        'cả phòng nghỉ giải lao uống nước lọc nhé',
        'pin laptop còn đúng bốn mươi phần trăm thôi',
        'sắp xếp sáu lọ gia vị thủy tinh lên kệ bếp',
        'chia sẻ slide thuyết trình lên nhóm lớp học',
        'trả lời tin nhắn khách hàng trên hộp thư',
        'chúc mọi người cuối tuần nghỉ ngơi vui vẻ',
        'alo đầu dây bên kia nghe rõ tiếng không',
        'chạy bộ năm vòng quanh hồ buổi sáng sớm',
        'đặt lịch họp nhóm lúc mười giờ sáng thứ ba',
        'hẹn báo thức năm giờ bốn mươi lăm sáng mai',
        'nhắc uống hai viên vitamin tổng hợp sau ăn',
        'đã uống bốn trăm ml nước lọc tinh khiết',
        'cập nhật odo xe máy vision đạt mười lăm nghìn km',
        'danh sách đi chợ mua hành ngò cà chua tỏi ớt',
        'ghi chú cần kiểm tra lại báo cáo cuối ngày',
        'nhắc tắt bình nóng lạnh trước khi đi ngủ',
        'good morning team let us start our daily standup',
        'please share the google meet link before nine',
        'ok bro check pull request giúp mình nhé',
        'deploy hotfix xong rồi mọi người yên tâm',
        'qwerty asdfgh zxcvbn poiuyt',
        'blabla wibble wobble snickerdoodle',
        'SELECT id, status FROM budgets WHERE active = 1',
        'git commit -m update offline evaluation script',
        'chào ngày mới tốt lành',
        'cảm ơn nhiều nha',
        'được rồi nhé',
        'đừng ghi khoản ăn tối 150k vừa rồi',
        'không lưu giao dịch nháp này vào sổ',
        'tôi định mua chiếc xe đạp 12 triệu',
        'nếu mua điện thoại mới 15tr có ổn không',
        'số dư tài khoản ngân hàng còn bao nhiêu',
        'hiện còn 3 triệu trong ví tiền mặt',
        'mã OTP xác thực giao dịch là 482910',
        'mã PIN thẻ ngân hàng của bạn là 618293',
        'ket xe ngoai nga tu gio tan tam',
        'thoi tiet chieu nay troi mat me de chiu',
        'dat bao thuc sau gio sang mai di lam',
        // Hard near-OOD single-person transactions (NOT group splits or allocation!) (24)
        'chuyển khoản 2 triệu cho mẹ',
        'nhận lương tháng này 20 triệu',
        'ăn phở bò 55k',
        'đổ xăng 70k',
        'mua thuốc cảm cúm nhà thuốc long châu 95k',
        'uống cà phê sữa đá highlands 55k',
        'rút tiền mặt cây atm 1 triệu',
        'chuyển 4 triệu từ techcombank sang sổ tiết kiệm online',
        'đóng tiền điện tháng 11 evn 890k',
        'mua áo sơ mi uniqlo 499k',
        'đi taxi xanh sm ra sân bay 180k',
        'gia hạn thuê bao spotify duo tháng này 75k',
        'thay nhớt xe máy honda vision 150k',
        'đóng tiền thuê phòng trọ tháng này 3tr5',
        'mua sách kỹ năng ở nhà sách fahasa 140k',
        'nhận tiền thưởng hoàn thành dự án 5 triệu',
        'chuyen khoan 2 trieu cho me',
        'nhan luong thang nay 20 trieu',
        'an pho bo 55k',
        'do xang 70k',
        'mua thuoc cam 85k',
        'dong tien mang internet fpt 250k',
        'di cho mua rau thit nau com 160k',
        'thanh toan phi thuong nien the visa 499k',
      ];

      final th = splitMetaMap['thresholds'] as Map<String, dynamic>;
      final oodRejectTh = (th['oodReject'] as num).toDouble();
      final lowTh = (th['lowConfidence'] as num).toDouble();
      final highTh = (th['highConfidence'] as num).toDouble();

      var rejected = 0;
      var falseAutoAssign = 0;
      final missed = <String>[];

      for (final prompt in splitOodPrompts) {
        final norm = normalizer.toClassifierInput(prompt);
        final probs = splitBinaryModel.evaluateProbsFromBuckets(
          splitBinaryModel.extractFeatureBuckets(norm),
        );
        final isOod = splitBinaryModel.isRejectedAsOod(
          probs,
          oodRejectThreshold: oodRejectTh,
          lowConfidenceThreshold: lowTh,
        );
        if (isOod) {
          rejected++;
        } else {
          final best = splitBinaryModel.bestInDomainFrom(probs);
          missed.add('$prompt -> ${best.label} (${best.probability.toStringAsFixed(3)})');
          if (best.probability >= highTh) {
            falseAutoAssign++;
          }
        }
      }

      expect(
        rejected / splitOodPrompts.length,
        greaterThanOrEqualTo(0.95),
        reason: 'Missed Money Split OOD (${missed.length}): ${missed.join(' | ')}',
      );
      expect(falseAutoAssign, equals(0));

      // Verify real split & allocation intents are NOT rejected and classify accurately
      const splitIdCases = <(String utterance, String expectedLabel)>[
        ('Ăn lẩu bò 600k chia đều 4 người', 'split.equal'),
        ('Tiền điện 900k Hòa 60 phần trăm Minh 40 phần trăm', 'split.percentage'),
        ('Đi ăn hải sản 1tr4 nhà Hòa 2 suất Nam 1 suất Lan 1 suất', 'split.shares_ratio'),
        ('Ăn trưa 320k Minh uống thêm cà phê 40k còn lại 4 người chia đều', 'split.itemized_remainder'),
        ('Tiền đi chợ 500k Hòa 200k Minh 180k còn lại Lan chịu', 'split.exact_custom'),
        ('Siêu thị WinMart 580k gồm thực phẩm 400k việc nhà 180k', 'split.multi_category_receipt'),
        ('Lan chuyển khoản trả lại tiền chia bill lẩu nướng 280k', 'split.settle_repayment'),
        ('Nhận lương 22tr phân bổ theo quy tắc 50 30 20', 'alloc.rule_50_30_20'),
        ('Lương 26 triệu chia vào 6 chiếc lọ tài chính', 'alloc.six_jars'),
        ('Thu nhập hai vợ chồng 35 triệu có con nhỏ chia quỹ gia đình sao cho hợp lý', 'alloc.family_household'),
        ('Lương 21 triệu đang trả góp 6 triệu chia tiền trả nợ sao cho nhanh hết', 'alloc.debt_payoff'),
        ('Lương 32 triệu thuê nhà 5 triệu muốn tiết kiệm tối đa đầu tư FIRE', 'alloc.fire_high_savings'),
      ];

      for (final (utterance, expected) in splitIdCases) {
        final norm = normalizer.toClassifierInput(utterance);
        final probs = splitBinaryModel.evaluateProbsFromBuckets(
          splitBinaryModel.extractFeatureBuckets(norm),
        );
        expect(
          splitBinaryModel.isRejectedAsOod(
            probs,
            oodRejectThreshold: oodRejectTh,
            lowConfidenceThreshold: lowTh,
          ),
          isFalse,
          reason: 'Valid Money Split utterance "$utterance" was rejected as OOD!',
        );
        final best = splitBinaryModel.bestInDomainFrom(probs);
        expect(best.label, expected, reason: utterance);
      }
    });
  });

  group('4. Exact Vietnamese Amount Parsing & Multi-Intent Compound NLU', () {
    test('parses 65k, 1tr2, 18 triệu rưỡi, 2 củ, 500 nghìn accurately in minor VND units', () {
      const cases = <(String phrase, int expectedMinor)>[
        ('Ăn phở 65k', 65000),
        ('Mua tai nghe 1tr2', 1200000),
        ('Nhận lương 18 triệu rưỡi', 18500000),
        ('Đóng tiền nhà 2 củ', 2000000),
        ('Mừng cưới 500 nghìn', 500000),
      ];

      for (final (phrase, expectedMinor) in cases) {
        final normalized = normalizer.normalizeText(phrase);
        final parsed = normalizer.extractAmounts(normalized);
        expect(parsed, isNotEmpty, reason: 'No amount parsed for "$phrase"');
        expect(parsed.first.amountMinor, expectedMinor, reason: phrase);
      }
    });

    test('parses compound 4-clause utterance across income, fuel, 4-way group split & Sunday maintenance', () {
      const compound =
          'Hôm nay nhận lương 15 triệu, đổ xăng 70k, tối ăn lẩu 600k chia bốn người và Chủ nhật nhắc bảo dưỡng xe';

      final spokenNormalized = VoiceFinancialNlpEngine.normalizeSpokenVietnamese(
        compound,
      );
      final omniDrafts = SmartOmniIntentParser.parseMulti(
        spokenNormalized,
        now: fixedNow,
      );
      expect(omniDrafts.length, 4);

      expect(omniDrafts[0].kind, OmniActionKind.transaction);
      expect(omniDrafts[0].transactionKind, TransactionKind.income);
      expect(omniDrafts[0].amountMinor, 15000000);

      expect(omniDrafts[1].kind, OmniActionKind.transaction);
      expect(omniDrafts[1].resolvedSubtype, OmniIntentSubtype.fuelRefill);
      expect(omniDrafts[1].amountMinor, 70000);

      expect(omniDrafts[2].kind, OmniActionKind.groupSplit);
      expect(omniDrafts[2].amountMinor, 600000);
      expect(omniDrafts[2].participantCount, 4);
      expect(omniDrafts[2].perPersonShareMinor, 150000);

      expect(omniDrafts[3].kind, OmniActionKind.task);
      expect(omniDrafts[3].resolvedSubtype, OmniIntentSubtype.vehicleMaintenance);

      // FinancialEntityExtractor isolates the 3 monetary ledger clauses while excluding the non-monetary Sunday reminder
      final extractor = FinancialEntityExtractor(normalizer);
      final entities = extractor.extractAll(compound, referenceTime: fixedNow);
      expect(entities.length, 3);
      expect(
        entities.map((e) => e.amountMinor).toList(),
        [15000000, 70000, 600000],
      );
      expect(entities[0].transactionType, FinancialTransactionType.income);
      expect(entities[1].transactionType, FinancialTransactionType.expense);
      expect(entities[2].transactionType, FinancialTransactionType.expense);
    });
  });
}
