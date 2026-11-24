import '../../domain/entities/financial_ai_entities.dart';

/// Phase 11 & Phase 17 — Multi-Dimensional Confidence & Decision Policy Engine.
/// Evaluates critical financial dimensions independently (NEVER a naive average!)
/// and enforces strict safety gates before allowing auto-selection or auto-posting.
abstract final class ConfidencePolicyEngine {
  static double sourceReliability(FinancialInputSource source) {
    return switch (source) {
      FinancialInputSource.bankFeed => 0.98,
      FinancialInputSource.androidBankNotification => 0.88,
      FinancialInputSource.manualText => 0.92,
      FinancialInputSource.clipboard => 0.85,
      FinancialInputSource.voiceTranscript => 0.78,
    };
  }

  static ClassificationConfidence evaluate({
    required ExtractedFinancialEntity extracted,
    required CategoryPrediction topPrediction,
    required FinancialInputSource source,
    required FinancialModelMetadata modelMeta,
    required bool hasValidSourceWallet,
    required bool hasValidDestinationWalletIfTransfer,
    required bool hasResolvedUserCategory,
    required bool isDuplicateCandidate,
    required List<AmbiguityFlag> allFlags,
  }) {
    final amountConf = extracted.amountConfidence.clamp(0.0, 1.0);
    final typeConf = extracted.typeConfidence.clamp(0.0, 1.0);
    final catConf = topPrediction.probability.clamp(0.0, 1.0);
    final merchConf = extracted.merchantConfidence.clamp(0.0, 1.0);
    final srcConf = sourceReliability(source);

    // Critical bottleneck: if amount or transaction type is missing/unknown, overall tier drops immediately!
    if (extracted.amountMinor == null ||
        extracted.amountMinor! <= 0 ||
        extracted.transactionType == FinancialTransactionType.unknown ||
        extracted.transactionType == FinancialTransactionType.nonTransaction) {
      return ClassificationConfidence(
        amountConfidence: amountConf,
        typeConfidence: typeConf,
        categoryConfidence: catConf,
        merchantConfidence: merchConf,
        sourceConfidence: srcConf,
        tier: ConfidenceTier.unknown,
        canAutoPostUnderPolicy: false,
      );
    }

    // Transfers don't rely on expense/income semantic category probability
    final effectiveCatConf =
        extracted.transactionType == FinancialTransactionType.internalTransfer ||
            extracted.transactionType ==
                FinancialTransactionType.investmentTransfer
        ? 0.92
        : catConf;

    final criticalMin = [
      amountConf,
      typeConf,
      effectiveCatConf,
    ].reduce((a, b) => a < b ? a : b);

    final hasBlockingAmbiguity =
        allFlags.contains(AmbiguityFlag.ambiguousDecimalOrThousands) ||
        allFlags.contains(AmbiguityFlag.multipleMatchingUserCategories) ||
        allFlags.contains(AmbiguityFlag.unmappedUserCategory) ||
        allFlags.contains(AmbiguityFlag.missingDestinationWalletForTransfer);

    final ConfidenceTier tier;
    if (criticalMin < modelMeta.lowConfidenceThreshold) {
      tier = ConfidenceTier.unknown;
    } else if (criticalMin < modelMeta.mediumConfidenceThreshold ||
        hasBlockingAmbiguity) {
      tier = ConfidenceTier.lowConfidence;
    } else if (criticalMin < modelMeta.highConfidenceThreshold) {
      tier = ConfidenceTier.mediumConfidence;
    } else {
      tier = ConfidenceTier.highConfidence;
    }

    // Strict Auto-Post Gate (Phase 11 & Phase 17):
    // NEVER auto-post on category confidence alone! Requires highConfidence + zero ambiguity
    // + verified wallet + verified category + non-duplicate + verified/notification source.
    final canAutoPost =
        tier == ConfidenceTier.highConfidence &&
        allFlags.isEmpty &&
        !isDuplicateCandidate &&
        hasValidSourceWallet &&
        hasValidDestinationWalletIfTransfer &&
        (hasResolvedUserCategory ||
            !extracted.transactionType.createsStandardPnlImpact);

    return ClassificationConfidence(
      amountConfidence: amountConf,
      typeConfidence: typeConf,
      categoryConfidence: effectiveCatConf,
      merchantConfidence: merchConf,
      sourceConfidence: srcConf,
      tier: tier,
      canAutoPostUnderPolicy: canAutoPost,
    );
  }
}
