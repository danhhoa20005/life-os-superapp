import 'package:equatable/equatable.dart';

/// Represents a learned user habit ranked by Recency × Frequency × Circadian Time Affinity
/// (interoperates seamlessly with Behavior Engine 2.0 & `UserBehaviorPrefs`).
class HabitShortcut extends Equatable {
  final String id;
  final String label;
  final String commandText;
  final String categoryName;
  final int amountMinor;
  final int frequency;
  final int lastUsedEpochMs;
  final int typicalHour;

  const HabitShortcut({
    required this.id,
    required this.label,
    required this.commandText,
    this.categoryName = '',
    this.amountMinor = 0,
    this.frequency = 1,
    required this.lastUsedEpochMs,
    required this.typicalHour,
  });

  /// Computes behavioral relevance score at [now] combining frequency, 14-day recency decay,
  /// and ±2h circadian time-of-day affinity.
  double scoreAt(DateTime now) {
    final freqScore = frequency * 2.2;
    final ageHours =
        ((now.millisecondsSinceEpoch - lastUsedEpochMs) / 3600000.0).clamp(
          0.0,
          720.0,
        );
    final recencyScore = (1.0 - (ageHours / 336.0)).clamp(0.0, 1.0) * 4.0;
    final hourDiff = (now.hour - typicalHour).abs();
    final wrappedHourDiff = hourDiff > 12 ? 24 - hourDiff : hourDiff;
    final circadianBonus = wrappedHourDiff <= 2
        ? 3.2
        : (wrappedHourDiff <= 4 ? 1.2 : 0.0);
    return freqScore + recencyScore + circadianBonus;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'label': label,
    'commandText': commandText,
    'categoryName': categoryName,
    'amountMinor': amountMinor,
    'frequency': frequency,
    'lastUsedEpochMs': lastUsedEpochMs,
    'typicalHour': typicalHour,
  };

  factory HabitShortcut.fromJson(Map<String, dynamic> json) {
    return HabitShortcut(
      id: (json['id'] as String?) ?? '',
      label: (json['label'] as String?) ?? '',
      commandText: (json['commandText'] as String?) ?? '',
      categoryName: (json['categoryName'] as String?) ?? '',
      amountMinor: (json['amountMinor'] as num?)?.toInt() ?? 0,
      frequency: (json['frequency'] as num?)?.toInt() ?? 1,
      lastUsedEpochMs: (json['lastUsedEpochMs'] as num?)?.toInt() ?? 0,
      typicalHour: (json['typicalHour'] as num?)?.toInt() ?? 12,
    );
  }

  @override
  List<Object?> get props => [
    id,
    label,
    commandText,
    categoryName,
    amountMinor,
    frequency,
    lastUsedEpochMs,
    typicalHour,
  ];
}

/// Strictly bounded set of 12 non-PII UX behavior event types recorded locally on-device.
enum BehaviorEventType {
  featureOpened,
  quickActionUsed,
  taskCompleted,
  searchPerformed,
  searchResultSelected,
  recommendationAccepted,
  recommendationDismissed,
  shortcutPinned,
  shortcutUnpinned,
  formAbandoned,
  validationFailed,
  undoRequested;

  static BehaviorEventType? fromWire(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    for (final value in BehaviorEventType.values) {
      if (value.name == raw.trim()) return value;
    }
    return null;
  }
}

/// Enforces strict local-only privacy boundaries on UX behavior signals:
/// - Allowlist of 7 non-PII metadata keys only.
/// - Strips/rejects raw financial content, notes, documents, voice transcripts,
///   and phone/email/bank account PII.
/// - Never uploads behavioral analytics externally.
abstract final class BehaviorPrivacyPolicy {
  static const bool externalUploadAllowed = false;

  static const Set<String> allowedMetadataKeys = <String>{
    'targetId',
    'featureKey',
    'hourOfDay',
    'weekday',
    'screenKey',
    'durationMs',
    'stepCount',
  };

  static final RegExp _emailPattern = RegExp(
    r'[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}',
    caseSensitive: false,
  );
  static final RegExp _phonePattern = RegExp(
    r'(?:\+84|84|0)(?:3|5|7|8|9)\d{7,9}|\b0\d{8,10}\b',
  );
  static final RegExp _longDigitsPattern = RegExp(r'\d{9,}');
  static final RegExp _currencyPattern = RegExp(
    r'(?:^|\s)\d+(?:[.,]\d+)*\s*(?:k|tr|trieu|triệu|ty|tỷ|ngàn|nghin|nghìn|đ|₫|vnd|vnđ)(?:\s|$)',
    caseSensitive: false,
  );

  static bool isAllowedKey(String key) => allowedMetadataKeys.contains(key);

  static bool containsSensitivePii(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return false;
    if (_emailPattern.hasMatch(trimmed)) return true;
    if (_phonePattern.hasMatch(trimmed)) return true;
    if (_longDigitsPattern.hasMatch(trimmed)) return true;
    if (_currencyPattern.hasMatch(trimmed)) return true;
    if (trimmed.contains('₫')) return true;
    return false;
  }

  /// Returns an unmodifiable sanitized copy keeping ONLY allowlisted keys and
  /// non-PII scalar values.
  static Map<String, Object> sanitizeMetadata(Map<String, Object?> raw) {
    if (raw.isEmpty) return const <String, Object>{};
    final out = <String, Object>{};

    for (final entry in raw.entries) {
      final key = entry.key;
      if (!isAllowedKey(key)) continue;
      final value = entry.value;
      if (value == null) continue;

      if (value is bool) {
        out[key] = value;
      } else if (value is int) {
        out[key] = _clampNumericKey(key, value);
      } else if (value is double) {
        if (!value.isFinite) continue;
        out[key] = _clampNumericKey(key, value.round());
      } else if (value is String) {
        final cleaned = value.trim();
        if (cleaned.isEmpty) continue;
        if (cleaned.length > 64) continue;
        // Reject free-form notes/transcripts containing newlines or multiple words > 3
        if (cleaned.contains('\n') || cleaned.contains('\r')) continue;
        final wordCount = cleaned
            .split(RegExp(r'\s+'))
            .where((w) => w.isNotEmpty)
            .length;
        if (wordCount > 3) continue;
        if (containsSensitivePii(cleaned)) continue;
        out[key] = cleaned;
      }
    }

    return Map<String, Object>.unmodifiable(out);
  }

  static int _clampNumericKey(String key, int value) {
    return switch (key) {
      'hourOfDay' => value.clamp(0, 23),
      'weekday' => value.clamp(1, 7),
      'durationMs' || 'stepCount' => value < 0 ? 0 : value,
      _ => value,
    };
  }
}

/// Anonymized UX behavior event stored in a bounded local rolling window.
class BehaviorEvent extends Equatable {
  final BehaviorEventType type;
  final int timestampEpochMs;
  final Map<String, Object> metadata;

  BehaviorEvent({
    required this.type,
    required this.timestampEpochMs,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) : metadata = BehaviorPrivacyPolicy.sanitizeMetadata(metadata);

  factory BehaviorEvent.create({
    required BehaviorEventType type,
    DateTime? timestamp,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    final ts = timestamp ?? DateTime.now();
    return BehaviorEvent(
      type: type,
      timestampEpochMs: ts.millisecondsSinceEpoch,
      metadata: metadata,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'type': type.name,
    'timestampEpochMs': timestampEpochMs,
    'metadata': metadata,
  };

  static BehaviorEvent? fromJson(Map<String, dynamic> json) {
    final parsedType = BehaviorEventType.fromWire(json['type'] as String?);
    if (parsedType == null) return null;
    final ts = (json['timestampEpochMs'] as num?)?.toInt() ?? 0;
    final rawMeta = json['metadata'];
    final metaMap = rawMeta is Map
        ? Map<String, Object?>.from(rawMeta)
        : const <String, Object?>{};
    return BehaviorEvent(
      type: parsedType,
      timestampEpochMs: ts,
      metadata: metaMap,
    );
  }

  @override
  List<Object?> get props => [type, timestampEpochMs, metadata];
}

/// High-level life domain interest groups for transparent personalization.
enum UserInterestGroup {
  spending('spending', 'Quản lý chi tiêu', 'Chi tiêu'),
  schedule('schedule', 'Quản lý lịch', 'Lịch trình'),
  family('family', 'Quản lý gia đình', 'Gia đình'),
  home('home', 'Quản lý nhà cửa', 'Nhà cửa'),
  vehicle('vehicle', 'Quản lý xe cộ', 'Xe cộ'),
  all('all', 'Tất cả', 'Tất cả');

  final String id;
  final String labelVi;
  final String shortLabelVi;

  const UserInterestGroup(this.id, this.labelVi, this.shortLabelVi);

  static UserInterestGroup? fromId(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final normalized = raw.trim().toLowerCase();
    for (final group in UserInterestGroup.values) {
      if (group.id == normalized || group.name.toLowerCase() == normalized) {
        return group;
      }
    }
    return null;
  }

  static Set<UserInterestGroup> fromIds(Iterable<String> ids) {
    final result = <UserInterestGroup>{};
    for (final id in ids) {
      final parsed = fromId(id);
      if (parsed != null) {
        result.add(parsed);
      }
    }
    return result;
  }
}

/// Account-partitioned personalization settings & feedback state.
class PersonalizationSettings extends Equatable {
  final bool enabled;
  final bool consentGranted;
  final Set<UserInterestGroup> selectedInterests;
  final List<String> pinnedFeatureIds;
  final Map<String, int> dismissedCounts;
  final Map<String, int> lastDismissedEpochMs;
  final int totalRecordedSignals;
  final int coldStartMinSignals;

  const PersonalizationSettings({
    this.enabled = true,
    this.consentGranted = true,
    this.selectedInterests = const <UserInterestGroup>{UserInterestGroup.all},
    this.pinnedFeatureIds = const <String>[],
    this.dismissedCounts = const <String, int>{},
    this.lastDismissedEpochMs = const <String, int>{},
    this.totalRecordedSignals = 0,
    this.coldStartMinSignals = 3,
  });

  bool get isColdStart => totalRecordedSignals < coldStartMinSignals;

  PersonalizationSettings copyWith({
    bool? enabled,
    bool? consentGranted,
    Set<UserInterestGroup>? selectedInterests,
    List<String>? pinnedFeatureIds,
    Map<String, int>? dismissedCounts,
    Map<String, int>? lastDismissedEpochMs,
    int? totalRecordedSignals,
    int? coldStartMinSignals,
  }) {
    return PersonalizationSettings(
      enabled: enabled ?? this.enabled,
      consentGranted: consentGranted ?? this.consentGranted,
      selectedInterests: selectedInterests ?? this.selectedInterests,
      pinnedFeatureIds: pinnedFeatureIds ?? this.pinnedFeatureIds,
      dismissedCounts: dismissedCounts ?? this.dismissedCounts,
      lastDismissedEpochMs: lastDismissedEpochMs ?? this.lastDismissedEpochMs,
      totalRecordedSignals: totalRecordedSignals ?? this.totalRecordedSignals,
      coldStartMinSignals: coldStartMinSignals ?? this.coldStartMinSignals,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'enabled': enabled,
    'consentGranted': consentGranted,
    'selectedInterests': selectedInterests.map((e) => e.id).toList(),
    'pinnedFeatureIds': pinnedFeatureIds,
    'dismissedCounts': dismissedCounts,
    'lastDismissedEpochMs': lastDismissedEpochMs,
    'totalRecordedSignals': totalRecordedSignals,
    'coldStartMinSignals': coldStartMinSignals,
  };

  factory PersonalizationSettings.fromJson(Map<String, dynamic> json) {
    final rawInterests = json['selectedInterests'];
    final parsedInterests = rawInterests is Iterable
        ? UserInterestGroup.fromIds(rawInterests.map((e) => e.toString()))
        : const <UserInterestGroup>{UserInterestGroup.all};
    final rawPinned = json['pinnedFeatureIds'];
    final parsedPinned = rawPinned is Iterable
        ? rawPinned.map((e) => e.toString()).where((e) => e.isNotEmpty).toList()
        : const <String>[];
    final rawDismissed = json['dismissedCounts'];
    final parsedDismissed = <String, int>{};
    if (rawDismissed is Map) {
      for (final entry in rawDismissed.entries) {
        final count = (entry.value as num?)?.toInt() ?? 0;
        if (count > 0) {
          parsedDismissed[entry.key.toString()] = count;
        }
      }
    }
    final rawDismissedTs = json['lastDismissedEpochMs'];
    final parsedDismissedTs = <String, int>{};
    if (rawDismissedTs is Map) {
      for (final entry in rawDismissedTs.entries) {
        final ts = (entry.value as num?)?.toInt() ?? 0;
        if (ts > 0) {
          parsedDismissedTs[entry.key.toString()] = ts;
        }
      }
    }

    return PersonalizationSettings(
      enabled: (json['enabled'] as bool?) ?? true,
      consentGranted: (json['consentGranted'] as bool?) ?? true,
      selectedInterests: parsedInterests.isEmpty
          ? const <UserInterestGroup>{UserInterestGroup.all}
          : Set<UserInterestGroup>.unmodifiable(parsedInterests),
      pinnedFeatureIds: List<String>.unmodifiable(parsedPinned),
      dismissedCounts: Map<String, int>.unmodifiable(parsedDismissed),
      lastDismissedEpochMs: Map<String, int>.unmodifiable(parsedDismissedTs),
      totalRecordedSignals:
          ((json['totalRecordedSignals'] as num?)?.toInt() ?? 0).clamp(
            0,
            1000000,
          ),
      coldStartMinSignals: ((json['coldStartMinSignals'] as num?)?.toInt() ?? 3)
          .clamp(1, 50),
    );
  }

  @override
  List<Object?> get props => [
    enabled,
    consentGranted,
    selectedInterests,
    pinnedFeatureIds,
    dismissedCounts,
    lastDismissedEpochMs,
    totalRecordedSignals,
    coldStartMinSignals,
  ];
}

/// Real-time local life context fed into `ContextEngine` and `RecommendationEngine`.
class BehaviorContextSignal extends Equatable {
  final DateTime now;
  final int pendingTaskCount;
  final int upcomingEventCount;
  final int upcomingBillCount;
  final double budgetUsageRatio;
  final bool hasProvisionalBankTx;
  final bool hasActiveFamily;
  final bool isEndOfMonth;
  final bool isWeekend;

  BehaviorContextSignal({
    required this.now,
    this.pendingTaskCount = 0,
    this.upcomingEventCount = 0,
    this.upcomingBillCount = 0,
    double budgetUsageRatio = 0.0,
    this.hasProvisionalBankTx = false,
    this.hasActiveFamily = false,
    bool? isEndOfMonth,
    bool? isWeekend,
  }) : budgetUsageRatio = budgetUsageRatio.clamp(0.0, 2.0),
       isEndOfMonth = isEndOfMonth ?? (now.day >= 25),
       isWeekend = isWeekend ?? (now.weekday >= DateTime.saturday);

  @override
  List<Object?> get props => [
    now,
    pendingTaskCount,
    upcomingEventCount,
    upcomingBillCount,
    budgetUsageRatio,
    hasProvisionalBankTx,
    hasActiveFamily,
    isEndOfMonth,
    isWeekend,
  ];
}

/// Candidate action or navigation shortcut evaluated by `RecommendationEngine`.
class RecommendationCandidate extends Equatable {
  final String id;
  final String featureKey;
  final String titleVi;
  final String subtitleVi;
  final String reasonVi;
  final String targetRoute;
  final String actionLabelVi;
  final UserInterestGroup interestGroup;
  final bool isPinnedByUser;
  final int frequencyCount;
  final int lastUsedEpochMs;
  final List<int> typicalHours;
  final double urgencyScore;
  final double habitConsistencyScore;
  final bool isFinancialMutation;
  final bool isStarterSuggestion;
  final String? prefillText;

  const RecommendationCandidate({
    required this.id,
    required this.featureKey,
    required this.titleVi,
    required this.subtitleVi,
    required this.reasonVi,
    required this.targetRoute,
    required this.actionLabelVi,
    required this.interestGroup,
    this.isPinnedByUser = false,
    this.frequencyCount = 0,
    this.lastUsedEpochMs = 0,
    this.typicalHours = const <int>[],
    this.urgencyScore = 0.0,
    this.habitConsistencyScore = 0.0,
    this.isFinancialMutation = false,
    this.isStarterSuggestion = false,
    this.prefillText,
  });

  /// Builds a candidate interoperably from an existing [HabitShortcut] without
  /// duplicating habit storage structures.
  factory RecommendationCandidate.fromHabitShortcut(
    HabitShortcut habit, {
    bool isPinnedByUser = false,
    UserInterestGroup interestGroup = UserInterestGroup.spending,
    String targetRoute = '/financial-ai',
    String actionLabelVi = 'Mở ghi nhanh',
    bool isFinancialMutation = true,
  }) {
    final hourStr = habit.typicalHour.toString().padLeft(2, '0');
    return RecommendationCandidate(
      id: 'habit_${habit.id}',
      featureKey: 'habit_${habit.id}',
      titleVi: habit.label,
      subtitleVi: habit.categoryName.isNotEmpty
          ? '${habit.categoryName} · Kiểm tra trước khi lưu'
          : 'Thao tác quen thuộc của bạn',
      reasonVi:
          'Bạn thường dùng khoảng ${hourStr}h (${habit.frequency} lần gần đây)',
      targetRoute: targetRoute,
      actionLabelVi: actionLabelVi,
      interestGroup: interestGroup,
      isPinnedByUser: isPinnedByUser,
      frequencyCount: habit.frequency,
      lastUsedEpochMs: habit.lastUsedEpochMs,
      typicalHours: <int>[habit.typicalHour],
      urgencyScore: 0.25,
      habitConsistencyScore: (habit.frequency / 5.0).clamp(0.2, 1.0),
      isFinancialMutation: isFinancialMutation,
      isStarterSuggestion: false,
      prefillText: habit.commandText,
    );
  }

  @override
  List<Object?> get props => [
    id,
    featureKey,
    titleVi,
    subtitleVi,
    reasonVi,
    targetRoute,
    actionLabelVi,
    interestGroup,
    isPinnedByUser,
    frequencyCount,
    lastUsedEpochMs,
    typicalHours,
    urgencyScore,
    habitConsistencyScore,
    isFinancialMutation,
    isStarterSuggestion,
    prefillText,
  ];
}

/// Transparent normalized component breakdown for a scored recommendation.
class RecommendationScoreBreakdown extends Equatable {
  final double frequencyNorm;
  final double recencyNorm;
  final double contextMatchNorm;
  final double urgencyNorm;
  final double explicitPreferenceNorm;
  final double habitConsistencyNorm;
  final double dismissalPenalty;
  final double finalScore;
  final bool autoExecuteAllowed;

  const RecommendationScoreBreakdown({
    required this.frequencyNorm,
    required this.recencyNorm,
    required this.contextMatchNorm,
    required this.urgencyNorm,
    required this.explicitPreferenceNorm,
    required this.habitConsistencyNorm,
    required this.dismissalPenalty,
    required this.finalScore,
    required this.autoExecuteAllowed,
  });

  @override
  List<Object?> get props => [
    frequencyNorm,
    recencyNorm,
    contextMatchNorm,
    urgencyNorm,
    explicitPreferenceNorm,
    habitConsistencyNorm,
    dismissalPenalty,
    finalScore,
    autoExecuteAllowed,
  ];
}

/// Candidate paired with its transparent score breakdown.
class ScoredRecommendation extends Equatable {
  final RecommendationCandidate candidate;
  final RecommendationScoreBreakdown breakdown;

  const ScoredRecommendation({
    required this.candidate,
    required this.breakdown,
  });

  double get score => breakdown.finalScore;
  bool get autoExecuteAllowed => breakdown.autoExecuteAllowed;

  @override
  List<Object?> get props => [candidate, breakdown];
}

/// Versioned local-only UX quality counter snapshot (zero PII, zero upload).
class UxMetricsSnapshot extends Equatable {
  static const int currentSchemaVersion = 1;

  final int schemaVersion;
  final int taskSuccessCount;
  final int taskFailureCount;
  final int undoCount;
  final int formAbandonCount;
  final int validationErrorCount;
  final int searchCount;
  final int zeroResultSearchCount;
  final int recommendationAcceptedCount;
  final int recommendationDismissedCount;

  const UxMetricsSnapshot({
    this.schemaVersion = currentSchemaVersion,
    this.taskSuccessCount = 0,
    this.taskFailureCount = 0,
    this.undoCount = 0,
    this.formAbandonCount = 0,
    this.validationErrorCount = 0,
    this.searchCount = 0,
    this.zeroResultSearchCount = 0,
    this.recommendationAcceptedCount = 0,
    this.recommendationDismissedCount = 0,
  });

  static const UxMetricsSnapshot empty = UxMetricsSnapshot();

  UxMetricsSnapshot copyWith({
    int? schemaVersion,
    int? taskSuccessCount,
    int? taskFailureCount,
    int? undoCount,
    int? formAbandonCount,
    int? validationErrorCount,
    int? searchCount,
    int? zeroResultSearchCount,
    int? recommendationAcceptedCount,
    int? recommendationDismissedCount,
  }) {
    return UxMetricsSnapshot(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      taskSuccessCount: taskSuccessCount ?? this.taskSuccessCount,
      taskFailureCount: taskFailureCount ?? this.taskFailureCount,
      undoCount: undoCount ?? this.undoCount,
      formAbandonCount: formAbandonCount ?? this.formAbandonCount,
      validationErrorCount: validationErrorCount ?? this.validationErrorCount,
      searchCount: searchCount ?? this.searchCount,
      zeroResultSearchCount:
          zeroResultSearchCount ?? this.zeroResultSearchCount,
      recommendationAcceptedCount:
          recommendationAcceptedCount ?? this.recommendationAcceptedCount,
      recommendationDismissedCount:
          recommendationDismissedCount ?? this.recommendationDismissedCount,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'schemaVersion': schemaVersion,
    'taskSuccessCount': taskSuccessCount,
    'taskFailureCount': taskFailureCount,
    'undoCount': undoCount,
    'formAbandonCount': formAbandonCount,
    'validationErrorCount': validationErrorCount,
    'searchCount': searchCount,
    'zeroResultSearchCount': zeroResultSearchCount,
    'recommendationAcceptedCount': recommendationAcceptedCount,
    'recommendationDismissedCount': recommendationDismissedCount,
  };

  factory UxMetricsSnapshot.fromJson(Map<String, dynamic> json) {
    int readNonNeg(String key) =>
        ((json[key] as num?)?.toInt() ?? 0).clamp(0, 1000000000);
    return UxMetricsSnapshot(
      schemaVersion:
          (json['schemaVersion'] as num?)?.toInt() ?? currentSchemaVersion,
      taskSuccessCount: readNonNeg('taskSuccessCount'),
      taskFailureCount: readNonNeg('taskFailureCount'),
      undoCount: readNonNeg('undoCount'),
      formAbandonCount: readNonNeg('formAbandonCount'),
      validationErrorCount: readNonNeg('validationErrorCount'),
      searchCount: readNonNeg('searchCount'),
      zeroResultSearchCount: readNonNeg('zeroResultSearchCount'),
      recommendationAcceptedCount: readNonNeg('recommendationAcceptedCount'),
      recommendationDismissedCount: readNonNeg('recommendationDismissedCount'),
    );
  }

  @override
  List<Object?> get props => [
    schemaVersion,
    taskSuccessCount,
    taskFailureCount,
    undoCount,
    formAbandonCount,
    validationErrorCount,
    searchCount,
    zeroResultSearchCount,
    recommendationAcceptedCount,
    recommendationDismissedCount,
  ];
}
