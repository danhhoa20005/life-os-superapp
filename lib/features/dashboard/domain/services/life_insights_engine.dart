import 'package:equatable/equatable.dart';

enum LifeInsightPeriodKind {
  weekly('week', 'Tuần'),
  monthly('month', 'Tháng'),
  quarterly('quarter', 'Quý'),
  yearly('year', 'Năm');

  final String code;
  final String labelVi;
  const LifeInsightPeriodKind(this.code, this.labelVi);
}

enum InsightTone { positive, neutral, warning }

class VerifiedInsightObservation extends Equatable {
  final String id;
  final InsightTone tone;
  final String domainLabelVi;
  final String headlineVi;
  final String metricBadgeVi;

  const VerifiedInsightObservation({
    required this.id,
    required this.tone,
    required this.domainLabelVi,
    required this.headlineVi,
    required this.metricBadgeVi,
  });

  @override
  List<Object?> get props => [
    id,
    tone,
    domainLabelVi,
    headlineVi,
    metricBadgeVi,
  ];
}

class LifeInsightsReport extends Equatable {
  final LifeInsightPeriodKind period;
  final int incomeMinor;
  final int expenseMinor;
  final int netSavingsMinor;
  final double savingsRatePct;
  final int netWorthMinor;
  final int totalDebtMinor;
  final int fixedCostMinor;
  final double fixedCostSharePct;
  final int completedTasksCount;
  final int totalTasksCount;
  final double taskCompletionPct;
  final int vehicleMaintenanceCount;
  final int vehicleSpendMinor;
  final int familySharedSpendMinor;
  final double goalProgressPct;
  final int lifeBalanceScore;
  final List<VerifiedInsightObservation> observations;

  const LifeInsightsReport({
    required this.period,
    required this.incomeMinor,
    required this.expenseMinor,
    required this.netSavingsMinor,
    required this.savingsRatePct,
    required this.netWorthMinor,
    required this.totalDebtMinor,
    required this.fixedCostMinor,
    required this.fixedCostSharePct,
    required this.completedTasksCount,
    required this.totalTasksCount,
    required this.taskCompletionPct,
    required this.vehicleMaintenanceCount,
    required this.vehicleSpendMinor,
    required this.familySharedSpendMinor,
    required this.goalProgressPct,
    required this.lifeBalanceScore,
    required this.observations,
  });

  @override
  List<Object?> get props => [
    period,
    incomeMinor,
    expenseMinor,
    netSavingsMinor,
    savingsRatePct,
    netWorthMinor,
    totalDebtMinor,
    fixedCostMinor,
    fixedCostSharePct,
    completedTasksCount,
    totalTasksCount,
    taskCompletionPct,
    vehicleMaintenanceCount,
    vehicleSpendMinor,
    familySharedSpendMinor,
    goalProgressPct,
    lifeBalanceScore,
    observations,
  ];
}

/// Deterministic Cross-Domain Life Insights Engine (Section 22).
/// Every percentage, delta, and Vietnamese commentary sentence is derived strictly from
/// verified domain numbers — AI is NEVER allowed to invent or extrapolate unverified figures.
abstract final class LifeInsightsEngine {
  static LifeInsightsReport compute({
    required LifeInsightPeriodKind period,
    required int incomeMinor,
    required int expenseMinor,
    required int previousPeriodExpenseMinor,
    required int netWorthMinor,
    required int totalDebtMinor,
    required int fixedCostMinor,
    Map<String, int> currentCategorySpendMinor = const <String, int>{},
    Map<String, int> previousCategorySpendMinor = const <String, int>{},
    int savedTowardGoalsMinor = 0,
    int totalGoalsTargetMinor = 0,
    int completedTasksCount = 0,
    int totalTasksCount = 0,
    int vehicleMaintenanceCount = 0,
    int vehicleSpendMinor = 0,
    int familySharedSpendMinor = 0,
  }) {
    final netSavings = incomeMinor - expenseMinor;
    final savingsRate = incomeMinor > 0
        ? ((netSavings * 100.0) / incomeMinor).clamp(-100.0, 100.0)
        : 0.0;
    final fixedShare = expenseMinor > 0
        ? ((fixedCostMinor * 100.0) / expenseMinor).clamp(0.0, 100.0)
        : 0.0;
    final taskPct = totalTasksCount > 0
        ? ((completedTasksCount * 100.0) / totalTasksCount).clamp(0.0, 100.0)
        : 100.0;
    final goalPct = totalGoalsTargetMinor > 0
        ? ((savedTowardGoalsMinor * 100.0) / totalGoalsTargetMinor)
              .clamp(0.0, 100.0)
        : 0.0;

    final observations = <VerifiedInsightObservation>[];

    // 1. Period-over-Period total expense comparison
    if (previousPeriodExpenseMinor > 0 && expenseMinor > 0) {
      final deltaPct =
          ((expenseMinor - previousPeriodExpenseMinor) * 100.0) /
          previousPeriodExpenseMinor;
      final rounded = deltaPct.abs().round();
      if (rounded >= 3) {
        final increased = deltaPct > 0;
        observations.add(
          VerifiedInsightObservation(
            id: 'obs_total_spend_delta',
            tone: increased ? InsightTone.warning : InsightTone.positive,
            domainLabelVi: 'Chi tiêu',
            headlineVi:
                'Tổng chi tiêu ${period.labelVi.toLowerCase()} này ${increased ? "tăng" : "giảm"} $rounded% so với kỳ trước.',
            metricBadgeVi: '${increased ? "+" : "-"}$rounded%',
          ),
        );
      }
    }

    // 2. Biggest category change (e.g. "Chi phí Ăn uống tháng này tăng 15% so với tháng trước.")
    String? topChangedCat;
    double topAbsDeltaPct = 0.0;
    double topSignedDeltaPct = 0.0;
    for (final entry in currentCategorySpendMinor.entries) {
      final prev = previousCategorySpendMinor[entry.key] ?? 0;
      if (prev <= 0 || entry.value <= 0) continue;
      final pct = ((entry.value - prev) * 100.0) / prev;
      if (pct.abs() > topAbsDeltaPct && pct.abs() >= 5.0) {
        topAbsDeltaPct = pct.abs();
        topSignedDeltaPct = pct;
        topChangedCat = entry.key;
      }
    }
    if (topChangedCat != null) {
      final rounded = topSignedDeltaPct.abs().round();
      final up = topSignedDeltaPct > 0;
      observations.add(
        VerifiedInsightObservation(
          id: 'obs_cat_delta',
          tone: up ? InsightTone.warning : InsightTone.positive,
          domainLabelVi: 'Thói quen',
          headlineVi:
              'Chi phí $topChangedCat ${period.labelVi.toLowerCase()} này ${up ? "tăng" : "giảm"} $rounded% so với ${period.labelVi.toLowerCase()} trước.',
          metricBadgeVi: '${up ? "+" : "-"}$rounded%',
        ),
      );
    }

    // 3. Savings rate & debt health
    if (incomeMinor > 0) {
      final sRounded = savingsRate.round();
      observations.add(
        VerifiedInsightObservation(
          id: 'obs_savings_rate',
          tone: savingsRate >= 20
              ? InsightTone.positive
              : (savingsRate < 0 ? InsightTone.warning : InsightTone.neutral),
          domainLabelVi: 'Tích lũy',
          headlineVi: savingsRate >= 0
              ? 'Tỷ lệ tiết kiệm ròng đạt $sRounded% trên tổng thu nhập kỳ này.'
              : 'Chi tiêu vượt thu nhập ${sRounded.abs()}% trong kỳ này — cần rà soát các khoản không thiết yếu.',
          metricBadgeVi: '$sRounded%',
        ),
      );
    }

    if (totalDebtMinor > 0 && netWorthMinor > 0) {
      final debtRatio = ((totalDebtMinor * 100.0) / (netWorthMinor + totalDebtMinor)).round();
      observations.add(
        VerifiedInsightObservation(
          id: 'obs_debt_ratio',
          tone: debtRatio > 40 ? InsightTone.warning : InsightTone.neutral,
          domainLabelVi: 'Công nợ',
          headlineVi:
              'Dư nợ hiện chiếm $debtRatio% tổng tài sản gộp.',
          metricBadgeVi: '$debtRatio%',
        ),
      );
    }

    // 4. Tasks & Productivity
    if (totalTasksCount > 0) {
      final tRounded = taskPct.round();
      observations.add(
        VerifiedInsightObservation(
          id: 'obs_tasks',
          tone: tRounded >= 75 ? InsightTone.positive : InsightTone.neutral,
          domainLabelVi: 'Công việc',
          headlineVi:
              'Đã hoàn thành $completedTasksCount/$totalTasksCount công việc ($tRounded%) trong ${period.labelVi.toLowerCase()}.',
          metricBadgeVi: '$tRounded%',
        ),
      );
    }

    // 5. Vehicle maintenance & Family shared cost
    if (vehicleMaintenanceCount > 0 || vehicleSpendMinor > 0) {
      observations.add(
        VerifiedInsightObservation(
          id: 'obs_vehicle',
          tone: InsightTone.neutral,
          domainLabelVi: 'Phương tiện',
          headlineVi:
              'Ghi nhận $vehicleMaintenanceCount lượt bảo dưỡng / chăm sóc xe trong kỳ.',
          metricBadgeVi: '$vehicleMaintenanceCount lượt',
        ),
      );
    }

    if (familySharedSpendMinor > 0 && expenseMinor > 0) {
      final famPct = ((familySharedSpendMinor * 100.0) / expenseMinor)
          .clamp(0.0, 100.0)
          .round();
      observations.add(
        VerifiedInsightObservation(
          id: 'obs_family_spend',
          tone: InsightTone.neutral,
          domainLabelVi: 'Gia đình',
          headlineVi:
              'Chi phí sinh hoạt chung gia đình tương đương $famPct% chi tiêu cá nhân.',
          metricBadgeVi: '$famPct%',
        ),
      );
    }

    // Life Balance Score (0..100): weighted blend of financial savings, fixed-cost discipline, debt health, and task execution
    var score = 55;
    if (savingsRate >= 25) {
      score += 20;
    } else if (savingsRate >= 10) {
      score += 10;
    } else if (savingsRate < 0) {
      score -= 15;
    }
    if (fixedShare > 0 && fixedShare <= 55) {
      score += 10;
    } else if (fixedShare > 75) {
      score -= 10;
    }
    if (totalDebtMinor == 0) {
      score += 8;
    }
    if (taskPct >= 75) {
      score += 7;
    }
    score = score.clamp(10, 100);

    return LifeInsightsReport(
      period: period,
      incomeMinor: incomeMinor,
      expenseMinor: expenseMinor,
      netSavingsMinor: netSavings,
      savingsRatePct: double.parse(savingsRate.toStringAsFixed(1)),
      netWorthMinor: netWorthMinor,
      totalDebtMinor: totalDebtMinor,
      fixedCostMinor: fixedCostMinor,
      fixedCostSharePct: double.parse(fixedShare.toStringAsFixed(1)),
      completedTasksCount: completedTasksCount,
      totalTasksCount: totalTasksCount,
      taskCompletionPct: double.parse(taskPct.toStringAsFixed(1)),
      vehicleMaintenanceCount: vehicleMaintenanceCount,
      vehicleSpendMinor: vehicleSpendMinor,
      familySharedSpendMinor: familySharedSpendMinor,
      goalProgressPct: double.parse(goalPct.toStringAsFixed(1)),
      lifeBalanceScore: score,
      observations: observations,
    );
  }
}
