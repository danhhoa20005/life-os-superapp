import 'package:equatable/equatable.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/utils/vietnamese_search_matcher.dart';
import '../../../../core/utils/vnd_amount.dart';
import '../../domain/entities/transaction_entities.dart';

enum LoadStatus { initial, loading, loaded, failure }

final class TransactionListState extends Equatable {
  static final Expando<List<TransactionEntity>> _filteredCache =
      Expando<List<TransactionEntity>>('_txFilteredCache');
  static final Expando<List<TransactionEntity>> _provisionalCache =
      Expando<List<TransactionEntity>>('_txProvisionalCache');

  final LoadStatus status;
  final String monthKey;
  final List<WalletEntity> wallets;
  final List<CategoryEntity> categories;
  final List<TransactionEntity> allTransactions;
  final String searchQuery;
  final TransactionKind? kindFilter;
  final String? selectedWalletId;
  final String? categoryFilter;
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
    this.selectedWalletId,
    this.categoryFilter,
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

  bool get hasActiveFilters =>
      searchQuery.trim().isNotEmpty ||
      kindFilter != null ||
      selectedWalletId != null ||
      categoryFilter != null;

  List<TransactionEntity> get filteredTransactions {
    final cached = _filteredCache[this];
    if (cached != null) return cached;

    final q = searchQuery.trim();
    final foldedCat = categoryFilter != null
        ? VietnameseSearchMatcher.fold(categoryFilter!)
        : null;
    final result = allTransactions
        .where((tx) {
          if (!tx.isConfirmedInLedger) return false;
          if (selectedWalletId != null &&
              tx.walletId != selectedWalletId &&
              tx.targetWalletId != selectedWalletId) {
            return false;
          }
          if (kindFilter != null) {
            if (kindFilter == TransactionKind.transfer) {
              if (tx.kind != TransactionKind.transfer &&
                  tx.kind != TransactionKind.creditCardPayment) {
                return false;
              }
            } else if (tx.kind != kindFilter) {
              return false;
            }
          }
          if (foldedCat != null) {
            final matchesPrimary =
                VietnameseSearchMatcher.fold(tx.categoryName) == foldedCat;
            final matchesSplit = tx.splitLines.any(
              (l) => VietnameseSearchMatcher.fold(l.categoryName) == foldedCat,
            );
            if (!matchesPrimary && !matchesSplit) return false;
          }
          if (q.isNotEmpty) {
            final matched = VietnameseSearchMatcher.matchesAny(q, [
              tx.merchant,
              tx.categoryName,
              ...tx.splitLines.map((l) => l.categoryName),
              tx.note,
              tx.walletName,
              tx.referenceCode,
              tx.amountMinor.toString(),
              VndAmount.format(tx.amountMinor),
            ]);
            if (!matched) return false;
          }
          return true;
        })
        .toList(growable: false);
    _filteredCache[this] = result;
    return result;
  }

  List<TransactionEntity> get provisionalTransactions {
    final cached = _provisionalCache[this];
    if (cached != null) return cached;
    final result = allTransactions
        .where(
          (tx) =>
              tx.verification == TransactionVerification.provisional ||
              tx.verification == TransactionVerification.needsReview,
        )
        .toList(growable: false);
    _provisionalCache[this] = result;
    return result;
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
    String? selectedWalletId,
    bool clearWalletFilter = false,
    String? categoryFilter,
    bool clearCategoryFilter = false,
    FinanceOverviewSummary? summary,
    Failure? failure,
    bool clearFailure = false,
  }) {
    return TransactionListState(
      status: status ?? this.status,
      monthKey: monthKey ?? this.monthKey,
      wallets: wallets != null ? List.unmodifiable(wallets) : this.wallets,
      categories: categories != null
          ? List.unmodifiable(categories)
          : this.categories,
      allTransactions: allTransactions != null
          ? List.unmodifiable(allTransactions)
          : this.allTransactions,
      searchQuery: searchQuery ?? this.searchQuery,
      kindFilter: clearKindFilter ? null : (kindFilter ?? this.kindFilter),
      selectedWalletId: clearWalletFilter
          ? null
          : (selectedWalletId ?? this.selectedWalletId),
      categoryFilter: clearCategoryFilter
          ? null
          : (categoryFilter ?? this.categoryFilter),
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
    selectedWalletId,
    categoryFilter,
    summary,
    failure,
  ];
}

enum ActionStatus { idle, submitting, success, failure }

final class TransactionActionState extends Equatable {
  final ActionStatus status;
  final String? lastOperationId;
  final String? successMessage;
  final Failure? failure;
  final TransactionEntity? lastCreatedTransaction;

  const TransactionActionState({
    this.status = ActionStatus.idle,
    this.lastOperationId,
    this.successMessage,
    this.failure,
    this.lastCreatedTransaction,
  });

  @override
  List<Object?> get props => [
    status,
    lastOperationId,
    successMessage,
    failure,
    lastCreatedTransaction,
  ];
}
