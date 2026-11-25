import 'dart:convert';
import 'dart:math' as math;

import 'package:equatable/equatable.dart';
import 'package:flutter/services.dart';

import '../../features/family/domain/entities/family_entities.dart';
import '../../features/financial_ai/data/inference/fasttext_binary_model.dart';
import '../../features/financial_ai/data/normalization/financial_text_normalizer.dart';
import 'participant_resolution_engine.dart';
import 'smart_quick_entry_parser.dart';
import 'vietnamese_temporal_and_entity_resolver.dart';

export 'participant_resolution_engine.dart';

enum SplitValidationStatus {
  valid,
  invalidAmount,
  invalidPercentage,
  duplicateParticipant,
  ambiguousParticipant,
  missingParticipant,
  missingPayer,
  inconsistentTotal,
  requiresConfirmation,
}

enum AllocationStrategyKind {
  rule503020('alloc.rule_50_30_20', 'Quy tắc 50/30/20 Cân bằng'),
  sixJars('alloc.six_jars', 'Mô hình 6 Chiếc Lọ JARS'),
  familyHousehold('alloc.family_household', 'Tổ ấm Gia đình & Con nhỏ'),
  debtPayoff('alloc.debt_payoff', 'Tăng tốc Trả nợ (Avalanche)'),
  fireHighSavings('alloc.fire_high_savings', 'Tích lũy FIRE & Mua Tài sản');

  final String labelKey;
  final String displayNameVi;
  const AllocationStrategyKind(this.labelKey, this.displayNameVi);
}

class AllocationBucketItem extends Equatable {
  final String id;
  final String titleVi;
  final String subtitleVi;
  final int percentage;
  final int amountMinor;
  final bool isSavingsOrInvestment;

  const AllocationBucketItem({
    required this.id,
    required this.titleVi,
    required this.subtitleVi,
    required this.percentage,
    required this.amountMinor,
    this.isSavingsOrInvestment = false,
  });

  @override
  List<Object?> get props => [
    id,
    titleVi,
    subtitleVi,
    percentage,
    amountMinor,
    isSavingsOrInvestment,
  ];
}

class BudgetCategoryDraft extends Equatable {
  final String categoryId;
  final String categoryName;
  final int limitMinor;

  const BudgetCategoryDraft({
    required this.categoryId,
    required this.categoryName,
    required this.limitMinor,
  });

  @override
  List<Object?> get props => [categoryId, categoryName, limitMinor];
}

class SmartIncomeAllocationPlan extends Equatable {
  final int monthlyIncomeMinor;
  final AllocationStrategyKind strategy;
  final double modelConfidence;
  final String rationaleVi;
  final int fixedCommitmentsMinor;
  final int totalSavingsMinor;
  final double savingsRatePct;
  final int safeDailySpendMinor;
  final List<AllocationBucketItem> buckets;
  final List<BudgetCategoryDraft> budgetDrafts;

  const SmartIncomeAllocationPlan({
    required this.monthlyIncomeMinor,
    required this.strategy,
    required this.modelConfidence,
    required this.rationaleVi,
    required this.fixedCommitmentsMinor,
    required this.totalSavingsMinor,
    required this.savingsRatePct,
    required this.safeDailySpendMinor,
    required this.buckets,
    required this.budgetDrafts,
  });

  @override
  List<Object?> get props => [
    monthlyIncomeMinor,
    strategy,
    modelConfidence,
    rationaleVi,
    fixedCommitmentsMinor,
    totalSavingsMinor,
    savingsRatePct,
    safeDailySpendMinor,
    buckets,
    budgetDrafts,
  ];
}

class OptimalSettlementTransfer extends Equatable {
  final String fromUserId;
  final String fromName;
  final String toUserId;
  final String toName;
  final int amountMinor;

  const OptimalSettlementTransfer({
    required this.fromUserId,
    required this.fromName,
    required this.toUserId,
    required this.toName,
    required this.amountMinor,
  });

  @override
  List<Object?> get props => [
    fromUserId,
    fromName,
    toUserId,
    toName,
    amountMinor,
  ];
}

class MoneySplitModelPrediction extends Equatable {
  final String topLabel;
  final double confidence;
  final Map<String, double> probabilities;

  const MoneySplitModelPrediction({
    required this.topLabel,
    required this.confidence,
    required this.probabilities,
  });

  @override
  List<Object?> get props => [topLabel, confidence, probabilities];
}

class AdvancedGroupSplitParseResult extends Equatable {
  final String title;
  final int totalAmountMinor;
  final SharedExpenseTopic topic;
  final SplitMethod splitMethod;
  final String? paidByParticipantId;
  final String? paidByDisplayName;
  final List<({String participantId, String displayName, int amountMinor, int? percentage, int? sharesWeight})> shares;
  final Map<String, int> rawInputValuesByUserId;
  final SplitValidationStatus validationStatus;
  final String? validationMessageVi;
  final List<ParticipantResolutionOutcome> ambiguousParticipants;

  const AdvancedGroupSplitParseResult({
    required this.title,
    required this.totalAmountMinor,
    required this.topic,
    required this.splitMethod,
    this.paidByParticipantId,
    this.paidByDisplayName,
    required this.shares,
    required this.rawInputValuesByUserId,
    this.validationStatus = SplitValidationStatus.valid,
    this.validationMessageVi,
    this.ambiguousParticipants = const <ParticipantResolutionOutcome>[],
  });

  bool get isValid => validationStatus == SplitValidationStatus.valid;

  @override
  List<Object?> get props => [
    title,
    totalAmountMinor,
    topic,
    splitMethod,
    paidByParticipantId,
    paidByDisplayName,
    shares,
    rawInputValuesByUserId,
    validationStatus,
    validationMessageVi,
    ambiguousParticipants,
  ];
}

/// On-Device Vietnamese Money-Splitting & Smart Income Allocation AI Engine.
///
/// Combines:
/// 1. Quantized INT8 FastText Neural Classifier (`assets/models/vn_money_split_fasttext_v1.ftq`)
///    trained across 12 money-splitting, settlement, and income-allocation intents.
/// 2. Exact Integer VND Hamilton (Largest Remainder) Apportionment (`0 ₫` rounding loss!).
/// 3. Greedy Minimum-Cash-Flow Multi-Party Debt Simplification ($\le N - 1$ transfers).
/// 4. Constraint-Aware Income Allocation Advisor (`50/30/20`, `6 Jars`, `Family`, `Debt`, `FIRE`).
abstract final class SmartMoneySplitAiEngine {
  static const String modelAssetPath =
      'assets/models/vn_money_split_fasttext_v1.ftq';
  static const String metadataAssetPath =
      'assets/models/vn_money_split_fasttext_v1_meta.json';

  static FastTextBinaryModel? _cachedModel;
  static final FinancialTextNormalizer _normalizer = FinancialTextNormalizer();

  static final RegExp _amountTokenRegex = RegExp(
    r'(\d+(?:[.,]\d+)?\s*(?:tỷ|ty|triệu|trieu|tr|củ|cu)(?:\s*\d{1,3}(?:\s*(?:nghìn|nghin|ngàn|ngan|k))?)?|\d+(?:[.,]\d+)?\s*(?:nghìn|nghin|ngàn|ngan|k|xị|xi|lít|lit|cành|canh)(?:\s*\d{1,2})?|\d{1,3}(?:[.,]\d{3})+|\d{5,12})\s*(?:đ|₫|vnđ|vnd|đồng|dong)?',
    caseSensitive: false,
    unicode: true,
  );

  /// Loads and SHA-256-verifies the quantized INT8 `vn_money_split_fasttext_v1.ftq` model once.
  static Future<FastTextBinaryModel?> ensureModelLoaded({
    Future<Uint8List> Function(String path)? bytesLoader,
    Future<String> Function(String path)? jsonLoader,
  }) async {
    if (_cachedModel != null && bytesLoader == null && jsonLoader == null) {
      return _cachedModel;
    }
    try {
      final loadBytes =
          bytesLoader ??
          ((String p) async => (await rootBundle.load(p)).buffer.asUint8List());
      final loadJson = jsonLoader ?? rootBundle.loadString;
      final rawBytes = await loadBytes(modelAssetPath);
      final rawMeta = await loadJson(metadataAssetPath);
      final meta = jsonDecode(rawMeta) as Map<String, dynamic>;
      final model = FastTextBinaryModel.parseAndVerify(
        rawBytes,
        expectedSha256: meta['sha256'] as String?,
      );
      if (bytesLoader == null && jsonLoader == null) {
        _cachedModel = model;
      }
      return model;
    } catch (_) {
      return null;
    }
  }

  /// Evaluates the trained 12-class INT8 model synchronously once loaded.
  static MoneySplitModelPrediction? classifyWithModel(
    String rawText, {
    FastTextBinaryModel? modelOverride,
  }) {
    final model = modelOverride ?? _cachedModel;
    if (model == null) return null;
    final norm = _normalizer.toClassifierInput(rawText);
    final buckets = model.extractFeatureBuckets(norm);
    final probs = model.evaluateProbsFromBuckets(buckets);
    var bestIdx = 0;
    final map = <String, double>{};
    for (var i = 0; i < model.labels.length; i++) {
      map[model.labels[i]] = probs[i];
      if (probs[i] > probs[bestIdx]) {
        bestIdx = i;
      }
    }
    return MoneySplitModelPrediction(
      topLabel: model.labels[bestIdx],
      confidence: probs[bestIdx],
      probabilities: map,
    );
  }

  /// Exact Integer VND Hamilton (Largest Remainder) Apportionment using `BigInt`
  /// rational arithmetic (`exactNumerator = BigInt.from(totalMinor) * weightBig`).
  /// Guarantees `result.fold(0, +) == totalMinor` with zero IEEE-754 float drift
  /// even for multi-billion VND bills!
  static List<int> apportionExactVnd(int totalMinor, List<double> weights) {
    if (weights.isEmpty) return const <int>[];
    if (totalMinor <= 0) return List<int>.filled(weights.length, 0);

    final allWhole = weights.every(
      (w) => w.isFinite && (w - w.roundToDouble()).abs() < 1e-9,
    );
    final bigWeights = weights.map((w) {
      if (!w.isFinite || w <= 0) return BigInt.zero;
      if (allWhole) return BigInt.from(w.round());
      return BigInt.from((w * 1000000).round());
    }).toList();

    return apportionExactVndBigInt(totalMinor, bigWeights);
  }

  /// Pure `BigInt` Hamilton (Largest Remainder) integer apportionment.
  static List<int> apportionExactVndBigInt(
    int totalMinor,
    List<BigInt> weights,
  ) {
    if (weights.isEmpty) return const <int>[];
    if (totalMinor <= 0) return List<int>.filled(weights.length, 0);

    final sanitized = weights
        .map((w) => w > BigInt.zero ? w : BigInt.zero)
        .toList();
    var weightSum = sanitized.fold<BigInt>(BigInt.zero, (a, b) => a + b);
    if (weightSum <= BigInt.zero) {
      for (var i = 0; i < sanitized.length; i++) {
        sanitized[i] = BigInt.one;
      }
      weightSum = BigInt.from(sanitized.length);
    }

    final totalBig = BigInt.from(totalMinor);
    final floors = List<int>.filled(sanitized.length, 0);
    final remainders = <({int index, BigInt rem})>[];
    var allocated = BigInt.zero;

    for (var i = 0; i < sanitized.length; i++) {
      final exactNumerator = totalBig * sanitized[i];
      final fl = exactNumerator ~/ weightSum;
      final rem = exactNumerator % weightSum;
      floors[i] = fl.toInt();
      allocated += fl;
      remainders.add((index: i, rem: rem));
    }

    final leftover = (totalBig - allocated).toInt();
    if (leftover > 0) {
      remainders.sort((a, b) {
        final cmp = b.rem.compareTo(a.rem);
        return cmp != 0 ? cmp : a.index.compareTo(b.index);
      });
      for (var k = 0; k < leftover; k++) {
        floors[remainders[k % remainders.length].index] += 1;
      }
    }
    return floors;
  }

  /// Greedy Minimum-Cash-Flow Debt Simplification across $N$ group members.
  /// Reduces arbitrary pairwise IOUs to at most $N - 1$ optimal transfers!
  static List<OptimalSettlementTransfer> optimizeSettlementTransfers(
    Map<String, int> netBalanceByMemberId, {
    Map<String, String> memberNames = const <String, String>{},
  }) {
    final creditors = <({String id, int amount})>[];
    final debtors = <({String id, int amount})>[];

    for (final entry in netBalanceByMemberId.entries) {
      if (entry.value > 0) {
        creditors.add((id: entry.key, amount: entry.value));
      } else if (entry.value < 0) {
        debtors.add((id: entry.key, amount: -entry.value));
      }
    }

    creditors.sort((a, b) => b.amount.compareTo(a.amount));
    debtors.sort((a, b) => b.amount.compareTo(a.amount));

    final transfers = <OptimalSettlementTransfer>[];
    var cIdx = 0;
    var dIdx = 0;
    final credRem = creditors.map((e) => e.amount).toList();
    final debtRem = debtors.map((e) => e.amount).toList();

    while (cIdx < creditors.length && dIdx < debtors.length) {
      final settled = math.min(credRem[cIdx], debtRem[dIdx]);
      if (settled > 0) {
        final fromId = debtors[dIdx].id;
        final toId = creditors[cIdx].id;
        transfers.add(
          OptimalSettlementTransfer(
            fromUserId: fromId,
            fromName: memberNames[fromId] ?? fromId,
            toUserId: toId,
            toName: memberNames[toId] ?? toId,
            amountMinor: settled,
          ),
        );
      }
      credRem[cIdx] -= settled;
      debtRem[dIdx] -= settled;
      if (credRem[cIdx] == 0) cIdx++;
      if (debtRem[dIdx] == 0) dIdx++;
    }

    return transfers;
  }

  static bool looksLikeGroupSplitUtterance(String lower) {
    if (lower.contains('chia ') ||
        lower.contains('chia đều') ||
        lower.contains('campuchia') ||
        lower.contains('cưa đôi') ||
        lower.contains('chia đôi') ||
        lower.contains('mỗi người') ||
        lower.contains('mỗi bạn') ||
        lower.contains('mỗi đứa') ||
        lower.contains('người chịu') ||
        lower.contains('còn lại') ||
        RegExp(
          r'\b-?\d+\s*(?:%|(?:phần\s*trăm|suất|phần)\b)',
          caseSensitive: false,
          unicode: true,
        ).hasMatch(lower)) {
      return true;
    }
    // Named per-person payments like "Hòa đơn 500k, A trả 300k, B trả 300k"
    final namedShareCount = RegExp(
      r'(?:^|[,;\s])[A-Za-zÀ-ỹ]+\s+(?:đóng|trả|chịu|gửi|ứng|chiếm)\s+(?:-?\s*|âm\s+)?\d',
      caseSensitive: false,
      unicode: true,
    ).allMatches(lower).length;
    return namedShareCount >= 2;
  }

  /// Parses complex real-world Vietnamese group bill-splitting sentences:
  /// - Equal / Campuchia / Cưa đôi
  /// - Percentage (including `còn lại <Name>`)
  /// - Weighted Shares / Suất / Phần (`2 suất, 1 suất`)
  /// - Itemized Individual Extras + Shared Equal Remainder (`Minh thêm cf 40k còn lại 4 người chia đều`)
  /// - Exact per-person + Remainder (`Hòa 200k Minh 180k còn lại Lan chịu`)
  /// - Upfront Payer extraction (`Hùng trả trước tiền lẩu 850k...`)
  ///
  /// FIX-004 & FIX-005: NEVER falls through silently to `SplitMethod.equal` when
  /// another method's markers exist with invalid totals, percentages, missing/duplicate/
  /// ambiguous participants, or negative/zero amounts.
  static AdvancedGroupSplitParseResult? tryParseAdvancedGroupSplit(
    String normalizedText, {
    required String currentUserId,
    required String currentUserName,
    required SharedExpenseTopic topic,
    List<FamilyMemberInfo> knownMembers = const <FamilyMemberInfo>[],
    Map<String, List<String>> nicknamesByUserId =
        const <String, List<String>>{},
    Map<String, String> explicitParticipantOverrides = const <String, String>{},
  }) {
    final normalized = normalizedText
        .replaceAll(
          RegExp(r'\bphần\s+trăm\b', caseSensitive: false, unicode: true),
          '%',
        )
        .trim();

    final allAmounts = _extractValidMoneyMatches(normalized);

    final hasNegativeOrZeroBill = _hasNegativeMoneyBeforeOrAtFirst(
      normalized,
      allAmounts.isEmpty ? null : allAmounts.first.start,
    );

    if (allAmounts.isEmpty) {
      if (hasNegativeOrZeroBill && looksLikeGroupSplitUtterance(normalized.toLowerCase())) {
        return AdvancedGroupSplitParseResult(
          title: 'Khoản chi chung nhóm',
          totalAmountMinor: 0,
          topic: topic,
          splitMethod: SplitMethod.equal,
          shares: const [],
          rawInputValuesByUserId: const <String, int>{},
          validationStatus: SplitValidationStatus.invalidAmount,
          validationMessageVi:
              'Tổng hóa đơn phải lớn hơn 0 ₫ (không chấp nhận 0 đ hoặc số âm).',
        );
      }
      return null;
    }

    final firstAmtMatch = allAmounts.first;
    final parsedTotal = _parseAmountToken(firstAmtMatch.group(0) ?? '');
    if (hasNegativeOrZeroBill || parsedTotal == null || parsedTotal <= 0) {
      return AdvancedGroupSplitParseResult(
        title: 'Khoản chi chung nhóm',
        totalAmountMinor: 0,
        topic: topic,
        splitMethod: SplitMethod.equal,
        shares: const [],
        rawInputValuesByUserId: const <String, int>{},
        validationStatus: SplitValidationStatus.invalidAmount,
        validationMessageVi:
            'Tổng hóa đơn phải lớn hơn 0 ₫ (không chấp nhận 0 đ hoặc số âm).',
      );
    }
    final totalMinor = parsedTotal;

    final headBeforeTotal = normalized.substring(0, firstAmtMatch.start).trim();
    final payerExtract = _extractUpfrontPayer(
      headBeforeTotal,
      currentUserId: currentUserId,
      currentUserName: currentUserName,
      knownMembers: knownMembers,
      nicknamesByUserId: nicknamesByUserId,
      explicitParticipantOverrides: explicitParticipantOverrides,
    );

    var rawTitle = payerExtract.cleanedTitle;
    rawTitle = rawTitle.replaceAll(RegExp(r'^[-:,.\s]+|[-:,.\s]+$'), '');
    if (rawTitle.length < 2) {
      rawTitle = 'Khoản chi chung nhóm';
    } else {
      rawTitle = '${rawTitle[0].toUpperCase()}${rawTitle.substring(1)}';
    }

    final afterFirstAmount = normalized.substring(firstAmtMatch.end).trim();
    final declaredHeadcount = _extractDeclaredHeadcount(afterFirstAmount);

    // 1. Itemized Individual Extras + Shared Equal Remainder
    // e.g. "Minh uống thêm cà phê 40k còn lại 4 người chia đều"
    final remEqualClause = RegExp(
      r'(?:phần\s+còn\s+lại|số\s+còn\s+lại|phần\s+chung|còn\s+lại)\s*(.*?)(?:chia\s*đều|campuchia|cưa\s*đôi|chia\s*đôi)(.*)$',
      caseSensitive: false,
      unicode: true,
    ).firstMatch(afterFirstAmount);
    if (remEqualClause != null) {
      final itemizedSection = afterFirstAmount
          .substring(0, remEqualClause.start)
          .trim();
      final tailParticipantsSection =
          '${remEqualClause.group(1) ?? ''} ${remEqualClause.group(2) ?? ''}'
              .trim();
      final extras = _extractNamedExtras(itemizedSection);
      if (extras.isNotEmpty) {
        final hasInvalidExtraAmt = extras.any((e) => e.amountMinor <= 0);
        final extraSum = extras.fold<int>(0, (s, e) => s + e.amountMinor);
        if (hasInvalidExtraAmt || extraSum <= 0) {
          return _invalidSplitResult(
            title: rawTitle,
            totalMinor: totalMinor,
            topic: topic,
            method: SplitMethod.exact,
            payerExtract: payerExtract,
            status: SplitValidationStatus.invalidAmount,
            messageVi: 'Số tiền món gọi riêng phải lớn hơn 0 ₫.',
          );
        }
        if (extraSum >= totalMinor) {
          return _invalidSplitResult(
            title: rawTitle,
            totalMinor: totalMinor,
            topic: topic,
            method: SplitMethod.exact,
            payerExtract: payerExtract,
            status: SplitValidationStatus.inconsistentTotal,
            messageVi:
                'Tổng món gọi riêng (${_formatVndStatic(extraSum)}) không thể lớn hơn hoặc bằng tổng hóa đơn (${_formatVndStatic(totalMinor)}).',
          );
        }

        final matchedEqualKeyword = remEqualClause.group(0) ?? 'chia đều';
        final participantClause = tailParticipantsSection.isEmpty
            ? matchedEqualKeyword
            : 'chia đều $tailParticipantsSection';
        final participantNames = _resolveEqualParticipantNames(
          participantClause,
          currentUserName: currentUserName,
          knownMembers: knownMembers,
          mustIncludeNames: extras.map((e) => e.name).toList(),
        );
        final n = participantNames.length;
        final sharedPool = totalMinor - extraSum;
        final equalBase = apportionExactVnd(
          sharedPool,
          List<double>.filled(n, 1.0),
        );

        final extraByLower = <String, int>{};
        for (final ex in extras) {
          final k = ex.name.toLowerCase();
          extraByLower[k] = (extraByLower[k] ?? 0) + ex.amountMinor;
        }

        final draftShares = <({
          String name,
          int amountMinor,
          int? percentage,
          int? sharesWeight,
          int? rawValue,
        })>[];
        for (var i = 0; i < n; i++) {
          final name = participantNames[i];
          final personalExtra = extraByLower[name.toLowerCase()] ?? 0;
          final finalAmt = equalBase[i] + personalExtra;
          draftShares.add((
            name: name,
            amountMinor: finalAmt,
            percentage: null,
            sharesWeight: null,
            rawValue: finalAmt,
          ));
        }
        return _finalizeValidatedResult(
          title: rawTitle,
          totalMinor: totalMinor,
          topic: topic,
          method: SplitMethod.exact,
          payerExtract: payerExtract,
          draftShares: draftShares,
          currentUserId: currentUserId,
          currentUserName: currentUserName,
          knownMembers: knownMembers,
          nicknamesByUserId: nicknamesByUserId,
          explicitParticipantOverrides: explicitParticipantOverrides,
          includeRawValues: true,
        );
      }
    }

    // 2. Percentage Split (supports "Hòa 60% Minh 40%" AND "Hòa 50% Minh 30% còn lại Lan")
    final hasPercentMarker = RegExp(
      r'-?\d+\s*%',
      caseSensitive: false,
      unicode: true,
    ).hasMatch(afterFirstAmount);
    if (hasPercentMarker) {
      final pctMatches = RegExp(
        r'([A-Za-zÀ-ỹ]+(?:\s+[A-Za-zÀ-ỹ]+)?)\s+(?:chiếm\s+|đóng\s+|trả\s+|chịu\s+)?(-?\d{1,3})\s*%',
        caseSensitive: false,
        unicode: true,
      ).allMatches(afterFirstAmount).toList();

      final entries = <({String name, int pct})>[];
      var pctSum = 0;
      var hasNonPositivePct = false;
      for (final m in pctMatches) {
        final cleaned = _cleanParticipantCandidateName(m.group(1)!);
        if (cleaned.isEmpty || _isStopWord(cleaned)) continue;
        final pct = int.tryParse(m.group(2)!) ?? 0;
        if (pct <= 0) {
          hasNonPositivePct = true;
        }
        entries.add((name: cleaned, pct: pct));
        pctSum += pct;
      }

      final remPctPerson = RegExp(
        r'còn\s+lại\s+([A-Za-zÀ-ỹ]+(?:\s+[A-Za-zÀ-ỹ]+)?)',
        caseSensitive: false,
        unicode: true,
      ).firstMatch(afterFirstAmount);
      if (remPctPerson != null && pctSum < 100 && !hasNonPositivePct) {
        final remName = _cleanParticipantCandidateName(remPctPerson.group(1)!);
        if (remName.isNotEmpty && !_isStopWord(remName)) {
          entries.add((name: remName, pct: 100 - pctSum));
          pctSum = 100;
        }
      }

      if (hasNonPositivePct) {
        return _invalidSplitResult(
          title: rawTitle,
          totalMinor: totalMinor,
          topic: topic,
          method: SplitMethod.percentage,
          payerExtract: payerExtract,
          status: SplitValidationStatus.invalidPercentage,
          messageVi: 'Tỷ lệ phần trăm của từng thành viên phải lớn hơn 0%.',
        );
      }

      if (entries.isEmpty) {
        return _invalidSplitResult(
          title: rawTitle,
          totalMinor: totalMinor,
          topic: topic,
          method: SplitMethod.percentage,
          payerExtract: payerExtract,
          status: SplitValidationStatus.missingParticipant,
          messageVi: 'Chưa xác định được tên thành viên kèm tỷ lệ phần trăm.',
        );
      }

      final exactAmts = apportionExactVnd(
        totalMinor,
        entries.map((e) => math.max(0, e.pct).toDouble()).toList(),
      );
      final draftShares = <({
        String name,
        int amountMinor,
        int? percentage,
        int? sharesWeight,
        int? rawValue,
      })>[
        for (var i = 0; i < entries.length; i++)
          (
            name: entries[i].name,
            amountMinor: exactAmts[i],
            percentage: entries[i].pct,
            sharesWeight: null,
            rawValue: entries[i].pct,
          ),
      ];

      String? pctErrorMsg;
      SplitValidationStatus? pctOverrideStatus;
      if (declaredHeadcount != null && declaredHeadcount != entries.length) {
        pctOverrideStatus = SplitValidationStatus.inconsistentTotal;
        pctErrorMsg =
            'Khai báo chia cho $declaredHeadcount người nhưng có ${entries.length} phần trăm phân bổ.';
      } else if (pctSum != 100) {
        pctOverrideStatus = SplitValidationStatus.invalidPercentage;
        pctErrorMsg =
            'Tổng tỷ lệ phần trăm đang là $pctSum% (phải bằng đúng 100%).';
      } else if (entries.length < 2) {
        pctOverrideStatus = SplitValidationStatus.missingParticipant;
        pctErrorMsg = 'Cần ít nhất 2 thành viên để chia theo phần trăm.';
      }

      return _finalizeValidatedResult(
        title: rawTitle,
        totalMinor: totalMinor,
        topic: topic,
        method: SplitMethod.percentage,
        payerExtract: payerExtract,
        draftShares: draftShares,
        currentUserId: currentUserId,
        currentUserName: currentUserName,
        knownMembers: knownMembers,
        nicknamesByUserId: nicknamesByUserId,
        explicitParticipantOverrides: explicitParticipantOverrides,
        includeRawValues: true,
        postResolutionStatusOverride: pctOverrideStatus,
        postResolutionMessageOverride: pctErrorMsg,
      );
    }

    // 3. Weighted Shares / Ratio Split ("nhà Hòa 2 suất, Nam 1 suất, Lan 1 suất" / "phòng A 3 phần phòng B 2 phần")
    final hasShareMarker = RegExp(
      r'\b-?\d{1,2}\s*(?:suất|phần|cổ\s+phần)\b',
      caseSensitive: false,
      unicode: true,
    ).hasMatch(afterFirstAmount);
    if (hasShareMarker) {
      final shareMatches = RegExp(
        r'(?:nhà\s+|gia\s+đình\s+|phòng\s+|anh\s+|chị\s+|em\s+|bạn\s+)?([A-Za-zÀ-ỹ0-9]+(?:\s+[A-Za-zÀ-ỹ0-9]+)?)\s+(?:ăn\s+|lấy\s+|đóng\s+|chịu\s+)?(-?\d{1,2})\s*(?:suất|phần|cổ\s+phần)\b',
        caseSensitive: false,
        unicode: true,
      ).allMatches(afterFirstAmount).toList();

      final shareEntries = <({String name, int weight})>[];
      var hasInvalidWeight = false;
      for (final m in shareMatches) {
        final cleaned = _cleanParticipantCandidateName(m.group(1)!);
        if (cleaned.isEmpty || _isStopWord(cleaned)) continue;
        final w = int.tryParse(m.group(2)!) ?? 0;
        if (w <= 0) {
          hasInvalidWeight = true;
        }
        shareEntries.add((name: cleaned, weight: w));
      }

      if (hasInvalidWeight) {
        return _invalidSplitResult(
          title: rawTitle,
          totalMinor: totalMinor,
          topic: topic,
          method: SplitMethod.shares,
          payerExtract: payerExtract,
          status: SplitValidationStatus.invalidAmount,
          messageVi: 'Số suất / phần chia của mỗi thành viên phải lớn hơn 0.',
        );
      }

      if (shareEntries.length < 2) {
        return _invalidSplitResult(
          title: rawTitle,
          totalMinor: totalMinor,
          topic: topic,
          method: SplitMethod.shares,
          payerExtract: payerExtract,
          status: SplitValidationStatus.missingParticipant,
          messageVi:
              'Cần ít nhất 2 thành viên hoặc nhóm hợp lệ khi chia theo suất/tỷ trọng.',
        );
      }

      final exactAmts = apportionExactVnd(
        totalMinor,
        shareEntries.map((e) => e.weight.toDouble()).toList(),
      );
      final draftShares = <({
        String name,
        int amountMinor,
        int? percentage,
        int? sharesWeight,
        int? rawValue,
      })>[
        for (var i = 0; i < shareEntries.length; i++)
          (
            name: shareEntries[i].name,
            amountMinor: exactAmts[i],
            percentage: null,
            sharesWeight: shareEntries[i].weight,
            rawValue: shareEntries[i].weight,
          ),
      ];
      return _finalizeValidatedResult(
        title: rawTitle,
        totalMinor: totalMinor,
        topic: topic,
        method: SplitMethod.shares,
        payerExtract: payerExtract,
        draftShares: draftShares,
        currentUserId: currentUserId,
        currentUserName: currentUserName,
        knownMembers: knownMembers,
        nicknamesByUserId: nicknamesByUserId,
        explicitParticipantOverrides: explicitParticipantOverrides,
        includeRawValues: true,
        postResolutionStatusOverride:
            (declaredHeadcount != null && declaredHeadcount != shareEntries.length)
                ? SplitValidationStatus.inconsistentTotal
                : null,
        postResolutionMessageOverride:
            (declaredHeadcount != null && declaredHeadcount != shareEntries.length)
                ? 'Khai báo chia cho $declaredHeadcount người nhưng có ${shareEntries.length} suất phân bổ.'
                : null,
      );
    }

    // 4. Exact Per-Person Amounts + Optional "còn lại <Name> chịu"
    final personAmtRegex = RegExp(
      r'([A-Za-zÀ-ỹ]+(?:\s+[A-Za-zÀ-ỹ]+)?)\s+(?:đóng\s+|trả\s+|chịu\s+|gửi\s+|ứng\s+)?((?:-\s*|âm\s+|am\s+)?(?:\d+(?:[.,]\d+)?\s*(?:tr|triệu|trieu|củ|cu)(?:\s*\d{1,3})?|\d+(?:[.,]\d+)?\s*(?:k|nghìn|nghin|ngàn|ngan)(?:\s*\d{1,2})?|\d{1,3}(?:[.,]\d{3})+|\d{5,11}|0\s*(?:đ|₫|vnđ|vnd|đồng|dong)))(?![\p{L}\p{N}])',
      caseSensitive: false,
      unicode: true,
    );
    final rawPersonMatches = personAmtRegex.allMatches(afterFirstAmount).toList();
    final personMatches = <({String name, String amtToken, bool isNegative})>[];
    for (final m in rawPersonMatches) {
      final cleanedName = _cleanParticipantCandidateName(m.group(1)!);
      if (cleanedName.isEmpty || _isStopWord(cleanedName)) continue;
      final amtToken = (m.group(2) ?? '').trim();
      final isNeg = RegExp(
        r'^(?:-|âm\b|am\b)',
        caseSensitive: false,
        unicode: true,
      ).hasMatch(amtToken);
      personMatches.add((
        name: cleanedName,
        amtToken: amtToken,
        isNegative: isNeg,
      ));
    }

    if (personMatches.isNotEmpty) {
      final draftShares = <({
        String name,
        int amountMinor,
        int? percentage,
        int? sharesWeight,
        int? rawValue,
      })>[];
      var assignedSum = 0;
      var hasBadShareAmount = false;
      for (final pm in personMatches) {
        if (pm.isNegative) {
          hasBadShareAmount = true;
          draftShares.add((
            name: pm.name,
            amountMinor: 0,
            percentage: null,
            sharesWeight: null,
            rawValue: 0,
          ));
          continue;
        }
        final amt = _parseAmountToken(pm.amtToken) ?? 0;
        if (amt <= 0) {
          hasBadShareAmount = true;
        }
        assignedSum += amt;
        draftShares.add((
          name: pm.name,
          amountMinor: amt,
          percentage: null,
          sharesWeight: null,
          rawValue: amt,
        ));
      }

      if (hasBadShareAmount) {
        return _invalidSplitResult(
          title: rawTitle,
          totalMinor: totalMinor,
          topic: topic,
          method: SplitMethod.exact,
          payerExtract: payerExtract,
          status: SplitValidationStatus.invalidAmount,
          messageVi: 'Số tiền mỗi người đóng/chịu phải lớn hơn 0 ₫.',
        );
      }

      final remMatch = RegExp(
        r'còn\s+lại\s+([A-Za-zÀ-ỹ]+(?:\s+[A-Za-zÀ-ỹ]+)?)',
        caseSensitive: false,
        unicode: true,
      ).firstMatch(afterFirstAmount);
      var overflowRemainder = false;
      if (remMatch != null) {
        final remName = _cleanParticipantCandidateName(remMatch.group(1)!);
        if (remName.isNotEmpty && !_isStopWord(remName)) {
          if (assignedSum >= totalMinor) {
            overflowRemainder = true;
          } else {
            final remAmt = totalMinor - assignedSum;
            draftShares.add((
              name: remName,
              amountMinor: remAmt,
              percentage: null,
              sharesWeight: null,
              rawValue: remAmt,
            ));
            assignedSum += remAmt;
          }
        }
      }

      SplitValidationStatus? exactStatus;
      String? exactMessage;
      if (overflowRemainder) {
        exactStatus = SplitValidationStatus.inconsistentTotal;
        exactMessage =
            'Số tiền đã phân bổ (${_formatVndStatic(assignedSum)}) đã lớn hơn hoặc bằng tổng hóa đơn (${_formatVndStatic(totalMinor)}), không còn dư để chia phần còn lại.';
      } else if (declaredHeadcount != null &&
          declaredHeadcount != draftShares.length) {
        exactStatus = SplitValidationStatus.inconsistentTotal;
        exactMessage =
            'Khai báo chia cho $declaredHeadcount người nhưng có ${draftShares.length} khoản phân bổ.';
      } else if (assignedSum != totalMinor) {
        exactStatus = SplitValidationStatus.inconsistentTotal;
        exactMessage =
            'Tổng các khoản chia (${_formatVndStatic(assignedSum)}) không khớp tổng hóa đơn (${_formatVndStatic(totalMinor)}).';
      } else if (draftShares.length < 2) {
        exactStatus = SplitValidationStatus.missingParticipant;
        exactMessage = 'Cần ít nhất 2 thành viên hợp lệ để chia hóa đơn.';
      }

      return _finalizeValidatedResult(
        title: rawTitle,
        totalMinor: totalMinor,
        topic: topic,
        method: SplitMethod.exact,
        payerExtract: payerExtract,
        draftShares: draftShares,
        currentUserId: currentUserId,
        currentUserName: currentUserName,
        knownMembers: knownMembers,
        nicknamesByUserId: nicknamesByUserId,
        explicitParticipantOverrides: explicitParticipantOverrides,
        includeRawValues: true,
        postResolutionStatusOverride: exactStatus,
        postResolutionMessageOverride: exactMessage,
      );
    }

    // 5. Equal Split (Headcount / Cưa đôi / Campuchia / Named list)
    if (RegExp(
      r'(?:chia(?:\s+đều)?\s+cho|cùng\s+với)\s*$',
      caseSensitive: false,
      unicode: true,
    ).hasMatch(afterFirstAmount)) {
      return _invalidSplitResult(
        title: rawTitle,
        totalMinor: totalMinor,
        topic: topic,
        method: SplitMethod.equal,
        payerExtract: payerExtract,
        status: SplitValidationStatus.missingParticipant,
        messageVi: 'Chưa có danh sách thành viên để chia tiền.',
      );
    }

    final participantNames = _resolveEqualParticipantNames(
      afterFirstAmount,
      currentUserName: currentUserName,
      knownMembers: knownMembers,
    );
    if (participantNames.length < 2) {
      return _invalidSplitResult(
        title: rawTitle,
        totalMinor: totalMinor,
        topic: topic,
        method: SplitMethod.equal,
        payerExtract: payerExtract,
        status: SplitValidationStatus.missingParticipant,
        messageVi: 'Cần ít nhất 2 người tham gia để chia đều.',
      );
    }

    final n = participantNames.length;
    final exactAmts = apportionExactVnd(
      totalMinor,
      List<double>.filled(n, 1.0),
    );
    final draftShares = <({
      String name,
      int amountMinor,
      int? percentage,
      int? sharesWeight,
      int? rawValue,
    })>[
      for (var i = 0; i < n; i++)
        (
          name: participantNames[i],
          amountMinor: exactAmts[i],
          percentage: null,
          sharesWeight: null,
          rawValue: null,
        ),
    ];

    return _finalizeValidatedResult(
      title: rawTitle,
      totalMinor: totalMinor,
      topic: topic,
      method: SplitMethod.equal,
      payerExtract: payerExtract,
      draftShares: draftShares,
      currentUserId: currentUserId,
      currentUserName: currentUserName,
      knownMembers: knownMembers,
      nicknamesByUserId: nicknamesByUserId,
      explicitParticipantOverrides: explicitParticipantOverrides,
      includeRawValues: false,
    );
  }

  /// Recommends an exact-VND, constraint-aware monthly income & salary allocation plan.
  static SmartIncomeAllocationPlan recommendIncomeAllocation({
    required String prompt,
    int? explicitIncomeMinor,
    AllocationStrategyKind? forcedStrategy,
    FastTextBinaryModel? modelOverride,
  }) {
    final lower = prompt.trim().toLowerCase();
    final extractedAmounts = _extractLabeledAmounts(lower);
    final incomeMinor = math.max(
      1000000,
      explicitIncomeMinor ??
          extractedAmounts.incomeMinor ??
          25000000,
    );
    final fixedRentMinor = math.min(
      (incomeMinor * 0.65).round(),
      extractedAmounts.rentMinor ?? 0,
    );
    final fixedDebtMinor = math.min(
      (incomeMinor * 0.65).round(),
      extractedAmounts.debtMinor ?? 0,
    );

    final modelPred = classifyWithModel(prompt, modelOverride: modelOverride);

    final strategy = forcedStrategy ??
        _selectBestAllocationStrategy(
          lower: lower,
          modelPred: modelPred,
          fixedDebtMinor: fixedDebtMinor,
        );
    final confidence = forcedStrategy != null
        ? 1.0
        : (modelPred != null && modelPred.topLabel == strategy.labelKey
              ? modelPred.confidence
              : 0.91);

    final template = _strategyWeights(strategy);
    // Adapt weights when user explicitly has fixed rent or debt commitments!
    final weights = List<double>.from(template.weights);
    if (fixedDebtMinor > 0) {
      final debtPct = ((fixedDebtMinor / incomeMinor) * 100.0).clamp(10.0, 55.0);
      final essentialIdx = template.debtBucketIdx;
      if (essentialIdx != null) {
        weights[essentialIdx] = math.max(weights[essentialIdx], debtPct);
      }
    }
    if (fixedRentMinor > 0 && template.housingBucketIdx != null) {
      final rentPct = ((fixedRentMinor / incomeMinor) * 100.0).clamp(15.0, 50.0);
      weights[template.housingBucketIdx!] = math.max(
        weights[template.housingBucketIdx!],
        rentPct,
      );
    }

    final exactBucketAmts = apportionExactVnd(incomeMinor, weights);
    final weightTotal = weights.fold<double>(0.0, (a, b) => a + b);
    final exactPcts = apportionExactVnd(100, weights);

    final buckets = <AllocationBucketItem>[];
    var savingsSum = 0;
    for (var i = 0; i < template.specs.length; i++) {
      final spec = template.specs[i];
      if (spec.isSavings) {
        savingsSum += exactBucketAmts[i];
      }
      buckets.add(
        AllocationBucketItem(
          id: spec.id,
          titleVi: spec.titleVi,
          subtitleVi: spec.subtitleVi,
          percentage: weightTotal > 0 ? exactPcts[i] : 0,
          amountMinor: exactBucketAmts[i],
          isSavingsOrInvestment: spec.isSavings,
        ),
      );
    }

    final spendableMinor = math.max(0, incomeMinor - savingsSum);
    final discretionaryMinor = math.max(
      0,
      spendableMinor - fixedRentMinor - fixedDebtMinor,
    );
    final safeDailyMinor = discretionaryMinor ~/ 30;
    final savingsRatePct = (savingsSum * 100.0) / incomeMinor;

    // Map spendable portion cleanly into LifeOS Monthly Budget Categories
    final budgetDrafts = _buildBudgetCategoryDrafts(
      spendableMinor: spendableMinor,
      fixedRentMinor: fixedRentMinor,
      fixedDebtMinor: fixedDebtMinor,
      strategy: strategy,
    );

    return SmartIncomeAllocationPlan(
      monthlyIncomeMinor: incomeMinor,
      strategy: strategy,
      modelConfidence: confidence,
      rationaleVi: _buildRationaleVi(
        strategy: strategy,
        savingsRatePct: savingsRatePct,
        fixedRentMinor: fixedRentMinor,
        fixedDebtMinor: fixedDebtMinor,
      ),
      fixedCommitmentsMinor: fixedRentMinor + fixedDebtMinor,
      totalSavingsMinor: savingsSum,
      savingsRatePct: savingsRatePct,
      safeDailySpendMinor: safeDailyMinor,
      buckets: buckets,
      budgetDrafts: budgetDrafts,
    );
  }

  static AllocationStrategyKind _selectBestAllocationStrategy({
    required String lower,
    required MoneySplitModelPrediction? modelPred,
    required int fixedDebtMinor,
  }) {
    if (modelPred != null &&
        modelPred.topLabel.startsWith('alloc.') &&
        modelPred.confidence >= 0.62) {
      for (final s in AllocationStrategyKind.values) {
        if (s.labelKey == modelPred.topLabel) return s;
      }
    }
    if (fixedDebtMinor > 0 ||
        lower.contains('trả nợ') ||
        lower.contains('trả góp') ||
        lower.contains('thẻ tín dụng') ||
        lower.contains('snowball') ||
        lower.contains('avalanche')) {
      return AllocationStrategyKind.debtPayoff;
    }
    if (lower.contains('con nhỏ') ||
        lower.contains('em bé') ||
        lower.contains('bỉm') ||
        lower.contains('sữa') ||
        lower.contains('vợ chồng') ||
        lower.contains('gia đình')) {
      return AllocationStrategyKind.familyHousehold;
    }
    if (lower.contains('fire') ||
        lower.contains('tích lũy cao') ||
        lower.contains('tiết kiệm tối đa') ||
        lower.contains('mua nhà') ||
        lower.contains('mua xe') ||
        lower.contains('nghỉ hưu sớm')) {
      return AllocationStrategyKind.fireHighSavings;
    }
    if (lower.contains('6 lọ') ||
        lower.contains('6 chiếc lọ') ||
        lower.contains('sáu chiếc lọ') ||
        lower.contains('6 hũ')) {
      return AllocationStrategyKind.sixJars;
    }
    return AllocationStrategyKind.rule503020;
  }

  static ({
    List<({String id, String titleVi, String subtitleVi, bool isSavings})> specs,
    List<double> weights,
    int? housingBucketIdx,
    int? debtBucketIdx,
  }) _strategyWeights(AllocationStrategyKind strategy) {
    switch (strategy) {
      case AllocationStrategyKind.rule503020:
        return (
          specs: [
            (
              id: 'needs',
              titleVi: 'Nhu cầu Thiết yếu (50%)',
              subtitleVi: 'Nhà ở, ăn uống, điện nước, đi lại & y tế cơ bản',
              isSavings: false,
            ),
            (
              id: 'wants',
              titleVi: 'Cá nhân & Hưởng thụ (30%)',
              subtitleVi: 'Cà phê, mua sắm, giải trí, du lịch & đối ngoại',
              isSavings: false,
            ),
            (
              id: 'savings',
              titleVi: 'Tiết kiệm & Đầu tư (20%)',
              subtitleVi: 'Quỹ khẩn cấp 6 tháng, sổ tiết kiệm & ETF',
              isSavings: true,
            ),
          ],
          weights: [50.0, 30.0, 20.0],
          housingBucketIdx: 0,
          debtBucketIdx: 0,
        );
      case AllocationStrategyKind.sixJars:
        return (
          specs: [
            (
              id: 'nec',
              titleVi: 'Thiết yếu NEC (55%)',
              subtitleVi: 'Sinh hoạt hằng ngày, tiền nhà, hóa đơn, đi lại',
              isSavings: false,
            ),
            (
              id: 'ffa',
              titleVi: 'Tự do Tài chính FFA (10%)',
              subtitleVi: 'Đầu tư cổ phiếu, chứng chỉ quỹ, sinh lời dài hạn',
              isSavings: true,
            ),
            (
              id: 'ltss',
              titleVi: 'Tiết kiệm Dài hạn LTSS (10%)',
              subtitleVi: 'Quỹ dự phòng khẩn cấp & mục tiêu lớn',
              isSavings: true,
            ),
            (
              id: 'edu',
              titleVi: 'Giáo dục & Phát triển EDU (10%)',
              subtitleVi: 'Khóa học, sách vở, nâng cấp kỹ năng nghề nghiệp',
              isSavings: false,
            ),
            (
              id: 'play',
              titleVi: 'Hưởng thụ Cân bằng PLAY (10%)',
              subtitleVi: 'Giải trí, chăm sóc bản thân & trải nghiệm mới',
              isSavings: false,
            ),
            (
              id: 'give',
              titleVi: 'Cho đi & Hiếu hỉ GIVE (5%)',
              subtitleVi: 'Biếu bố mẹ, quà tặng, hiếu hỉ & thiện nguyện',
              isSavings: false,
            ),
          ],
          weights: [55.0, 10.0, 10.0, 10.0, 10.0, 5.0],
          housingBucketIdx: 0,
          debtBucketIdx: 0,
        );
      case AllocationStrategyKind.familyHousehold:
        return (
          specs: [
            (
              id: 'household_living',
              titleVi: 'Sinh hoạt Tổ ấm & Nhà cửa (45%)',
              subtitleVi: 'Tiền nhà, chợ búa, điện nước, vật tư gia đình',
              isSavings: false,
            ),
            (
              id: 'child_education',
              titleVi: 'Con cái, Sữa bỉm & Học phí (20%)',
              subtitleVi: 'Dinh dưỡng, học tập, tiêm chủng & chăm sóc bé',
              isSavings: false,
            ),
            (
              id: 'emergency_health',
              titleVi: 'Dự phòng Y tế & Tích lũy Gia đình (20%)',
              subtitleVi: 'Quỹ dự phòng ốm đau, bảo hiểm & tiết kiệm chung',
              isSavings: true,
            ),
            (
              id: 'parents_social',
              titleVi: 'Nội ngoại, Hiếu hỉ & Thư giãn (15%)',
              subtitleVi: 'Phụng dưỡng ông bà, đối ngoại & cuối tuần gia đình',
              isSavings: false,
            ),
          ],
          weights: [45.0, 20.0, 20.0, 15.0],
          housingBucketIdx: 0,
          debtBucketIdx: 0,
        );
      case AllocationStrategyKind.debtPayoff:
        return (
          specs: [
            (
              id: 'lean_essentials',
              titleVi: 'Sinh hoạt Tối giản Thiết yếu (45%)',
              subtitleVi: 'Giữ mức ăn ở, xăng xe cơ bản gọn gàng nhất',
              isSavings: false,
            ),
            (
              id: 'debt_accelerator',
              titleVi: 'Ưu tiên Tất toán Nợ & Lãi vay (35%)',
              subtitleVi: 'Trả gốc + lãi đúng hạn & dồn trả trước nợ lãi cao',
              isSavings: false,
            ),
            (
              id: 'safety_buffer',
              titleVi: 'Đệm Khẩn cấp Chống Vay lại (10%)',
              subtitleVi: 'Quỹ đệm tiền mặt để không phát sinh nợ mới',
              isSavings: true,
            ),
            (
              id: 'personal_breathing',
              titleVi: 'Chi tiêu Linh hoạt Nhỏ (10%)',
              subtitleVi: 'Khoản đệm tinh thần vừa đủ để duy trì kỷ luật bền',
              isSavings: false,
            ),
          ],
          weights: [45.0, 35.0, 10.0, 10.0],
          housingBucketIdx: 0,
          debtBucketIdx: 1,
        );
      case AllocationStrategyKind.fireHighSavings:
        return (
          specs: [
            (
              id: 'fire_invest',
              titleVi: 'Tích sản FIRE & Mua Tài sản (45%)',
              subtitleVi: 'Trích ngay khi nhận lương vào ETF, tiết kiệm, tích sản',
              isSavings: true,
            ),
            (
              id: 'smart_essentials',
              titleVi: 'Chi phí Cố định Tối ưu (38%)',
              subtitleVi: 'Nhà ở, ăn uống lành mạnh, di chuyển & hóa đơn',
              isSavings: false,
            ),
            (
              id: 'growth_lifestyle',
              titleVi: 'Phát triển Bản thân & Tận hưởng (17%)',
              subtitleVi: 'Học tập nâng thu nhập, sức khỏe & giải trí chọn lọc',
              isSavings: false,
            ),
          ],
          weights: [45.0, 38.0, 17.0],
          housingBucketIdx: 1,
          debtBucketIdx: 1,
        );
    }
  }

  static List<BudgetCategoryDraft> _buildBudgetCategoryDrafts({
    required int spendableMinor,
    required int fixedRentMinor,
    required int fixedDebtMinor,
    required AllocationStrategyKind strategy,
  }) {
    if (spendableMinor <= 0) return const <BudgetCategoryDraft>[];
    final hasDebt =
        fixedDebtMinor > 0 || strategy == AllocationStrategyKind.debtPayoff;

    final catSpecs = <({String id, String name, double weight})>[
      (id: 'cat_food', name: 'Ăn uống', weight: 28.0),
      (
        id: 'cat_housing',
        name: 'Nhà cửa & Thuê nhà',
        weight: fixedRentMinor > 0 ? 26.0 : 20.0,
      ),
      (id: 'cat_utilities', name: 'Điện/Nước/Internet', weight: 10.0),
      (
        id: 'cat_health',
        name: 'Sức khỏe & Giáo dục',
        weight: strategy == AllocationStrategyKind.familyHousehold ? 18.0 : 12.0,
      ),
      (
        id: 'cat_entertainment',
        name: 'Giải trí & Đăng ký',
        weight: strategy == AllocationStrategyKind.fireHighSavings ||
                strategy == AllocationStrategyKind.debtPayoff
            ? 8.0
            : 14.0,
      ),
      (
        id: 'cat_family_social',
        name: 'Hiếu hỉ & Đối ngoại',
        weight: strategy == AllocationStrategyKind.familyHousehold ? 12.0 : 8.0,
      ),
      if (hasDebt)
        (
          id: 'cat_debt',
          name: 'Trả nợ & Cho vay',
          weight: 28.0,
        ),
    ];

    final limits = apportionExactVnd(
      spendableMinor,
      catSpecs.map((e) => e.weight).toList(),
    );
    return [
      for (var i = 0; i < catSpecs.length; i++)
        BudgetCategoryDraft(
          categoryId: catSpecs[i].id,
          categoryName: catSpecs[i].name,
          limitMinor: limits[i],
        ),
    ];
  }

  static String _buildRationaleVi({
    required AllocationStrategyKind strategy,
    required double savingsRatePct,
    required int fixedRentMinor,
    required int fixedDebtMinor,
  }) {
    final rateStr = savingsRatePct.toStringAsFixed(0);
    final commitNote = (fixedRentMinor > 0 || fixedDebtMinor > 0)
        ? ' Đã tự động cân đối theo khoản cố định thuê nhà / trả góp trong câu nói.'
        : '';
    return switch (strategy) {
      AllocationStrategyKind.rule503020 =>
        'Cân bằng chuẩn mực giữa sinh hoạt, tận hưởng và tích lũy ($rateStr% thu nhập).$commitNote',
      AllocationStrategyKind.sixJars =>
        'Chia tách 6 quỹ độc lập giúp kiểm soát kỷ luật chi tiêu và đầu tư tự động ($rateStr% tích lũy).$commitNote',
      AllocationStrategyKind.familyHousehold =>
        'Ưu tiên an toàn dòng tiền tổ ấm, chi phí con nhỏ và quỹ dự phòng y tế ($rateStr% dự phòng).$commitNote',
      AllocationStrategyKind.debtPayoff =>
        'Tập trung dồn dòng tiền xóa nhanh nợ lãi cao đồng thời giữ quỹ đệm $rateStr% chống vay lại.$commitNote',
      AllocationStrategyKind.fireHighSavings =>
        'Trích trước $rateStr% thu nhập cho đầu tư & tích sản để rút ngắn tối đa thời gian đạt mục tiêu lớn.$commitNote',
    };
  }

  static ({int? incomeMinor, int? rentMinor, int? debtMinor})
      _extractLabeledAmounts(String lower) {
    int? income;
    int? rent;
    int? debt;

    final incMatch = RegExp(
      r'(?:lương|thu\s+nhập|tổng\s+thu|nhận)\s*(?:về\s+|tháng\s+này\s+|hai\s+vợ\s+chồng\s+)?(\d+(?:[.,]\d+)?\s*(?:tr|triệu|trieu|củ|cu|tỷ|ty)(?:\s*\d{1,3})?|\d{6,11})',
      caseSensitive: false,
      unicode: true,
    ).firstMatch(lower);
    if (incMatch != null) {
      income = _parseAmountToken(incMatch.group(1)!);
    }

    final rentMatch = RegExp(
      r'(?:thuê\s+nhà|tiền\s+nhà|tiền\s+trọ|thuê\s+phòng)\s*(\d+(?:[.,]\d+)?\s*(?:tr|triệu|trieu|củ|cu|k|nghìn|ngàn)(?:\s*\d{1,3})?|\d{6,11})',
      caseSensitive: false,
      unicode: true,
    ).firstMatch(lower);
    if (rentMatch != null) {
      rent = _parseAmountToken(rentMatch.group(1)!);
    }

    final debtMatch = RegExp(
      r'(?:trả\s+góp|trả\s+nợ|nợ\s+hàng\s+tháng|đóng\s+gốc\s+lãi|vay\s+ngân\s+hàng)\s*(?:xe\s+|nhà\s+)?(\d+(?:[.,]\d+)?\s*(?:tr|triệu|trieu|củ|cu|k|nghìn|ngàn)(?:\s*\d{1,3})?|\d{6,11})',
      caseSensitive: false,
      unicode: true,
    ).firstMatch(lower);
    if (debtMatch != null) {
      debt = _parseAmountToken(debtMatch.group(1)!);
    }

    if (income == null) {
      final first = _amountTokenRegex.firstMatch(lower);
      if (first != null) {
        income = _parseAmountToken(first.group(0)!);
      }
    }
    return (incomeMinor: income, rentMinor: rent, debtMinor: debt);
  }

  static ({
    String? payerId,
    String? payerName,
    String cleanedTitle,
    ParticipantResolutionOutcome? payerOutcome,
  }) _extractUpfrontPayer(
    String headBeforeTotal, {
    required String currentUserId,
    required String currentUserName,
    required List<FamilyMemberInfo> knownMembers,
    Map<String, List<String>> nicknamesByUserId =
        const <String, List<String>>{},
    Map<String, String> explicitParticipantOverrides = const <String, String>{},
  }) {
    final payerMatch = RegExp(
      r'^([A-Za-zÀ-ỹ]+(?:\s+[A-Za-zÀ-ỹ]+)?)\s+(?:trả\s+trước|ứng\s+trước|ứng|thanh\s+toán\s+trước|bao\s+trước)\s*(.*)$',
      caseSensitive: false,
      unicode: true,
    ).firstMatch(headBeforeTotal);
    if (payerMatch == null) {
      return (
        payerId: null,
        payerName: null,
        cleanedTitle: headBeforeTotal,
        payerOutcome: null,
      );
    }
    final rawPayer = _cleanParticipantCandidateName(payerMatch.group(1)!);
    if (rawPayer.isEmpty || _isStopWord(rawPayer)) {
      return (
        payerId: null,
        payerName: null,
        cleanedTitle: headBeforeTotal,
        payerOutcome: null,
      );
    }
    final outcome = ParticipantResolutionEngine.resolve(
      spokenName: rawPayer,
      index: 0,
      currentUserId: currentUserId,
      currentUserName: currentUserName,
      knownMembers: knownMembers,
      nicknamesByUserId: nicknamesByUserId,
      explicitOverridesBySpoken: explicitParticipantOverrides,
    );
    final restTitle = (payerMatch.group(2) ?? '').trim();
    return (
      payerId: outcome.participantId,
      payerName: outcome.displayName.isNotEmpty ? outcome.displayName : rawPayer,
      cleanedTitle: restTitle.isEmpty ? 'Khoản chi chung nhóm' : restTitle,
      payerOutcome: outcome,
    );
  }

  static List<({String name, int amountMinor})> _extractNamedExtras(
    String section,
  ) {
    final results = <({String name, int amountMinor})>[];
    final verbRegex = RegExp(
      r'([A-Za-zÀ-ỹ]+(?:\s+[A-Za-zÀ-ỹ]+)?)\s+(?:uống\s+thêm|gọi\s+thêm|mua\s+riêng|lấy\s+riêng|thêm|gọi\s+riêng|uống\s+riêng|tính\s+riêng|đặt\s+thêm)[^0-9]*?((?:-\s*|âm\s+)?(?:\d+(?:[.,]\d+)?\s*(?:tr|triệu|trieu|củ|cu|k|nghìn|nghin|ngàn|ngan)(?:\s*\d{1,3})?|\d{1,3}(?:[.,]\d{3})+|\d{5,11}|0\s*(?:đ|₫|vnđ|vnd|đồng|dong)))',
      caseSensitive: false,
      unicode: true,
    );
    for (final m in verbRegex.allMatches(section)) {
      final cleaned = _cleanParticipantCandidateName(m.group(1)!);
      if (cleaned.isEmpty || _isStopWord(cleaned)) continue;
      final token = m.group(2)!.trim();
      final isNeg = RegExp(r'^(?:-|âm\b)', caseSensitive: false).hasMatch(token);
      final amt = isNeg ? 0 : (_parseAmountToken(token) ?? 0);
      results.add((name: cleaned, amountMinor: amt));
    }
    if (results.isEmpty && section.trim().isNotEmpty) {
      final fallbackRegex = RegExp(
        r'([A-Za-zÀ-ỹ]+(?:\s+[A-Za-zÀ-ỹ]+)?)\s+(?:đóng\s+|trả\s+|chịu\s+|uống\s+|ăn\s+)?((?:-\s*|âm\s+)?(?:\d+(?:[.,]\d+)?\s*(?:tr|triệu|trieu|củ|cu|k|nghìn|nghin|ngàn|ngan)(?:\s*\d{1,3})?|\d{1,3}(?:[.,]\d{3})+|\d{5,11}|0\s*(?:đ|₫|vnđ|vnd|đồng|dong)))',
        caseSensitive: false,
        unicode: true,
      );
      for (final m in fallbackRegex.allMatches(section)) {
        final cleaned = _cleanParticipantCandidateName(m.group(1)!);
        if (cleaned.isEmpty || _isStopWord(cleaned)) continue;
        final token = m.group(2)!.trim();
        final isNeg = RegExp(r'^(?:-|âm\b)', caseSensitive: false).hasMatch(token);
        final amt = isNeg ? 0 : (_parseAmountToken(token) ?? 0);
        results.add((name: cleaned, amountMinor: amt));
      }
    }
    return results;
  }

  static List<String> _resolveEqualParticipantNames(
    String clause, {
    required String currentUserName,
    required List<FamilyMemberInfo> knownMembers,
    List<String> mustIncludeNames = const <String>[],
  }) {
    final lower = clause.toLowerCase();

    // Check "cưa đôi với <Name>" / "chia đôi với <Name>"
    final pairWithMatch = RegExp(
      r'(?:cưa\s+đôi|chia\s+đôi)\s+(?:với|cùng)\s+([A-Za-zÀ-ỹ]+(?:\s+[A-Za-zÀ-ỹ]+)?)',
      caseSensitive: false,
      unicode: true,
    ).firstMatch(clause);
    if (pairWithMatch != null) {
      final partner = _cleanParticipantCandidateName(pairWithMatch.group(1)!);
      if (partner.isNotEmpty) {
        return <String>[currentUserName, partner];
      }
    }
    if (lower.contains('cưa đôi') || lower.contains('chia đôi')) {
      if (knownMembers.length >= 2) {
        return knownMembers.take(2).map((m) => m.fullName).toList();
      }
      return <String>[currentUserName, 'Thành viên 2'];
    }

    // Check spoken number headcount ("chia đều 4 người", "campuchia 5 anh em", "4 người chia đều")
    final countMatch = RegExp(
      r'(?:chia\s*(?:đều)?\s*(?:cho\s*)?|campuchia\s*(?:đều)?\s*(?:cho\s*)?|mỗi\s+người\s+)?(\d{1,2}|hai|ba|bốn|tư|năm|sáu|bảy|tám|chín|mười)\s*(?:người|bạn|anh\s+em|chị\s+em|đứa|thành\s+viên|đồng\s+nghiệp)\b|(?:chia\s*(?:đều)?\s*(?:cho\s*)?|campuchia\s*)(\d{1,2})\b',
      caseSensitive: false,
      unicode: true,
    ).firstMatch(clause);

    var participantNames = <String>[];
    if (countMatch != null) {
      final token = (countMatch.group(1) ?? countMatch.group(2) ?? '2').trim();
      final count = (_parseHeadcountToken(token) ?? 2).clamp(2, 20);
      if (knownMembers.length >= count && mustIncludeNames.isEmpty) {
        participantNames = knownMembers
            .take(count)
            .map((m) => m.fullName)
            .toList();
      } else {
        final seeded = <String>[];
        for (final inc in mustIncludeNames) {
          if (!seeded.any((s) => s.toLowerCase() == inc.toLowerCase())) {
            seeded.add(inc);
          }
        }
        if (!seeded.any(
              (s) => s.toLowerCase() == currentUserName.toLowerCase(),
            ) &&
            seeded.length < count) {
          seeded.insert(0, currentUserName);
        }
        var idx = seeded.length + 1;
        while (seeded.length < count) {
          seeded.add('Thành viên $idx');
          idx++;
        }
        participantNames = seeded.take(count).toList();
      }
      return participantNames;
    }

    // Named list after "chia cho" / "chia đều cho" / "cho" / "với"
    final namesClauseMatch = RegExp(
      r'(?:chia\s*(?:đều)?\s*cho|campuchia\s*(?:đều)?\s*cho|cùng\s+với|với)\s+(.+)$',
      caseSensitive: false,
      unicode: true,
    ).firstMatch(clause);
    if (namesClauseMatch != null) {
      final rawNames = namesClauseMatch
          .group(1)!
          .split(RegExp(r'\s*(?:,|và|với|&)\s*', caseSensitive: false))
          .map(
            (s) => s
                .replaceAll(RegExp(r'[^A-Za-zÀ-ỹ\s]', unicode: true), '')
                .trim(),
          )
          .where((s) => s.isNotEmpty && !_isStopWord(s))
          .map(_capitalizeName)
          .toList();
      if (rawNames.length == 1) {
        participantNames = [currentUserName, rawNames.single];
      } else if (rawNames.length >= 2) {
        participantNames = rawNames;
      }
    }

    if (participantNames.isEmpty) {
      if (knownMembers.length >= 2) {
        participantNames = knownMembers.map((m) => m.fullName).toList();
      } else if (mustIncludeNames.isNotEmpty) {
        participantNames = <String>{
          currentUserName,
          ...mustIncludeNames,
        }.toList();
        if (participantNames.length < 2) {
          participantNames.add('Thành viên 2');
        }
      } else {
        participantNames = [currentUserName, 'Thành viên 2'];
      }
    }
    return participantNames;
  }

  static int? _parseHeadcountToken(String raw) {
    final asInt = int.tryParse(raw);
    if (asInt != null) return asInt;
    return switch (raw.toLowerCase()) {
      'hai' || 'đôi' => 2,
      'ba' => 3,
      'bốn' || 'tư' => 4,
      'năm' => 5,
      'sáu' => 6,
      'bảy' => 7,
      'tám' => 8,
      'chín' => 9,
      'mười' => 10,
      _ => null,
    };
  }

  static int? _parseAmountToken(String token) {
    final trimmed = token.trim();
    if (trimmed.isEmpty) return null;
    final bilMatch = RegExp(
      r'^(\d+(?:[.,]\d+)?)\s*(?:tỷ|ty)\b(?:\s*(\d{1,3}))?',
      caseSensitive: false,
      unicode: true,
    ).firstMatch(trimmed);
    if (bilMatch != null) {
      final rawWhole = (bilMatch.group(1) ?? '').replaceAll(',', '.');
      final parts = rawWhole.split('.');
      final whole = int.tryParse(parts[0]) ?? 0;
      var minor = whole * 1000000000;
      if (parts.length > 1 && parts[1].isNotEmpty) {
        final frac = parts[1].padRight(9, '0').substring(0, 9);
        minor += int.parse(frac);
      } else if ((bilMatch.group(2) ?? '').isNotEmpty) {
        final mil = int.tryParse(bilMatch.group(2)!) ?? 0;
        minor += mil * 1000000;
      }
      return minor > 0 ? minor : null;
    }
    final entry = SmartQuickEntryParser.tryParse('chi $trimmed');
    return entry?.amountMinor;
  }

  static List<RegExpMatch> _extractValidMoneyMatches(String text) {
    final matches = <RegExpMatch>[];
    for (final m in _amountTokenRegex.allMatches(text)) {
      final token = m.group(0) ?? '';
      final hasSuffix = RegExp(
        r'(?:đ|₫|vnđ|vnd|đồng|dong|tỷ|ty|triệu|trieu|tr|củ|cu|nghìn|nghin|ngàn|ngan|k|xị|xi|lít|lit|cành|canh)\s*$',
        caseSensitive: false,
        unicode: true,
      ).hasMatch(token.trim());
      if (VietnameseTemporalAndEntityResolver.isFollowedByNonCurrencyUnit(
        text,
        m.end,
        hasExplicitCurrencySuffix: hasSuffix,
      )) {
        continue;
      }
      matches.add(m);
    }
    return matches;
  }

  static bool _hasNegativeMoneyBeforeOrAtFirst(String text, int? firstStart) {
    final head = firstStart == null ? text : text.substring(0, firstStart);
    if (RegExp(
      r'(?:^|[\s,(])(?:-\s*|âm\s+|am\s+)$',
      caseSensitive: false,
      unicode: true,
    ).hasMatch(head)) {
      return true;
    }
    if (RegExp(
      r'(?:^|[\s,(])(?:-\s*\d|âm\s+\d|am\s+\d)',
      caseSensitive: false,
      unicode: true,
    ).hasMatch(head)) {
      return true;
    }
    if (RegExp(
      r'\b0\s*(?:đ|₫|vnđ|vnd|đồng|dong|k|tr|triệu|củ)\b',
      caseSensitive: false,
      unicode: true,
    ).hasMatch(head)) {
      return true;
    }
    if (firstStart == null &&
        RegExp(
          r'(?:^|[\s,(])(?:-\s*\d|âm\s+\d|am\s+\d)',
          caseSensitive: false,
          unicode: true,
        ).hasMatch(text)) {
      return true;
    }
    return false;
  }

  static int? _extractDeclaredHeadcount(String afterFirstAmount) {
    final m = RegExp(
      r'^(?:[,;:\s]*)?(?:chia|cho)\s+(\d{1,2}|hai|ba|bốn|tư|năm|sáu|bảy|tám|chín|mười)\s*(?:người|bạn|anh\s+em|chị\s+em|thành\s+viên)\b',
      caseSensitive: false,
      unicode: true,
    ).firstMatch(afterFirstAmount);
    if (m == null) return null;
    final parsed = _parseHeadcountToken(m.group(1)!);
    if (parsed == null || parsed < 2) return null;
    // Ignore when followed by "chia đều" (e.g. "chia 4 người đều" handled by equal/remainder)
    final tail = afterFirstAmount.substring(m.end).trim().toLowerCase();
    if (tail.isEmpty || tail.startsWith('đều')) return null;
    return parsed;
  }

  static AdvancedGroupSplitParseResult _invalidSplitResult({
    required String title,
    required int totalMinor,
    required SharedExpenseTopic topic,
    required SplitMethod method,
    required ({
      String? payerId,
      String? payerName,
      String cleanedTitle,
      ParticipantResolutionOutcome? payerOutcome,
    }) payerExtract,
    required SplitValidationStatus status,
    required String messageVi,
    List<ParticipantResolutionOutcome> ambiguousParticipants =
        const <ParticipantResolutionOutcome>[],
  }) {
    return AdvancedGroupSplitParseResult(
      title: title,
      totalAmountMinor: totalMinor,
      topic: topic,
      splitMethod: method,
      paidByParticipantId: payerExtract.payerId,
      paidByDisplayName: payerExtract.payerName,
      shares: const [],
      rawInputValuesByUserId: const <String, int>{},
      validationStatus: status,
      validationMessageVi: messageVi,
      ambiguousParticipants: ambiguousParticipants,
    );
  }

  static AdvancedGroupSplitParseResult _finalizeValidatedResult({
    required String title,
    required int totalMinor,
    required SharedExpenseTopic topic,
    required SplitMethod method,
    required ({
      String? payerId,
      String? payerName,
      String cleanedTitle,
      ParticipantResolutionOutcome? payerOutcome,
    }) payerExtract,
    required List<
      ({
        String name,
        int amountMinor,
        int? percentage,
        int? sharesWeight,
        int? rawValue,
      })
    >
    draftShares,
    required String currentUserId,
    required String currentUserName,
    required List<FamilyMemberInfo> knownMembers,
    required Map<String, List<String>> nicknamesByUserId,
    required Map<String, String> explicitParticipantOverrides,
    required bool includeRawValues,
    SplitValidationStatus? postResolutionStatusOverride,
    String? postResolutionMessageOverride,
  }) {
    final ambiguousOutcomes = <ParticipantResolutionOutcome>[];
    if (payerExtract.payerOutcome != null &&
        payerExtract.payerOutcome!.isAmbiguous) {
      ambiguousOutcomes.add(payerExtract.payerOutcome!);
    }

    final shares = <({
      String participantId,
      String displayName,
      int amountMinor,
      int? percentage,
      int? sharesWeight,
    })>[];
    final rawMap = <String, int>{};
    final seenIdentityKeys = <String>{};
    String? duplicateDisplayName;

    for (var i = 0; i < draftShares.length; i++) {
      final item = draftShares[i];
      final outcome = ParticipantResolutionEngine.resolve(
        spokenName: item.name,
        index: i,
        currentUserId: currentUserId,
        currentUserName: currentUserName,
        knownMembers: knownMembers,
        nicknamesByUserId: nicknamesByUserId,
        explicitOverridesBySpoken: explicitParticipantOverrides,
      );
      if (outcome.isAmbiguous) {
        ambiguousOutcomes.add(outcome);
      }

      final isKnownParticipant =
          outcome.status == ParticipantResolutionStatus.resolved ||
          outcome.participantId == currentUserId;
      final identityKey = isKnownParticipant
          ? outcome.participantId
          : 'guest:${FinancialTextNormalizer.stripVnAccents(item.name).replaceAll(RegExp(r'\s+'), '_')}';
      if (!seenIdentityKeys.add(identityKey)) {
        duplicateDisplayName ??=
            outcome.displayName.isNotEmpty ? outcome.displayName : item.name;
      }

      final display =
          outcome.displayName.isNotEmpty ? outcome.displayName : item.name;
      if (includeRawValues && item.rawValue != null) {
        rawMap[outcome.participantId] = item.rawValue!;
      }
      shares.add((
        participantId: outcome.participantId,
        displayName: display,
        amountMinor: item.amountMinor,
        percentage: item.percentage,
        sharesWeight: item.sharesWeight,
      ));
    }

    var status = SplitValidationStatus.valid;
    String? messageVi;
    if (ambiguousOutcomes.isNotEmpty) {
      final firstAmb = ambiguousOutcomes.first;
      final candList = firstAmb.ambiguousCandidates
          .map((c) => c.displayName)
          .join(', ');
      status = SplitValidationStatus.ambiguousParticipant;
      messageVi = candList.isNotEmpty
          ? 'Tên "${firstAmb.spokenName}" có thể là nhiều người ($candList). Vui lòng chọn đúng thành viên.'
          : 'Có thành viên trùng tên "${firstAmb.spokenName}", vui lòng chọn đúng người trước khi lưu.';
    } else if (duplicateDisplayName != null) {
      status = SplitValidationStatus.duplicateParticipant;
      messageVi =
          'Thành viên "$duplicateDisplayName" bị trùng trong danh sách chia tiền.';
    } else if (postResolutionStatusOverride != null) {
      status = postResolutionStatusOverride;
      messageVi = postResolutionMessageOverride;
    }

    return AdvancedGroupSplitParseResult(
      title: title,
      totalAmountMinor: totalMinor,
      topic: topic,
      splitMethod: method,
      paidByParticipantId: payerExtract.payerId,
      paidByDisplayName: payerExtract.payerName,
      shares: shares,
      rawInputValuesByUserId: includeRawValues ? rawMap : const <String, int>{},
      validationStatus: status,
      validationMessageVi: messageVi,
      ambiguousParticipants: ambiguousOutcomes,
    );
  }

  static String _formatVndStatic(int minor) {
    final abs = minor.abs();
    final str = abs.toString();
    final buf = StringBuffer();
    for (var i = 0; i < str.length; i++) {
      final revIdx = str.length - i;
      if (i > 0 && revIdx % 3 == 0) {
        buf.write('.');
      }
      buf.write(str[i]);
    }
    return '${minor < 0 ? '-' : ''}${buf.toString()} ₫';
  }

  static String _cleanParticipantCandidateName(String raw) {
    var tokens = raw
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    while (tokens.isNotEmpty && _isStopWord(tokens.first)) {
      tokens = tokens.sublist(1);
    }
    while (tokens.isNotEmpty && _isStopWord(tokens.last)) {
      tokens = tokens.sublist(0, tokens.length - 1);
    }
    if (tokens.isEmpty) return '';
    return _capitalizeName(tokens.join(' '));
  }

  static bool _isStopWord(String word) {
    const stops = {
      'chia',
      'đều',
      'cho',
      'với',
      'người',
      'mỗi',
      'còn',
      'lại',
      'chịu',
      'trả',
      'gồm',
      'tổng',
      'phần',
      'suất',
      'số',
      'cả',
      'nhóm',
      'bàn',
      'campuchia',
      'cưa',
      'đôi',
      'tiền',
      'hóa',
      'đơn',
      'hôm',
      'nay',
      'qua',
      'và',
      'nhưng',
      'của',
      'thì',
      'là',
      'nhà',
      'bạn',
      'anh',
      'chị',
      'em',
      'đứa',
      'triệu',
      'trieu',
      'nghìn',
      'nghin',
      'ngàn',
      'ngan',
      'trăm',
      'tram',
      'đồng',
      'dong',
      'vnd',
      'vnđ',
      'âm',
      'khoản',
      'phân',
      'bổ',
      'ăn',
      'uống',
      'đi',
      'chơi',
      'tiệc',
    };
    return stops.contains(word.toLowerCase().trim());
  }

  static String _capitalizeName(String raw) {
    return raw
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .map((w) => '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
        .join(' ');
  }
}
