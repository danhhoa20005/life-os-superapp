import 'package:equatable/equatable.dart';

import '../../../transactions/domain/entities/transaction_entities.dart';

/// Injectable clock abstraction so relative Vietnamese date parsing ("hôm qua",
/// "sáng nay", "thứ hai tuần trước") is 100% deterministic in unit tests.
abstract interface class FinancialClock {
  DateTime now();
}

final class SystemFinancialClock implements FinancialClock {
  const SystemFinancialClock();

  @override
  DateTime now() => DateTime.now();
}

final class FixedFinancialClock implements FinancialClock {
  final DateTime fixedNow;
  const FixedFinancialClock(this.fixedNow);

  @override
  DateTime now() => fixedNow;
}

enum FinancialInputSource {
  manualText,
  voiceTranscript,
  androidBankNotification,
  clipboard,
  bankFeed,
}

/// Canonical 10 transaction types (Phase 6) + explicit `nonTransaction` guard
/// for balance statements, negations, OTPs, and cancellation commands.
enum FinancialTransactionType {
  income,
  expense,
  internalTransfer,
  externalTransfer,
  refund,
  reversal,
  loanDisbursement,
  loanRepayment,
  investmentTransfer,
  unknown,
  nonTransaction;

  String get wireKey => switch (this) {
    FinancialTransactionType.income => 'income',
    FinancialTransactionType.expense => 'expense',
    FinancialTransactionType.internalTransfer => 'internal_transfer',
    FinancialTransactionType.externalTransfer => 'external_transfer',
    FinancialTransactionType.refund => 'refund',
    FinancialTransactionType.reversal => 'reversal',
    FinancialTransactionType.loanDisbursement => 'loan_disbursement',
    FinancialTransactionType.loanRepayment => 'loan_repayment',
    FinancialTransactionType.investmentTransfer => 'investment_transfer',
    FinancialTransactionType.unknown => 'unknown',
    FinancialTransactionType.nonTransaction => 'non_transaction',
  };

  String get displayLabelVi => switch (this) {
    FinancialTransactionType.income => 'Thu nhập',
    FinancialTransactionType.expense => 'Chi tiêu',
    FinancialTransactionType.internalTransfer => 'Chuyển nội bộ / Rút ATM',
    FinancialTransactionType.externalTransfer => 'Chuyển tiền cho người khác',
    FinancialTransactionType.refund => 'Hoàn tiền (Refund)',
    FinancialTransactionType.reversal => 'Đảo / Hủy bút toán',
    FinancialTransactionType.loanDisbursement => 'Giải ngân / Đi vay',
    FinancialTransactionType.loanRepayment => 'Trả nợ vay',
    FinancialTransactionType.investmentTransfer => 'Chuyển đầu tư / Tiết kiệm',
    FinancialTransactionType.unknown => 'Chưa rõ loại giao dịch',
    FinancialTransactionType.nonTransaction => 'Không phải giao dịch mới',
  };

  /// Direction used for category lookup when applicable ('debit' | 'credit' | 'transfer').
  String get expectedDirection => switch (this) {
    FinancialTransactionType.income ||
    FinancialTransactionType.refund ||
    FinancialTransactionType.loanDisbursement => 'credit',
    FinancialTransactionType.internalTransfer ||
    FinancialTransactionType.investmentTransfer => 'transfer',
    _ => 'debit',
  };

  /// Maps safely onto LifeOS's immutable ledger `TransactionKind` (null when non-postable).
  TransactionKind? get toLedgerKind => switch (this) {
    FinancialTransactionType.income => TransactionKind.income,
    FinancialTransactionType.expense ||
    FinancialTransactionType.externalTransfer ||
    FinancialTransactionType.loanRepayment => TransactionKind.expense,
    FinancialTransactionType.internalTransfer ||
    FinancialTransactionType.investmentTransfer => TransactionKind.transfer,
    // Refunds & loan disbursements increase wallet balance (`credit`), but carry explicit category/note
    // so they are never conflated with regular salary income!
    FinancialTransactionType.refund ||
    FinancialTransactionType.loanDisbursement => TransactionKind.income,
    FinancialTransactionType.reversal => TransactionKind.reversal,
    FinancialTransactionType.unknown ||
    FinancialTransactionType.nonTransaction => null,
  };

  bool get createsStandardPnlImpact =>
      this == FinancialTransactionType.income ||
      this == FinancialTransactionType.expense ||
      this == FinancialTransactionType.externalTransfer ||
      this == FinancialTransactionType.loanRepayment;
}

enum ConfidenceTier {
  highConfidence,
  mediumConfidence,
  lowConfidence,
  unknown;

  String get wireKey => switch (this) {
    ConfidenceTier.highConfidence => 'high_confidence',
    ConfidenceTier.mediumConfidence => 'medium_confidence',
    ConfidenceTier.lowConfidence => 'low_confidence',
    ConfidenceTier.unknown => 'unknown',
  };

  String get displayLabelVi => switch (this) {
    ConfidenceTier.highConfidence => 'Độ tin cậy cao',
    ConfidenceTier.mediumConfidence => 'Khá chắc chắn · Nên kiểm tra',
    ConfidenceTier.lowConfidence => 'Độ tin cậy thấp · Cần chọn lại',
    ConfidenceTier.unknown => 'Chưa xác định · Chờ phân loại',
  };
}

enum AmbiguityFlag {
  ambiguousDecimalOrThousands,
  missingAmount,
  zeroOrNegativeAmount,
  missingSourceWallet,
  missingDestinationWalletForTransfer,
  multipleMatchingUserCategories,
  unmappedUserCategory,
  lowCategoryConfidence,
  ambiguousTransactionType,
  potentialDuplicate,
  balanceStatementNotIncome,
  negatedStatement,
  cancellationCommandNotExpense,
  otpOrSensitiveBlocked,
}

enum ClassifierInferenceOrigin {
  personalizationRule,
  fastTextNativeFfi,
  fastTextIsolateInt8,
  deterministicRuleFallback,
  fakeTestClassifier,
}

/// Multi-dimensional confidence vector (Phase 11 — never a naive arithmetic mean).
class ClassificationConfidence extends Equatable {
  final double amountConfidence;
  final double typeConfidence;
  final double categoryConfidence;
  final double merchantConfidence;
  final double sourceConfidence;
  final ConfidenceTier tier;
  final bool canAutoPostUnderPolicy;

  const ClassificationConfidence({
    required this.amountConfidence,
    required this.typeConfidence,
    required this.categoryConfidence,
    required this.merchantConfidence,
    required this.sourceConfidence,
    required this.tier,
    required this.canAutoPostUnderPolicy,
  });

  /// Bottleneck score governed by critical financial fields (`amount`, `type`, `category`).
  double get criticalFloorScore {
    var minVal = amountConfidence;
    if (typeConfidence < minVal) minVal = typeConfidence;
    if (categoryConfidence < minVal) minVal = categoryConfidence;
    return minVal;
  }

  @override
  List<Object?> get props => [
    amountConfidence,
    typeConfidence,
    categoryConfidence,
    merchantConfidence,
    sourceConfidence,
    tier,
    canAutoPostUnderPolicy,
  ];
}

class CategoryPrediction extends Equatable {
  final String semanticKey;
  final String suggestedDisplayName;
  final double probability;
  final ClassifierInferenceOrigin origin;

  const CategoryPrediction({
    required this.semanticKey,
    required this.suggestedDisplayName,
    required this.probability,
    required this.origin,
  });

  @override
  List<Object?> get props => [
    semanticKey,
    suggestedDisplayName,
    probability,
    origin,
  ];
}

class ClassificationResult extends Equatable {
  final List<CategoryPrediction> predictions;
  final int latencyMicros;
  final String modelVersion;
  final ClassifierInferenceOrigin origin;
  final bool usedFallback;

  const ClassificationResult({
    required this.predictions,
    required this.latencyMicros,
    required this.modelVersion,
    required this.origin,
    this.usedFallback = false,
  });

  CategoryPrediction get topPrediction => predictions.isNotEmpty
      ? predictions.first
      : const CategoryPrediction(
          semanticKey: 'other',
          suggestedDisplayName: 'Chi tiêu khác',
          probability: 0.0,
          origin: ClassifierInferenceOrigin.deterministicRuleFallback,
        );

  @override
  List<Object?> get props => [
    predictions,
    latencyMicros,
    modelVersion,
    origin,
    usedFallback,
  ];
}

class FinancialModelMetadata extends Equatable {
  final String modelId;
  final String modelVersion;
  final String architecture;
  final String license;
  final int sizeBytes;
  final String sha256;
  final int numClasses;
  final double calibratedTemperature;
  final double highConfidenceThreshold;
  final double mediumConfidenceThreshold;
  final double lowConfidenceThreshold;
  final bool isLoaded;
  final bool isNativeFfiActive;
  final bool usingRuleFallback;

  const FinancialModelMetadata({
    required this.modelId,
    required this.modelVersion,
    required this.architecture,
    this.license = 'MIT',
    required this.sizeBytes,
    required this.sha256,
    required this.numClasses,
    this.calibratedTemperature = 1.0,
    this.highConfidenceThreshold = 0.78,
    this.mediumConfidenceThreshold = 0.52,
    this.lowConfidenceThreshold = 0.32,
    this.isLoaded = false,
    this.isNativeFfiActive = false,
    this.usingRuleFallback = false,
  });

  static const FinancialModelMetadata fallbackMetadata = FinancialModelMetadata(
    modelId: 'rule_fallback_v1',
    modelVersion: '1.0.0-fallback',
    architecture: 'Deterministic Vietnamese Rule Classifier',
    sizeBytes: 0,
    sha256: '',
    numClasses: 30,
    isLoaded: true,
    isNativeFfiActive: false,
    usingRuleFallback: true,
  );

  @override
  List<Object?> get props => [
    modelId,
    modelVersion,
    architecture,
    sizeBytes,
    sha256,
    numClasses,
    calibratedTemperature,
    isLoaded,
    isNativeFfiActive,
    usingRuleFallback,
  ];
}

/// Preserves both original and normalized text with full temporal & locale context (Phase 4.6).
class FinancialAnalysisRequest extends Equatable {
  final String requestId;
  final String userId;
  final String originalText;
  final String normalizedText;
  final FinancialInputSource source;
  final String locale;
  final DateTime referenceTime;
  final int timezoneOffsetMinutes;
  final String? preferredWalletId;
  final String? familyId;
  final String? externalReferenceId;

  const FinancialAnalysisRequest({
    required this.requestId,
    required this.userId,
    required this.originalText,
    required this.normalizedText,
    this.source = FinancialInputSource.manualText,
    this.locale = 'vi_VN',
    required this.referenceTime,
    this.timezoneOffsetMinutes = 420,
    this.preferredWalletId,
    this.familyId,
    this.externalReferenceId,
  });

  @override
  List<Object?> get props => [
    requestId,
    userId,
    originalText,
    normalizedText,
    source,
    locale,
    referenceTime,
    timezoneOffsetMinutes,
    preferredWalletId,
    familyId,
    externalReferenceId,
  ];
}

/// Structured financial entity extracted from a single transaction clause (Phase 5).
class ExtractedFinancialEntity extends Equatable {
  final String rawSegment;
  final String normalizedSegment;
  final String classifierInput;
  final int? amountMinor;
  final String currencyCode;
  final int currencyDecimalDigits;
  final FinancialTransactionType transactionType;
  final DateTime? explicitOccurredAt;
  final String? merchant;
  final String? merchantCanonicalKey;
  final String description;
  final String? sourceAccountHint;
  final String? destinationAccountHint;
  final String? recipient;
  final String? paymentMethod;
  final String? candidateSemanticKey;
  final double amountConfidence;
  final double typeConfidence;
  final double merchantConfidence;
  final List<AmbiguityFlag> ambiguityFlags;

  const ExtractedFinancialEntity({
    required this.rawSegment,
    required this.normalizedSegment,
    required this.classifierInput,
    required this.amountMinor,
    this.currencyCode = 'VND',
    this.currencyDecimalDigits = 0,
    required this.transactionType,
    this.explicitOccurredAt,
    this.merchant,
    this.merchantCanonicalKey,
    required this.description,
    this.sourceAccountHint,
    this.destinationAccountHint,
    this.recipient,
    this.paymentMethod,
    this.candidateSemanticKey,
    required this.amountConfidence,
    required this.typeConfidence,
    required this.merchantConfidence,
    this.ambiguityFlags = const [],
  });

  @override
  List<Object?> get props => [
    rawSegment,
    normalizedSegment,
    classifierInput,
    amountMinor,
    currencyCode,
    currencyDecimalDigits,
    transactionType,
    explicitOccurredAt,
    merchant,
    merchantCanonicalKey,
    description,
    sourceAccountHint,
    destinationAccountHint,
    recipient,
    paymentMethod,
    candidateSemanticKey,
    amountConfidence,
    typeConfidence,
    merchantConfidence,
    ambiguityFlags,
  ];
}

class ResolvedCategoryMatch extends Equatable {
  final String? categoryId;
  final String displayCategoryName;
  final String suggestedCategoryName;
  final String semanticKey;
  final bool hasExactUserCategory;
  final bool hasMultipleMatches;

  const ResolvedCategoryMatch({
    required this.categoryId,
    required this.displayCategoryName,
    required this.suggestedCategoryName,
    required this.semanticKey,
    required this.hasExactUserCategory,
    this.hasMultipleMatches = false,
  });

  @override
  List<Object?> get props => [
    categoryId,
    displayCategoryName,
    suggestedCategoryName,
    semanticKey,
    hasExactUserCategory,
    hasMultipleMatches,
  ];
}

/// Complete, editable Transaction Draft produced by the Hybrid Financial AI Engine.
class TransactionCandidate extends Equatable {
  final String draftId;
  final String userId;
  final FinancialInputSource source;
  final ExtractedFinancialEntity extracted;
  final FinancialTransactionType transactionType;
  final int amountMinor;
  final String currencyCode;
  final String description;
  final String? merchant;
  final String? merchantCanonicalKey;
  final CategoryPrediction topPrediction;
  final List<CategoryPrediction> alternativePredictions;
  final String? resolvedCategoryId;
  final String resolvedCategoryName;
  final String suggestedCategoryName;
  final String? sourceWalletId;
  final String? destinationWalletId;
  final DateTime occurredAt;
  final bool hasExplicitDate;
  final ClassificationConfidence confidence;
  final List<AmbiguityFlag> ambiguityFlags;
  final bool requiresConfirmation;
  final bool isDuplicateCandidate;
  final String? duplicateOfTransactionId;
  final String transactionFingerprint;
  final String? appliedPersonalizationRuleId;

  const TransactionCandidate({
    required this.draftId,
    required this.userId,
    required this.source,
    required this.extracted,
    required this.transactionType,
    required this.amountMinor,
    this.currencyCode = 'VND',
    required this.description,
    this.merchant,
    this.merchantCanonicalKey,
    required this.topPrediction,
    this.alternativePredictions = const [],
    this.resolvedCategoryId,
    required this.resolvedCategoryName,
    required this.suggestedCategoryName,
    this.sourceWalletId,
    this.destinationWalletId,
    required this.occurredAt,
    required this.hasExplicitDate,
    required this.confidence,
    this.ambiguityFlags = const [],
    required this.requiresConfirmation,
    this.isDuplicateCandidate = false,
    this.duplicateOfTransactionId,
    required this.transactionFingerprint,
    this.appliedPersonalizationRuleId,
  });

  bool get isReadyToConfirm =>
      amountMinor > 0 &&
      transactionType.toLedgerKind != null &&
      sourceWalletId != null &&
      sourceWalletId!.isNotEmpty &&
      (transactionType.toLedgerKind != TransactionKind.transfer ||
          (destinationWalletId != null &&
              destinationWalletId!.isNotEmpty &&
              destinationWalletId != sourceWalletId));

  TransactionCandidate copyWith({
    FinancialTransactionType? transactionType,
    int? amountMinor,
    String? description,
    String? merchant,
    String? resolvedCategoryId,
    bool clearResolvedCategoryId = false,
    String? resolvedCategoryName,
    String? suggestedCategoryName,
    String? sourceWalletId,
    String? destinationWalletId,
    bool clearDestinationWalletId = false,
    DateTime? occurredAt,
    bool? requiresConfirmation,
    List<AmbiguityFlag>? ambiguityFlags,
  }) {
    return TransactionCandidate(
      draftId: draftId,
      userId: userId,
      source: source,
      extracted: extracted,
      transactionType: transactionType ?? this.transactionType,
      amountMinor: amountMinor ?? this.amountMinor,
      currencyCode: currencyCode,
      description: description ?? this.description,
      merchant: merchant ?? this.merchant,
      merchantCanonicalKey: merchantCanonicalKey,
      topPrediction: topPrediction,
      alternativePredictions: alternativePredictions,
      resolvedCategoryId: clearResolvedCategoryId
          ? null
          : (resolvedCategoryId ?? this.resolvedCategoryId),
      resolvedCategoryName: resolvedCategoryName ?? this.resolvedCategoryName,
      suggestedCategoryName:
          suggestedCategoryName ?? this.suggestedCategoryName,
      sourceWalletId: sourceWalletId ?? this.sourceWalletId,
      destinationWalletId: clearDestinationWalletId
          ? null
          : (destinationWalletId ?? this.destinationWalletId),
      occurredAt: occurredAt ?? this.occurredAt,
      hasExplicitDate: occurredAt != null ? true : hasExplicitDate,
      confidence: confidence,
      ambiguityFlags: ambiguityFlags ?? this.ambiguityFlags,
      requiresConfirmation: requiresConfirmation ?? this.requiresConfirmation,
      isDuplicateCandidate: isDuplicateCandidate,
      duplicateOfTransactionId: duplicateOfTransactionId,
      transactionFingerprint: transactionFingerprint,
      appliedPersonalizationRuleId: appliedPersonalizationRuleId,
    );
  }

  @override
  List<Object?> get props => [
    draftId,
    userId,
    source,
    transactionType,
    amountMinor,
    currencyCode,
    description,
    merchant,
    merchantCanonicalKey,
    topPrediction,
    resolvedCategoryId,
    resolvedCategoryName,
    sourceWalletId,
    destinationWalletId,
    occurredAt,
    confidence,
    ambiguityFlags,
    requiresConfirmation,
    isDuplicateCandidate,
    transactionFingerprint,
    appliedPersonalizationRuleId,
  ];
}

class FinancialAnalysisResult extends Equatable {
  final FinancialAnalysisRequest request;
  final List<TransactionCandidate> candidates;
  final String? nonTransactionReason;
  final bool requiresConfirmation;
  final FinancialModelMetadata modelMetadata;
  final int totalElapsedMicros;

  const FinancialAnalysisResult({
    required this.request,
    required this.candidates,
    this.nonTransactionReason,
    required this.requiresConfirmation,
    required this.modelMetadata,
    required this.totalElapsedMicros,
  });

  bool get hasActionableCandidates => candidates.isNotEmpty;

  @override
  List<Object?> get props => [
    request,
    candidates,
    nonTransactionReason,
    requiresConfirmation,
    modelMetadata,
    totalElapsedMicros,
  ];
}

/// User-scoped, context-aware Personalization Rule (Phase 10).
class PersonalizationRule extends Equatable {
  final String id;
  final String userId;
  final String merchantCanonicalKey;
  final String merchantDisplay;
  final String selectedCategoryId;
  final String selectedCategoryName;
  final String semanticKey;

  /// Optional context condition: `'debit'`, `'credit'`, or `'any'`.
  final String directionCondition;

  /// Optional source context: `'any'`, `'manualText'`, `'androidBankNotification'`, etc.
  final String sourceContext;
  final int? minAmountMinor;
  final int? maxAmountMinor;
  final int confirmationCount;
  final DateTime lastCorrectedAt;
  final int priority;
  final double ruleConfidence;
  final String modelVersion;
  final bool isEnabled;

  const PersonalizationRule({
    required this.id,
    required this.userId,
    required this.merchantCanonicalKey,
    required this.merchantDisplay,
    required this.selectedCategoryId,
    required this.selectedCategoryName,
    required this.semanticKey,
    this.directionCondition = 'any',
    this.sourceContext = 'any',
    this.minAmountMinor,
    this.maxAmountMinor,
    required this.confirmationCount,
    required this.lastCorrectedAt,
    this.priority = 10,
    required this.ruleConfidence,
    required this.modelVersion,
    this.isEnabled = true,
  });

  bool matchesContext({
    required String canonicalKey,
    required String direction,
    required FinancialInputSource source,
    required int? amountMinor,
  }) {
    if (!isEnabled) return false;
    final normIncoming = canonicalKey
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), '_');
    final normRule = merchantCanonicalKey
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), '_');
    if (normRule.isEmpty || normIncoming.isEmpty) return false;
    if (normIncoming != normRule && !normIncoming.contains(normRule)) {
      return false;
    }
    if (directionCondition != 'any' && directionCondition != direction) {
      return false;
    }
    if (sourceContext != 'any' && sourceContext != source.name) {
      return false;
    }
    if (minAmountMinor != null &&
        amountMinor != null &&
        amountMinor < minAmountMinor!) {
      return false;
    }
    if (maxAmountMinor != null &&
        amountMinor != null &&
        amountMinor > maxAmountMinor!) {
      return false;
    }
    return true;
  }

  @override
  List<Object?> get props => [
    id,
    userId,
    merchantCanonicalKey,
    merchantDisplay,
    selectedCategoryId,
    selectedCategoryName,
    semanticKey,
    directionCondition,
    sourceContext,
    minAmountMinor,
    maxAmountMinor,
    confirmationCount,
    lastCorrectedAt,
    priority,
    ruleConfidence,
    modelVersion,
    isEnabled,
  ];
}

class UserAiClassificationPreferences extends Equatable {
  final String userId;
  final bool aiClassificationEnabled;
  final bool personalizationEnabled;
  final bool autoClassifyBankNotifications;
  final bool requireConfirmationBeforeSave;

  const UserAiClassificationPreferences({
    required this.userId,
    this.aiClassificationEnabled = true,
    this.personalizationEnabled = true,
    this.autoClassifyBankNotifications = true,
    this.requireConfirmationBeforeSave = true,
  });

  UserAiClassificationPreferences copyWith({
    bool? aiClassificationEnabled,
    bool? personalizationEnabled,
    bool? autoClassifyBankNotifications,
    bool? requireConfirmationBeforeSave,
  }) {
    return UserAiClassificationPreferences(
      userId: userId,
      aiClassificationEnabled:
          aiClassificationEnabled ?? this.aiClassificationEnabled,
      personalizationEnabled:
          personalizationEnabled ?? this.personalizationEnabled,
      autoClassifyBankNotifications:
          autoClassifyBankNotifications ?? this.autoClassifyBankNotifications,
      requireConfirmationBeforeSave:
          requireConfirmationBeforeSave ?? this.requireConfirmationBeforeSave,
    );
  }

  @override
  List<Object?> get props => [
    userId,
    aiClassificationEnabled,
    personalizationEnabled,
    autoClassifyBankNotifications,
    requireConfirmationBeforeSave,
  ];
}
