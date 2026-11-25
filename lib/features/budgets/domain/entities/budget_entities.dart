import 'package:equatable/equatable.dart';

enum FundScope { personal, family }

/// Full 9-state lifecycle for family & personal fund expense requests (`AUD-006`).
enum FundExpenseStatus {
  draft,
  pendingApproval,
  approved,
  executed,
  reconciled,
  rejected,
  cancelled,
  disputed,
  reversed;

  /// Backward-compatible alias for legacy references to `FundExpenseStatus.pending`.
  static const FundExpenseStatus pending = pendingApproval;

  bool get isTerminal =>
      this == reconciled ||
      this == rejected ||
      this == cancelled ||
      this == reversed;

  bool get affectsBalance =>
      this == executed || this == reconciled || this == disputed;

  String get displayLabelVi => switch (this) {
    FundExpenseStatus.draft => 'Nháp',
    FundExpenseStatus.pendingApproval => 'Chờ duyệt',
    FundExpenseStatus.approved => 'Đã duyệt',
    FundExpenseStatus.executed => 'Đã giải ngân',
    FundExpenseStatus.reconciled => 'Đã đối soát',
    FundExpenseStatus.rejected => 'Từ chối',
    FundExpenseStatus.cancelled => 'Đã hủy',
    FundExpenseStatus.disputed => 'Khiếu nại',
    FundExpenseStatus.reversed => 'Đã hoàn tác',
  };

  String toWireValue() => switch (this) {
    FundExpenseStatus.draft => 'draft',
    FundExpenseStatus.pendingApproval => 'pending_approval',
    FundExpenseStatus.approved => 'approved',
    FundExpenseStatus.executed => 'executed',
    FundExpenseStatus.reconciled => 'reconciled',
    FundExpenseStatus.rejected => 'rejected',
    FundExpenseStatus.cancelled => 'cancelled',
    FundExpenseStatus.disputed => 'disputed',
    FundExpenseStatus.reversed => 'reversed',
  };

  static FundExpenseStatus fromWireValue(String? raw) => switch (raw) {
    'draft' => FundExpenseStatus.draft,
    'pending_approval' || 'pending' => FundExpenseStatus.pendingApproval,
    'approved' => FundExpenseStatus.approved,
    'executed' => FundExpenseStatus.executed,
    'reconciled' => FundExpenseStatus.reconciled,
    'rejected' => FundExpenseStatus.rejected,
    'cancelled' => FundExpenseStatus.cancelled,
    'disputed' => FundExpenseStatus.disputed,
    'reversed' => FundExpenseStatus.reversed,
    _ => FundExpenseStatus.pendingApproval,
  };
}

/// Pure Dart state-machine & RBAC separation-of-duties validator for fund expenses (`AUD-006`).
abstract final class FundExpenseStateMachine {
  static const Map<FundExpenseStatus, Set<FundExpenseStatus>> allowedTransitions = {
    FundExpenseStatus.draft: {
      FundExpenseStatus.draft,
      FundExpenseStatus.pendingApproval,
      FundExpenseStatus.cancelled,
    },
    FundExpenseStatus.pendingApproval: {
      FundExpenseStatus.approved,
      FundExpenseStatus.rejected,
      FundExpenseStatus.cancelled,
    },
    FundExpenseStatus.approved: {
      FundExpenseStatus.executed,
      FundExpenseStatus.reversed,
    },
    FundExpenseStatus.executed: {
      FundExpenseStatus.reconciled,
      FundExpenseStatus.disputed,
      FundExpenseStatus.reversed,
    },
    FundExpenseStatus.disputed: {
      FundExpenseStatus.reversed,
    },
    FundExpenseStatus.reconciled: <FundExpenseStatus>{},
    FundExpenseStatus.rejected: <FundExpenseStatus>{},
    FundExpenseStatus.cancelled: <FundExpenseStatus>{},
    FundExpenseStatus.reversed: <FundExpenseStatus>{},
  };

  static bool canTransition(FundExpenseStatus from, FundExpenseStatus to) =>
      allowedTransitions[from]?.contains(to) ?? false;

  static bool canUserDecide({
    required bool isManager,
    required String actorUserId,
    required String requesterId,
    required int memberCount,
  }) {
    if (!isManager || actorUserId.trim().isEmpty) return false;
    return actorUserId != requesterId || memberCount <= 1;
  }

  static bool canUserCancel({
    required FundExpenseStatus currentStatus,
    required String actorUserId,
    required String requesterId,
  }) {
    if (actorUserId.trim().isEmpty || actorUserId != requesterId) return false;
    return currentStatus == FundExpenseStatus.draft ||
        currentStatus == FundExpenseStatus.pendingApproval;
  }

  static bool canUserSubmitDraft({
    required FundExpenseStatus currentStatus,
    required String actorUserId,
    required String requesterId,
  }) {
    if (actorUserId.trim().isEmpty || actorUserId != requesterId) return false;
    return currentStatus == FundExpenseStatus.draft;
  }

  static bool doesReverseRestoreBalance(FundExpenseStatus previousStatus) =>
      previousStatus == FundExpenseStatus.executed ||
      previousStatus == FundExpenseStatus.disputed;
}

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
  final String? fundId;
  final String contributorId;
  final String contributorName;
  final int amountMinor;
  final String? note;
  final String? operationId;
  final String? sourceWalletId;
  final DateTime createdAt;

  const FundContributionEntity({
    required this.id,
    this.fundId,
    required this.contributorId,
    required this.contributorName,
    required this.amountMinor,
    this.note,
    this.operationId,
    this.sourceWalletId,
    required this.createdAt,
  });

  @override
  List<Object?> get props => [
    id,
    fundId,
    contributorId,
    contributorName,
    amountMinor,
    note,
    operationId,
    sourceWalletId,
    createdAt,
  ];
}

class FundExpenseRequestEntity extends Equatable {
  final String id;
  final String? fundId;
  final String requesterId;
  final String requesterName;
  final String title;
  final int amountMinor;
  final FundExpenseStatus status;
  final String? operationId;
  final String? decidedBy;
  final DateTime? decidedAt;
  final String? executedBy;
  final DateTime? executedAt;
  final String? reconciledTxId;
  final String? disputeReason;
  final String? disputedBy;
  final DateTime? disputedAt;
  final String? reversalReason;
  final DateTime createdAt;

  const FundExpenseRequestEntity({
    required this.id,
    this.fundId,
    required this.requesterId,
    required this.requesterName,
    required this.title,
    required this.amountMinor,
    required this.status,
    this.operationId,
    this.decidedBy,
    this.decidedAt,
    this.executedBy,
    this.executedAt,
    this.reconciledTxId,
    this.disputeReason,
    this.disputedBy,
    this.disputedAt,
    this.reversalReason,
    required this.createdAt,
  });

  @override
  List<Object?> get props => [
    id,
    fundId,
    requesterId,
    requesterName,
    title,
    amountMinor,
    status,
    operationId,
    decidedBy,
    decidedAt,
    executedBy,
    executedAt,
    reconciledTxId,
    disputeReason,
    disputedBy,
    disputedAt,
    reversalReason,
    createdAt,
  ];
}

/// Immutable append-only audit entry for fund balance mutations (`fund_audits`).
class FundAuditEntry extends Equatable {
  final String id;
  final String fundId;
  final String actorId;
  final String eventType;
  final String eventId;
  final int previousBalanceMinor;
  final int deltaMinor;
  final int newBalanceMinor;
  final DateTime createdAt;

  const FundAuditEntry({
    required this.id,
    required this.fundId,
    required this.actorId,
    required this.eventType,
    required this.eventId,
    required this.previousBalanceMinor,
    required this.deltaMinor,
    required this.newBalanceMinor,
    required this.createdAt,
  });

  bool get satisfiesBalanceInvariant =>
      previousBalanceMinor + deltaMinor == newBalanceMinor;

  @override
  List<Object?> get props => [
    id,
    fundId,
    actorId,
    eventType,
    eventId,
    previousBalanceMinor,
    deltaMinor,
    newBalanceMinor,
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
  final int totalContributedMinor;
  final int totalExecutedMinor;
  final List<FundContributionEntity> recentContributions;
  final List<FundExpenseRequestEntity> expenseRequests;
  final List<FundAuditEntry> auditTrail;

  const FundEntity({
    required this.id,
    required this.scope,
    this.ownerId,
    this.familyId,
    required this.name,
    required this.targetAmountMinor,
    required this.balanceMinor,
    this.totalContributedMinor = 0,
    this.totalExecutedMinor = 0,
    this.recentContributions = const [],
    this.expenseRequests = const [],
    this.auditTrail = const [],
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
    totalContributedMinor,
    totalExecutedMinor,
    recentContributions,
    expenseRequests,
    auditTrail,
  ];
}
