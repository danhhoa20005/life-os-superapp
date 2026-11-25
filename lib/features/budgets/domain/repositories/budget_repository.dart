import '../../../../core/error/app_exception.dart';
import '../entities/budget_entities.dart';

abstract interface class BudgetRepository {
  Stream<Result<List<BudgetEntity>>> watchBudgets({
    required String userId,
    required String monthKey,
  });

  Stream<Result<List<FundEntity>>> watchFunds({
    required String userId,
    String? familyId,
  });

  Future<Result<void>> upsertBudget({
    required String userId,
    required String categoryId,
    required String categoryName,
    required String monthKey,
    required int limitMinor,
    int alertThresholdPct = 80,
  });

  Future<Result<void>> createFund({
    required String userId,
    String? familyId,
    required FundScope scope,
    required String name,
    required int targetAmountMinor,
  });

  Future<Result<void>> contributeToFund({
    required String userId,
    required String userName,
    required FundScope scope,
    String? familyId,
    required String fundId,
    required int amountMinor,
    String? note,
    String? sourceWalletId,
    String? operationId,
  });

  Future<Result<void>> requestFundExpense({
    required String userId,
    required String userName,
    required FundScope scope,
    String? familyId,
    required String fundId,
    required String title,
    required int amountMinor,
    required bool canAutoApprove,
    bool saveAsDraft = false,
    String? operationId,
  });

  Future<Result<void>> submitFundExpenseDraft({
    required FundScope scope,
    required String userId,
    String? familyId,
    required String fundId,
    required String expenseId,
    String? updatedTitle,
    int? updatedAmountMinor,
  });

  Future<Result<void>> decideFundExpense({
    required String familyId,
    required String fundId,
    required String expenseId,
    required bool approve,
    String? actorUserId,
    String? operationId,
  });

  Future<Result<void>> executeFundExpense({
    required String familyId,
    required String fundId,
    required String expenseId,
    required String actorUserId,
    String? operationId,
  });

  Future<Result<void>> reconcileFundExpense({
    required String familyId,
    required String fundId,
    required String expenseId,
    required String actorUserId,
    required String reconciledTxId,
    String? operationId,
  });

  Future<Result<void>> disputeFundExpense({
    required String familyId,
    required String fundId,
    required String expenseId,
    required String actorUserId,
    required String reason,
    String? operationId,
  });

  Future<Result<void>> reverseFundExpense({
    required String familyId,
    required String fundId,
    required String expenseId,
    required String actorUserId,
    String? reason,
    String? operationId,
  });

  Future<Result<void>> cancelFundExpense({
    required FundScope scope,
    required String userId,
    String? familyId,
    required String fundId,
    required String expenseId,
    required String actorUserId,
    String? operationId,
  });
}
