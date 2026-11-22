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
  });

  Future<Result<void>> decideFundExpense({
    required String familyId,
    required String fundId,
    required String expenseId,
    required bool approve,
  });
}
