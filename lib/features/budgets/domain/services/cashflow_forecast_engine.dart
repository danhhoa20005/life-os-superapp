import 'dart:math' as math;

import 'package:equatable/equatable.dart';

class ScheduledCashflowItem extends Equatable {
  final String id;
  final String title;
  final int amountMinor;
  final bool isInflow;
  final DateTime dueDate;
  final int cycleDays; // 0 = one-off, 7 = weekly, 30 = monthly, 365 = yearly

  const ScheduledCashflowItem({
    required this.id,
    required this.title,
    required this.amountMinor,
    this.isInflow = false,
    required this.dueDate,
    this.cycleDays = 30,
  });

  @override
  List<Object?> get props => [
    id,
    title,
    amountMinor,
    isInflow,
    dueDate,
    cycleDays,
  ];
}

class DebtObligationItem extends Equatable {
  final String id;
  final String name;
  final int balanceMinor;
  final double annualInterestPct;
  final int minimumMonthlyPaymentMinor;

  const DebtObligationItem({
    required this.id,
    required this.name,
    required this.balanceMinor,
    required this.annualInterestPct,
    required this.minimumMonthlyPaymentMinor,
  });

  @override
  List<Object?> get props => [
    id,
    name,
    balanceMinor,
    annualInterestPct,
    minimumMonthlyPaymentMinor,
  ];
}

class SavingsGoalProgress extends Equatable {
  final String id;
  final String name;
  final int currentSavedMinor;
  final int targetMinor;
  final int suggestedMonthlyContributionMinor;
  final int estimatedMonthsToGoal;

  const SavingsGoalProgress({
    required this.id,
    required this.name,
    required this.currentSavedMinor,
    required this.targetMinor,
    required this.suggestedMonthlyContributionMinor,
    required this.estimatedMonthsToGoal,
  });

  @override
  List<Object?> get props => [
    id,
    name,
    currentSavedMinor,
    targetMinor,
    suggestedMonthlyContributionMinor,
    estimatedMonthsToGoal,
  ];
}

class HorizonCashflowProjection extends Equatable {
  final int horizonDays; // 7 | 30 | 90
  final int startingLiquidMinor;
  final int projectedInflowMinor;
  final int projectedScheduledOutflowMinor;
  final int projectedVariableSpendMinor;
  final int abnormalBufferMinor;
  final int projectedEndingBalanceMinor;
  final int lowestBalanceMinor;
  final DateTime? firstShortfallDate;
  final List<int> dailyBalancesMinor;

  const HorizonCashflowProjection({
    required this.horizonDays,
    required this.startingLiquidMinor,
    required this.projectedInflowMinor,
    required this.projectedScheduledOutflowMinor,
    required this.projectedVariableSpendMinor,
    required this.abnormalBufferMinor,
    required this.projectedEndingBalanceMinor,
    required this.lowestBalanceMinor,
    this.firstShortfallDate,
    required this.dailyBalancesMinor,
  });

  bool get hasShortfallRisk => lowestBalanceMinor < 0;

  @override
  List<Object?> get props => [
    horizonDays,
    startingLiquidMinor,
    projectedInflowMinor,
    projectedScheduledOutflowMinor,
    projectedVariableSpendMinor,
    abnormalBufferMinor,
    projectedEndingBalanceMinor,
    lowestBalanceMinor,
    firstShortfallDate,
    dailyBalancesMinor,
  ];
}

class SmartFinancialPlanReport extends Equatable {
  final HorizonCashflowProjection forecast7d;
  final HorizonCashflowProjection forecast30d;
  final HorizonCashflowProjection forecast90d;
  final int safeDailySpendMinor;
  final double emergencyRunwayMonths;
  final int recommendedEmergencyTargetMinor;
  final List<String> heavyBillMonthKeys;
  final List<DebtObligationItem> avalanchePayoffOrder;
  final List<DebtObligationItem> snowballPayoffOrder;
  final int simulatedNetMonthlySurplusMinor;
  final String formulaDisclosureVi;

  const SmartFinancialPlanReport({
    required this.forecast7d,
    required this.forecast30d,
    required this.forecast90d,
    required this.safeDailySpendMinor,
    required this.emergencyRunwayMonths,
    required this.recommendedEmergencyTargetMinor,
    required this.heavyBillMonthKeys,
    required this.avalanchePayoffOrder,
    required this.snowballPayoffOrder,
    required this.simulatedNetMonthlySurplusMinor,
    required this.formulaDisclosureVi,
  });

  @override
  List<Object?> get props => [
    forecast7d,
    forecast30d,
    forecast90d,
    safeDailySpendMinor,
    emergencyRunwayMonths,
    recommendedEmergencyTargetMinor,
    heavyBillMonthKeys,
    avalanchePayoffOrder,
    snowballPayoffOrder,
    simulatedNetMonthlySurplusMinor,
    formulaDisclosureVi,
  ];
}

/// Transparent, Assumption-Adjustable Personal Financial Planning & 7/30/90d Cashflow Forecast Engine (Section 23).
/// Never presents projections as guaranteed outcomes; exposes transparent assumptions and formula disclosure.
abstract final class CashflowForecastEngine {
  static SmartFinancialPlanReport buildPlan({
    required DateTime referenceDate,
    required int currentLiquidBalanceMinor,
    required int emergencySavingsMinor,
    required int baselineMonthlyIncomeMinor,
    required int observedDailyVariableSpendMinor,
    List<ScheduledCashflowItem> scheduledItems = const <ScheduledCashflowItem>[],
    List<DebtObligationItem> debts = const <DebtObligationItem>[],
    double incomeChangeDeltaPct = 0.0,
    double abnormalContingencyPct = 8.0,
  }) {
    final startDay = DateTime(
      referenceDate.year,
      referenceDate.month,
      referenceDate.day,
    );
    final adjustedMonthlyIncome = math.max(
      0,
      (baselineMonthlyIncomeMinor * (1.0 + incomeChangeDeltaPct / 100.0))
          .round(),
    );
    final clampedContingency = abnormalContingencyPct.clamp(0.0, 40.0);

    final f7 = _simulateHorizon(
      startDay: startDay,
      horizonDays: 7,
      startingLiquidMinor: currentLiquidBalanceMinor,
      adjustedMonthlyIncomeMinor: adjustedMonthlyIncome,
      dailyVariableSpendMinor: observedDailyVariableSpendMinor,
      scheduledItems: scheduledItems,
      debts: debts,
      abnormalContingencyPct: clampedContingency,
    );
    final f30 = _simulateHorizon(
      startDay: startDay,
      horizonDays: 30,
      startingLiquidMinor: currentLiquidBalanceMinor,
      adjustedMonthlyIncomeMinor: adjustedMonthlyIncome,
      dailyVariableSpendMinor: observedDailyVariableSpendMinor,
      scheduledItems: scheduledItems,
      debts: debts,
      abnormalContingencyPct: clampedContingency,
    );
    final f90 = _simulateHorizon(
      startDay: startDay,
      horizonDays: 90,
      startingLiquidMinor: currentLiquidBalanceMinor,
      adjustedMonthlyIncomeMinor: adjustedMonthlyIncome,
      dailyVariableSpendMinor: observedDailyVariableSpendMinor,
      scheduledItems: scheduledItems,
      debts: debts,
      abnormalContingencyPct: clampedContingency,
    );

    final monthlyScheduledOutflow = f30.projectedScheduledOutflowMinor;
    final monthlyVariableOutflow = observedDailyVariableSpendMinor * 30;
    final monthlyCoreBurn = math.max(
      1,
      monthlyScheduledOutflow + monthlyVariableOutflow,
    );
    final totalEmergencyPool =
        math.max(0, currentLiquidBalanceMinor) + math.max(0, emergencySavingsMinor);
    final runwayMonths = totalEmergencyPool / monthlyCoreBurn;
    final recommendedEmergencyMinor = monthlyCoreBurn * 6;

    // Safe Daily Spend over remaining days in current month (reserving 15% savings + scheduled bills)
    final daysInMonth = DateTime(startDay.year, startDay.month + 1, 0).day;
    final remainingDaysInMonth = math.max(1, daysInMonth - startDay.day + 1);
    final savingsReserve = (adjustedMonthlyIncome * 15) ~/ 100;
    final freePool30d = math.max(
      0,
      math.max(adjustedMonthlyIncome, currentLiquidBalanceMinor) -
          monthlyScheduledOutflow -
          savingsReserve -
          f30.abnormalBufferMinor,
    );
    final safeDaily = freePool30d ~/ math.max(remainingDaysInMonth, 15);

    // Detect heavy-bill months over the next 12 months (> 1.25x median monthly scheduled outflow)
    final monthlyScheduledTotals = <String, int>{};
    for (var mOffset = 0; mOffset < 12; mOffset++) {
      final mStart = DateTime(startDay.year, startDay.month + mOffset, 1);
      final mEnd = DateTime(startDay.year, startDay.month + mOffset + 1, 1);
      final key =
          '${mStart.year}-${mStart.month.toString().padLeft(2, '0')}';
      var sum = 0;
      for (final item in scheduledItems) {
        if (item.isInflow) continue;
        sum += _occurrencesBetween(item, mStart, mEnd) * item.amountMinor;
      }
      monthlyScheduledTotals[key] = sum;
    }
    final sortedTotals = monthlyScheduledTotals.values.toList()..sort();
    final medianOutflow = sortedTotals.isEmpty
        ? 0
        : sortedTotals[sortedTotals.length ~/ 2];
    final heavyMonths = <String>[
      for (final e in monthlyScheduledTotals.entries)
        if (medianOutflow > 0 && e.value >= (medianOutflow * 1.25).round())
          e.key,
    ];

    final avalanche = List<DebtObligationItem>.from(debts)
      ..sort((a, b) {
        final cmp = b.annualInterestPct.compareTo(a.annualInterestPct);
        return cmp != 0 ? cmp : a.balanceMinor.compareTo(b.balanceMinor);
      });
    final snowball = List<DebtObligationItem>.from(debts)
      ..sort((a, b) {
        final cmp = a.balanceMinor.compareTo(b.balanceMinor);
        return cmp != 0
            ? cmp
            : b.annualInterestPct.compareTo(a.annualInterestPct);
      });

    final netMonthlySurplus =
        adjustedMonthlyIncome - monthlyScheduledOutflow - monthlyVariableOutflow;

    return SmartFinancialPlanReport(
      forecast7d: f7,
      forecast30d: f30,
      forecast90d: f90,
      safeDailySpendMinor: safeDaily,
      emergencyRunwayMonths: double.parse(runwayMonths.toStringAsFixed(1)),
      recommendedEmergencyTargetMinor: recommendedEmergencyMinor,
      heavyBillMonthKeys: heavyMonths,
      avalanchePayoffOrder: avalanche,
      snowballPayoffOrder: snowball,
      simulatedNetMonthlySurplusMinor: netMonthlySurplus,
      formulaDisclosureVi:
          'Dự báo ước tính dựa trên giả định: Số dư cuối kỳ = Số dư thanh khoản đầu kỳ + Thu nhập dự kiến (${incomeChangeDeltaPct >= 0 ? "+" : ""}${incomeChangeDeltaPct.toStringAsFixed(0)}%) - Hóa đơn định kỳ & trả nợ - Chi tiêu biến đổi bình quân ngày - Đệm phát sinh (${clampedContingency.toStringAsFixed(0)}%). Số liệu mang tính tham khảo lập kế hoạch, không phải cam kết chắc chắn.',
    );
  }

  static SavingsGoalProgress evaluateSavingsGoal({
    required String id,
    required String name,
    required int currentSavedMinor,
    required int targetMinor,
    required int monthlyContributionMinor,
  }) {
    final remaining = math.max(0, targetMinor - currentSavedMinor);
    final safeMonthly = math.max(100000, monthlyContributionMinor);
    final months = remaining == 0 ? 0 : (remaining / safeMonthly).ceil();
    return SavingsGoalProgress(
      id: id,
      name: name,
      currentSavedMinor: currentSavedMinor,
      targetMinor: targetMinor,
      suggestedMonthlyContributionMinor: safeMonthly,
      estimatedMonthsToGoal: months,
    );
  }

  static HorizonCashflowProjection _simulateHorizon({
    required DateTime startDay,
    required int horizonDays,
    required int startingLiquidMinor,
    required int adjustedMonthlyIncomeMinor,
    required int dailyVariableSpendMinor,
    required List<ScheduledCashflowItem> scheduledItems,
    required List<DebtObligationItem> debts,
    required double abnormalContingencyPct,
  }) {
    var running = startingLiquidMinor;
    var lowest = startingLiquidMinor;
    DateTime? shortfallDate;
    var totalInflow = 0;
    var totalScheduledOut = 0;
    var totalVariableOut = 0;
    final dailySeries = <int>[];

    final hasExplicitSalaryItem = scheduledItems.any((e) => e.isInflow);
    final totalDebtMinMonthly = debts.fold<int>(
      0,
      (s, d) => s + d.minimumMonthlyPaymentMinor,
    );

    for (var d = 0; d < horizonDays; d++) {
      final curDate = startDay.add(Duration(days: d));
      final nextDate = curDate.add(const Duration(days: 1));
      var dayIn = 0;
      var daySchedOut = 0;

      for (final item in scheduledItems) {
        final hits = _occurrencesBetween(item, curDate, nextDate);
        if (hits > 0) {
          if (item.isInflow) {
            dayIn += hits * item.amountMinor;
          } else {
            daySchedOut += hits * item.amountMinor;
          }
        }
      }

      // Assume monthly salary lands on the 5th if no explicit inflow schedule was supplied
      if (!hasExplicitSalaryItem &&
          adjustedMonthlyIncomeMinor > 0 &&
          curDate.day == 5) {
        dayIn += adjustedMonthlyIncomeMinor;
      }
      // Assume debt minimum payment lands on the 15th
      if (totalDebtMinMonthly > 0 && curDate.day == 15) {
        daySchedOut += totalDebtMinMonthly;
      }

      totalInflow += dayIn;
      totalScheduledOut += daySchedOut;
      totalVariableOut += dailyVariableSpendMinor;
      running = running + dayIn - daySchedOut - dailyVariableSpendMinor;
      dailySeries.add(running);

      if (running < lowest) {
        lowest = running;
      }
      if (running < 0 && shortfallDate == null) {
        shortfallDate = curDate;
      }
    }

    final abnormalBuffer =
        ((totalVariableOut + totalScheduledOut) * abnormalContingencyPct / 100.0)
            .round();
    final endingWithBuffer = running - abnormalBuffer;
    if (endingWithBuffer < lowest) {
      lowest = endingWithBuffer;
    }

    return HorizonCashflowProjection(
      horizonDays: horizonDays,
      startingLiquidMinor: startingLiquidMinor,
      projectedInflowMinor: totalInflow,
      projectedScheduledOutflowMinor: totalScheduledOut,
      projectedVariableSpendMinor: totalVariableOut,
      abnormalBufferMinor: abnormalBuffer,
      projectedEndingBalanceMinor: endingWithBuffer,
      lowestBalanceMinor: lowest,
      firstShortfallDate: shortfallDate,
      dailyBalancesMinor: dailySeries,
    );
  }

  static int _occurrencesBetween(
    ScheduledCashflowItem item,
    DateTime windowStart,
    DateTime windowEndExclusive,
  ) {
    final anchor = DateTime(
      item.dueDate.year,
      item.dueDate.month,
      item.dueDate.day,
    );
    if (item.cycleDays <= 0) {
      return (!anchor.isBefore(windowStart) &&
              anchor.isBefore(windowEndExclusive))
          ? 1
          : 0;
    }
    if (item.cycleDays == 30) {
      var count = 0;
      var cursor = DateTime(windowStart.year, windowStart.month, 1);
      while (cursor.isBefore(windowEndExclusive)) {
        final maxDay = DateTime(cursor.year, cursor.month + 1, 0).day;
        final occurrence = DateTime(
          cursor.year,
          cursor.month,
          math.min(anchor.day, maxDay),
        );
        if (!occurrence.isBefore(anchor) &&
            !occurrence.isBefore(windowStart) &&
            occurrence.isBefore(windowEndExclusive)) {
          count++;
        }
        cursor = DateTime(cursor.year, cursor.month + 1, 1);
      }
      return count;
    }
    var cur = anchor;
    if (cur.isBefore(windowStart)) {
      final diffDays = windowStart.difference(cur).inDays;
      final jumps = diffDays ~/ item.cycleDays;
      cur = cur.add(Duration(days: jumps * item.cycleDays));
      while (cur.isBefore(windowStart)) {
        cur = cur.add(Duration(days: item.cycleDays));
      }
    }
    var hits = 0;
    while (cur.isBefore(windowEndExclusive)) {
      hits++;
      cur = cur.add(Duration(days: item.cycleDays));
    }
    return hits;
  }
}
