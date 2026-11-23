import 'package:equatable/equatable.dart';

enum FundScope { personal, family }

enum FundExpenseStatus { pending, approved, rejected }

class BudgetEntity extends Equatable {
  final String id;
  final String ownerId;
  final String categoryId;
  final String categoryName;
  final String monthKey;
  final int limitMinor;
  final int spentMinor;
  final int alertThresholdPct;

  const BudgetEntity({
    required this.id,
    required this.ownerId,
    required this.categoryId,
    required this.categoryName,
    required this.monthKey,
    required this.limitMinor,
    this.spentMinor = 0,
    this.alertThresholdPct = 80,
  });

  int get remainingMinor => limitMinor - spentMinor;

  int get percentUsed =>
      limitMinor > 0 ? ((spentMinor * 100) / limitMinor).round() : 0;

  bool get isExceeded => spentMinor > limitMinor;

  bool get isWarning => !isExceeded && percentUsed >= alertThresholdPct;

  BudgetEntity withSpent(int computedSpentMinor) {
    return BudgetEntity(
      id: id,
      ownerId: ownerId,
      categoryId: categoryId,
      categoryName: categoryName,
      monthKey: monthKey,
      limitMinor: limitMinor,
      spentMinor: computedSpentMinor,
      alertThresholdPct: alertThresholdPct,
    );
  }

  @override
  List<Object?> get props => [
    id,
    ownerId,
    categoryId,
    categoryName,
    monthKey,
    limitMinor,
    spentMinor,
    alertThresholdPct,
  ];
}

class FundContributionEntity extends Equatable {
  final String id;
  final String contributorId;
  final String contributorName;
  final int amountMinor;
  final String? note;
  final DateTime createdAt;

  const FundContributionEntity({
    required this.id,
    required this.contributorId,
    required this.contributorName,
    required this.amountMinor,
    this.note,
    required this.createdAt,
  });

  @override
  List<Object?> get props => [
    id,
    contributorId,
    contributorName,
    amountMinor,
    note,
    createdAt,
  ];
}

class FundExpenseRequestEntity extends Equatable {
  final String id;
  final String requesterId;
  final String requesterName;
  final String title;
  final int amountMinor;
  final FundExpenseStatus status;
  final DateTime createdAt;

  const FundExpenseRequestEntity({
    required this.id,
    required this.requesterId,
    required this.requesterName,
    required this.title,
    required this.amountMinor,
    required this.status,
    required this.createdAt,
  });

  @override
  List<Object?> get props => [
    id,
    requesterId,
    requesterName,
    title,
    amountMinor,
    status,
    createdAt,
  ];
}

/// Virtual fund ledger (accounting earmark — never claims to custody real money).
class FundEntity extends Equatable {
  final String id;
  final FundScope scope;
  final String? ownerId;
  final String? familyId;
  final String name;
  final int targetAmountMinor;
  final int balanceMinor;
  final List<FundContributionEntity> recentContributions;
  final List<FundExpenseRequestEntity> expenseRequests;

  const FundEntity({
    required this.id,
    required this.scope,
    this.ownerId,
    this.familyId,
    required this.name,
    required this.targetAmountMinor,
    required this.balanceMinor,
    this.recentContributions = const [],
    this.expenseRequests = const [],
  });

  int get progressPct => targetAmountMinor > 0
      ? ((balanceMinor * 100) / targetAmountMinor).clamp(0, 100).round()
      : 0;

  @override
  List<Object?> get props => [
    id,
    scope,
    ownerId,
    familyId,
    name,
    targetAmountMinor,
    balanceMinor,
    recentContributions,
    expenseRequests,
  ];
}
