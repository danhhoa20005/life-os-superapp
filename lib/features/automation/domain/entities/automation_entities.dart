import 'package:equatable/equatable.dart';

enum AutomationTriggerKind {
  incomeSalaryReceived('income_salary', 'Nhận lương / Thu nhập lớn'),
  fuelExpenseLogged('fuel_logged', 'Đổ xăng / Sạc điện xe'),
  oilChangeLogged('oil_change', 'Thay dầu / Bảo dưỡng xe'),
  utilityBillPaid('utility_paid', 'Thanh toán điện / nước / internet'),
  appliancePurchased('appliance_bought', 'Mua đồ điện tử / gia dụng'),
  groupExpenseDetected('group_expense', 'Phát sinh chi phí nhóm / ăn chung'),
  budgetNearLimit('budget_near_limit', 'Gần vượt hạn mức ngân sách'),
  documentExpiringSoon('document_expiring', 'Giấy tờ sắp đến hạn'),
  calendarEventStartingSoon('event_starting', 'Sự kiện lịch sắp bắt đầu');

  final String code;
  final String labelVi;
  const AutomationTriggerKind(this.code, this.labelVi);
}

enum AutomationActionKind {
  suggestSalaryBudgetAllocation(
    'allocate_budget',
    'Đề xuất phân bổ ngân sách tháng',
  ),
  logVehicleFuelCost('log_vehicle_fuel', 'Gắn chi phí nhiên liệu vào hồ sơ xe'),
  updateVehicleMaintenanceCycle(
    'update_vehicle_maint',
    'Cập nhật mốc ODO bảo dưỡng xe',
  ),
  markRecurringBillPaid('update_recurring_bill', 'Cập nhật kỳ hóa đơn định kỳ'),
  promptSaveWarranty('save_warranty', 'Đề xuất lưu phiếu bảo hành thiết bị'),
  promptSplitGroupBill('split_group_bill', 'Đề xuất chia tiền nhóm'),
  emitSpendingAlert('spending_alert', 'Phát cảnh báo kiểm soát chi tiêu'),
  createExpiryReminder('create_doc_reminder', 'Tạo lời nhắc gia hạn giấy tờ'),
  showUpcomingEventAlert(
    'event_alert',
    'Hiển thị nhắc nhở sự kiện sắp diễn ra',
  );

  final String code;
  final String labelVi;
  const AutomationActionKind(this.code, this.labelVi);
}

enum AutomationAuditStatus {
  suggested,
  executed,
  skippedDuplicate,
  blockedLoopGuard,
  blockedPermission,
  undone,
  failed,
}

class AutomationDomainEvent extends Equatable {
  final String eventId;
  final AutomationTriggerKind triggerKind;
  final String actorUserId;
  final DateTime occurredAt;
  final int amountMinor;
  final String title;
  final String? categoryName;
  final String? vehicleId;
  final String? familyId;
  final int budgetUsedPct;
  final int daysUntilExpiry;
  final int minutesUntilStart;
  final bool originatedFromAutomation;

  const AutomationDomainEvent({
    required this.eventId,
    required this.triggerKind,
    required this.actorUserId,
    required this.occurredAt,
    this.amountMinor = 0,
    required this.title,
    this.categoryName,
    this.vehicleId,
    this.familyId,
    this.budgetUsedPct = 0,
    this.daysUntilExpiry = 999,
    this.minutesUntilStart = 999,
    this.originatedFromAutomation = false,
  });

  @override
  List<Object?> get props => [
    eventId,
    triggerKind,
    actorUserId,
    occurredAt,
    amountMinor,
    title,
    categoryName,
    vehicleId,
    familyId,
    budgetUsedPct,
    daysUntilExpiry,
    minutesUntilStart,
    originatedFromAutomation,
  ];
}

class AutomationRuleEntity extends Equatable {
  final String id;
  final String ownerId;
  final String nameVi;
  final String descriptionVi;
  final AutomationTriggerKind triggerKind;
  final AutomationActionKind actionKind;
  final bool enabled;
  final bool requiresUserConfirmation;
  final int minAmountMinor;
  final int thresholdPct;
  final int leadDays;
  final String? requiredFamilyId;

  const AutomationRuleEntity({
    required this.id,
    required this.ownerId,
    required this.nameVi,
    required this.descriptionVi,
    required this.triggerKind,
    required this.actionKind,
    this.enabled = true,
    this.requiresUserConfirmation = true,
    this.minAmountMinor = 0,
    this.thresholdPct = 80,
    this.leadDays = 30,
    this.requiredFamilyId,
  });

  AutomationRuleEntity copyWith({
    bool? enabled,
    bool? requiresUserConfirmation,
    int? minAmountMinor,
    int? thresholdPct,
    int? leadDays,
  }) {
    return AutomationRuleEntity(
      id: id,
      ownerId: ownerId,
      nameVi: nameVi,
      descriptionVi: descriptionVi,
      triggerKind: triggerKind,
      actionKind: actionKind,
      enabled: enabled ?? this.enabled,
      requiresUserConfirmation:
          requiresUserConfirmation ?? this.requiresUserConfirmation,
      minAmountMinor: minAmountMinor ?? this.minAmountMinor,
      thresholdPct: thresholdPct ?? this.thresholdPct,
      leadDays: leadDays ?? this.leadDays,
      requiredFamilyId: requiredFamilyId,
    );
  }

  @override
  List<Object?> get props => [
    id,
    ownerId,
    nameVi,
    descriptionVi,
    triggerKind,
    actionKind,
    enabled,
    requiresUserConfirmation,
    minAmountMinor,
    thresholdPct,
    leadDays,
    requiredFamilyId,
  ];
}

class AutomationActionSuggestion extends Equatable {
  final String suggestionId;
  final String idempotencyKey;
  final String ruleId;
  final String sourceEventId;
  final AutomationActionKind actionKind;
  final String headlineVi;
  final String detailVi;
  final String targetRoute;
  final Map<String, Object?> payload;
  final bool supportsUndo;
  final DateTime createdAt;

  const AutomationActionSuggestion({
    required this.suggestionId,
    required this.idempotencyKey,
    required this.ruleId,
    required this.sourceEventId,
    required this.actionKind,
    required this.headlineVi,
    required this.detailVi,
    required this.targetRoute,
    this.payload = const <String, Object?>{},
    this.supportsUndo = true,
    required this.createdAt,
  });

  @override
  List<Object?> get props => [
    suggestionId,
    idempotencyKey,
    ruleId,
    sourceEventId,
    actionKind,
    headlineVi,
    detailVi,
    targetRoute,
    payload,
    supportsUndo,
    createdAt,
  ];
}

class AutomationAuditEntry extends Equatable {
  final String auditId;
  final String idempotencyKey;
  final String ruleId;
  final String sourceEventId;
  final String actorUserId;
  final AutomationActionKind actionKind;
  final AutomationAuditStatus status;
  final String summaryVi;
  final DateTime timestamp;
  final String? undoReferenceId;

  const AutomationAuditEntry({
    required this.auditId,
    required this.idempotencyKey,
    required this.ruleId,
    required this.sourceEventId,
    required this.actorUserId,
    required this.actionKind,
    required this.status,
    required this.summaryVi,
    required this.timestamp,
    this.undoReferenceId,
  });

  AutomationAuditEntry markUndone(DateTime undoneAt) {
    return AutomationAuditEntry(
      auditId: auditId,
      idempotencyKey: idempotencyKey,
      ruleId: ruleId,
      sourceEventId: sourceEventId,
      actorUserId: actorUserId,
      actionKind: actionKind,
      status: AutomationAuditStatus.undone,
      summaryVi: '$summaryVi (Đã hoàn tác)',
      timestamp: undoneAt,
      undoReferenceId: undoReferenceId,
    );
  }

  @override
  List<Object?> get props => [
    auditId,
    idempotencyKey,
    ruleId,
    sourceEventId,
    actorUserId,
    actionKind,
    status,
    summaryVi,
    timestamp,
    undoReferenceId,
  ];
}
