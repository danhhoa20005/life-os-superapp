import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/error/app_exception.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/utils/stream_combiner.dart';
import '../../domain/entities/budget_entities.dart';
import '../../domain/repositories/budget_repository.dart';
import '../../domain/usecases/budget_usecases.dart';

sealed class BudgetEvent extends Equatable {
  const BudgetEvent();

  @override
  List<Object?> get props => [];
}

final class BudgetsSubscriptionRequested extends BudgetEvent {
  final String userId;
  final String monthKey;
  final String? familyId;

  const BudgetsSubscriptionRequested({
    required this.userId,
    required this.monthKey,
    this.familyId,
  });

  @override
  List<Object?> get props => [userId, monthKey, familyId];
}

final class BudgetUpsertSubmitted extends BudgetEvent {
  final UpsertBudgetParams params;
  const BudgetUpsertSubmitted(this.params);

  @override
  List<Object?> get props => [params];
}

final class FundCreateSubmitted extends BudgetEvent {
  final CreateFundParams params;
  const FundCreateSubmitted(this.params);

  @override
  List<Object?> get props => [params];
}

final class FundContributionSubmitted extends BudgetEvent {
  final ContributeFundParams params;
  const FundContributionSubmitted(this.params);

  @override
  List<Object?> get props => [params];
}

final class FundExpenseRequested extends BudgetEvent {
  final RequestFundExpenseParams params;
  const FundExpenseRequested(this.params);

  @override
  List<Object?> get props => [params];
}

final class FundExpenseDraftSubmitted extends BudgetEvent {
  final SubmitFundExpenseDraftParams params;
  const FundExpenseDraftSubmitted(this.params);

  @override
  List<Object?> get props => [params];
}

final class FundExpenseDecisionSubmitted extends BudgetEvent {
  final DecideFundExpenseParams params;
  const FundExpenseDecisionSubmitted(this.params);

  @override
  List<Object?> get props => [params];
}

final class FundExpenseExecuted extends BudgetEvent {
  final ExecuteFundExpenseParams params;
  const FundExpenseExecuted(this.params);

  @override
  List<Object?> get props => [params];
}

final class FundExpenseReconciled extends BudgetEvent {
  final ReconcileFundExpenseParams params;
  const FundExpenseReconciled(this.params);

  @override
  List<Object?> get props => [params];
}

final class FundExpenseDisputed extends BudgetEvent {
  final DisputeFundExpenseParams params;
  const FundExpenseDisputed(this.params);

  @override
  List<Object?> get props => [params];
}

final class FundExpenseReversed extends BudgetEvent {
  final ReverseFundExpenseParams params;
  const FundExpenseReversed(this.params);

  @override
  List<Object?> get props => [params];
}

final class FundExpenseCancelled extends BudgetEvent {
  final CancelFundExpenseParams params;
  const FundExpenseCancelled(this.params);

  @override
  List<Object?> get props => [params];
}

final class BudgetState extends Equatable {
  final bool isLoading;
  final bool isSaving;
  final List<BudgetEntity> budgets;
  final List<FundEntity> funds;
  final Failure? failure;
  final String? actionMessage;
  final String? lastActionOperationId;

  const BudgetState({
    this.isLoading = false,
    this.isSaving = false,
    this.budgets = const [],
    this.funds = const [],
    this.failure,
    this.actionMessage,
    this.lastActionOperationId,
  });

  BudgetState copyWith({
    bool? isLoading,
    bool? isSaving,
    List<BudgetEntity>? budgets,
    List<FundEntity>? funds,
    Failure? failure,
    bool clearFailure = false,
    String? actionMessage,
    bool clearMessage = false,
    String? lastActionOperationId,
    bool clearOperationId = false,
  }) {
    return BudgetState(
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      budgets: budgets != null ? List.unmodifiable(budgets) : this.budgets,
      funds: funds != null ? List.unmodifiable(funds) : this.funds,
      failure: clearFailure ? null : (failure ?? this.failure),
      actionMessage: clearMessage
          ? null
          : (actionMessage ?? this.actionMessage),
      lastActionOperationId: clearOperationId
          ? null
          : (lastActionOperationId ?? this.lastActionOperationId),
    );
  }

  @override
  List<Object?> get props => [
    isLoading,
    isSaving,
    budgets,
    funds,
    failure,
    actionMessage,
    lastActionOperationId,
  ];
}

class BudgetBloc extends Bloc<BudgetEvent, BudgetState> {
  final BudgetRepository _repository;
  final UpsertBudgetUseCase _upsertBudget;
  final CreateFundUseCase _createFund;
  final ContributeToFundUseCase _contributeToFund;
  final RequestFundExpenseUseCase _requestFundExpense;
  final SubmitFundExpenseDraftUseCase _submitFundExpenseDraft;
  final DecideFundExpenseUseCase _decideFundExpense;
  final ExecuteFundExpenseUseCase _executeFundExpense;
  final ReconcileFundExpenseUseCase _reconcileFundExpense;
  final DisputeFundExpenseUseCase _disputeFundExpense;
  final ReverseFundExpenseUseCase _reverseFundExpense;
  final CancelFundExpenseUseCase _cancelFundExpense;

  String? _activeUserId;

  BudgetBloc({
    required BudgetRepository repository,
    required UpsertBudgetUseCase upsertBudget,
    required CreateFundUseCase createFund,
    required ContributeToFundUseCase contributeToFund,
    required RequestFundExpenseUseCase requestFundExpense,
    required DecideFundExpenseUseCase decideFundExpense,
    SubmitFundExpenseDraftUseCase? submitFundExpenseDraft,
    ExecuteFundExpenseUseCase? executeFundExpense,
    ReconcileFundExpenseUseCase? reconcileFundExpense,
    DisputeFundExpenseUseCase? disputeFundExpense,
    ReverseFundExpenseUseCase? reverseFundExpense,
    CancelFundExpenseUseCase? cancelFundExpense,
  }) : _repository = repository,
       _upsertBudget = upsertBudget,
       _createFund = createFund,
       _contributeToFund = contributeToFund,
       _requestFundExpense = requestFundExpense,
       _submitFundExpenseDraft =
           submitFundExpenseDraft ?? SubmitFundExpenseDraftUseCase(repository),
       _decideFundExpense = decideFundExpense,
       _executeFundExpense =
           executeFundExpense ?? ExecuteFundExpenseUseCase(repository),
       _reconcileFundExpense =
           reconcileFundExpense ?? ReconcileFundExpenseUseCase(repository),
       _disputeFundExpense =
           disputeFundExpense ?? DisputeFundExpenseUseCase(repository),
       _reverseFundExpense =
           reverseFundExpense ?? ReverseFundExpenseUseCase(repository),
       _cancelFundExpense =
           cancelFundExpense ?? CancelFundExpenseUseCase(repository),
       super(const BudgetState()) {
    on<BudgetsSubscriptionRequested>(
      _onSubscriptionRequested,
      transformer: restartable(),
    );
    on<BudgetUpsertSubmitted>(_onUpsertBudget, transformer: sequential());
    on<FundCreateSubmitted>(_onCreateFund, transformer: sequential());
    on<FundContributionSubmitted>(_onContributeFund, transformer: sequential());
    on<FundExpenseRequested>(_onRequestExpense, transformer: sequential());
    on<FundExpenseDraftSubmitted>(
      _onSubmitExpenseDraft,
      transformer: sequential(),
    );
    on<FundExpenseDecisionSubmitted>(
      _onDecideExpense,
      transformer: sequential(),
    );
    on<FundExpenseExecuted>(_onExecuteExpense, transformer: sequential());
    on<FundExpenseReconciled>(_onReconcileExpense, transformer: sequential());
    on<FundExpenseDisputed>(_onDisputeExpense, transformer: sequential());
    on<FundExpenseReversed>(_onReverseExpense, transformer: sequential());
    on<FundExpenseCancelled>(_onCancelExpense, transformer: sequential());
  }

  /// Dispatches [event] and awaits completion (`isSaving == false`) matching [operationId].
  Future<BudgetState> submitAndAwait(
    BudgetEvent event, {
    required String operationId,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    if (isClosed) {
      return state.copyWith(
        isSaving: false,
        failure: const UnexpectedFailure(message: 'Phiên làm việc đã đóng.'),
        lastActionOperationId: operationId,
      );
    }
    final waiter = stream
        .firstWhere(
          (s) =>
              !s.isSaving &&
              s.lastActionOperationId == operationId &&
              (s.failure != null || s.actionMessage != null),
        )
        .timeout(
          timeout,
          onTimeout: () => state.copyWith(
            isSaving: false,
            failure: const NetworkFailure(
              message: 'Hết thời gian chờ xác nhận giao dịch quỹ.',
            ),
            lastActionOperationId: operationId,
          ),
        );
    add(event);
    return waiter;
  }

  Future<void> _onSubscriptionRequested(
    BudgetsSubscriptionRequested event,
    Emitter<BudgetState> emit,
  ) async {
    _activeUserId = event.userId;
    emit(
      state.copyWith(isLoading: true, clearFailure: true, clearMessage: true),
    );
    final stream =
        StreamCombiner.combine2<
          Result<List<BudgetEntity>>,
          Result<List<FundEntity>>,
          BudgetState
        >(
          _repository.watchBudgets(
            userId: event.userId,
            monthKey: event.monthKey,
          ),
          _repository.watchFunds(
            userId: event.userId,
            familyId: event.familyId,
          ),
          (bRes, fRes) {
            if (bRes is Err<List<BudgetEntity>>) {
              return state.copyWith(
                isLoading: false,
                failure: bRes.failure,
                clearMessage: true,
              );
            }
            if (fRes is Err<List<FundEntity>>) {
              return state.copyWith(
                isLoading: false,
                failure: fRes.failure,
                clearMessage: true,
              );
            }
            return state.copyWith(
              isLoading: false,
              budgets: (bRes as Success<List<BudgetEntity>>).value,
              funds: (fRes as Success<List<FundEntity>>).value,
              clearFailure: true,
              clearMessage: true,
            );
          },
        );

    await emit.forEach<BudgetState>(stream, onData: (s) => s);
  }

  Future<void> _onUpsertBudget(
    BudgetUpsertSubmitted event,
    Emitter<BudgetState> emit,
  ) async {
    emit(
      state.copyWith(
        isSaving: true,
        clearFailure: true,
        clearMessage: true,
        clearOperationId: true,
      ),
    );
    final res = await _upsertBudget(event.params);
    res.fold(
      (f) => emit(state.copyWith(isSaving: false, failure: f)),
      (_) => emit(
        state.copyWith(
          isSaving: false,
          actionMessage: 'Đã lưu ngân sách tháng.',
        ),
      ),
    );
  }

  Future<void> _onCreateFund(
    FundCreateSubmitted event,
    Emitter<BudgetState> emit,
  ) async {
    emit(
      state.copyWith(
        isSaving: true,
        clearFailure: true,
        clearMessage: true,
        clearOperationId: true,
      ),
    );
    final res = await _createFund(event.params);
    res.fold(
      (f) => emit(state.copyWith(isSaving: false, failure: f)),
      (_) => emit(
        state.copyWith(isSaving: false, actionMessage: 'Đã tạo sổ quỹ mới.'),
      ),
    );
  }

  Future<void> _onContributeFund(
    FundContributionSubmitted event,
    Emitter<BudgetState> emit,
  ) async {
    final opId = event.params.operationId;
    emit(
      state.copyWith(
        isSaving: true,
        clearFailure: true,
        clearMessage: true,
        lastActionOperationId: opId,
        clearOperationId: opId == null,
      ),
    );
    final res = await _contributeToFund(event.params);
    res.fold(
      (f) => emit(
        state.copyWith(
          isSaving: false,
          failure: f,
          lastActionOperationId: opId,
        ),
      ),
      (_) => emit(
        state.copyWith(
          isSaving: false,
          actionMessage:
              event.params.sourceWalletId != null &&
                  event.params.sourceWalletId!.isNotEmpty
              ? 'Đã trừ ví nguồn và nạp quỹ thành công.'
              : 'Đã ghi nhận đóng góp vào quỹ.',
          lastActionOperationId: opId,
        ),
      ),
    );
  }

  Future<void> _onRequestExpense(
    FundExpenseRequested event,
    Emitter<BudgetState> emit,
  ) async {
    final opId = event.params.operationId;
    emit(
      state.copyWith(
        isSaving: true,
        clearFailure: true,
        clearMessage: true,
        lastActionOperationId: opId,
        clearOperationId: opId == null,
      ),
    );
    final res = await _requestFundExpense(event.params);
    res.fold(
      (f) => emit(
        state.copyWith(
          isSaving: false,
          failure: f,
          lastActionOperationId: opId,
        ),
      ),
      (_) => emit(
        state.copyWith(
          isSaving: false,
          actionMessage: event.params.saveAsDraft
              ? 'Đã lưu nháp đề xuất chi quỹ.'
              : event.params.scope == FundScope.personal &&
                    event.params.canAutoApprove
              ? 'Đã giải ngân khoản rút quỹ cá nhân.'
              : 'Đã gửi đề xuất chi quỹ chờ duyệt.',
          lastActionOperationId: opId,
        ),
      ),
    );
  }

  Future<void> _onSubmitExpenseDraft(
    FundExpenseDraftSubmitted event,
    Emitter<BudgetState> emit,
  ) async {
    emit(
      state.copyWith(isSaving: true, clearFailure: true, clearMessage: true),
    );
    final res = await _submitFundExpenseDraft(event.params);
    res.fold(
      (f) => emit(state.copyWith(isSaving: false, failure: f)),
      (_) => emit(
        state.copyWith(
          isSaving: false,
          actionMessage: 'Đã gửi đề xuất chi từ bản nháp.',
        ),
      ),
    );
  }

  Future<void> _onDecideExpense(
    FundExpenseDecisionSubmitted event,
    Emitter<BudgetState> emit,
  ) async {
    final opId = event.params.operationId;
    emit(
      state.copyWith(
        isSaving: true,
        clearFailure: true,
        clearMessage: true,
        lastActionOperationId: opId,
        clearOperationId: opId == null,
      ),
    );
    final effectiveParams =
        (event.params.actorUserId != null &&
                event.params.actorUserId!.trim().isNotEmpty) ||
            _activeUserId == null
        ? event.params
        : DecideFundExpenseParams(
            familyId: event.params.familyId,
            fundId: event.params.fundId,
            expenseId: event.params.expenseId,
            approve: event.params.approve,
            actorUserId: _activeUserId,
            operationId: event.params.operationId,
          );
    final res = await _decideFundExpense(effectiveParams);
    res.fold(
      (f) => emit(
        state.copyWith(
          isSaving: false,
          failure: f,
          lastActionOperationId: opId,
        ),
      ),
      (_) => emit(
        state.copyWith(
          isSaving: false,
          actionMessage: event.params.approve
              ? 'Đã phê duyệt khoản chi quỹ. Có thể tiến hành giải ngân.'
              : 'Đã từ chối khoản chi.',
          lastActionOperationId: opId,
        ),
      ),
    );
  }

  Future<void> _onExecuteExpense(
    FundExpenseExecuted event,
    Emitter<BudgetState> emit,
  ) async {
    final opId = event.params.operationId;
    emit(
      state.copyWith(
        isSaving: true,
        clearFailure: true,
        clearMessage: true,
        lastActionOperationId: opId,
        clearOperationId: opId == null,
      ),
    );
    final res = await _executeFundExpense(event.params);
    res.fold(
      (f) => emit(
        state.copyWith(
          isSaving: false,
          failure: f,
          lastActionOperationId: opId,
        ),
      ),
      (_) => emit(
        state.copyWith(
          isSaving: false,
          actionMessage: 'Đã giải ngân và ghi sổ kiểm toán quỹ.',
          lastActionOperationId: opId,
        ),
      ),
    );
  }

  Future<void> _onReconcileExpense(
    FundExpenseReconciled event,
    Emitter<BudgetState> emit,
  ) async {
    emit(
      state.copyWith(isSaving: true, clearFailure: true, clearMessage: true),
    );
    final res = await _reconcileFundExpense(event.params);
    res.fold(
      (f) => emit(state.copyWith(isSaving: false, failure: f)),
      (_) => emit(
        state.copyWith(
          isSaving: false,
          actionMessage: 'Đã đối soát khoản chi với giao dịch ngân hàng.',
        ),
      ),
    );
  }

  Future<void> _onDisputeExpense(
    FundExpenseDisputed event,
    Emitter<BudgetState> emit,
  ) async {
    emit(
      state.copyWith(isSaving: true, clearFailure: true, clearMessage: true),
    );
    final res = await _disputeFundExpense(event.params);
    res.fold(
      (f) => emit(state.copyWith(isSaving: false, failure: f)),
      (_) => emit(
        state.copyWith(
          isSaving: false,
          actionMessage: 'Đã ghi nhận khiếu nại khoản chi quỹ.',
        ),
      ),
    );
  }

  Future<void> _onReverseExpense(
    FundExpenseReversed event,
    Emitter<BudgetState> emit,
  ) async {
    emit(
      state.copyWith(isSaving: true, clearFailure: true, clearMessage: true),
    );
    final res = await _reverseFundExpense(event.params);
    res.fold(
      (f) => emit(state.copyWith(isSaving: false, failure: f)),
      (_) => emit(
        state.copyWith(
          isSaving: false,
          actionMessage: 'Đã hoàn tác khoản chi và cập nhật lại số dư quỹ.',
        ),
      ),
    );
  }

  Future<void> _onCancelExpense(
    FundExpenseCancelled event,
    Emitter<BudgetState> emit,
  ) async {
    emit(
      state.copyWith(isSaving: true, clearFailure: true, clearMessage: true),
    );
    final res = await _cancelFundExpense(event.params);
    res.fold(
      (f) => emit(state.copyWith(isSaving: false, failure: f)),
      (_) => emit(
        state.copyWith(
          isSaving: false,
          actionMessage: 'Đã hủy đề xuất chi quỹ.',
        ),
      ),
    );
  }
}
