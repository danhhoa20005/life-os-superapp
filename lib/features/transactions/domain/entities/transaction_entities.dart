import 'package:equatable/equatable.dart';

enum WalletType { cash, bank, creditCard }

enum TransactionKind { expense, income, transfer, creditCardPayment, reversal }

enum TransactionVerification { provisional, userConfirmed, verified, rejected }

enum TransactionSourceKind { manual, androidNotification, csv, bankApi }

/// Represents a single category slice of a multi-category Split Transaction
/// (e.g., 1 supermarket payment of 500,000 VND split into 320,000 VND "Ăn uống"
/// + 180,000 VND "Việc nhà & Gia dụng").
class TransactionSplitLine extends Equatable {
  final String categoryName;
  final int amountMinor;
  final String? note;

  const TransactionSplitLine({
    required this.categoryName,
    required this.amountMinor,
    this.note,
  });

  @override
  List<Object?> get props => [categoryName, amountMinor, note];
}

class WalletEntity extends Equatable {
  final String id;
  final String ownerId;
  final String name;
  final WalletType type;
  final String? bankCode;
  final String? maskedAccount;
  final int balanceMinor;
  final bool isEstimatedBalance;
  final bool hasPendingWrites;

  const WalletEntity({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.type,
    this.bankCode,
    this.maskedAccount,
    required this.balanceMinor,
    this.isEstimatedBalance = true,
    this.hasPendingWrites = false,
  });

  @override
  List<Object?> get props => [
        id,
        ownerId,
        name,
        type,
        bankCode,
        maskedAccount,
        balanceMinor,
        isEstimatedBalance,
        hasPendingWrites,
      ];
}

class CategoryEntity extends Equatable {
  final String id;
  final String ownerId;
  final String name;
  final String direction; // 'debit' | 'credit'
  final String iconKey;

  const CategoryEntity({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.direction,
    required this.iconKey,
  });

  @override
  List<Object?> get props => [id, ownerId, name, direction, iconKey];
}

class TransactionEntity extends Equatable {
  final String id;
  final String ownerId;
  final String walletId;
  final String? targetWalletId;
  final String? categoryId;
  final String categoryName;
  final TransactionKind kind;
  final String direction; // 'debit' | 'credit'
  final int amountMinor;
  final String currencyCode;
  final String merchant;
  final String? note;
  final DateTime occurredAt;
  final String monthKey;
  final TransactionSourceKind sourceKind;
  final TransactionVerification verification;
  final String crossSourceFingerprint;
  final String? reversalOfId;
  final String? reversedById;
  final bool isVehicleMaintenanceHint;
  final List<TransactionSplitLine> splitLines;
  final bool hasPendingWrites;

  const TransactionEntity({
    required this.id,
    required this.ownerId,
    required this.walletId,
    this.targetWalletId,
    this.categoryId,
    required this.categoryName,
    required this.kind,
    required this.direction,
    required this.amountMinor,
    this.currencyCode = 'VND',
    required this.merchant,
    this.note,
    required this.occurredAt,
    required this.monthKey,
    required this.sourceKind,
    required this.verification,
    required this.crossSourceFingerprint,
    this.reversalOfId,
    this.reversedById,
    this.isVehicleMaintenanceHint = false,
    this.splitLines = const [],
    this.hasPendingWrites = false,
  });

  bool get isConfirmedInLedger =>
      verification == TransactionVerification.userConfirmed ||
      verification == TransactionVerification.verified;

  bool get isReversed => reversedById != null && reversedById!.isNotEmpty;

  bool get isSplitTransaction => splitLines.length > 1;

  @override
  List<Object?> get props => [
        id,
        ownerId,
        walletId,
        targetWalletId,
        categoryId,
        categoryName,
        kind,
        direction,
        amountMinor,
        currencyCode,
        merchant,
        note,
        occurredAt,
        monthKey,
        sourceKind,
        verification,
        crossSourceFingerprint,
        reversalOfId,
        reversedById,
        isVehicleMaintenanceHint,
        splitLines,
        hasPendingWrites,
      ];
}

class CategorySpendShare extends Equatable {
  final String categoryName;
  final int amountMinor;
  final double sharePct;

  const CategorySpendShare({
    required this.categoryName,
    required this.amountMinor,
    required this.sharePct,
  });

  @override
  List<Object?> get props => [categoryName, amountMinor, sharePct];
}

class FinanceOverviewSummary extends Equatable {
  final int netWorthMinor;
  final int monthlyIncomeMinor;
  final int monthlyExpenseMinor;
  final int monthlyInternalTransferMinor;
  final int provisionalCount;
  final int verifiedCount;
  final int userConfirmedCount;
  final Map<String, int> expenseByCategory;

  const FinanceOverviewSummary({
    required this.netWorthMinor,
    required this.monthlyIncomeMinor,
    required this.monthlyExpenseMinor,
    required this.monthlyInternalTransferMinor,
    required this.provisionalCount,
    this.verifiedCount = 0,
    this.userConfirmedCount = 0,
    required this.expenseByCategory,
  });

  int get netCashFlowMinor => monthlyIncomeMinor - monthlyExpenseMinor;

  /// Net personal savings rate (%) when income > 0.
  double get savingsRatePct {
    if (monthlyIncomeMinor <= 0) return 0.0;
    final net = monthlyIncomeMinor - monthlyExpenseMinor;
    return (net * 100.0) / monthlyIncomeMinor;
  }

  /// Average daily burn rate over a standard 30-day cycle (exact integer VND).
  int get averageDailyExpenseMinor => monthlyExpenseMinor ~/ 30;

  List<CategorySpendShare> get sortedCategoryShares {
    if (expenseByCategory.isEmpty || monthlyExpenseMinor <= 0) {
      return const [];
    }
    final entries = expenseByCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries
        .map(
          (e) => CategorySpendShare(
            categoryName: e.key,
            amountMinor: e.value,
            sharePct: (e.value * 100.0) / monthlyExpenseMinor,
          ),
        )
        .toList(growable: false);
  }

  /// Pure domain accounting calculation:
  /// - Internal transfers and credit card payoffs NEVER inflate expense or income totals.
  /// - Provisional or rejected signals are excluded until confirmed.
  /// - Reversed transactions are excluded (netted out by immutable reversal).
  /// - Multi-category Split Transactions distribute exact amounts into each sub-category.
  factory FinanceOverviewSummary.compute({
    required List<WalletEntity> wallets,
    required List<TransactionEntity> transactions,
  }) {
    final netWorth = wallets.fold<int>(0, (sum, w) => sum + w.balanceMinor);
    var income = 0;
    var expense = 0;
    var internalTransfers = 0;
    var provisionalCount = 0;
    var verifiedCount = 0;
    var userConfirmedCount = 0;
    final breakdown = <String, int>{};

    for (final tx in transactions) {
      if (tx.verification == TransactionVerification.provisional) {
        provisionalCount += 1;
        continue;
      }
      if (!tx.isConfirmedInLedger || tx.isReversed) {
        continue;
      }

      if (tx.verification == TransactionVerification.verified) {
        verifiedCount += 1;
      } else if (tx.verification == TransactionVerification.userConfirmed) {
        userConfirmedCount += 1;
      }

      switch (tx.kind) {
        case TransactionKind.expense:
          expense += tx.amountMinor;
          if (tx.splitLines.isNotEmpty) {
            for (final line in tx.splitLines) {
              breakdown[line.categoryName] =
                  (breakdown[line.categoryName] ?? 0) + line.amountMinor;
            }
          } else {
            breakdown[tx.categoryName] = (breakdown[tx.categoryName] ?? 0) + tx.amountMinor;
          }
        case TransactionKind.income:
          income += tx.amountMinor;
        case TransactionKind.transfer:
        case TransactionKind.creditCardPayment:
          internalTransfers += tx.amountMinor;
        case TransactionKind.reversal:
          // Compensating entry paired with `reversedById` on original transaction
          break;
      }
    }

    return FinanceOverviewSummary(
      netWorthMinor: netWorth,
      monthlyIncomeMinor: income,
      monthlyExpenseMinor: expense,
      monthlyInternalTransferMinor: internalTransfers,
      provisionalCount: provisionalCount,
      verifiedCount: verifiedCount,
      userConfirmedCount: userConfirmedCount,
      expenseByCategory: Map.unmodifiable(breakdown),
    );
  }

  @override
  List<Object?> get props => [
        netWorthMinor,
        monthlyIncomeMinor,
        monthlyExpenseMinor,
        monthlyInternalTransferMinor,
        provisionalCount,
        verifiedCount,
        userConfirmedCount,
        expenseByCategory,
      ];
}

enum AllocationPreset {
  personal503020,
  family602020,
  roommates552025,
}

class AllocationBucketItem extends Equatable {
  final String categoryId;
  final String categoryName;
  final String groupLabel; // 'Thiết yếu' | 'Linh hoạt & Đối ngoại' | 'Tiết kiệm & Dự phòng'
  final int weightPct;
  final int amountMinor;
  final bool isSavingsFund;

  const AllocationBucketItem({
    required this.categoryId,
    required this.categoryName,
    required this.groupLabel,
    required this.weightPct,
    required this.amountMinor,
    this.isSavingsFund = false,
  });

  @override
  List<Object?> get props => [
        categoryId,
        categoryName,
        groupLabel,
        weightPct,
        amountMinor,
        isSavingsFund,
      ];
}

class IncomeAllocationPlan extends Equatable {
  final AllocationPreset preset;
  final int totalIncomeMinor;
  final List<AllocationBucketItem> buckets;

  const IncomeAllocationPlan({
    required this.preset,
    required this.totalIncomeMinor,
    required this.buckets,
  });

  int get allocatedTotalMinor => buckets.fold<int>(0, (sum, b) => sum + b.amountMinor);

  @override
  List<Object?> get props => [preset, totalIncomeMinor, buckets];
}

/// Pure Domain Income & Expense Allocation Engine using Hamilton's Largest Remainder Method
/// so `sum(buckets.amountMinor) == totalIncomeMinor` with ZERO VND rounding discrepancy.
abstract final class IncomeAllocationEngine {
  static String presetLabel(AllocationPreset preset) {
    return switch (preset) {
      AllocationPreset.personal503020 => 'Cá nhân Cân bằng (50/30/20)',
      AllocationPreset.family602020 => 'Hộ Gia đình & Tổ ấm (60/20/20)',
      AllocationPreset.roommates552025 => 'Ở ghép / Hội nhóm Tiết kiệm (55/20/25)',
    };
  }

  static IncomeAllocationPlan allocate({
    required int totalIncomeMinor,
    required AllocationPreset preset,
  }) {
    if (totalIncomeMinor <= 0) {
      return IncomeAllocationPlan(
        preset: preset,
        totalIncomeMinor: 0,
        buckets: const [],
      );
    }

    final specs = switch (preset) {
      AllocationPreset.personal503020 => const [
          ('cat_food', 'Ăn uống', 'Thiết yếu (50%)', 20, false),
          ('cat_housing', 'Nhà cửa & Thuê nhà', 'Thiết yếu (50%)', 15, false),
          ('cat_utilities', 'Điện/Nước/Internet', 'Thiết yếu (50%)', 5, false),
          ('cat_housework', 'Việc nhà & Gia dụng', 'Thiết yếu (50%)', 5, false),
          ('cat_vehicle', 'Xe cộ & Di chuyển', 'Thiết yếu (50%)', 5, false),
          ('cat_shopping', 'Chợ & Mua sắm', 'Cá nhân & Giải trí (30%)', 15, false),
          ('cat_entertainment', 'Giải trí & Đăng ký', 'Cá nhân & Giải trí (30%)', 10, false),
          ('cat_health', 'Sức khỏe & Giáo dục', 'Cá nhân & Giải trí (30%)', 5, false),
          ('fund_emergency', 'Quỹ Tiết kiệm & Dự phòng', 'Tích lũy (20%)', 20, true),
        ],
      AllocationPreset.family602020 => const [
          ('cat_food', 'Ăn uống', 'Sinh hoạt Gia đình (60%)', 22, false),
          ('cat_shopping', 'Chợ & Mua sắm', 'Sinh hoạt Gia đình (60%)', 10, false),
          ('cat_housework', 'Việc nhà & Gia dụng', 'Sinh hoạt Gia đình (60%)', 8, false),
          ('cat_utilities', 'Điện/Nước/Internet', 'Sinh hoạt Gia đình (60%)', 8, false),
          ('cat_health', 'Sức khỏe & Giáo dục', 'Sinh hoạt Gia đình (60%)', 12, false),
          ('cat_family_social', 'Hiếu hỉ & Đối ngoại', 'Đối nội ngoại & Chung (20%)', 12, false),
          ('cat_vehicle', 'Xe cộ & Di chuyển', 'Đối nội ngoại & Chung (20%)', 8, false),
          ('fund_family', 'Quỹ Tích lũy Gia đình', 'Tích lũy (20%)', 20, true),
        ],
      AllocationPreset.roommates552025 => const [
          ('cat_housing', 'Nhà cửa & Thuê nhà', 'Chi phí Ở ghép & Sinh hoạt (55%)', 20, false),
          ('cat_food', 'Ăn uống', 'Chi phí Ở ghép & Sinh hoạt (55%)', 18, false),
          ('cat_utilities', 'Điện/Nước/Internet', 'Chi phí Ở ghép & Sinh hoạt (55%)', 7, false),
          ('cat_housework', 'Việc nhà & Gia dụng', 'Chi phí Ở ghép & Sinh hoạt (55%)', 5, false),
          ('cat_vehicle', 'Xe cộ & Di chuyển', 'Chi phí Ở ghép & Sinh hoạt (55%)', 5, false),
          ('cat_entertainment', 'Giải trí & Đăng ký', 'Học tập & Giải trí (20%)', 10, false),
          ('cat_health', 'Sức khỏe & Giáo dục', 'Học tập & Giải trí (20%)', 10, false),
          ('fund_goal', 'Quỹ Mục tiêu Cá nhân', 'Tiết kiệm (25%)', 25, true),
        ],
    };

    final totalWeight = specs.fold<int>(0, (s, item) => s + item.$4);
    final floors = List<int>.filled(specs.length, 0);
    final remainders = <({int index, int rem})>[];
    var floorSum = 0;

    for (var i = 0; i < specs.length; i++) {
      final numerator = totalIncomeMinor * specs[i].$4;
      floors[i] = numerator ~/ totalWeight;
      floorSum += floors[i];
      remainders.add((index: i, rem: numerator % totalWeight));
    }

    final leftover = totalIncomeMinor - floorSum;
    remainders.sort((a, b) {
      final cmp = b.rem.compareTo(a.rem);
      return cmp != 0 ? cmp : a.index.compareTo(b.index);
    });
    for (var k = 0; k < leftover; k++) {
      floors[remainders[k].index] += 1;
    }

    final buckets = <AllocationBucketItem>[];
    for (var i = 0; i < specs.length; i++) {
      buckets.add(
        AllocationBucketItem(
          categoryId: specs[i].$1,
          categoryName: specs[i].$2,
          groupLabel: specs[i].$3,
          weightPct: specs[i].$4,
          amountMinor: floors[i],
          isSavingsFund: specs[i].$5,
        ),
      );
    }

    return IncomeAllocationPlan(
      preset: preset,
      totalIncomeMinor: totalIncomeMinor,
      buckets: List.unmodifiable(buckets),
    );
  }
}
