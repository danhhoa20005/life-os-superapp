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
      return const Err(
        ValidationFailure(message: 'Hạn mức ngân sách phải lớn hơn 0 ₫.'),
      );
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
      return const Err(
        ValidationFailure(message: 'Tên quỹ phải có ít nhất 2 ký tự.'),
      );
    }
    if (params.scope == FundScope.family &&
        (params.familyId == null || params.familyId!.isEmpty)) {
      return const Err(
        ValidationFailure(message: 'Quỹ chung bắt buộc chọn hộ gia đình.'),
      );
    }
    return _repository.createFund(
      userId: params.userId,
      familyId: params.familyId,
      scope: params.scope,
      name: params.name.trim(),
      targetAmountMinor: params.targetAmountMinor < 0
          ? 0
          : params.targetAmountMinor,
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
  final String? sourceWalletId;
  final String? operationId;

  const ContributeFundParams({
    required this.userId,
    required this.userName,
    required this.scope,
    this.familyId,
    required this.fundId,
    required this.amountMinor,
    this.note,
    this.sourceWalletId,
    this.operationId,
  });
}

class ContributeToFundUseCase implements UseCase<void, ContributeFundParams> {
  final BudgetRepository _repository;
  const ContributeToFundUseCase(this._repository);

  @override
  Future<Result<void>> call(ContributeFundParams params) async {
    if (params.amountMinor <= 0) {
      return const Err(
        ValidationFailure(message: 'Số tiền đóng góp quỹ phải lớn hơn 0 ₫.'),
      );
    }
    return _repository.contributeToFund(
      userId: params.userId,
      userName: params.userName,
      scope: params.scope,
      familyId: params.familyId,
      fundId: params.fundId,
      amountMinor: params.amountMinor,
      note: params.note?.trim(),
      sourceWalletId: params.sourceWalletId?.trim(),
      operationId: params.operationId?.trim(),
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
  final bool saveAsDraft;
  final String? operationId;

  const RequestFundExpenseParams({
    required this.userId,
    required this.userName,
    required this.scope,
    this.familyId,
    required this.fundId,
    required this.title,
    required this.amountMinor,
    required this.canAutoApprove,
    this.saveAsDraft = false,
    this.operationId,
  });
}

class RequestFundExpenseUseCase
    implements UseCase<void, RequestFundExpenseParams> {
  final BudgetRepository _repository;
  const RequestFundExpenseUseCase(this._repository);

  @override
  Future<Result<void>> call(RequestFundExpenseParams params) async {
    if (params.title.trim().length < 2) {
      return const Err(
        ValidationFailure(message: 'Mục đích chi quỹ phải có ít nhất 2 ký tự.'),
      );
    }
    if (params.amountMinor <= 0) {
      return const Err(
        ValidationFailure(message: 'Số tiền đề xuất chi phải lớn hơn 0 ₫.'),
      );
    }
    return _repository.requestFundExpense(
      userId: params.userId,
      userName: params.userName,
      scope: params.scope,
      familyId: params.familyId,
      fundId: params.fundId,
      title: params.title.trim(),
      amountMinor: params.amountMinor,
      // Strict AUD-006 guard: NEVER allow auto-approval on family shared funds!
      canAutoApprove:
          params.scope == FundScope.personal && params.canAutoApprove,
      saveAsDraft: params.saveAsDraft,
      operationId: params.operationId?.trim(),
    );
  }
}

final class SubmitFundExpenseDraftParams {
  final FundScope scope;
  final String userId;
  final String? familyId;
  final String fundId;
  final String expenseId;
  final String? updatedTitle;
  final int? updatedAmountMinor;

  const SubmitFundExpenseDraftParams({
    required this.scope,
    required this.userId,
    this.familyId,
    required this.fundId,
    required this.expenseId,
    this.updatedTitle,
    this.updatedAmountMinor,
  });
}

class SubmitFundExpenseDraftUseCase
    implements UseCase<void, SubmitFundExpenseDraftParams> {
  final BudgetRepository _repository;
  const SubmitFundExpenseDraftUseCase(this._repository);

  @override
  Future<Result<void>> call(SubmitFundExpenseDraftParams params) {
    if (params.updatedTitle != null && params.updatedTitle!.trim().length < 2) {
      return Future.value(
        const Err(
          ValidationFailure(
            message: 'Mục đích chi quỹ phải có ít nhất 2 ký tự.',
          ),
        ),
      );
    }
    if (params.updatedAmountMinor != null && params.updatedAmountMinor! <= 0) {
      return Future.value(
        const Err(
          ValidationFailure(message: 'Số tiền đề xuất chi phải lớn hơn 0 ₫.'),
        ),
      );
    }
    return _repository.submitFundExpenseDraft(
      scope: params.scope,
      userId: params.userId,
      familyId: params.familyId,
      fundId: params.fundId,
      expenseId: params.expenseId,
      updatedTitle: params.updatedTitle?.trim(),
      updatedAmountMinor: params.updatedAmountMinor,
    );
  }
}

final class DecideFundExpenseParams {
  final String familyId;
  final String fundId;
  final String expenseId;
  final bool approve;
  final String? actorUserId;
  final String? operationId;

  const DecideFundExpenseParams({
    required this.familyId,
    required this.fundId,
    required this.expenseId,
    required this.approve,
    this.actorUserId,
    this.operationId,
  });
}

class DecideFundExpenseUseCase
    implements UseCase<void, DecideFundExpenseParams> {
  final BudgetRepository _repository;
  const DecideFundExpenseUseCase(this._repository);

  @override
  Future<Result<void>> call(DecideFundExpenseParams params) {
    return _repository.decideFundExpense(
      familyId: params.familyId,
      fundId: params.fundId,
      expenseId: params.expenseId,
      approve: params.approve,
      actorUserId: params.actorUserId?.trim(),
      operationId: params.operationId?.trim(),
    );
  }
}

final class ExecuteFundExpenseParams {
  final String familyId;
  final String fundId;
  final String expenseId;
  final String actorUserId;
  final String? operationId;

  const ExecuteFundExpenseParams({
    required this.familyId,
    required this.fundId,
    required this.expenseId,
    required this.actorUserId,
    this.operationId,
  });
}

class ExecuteFundExpenseUseCase
    implements UseCase<void, ExecuteFundExpenseParams> {
  final BudgetRepository _repository;
  const ExecuteFundExpenseUseCase(this._repository);

  @override
  Future<Result<void>> call(ExecuteFundExpenseParams params) {
    if (params.actorUserId.trim().isEmpty) {
      return Future.value(
        const Err(
          PermissionDeniedFailure(
            message: 'Thiếu thông tin người giải ngân khoản chi.',
          ),
        ),
      );
    }
    return _repository.executeFundExpense(
      familyId: params.familyId,
      fundId: params.fundId,
      expenseId: params.expenseId,
      actorUserId: params.actorUserId.trim(),
      operationId: params.operationId?.trim(),
    );
  }
}

final class ReconcileFundExpenseParams {
  final String familyId;
  final String fundId;
  final String expenseId;
  final String actorUserId;
  final String reconciledTxId;
  final String? operationId;

  const ReconcileFundExpenseParams({
    required this.familyId,
    required this.fundId,
    required this.expenseId,
    required this.actorUserId,
    required this.reconciledTxId,
    this.operationId,
  });
}

class ReconcileFundExpenseUseCase
    implements UseCase<void, ReconcileFundExpenseParams> {
  final BudgetRepository _repository;
  const ReconcileFundExpenseUseCase(this._repository);

  @override
  Future<Result<void>> call(ReconcileFundExpenseParams params) {
    if (params.reconciledTxId.trim().isEmpty) {
      return Future.value(
        const Err(
          ValidationFailure(message: 'Vui lòng nhập mã giao dịch đối soát.'),
        ),
      );
    }
    return _repository.reconcileFundExpense(
      familyId: params.familyId,
      fundId: params.fundId,
      expenseId: params.expenseId,
      actorUserId: params.actorUserId.trim(),
      reconciledTxId: params.reconciledTxId.trim(),
      operationId: params.operationId?.trim(),
    );
  }
}

final class DisputeFundExpenseParams {
  final String familyId;
  final String fundId;
  final String expenseId;
  final String actorUserId;
  final String reason;
  final String? operationId;

  const DisputeFundExpenseParams({
    required this.familyId,
    required this.fundId,
    required this.expenseId,
    required this.actorUserId,
    required this.reason,
    this.operationId,
  });
}

class DisputeFundExpenseUseCase
    implements UseCase<void, DisputeFundExpenseParams> {
  final BudgetRepository _repository;
  const DisputeFundExpenseUseCase(this._repository);

  @override
  Future<Result<void>> call(DisputeFundExpenseParams params) {
    if (params.reason.trim().length < 2) {
      return Future.value(
        const Err(
          ValidationFailure(
            message: 'Vui lòng nhập lý do khiếu nại (>= 2 ký tự).',
          ),
        ),
      );
    }
    return _repository.disputeFundExpense(
      familyId: params.familyId,
      fundId: params.fundId,
      expenseId: params.expenseId,
      actorUserId: params.actorUserId.trim(),
      reason: params.reason.trim(),
      operationId: params.operationId?.trim(),
    );
  }
}

final class ReverseFundExpenseParams {
  final String familyId;
  final String fundId;
  final String expenseId;
  final String actorUserId;
  final String? reason;
  final String? operationId;

  const ReverseFundExpenseParams({
    required this.familyId,
    required this.fundId,
    required this.expenseId,
    required this.actorUserId,
    this.reason,
    this.operationId,
  });
}

class ReverseFundExpenseUseCase
    implements UseCase<void, ReverseFundExpenseParams> {
  final BudgetRepository _repository;
  const ReverseFundExpenseUseCase(this._repository);

  @override
  Future<Result<void>> call(ReverseFundExpenseParams params) {
    return _repository.reverseFundExpense(
      familyId: params.familyId,
      fundId: params.fundId,
      expenseId: params.expenseId,
      actorUserId: params.actorUserId.trim(),
      reason: params.reason?.trim(),
      operationId: params.operationId?.trim(),
    );
  }
}

final class CancelFundExpenseParams {
  final FundScope scope;
  final String userId;
  final String? familyId;
  final String fundId;
  final String expenseId;
  final String actorUserId;
  final String? operationId;

  const CancelFundExpenseParams({
    required this.scope,
    required this.userId,
    this.familyId,
    required this.fundId,
    required this.expenseId,
    required this.actorUserId,
    this.operationId,
  });
}

class CancelFundExpenseUseCase
    implements UseCase<void, CancelFundExpenseParams> {
  final BudgetRepository _repository;
  const CancelFundExpenseUseCase(this._repository);

  @override
  Future<Result<void>> call(CancelFundExpenseParams params) {
    return _repository.cancelFundExpense(
      scope: params.scope,
      userId: params.userId,
      familyId: params.familyId,
      fundId: params.fundId,
      expenseId: params.expenseId,
      actorUserId: params.actorUserId.trim(),
      operationId: params.operationId?.trim(),
    );
  }
}
