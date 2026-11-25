import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:life_os/core/services/native_voice_assistant_bridge.dart';
import 'package:life_os/core/utils/smart_money_split_ai_engine.dart';
import 'package:life_os/core/utils/user_behavior_prefs.dart';
import 'package:life_os/core/utils/voice_financial_nlp_engine.dart';
import 'package:life_os/features/family/domain/entities/family_entities.dart';
import 'package:life_os/features/financial_ai/data/inference/fasttext_binary_model.dart';

void main() {
  late Uint8List splitModelBytes;
  late String splitMetaJson;
  late Map<String, dynamic> splitMetaMap;
  late FastTextBinaryModel splitBinaryModel;

  setUpAll(() {
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
  });

  group('1. Trained INT8 FastText Money-Splitting & Allocation AI Model', () {
    test('verifies LFTQ v1 SHA-256 integrity, compact <450KB size, >=97% test accuracy, and 0% false auto-assign', () {
      expect(splitMetaMap['modelId'], 'vn_money_split_fasttext_v1');
      expect(splitBinaryModel.numClasses, 12);
      expect(splitModelBytes.length, lessThan(450 * 1024));

      final metrics = splitMetaMap['metrics'] as Map<String, dynamic>;
      expect(
        (metrics['testAccuracy'] as num).toDouble(),
        greaterThanOrEqualTo(0.97),
      );
      expect(
        (metrics['testMacroF1'] as num).toDouble(),
        greaterThanOrEqualTo(0.97),
      );
      expect(
        (metrics['falseAutoAssignmentRate'] as num).toDouble(),
        equals(0.0),
      );
      expect(
        (metrics['oodUnknownRejectionRate'] as num).toDouble(),
        equals(1.0),
      );
    });

    test('accurately classifies all 12 Vietnamese money-splitting & allocation intents on-device', () async {
      final loaded = await SmartMoneySplitAiEngine.ensureModelLoaded(
        bytesLoader: (_) async => splitModelBytes,
        jsonLoader: (_) async => splitMetaJson,
      );
      expect(loaded, isNotNull);

      const cases = <(String utterance, String expectedLabel)>[
        ('Ăn lẩu bò 600k chia đều 4 người', 'split.equal'),
        ('Tiền điện 900k chia phần trăm Hòa 60 phần trăm Minh 40 phần trăm', 'split.percentage'),
        ('Đi ăn hải sản 1tr4 chia theo suất nhà Hòa 2 suất Nam 1 suất Lan 1 suất', 'split.shares_ratio'),
        ('Ăn trưa 320k Minh uống thêm cà phê 40k còn lại 4 người chia đều', 'split.itemized_remainder'),
        ('Tiền đi chợ 500k Hòa 200k Minh 180k còn lại Lan chịu', 'split.exact_custom'),
        ('Siêu thị WinMart 580k gồm thực phẩm 400k việc nhà 180k', 'split.multi_category_receipt'),
        ('Lan chuyển khoản trả lại tiền chia bill lẩu nướng 280k', 'split.settle_repayment'),
        ('Nhận lương 22tr phân bổ theo quy tắc 50 30 20 cân bằng', 'alloc.rule_50_30_20'),
        ('Lương 26 triệu phân bổ vào 6 chiếc lọ tài chính', 'alloc.six_jars'),
        ('Thu nhập hai vợ chồng 35 triệu có con nhỏ chia quỹ gia đình sao cho hợp lý', 'alloc.family_household'),
        ('Lương 21 triệu đang trả góp 6 triệu chia tiền trả nợ sao cho nhanh hết', 'alloc.debt_payoff'),
        ('Lương 32 triệu thuê nhà 5 triệu muốn tiết kiệm tối đa để đầu tư FIRE', 'alloc.fire_high_savings'),
      ];

      for (final (utterance, expectedLabel) in cases) {
        final pred = SmartMoneySplitAiEngine.classifyWithModel(
          utterance,
          modelOverride: splitBinaryModel,
        );
        expect(pred, isNotNull);
        expect(
          pred!.topLabel,
          expectedLabel,
          reason: 'Expected $expectedLabel for "$utterance", got ${pred.topLabel}',
        );
        expect(pred.confidence, greaterThan(0.65));
      }
    });
  });

  group('2. Exact VND Hamilton Apportionment, Advanced Split NLP & Min-Cash-Flow Settlement', () {
    test('Hamilton apportionment preserves exact VND total with zero 1-dong drift', () {
      final threeWays = SmartMoneySplitAiEngine.apportionExactVnd(
        100000,
        [1, 1, 1],
      );
      expect(threeWays, [33334, 33333, 33333]);
      expect(threeWays.fold<int>(0, (a, b) => a + b), 100000);

      final weighted = SmartMoneySplitAiEngine.apportionExactVnd(
        1000000,
        [3, 2, 2],
      );
      expect(weighted.fold<int>(0, (a, b) => a + b), 1000000);
      expect(weighted.first, greaterThan(weighted.last));
    });

    test('VoiceFinancialNlpEngine parses itemized extras + shared remainder, weighted shares, campuchia/cưa đôi, and upfront payer', () {
      // 1. Itemized extra + shared equal remainder
      final itemized = VoiceFinancialNlpEngine.analyze(
        'Ăn trưa 320k Minh uống thêm cà phê 40k còn lại chia đều cho Hòa, Minh, Lan, Tuấn',
        currentUserId: 'u_hoa',
        currentUserName: 'Hòa',
      );
      expect(itemized, isNotNull);
      expect(itemized!.intentKind, VoiceSentenceIntentKind.groupBillSplit);
      final g1 = itemized.groupSplit!;
      expect(g1.totalAmountMinor, 320000);
      expect(g1.shares.fold<int>(0, (s, e) => s + e.amountMinor), 320000);
      final minhShare = g1.shares.firstWhere((s) => s.displayName == 'Minh');
      final hoaShare = g1.shares.firstWhere((s) => s.displayName == 'Hòa');
      expect(minhShare.amountMinor, 110000); // 40k extra + 70k shared
      expect(hoaShare.amountMinor, 70000);

      // 2. Weighted shares ("2 suất, 1 suất, 1 suất")
      final weighted = VoiceFinancialNlpEngine.analyze(
        'Đi ăn hải sản 1tr4 nhà Hòa 2 suất Nam 1 suất Lan 1 suất',
        currentUserId: 'u_hoa',
        currentUserName: 'Hòa',
      );
      expect(weighted?.groupSplit?.splitMethod, SplitMethod.shares);
      expect(
        weighted!.groupSplit!.shares.map((s) => s.amountMinor).toList(),
        [700000, 350000, 350000],
      );

      // 3. Upfront payer + campuchia slang
      final payerSplit = VoiceFinancialNlpEngine.analyze(
        'Hùng trả trước tiền lẩu 750k campuchia 5 anh em',
        currentUserId: 'u_hoa',
        currentUserName: 'Hòa',
      );
      expect(payerSplit?.groupSplit?.paidByDisplayName, 'Hùng');
      expect(payerSplit?.groupSplit?.shares.length, 5);
      expect(payerSplit?.groupSplit?.shares.first.amountMinor, 150000);

      // 4. "cưa đôi với Minh"
      final cuaDoi = VoiceFinancialNlpEngine.analyze(
        'Uống cà phê 90k cưa đôi với Minh',
        currentUserId: 'u_hoa',
        currentUserName: 'Hòa',
      );
      expect(cuaDoi?.groupSplit?.shares.length, 2);
      expect(cuaDoi?.groupSplit?.shares[0].amountMinor, 45000);
      expect(cuaDoi?.groupSplit?.shares[1].displayName, 'Minh');
    });

    test('Greedy Min-Cash-Flow simplifies multi-person group debt to <= N-1 transfers', () {
      // Net balances summing to 0 across 4 members:
      // Hòa: +500k, Lan: +100k, Minh: -350k, Tuấn: -250k
      final transfers = SmartMoneySplitAiEngine.optimizeSettlementTransfers(
        const {
          'u_hoa': 500000,
          'u_lan': 100000,
          'u_minh': -350000,
          'u_tuan': -250000,
        },
        memberNames: const {
          'u_hoa': 'Hòa',
          'u_lan': 'Lan',
          'u_minh': 'Minh',
          'u_tuan': 'Tuấn',
        },
      );
      expect(transfers.length, lessThanOrEqualTo(3));
      expect(transfers.fold<int>(0, (s, t) => s + t.amountMinor), 600000);
      expect(transfers.first.fromName, 'Minh');
      expect(transfers.first.toName, 'Hòa');
      expect(transfers.first.amountMinor, 350000);
    });

    test('SmartIncomeAllocationPlan adapts to constraints and sums to exact VND income', () {
      final firePlan = SmartMoneySplitAiEngine.recommendIncomeAllocation(
        prompt: 'Lương 30 triệu thuê nhà 5 triệu muốn tiết kiệm tối đa đầu tư FIRE',
        modelOverride: splitBinaryModel,
      );
      expect(firePlan.monthlyIncomeMinor, 30000000);
      expect(firePlan.strategy, AllocationStrategyKind.fireHighSavings);
      expect(
        firePlan.buckets.fold<int>(0, (s, b) => s + b.amountMinor),
        30000000,
      );
      expect(
        firePlan.budgetDrafts.fold<int>(0, (s, d) => s + d.limitMinor),
        30000000 - firePlan.totalSavingsMinor,
      );
    });
  });

  group('3. Android Google Speech Engine Escalation & Bridge Signal Contract', () {
    test('MethodChannelVoiceAssistantDriver parses engine_switched signal and persists Google Dialog preference', () async {
      await UserBehaviorPrefs.resetForTest();
      final sig = MethodChannelVoiceAssistantDriver.parseRawVoiceEvent(
        <String, dynamic>{
          'type': 'engine_switched',
          'mode': 'system_dialog',
        },
      );
      expect(sig, isA<VoiceEngineSwitchedSignal>());
      expect(
        (sig as VoiceEngineSwitchedSignal).modeWireValue,
        'system_dialog',
      );
    });
  });
}
