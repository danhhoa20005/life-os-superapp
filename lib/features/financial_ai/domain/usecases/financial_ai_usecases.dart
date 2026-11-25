import '../../../../core/error/app_exception.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/usecases/usecase.dart';
import '../../../transactions/domain/entities/transaction_entities.dart';
import '../entities/financial_ai_entities.dart';
import '../repositories/financial_ai_repository.dart';

final class AnalyzeFinancialTextParams {
  final String userId;
  final String text;
  final FinancialInputSource source;
  final String? preferredWalletId;
  final String? familyId;
  final DateTime? referenceTime;
  final String? externalReferenceId;
  final List<WalletEntity>? knownWallets;
  final List<CategoryEntity>? knownCategories;

  const AnalyzeFinancialTextParams({
    required this.userId,
    required this.text,
    this.source = FinancialInputSource.manualText,
    this.preferredWalletId,
    this.familyId,
    this.referenceTime,
    this.externalReferenceId,
    this.knownWallets,
    this.knownCategories,
  });
}

class AnalyzeFinancialTextUseCase
    implements UseCase<FinancialAnalysisResult, AnalyzeFinancialTextParams> {
  final FinancialAiRepository _repository;
  const AnalyzeFinancialTextUseCase(this._repository);

  @override
  Future<Result<FinancialAnalysisResult>> call(
    AnalyzeFinancialTextParams params,
  ) {
    if (params.text.trim().isEmpty) {
      return Future.value(
        const Err(
          ValidationFailure(
            message: 'Vui lòng nhập hoặc nói nội dung giao dịch cần phân tích.',
          ),
        ),
      );
    }
    return _repository.analyzeText(
      userId: params.userId,
      text: params.text,
      source: params.source,
      preferredWalletId: params.preferredWalletId,
      familyId: params.familyId,
      referenceTime: params.referenceTime,
      externalReferenceId: params.externalReferenceId,
      knownWallets: params.knownWallets,
      knownCategories: params.knownCategories,
    );
  }
}

final class ExtractTransactionsParams {
  final String text;
  final DateTime? referenceTime;
  const ExtractTransactionsParams({required this.text, this.referenceTime});
}

class ExtractTransactionsUseCase
    implements
        UseCase<List<ExtractedFinancialEntity>, ExtractTransactionsParams> {
  final FinancialAiRepository _repository;
  const ExtractTransactionsUseCase(this._repository);

  @override
  Future<Result<List<ExtractedFinancialEntity>>> call(
    ExtractTransactionsParams params,
  ) {
    return _repository.extractEntities(
      text: params.text,
      referenceTime: params.referenceTime,
    );
  }
}

class ClassifyTransactionUseCase
    implements UseCase<ClassificationResult, String> {
  final FinancialAiRepository _repository;
  const ClassifyTransactionUseCase(this._repository);

  @override
  Future<Result<ClassificationResult>> call(String normalizedText) {
    return _repository.classifyNormalizedSegment(normalizedText);
  }
}

final class ResolveUserCategoryParams {
  final String userId;
  final String semanticKey;
  final String direction;
  final String? merchantCanonicalKey;
  final FinancialInputSource source;
  final int? amountMinor;
  final List<CategoryEntity>? knownCategories;

  const ResolveUserCategoryParams({
    required this.userId,
    required this.semanticKey,
    required this.direction,
    this.merchantCanonicalKey,
    this.source = FinancialInputSource.manualText,
    this.amountMinor,
    this.knownCategories,
  });
}

class ResolveUserCategoryUseCase
    implements UseCase<ResolvedCategoryMatch, ResolveUserCategoryParams> {
  final FinancialAiRepository _repository;
  const ResolveUserCategoryUseCase(this._repository);

  @override
  Future<Result<ResolvedCategoryMatch>> call(ResolveUserCategoryParams params) {
    return _repository.resolveUserCategory(
      userId: params.userId,
      semanticKey: params.semanticKey,
      direction: params.direction,
      merchantCanonicalKey: params.merchantCanonicalKey,
      source: params.source,
      amountMinor: params.amountMinor,
      knownCategories: params.knownCategories,
    );
  }
}

final class ConfirmTransactionDraftParams {
  final String userId;
  final TransactionCandidate candidate;
  final String? operationId;

  const ConfirmTransactionDraftParams({
    required this.userId,
    required this.candidate,
    this.operationId,
  });
}

/// Enforces all Phase 17 Financial Safety & Data Integrity rules before delegating to Ledger!
class ConfirmTransactionDraftUseCase
    implements UseCase<TransactionEntity, ConfirmTransactionDraftParams> {
  final FinancialAiRepository _repository;
  const ConfirmTransactionDraftUseCase(this._repository);

  @override
  Future<Result<TransactionEntity>> call(
    ConfirmTransactionDraftParams params,
  ) async {
    final c = params.candidate;
    if (c.userId != params.userId) {
      return const Err(
        PermissionDeniedFailure(
          message: 'Không có quyền xác nhận bản nháp của người dùng khác.',
        ),
      );
    }
    if (c.amountMinor <= 0) {
      return const Err(
        ValidationFailure(
          message: 'Số tiền giao dịch phải lớn hơn 0 ₫ (không ghi giao dịch 0 hoặc âm).',
        ),
      );
    }
    final ledgerKind = c.transactionType.toLedgerKind;
    if (ledgerKind == null) {
      return const Err(
        ValidationFailure(
          message:
              'Loại giao dịch chưa xác định hoặc không phải giao dịch tài chính. Vui lòng chọn loại hợp lệ.',
        ),
      );
    }
    if (c.sourceWalletId == null || c.sourceWalletId!.trim().isEmpty) {
      return const Err(
        ValidationFailure(
          message: 'Vui lòng chọn ví nguồn hợp lệ trước khi ghi sổ.',
        ),
      );
    }
    if (ledgerKind == TransactionKind.transfer) {
      if (c.destinationWalletId == null ||
          c.destinationWalletId!.trim().isEmpty ||
          c.destinationWalletId == c.sourceWalletId) {
        return const Err(
          ValidationFailure(
            message:
                'Giao dịch chuyển nội bộ / rút ATM cần chọn ví đích khác với ví nguồn.',
          ),
        );
      }
    }
    return _repository.confirmCandidateDraft(
      userId: params.userId,
      candidate: c,
      operationId: params.operationId,
    );
  }
}

final class SaveCategoryCorrectionParams {
  final String userId;
  final String merchantDisplay;
  final String merchantCanonicalKey;
  final String selectedCategoryId;
  final String selectedCategoryName;
  final String semanticKey;
  final String directionCondition;
  final String sourceContext;
  final String ruleKind;
  final String? preferredWalletId;
  final String? preferredWalletName;
  final String? participantUserId;
  final String? participantDisplayName;
  final String? ruleIdOverride;

  const SaveCategoryCorrectionParams({
    required this.userId,
    required this.merchantDisplay,
    required this.merchantCanonicalKey,
    required this.selectedCategoryId,
    required this.selectedCategoryName,
    required this.semanticKey,
    this.directionCondition = 'any',
    this.sourceContext = 'any',
    this.ruleKind = 'category',
    this.preferredWalletId,
    this.preferredWalletName,
    this.participantUserId,
    this.participantDisplayName,
    this.ruleIdOverride,
  });
}

class SaveCategoryCorrectionUseCase
    implements UseCase<PersonalizationRule, SaveCategoryCorrectionParams> {
  final FinancialAiRepository _repository;
  const SaveCategoryCorrectionUseCase(this._repository);

  @override
  Future<Result<PersonalizationRule>> call(
    SaveCategoryCorrectionParams params,
  ) {
    if (params.ruleKind == 'category' &&
        params.selectedCategoryId.trim().isEmpty &&
        (params.preferredWalletId ?? '').trim().isEmpty) {
      return Future.value(
        const Err(
          ValidationFailure(message: 'Danh mục được chọn không hợp lệ.'),
        ),
      );
    }
    return _repository.saveCategoryCorrection(
      userId: params.userId,
      merchantDisplay: params.merchantDisplay,
      merchantCanonicalKey: params.merchantCanonicalKey,
      selectedCategoryId: params.selectedCategoryId,
      selectedCategoryName: params.selectedCategoryName,
      semanticKey: params.semanticKey,
      directionCondition: params.directionCondition,
      sourceContext: params.sourceContext,
      ruleKind: params.ruleKind,
      preferredWalletId: params.preferredWalletId,
      preferredWalletName: params.preferredWalletName,
      participantUserId: params.participantUserId,
      participantDisplayName: params.participantDisplayName,
      ruleIdOverride: params.ruleIdOverride,
    );
  }
}

final class DetectDuplicateTransactionParams {
  final String userId;
  final String fingerprint;
  final String direction;
  final int amountMinor;
  final DateTime occurredAt;
  final String? referenceCode;

  const DetectDuplicateTransactionParams({
    required this.userId,
    required this.fingerprint,
    required this.direction,
    required this.amountMinor,
    required this.occurredAt,
    this.referenceCode,
  });
}

class DetectDuplicateTransactionUseCase
    implements
        UseCase<
          ({bool isDuplicate, String? matchedTransactionId}),
          DetectDuplicateTransactionParams
        > {
  final FinancialAiRepository _repository;
  const DetectDuplicateTransactionUseCase(this._repository);

  @override
  Future<Result<({bool isDuplicate, String? matchedTransactionId})>> call(
    DetectDuplicateTransactionParams params,
  ) {
    return _repository.detectDuplicate(
      userId: params.userId,
      fingerprint: params.fingerprint,
      direction: params.direction,
      amountMinor: params.amountMinor,
      occurredAt: params.occurredAt,
      referenceCode: params.referenceCode,
    );
  }
}

class GetPendingTransactionsUseCase {
  final FinancialAiRepository _repository;
  const GetPendingTransactionsUseCase(this._repository);

  Stream<Result<List<TransactionCandidate>>> call(String userId) {
    return _repository.watchPendingDrafts(userId);
  }
}
