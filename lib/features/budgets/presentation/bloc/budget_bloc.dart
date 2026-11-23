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

final class FundExpenseDecisionSubmitted extends BudgetEvent {
  final DecideFundExpenseParams params;
  const FundExpenseDecisionSubmitted(this.params);

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

  const BudgetState({
    this.isLoading = false,
    this.isSaving = false,
    this.budgets = const [],
    this.funds = const [],
    this.failure,
    this.actionMessage,
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
  ];
}

class BudgetBloc extends Bloc<BudgetEvent, BudgetState> {
  final BudgetRepository _repository;
  final UpsertBudgetUseCase _upsertBudget;
  final CreateFundUseCase _createFund;
  final ContributeToFundUseCase _contributeToFund;
  final RequestFundExpenseUseCase _requestFundExpense;
  final DecideFundExpenseUseCase _decideFundExpense;

  BudgetBloc({
    required BudgetRepository repository,
    required UpsertBudgetUseCase upsertBudget,
    required CreateFundUseCase createFund,
    required ContributeToFundUseCase contributeToFund,
    required RequestFundExpenseUseCase requestFundExpense,
    required DecideFundExpenseUseCase decideFundExpense,
  }) : _repository = repository,
       _upsertBudget = upsertBudget,
       _createFund = createFund,
       _contributeToFund = contributeToFund,
       _requestFundExpense = requestFundExpense,
       _decideFundExpense = decideFundExpense,
       super(const BudgetState()) {
    on<BudgetsSubscriptionRequested>(
      _onSubscriptionRequested,
      transformer: restartable(),
    );
    on<BudgetUpsertSubmitted>(_onUpsertBudget, transformer: sequential());
    on<FundCreateSubmitted>(_onCreateFund, transformer: sequential());
    on<FundContributionSubmitted>(_onContributeFund, transformer: sequential());
    on<FundExpenseRequested>(_onRequestExpense, transformer: sequential());
    on<FundExpenseDecisionSubmitted>(
      _onDecideExpense,
      transformer: sequential(),
    );
  }

  Future<void> _onSubscriptionRequested(
    BudgetsSubscriptionRequested event,
    Emitter<BudgetState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, clearFailure: true));
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
              return state.copyWith(isLoading: false, failure: bRes.failure);
            }
            if (fRes is Err<List<FundEntity>>) {
              return state.copyWith(isLoading: false, failure: fRes.failure);
            }
            return state.copyWith(
              isLoading: false,
              budgets: (bRes as Success<List<BudgetEntity>>).value,
              funds: (fRes as Success<List<FundEntity>>).value,
              clearFailure: true,
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
      state.copyWith(isSaving: true, clearFailure: true, clearMessage: true),
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
      state.copyWith(isSaving: true, clearFailure: true, clearMessage: true),
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
    emit(
      state.copyWith(isSaving: true, clearFailure: true, clearMessage: true),
    );
    final res = await _contributeToFund(event.params);
    res.fold(
      (f) => emit(state.copyWith(isSaving: false, failure: f)),
      (_) => emit(
        state.copyWith(
          isSaving: false,
          actionMessage: 'Đã ghi nhận đóng góp vào quỹ.',
        ),
      ),
    );
  }

  Future<void> _onRequestExpense(
    FundExpenseRequested event,
    Emitter<BudgetState> emit,
  ) async {
    emit(
      state.copyWith(isSaving: true, clearFailure: true, clearMessage: true),
    );
    final res = await _requestFundExpense(event.params);
    res.fold(
      (f) => emit(state.copyWith(isSaving: false, failure: f)),
      (_) => emit(
        state.copyWith(
          isSaving: false,
          actionMessage: 'Đã ghi nhận đề xuất chi quỹ.',
        ),
      ),
    );
  }

  Future<void> _onDecideExpense(
    FundExpenseDecisionSubmitted event,
    Emitter<BudgetState> emit,
  ) async {
    emit(
      state.copyWith(isSaving: true, clearFailure: true, clearMessage: true),
    );
    final res = await _decideFundExpense(event.params);
    res.fold(
      (f) => emit(state.copyWith(isSaving: false, failure: f)),
      (_) => emit(
        state.copyWith(
          isSaving: false,
          actionMessage: event.params.approve
              ? 'Đã phê duyệt khoản chi quỹ.'
              : 'Đã từ chối khoản chi.',
        ),
      ),
    );
  }
}
