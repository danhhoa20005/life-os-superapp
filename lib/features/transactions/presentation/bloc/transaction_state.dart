import 'package:equatable/equatable.dart';
import '../../../../core/error/failure.dart';
import '../../domain/entities/transaction_entities.dart';

enum LoadStatus { initial, loading, loaded, failure }

final class TransactionListState extends Equatable {
  final LoadStatus status;
  final String monthKey;
  final List<WalletEntity> wallets;
  final List<CategoryEntity> categories;
  final List<TransactionEntity> allTransactions;
  final String searchQuery;
  final TransactionKind? kindFilter;
  final FinanceOverviewSummary summary;
  final Failure? failure;

  const TransactionListState({
    this.status = LoadStatus.initial,
    required this.monthKey,
    this.wallets = const [],
    this.categories = const [],
    this.allTransactions = const [],
    this.searchQuery = '',
    this.kindFilter,
    this.summary = const FinanceOverviewSummary(
      netWorthMinor: 0,
      monthlyIncomeMinor: 0,
      monthlyExpenseMinor: 0,
      monthlyInternalTransferMinor: 0,
      provisionalCount: 0,
      expenseByCategory: {},
    ),
    this.failure,
  });

  List<TransactionEntity> get filteredTransactions {
    final q = searchQuery.trim().toLowerCase();
    return allTransactions.where((tx) {
      if (tx.verification == TransactionVerification.rejected) return false;
      if (kindFilter != null && tx.kind != kindFilter) return false;
      if (q.isNotEmpty) {
        final matchMerchant = tx.merchant.toLowerCase().contains(q);
        final matchCategory = tx.categoryName.toLowerCase().contains(q);
        final matchNote = (tx.note ?? '').toLowerCase().contains(q);
        if (!matchMerchant && !matchCategory && !matchNote) return false;
      }
      return true;
    }).toList(growable: false);
  }

  List<TransactionEntity> get provisionalTransactions {
    return allTransactions
        .where((tx) => tx.verification == TransactionVerification.provisional)
        .toList(growable: false);
  }

  TransactionListState copyWith({
    LoadStatus? status,
    String? monthKey,
    List<WalletEntity>? wallets,
    List<CategoryEntity>? categories,
    List<TransactionEntity>? allTransactions,
    String? searchQuery,
    TransactionKind? kindFilter,
    bool clearKindFilter = false,
    FinanceOverviewSummary? summary,
    Failure? failure,
    bool clearFailure = false,
  }) {
    return TransactionListState(
      status: status ?? this.status,
      monthKey: monthKey ?? this.monthKey,
      wallets: wallets != null ? List.unmodifiable(wallets) : this.wallets,
      categories: categories != null ? List.unmodifiable(categories) : this.categories,
      allTransactions:
          allTransactions != null ? List.unmodifiable(allTransactions) : this.allTransactions,
      searchQuery: searchQuery ?? this.searchQuery,
      kindFilter: clearKindFilter ? null : (kindFilter ?? this.kindFilter),
      summary: summary ?? this.summary,
      failure: clearFailure ? null : (failure ?? this.failure),
    );
  }

  @override
  List<Object?> get props => [
        status,
        monthKey,
        wallets,
        categories,
        allTransactions,
        searchQuery,
        kindFilter,
        summary,
        failure,
      ];
}

enum ActionStatus { idle, submitting, success, failure }

final class TransactionActionState extends Equatable {
  final ActionStatus status;
  final String? successMessage;
  final Failure? failure;
  final TransactionEntity? lastCreatedTransaction;

  const TransactionActionState({
    this.status = ActionStatus.idle,
    this.successMessage,
    this.failure,
    this.lastCreatedTransaction,
  });

  @override
  List<Object?> get props => [status, successMessage, failure, lastCreatedTransaction];
}
