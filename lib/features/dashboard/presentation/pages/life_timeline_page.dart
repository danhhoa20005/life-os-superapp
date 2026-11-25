import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/utils/vnd_amount.dart';
import '../../../../core/widgets/lifeos_design_system.dart';
import '../../../budgets/presentation/bloc/budget_bloc.dart';
import '../../../calendar/presentation/bloc/calendar_bloc.dart';
import '../../../family/presentation/bloc/family_bloc.dart';
import '../../../tasks/presentation/bloc/task_bloc.dart';
import '../../../transactions/domain/entities/transaction_entities.dart';
import '../../../transactions/presentation/bloc/transaction_bloc.dart';
import '../../../vehicles/presentation/bloc/vehicle_bloc.dart';
import '../../domain/services/life_timeline_engine.dart';

T? _maybeWatchBloc<T extends StateStreamableSource<Object?>>(
  BuildContext context,
) {
  try {
    return BlocProvider.of<T>(context, listen: true);
  } catch (_) {
    return null;
  }
}

/// Unified read-only chronological Life Timeline aggregating live snapshots across
/// Finance, Calendar, Tasks, Vehicles/Bills, Family, and Goals without duplicating data.
class LifeTimelinePage extends StatefulWidget {
  final List<LifeTimelineEntry>? injectedEntries;

  const LifeTimelinePage({super.key, this.injectedEntries});

  @override
  State<LifeTimelinePage> createState() => _LifeTimelinePageState();
}

class _LifeTimelinePageState extends State<LifeTimelinePage> {
  final TextEditingController _searchCtrl = TextEditingController();
  LifeTimelineDomain? _selectedDomain;
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<LifeTimelineEntry> _collectLiveEntries(BuildContext context) {
    if (widget.injectedEntries != null) {
      return widget.injectedEntries!;
    }
    final now = DateTime.now();
    final entries = <LifeTimelineEntry>[];

    final txState = _maybeWatchBloc<TransactionListBloc>(context)?.state;
    if (txState != null) {
      for (final tx in txState.allTransactions.take(80)) {
        if (tx.kind == TransactionKind.reversal ||
            tx.verification == TransactionVerification.rejected) {
          continue;
        }
        final isCredit = tx.kind == TransactionKind.income;
        entries.add(
          LifeTimelineEntry(
            dedupKey: 'finance:${tx.id}',
            sourceId: tx.id,
            domain: LifeTimelineDomain.finance,
            timestamp: tx.occurredAt,
            title: tx.merchant.isNotEmpty ? tx.merchant : tx.categoryName,
            subtitle: '${tx.categoryName} · ${tx.walletName ?? "Ví cá nhân"}',
            amountMinor: tx.amountMinor,
            isCredit: isCredit,
            badgeLabel: isCredit ? 'Thu nhập' : 'Chi tiêu',
            targetRoute: '/finance',
          ),
        );
      }
    }

    final calState = _maybeWatchBloc<CalendarBloc>(context)?.state;
    if (calState != null) {
      for (final ev in calState.events.take(60)) {
        entries.add(
          LifeTimelineEntry(
            dedupKey: 'calendar:${ev.id}',
            sourceId: ev.id,
            domain: LifeTimelineDomain.calendar,
            timestamp: ev.startsAt,
            title: ev.title,
            subtitle: (ev.location ?? '').isNotEmpty
                ? ev.location!
                : (ev.isAllDay ? 'Sự kiện cả ngày' : 'Lịch trình'),
            badgeLabel: ev.startsAt.isAfter(now) ? 'Sắp diễn ra' : 'Lịch hẹn',
            targetRoute: '/planning',
            isUpcoming: ev.startsAt.isAfter(now),
          ),
        );
      }
    }

    final taskState = _maybeWatchBloc<TaskBloc>(context)?.state;
    if (taskState != null) {
      for (final task in taskState.tasks.take(60)) {
        final ts = task.dueAt ?? now;
        entries.add(
          LifeTimelineEntry(
            dedupKey: 'tasks:${task.id}',
            sourceId: task.id,
            domain: LifeTimelineDomain.tasks,
            timestamp: ts,
            title: task.title,
            subtitle: 'Phụ trách: ${task.assigneeName}',
            badgeLabel: task.status.name == 'done' ? 'Hoàn tất' : 'Công việc',
            targetRoute: '/tasks-board',
            isUpcoming: ts.isAfter(now),
          ),
        );
      }
    }

    final vehicleState = _maybeWatchBloc<VehicleBloc>(context)?.state;
    if (vehicleState != null) {
      for (final bill in vehicleState.bills.take(40)) {
        final due = bill.nextDueDate;
        entries.add(
          LifeTimelineEntry(
            dedupKey: 'bill:${bill.id}',
            sourceId: bill.id,
            domain: LifeTimelineDomain.vehiclesAndBills,
            timestamp: due,
            title: bill.title,
            subtitle:
                '${bill.providerName} · Hạn ${DateFormat('dd/MM/yyyy').format(due.toLocal())}',
            amountMinor: bill.estimatedAmountMinor,
            isCredit: false,
            badgeLabel: bill.hasAbnormalSpike ? 'Tăng bất thường' : 'Hóa đơn',
            targetRoute: '/assets',
            isUpcoming: due.isAfter(now),
          ),
        );
      }
      for (final veh in vehicleState.vehicles.take(20)) {
        entries.add(
          LifeTimelineEntry(
            dedupKey: 'vehicle:${veh.id}',
            sourceId: veh.id,
            domain: LifeTimelineDomain.vehiclesAndBills,
            timestamp: veh.lastServiceDate,
            title: '${veh.name} (${veh.plateNumber})',
            subtitle:
                'ODO hiện tại ${NumberFormat('#,##0', 'vi_VN').format(veh.currentOdometerKm)} km',
            badgeLabel: 'Bảo dưỡng xe',
            targetRoute: '/assets',
          ),
        );
      }
    }

    final familyState = _maybeWatchBloc<FamilyBloc>(context)?.state;
    if (familyState != null) {
      for (final bill in familyState.sharedBills.take(40)) {
        entries.add(
          LifeTimelineEntry(
            dedupKey: 'family_split:${bill.id}',
            sourceId: bill.id,
            domain: LifeTimelineDomain.family,
            timestamp: bill.createdAt,
            title: bill.title,
            subtitle: 'Chia nhóm · ${bill.paidByName} thanh toán',
            amountMinor: bill.totalAmountMinor,
            isCredit: false,
            badgeLabel: 'Chia tiền',
            targetRoute: '/family',
          ),
        );
      }
    }

    final budgetState = _maybeWatchBloc<BudgetBloc>(context)?.state;
    if (budgetState != null) {
      for (final fund in budgetState.funds.take(20)) {
        final latestTs = fund.recentContributions.isNotEmpty
            ? fund.recentContributions.first.createdAt
            : now;
        entries.add(
          LifeTimelineEntry(
            dedupKey: 'goal:${fund.id}',
            sourceId: fund.id,
            domain: LifeTimelineDomain.goals,
            timestamp: latestTs,
            title: fund.name,
            subtitle:
                'Số dư hiện tại ${VndAmount.format(fund.balanceMinor)} / Mục tiêu ${VndAmount.format(fund.targetAmountMinor)}',
            amountMinor: fund.balanceMinor,
            isCredit: true,
            badgeLabel: 'Quỹ & Mục tiêu',
            targetRoute: '/family-funds',
          ),
        );
      }
    }

    return entries;
  }

  LifeOsAccentTone _toneForDomain(LifeTimelineDomain domain) => switch (domain) {
    LifeTimelineDomain.finance => LifeOsAccentTone.emerald,
    LifeTimelineDomain.calendar => LifeOsAccentTone.blue,
    LifeTimelineDomain.tasks => LifeOsAccentTone.emerald,
    LifeTimelineDomain.vehiclesAndBills => LifeOsAccentTone.amber,
    LifeTimelineDomain.family => LifeOsAccentTone.purple,
    LifeTimelineDomain.goals => LifeOsAccentTone.emerald,
  };

  IconData _iconForDomain(LifeTimelineDomain domain) => switch (domain) {
    LifeTimelineDomain.finance => Icons.account_balance_wallet_rounded,
    LifeTimelineDomain.calendar => Icons.calendar_month_rounded,
    LifeTimelineDomain.tasks => Icons.task_alt_rounded,
    LifeTimelineDomain.vehiclesAndBills => Icons.two_wheeler_rounded,
    LifeTimelineDomain.family => Icons.groups_rounded,
    LifeTimelineDomain.goals => Icons.savings_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final raw = _collectLiveEntries(context);
    final filtered = LifeTimelineEngine.mergeAndFilter(
      rawEntries: raw,
      domainFilter: _selectedDomain,
      query: _query,
    );
    final groups = LifeTimelineEngine.groupByDay(filtered);
    final timeFmt = DateFormat('HH:mm');

    return Scaffold(
      body: LifeOsMintWaveCanvas(
        child: SafeArea(
          child: Column(
            children: [
              const LifeOsTopBrandHeader(
                title: 'Dòng thời gian Cuộc sống',
                showBackButton: true,
              ),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: AppSpacing.maxContentWidth,
                    ),
                    child: ListView(
                      key: const Key('life_timeline_list_view'),
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.md,
                        AppSpacing.xs,
                        AppSpacing.md,
                        AppSpacing.xxl,
                      ),
                      children: [
                        LifeOsSoftCard(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              TextField(
                                key: const Key('life_timeline_search_field'),
                                controller: _searchCtrl,
                                onChanged: (v) => setState(() => _query = v),
                                decoration: const InputDecoration(
                                  isDense: true,
                                  hintText:
                                      'Tìm giao dịch, lịch hẹn, việc nhà, xe, quỹ...',
                                  prefixIcon: Icon(
                                    Icons.search_rounded,
                                    size: 19,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  ChoiceChip(
                                    key: const Key('timeline_filter_all'),
                                    label: Text('Tất cả (${raw.length})'),
                                    selected: _selectedDomain == null,
                                    onSelected: (_) =>
                                        setState(() => _selectedDomain = null),
                                  ),
                                  for (final d in LifeTimelineDomain.values)
                                    ChoiceChip(
                                      key: Key('timeline_filter_${d.code}'),
                                      label: Text(d.labelVi),
                                      selected: _selectedDomain == d,
                                      onSelected: (_) => setState(
                                        () => _selectedDomain =
                                            _selectedDomain == d ? null : d,
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (groups.isEmpty)
                          LifeOsSoftCard(
                            child: Column(
                              children: [
                                Icon(
                                  Icons.timeline_rounded,
                                  size: 38,
                                  color: c.primary,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Chưa có hoạt động nào khớp bộ lọc',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w800,
                                    color: c.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Mọi giao dịch, lịch hẹn, việc làm, hóa đơn và quỹ gia đình sẽ tự động hội tụ tại đây theo thời gian thực.',
                                  textAlign: TextAlign.center,
                                  softWrap: true,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: c.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          for (final group in groups) ...[
                            Padding(
                              padding: const EdgeInsets.only(
                                top: 6,
                                bottom: 6,
                                left: 4,
                              ),
                              child: Text(
                                '${group.labelVi} · ${group.entries.length} mục',
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w800,
                                  color: c.textPrimary,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ),
                            for (final item in group.entries)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: LifeOsSoftCard(
                                  onTap: () {
                                    final router = GoRouter.maybeOf(context);
                                    if (router != null) {
                                      context.push(item.targetRoute);
                                    }
                                  },
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      LifeOsIconSquircle(
                                        icon: _iconForDomain(item.domain),
                                        tone: _toneForDomain(item.domain),
                                        size: 38,
                                        iconSize: 19,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Wrap(
                                              spacing: 6,
                                              runSpacing: 4,
                                              crossAxisAlignment:
                                                  WrapCrossAlignment.center,
                                              children: [
                                                LifeOsStatusPill(
                                                  label: item.badgeLabel,
                                                  tone: _toneForDomain(
                                                    item.domain,
                                                  ),
                                                ),
                                                Text(
                                                  timeFmt.format(
                                                    item.timestamp.toLocal(),
                                                  ),
                                                  style: TextStyle(
                                                    fontSize: 11.5,
                                                    color: c.textSecondary,
                                                    fontFeatures: const [
                                                      FontFeature.tabularFigures(),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 5),
                                            Text(
                                              item.title,
                                              softWrap: true,
                                              style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w800,
                                                color: c.textPrimary,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              item.subtitle,
                                              softWrap: true,
                                              style: TextStyle(
                                                fontSize: 12.2,
                                                color: c.textSecondary,
                                              ),
                                            ),
                                            if (item.amountMinor != null) ...[
                                              const SizedBox(height: 4),
                                              Text(
                                                '${item.isCredit == true ? '+' : '-'}${VndAmount.format(item.amountMinor!)}',
                                                style: TextStyle(
                                                  fontSize: 13.5,
                                                  fontWeight: FontWeight.w800,
                                                  color: item.isCredit == true
                                                      ? c.primary
                                                      : c.error,
                                                  fontFeatures: const [
                                                    FontFeature.tabularFigures(),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
