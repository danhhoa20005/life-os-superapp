import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../core/utils/vnd_amount.dart';
import '../../../../core/widgets/lifeos_design_system.dart';
import '../../../budgets/domain/services/cashflow_forecast_engine.dart';
import '../../../vehicles/domain/entities/vehicle_entities.dart';
import '../../domain/entities/transaction_entities.dart';

/// Transparent 7 / 30 / 90-day Cashflow Forecast & Financial Planning Card (Section 23).
/// Computes projections from confirmed ledger balances, recurring bills, and adjustable
/// user assumptions without ever disguising projections as guaranteed outcomes.
class CashflowForecastPlanCard extends StatefulWidget {
  final List<WalletEntity> wallets;
  final List<TransactionEntity> transactions;
  final List<RecurringBillEntity> recurringBills;
  final bool obscureBalances;
  final DateTime? referenceDate;

  const CashflowForecastPlanCard({
    super.key,
    required this.wallets,
    required this.transactions,
    this.recurringBills = const <RecurringBillEntity>[],
    this.obscureBalances = false,
    this.referenceDate,
  });

  @override
  State<CashflowForecastPlanCard> createState() =>
      _CashflowForecastPlanCardState();
}

class _CashflowForecastPlanCardState extends State<CashflowForecastPlanCard> {
  static final DateFormat _dateFmt = DateFormat('dd/MM/yyyy');

  int _horizonDays = 30;
  double _incomeDeltaPct = 0.0;
  double _contingencyPct = 8.0;

  List<WalletEntity>? _lastWallets;
  List<TransactionEntity>? _lastTransactions;
  List<RecurringBillEntity>? _lastBills;
  int? _lastRefDayKey;
  double? _lastIncomeDelta;
  double? _lastContingency;
  SmartFinancialPlanReport? _cachedPlan;

  SmartFinancialPlanReport _resolvePlan(DateTime refNow) {
    final dayKey = refNow.year * 10000 + refNow.month * 100 + refNow.day;
    final cached = _cachedPlan;
    if (cached != null &&
        identical(_lastWallets, widget.wallets) &&
        identical(_lastTransactions, widget.transactions) &&
        identical(_lastBills, widget.recurringBills) &&
        _lastRefDayKey == dayKey &&
        _lastIncomeDelta == _incomeDeltaPct &&
        _lastContingency == _contingencyPct) {
      return cached;
    }

    var liquidMinor = 0;
    var savingsMinor = 0;
    final debts = <DebtObligationItem>[];

    for (final w in widget.wallets) {
      if (w.type == WalletType.savings) {
        savingsMinor += w.balanceMinor;
      } else if (w.type == WalletType.creditCard && w.balanceMinor < 0) {
        final owed = -w.balanceMinor;
        debts.add(
          DebtObligationItem(
            id: w.id,
            name: w.name,
            balanceMinor: owed,
            annualInterestPct: 24.0,
            minimumMonthlyPaymentMinor: (owed * 5) ~/ 100,
          ),
        );
      } else {
        liquidMinor += w.balanceMinor;
      }
    }

    var confirmedIncome = 0;
    var confirmedExpense = 0;
    for (final tx in widget.transactions) {
      if (!tx.isConfirmedInLedger || tx.isReversed) continue;
      if (tx.kind == TransactionKind.income) {
        confirmedIncome += tx.amountMinor;
      } else if (tx.kind == TransactionKind.expense) {
        confirmedExpense += tx.amountMinor;
      }
    }

    final observedDays = refNow.day.clamp(1, 31);
    final dailyVarSpend = confirmedExpense > 0
        ? (confirmedExpense ~/ observedDays)
        : 0;

    final scheduled = <ScheduledCashflowItem>[
      for (final b in widget.recurringBills)
        ScheduledCashflowItem(
          id: b.id,
          title: b.title,
          amountMinor: b.estimatedAmountMinor,
          dueDate: b.nextDueDate,
          cycleDays: 30,
        ),
    ];

    final plan = CashflowForecastEngine.buildPlan(
      referenceDate: refNow,
      currentLiquidBalanceMinor: liquidMinor,
      emergencySavingsMinor: savingsMinor,
      baselineMonthlyIncomeMinor: confirmedIncome,
      observedDailyVariableSpendMinor: dailyVarSpend,
      scheduledItems: scheduled,
      debts: debts,
      incomeChangeDeltaPct: _incomeDeltaPct,
      abnormalContingencyPct: _contingencyPct,
    );

    _lastWallets = widget.wallets;
    _lastTransactions = widget.transactions;
    _lastBills = widget.recurringBills;
    _lastRefDayKey = dayKey;
    _lastIncomeDelta = _incomeDeltaPct;
    _lastContingency = _contingencyPct;
    _cachedPlan = plan;
    return plan;
  }

  String _fmt(int minor, {bool showSign = false}) {
    if (widget.obscureBalances) return '•••••• ₫';
    if (showSign && minor > 0) return '+${VndAmount.format(minor)}';
    return VndAmount.format(minor);
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final refNow = widget.referenceDate ?? DateTime.now();
    final plan = _resolvePlan(refNow);

    final activeProj = switch (_horizonDays) {
      7 => plan.forecast7d,
      90 => plan.forecast90d,
      _ => plan.forecast30d,
    };

    return LifeOsSoftCard(
      key: const Key('cashflow_forecast_plan_card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
                    icon: Icons.timeline_rounded,
                    tone: LifeOsAccentTone.emerald,
                    size: 32,
                    iconSize: 17,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Dự báo Dòng tiền 7 · 30 · 90 ngày',
                      softWrap: true,
                      style: TextStyle(
                        fontSize: 14.8,
                        fontWeight: FontWeight.w800,
                        color: c.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              LifeOsStatusPill(
                icon: activeProj.hasShortfallRisk
                    ? Icons.warning_amber_rounded
                    : Icons.verified_outlined,
                label: activeProj.hasShortfallRisk
                    ? 'Có nguy cơ thiếu hụt'
                    : 'Dòng tiền ổn định',
                tone: activeProj.hasShortfallRisk
                    ? LifeOsAccentTone.coral
                    : LifeOsAccentTone.emerald,
              ),
            ],
          ),
          const SizedBox(height: 10),
          LifeOsSegmentedPills<int>(
            selected: _horizonDays,
            options: const [
              (7, '7 ngày', null),
              (30, '30 ngày', null),
              (90, '90 ngày', null),
            ],
            onChanged: (v) => setState(() => _horizonDays = v),
          ),
          const SizedBox(height: 12),
          IntrinsicHeight(
            child: Row(
              children: [
                Expanded(
                  child: _ForecastMetricCell(
                    label: 'Số dư dự kiến cuối kỳ',
                    value: _fmt(activeProj.projectedEndingBalanceMinor),
                    valueColor: activeProj.projectedEndingBalanceMinor < 0
                        ? c.error
                        : c.primary,
                  ),
                ),
                VerticalDivider(width: 16, color: c.separator),
                Expanded(
                  child: _ForecastMetricCell(
                    label: 'Hạn mức an toàn / ngày',
                    value: _fmt(plan.safeDailySpendMinor),
                    valueColor: c.textPrimary,
                  ),
                ),
                VerticalDivider(width: 16, color: c.separator),
                Expanded(
                  child: _ForecastMetricCell(
                    label: 'Quỹ dự phòng',
                    value:
                        '${plan.emergencyRunwayMonths.toStringAsFixed(1)} tháng',
                    valueColor: plan.emergencyRunwayMonths >= 3.0
                        ? c.success
                        : const Color(0xFFD97706),
                  ),
                ),
              ],
            ),
          ),
          if (activeProj.hasShortfallRisk &&
              activeProj.firstShortfallDate != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: c.error.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: c.error.withValues(alpha: 0.35)),
              ),
              child: Text(
                'Cảnh báo: Số dư khả dụng dự kiến âm vào ngày ${_dateFmt.format(activeProj.firstShortfallDate!)} (mức thấp nhất ${_fmt(activeProj.lowestBalanceMinor)}).',
                softWrap: true,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: c.error,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          LifeOsDetailsDiscloseSection(
            toggleKey: const Key('cashflow_forecast_assumptions_toggle'),
            label: 'Điều chỉnh giả định & Công thức',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Biến động thu nhập giả định: ${_incomeDeltaPct >= 0 ? "+" : ""}${_incomeDeltaPct.round()}%',
                  style: TextStyle(
                    fontSize: 12.2,
                    fontWeight: FontWeight.w700,
                    color: c.textPrimary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                Slider(
                  key: const Key('forecast_income_delta_slider'),
                  value: _incomeDeltaPct,
                  min: -40,
                  max: 40,
                  divisions: 16,
                  onChanged: (v) => setState(() => _incomeDeltaPct = v),
                ),
                Text(
                  'Đệm dự phòng phát sinh bất thường: ${_contingencyPct.round()}%',
                  style: TextStyle(
                    fontSize: 12.2,
                    fontWeight: FontWeight.w700,
                    color: c.textPrimary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                Slider(
                  key: const Key('forecast_contingency_slider'),
                  value: _contingencyPct,
                  min: 0,
                  max: 25,
                  divisions: 5,
                  onChanged: (v) => setState(() => _contingencyPct = v),
                ),
                Text(
                  plan.formulaDisclosureVi,
                  softWrap: true,
                  style: TextStyle(
                    fontSize: 11.4,
                    height: 1.35,
                    color: c.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ForecastMetricCell extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;

  const _ForecastMetricCell({
    required this.label,
    required this.value,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          softWrap: true,
          style: TextStyle(fontSize: 11.2, color: c.textSecondary),
        ),
        const SizedBox(height: 3),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
              color: valueColor,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}
