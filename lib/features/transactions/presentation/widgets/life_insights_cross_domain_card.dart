import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../core/widgets/lifeos_design_system.dart';
import '../../../dashboard/domain/services/life_insights_engine.dart';
import '../../../dashboard/presentation/bloc/dashboard_bloc.dart';
import '../../../family/presentation/bloc/family_bloc.dart';
import '../../../tasks/domain/entities/task_entities.dart';
import '../../../tasks/presentation/bloc/task_bloc.dart';
import '../../../vehicles/presentation/bloc/vehicle_bloc.dart';

T? _maybeWatchInsight<T>(BuildContext context) {
  try {
    return context.watch<T>();
  } catch (_) {
    return null;
  }
}

/// Cross-Domain Deterministic Life Insights Card (Section 22).
/// Derives every percentage and Vietnamese summary strictly from verified domain BLoCs.
class LifeInsightsCrossDomainCard extends StatelessWidget {
  final String periodCode; // 'week' | 'month' | 'year'
  final int incomeMinor;
  final int expenseMinor;
  final Map<String, int> expenseByCategory;

  const LifeInsightsCrossDomainCard({
    super.key,
    required this.periodCode,
    required this.incomeMinor,
    required this.expenseMinor,
    required this.expenseByCategory,
  });

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final dash = _maybeWatchInsight<DashboardBloc>(context)?.state.data;
    final tasks =
        _maybeWatchInsight<TaskBloc>(context)?.state.tasks ??
        const <TaskEntity>[];
    final famState = _maybeWatchInsight<FamilyBloc>(context)?.state;
    final vehicleState = _maybeWatchInsight<VehicleBloc>(context)?.state;

    final completedTasks = tasks
        .where((t) => t.status == TaskWorkflowStatus.done)
        .length;
    final fixedCostMinor = (vehicleState?.bills ?? const []).fold<int>(
      0,
      (s, b) => s + b.estimatedAmountMinor,
    );
    var maintCount = 0;
    var vehicleSpend = 0;
    for (final list
        in (vehicleState?.maintenanceHistoryByVehicleId ?? const {}).values) {
      maintCount += list.length;
      for (final item in list) {
        vehicleSpend += item.costMinor;
      }
    }
    final familySharedMinor = (famState?.sharedBills ?? const []).fold<int>(
      0,
      (s, b) => s + b.totalAmountMinor,
    );

    final periodKind = switch (periodCode) {
      'week' => LifeInsightPeriodKind.weekly,
      'year' => LifeInsightPeriodKind.yearly,
      _ => LifeInsightPeriodKind.monthly,
    };

    final report = LifeInsightsEngine.compute(
      period: periodKind,
      incomeMinor: incomeMinor,
      expenseMinor: expenseMinor,
      previousPeriodExpenseMinor: 0,
      netWorthMinor: dash?.netWorthMinor ?? 0,
      totalDebtMinor: 0,
      fixedCostMinor: fixedCostMinor,
      currentCategorySpendMinor: expenseByCategory,
      completedTasksCount: completedTasks,
      totalTasksCount: tasks.length,
      vehicleMaintenanceCount: maintCount,
      vehicleSpendMinor: vehicleSpend,
      familySharedSpendMinor: familySharedMinor,
    );

    return LifeOsMintHeroCard(
      key: const Key('life_insights_cross_domain_card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const LifeOsIconSquircle(
                    icon: Icons.insights_rounded,
                    tone: LifeOsAccentTone.emerald,
                    size: 32,
                    iconSize: 17,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Phân tích Đời sống & Tài chính (${periodKind.labelVi})',
                      softWrap: true,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: c.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              LifeOsStatusPill(
                icon: Icons.stars_rounded,
                label: 'Điểm cân bằng: ${report.lifeBalanceScore}/100',
                tone: report.lifeBalanceScore >= 70
                    ? LifeOsAccentTone.emerald
                    : LifeOsAccentTone.amber,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              LifeOsStatusPill(
                label:
                    'Tiết kiệm: ${report.savingsRatePct.toStringAsFixed(0)}%',
                tone: report.savingsRatePct >= 20
                    ? LifeOsAccentTone.emerald
                    : LifeOsAccentTone.amber,
              ),
              LifeOsStatusPill(
                label:
                    'Hoàn thành việc: ${report.taskCompletionPct.toStringAsFixed(0)}%',
                tone: LifeOsAccentTone.blue,
              ),
              if (report.fixedCostMinor > 0)
                LifeOsStatusPill(
                  label:
                      'Chi cố định: ${report.fixedCostSharePct.toStringAsFixed(0)}%',
                  tone: LifeOsAccentTone.purple,
                ),
            ],
          ),
          if (report.observations.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final obs in report.observations.take(4))
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      obs.tone == InsightTone.warning
                          ? Icons.info_outline_rounded
                          : Icons.check_circle_outline_rounded,
                      size: 16,
                      color: obs.tone == InsightTone.warning
                          ? const Color(0xFFD97706)
                          : c.primary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        obs.headlineVi,
                        softWrap: true,
                        style: TextStyle(
                          fontSize: 12.4,
                          height: 1.32,
                          color: c.textPrimary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
