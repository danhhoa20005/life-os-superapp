import 'dart:math' as math;

import 'behavior_domain.dart';

/// Pure-Dart Recency × Frequency × Circular Circadian Engine.
abstract final class RecencyFrequencyEngine {
  static const double _fourteenDaysHours = 336.0;
  static const double _maxAgeHours = 720.0;

  static final RegExp _trailingVndShorthandPattern = RegExp(
    r'(?:\s+\d+(?:[.,]\d+)*\s*(?:k|tr|trieu|triệu|ty|tỷ|ngàn|nghin|nghìn|vnd|vnđ|đ|d|₫)|\s+\d{1,3}(?:[.,]\d{3})+|\s+\d{4,})\s*$',
    caseSensitive: false,
  );

  /// Midnight-safe circular distance on a 24-hour clock (`min(|h1-h2|, 24-|h1-h2|)`).
  static int circularHourDistance(int h1, int h2) {
    final a = ((h1 % 24) + 24) % 24;
    final b = ((h2 % 24) + 24) % 24;
    final diff = (a - b).abs();
    return diff > 12 ? 24 - diff : diff;
  }

  /// Computes circular mean hour on `[0.0, 24.0)` so `23` and `1` average to `0.0` (midnight),
  /// never `12.0` (noon).
  static double computeCircularMeanHour(Iterable<int> hours) {
    final list = hours.toList(growable: false);
    if (list.isEmpty) return 12.0;

    var sumSin = 0.0;
    var sumCos = 0.0;
    for (final rawHour in list) {
      final h = ((rawHour % 24) + 24) % 24;
      final radians = h * (2.0 * math.pi / 24.0);
      sumSin += math.sin(radians);
      sumCos += math.cos(radians);
    }

    if (sumSin.abs() < 1e-9 && sumCos.abs() < 1e-9) {
      return (((list.first % 24) + 24) % 24).toDouble();
    }

    var angle = math.atan2(sumSin, sumCos);
    if (angle < 0) {
      angle += 2.0 * math.pi;
    }
    final mean = (angle * 24.0) / (2.0 * math.pi);
    return mean >= 24.0 ? mean - 24.0 : mean;
  }

  /// Rounded circular mean hour in `0..23` (`circularMeanHourInt([23, 1]) == 0`).
  static int circularMeanHourInt(Iterable<int> hours) {
    return computeCircularMeanHour(hours).round() % 24;
  }

  /// Produces a canonical amount-free habit ID so `"Cà phê 35k"` and `"Cà phê 45k"`
  /// merge cleanly into `"cà_phê"`, while preserving non-currency tokens such as `"9h"`.
  static String canonicalizeHabitId(String rawLabel) {
    final cleaned = rawLabel.trim().toLowerCase();
    if (cleaned.isEmpty) return '';

    var stripped = cleaned;
    while (true) {
      final next = stripped
          .replaceFirst(_trailingVndShorthandPattern, '')
          .trim();
      if (next == stripped || next.isEmpty) {
        if (next.isNotEmpty) stripped = next;
        break;
      }
      stripped = next;
    }

    final candidate = stripped
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    if (candidate.isNotEmpty) return candidate;

    return cleaned
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
  }

  /// Normalizes frequency into `[0.0, 1.0]` using logarithmic scaling.
  static double computeFrequencyNorm(int frequency, int maxFrequency) {
    if (frequency <= 0 || maxFrequency <= 0) return 0.0;
    final denom = math.log(1 + maxFrequency);
    if (denom <= 0) return 0.0;
    return (math.log(1 + frequency) / denom).clamp(0.0, 1.0);
  }

  /// Normalizes recency into `[0.0, 1.0]` with linear 14-day (336h) decay.
  static double computeRecencyNorm(int lastUsedEpochMs, DateTime now) {
    if (lastUsedEpochMs <= 0) return 0.0;
    final ageHours =
        ((now.millisecondsSinceEpoch - lastUsedEpochMs) / 3600000.0).clamp(
          0.0,
          _maxAgeHours,
        );
    return (1.0 - (ageHours / _fourteenDaysHours)).clamp(0.0, 1.0);
  }

  /// Upserts an executed quick action into an existing [HabitShortcut] list using
  /// amount-free canonical IDs and midnight-safe circular mean hours.
  static List<HabitShortcut> upsertHabitShortcut({
    required List<HabitShortcut> existing,
    required String label,
    required String commandText,
    String categoryName = '',
    int amountMinor = 0,
    DateTime? now,
    int maxItems = 16,
  }) {
    final cleanCmd = commandText.trim();
    final cleanLabel = label.trim();
    if (cleanCmd.isEmpty || cleanLabel.isEmpty) {
      return List<HabitShortcut>.unmodifiable(existing);
    }

    final refNow = now ?? DateTime.now();
    final canonicalId = canonicalizeHabitId(cleanLabel);
    final mutable = List<HabitShortcut>.from(existing);
    final idx = mutable.indexWhere((h) => h.id == canonicalId);

    if (idx >= 0) {
      final prev = mutable[idx];
      mutable[idx] = HabitShortcut(
        id: canonicalId,
        label: cleanLabel,
        commandText: cleanCmd,
        categoryName: categoryName.isNotEmpty
            ? categoryName
            : prev.categoryName,
        amountMinor: amountMinor > 0 ? amountMinor : prev.amountMinor,
        frequency: prev.frequency + 1,
        lastUsedEpochMs: refNow.millisecondsSinceEpoch,
        typicalHour: circularMeanHourInt([prev.typicalHour, refNow.hour]),
      );
    } else {
      mutable.insert(
        0,
        HabitShortcut(
          id: canonicalId,
          label: cleanLabel,
          commandText: cleanCmd,
          categoryName: categoryName,
          amountMinor: amountMinor,
          frequency: 1,
          lastUsedEpochMs: refNow.millisecondsSinceEpoch,
          typicalHour: refNow.hour,
        ),
      );
    }

    mutable.sort((a, b) => b.scoreAt(refNow).compareTo(a.scoreAt(refNow)));
    if (mutable.length > maxItems) {
      mutable.removeRange(maxItems, mutable.length);
    }
    return List<HabitShortcut>.unmodifiable(mutable);
  }
}

/// Pure-Dart contextual relevance scorer respecting user-recorded `typicalHours`
/// without imposing rigid daytime circadian assumptions on atypical schedules.
abstract final class ContextEngine {
  static double scoreContextMatch(
    RecommendationCandidate candidate,
    BehaviorContextSignal signal,
  ) {
    final fk = candidate.featureKey.toLowerCase();
    final idLower = candidate.id.toLowerCase();
    final token = '$fk $idLower';
    final hour = signal.now.hour;

    // 1. Live situational signals (objective state, independent of clock bias)
    var liveSituationScore = 0.0;
    if (signal.hasProvisionalBankTx &&
        (token.contains('provisional') ||
            token.contains('bank') ||
            token.contains('auto_tx'))) {
      liveSituationScore = math.max(liveSituationScore, 0.95);
    }
    if (signal.budgetUsageRatio >= 0.80 &&
        (token.contains('budget') ||
            token.contains('report') ||
            candidate.interestGroup == UserInterestGroup.spending)) {
      liveSituationScore = math.max(liveSituationScore, 0.90);
    }
    if (signal.upcomingBillCount > 0 &&
        (token.contains('bill') ||
            token.contains('evn') ||
            token.contains('utility') ||
            candidate.interestGroup == UserInterestGroup.home)) {
      liveSituationScore = math.max(liveSituationScore, 0.85);
    }
    if (signal.pendingTaskCount > 0 &&
        (token.contains('task') ||
            candidate.interestGroup == UserInterestGroup.schedule)) {
      liveSituationScore = math.max(liveSituationScore, 0.78);
    }
    if (signal.upcomingEventCount > 0 &&
        (token.contains('schedule') ||
            token.contains('calendar') ||
            token.contains('planning'))) {
      liveSituationScore = math.max(liveSituationScore, 0.80);
    }
    if (signal.isEndOfMonth &&
        (token.contains('budget') ||
            token.contains('bill') ||
            token.contains('evn') ||
            token.contains('report') ||
            token.contains('summary'))) {
      liveSituationScore = math.max(liveSituationScore, 0.85);
    }
    if (signal.isWeekend &&
        (candidate.interestGroup == UserInterestGroup.family ||
            candidate.interestGroup == UserInterestGroup.vehicle)) {
      liveSituationScore = math.max(liveSituationScore, 0.78);
    }
    if (signal.hasActiveFamily &&
        candidate.interestGroup == UserInterestGroup.family) {
      liveSituationScore = math.max(liveSituationScore, 0.65);
    }

    // 2. If user has recorded `typicalHours` for this candidate, honor their personal
    //    circadian rhythm using midnight-safe circular distance (NEVER assume 8am–10pm).
    if (candidate.typicalHours.isNotEmpty) {
      var minDistance = 24;
      for (final typicalHour in candidate.typicalHours) {
        final d = RecencyFrequencyEngine.circularHourDistance(
          hour,
          typicalHour,
        );
        if (d < minDistance) minDistance = d;
      }
      final personalScore = switch (minDistance) {
        0 => 1.0,
        1 => 0.90,
        2 => 0.78,
        3 => 0.55,
        4 => 0.35,
        <= 6 => 0.15,
        _ => 0.05,
      };
      return math.max(personalScore, liveSituationScore).clamp(0.0, 1.0);
    }

    // 3. General contextual rhythm fallback when no personal typicalHours exist yet
    var rhythmScore = 0.25;
    if (hour >= 5 && hour < 11) {
      if (token.contains('schedule') ||
          token.contains('calendar') ||
          token.contains('task') ||
          token.contains('planning') ||
          candidate.interestGroup == UserInterestGroup.schedule) {
        rhythmScore = 0.78;
      }
    } else if (hour >= 11 && hour < 14) {
      // Lunch food suggestion ONLY when user has recorded history (frequencyCount > 0)
      final isFoodOrExpense =
          token.contains('food') ||
          token.contains('lunch') ||
          token.contains('meal') ||
          token.contains('coffee') ||
          token.contains('expense') ||
          candidate.interestGroup == UserInterestGroup.spending;
      if (isFoodOrExpense && candidate.frequencyCount > 0) {
        rhythmScore = 0.75;
      } else if (candidate.interestGroup == UserInterestGroup.schedule) {
        rhythmScore = 0.45;
      }
    } else if (hour >= 17 && hour < 23) {
      if (token.contains('shopping') ||
          token.contains('kitchen') ||
          token.contains('grocery') ||
          token.contains('summary') ||
          token.contains('report') ||
          candidate.interestGroup == UserInterestGroup.family) {
        rhythmScore = 0.75;
      }
    }

    return math.max(rhythmScore, liveSituationScore).clamp(0.0, 1.0);
  }
}

/// Pure-Dart multi-factor contextual recommendation engine.
abstract final class RecommendationEngine {
  static const double _fourteenDaysHours = 336.0;

  /// Scores a single [candidate] by normalizing every factor into `[0.0, 1.0]`
  /// before computing the weighted sum minus decayed dismissal penalty.
  static RecommendationScoreBreakdown scoreCandidate({
    required RecommendationCandidate candidate,
    required PersonalizationSettings settings,
    required BehaviorContextSignal signal,
    required int maxFrequency,
  }) {
    final frequencyNorm = RecencyFrequencyEngine.computeFrequencyNorm(
      candidate.frequencyCount,
      maxFrequency,
    );
    final recencyNorm = RecencyFrequencyEngine.computeRecencyNorm(
      candidate.lastUsedEpochMs,
      signal.now,
    );
    final contextMatchNorm = ContextEngine.scoreContextMatch(
      candidate,
      signal,
    ).clamp(0.0, 1.0);
    final urgencyNorm = candidate.urgencyScore.clamp(0.0, 1.0);

    final isPinned =
        candidate.isPinnedByUser ||
        settings.pinnedFeatureIds.contains(candidate.featureKey) ||
        settings.pinnedFeatureIds.contains(candidate.id);

    final matchesSelectedInterest =
        settings.selectedInterests.contains(UserInterestGroup.all) ||
        settings.selectedInterests.contains(candidate.interestGroup);

    final explicitPreferenceNorm = matchesSelectedInterest
        ? 1.0
        : (isPinned ? 0.5 : 0.0);

    final habitConsistencyNorm = candidate.habitConsistencyScore.clamp(
      0.0,
      1.0,
    );

    final dismissCount =
        settings.dismissedCounts[candidate.id] ??
        settings.dismissedCounts[candidate.featureKey] ??
        0;
    var dismissalPenalty = 0.0;
    if (dismissCount > 0) {
      final lastDismissMs =
          settings.lastDismissedEpochMs[candidate.id] ??
          settings.lastDismissedEpochMs[candidate.featureKey] ??
          0;
      final decayFactor = lastDismissMs <= 0
          ? 1.0
          : (1.0 -
                    (((signal.now.millisecondsSinceEpoch - lastDismissMs) /
                                3600000.0)
                            .clamp(0.0, _fourteenDaysHours) /
                        _fourteenDaysHours))
                .clamp(0.0, 1.0);
      dismissalPenalty = (dismissCount * 0.22 * decayFactor).clamp(0.0, 0.85);
    }

    final finalScore =
        0.25 * frequencyNorm +
        0.20 * recencyNorm +
        0.20 * contextMatchNorm +
        0.15 * urgencyNorm +
        0.10 * explicitPreferenceNorm +
        0.10 * habitConsistencyNorm -
        dismissalPenalty;

    return RecommendationScoreBreakdown(
      frequencyNorm: frequencyNorm,
      recencyNorm: recencyNorm,
      contextMatchNorm: contextMatchNorm,
      urgencyNorm: urgencyNorm,
      explicitPreferenceNorm: explicitPreferenceNorm,
      habitConsistencyNorm: habitConsistencyNorm,
      dismissalPenalty: dismissalPenalty,
      finalScore: finalScore,
      // Safety invariant: financial mutations can NEVER auto-execute.
      autoExecuteAllowed: !candidate.isFinancialMutation,
    );
  }

  /// Ranks and selects up to [limit] contextual recommendations.
  /// - Returns empty immediately when [settings.enabled] is `false`.
  /// - During Cold Start (`totalRecordedSignals < coldStartMinSignals`), NEVER
  ///   fabricates financial habits; only allows calm starter suggestions matching
  ///   `selectedInterests` (or simple defaults).
  static List<ScoredRecommendation> recommend({
    required List<RecommendationCandidate> candidates,
    required PersonalizationSettings settings,
    required BehaviorContextSignal signal,
    int limit = 2,
    bool prioritizePinned = false,
  }) {
    if (!settings.enabled || limit <= 0) {
      return const <ScoredRecommendation>[];
    }

    final List<RecommendationCandidate> pool;
    if (settings.isColdStart) {
      final source = candidates.isEmpty
          ? coldStartStarterSuggestions(settings: settings, signal: signal)
          : candidates;
      final hasSpecificInterest =
          settings.selectedInterests.isNotEmpty &&
          !settings.selectedInterests.contains(UserInterestGroup.all);

      pool = source
          .where((c) {
            // Never fabricate financial habits during cold start
            if (c.isFinancialMutation) return false;
            if (c.frequencyCount > 0 && !c.isStarterSuggestion) return false;
            if (hasSpecificInterest &&
                c.interestGroup != UserInterestGroup.all &&
                !settings.selectedInterests.contains(c.interestGroup)) {
              return false;
            }
            return true;
          })
          .toList(growable: false);
    } else {
      pool = candidates;
    }

    if (pool.isEmpty) {
      return const <ScoredRecommendation>[];
    }

    var maxFreq = 0;
    for (final c in pool) {
      if (c.frequencyCount > maxFreq) {
        maxFreq = c.frequencyCount;
      }
    }

    final scored = pool
        .map(
          (c) => ScoredRecommendation(
            candidate: c,
            breakdown: scoreCandidate(
              candidate: c,
              settings: settings,
              signal: signal,
              maxFrequency: maxFreq,
            ),
          ),
        )
        .toList(growable: true);

    scored.sort((a, b) {
      if (prioritizePinned) {
        final aPinned = _isPinned(a.candidate, settings);
        final bPinned = _isPinned(b.candidate, settings);
        if (aPinned != bPinned) {
          return aPinned ? -1 : 1;
        }
      }
      final scoreCmp = b.score.compareTo(a.score);
      if (scoreCmp != 0) return scoreCmp;
      final urgencyCmp = b.breakdown.urgencyNorm.compareTo(
        a.breakdown.urgencyNorm,
      );
      if (urgencyCmp != 0) return urgencyCmp;
      return a.candidate.id.compareTo(b.candidate.id);
    });

    return List<ScoredRecommendation>.unmodifiable(scored.take(limit));
  }

  /// Sorts shortcuts ensuring user-pinned items ALWAYS outrank inferred items.
  static List<ScoredRecommendation> sortPinnedShortcuts({
    required List<RecommendationCandidate> candidates,
    required PersonalizationSettings settings,
    required BehaviorContextSignal signal,
  }) {
    if (candidates.isEmpty) return const <ScoredRecommendation>[];
    var maxFreq = 0;
    for (final c in candidates) {
      if (c.frequencyCount > maxFreq) {
        maxFreq = c.frequencyCount;
      }
    }

    final scored = candidates
        .map(
          (c) => ScoredRecommendation(
            candidate: c,
            breakdown: scoreCandidate(
              candidate: c,
              settings: settings,
              signal: signal,
              maxFrequency: maxFreq,
            ),
          ),
        )
        .toList(growable: true);

    scored.sort((a, b) {
      final aPinned = _isPinned(a.candidate, settings);
      final bPinned = _isPinned(b.candidate, settings);
      if (aPinned != bPinned) {
        return aPinned ? -1 : 1;
      }
      return b.score.compareTo(a.score);
    });

    return List<ScoredRecommendation>.unmodifiable(scored);
  }

  /// Calm non-fabricating starter suggestions used during cold start.
  static List<RecommendationCandidate> coldStartStarterSuggestions({
    required PersonalizationSettings settings,
    required BehaviorContextSignal signal,
  }) {
    final allStarters = <RecommendationCandidate>[
      RecommendationCandidate(
        id: 'starter_schedule_today',
        featureKey: 'planning_schedule',
        titleVi: 'Xem nhịp lịch & việc hôm nay',
        subtitleVi: 'Sắp xếp việc cần làm và lịch hẹn trong ngày gọn gàng.',
        reasonVi: 'Gợi ý khởi đầu theo nhóm Quản lý lịch',
        targetRoute: '/planning',
        actionLabelVi: 'Mở lịch & việc',
        interestGroup: UserInterestGroup.schedule,
        urgencyScore: signal.pendingTaskCount > 0 ? 0.65 : 0.45,
        isFinancialMutation: false,
        isStarterSuggestion: true,
      ),
      const RecommendationCandidate(
        id: 'starter_quick_expense',
        featureKey: 'quick_expense_guide',
        titleVi: 'Ghi khoản chi đầu tiên',
        subtitleVi: 'Mở bảng ghi nhanh bằng giọng nói hoặc gõ ngắn tự nhiên.',
        reasonVi: 'Gợi ý khởi đầu theo nhóm Quản lý chi tiêu',
        targetRoute: '/financial-ai',
        actionLabelVi: 'Ghi nhanh ngay',
        interestGroup: UserInterestGroup.spending,
        urgencyScore: 0.40,
        isFinancialMutation: false,
        isStarterSuggestion: true,
      ),
      RecommendationCandidate(
        id: 'starter_family_hub',
        featureKey: 'family_hub_guide',
        titleVi: 'Khám phá không gian gia đình',
        subtitleVi: 'Tách bạch ví cá nhân và quỹ chung khi cần chia chi tiêu.',
        reasonVi: 'Gợi ý khởi đầu theo nhóm Quản lý gia đình',
        targetRoute: '/family',
        actionLabelVi: 'Xem gia đình',
        interestGroup: UserInterestGroup.family,
        urgencyScore: signal.isWeekend ? 0.55 : 0.35,
        isFinancialMutation: false,
        isStarterSuggestion: true,
      ),
      RecommendationCandidate(
        id: 'starter_home_evn',
        featureKey: 'home_evn_guide',
        titleVi: 'Theo dõi điện nước trong nhà',
        subtitleVi: 'Tính bậc thang EVN và nhắc hóa đơn hàng tháng rõ ràng.',
        reasonVi: 'Gợi ý khởi đầu theo nhóm Quản lý nhà cửa',
        targetRoute: '/home-living',
        actionLabelVi: 'Mở tiện ích nhà',
        interestGroup: UserInterestGroup.home,
        urgencyScore: signal.isEndOfMonth ? 0.60 : 0.35,
        isFinancialMutation: false,
        isStarterSuggestion: true,
      ),
      RecommendationCandidate(
        id: 'starter_vehicle_care',
        featureKey: 'vehicle_care_guide',
        titleVi: 'Thiết lập nhắc bảo dưỡng xe',
        subtitleVi: 'Theo dõi mốc thay nhớt và bảo hiểm xe cộ đúng hạn.',
        reasonVi: 'Gợi ý khởi đầu theo nhóm Quản lý xe cộ',
        targetRoute: '/assets',
        actionLabelVi: 'Mở xe cộ',
        interestGroup: UserInterestGroup.vehicle,
        urgencyScore: signal.isWeekend ? 0.55 : 0.35,
        isFinancialMutation: false,
        isStarterSuggestion: true,
      ),
    ];

    final hasSpecific =
        settings.selectedInterests.isNotEmpty &&
        !settings.selectedInterests.contains(UserInterestGroup.all);

    if (!hasSpecific) {
      return List<RecommendationCandidate>.unmodifiable(allStarters.take(3));
    }

    final filtered = allStarters
        .where((s) => settings.selectedInterests.contains(s.interestGroup))
        .toList(growable: false);
    if (filtered.isNotEmpty) {
      return List<RecommendationCandidate>.unmodifiable(filtered);
    }
    return List<RecommendationCandidate>.unmodifiable(allStarters.take(2));
  }

  static bool _isPinned(
    RecommendationCandidate candidate,
    PersonalizationSettings settings,
  ) {
    return candidate.isPinnedByUser ||
        settings.pinnedFeatureIds.contains(candidate.featureKey) ||
        settings.pinnedFeatureIds.contains(candidate.id);
  }
}
