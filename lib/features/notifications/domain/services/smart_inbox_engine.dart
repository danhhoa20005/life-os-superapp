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

/// 4-tier notification attention taxonomy (Notification Experience Engine 2.0):
/// 1. Critical -> security, reversed/disputed financial alert (bypasses quiet hours)
/// 2. Time-sensitive -> calendar reminders, medications, bills due soon
/// 3. Actionable -> provisional bank alerts, AI drafts, fund requests, family invites
/// 4. Informational -> status recaps & non-urgent reminders
enum SmartInboxTier {
  critical(4, 'Khẩn cấp'),
  timeSensitive(3, 'Đúng giờ'),
  actionable(2, 'Cần xử lý'),
  informational(1, 'Thông tin');

  final int rank;
  final String labelVi;
  const SmartInboxTier(this.rank, this.labelVi);
}

class NotificationExperiencePrefs extends Equatable {
  final bool quietHoursEnabled;
  final int quietStartHour;
  final int quietEndHour;
  final bool dailyDigestEnabled;
  final int digestHour;
  final Set<SmartInboxKind> disabledKinds;

  const NotificationExperiencePrefs({
    this.quietHoursEnabled = false,
    this.quietStartHour = 22,
    this.quietEndHour = 7,
    this.dailyDigestEnabled = false,
    this.digestHour = 20,
    this.disabledKinds = const <SmartInboxKind>{},
  });

  bool isWithinQuietHours(DateTime now) {
    if (!quietHoursEnabled) return false;
    final start = ((quietStartHour % 24) + 24) % 24;
    final end = ((quietEndHour % 24) + 24) % 24;
    if (start == end) return false;
    final hour = now.hour;
    if (start < end) {
      return hour >= start && hour < end;
    }
    // Overnight wrap (e.g. 22:00 -> 07:00)
    return hour >= start || hour < end;
  }

  NotificationExperiencePrefs copyWith({
    bool? quietHoursEnabled,
    int? quietStartHour,
    int? quietEndHour,
    bool? dailyDigestEnabled,
    int? digestHour,
    Set<SmartInboxKind>? disabledKinds,
  }) {
    return NotificationExperiencePrefs(
      quietHoursEnabled: quietHoursEnabled ?? this.quietHoursEnabled,
      quietStartHour: quietStartHour ?? this.quietStartHour,
      quietEndHour: quietEndHour ?? this.quietEndHour,
      dailyDigestEnabled: dailyDigestEnabled ?? this.dailyDigestEnabled,
      digestHour: digestHour ?? this.digestHour,
      disabledKinds: disabledKinds ?? this.disabledKinds,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'quietHoursEnabled': quietHoursEnabled,
    'quietStartHour': quietStartHour,
    'quietEndHour': quietEndHour,
    'dailyDigestEnabled': dailyDigestEnabled,
    'digestHour': digestHour,
    'disabledKinds': disabledKinds.map((k) => k.code).toList()..sort(),
  };

  factory NotificationExperiencePrefs.fromJson(Map<String, dynamic> json) {
    int clampHour(Object? raw, int fallback) {
      if (raw is int && raw >= 0 && raw <= 23) return raw;
      return fallback;
    }

    final disabled = <SmartInboxKind>{};
    final rawDisabled = json['disabledKinds'];
    if (rawDisabled is List) {
      for (final code in rawDisabled) {
        final str = code.toString();
        for (final kind in SmartInboxKind.values) {
          if (kind.code == str || kind.name == str) {
            disabled.add(kind);
          }
        }
      }
    }

    return NotificationExperiencePrefs(
      quietHoursEnabled: json['quietHoursEnabled'] == true,
      quietStartHour: clampHour(json['quietStartHour'], 22),
      quietEndHour: clampHour(json['quietEndHour'], 7),
      dailyDigestEnabled: json['dailyDigestEnabled'] == true,
      digestHour: clampHour(json['digestHour'], 20),
      disabledKinds: disabled,
    );
  }

  @override
  List<Object?> get props => [
    quietHoursEnabled,
    quietStartHour,
    quietEndHour,
    dailyDigestEnabled,
    digestHour,
    disabledKinds,
  ];
}

class SmartInboxItem extends Equatable {
  /// Deterministic deduplication key (e.g. `bank_provisional::tx_123`).
  /// Prevents duplicate inbox cards for the exact same underlying domain event!
  final String dedupKey;
  final SmartInboxKind kind;
  final SmartInboxPriority priority;
  final SmartInboxTier? tier;
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
    SmartInboxPriority? priority,
    this.tier,
    required this.titleVi,
    required this.subtitleVi,
    this.amountMinor,
    required this.timestamp,
    required this.targetRoute,
    required this.primaryActionLabelVi,
    this.isRead = false,
    this.snoozedUntil,
  }) : priority =
           priority ??
           (tier == SmartInboxTier.critical
               ? SmartInboxPriority.critical
               : (tier == SmartInboxTier.timeSensitive ||
                         tier == SmartInboxTier.actionable
                     ? SmartInboxPriority.high
                     : SmartInboxPriority.normal));

  SmartInboxTier get effectiveTier {
    if (tier != null) return tier!;
    switch (priority) {
      case SmartInboxPriority.critical:
        return SmartInboxTier.critical;
      case SmartInboxPriority.high:
        return (kind == SmartInboxKind.calendarUpcoming ||
                kind == SmartInboxKind.medicationReminder ||
                kind == SmartInboxKind.billUpcoming)
            ? SmartInboxTier.timeSensitive
            : SmartInboxTier.actionable;
      case SmartInboxPriority.normal:
        return SmartInboxTier.informational;
    }
  }

  bool isSnoozedAt(DateTime now) =>
      snoozedUntil != null && snoozedUntil!.isAfter(now);

  SmartInboxItem copyWith({
    bool? isRead,
    DateTime? snoozedUntil,
    bool clearSnooze = false,
    SmartInboxTier? tier,
  }) {
    return SmartInboxItem(
      dedupKey: dedupKey,
      kind: kind,
      priority: priority,
      tier: tier ?? this.tier,
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
    tier,
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
  final List<SmartInboxItem> quietDeferredItems;
  final Map<SmartInboxKind, List<SmartInboxItem>> groupedByKind;
  final int unreadActionableCount;
  final String? digestSummaryVi;
  final bool isQuietHoursActive;

  const SmartInboxSnapshot({
    required this.activeItems,
    required this.snoozedItems,
    this.quietDeferredItems = const <SmartInboxItem>[],
    required this.groupedByKind,
    required this.unreadActionableCount,
    this.digestSummaryVi,
    this.isQuietHoursActive = false,
  });

  @override
  List<Object?> get props => [
    activeItems,
    snoozedItems,
    quietDeferredItems,
    groupedByKind,
    unreadActionableCount,
    digestSummaryVi,
    isQuietHoursActive,
  ];
}

/// Unified Smart Inbox Triage & Deduplication Engine (Section 17 & v3.27).
/// Aggregates all 11 actionable life domains with 4-tier triage, quiet hours,
/// daily digest, and strict event deduplication.
abstract final class SmartInboxEngine {
  static SmartInboxSnapshot build({
    required List<SmartInboxItem> rawCandidates,
    required DateTime referenceNow,
    Set<String> readKeys = const <String>{},
    Set<String> dismissedKeys = const <String>{},
    Map<String, DateTime> snoozedUntilByKey = const <String, DateTime>{},
    NotificationExperiencePrefs prefs = const NotificationExperiencePrefs(),
  }) {
    final dedupedByKey = <String, SmartInboxItem>{};
    final quietActive = prefs.isWithinQuietHours(referenceNow);

    for (final raw in rawCandidates) {
      if (dismissedKeys.contains(raw.dedupKey)) continue;
      if (prefs.disabledKinds.contains(raw.kind)) continue;
      final decorated = raw.copyWith(
        isRead: raw.isRead || readKeys.contains(raw.dedupKey),
        snoozedUntil: snoozedUntilByKey[raw.dedupKey] ?? raw.snoozedUntil,
      );
      final prev = dedupedByKey[decorated.dedupKey];
      // Keep higher-tier / higher-priority or fresher item on collision
      final shouldReplace =
          prev == null ||
          decorated.effectiveTier.rank > prev.effectiveTier.rank ||
          (decorated.effectiveTier.rank == prev.effectiveTier.rank &&
              (decorated.priority.rank > prev.priority.rank ||
                  (decorated.priority.rank == prev.priority.rank &&
                      decorated.timestamp.isAfter(prev.timestamp))));
      if (shouldReplace) {
        dedupedByKey[decorated.dedupKey] = decorated;
      }
    }

    final active = <SmartInboxItem>[];
    final snoozed = <SmartInboxItem>[];
    final quietDeferred = <SmartInboxItem>[];

    for (final item in dedupedByKey.values) {
      if (item.isSnoozedAt(referenceNow)) {
        snoozed.add(item);
      } else if (quietActive && item.effectiveTier != SmartInboxTier.critical) {
        quietDeferred.add(item);
      } else {
        active.add(item);
      }
    }

    int compareItems(SmartInboxItem a, SmartInboxItem b) {
      if (a.isRead != b.isRead) {
        return a.isRead ? 1 : -1;
      }
      final tierCmp = b.effectiveTier.rank.compareTo(a.effectiveTier.rank);
      if (tierCmp != 0) return tierCmp;
      final prioCmp = b.priority.rank.compareTo(a.priority.rank);
      if (prioCmp != 0) return prioCmp;
      return b.timestamp.compareTo(a.timestamp);
    }

    active.sort(compareItems);
    quietDeferred.sort(compareItems);
    snoozed.sort((a, b) => a.snoozedUntil!.compareTo(b.snoozedUntil!));

    final grouped = <SmartInboxKind, List<SmartInboxItem>>{};
    for (final item in active) {
      grouped.putIfAbsent(item.kind, () => <SmartInboxItem>[]).add(item);
    }

    final unreadCount = active.where((i) => !i.isRead).length;
    String? digestSummary;
    if (prefs.dailyDigestEnabled &&
        (active.isNotEmpty || quietDeferred.isNotEmpty)) {
      final combined = <SmartInboxItem>[...active, ...quietDeferred];
      final kindsCount = combined.map((i) => i.kind).toSet().length;
      final deferredPart = quietDeferred.isEmpty
          ? ''
          : ' · ${quietDeferred.length} mục giữ lại cho hết giờ yên tĩnh';
      digestSummary =
          'Tổng hợp ngày: ${combined.length} mục thuộc $kindsCount nhóm$deferredPart.';
    }

    return SmartInboxSnapshot(
      activeItems: active,
      snoozedItems: snoozed,
      quietDeferredItems: quietDeferred,
      groupedByKind: grouped,
      unreadActionableCount: unreadCount,
      digestSummaryVi: digestSummary,
      isQuietHoursActive: quietActive,
    );
  }
}
