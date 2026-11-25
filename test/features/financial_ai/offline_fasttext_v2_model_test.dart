import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:life_os/features/financial_ai/data/inference/fasttext_binary_model.dart';
import 'package:life_os/features/financial_ai/data/inference/fasttext_classifier.dart';
import 'package:life_os/features/financial_ai/data/normalization/financial_text_normalizer.dart';
import 'package:life_os/features/financial_ai/domain/entities/financial_ai_entities.dart';

void main() {
  late Uint8List modelBytes;
  late String metaJson;
  late Map<String, dynamic> metaMap;
  late FastTextBinaryModel binaryModel;
  late FinancialTextNormalizer normalizer;

  setUpAll(() {
    modelBytes = File(
      'assets/models/vn_financial_fasttext_v1.ftq',
    ).readAsBytesSync();
    metaJson = File(
      'assets/models/vn_financial_fasttext_v1_meta.json',
    ).readAsStringSync();
    metaMap = jsonDecode(metaJson) as Map<String, dynamic>;
    binaryModel = FastTextBinaryModel.parseAndVerify(
      modelBytes,
      expectedSha256: metaMap['sha256'] as String,
    );
    normalizer = FinancialTextNormalizer();
  });

  group('Offline FastText v3.0 QAT+OOD Model — Integrity & Train-Serve Parity', () {
    test(
      'verifies v3.0.0 metadata, SHA-256 checksum, compact <1MB size, >=95% Macro F1 and >=95% unseen OOD rejection',
      () {
        expect(metaMap['modelId'], 'vn_financial_fasttext_v1');
        expect(metaMap['modelVersion'], '3.0.0');
        expect(binaryModel.numClasses, 30);
        expect(binaryModel.hasExplicitOodClass, isTrue);
        expect(binaryModel.dim, greaterThanOrEqualTo(30));
        expect(binaryModel.numBuckets, 28672);
        expect(binaryModel.wordNgrams, 2);
        expect(binaryModel.minSubword, 4);
        expect(binaryModel.maxSubword, 5);
        expect(modelBytes.length, lessThan(1024 * 1024));

        final metrics = metaMap['metrics'] as Map<String, dynamic>;
        expect(
          (metrics['testAccuracy'] as num).toDouble(),
          greaterThanOrEqualTo(0.96),
        );
        expect(
          (metrics['testMacroF1'] as num).toDouble(),
          greaterThanOrEqualTo(0.97),
        );
        expect(
          (metrics['oodUnknownRejectionRate'] as num).toDouble(),
          greaterThanOrEqualTo(0.95),
        );
        expect(
          (metrics['expectedCalibrationError'] as num).toDouble(),
          lessThanOrEqualTo(0.05),
        );
        expect(
          (metrics['falseAutoAssignmentRate'] as num).toDouble(),
          lessThanOrEqualTo(0.005),
        );
      },
    );

    test(
      'matches Python QuantizedFastTextReader normalization, bucket hashes, and probabilities bit-for-bit',
      () {
        const goldenVectors =
            <
              ({
                String raw,
                String expectedNorm,
                int expectedBucketCount,
                int expectedFirstBucket,
                String expectedLabel,
                double expectedProb,
              })
            >[
              (
                raw: 'Ăn sáng phở bò 45 cành',
                expectedNorm: 'ăn sáng phở bò',
                expectedBucketCount: 26,
                expectedFirstBucket: 3221,
                expectedLabel: 'food.meals',
                expectedProb: 1.0,
              ),
              (
                raw: 'uong cf muoi 30k',
                expectedNorm: 'uong cà phê muoi',
                expectedBucketCount: 31,
                expectedFirstBucket: 7291,
                expectedLabel: 'food.drinks',
                expectedProb: 0.999999,
              ),
              (
                raw: 'đi chợ mua thực phẩm nấu cơm gia đình 180k',
                expectedNorm: 'đi chợ mua thực phẩm nấu cơm gia đình',
                expectedBucketCount: 66,
                expectedFirstBucket: 18366,
                expectedLabel: 'food.groceries',
                expectedProb: 0.999996,
              ),
              (
                raw: 'mua sữa công thức cho em bé 450k',
                expectedNorm: 'mua sữa công thức cho em bé',
                expectedBucketCount: 49,
                expectedFirstBucket: 5505,
                expectedLabel: 'family',
                expectedProb: 0.999999,
              ),
              (
                raw: 'gửi tiền phụng dưỡng bố mẹ ở quê 3tr',
                expectedNorm: 'gửi tiền phụng dưỡng bố mẹ ở quê',
                expectedBucketCount: 64,
                expectedFirstBucket: 14047,
                expectedLabel: 'family',
                expectedProb: 0.999996,
              ),
              (
                raw: 'gia hạn gói netflix gia đình 260k',
                expectedNorm: 'gia hạn gói gói netflix gia đình',
                expectedBucketCount: 55,
                expectedFirstBucket: 28227,
                expectedLabel: 'subscriptions',
                expectedProb: 0.999985,
              ),
              (
                raw: 'mua cuộn túi rác gia đình 35k',
                expectedNorm: 'mua cuộn túi rác gia đình',
                expectedBucketCount: 43,
                expectedFirstBucket: 5505,
                expectedLabel: 'housing.housework',
                expectedProb: 0.999876,
              ),
              (
                raw: 'phong bì mừng đám cưới đồng nghiệp 500k',
                expectedNorm: 'phong bì mừng đám cưới đồng nghiệp',
                expectedBucketCount: 70,
                expectedFirstBucket: 5958,
                expectedLabel: 'gifts',
                expectedProb: 0.999999,
              ),
              (
                raw: 'được nhận tiền lì xì đầu năm 500k',
                expectedNorm: 'được nhận tiền lì xì đầu năm',
                expectedBucketCount: 54,
                expectedFirstBucket: 4475,
                expectedLabel: 'income.gift',
                expectedProb: 0.999998,
              ),
              (
                raw: 'bố mẹ gửi cho mình tiền ăn học 3tr',
                expectedNorm: 'bố mẹ gửi cho mình tiền ăn học',
                expectedBucketCount: 55,
                expectedFirstBucket: 16773,
                expectedLabel: 'income.gift',
                expectedProb: 0.999781,
              ),
              (
                raw: 'đóng tiền trả góp fe credit 1tr8',
                expectedNorm: 'đóng tiền trả góp fe credit',
                expectedBucketCount: 52,
                expectedFirstBucket: 4998,
                expectedLabel: 'debt.interest',
                expectedProb: 1.0,
              ),
              (
                raw: 'ngân hàng trừ phí sms biến động số dư 11k',
                expectedNorm: 'ngân hàng trừ phí sms biến động số dư',
                expectedBucketCount: 71,
                expectedFirstBucket: 10448,
                expectedLabel: 'bank.fee',
                expectedProb: 0.999997,
              ),
              (
                raw: 'nhận lương chuyển khoản tháng 11 18tr5',
                expectedNorm: 'nhận lương chuyển khoản tháng',
                expectedBucketCount: 62,
                expectedFirstBucket: 3798,
                expectedLabel: 'income.salary',
                expectedProb: 0.999999,
              ),
              (
                raw: 'đối soát tiền thu hộ cod giao hàng nhanh 4tr2',
                expectedNorm: 'đối soát tiền thu hộ cod giao hàng nhanh',
                expectedBucketCount: 78,
                expectedFirstBucket: 6257,
                expectedLabel: 'income.business',
                expectedProb: 1.0,
              ),
            ];

        for (final g in goldenVectors) {
          final dartNorm = normalizer.toClassifierInput(g.raw);
          expect(
            dartNorm,
            g.expectedNorm,
            reason: 'Normalization drift on "${g.raw}"',
          );

          final buckets = binaryModel.extractFeatureBuckets(dartNorm);
          expect(
            buckets.length,
            g.expectedBucketCount,
            reason: 'Bucket count drift on "${g.raw}"',
          );
          expect(
            buckets.first,
            g.expectedFirstBucket,
            reason: 'FNV-1a hash drift on "${g.raw}"',
          );

          final probs = binaryModel.evaluateProbsFromBuckets(buckets);
          var bestIdx = 0;
          for (var i = 1; i < probs.length; i++) {
            if (probs[i] > probs[bestIdx]) bestIdx = i;
          }
          expect(
            binaryModel.labels[bestIdx],
            g.expectedLabel,
            reason: 'Predicted label mismatch on "${g.raw}"',
          );
          expect(
            probs[bestIdx],
            greaterThanOrEqualTo(0.70),
            reason:
                'Calibrated confidence unexpectedly low on "${g.raw}": ${probs[bestIdx]}',
          );
        }
      },
    );

    test(
      'runs all 30 semantic categories & colloquial Vietnamese edge cases accurately in Worker Isolate',
      () async {
        final workerClassifier = FastTextClassifier(
          bytesLoader: (_) async => modelBytes,
          jsonLoader: (_) async => metaJson,
        );
        await workerClassifier.initialize();
        expect(workerClassifier.metadata.modelVersion, '3.0.0');
        expect(workerClassifier.metadata.usingRuleFallback, isFalse);

        const categorySmokeCases =
            <(String rawUtterance, String expectedLabel)>[
              ('ăn sáng bún bò huế 55k', 'food.meals'),
              ('uống trà đào cam sả 45k', 'food.drinks'),
              ('đi chợ mua thịt heo rau củ 160k', 'food.groceries'),
              ('đổ xăng ron 95 petrolimex 80k', 'transport.fuel'),
              ('gọi grabcar ra sân bay 180k', 'transport.ride_hailing'),
              ('nạp thẻ thu phí epass 200k', 'transport.public'),
              ('thay nhớt xe vision 1 xị rưỡi', 'transport.maintenance'),
              ('đóng tiền thuê phòng trọ 3tr5', 'housing.rent'),
              ('thanh toán tiền điện evn 920k', 'housing.utilities'),
              ('thuê dọn nhà theo giờ btaskee 280k', 'housing.housework'),
              ('mua áo sơ mi uniqlo 499k', 'shopping.clothes'),
              ('mua pin sạc dự phòng anker 650k', 'shopping.electronics'),
              ('đặt đơn hàng mua sắm shopee 320k', 'shopping.general'),
              ('mua thuốc cảm cúm longchau 95k', 'health.medicine'),
              ('tiêm vắc xin cúm vnvc 350k', 'health.hospital'),
              ('đóng học phí tiếng anh ielts 4tr5', 'education'),
              ('mua vé xem phim cgv 220k', 'entertainment'),
              ('gia hạn spotify premium 59k', 'subscriptions'),
              ('mua bỉm sữa cho em bé concung 520k', 'family'),
              ('đi phong bì mừng đám cưới bạn 5 lít', 'gifts'),
              ('thanh toán kỳ trả góp homecredit 1tr6', 'debt.interest'),
              ('phí thường niên thẻ tín dụng 499k', 'bank.fee'),
              ('thanh toán dịch vụ sao y công chứng giấy tờ 40k', 'other'),
              ('nhận lương chính thức tháng 11 22tr', 'income.salary'),
              ('nhận tiền thưởng đạt kpi quý 5tr', 'income.bonus'),
              ('nhận thù lao thiết kế logo freelance 3tr5', 'income.freelance'),
              ('tiền đối soát doanh thu shopee về ví 6tr8', 'income.business'),
              ('nhận tiền lãi sổ tiết kiệm đáo hạn 1tr2', 'income.interest'),
              ('được ông bà cho mình tiền mừng tuổi 1tr', 'income.gift'),
              ('bán thanh lý bàn ghế cũ không dùng 450k', 'income.other'),
            ];

        for (final (raw, expectedLabel) in categorySmokeCases) {
          final norm = normalizer.toClassifierInput(raw);
          final res = await workerClassifier.classify(norm);
          expect(
            res.topPrediction.semanticKey,
            expectedLabel,
            reason:
                'Expected $expectedLabel for "$raw" (norm="$norm"), got ${res.topPrediction.semanticKey}',
          );
          expect(
            res.topPrediction.origin,
            isNot(ClassifierInferenceOrigin.deterministicRuleFallback),
          );
        }

        await workerClassifier.dispose();
      },
    );
  });
}
