import 'package:equatable/equatable.dart';
import 'transaction_entities.dart';

/// Immutable, pure-integer VND result produced by [FinancialAggregationEngine].
///
/// Accounting invariants:
/// - `transfer` and `creditCardPayment` accumulate into [internalTransferMinor]
///   and NEVER inflate [incomeMinor] or [grossExpenseMinor].
/// - `provisional` and `needsReview` increment [unconfirmedCount] and
///   [provisionalAmountMinor], NEVER confirmed cashflow.
/// - `rejected` and reversed entries (plus compensating `reversal` entries)
///   are excluded from confirmed income/expense totals.
/// - Confirmed refunds are tracked separately in [refundMinor] so they do not
///   inflate salary/regular [incomeMinor], and enable exact [netExpenseMinor].
class FinancialAggregationResult extends Equatable {
  final int netWorthMinor;
  final int liquidAssetsMinor;
  final int savingsAssetsMinor;
  final int creditLiabilityMinor;
  final int incomeMinor;
  final int grossExpenseMinor;
  final int refundMinor;
  final int internalTransferMinor;
  final int unconfirmedCount;
  final int provisionalCount;
  final int needsReviewCount;
  final int provisionalAmountMinor;
  final int rejectedCount;
  final int reversedCount;
  final int reversedAmountMinor;
  final int verifiedCount;
  final int userConfirmedCount;
  final int matchedPaymentOrderCount;
  final int totalEvaluatedCount;
  final Map<String, int> expenseByCategory;
  final Map<String, int> refundByCategory;

  const FinancialAggregationResult({
    this.netWorthMinor = 0,
    this.liquidAssetsMinor = 0,
    this.savingsAssetsMinor = 0,
    this.creditLiabilityMinor = 0,
    required this.incomeMinor,
    required this.grossExpenseMinor,
    this.refundMinor = 0,
    required this.internalTransferMinor,
    this.unconfirmedCount = 0,
    this.provisionalCount = 0,
    this.needsReviewCount = 0,
    this.provisionalAmountMinor = 0,
    this.rejectedCount = 0,
    this.reversedCount = 0,
    this.reversedAmountMinor = 0,
    this.verifiedCount = 0,
    this.userConfirmedCount = 0,
    this.matchedPaymentOrderCount = 0,
    this.totalEvaluatedCount = 0,
    required this.expenseByCategory,
    this.refundByCategory = const {},
  });

  /// Alias matching standard gross expense sum across [expenseByCategory].
  int get expenseMinor => grossExpenseMinor;

  /// Net spending after deducting confirmed refunds (`grossExpense - refunds`).
  int get netExpenseMinor => grossExpenseMinor - refundMinor;

  /// Net cashflow across the period (`income + refunds - grossExpense`).
  int get netCashFlowMinor => incomeMinor + refundMinor - grossExpenseMinor;

  int get confirmedCount =>
      verifiedCount + userConfirmedCount + matchedPaymentOrderCount;

  /// Converts this aggregation snapshot to a [FinanceOverviewSummary] for UI &
  /// dashboard consumers.
  FinanceOverviewSummary toOverviewSummary() {
    return FinanceOverviewSummary(
      netWorthMinor: netWorthMinor,
      liquidAssetsMinor: liquidAssetsMinor,
      savingsAssetsMinor: savingsAssetsMinor,
      creditLiabilityMinor: creditLiabilityMinor,
      monthlyIncomeMinor: incomeMinor,
      monthlyExpenseMinor: grossExpenseMinor,
      monthlyRefundMinor: refundMinor,
      monthlyInternalTransferMinor: internalTransferMinor,
      provisionalCount: provisionalCount,
      needsReviewCount: needsReviewCount,
      unconfirmedCount: unconfirmedCount,
      verifiedCount: verifiedCount,
      userConfirmedCount: userConfirmedCount,
      matchedPaymentOrderCount: matchedPaymentOrderCount,
      expenseByCategory: expenseByCategory,
    );
  }

  @override
  List<Object?> get props => [
    netWorthMinor,
    liquidAssetsMinor,
    savingsAssetsMinor,
    creditLiabilityMinor,
    incomeMinor,
    grossExpenseMinor,
    refundMinor,
    internalTransferMinor,
    unconfirmedCount,
    provisionalCount,
    needsReviewCount,
    provisionalAmountMinor,
    rejectedCount,
    reversedCount,
    reversedAmountMinor,
    verifiedCount,
    userConfirmedCount,
    matchedPaymentOrderCount,
    totalEvaluatedCount,
    expenseByCategory,
    refundByCategory,
  ];
}

/// Pure Dart accounting & time-window aggregation engine (`FIX-001`).
/// Zero Flutter / Firebase dependencies; all monetary arithmetic uses integer VND.
abstract final class FinancialAggregationEngine {
  static final RegExp _refundPattern = RegExp(
    r'(ho[aà]n\s*ti[eề]n|hoan\s*tien|\brefund\b|b[oồ]i\s*ho[aà]n|boi\s*hoan)',
    caseSensitive: false,
  );

  /// Aggregates all transactions occurring on the calendar day of [day].
  static FinancialAggregationResult forDay(
    List<TransactionEntity> transactions,
    DateTime day, {
    List<WalletEntity> wallets = const [],
  }) {
    final start = day.isUtc
        ? DateTime.utc(day.year, day.month, day.day)
        : DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    return forRange(
      transactions,
      startInclusive: start,
      endExclusive: end,
      wallets: wallets,
    );
  }

  /// Aggregates all transactions in the ISO week (Monday 00:00 -> +7d) containing [anchorDate].
  static FinancialAggregationResult forWeek(
    List<TransactionEntity> transactions,
    DateTime anchorDate, {
    List<WalletEntity> wallets = const [],
  }) {
    final dayStart = anchorDate.isUtc
        ? DateTime.utc(anchorDate.year, anchorDate.month, anchorDate.day)
        : DateTime(anchorDate.year, anchorDate.month, anchorDate.day);
    final start = dayStart.subtract(
      Duration(days: dayStart.weekday - DateTime.monday),
    );
    final end = start.add(const Duration(days: 7));
    return forRange(
      transactions,
      startInclusive: start,
      endExclusive: end,
      wallets: wallets,
    );
  }

  /// Aggregates all transactions in calendar month ([year], [month]).
  static FinancialAggregationResult forMonth(
    List<TransactionEntity> transactions,
    int year,
    int month, {
    List<WalletEntity> wallets = const [],
    bool useUtc = false,
  }) {
    final start = useUtc
        ? DateTime.utc(year, month, 1)
        : DateTime(year, month, 1);
    final end = useUtc
        ? DateTime.utc(year, month + 1, 1)
        : DateTime(year, month + 1, 1);
    return forRange(
      transactions,
      startInclusive: start,
      endExclusive: end,
      wallets: wallets,
    );
  }

  /// Aggregates transactions matching `YYYY-MM` [monthKey] (by date window or monthKey).
  static FinancialAggregationResult forMonthKey(
    List<TransactionEntity> transactions,
    String monthKey, {
    List<WalletEntity> wallets = const [],
  }) {
    final parts = monthKey.split('-');
    if (parts.length == 2) {
      final year = int.tryParse(parts[0]);
      final month = int.tryParse(parts[1]);
      if (year != null && month != null && month >= 1 && month <= 12) {
        final matching = transactions.where((tx) {
          if (tx.monthKey == monthKey) return true;
          return tx.occurredAt.year == year && tx.occurredAt.month == month;
        }).toList(growable: false);
        return aggregate(
          matching,
          wallets: wallets,
          allReferenceTransactions: transactions,
        );
      }
    }
    final matching = transactions
        .where((tx) => tx.monthKey == monthKey)
        .toList(growable: false);
    return aggregate(
      matching,
      wallets: wallets,
      allReferenceTransactions: transactions,
    );
  }

  /// Aggregates all transactions in calendar quarter `1..4` of [year].
  static FinancialAggregationResult forQuarter(
    List<TransactionEntity> transactions,
    int year,
    int quarter, {
    List<WalletEntity> wallets = const [],
    bool useUtc = false,
  }) {
    final q = quarter.clamp(1, 4);
    final startMonth = (q - 1) * 3 + 1;
    final start = useUtc
        ? DateTime.utc(year, startMonth, 1)
        : DateTime(year, startMonth, 1);
    final end = useUtc
        ? DateTime.utc(year, startMonth + 3, 1)
        : DateTime(year, startMonth + 3, 1);
    return forRange(
      transactions,
      startInclusive: start,
      endExclusive: end,
      wallets: wallets,
    );
  }

  /// Aggregates all transactions in calendar [year].
  static FinancialAggregationResult forYear(
    List<TransactionEntity> transactions,
    int year, {
    List<WalletEntity> wallets = const [],
    bool useUtc = false,
  }) {
    final start = useUtc ? DateTime.utc(year, 1, 1) : DateTime(year, 1, 1);
    final end = useUtc
        ? DateTime.utc(year + 1, 1, 1)
        : DateTime(year + 1, 1, 1);
    return forRange(
      transactions,
      startInclusive: start,
      endExclusive: end,
      wallets: wallets,
    );
  }

  /// Aggregates all transactions in `[startInclusive, endExclusive)`.
  ///
  /// Cross-period reversal pairing is preserved by scanning [transactions] for
  /// `TransactionKind.reversal.reversalOfId` before slicing the window.
  static FinancialAggregationResult forRange(
    List<TransactionEntity> transactions, {
    required DateTime startInclusive,
    required DateTime endExclusive,
    List<WalletEntity> wallets = const [],
  }) {
    final sliced = transactions
        .where(
          (tx) =>
              !tx.occurredAt.isBefore(startInclusive) &&
              tx.occurredAt.isBefore(endExclusive),
        )
        .toList(growable: false);
    return aggregate(
      sliced,
      wallets: wallets,
      allReferenceTransactions: transactions,
    );
  }

  /// Determines whether [tx] represents an incoming refund credit.
  static bool isRefundTransaction(TransactionEntity tx) {
    if (tx.isRefund) return true;
    if (tx.kind != TransactionKind.income && tx.direction != 'credit') {
      return false;
    }
    return _refundPattern.hasMatch(tx.categoryName) ||
        (tx.note != null && _refundPattern.hasMatch(tx.note!)) ||
        _refundPattern.hasMatch(tx.merchant);
  }

  /// Aggregates an arbitrary list of transactions with deterministic ledger rules.
  static FinancialAggregationResult aggregate(
    List<TransactionEntity> transactions, {
    List<WalletEntity> wallets = const [],
    List<TransactionEntity>? allReferenceTransactions,
  }) {
    final refList = allReferenceTransactions ?? transactions;
    final reversedTargetIds = <String>{};
    for (final tx in refList) {
      if (tx.kind == TransactionKind.reversal &&
          tx.verification != TransactionVerification.rejected &&
          tx.reversalOfId != null &&
          tx.reversalOfId!.isNotEmpty) {
        reversedTargetIds.add(tx.reversalOfId!);
      }
    }

    final netWorth = wallets.fold<int>(0, (sum, w) => sum + w.balanceMinor);
    var liquidAssets = 0;
    var savingsAssets = 0;
    var creditLiability = 0;
    for (final w in wallets) {
      switch (w.type) {
        case WalletType.cash:
        case WalletType.bank:
          if (w.balanceMinor > 0) liquidAssets += w.balanceMinor;
        case WalletType.savings:
          if (w.balanceMinor > 0) savingsAssets += w.balanceMinor;
        case WalletType.creditCard:
          if (w.balanceMinor < 0) creditLiability += -w.balanceMinor;
      }
    }

    var incomeMinor = 0;
    var grossExpenseMinor = 0;
    var refundMinor = 0;
    var internalTransferMinor = 0;
    var provisionalCount = 0;
    var needsReviewCount = 0;
    var provisionalAmountMinor = 0;
    var rejectedCount = 0;
    var reversedCount = 0;
    var reversedAmountMinor = 0;
    var verifiedCount = 0;
    var userConfirmedCount = 0;
    var matchedPaymentOrderCount = 0;
    final countedReversedKeys = <String>{};
    final expenseBreakdown = <String, int>{};
    final refundBreakdown = <String, int>{};

    for (final tx in transactions) {
      if (tx.verification == TransactionVerification.rejected) {
        rejectedCount += 1;
        continue;
      }
      if (tx.verification == TransactionVerification.provisional) {
        provisionalCount += 1;
        provisionalAmountMinor += tx.amountMinor;
        continue;
      }
      if (tx.verification == TransactionVerification.needsReview) {
        needsReviewCount += 1;
        provisionalAmountMinor += tx.amountMinor;
        continue;
      }
      if (!tx.isConfirmedInLedger) {
        continue;
      }

      final isReversedOriginal =
          tx.isReversed || reversedTargetIds.contains(tx.id);
      if (isReversedOriginal) {
        if (countedReversedKeys.add(tx.id)) {
          reversedCount += 1;
          reversedAmountMinor += tx.amountMinor;
        }
        continue;
      }

      if (tx.kind == TransactionKind.reversal) {
        final pairKey =
            (tx.reversalOfId != null && tx.reversalOfId!.isNotEmpty)
            ? tx.reversalOfId!
            : tx.id;
        if (countedReversedKeys.add(pairKey)) {
          reversedCount += 1;
          reversedAmountMinor += tx.amountMinor;
        }
        continue;
      }

      switch (tx.verification) {
        case TransactionVerification.verified:
          verifiedCount += 1;
        case TransactionVerification.userConfirmed:
          userConfirmedCount += 1;
        case TransactionVerification.matchedPaymentOrder:
          matchedPaymentOrderCount += 1;
        case TransactionVerification.provisional:
        case TransactionVerification.needsReview:
        case TransactionVerification.rejected:
          break;
      }

      switch (tx.kind) {
        case TransactionKind.expense:
          grossExpenseMinor += tx.amountMinor;
          if (tx.splitLines.isNotEmpty) {
            for (final line in tx.splitLines) {
              if (line.categoryName.isEmpty || line.amountMinor <= 0) continue;
              expenseBreakdown[line.categoryName] =
                  (expenseBreakdown[line.categoryName] ?? 0) + line.amountMinor;
            }
          } else {
            expenseBreakdown[tx.categoryName] =
                (expenseBreakdown[tx.categoryName] ?? 0) + tx.amountMinor;
          }
        case TransactionKind.income:
          if (isRefundTransaction(tx)) {
            refundMinor += tx.amountMinor;
            refundBreakdown[tx.categoryName] =
                (refundBreakdown[tx.categoryName] ?? 0) + tx.amountMinor;
          } else {
            incomeMinor += tx.amountMinor;
          }
        case TransactionKind.transfer:
        case TransactionKind.creditCardPayment:
          internalTransferMinor += tx.amountMinor;
        case TransactionKind.reversal:
          break;
      }
    }

    return FinancialAggregationResult(
      netWorthMinor: netWorth,
      liquidAssetsMinor: liquidAssets,
      savingsAssetsMinor: savingsAssets,
      creditLiabilityMinor: creditLiability,
      incomeMinor: incomeMinor,
      grossExpenseMinor: grossExpenseMinor,
      refundMinor: refundMinor,
      internalTransferMinor: internalTransferMinor,
      unconfirmedCount: provisionalCount + needsReviewCount,
      provisionalCount: provisionalCount,
      needsReviewCount: needsReviewCount,
      provisionalAmountMinor: provisionalAmountMinor,
      rejectedCount: rejectedCount,
      reversedCount: reversedCount,
      reversedAmountMinor: reversedAmountMinor,
      verifiedCount: verifiedCount,
      userConfirmedCount: userConfirmedCount,
      matchedPaymentOrderCount: matchedPaymentOrderCount,
      totalEvaluatedCount: transactions.length,
      expenseByCategory: Map.unmodifiable(expenseBreakdown),
      refundByCategory: Map.unmodifiable(refundBreakdown),
    );
  }

  /// Computes today's gross expense and trailing [days]-day daily confirmed
  /// expense/income series ending on [referenceNow], respecting all reversal,
  /// transfer, refund, and verification rules in a single O(N) pass.
  static ({
    int todayExpenseMinor,
    List<int> dailyExpensesMinor,
    List<int> dailyIncomesMinor,
  }) computeRecentDailyCashflow(
    List<TransactionEntity> transactions, {
    required DateTime referenceNow,
    int days = 7,
  }) {
    final reversedTargetIds = <String>{};
    for (final tx in transactions) {
      if (tx.kind == TransactionKind.reversal &&
          tx.verification != TransactionVerification.rejected &&
          tx.reversalOfId != null &&
          tx.reversalOfId!.isNotEmpty) {
        reversedTargetIds.add(tx.reversalOfId!);
      }
    }

    final todayStart = referenceNow.isUtc
        ? DateTime.utc(referenceNow.year, referenceNow.month, referenceNow.day)
        : DateTime(referenceNow.year, referenceNow.month, referenceNow.day);
    final dailyExp = List<int>.filled(days, 0);
    final dailyInc = List<int>.filled(days, 0);
    var todayExpense = 0;

    for (final tx in transactions) {
      if (!tx.isConfirmedInLedger ||
          tx.isReversed ||
          reversedTargetIds.contains(tx.id) ||
          tx.kind == TransactionKind.reversal) {
        continue;
      }

      final txLocal = referenceNow.isUtc
          ? tx.occurredAt.toUtc()
          : tx.occurredAt.toLocal();
      final txDay = referenceNow.isUtc
          ? DateTime.utc(txLocal.year, txLocal.month, txLocal.day)
          : DateTime(txLocal.year, txLocal.month, txLocal.day);
      final daysAgo = todayStart.difference(txDay).inDays;

      if (tx.kind == TransactionKind.expense) {
        if (daysAgo == 0) {
          todayExpense += tx.amountMinor;
        }
        if (daysAgo >= 0 && daysAgo < days) {
          dailyExp[(days - 1) - daysAgo] += tx.amountMinor;
        }
      } else if (tx.kind == TransactionKind.income &&
          !isRefundTransaction(tx)) {
        if (daysAgo >= 0 && daysAgo < days) {
          dailyInc[(days - 1) - daysAgo] += tx.amountMinor;
        }
      }
    }

    return (
      todayExpenseMinor: todayExpense,
      dailyExpensesMinor: List<int>.unmodifiable(dailyExp),
      dailyIncomesMinor: List<int>.unmodifiable(dailyInc),
    );
  }
}
