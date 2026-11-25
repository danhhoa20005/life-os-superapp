import '../entities/automation_entities.dart';

class AutomationEvaluationBatch {
  final List<AutomationActionSuggestion> suggestions;
  final List<AutomationAuditEntry> audits;

  const AutomationEvaluationBatch({
    required this.suggestions,
    required this.audits,
  });
}

/// Event-driven cross-module Smart Automation Engine (Section 20).
///
/// Pipeline:
/// `DomainEvent -> RuleMatcher -> ConditionValidator -> PermissionCheck -> ActionSuggestion -> Audit`
///
/// Guarantees:
/// 1. **Zero infinite automation loops**: Any event with `originatedFromAutomation == true` is blocked immediately.
/// 2. **Strict idempotency**: `(ruleId, sourceEventId)` produces a deterministic `idempotencyKey` that cannot fire twice.
/// 3. **RBAC permission boundary**: Rules targeting a family space verify `allowedFamilyIds` before suggesting actions.
/// 4. **Confirmation-first**: Financial/data-mutating suggestions always require explicit user confirmation and support Undo.
abstract final class SmartAutomationEngine {
  static List<AutomationRuleEntity> defaultRulesForUser(String userId) {
    return <AutomationRuleEntity>[
      AutomationRuleEntity(
        id: 'auto_salary_budget',
        ownerId: userId,
        nameVi: 'Nhận lương -> Đề xuất phân bổ ngân sách',
        descriptionVi:
            'Khi ghi nhận khoản lương từ 5.000.000 ₫, gợi ý chia vào ngân sách tháng hoặc 6 chiếc lọ.',
        triggerKind: AutomationTriggerKind.incomeSalaryReceived,
        actionKind: AutomationActionKind.suggestSalaryBudgetAllocation,
        minAmountMinor: 5000000,
      ),
      AutomationRuleEntity(
        id: 'auto_fuel_vehicle',
        ownerId: userId,
        nameVi: 'Đổ xăng -> Ghi nhật ký nhiên liệu xe',
        descriptionVi:
            'Khi chi tiền xăng/trạm sạc, gợi ý gắn vào chiếc xe đang sử dụng để tính chi phí ₫/km.',
        triggerKind: AutomationTriggerKind.fuelExpenseLogged,
        actionKind: AutomationActionKind.logVehicleFuelCost,
        minAmountMinor: 20000,
      ),
      AutomationRuleEntity(
        id: 'auto_oil_maintenance',
        ownerId: userId,
        nameVi: 'Thay dầu -> Cập nhật chu kỳ bảo dưỡng xe',
        descriptionVi:
            'Khi thanh toán thay nhớt/bảo dưỡng, gợi ý cập nhật mốc ODO phụ tùng tương ứng.',
        triggerKind: AutomationTriggerKind.oilChangeLogged,
        actionKind: AutomationActionKind.updateVehicleMaintenanceCycle,
        minAmountMinor: 50000,
      ),
      AutomationRuleEntity(
        id: 'auto_utility_bill',
        ownerId: userId,
        nameVi: 'Thanh toán điện/nước -> Gạch hóa đơn định kỳ',
        descriptionVi:
            'Tự động gợi ý đánh dấu đã đóng hóa đơn điện, nước, internet của kỳ hiện tại.',
        triggerKind: AutomationTriggerKind.utilityBillPaid,
        actionKind: AutomationActionKind.markRecurringBillPaid,
        minAmountMinor: 30000,
      ),
      AutomationRuleEntity(
        id: 'auto_appliance_warranty',
        ownerId: userId,
        nameVi: 'Mua đồ điện tử/gia dụng -> Lưu bảo hành',
        descriptionVi:
            'Khi mua thiết bị từ 500.000 ₫, gợi ý lưu hạn bảo hành 12-24 tháng để nhắc trước khi hết hạn.',
        triggerKind: AutomationTriggerKind.appliancePurchased,
        actionKind: AutomationActionKind.promptSaveWarranty,
        minAmountMinor: 500000,
      ),
      AutomationRuleEntity(
        id: 'auto_group_split',
        ownerId: userId,
        nameVi: 'Chi phí nhóm -> Đề xuất chia hóa đơn',
        descriptionVi:
            'Khi phát sinh bữa ăn/chuyến đi chung, gợi ý mở bảng chia tiền nhanh cho thành viên.',
        triggerKind: AutomationTriggerKind.groupExpenseDetected,
        actionKind: AutomationActionKind.promptSplitGroupBill,
        minAmountMinor: 80000,
      ),
      AutomationRuleEntity(
        id: 'auto_budget_threshold',
        ownerId: userId,
        nameVi: 'Gần vượt ngân sách -> Cảnh báo chi tiêu',
        descriptionVi:
            'Cảnh báo ngay khi danh mục chạm ngưỡng 80% hạn mức tháng.',
        triggerKind: AutomationTriggerKind.budgetNearLimit,
        actionKind: AutomationActionKind.emitSpendingAlert,
        thresholdPct: 80,
      ),
      AutomationRuleEntity(
        id: 'auto_doc_expiry',
        ownerId: userId,
        nameVi: 'Giấy tờ sắp hết hạn -> Tạo lời nhắc gia hạn',
        descriptionVi:
            'Nhắc trước 30 ngày đối với CCCD, bằng lái, hộ chiếu, bảo hiểm xe và đăng kiểm.',
        triggerKind: AutomationTriggerKind.documentExpiringSoon,
        actionKind: AutomationActionKind.createExpiryReminder,
        leadDays: 30,
      ),
      AutomationRuleEntity(
        id: 'auto_event_upcoming',
        ownerId: userId,
        nameVi: 'Sự kiện sắp bắt đầu -> Hiển thị thông báo',
        descriptionVi:
            'Nhắc lịch họp và công việc quan trọng trước 15-30 phút.',
        triggerKind: AutomationTriggerKind.calendarEventStartingSoon,
        actionKind: AutomationActionKind.showUpcomingEventAlert,
      ),
    ];
  }

  static String buildIdempotencyKey(String ruleId, String sourceEventId) =>
      'idem_${ruleId}__$sourceEventId';

  static AutomationEvaluationBatch evaluate({
    required AutomationDomainEvent event,
    required List<AutomationRuleEntity> rules,
    required String activeUserId,
    Set<String> allowedFamilyIds = const <String>{},
    Set<String> processedIdempotencyKeys = const <String>{},
  }) {
    final suggestions = <AutomationActionSuggestion>[];
    final audits = <AutomationAuditEntry>[];

    // 1. Loop Guard: Never allow automation-generated actions to re-trigger rules!
    if (event.originatedFromAutomation) {
      audits.add(
        AutomationAuditEntry(
          auditId: 'aud_loop_${event.eventId}',
          idempotencyKey: 'loop_${event.eventId}',
          ruleId: 'loop_guard',
          sourceEventId: event.eventId,
          actorUserId: activeUserId,
          actionKind: AutomationActionKind.emitSpendingAlert,
          status: AutomationAuditStatus.blockedLoopGuard,
          summaryVi: 'Chặn vòng lặp tự động hóa cho sự kiện "${event.title}".',
          timestamp: event.occurredAt,
        ),
      );
      return AutomationEvaluationBatch(
        suggestions: suggestions,
        audits: audits,
      );
    }

    for (final rule in rules) {
      if (!rule.enabled) continue;
      if (rule.triggerKind != event.triggerKind) continue;

      final idemKey = buildIdempotencyKey(rule.id, event.eventId);

      // 2. Idempotency Guard
      if (processedIdempotencyKeys.contains(idemKey)) {
        audits.add(
          AutomationAuditEntry(
            auditId: 'aud_dup_$idemKey',
            idempotencyKey: idemKey,
            ruleId: rule.id,
            sourceEventId: event.eventId,
            actorUserId: activeUserId,
            actionKind: rule.actionKind,
            status: AutomationAuditStatus.skippedDuplicate,
            summaryVi: 'Bỏ qua thực thi trùng quy tắc "${rule.nameVi}".',
            timestamp: event.occurredAt,
          ),
        );
        continue;
      }

      // 3. Permission Check (Owner + Family RBAC)
      final targetFam = event.familyId ?? rule.requiredFamilyId;
      if (rule.ownerId != activeUserId ||
          event.actorUserId != activeUserId ||
          (targetFam != null &&
              targetFam.isNotEmpty &&
              !allowedFamilyIds.contains(targetFam))) {
        audits.add(
          AutomationAuditEntry(
            auditId: 'aud_perm_$idemKey',
            idempotencyKey: idemKey,
            ruleId: rule.id,
            sourceEventId: event.eventId,
            actorUserId: activeUserId,
            actionKind: rule.actionKind,
            status: AutomationAuditStatus.blockedPermission,
            summaryVi:
                'Từ chối quy tắc "${rule.nameVi}" do vượt phạm vi quyền truy cập.',
            timestamp: event.occurredAt,
          ),
        );
        continue;
      }

      // 4. Condition Validator
      if (!_matchesConditions(rule, event)) {
        continue;
      }

      // 5. Build Action Suggestion + Audit
      final suggestion = _buildSuggestion(rule, event, idemKey);
      suggestions.add(suggestion);
      audits.add(
        AutomationAuditEntry(
          auditId: 'aud_sug_$idemKey',
          idempotencyKey: idemKey,
          ruleId: rule.id,
          sourceEventId: event.eventId,
          actorUserId: activeUserId,
          actionKind: rule.actionKind,
          status: AutomationAuditStatus.suggested,
          summaryVi: suggestion.headlineVi,
          timestamp: event.occurredAt,
        ),
      );
    }

    return AutomationEvaluationBatch(suggestions: suggestions, audits: audits);
  }

  static bool _matchesConditions(
    AutomationRuleEntity rule,
    AutomationDomainEvent event,
  ) {
    if (rule.minAmountMinor > 0 && event.amountMinor < rule.minAmountMinor) {
      return false;
    }
    switch (rule.triggerKind) {
      case AutomationTriggerKind.budgetNearLimit:
        return event.budgetUsedPct >= rule.thresholdPct;
      case AutomationTriggerKind.documentExpiringSoon:
        return event.daysUntilExpiry >= 0 &&
            event.daysUntilExpiry <= rule.leadDays;
      case AutomationTriggerKind.calendarEventStartingSoon:
        return event.minutesUntilStart >= 0 && event.minutesUntilStart <= 60;
      default:
        return true;
    }
  }

  static AutomationActionSuggestion _buildSuggestion(
    AutomationRuleEntity rule,
    AutomationDomainEvent event,
    String idemKey,
  ) {
    final (headline, detail, route, supportsUndo) = switch (rule.actionKind) {
      AutomationActionKind.suggestSalaryBudgetAllocation => (
        'Phân bổ khoản thu "${event.title}" vào Ngân sách',
        'Áp dụng quy tắc 50/30/20 hoặc 6 Chiếc Lọ cho khoản thu vừa nhận.',
        '/wealth-tools?tab=fire',
        true,
      ),
      AutomationActionKind.logVehicleFuelCost => (
        'Gắn "${event.title}" vào Nhật ký Nhiên liệu Xe',
        'Cập nhật mức tiêu hao nhiên liệu và chi phí ₫/km của phương tiện.',
        '/assets',
        true,
      ),
      AutomationActionKind.updateVehicleMaintenanceCycle => (
        'Cập nhật mốc ODO bảo dưỡng cho "${event.title}"',
        'Đặt lại bộ đếm km thay dầu/phụ tùng để nhận nhắc nhở chính xác.',
        '/assets',
        true,
      ),
      AutomationActionKind.markRecurringBillPaid => (
        'Gạch nợ kỳ hóa đơn "${event.title}"',
        'Đánh dấu đã thanh toán và đẩy ngày đến hạn sang kỳ tiếp theo.',
        '/assets',
        true,
      ),
      AutomationActionKind.promptSaveWarranty => (
        'Lưu phiếu bảo hành cho "${event.title}"',
        'Theo dõi ngày hết hạn bảo hành trong mục Thuê bao & Bảo hành.',
        '/subscriptions-warranty',
        true,
      ),
      AutomationActionKind.promptSplitGroupBill => (
        'Chia hóa đơn "${event.title}" cho nhóm',
        'Mở nhanh bảng chia đều hoặc chia theo phần cho thành viên.',
        '/family',
        true,
      ),
      AutomationActionKind.emitSpendingAlert => (
        'Cảnh báo: "${event.title}" đạt ${event.budgetUsedPct}% ngân sách',
        'Kiểm tra hạn mức còn lại để giữ nhịp chi tiêu an toàn cuối tháng.',
        '/finance',
        false,
      ),
      AutomationActionKind.createExpiryReminder => (
        'Nhắc gia hạn "${event.title}" (còn ${event.daysUntilExpiry} ngày)',
        'Tạo lịch nhắc chuẩn bị hồ sơ gia hạn đúng hạn.',
        '/family-documents',
        true,
      ),
      AutomationActionKind.showUpcomingEventAlert => (
        'Sắp diễn ra sau ${event.minutesUntilStart} phút: "${event.title}"',
        'Mở chi tiết sự kiện và danh sách việc liên quan.',
        '/planning',
        false,
      ),
    };

    return AutomationActionSuggestion(
      suggestionId: 'sug_$idemKey',
      idempotencyKey: idemKey,
      ruleId: rule.id,
      sourceEventId: event.eventId,
      actionKind: rule.actionKind,
      headlineVi: headline,
      detailVi: detail,
      targetRoute: route,
      payload: <String, Object?>{
        'amountMinor': event.amountMinor,
        'title': event.title,
        if (event.categoryName != null) 'categoryName': event.categoryName,
        if (event.vehicleId != null) 'vehicleId': event.vehicleId,
        if (event.familyId != null) 'familyId': event.familyId,
      },
      supportsUndo: supportsUndo,
      createdAt: event.occurredAt,
    );
  }
}
