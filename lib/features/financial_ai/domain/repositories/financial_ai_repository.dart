import '../../../../core/error/app_exception.dart';
import '../../../transactions/domain/entities/transaction_entities.dart';
import '../entities/financial_ai_entities.dart';

abstract interface class FinancialAiRepository {
  FinancialModelMetadata get currentModelMetadata;

  Future<Result<FinancialModelMetadata>> initializeEngine();

  Future<Result<FinancialAnalysisResult>> analyzeText({
    required String userId,
    required String text,
    FinancialInputSource source = FinancialInputSource.manualText,
    String? preferredWalletId,
    String? familyId,
    DateTime? referenceTime,
    String? externalReferenceId,
    List<WalletEntity>? knownWallets,
    List<CategoryEntity>? knownCategories,
  });

  Future<Result<List<ExtractedFinancialEntity>>> extractEntities({
    required String text,
    DateTime? referenceTime,
  });

  Future<Result<ClassificationResult>> classifyNormalizedSegment(
    String normalizedText,
  );

  Future<Result<ResolvedCategoryMatch>> resolveUserCategory({
    required String userId,
    required String semanticKey,
    required String direction,
    String? merchantCanonicalKey,
    FinancialInputSource source = FinancialInputSource.manualText,
    int? amountMinor,
    List<CategoryEntity>? knownCategories,
  });

  Future<Result<TransactionEntity>> confirmCandidateDraft({
    required String userId,
    required TransactionCandidate candidate,
    String? operationId,
  });

  Future<Result<PersonalizationRule>> saveCategoryCorrection({
    required String userId,
    required String merchantDisplay,
    required String merchantCanonicalKey,
    required String selectedCategoryId,
    required String selectedCategoryName,
    required String semanticKey,
    String directionCondition = 'any',
    String sourceContext = 'any',
  });

  Future<Result<({bool isDuplicate, String? matchedTransactionId})>>
  detectDuplicate({
    required String userId,
    required String fingerprint,
    required String direction,
    required int amountMinor,
    required DateTime occurredAt,
    String? referenceCode,
  });

  Stream<Result<List<TransactionCandidate>>> watchPendingDrafts(String userId);

  Future<Result<void>> savePendingDraft(TransactionCandidate draft);

  Future<Result<void>> deletePendingDraft({
    required String userId,
    required String draftId,
  });

  Stream<Result<List<PersonalizationRule>>> watchPersonalizationRules(
    String userId,
  );

  Future<Result<void>> deletePersonalizationRule({
    required String userId,
    required String ruleId,
  });

  Future<Result<void>> clearAllPersonalizationData(String userId);

  Stream<Result<UserAiClassificationPreferences>> watchPreferences(
    String userId,
  );

  Future<Result<void>> updatePreferences(
    UserAiClassificationPreferences preferences,
  );
}
