import '../../../../core/error/app_exception.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/budget_entities.dart';
import '../repositories/budget_repository.dart';

final class UpsertBudgetParams {
  final String userId;
  final String categoryId;
  final String categoryName;
  final String monthKey;
  final int limitMinor;
  final int alertThresholdPct;

  const UpsertBudgetParams({
    required this.userId,
    required this.categoryId,
    required this.categoryName,
    required this.monthKey,
    required this.limitMinor,
    this.alertThresholdPct = 80,
  });
}

class UpsertBudgetUseCase implements UseCase<void, UpsertBudgetParams> {
  final BudgetRepository _repository;
  const UpsertBudgetUseCase(this._repository);

  @override
  Future<Result<void>> call(UpsertBudgetParams params) async {
    if (params.limitMinor <= 0) {
      return const Err(ValidationFailure(message: 'Hạn mức ngân sách phải lớn hơn 0 ₫.'));
    }
    return _repository.upsertBudget(
      userId: params.userId,
      categoryId: params.categoryId,
      categoryName: params.categoryName,
      monthKey: params.monthKey,
      limitMinor: params.limitMinor,
      alertThresholdPct: params.alertThresholdPct,
    );
  }
}

final class CreateFundParams {
  final String userId;
  final String? familyId;
  final FundScope scope;
  final String name;
  final int targetAmountMinor;

  const CreateFundParams({
    required this.userId,
    this.familyId,
    required this.scope,
    required this.name,
    required this.targetAmountMinor,
  });
}

class CreateFundUseCase implements UseCase<void, CreateFundParams> {
  final BudgetRepository _repository;
  const CreateFundUseCase(this._repository);

  @override
  Future<Result<void>> call(CreateFundParams params) async {
    if (params.name.trim().length < 2) {
      return const Err(ValidationFailure(message: 'Tên quỹ phải có ít nhất 2 ký tự.'));
    }
    if (params.scope == FundScope.family && (params.familyId == null || params.familyId!.isEmpty)) {
      return const Err(ValidationFailure(message: 'Quỹ chung bắt buộc chọn hộ gia đình.'));
    }
    return _repository.createFund(
      userId: params.userId,
      familyId: params.familyId,
      scope: params.scope,
      name: params.name.trim(),
      targetAmountMinor: params.targetAmountMinor < 0 ? 0 : params.targetAmountMinor,
    );
  }
}

final class ContributeFundParams {
  final String userId;
  final String userName;
  final FundScope scope;
  final String? familyId;
  final String fundId;
  final int amountMinor;
  final String? note;

  const ContributeFundParams({
    required this.userId,
    required this.userName,
    required this.scope,
    this.familyId,
    required this.fundId,
    required this.amountMinor,
    this.note,
  });
}

class ContributeToFundUseCase implements UseCase<void, ContributeFundParams> {
  final BudgetRepository _repository;
  const ContributeToFundUseCase(this._repository);

  @override
  Future<Result<void>> call(ContributeFundParams params) async {
    if (params.amountMinor <= 0) {
      return const Err(ValidationFailure(message: 'Số tiền đóng góp quỹ phải lớn hơn 0 ₫.'));
    }
    return _repository.contributeToFund(
      userId: params.userId,
      userName: params.userName,
      scope: params.scope,
      familyId: params.familyId,
      fundId: params.fundId,
      amountMinor: params.amountMinor,
      note: params.note?.trim(),
    );
  }
}

final class RequestFundExpenseParams {
  final String userId;
  final String userName;
  final FundScope scope;
  final String? familyId;
  final String fundId;
  final String title;
  final int amountMinor;
  final bool canAutoApprove;

  const RequestFundExpenseParams({
    required this.userId,
    required this.userName,
    required this.scope,
    this.familyId,
    required this.fundId,
    required this.title,
    required this.amountMinor,
    required this.canAutoApprove,
  });
}

class RequestFundExpenseUseCase implements UseCase<void, RequestFundExpenseParams> {
  final BudgetRepository _repository;
  const RequestFundExpenseUseCase(this._repository);

  @override
  Future<Result<void>> call(RequestFundExpenseParams params) async {
    if (params.title.trim().length < 2) {
      return const Err(ValidationFailure(message: 'Mục đích chi quỹ phải có ít nhất 2 ký tự.'));
    }
    if (params.amountMinor <= 0) {
      return const Err(ValidationFailure(message: 'Số tiền đề xuất chi phải lớn hơn 0 ₫.'));
    }
    return _repository.requestFundExpense(
      userId: params.userId,
      userName: params.userName,
      scope: params.scope,
      familyId: params.familyId,
      fundId: params.fundId,
      title: params.title.trim(),
      amountMinor: params.amountMinor,
      canAutoApprove: params.canAutoApprove,
    );
  }
}

final class DecideFundExpenseParams {
  final String familyId;
  final String fundId;
  final String expenseId;
  final bool approve;

  const DecideFundExpenseParams({
    required this.familyId,
    required this.fundId,
    required this.expenseId,
    required this.approve,
  });
}

class DecideFundExpenseUseCase implements UseCase<void, DecideFundExpenseParams> {
  final BudgetRepository _repository;
  const DecideFundExpenseUseCase(this._repository);

  @override
  Future<Result<void>> call(DecideFundExpenseParams params) {
    return _repository.decideFundExpense(
      familyId: params.familyId,
      fundId: params.fundId,
      expenseId: params.expenseId,
      approve: params.approve,
    );
  }
}
