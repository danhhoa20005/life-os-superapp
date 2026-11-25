import 'package:equatable/equatable.dart';

enum SmartInboxKind {
  bankProvisional('bank_provisional', 'Giao dịch ngân hàng chờ duyệt'),
  aiPendingDraft('ai_draft', 'Bản nháp AI chưa xác nhận'),
  familyInvite('family_invite', 'Lời mời tham gia nhóm'),
  fundApprovalRequest('fund_request', 'Yêu cầu duyệt chi quỹ chung'),
  debtDue('debt_due', 'Khoản công nợ cần tất toán'),
  billUpcoming('bill_due', 'Hóa đơn định kỳ sắp đến hạn'),
  taskOpen('task_open', 'Nhiệm vụ cần hoàn thành'),
  calendarUpcoming('event_upcoming', 'Lịch hẹn sắp diễn ra'),
  documentExpiring('doc_expiring', 'Giấy tờ sắp hết hạn'),
  vehicleMaintenance('vehicle_due', 'Nhắc bảo dưỡng phương tiện'),
  medicationReminder('med_reminder', 'Nhắc uống thuốc');

  final String code;
  final String groupTitleVi;
  const SmartInboxKind(this.code, this.groupTitleVi);
}

enum SmartInboxPriority {
  critical(3, 'Khẩn cấp'),
  high(2, 'Ưu tiên cao'),
  normal(1, 'Thông tin');

  final int rank;
  final String labelVi;
  const SmartInboxPriority(this.rank, this.labelVi);
}

class SmartInboxItem extends Equatable {
  /// Deterministic deduplication key (e.g. `bank_provisional::tx_123`).
  /// Prevents duplicate inbox cards for the exact same underlying domain event!
  final String dedupKey;
  final SmartInboxKind kind;
  final SmartInboxPriority priority;
  final String titleVi;
  final String subtitleVi;
  final int? amountMinor;
  final DateTime timestamp;
  final String targetRoute;
  final String primaryActionLabelVi;
  final bool isRead;
  final DateTime? snoozedUntil;

  const SmartInboxItem({
    required this.dedupKey,
    required this.kind,
    required this.priority,
    required this.titleVi,
    required this.subtitleVi,
    this.amountMinor,
    required this.timestamp,
    required this.targetRoute,
    required this.primaryActionLabelVi,
    this.isRead = false,
    this.snoozedUntil,
  });

  bool isSnoozedAt(DateTime now) =>
      snoozedUntil != null && snoozedUntil!.isAfter(now);

  SmartInboxItem copyWith({
    bool? isRead,
    DateTime? snoozedUntil,
    bool clearSnooze = false,
  }) {
    return SmartInboxItem(
      dedupKey: dedupKey,
      kind: kind,
      priority: priority,
      titleVi: titleVi,
      subtitleVi: subtitleVi,
      amountMinor: amountMinor,
      timestamp: timestamp,
      targetRoute: targetRoute,
      primaryActionLabelVi: primaryActionLabelVi,
      isRead: isRead ?? this.isRead,
      snoozedUntil: clearSnooze ? null : (snoozedUntil ?? this.snoozedUntil),
    );
  }

  @override
  List<Object?> get props => [
    dedupKey,
    kind,
    priority,
    titleVi,
    subtitleVi,
    amountMinor,
    timestamp,
    targetRoute,
    primaryActionLabelVi,
    isRead,
    snoozedUntil,
  ];
}

class SmartInboxSnapshot extends Equatable {
  final List<SmartInboxItem> activeItems;
  final List<SmartInboxItem> snoozedItems;
  final Map<SmartInboxKind, List<SmartInboxItem>> groupedByKind;
  final int unreadActionableCount;

  const SmartInboxSnapshot({
    required this.activeItems,
    required this.snoozedItems,
    required this.groupedByKind,
    required this.unreadActionableCount,
  });

  @override
  List<Object?> get props => [
    activeItems,
    snoozedItems,
    groupedByKind,
    unreadActionableCount,
  ];
}

/// Unified Smart Inbox Triage & Deduplication Engine (Section 17).
/// Aggregates all 11 actionable life domains without ever emitting duplicate cards
/// for the same underlying event.
abstract final class SmartInboxEngine {
  static SmartInboxSnapshot build({
    required List<SmartInboxItem> rawCandidates,
    required DateTime referenceNow,
    Set<String> readKeys = const <String>{},
    Set<String> dismissedKeys = const <String>{},
    Map<String, DateTime> snoozedUntilByKey = const <String, DateTime>{},
  }) {
    final dedupedByKey = <String, SmartInboxItem>{};

    for (final raw in rawCandidates) {
      if (dismissedKeys.contains(raw.dedupKey)) continue;
      final decorated = raw.copyWith(
        isRead: raw.isRead || readKeys.contains(raw.dedupKey),
        snoozedUntil: snoozedUntilByKey[raw.dedupKey] ?? raw.snoozedUntil,
      );
      final prev = dedupedByKey[decorated.dedupKey];
      // Keep higher-priority or fresher item on collision
      if (prev == null ||
          decorated.priority.rank > prev.priority.rank ||
          decorated.timestamp.isAfter(prev.timestamp)) {
        dedupedByKey[decorated.dedupKey] = decorated;
      }
    }

    final active = <SmartInboxItem>[];
    final snoozed = <SmartInboxItem>[];

    for (final item in dedupedByKey.values) {
      if (item.isSnoozedAt(referenceNow)) {
        snoozed.add(item);
      } else {
        active.add(item);
      }
    }

    active.sort((a, b) {
      if (a.isRead != b.isRead) {
        return a.isRead ? 1 : -1;
      }
      final prioCmp = b.priority.rank.compareTo(a.priority.rank);
      if (prioCmp != 0) return prioCmp;
      return b.timestamp.compareTo(a.timestamp);
    });

    snoozed.sort((a, b) => a.snoozedUntil!.compareTo(b.snoozedUntil!));

    final grouped = <SmartInboxKind, List<SmartInboxItem>>{};
    for (final item in active) {
      grouped.putIfAbsent(item.kind, () => <SmartInboxItem>[]).add(item);
    }

    final unreadCount = active.where((i) => !i.isRead).length;

    return SmartInboxSnapshot(
      activeItems: active,
      snoozedItems: snoozed,
      groupedByKind: grouped,
      unreadActionableCount: unreadCount,
    );
  }
}
