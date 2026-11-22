import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';

import '../../../../core/error/app_exception.dart';
import '../../../../core/utils/stream_combiner.dart';
import '../../domain/entities/transaction_entities.dart';
import '../../domain/repositories/transaction_repository.dart';
import '../../domain/usecases/transaction_usecases.dart';
import 'transaction_event.dart';
import 'transaction_state.dart';

class TransactionListBloc extends Bloc<TransactionListEvent, TransactionListState> {
  final TransactionRepository _repository;

  static String currentMonthKey() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';
  }

  TransactionListBloc({required TransactionRepository repository})
      : _repository = repository,
        super(TransactionListState(monthKey: currentMonthKey())) {
    on<TransactionsSubscriptionRequested>(
      _onSubscriptionRequested,
      transformer: restartable(),
    );
    on<TransactionsSearchChanged>(
      _onSearchChanged,
      transformer: restartable(),
    );
    on<TransactionsKindFilterChanged>(
      _onKindFilterChanged,
      transformer: restartable(),
    );
  }

  Future<void> _onSubscriptionRequested(
    TransactionsSubscriptionRequested event,
    Emitter<TransactionListState> emit,
  ) async {
    final targetMonth = event.monthKey ?? state.monthKey;
    emit(state.copyWith(status: LoadStatus.loading, monthKey: targetMonth, clearFailure: true));

    final combinedStream = StreamCombiner.combine3<
        Result<List<WalletEntity>>,
        Result<List<CategoryEntity>>,
        Result<List<TransactionEntity>>,
        TransactionListState>(
      _repository.watchWallets(event.userId),
      _repository.watchCategories(event.userId),
      _repository.watchTransactions(userId: event.userId, monthKey: targetMonth),
      (walletsRes, catsRes, txsRes) {
        if (walletsRes is Err<List<WalletEntity>>) {
          return state.copyWith(status: LoadStatus.failure, failure: walletsRes.failure);
        }
        if (catsRes is Err<List<CategoryEntity>>) {
          return state.copyWith(status: LoadStatus.failure, failure: catsRes.failure);
        }
        if (txsRes is Err<List<TransactionEntity>>) {
          return state.copyWith(status: LoadStatus.failure, failure: txsRes.failure);
        }
        final wallets = (walletsRes as Success<List<WalletEntity>>).value;
        final categories = (catsRes as Success<List<CategoryEntity>>).value;
        final txs = (txsRes as Success<List<TransactionEntity>>).value;
        final summary = FinanceOverviewSummary.compute(
          wallets: wallets,
          transactions: txs,
        );
        return state.copyWith(
          status: LoadStatus.loaded,
          monthKey: targetMonth,
          wallets: wallets,
          categories: categories,
          allTransactions: txs,
          summary: summary,
          clearFailure: true,
        );
      },
    );

    await emit.forEach<TransactionListState>(
      combinedStream,
      onData: (nextState) => nextState,
    );
  }

  void _onSearchChanged(
    TransactionsSearchChanged event,
    Emitter<TransactionListState> emit,
  ) {
    emit(state.copyWith(searchQuery: event.query));
  }

  void _onKindFilterChanged(
    TransactionsKindFilterChanged event,
    Emitter<TransactionListState> emit,
  ) {
    if (event.kind == null) {
      emit(state.copyWith(clearKindFilter: true));
    } else {
      emit(state.copyWith(kindFilter: event.kind));
    }
  }
}

/// Dedicated write BLoC using `sequential()` event concurrency so financial mutations
/// never overlap or drop user actions, paired with `operationId` idempotency.
class TransactionActionBloc extends Bloc<TransactionActionEvent, TransactionActionState> {
  final CreateWalletUseCase _createWallet;
  final CreateTransactionUseCase _createTransaction;
  final ReverseTransactionUseCase _reverseTransaction;
  final DecideProvisionalTransactionUseCase _decideProvisional;

  final Set<String> _inFlightOperationIds = <String>{};

  TransactionActionBloc({
    required CreateWalletUseCase createWallet,
    required CreateTransactionUseCase createTransaction,
    required ReverseTransactionUseCase reverseTransaction,
    required DecideProvisionalTransactionUseCase decideProvisional,
  })  : _createWallet = createWallet,
        _createTransaction = createTransaction,
        _reverseTransaction = reverseTransaction,
        _decideProvisional = decideProvisional,
        super(const TransactionActionState()) {
    on<WalletCreateSubmitted>(_onWalletCreate, transformer: sequential());
    on<TransactionCreateSubmitted>(_onTransactionCreate, transformer: sequential());
    on<TransactionReverseRequested>(_onTransactionReverse, transformer: sequential());
    on<ProvisionalTransactionDecisionSubmitted>(
      _onProvisionalDecision,
      transformer: sequential(),
    );
  }

  Future<void> _onWalletCreate(
    WalletCreateSubmitted event,
    Emitter<TransactionActionState> emit,
  ) async {
    emit(const TransactionActionState(status: ActionStatus.submitting));
    final res = await _createWallet(
      CreateWalletParams(
        userId: event.userId,
        name: event.name,
        type: event.type,
        openingBalanceMinor: event.openingBalanceMinor,
        bankCode: event.bankCode,
        maskedAccount: event.maskedAccount,
      ),
    );
    res.fold(
      (failure) => emit(TransactionActionState(status: ActionStatus.failure, failure: failure)),
      (wallet) => emit(
        TransactionActionState(
          status: ActionStatus.success,
          successMessage: 'Đã tạo ví "${wallet.name}".',
        ),
      ),
    );
  }

  Future<void> _onTransactionCreate(
    TransactionCreateSubmitted event,
    Emitter<TransactionActionState> emit,
  ) async {
    if (_inFlightOperationIds.contains(event.operationId)) {
      return;
    }
    _inFlightOperationIds.add(event.operationId);
    emit(const TransactionActionState(status: ActionStatus.submitting));
    try {
      final res = await _createTransaction(
        CreateTransactionParams(
          operationId: event.operationId,
          userId: event.userId,
          walletId: event.walletId,
          targetWalletId: event.targetWalletId,
          categoryId: event.categoryId,
          categoryName: event.categoryName,
          kind: event.kind,
          amountMinor: event.amountMinor,
          merchant: event.merchant,
          note: event.note,
          occurredAt: event.occurredAt,
          splitLines: event.splitLines,
        ),
      );
      res.fold(
        (failure) => emit(TransactionActionState(status: ActionStatus.failure, failure: failure)),
        (tx) => emit(
          TransactionActionState(
            status: ActionStatus.success,
            successMessage: 'Đã ghi nhận giao dịch thành công.',
            lastCreatedTransaction: tx,
          ),
        ),
      );
    } finally {
      _inFlightOperationIds.remove(event.operationId);
    }
  }

  Future<void> _onTransactionReverse(
    TransactionReverseRequested event,
    Emitter<TransactionActionState> emit,
  ) async {
    emit(const TransactionActionState(status: ActionStatus.submitting));
    final res = await _reverseTransaction(
      ReverseTransactionParams(
        userId: event.userId,
        transactionId: event.transactionId,
        reason: event.reason,
      ),
    );
    res.fold(
      (failure) => emit(TransactionActionState(status: ActionStatus.failure, failure: failure)),
      (_) => emit(
        const TransactionActionState(
          status: ActionStatus.success,
          successMessage: 'Đã tạo bút toán đảo và hoàn lại số dư ví.',
        ),
      ),
    );
  }

  Future<void> _onProvisionalDecision(
    ProvisionalTransactionDecisionSubmitted event,
    Emitter<TransactionActionState> emit,
  ) async {
    emit(const TransactionActionState(status: ActionStatus.submitting));
    final res = await _decideProvisional(
      DecideProvisionalParams(
        userId: event.userId,
        transactionId: event.transactionId,
        approve: event.approve,
        updatedCategoryName: event.updatedCategoryName,
        updatedMerchant: event.updatedMerchant,
      ),
    );
    res.fold(
      (failure) => emit(TransactionActionState(status: ActionStatus.failure, failure: failure)),
      (_) => emit(
        TransactionActionState(
          status: ActionStatus.success,
          successMessage: event.approve
              ? 'Đã xác nhận giao dịch vào sổ cái.'
              : 'Đã bỏ qua gợi ý giao dịch.',
        ),
      ),
    );
  }
}
