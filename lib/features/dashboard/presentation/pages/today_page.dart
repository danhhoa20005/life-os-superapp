import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/constants/app_assets.dart';
import '../../../../core/utils/user_behavior_prefs.dart';
import '../../../../core/utils/vnd_amount.dart';
import '../../../../core/widgets/lifeos_design_system.dart';
import '../../../../core/widgets/pro_max_widgets.dart';
import '../../../../core/widgets/status_widgets.dart';
import '../../../../core/widgets/voice_smart_capture_sheet.dart';
import '../../../app_update/presentation/widgets/app_update_widgets.dart';
import '../../../authentication/presentation/bloc/auth_bloc.dart';
import '../../../budgets/presentation/bloc/budget_bloc.dart';
import '../../../calendar/domain/entities/calendar_entities.dart';
import '../../../calendar/presentation/bloc/calendar_bloc.dart';
import '../../../daily_life/domain/entities/daily_life_entities.dart';
import '../../../daily_life/presentation/bloc/daily_life_bloc.dart';
import '../../../family/presentation/bloc/family_bloc.dart';
import '../../../notifications/presentation/bloc/notification_ingestion_bloc.dart';
import '../../../tasks/domain/entities/task_entities.dart';
import '../../../tasks/domain/repositories/task_repository.dart';
import '../../../tasks/presentation/bloc/task_bloc.dart';
import '../../../transactions/domain/entities/transaction_entities.dart';
import '../../../transactions/presentation/bloc/transaction_bloc.dart';
import '../../../transactions/presentation/bloc/transaction_event.dart';
import '../../../transactions/presentation/bloc/transaction_state.dart';
import '../../../vehicles/domain/entities/vehicle_entities.dart';
import '../../../vehicles/presentation/bloc/vehicle_bloc.dart';
import '../../domain/entities/dashboard_entities.dart';
import '../bloc/dashboard_bloc.dart';

class _ShortcutSpec {
  final String id;
  final String label;
  final IconData icon;
  final LifeOsAccentTone tone;
  final String route;
  final Key? tileKey;

  const _ShortcutSpec({
    required this.id,
    required this.label,
    required this.icon,
    required this.tone,
    required this.route,
    this.tileKey,
  });
}

class _InboxActionItem {
  final IconData icon;
  final LifeOsAccentTone tone;
  final String title;
  final String subtitle;
  final String badge;
  final VoidCallback onTap;
  final String? quickActionLabel;
  final VoidCallback? onQuickAction;
  final bool isQuickActionBusy;

  const _InboxActionItem({
    required this.icon,
    required this.tone,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.onTap,
    this.quickActionLabel,
    this.onQuickAction,
    this.isQuickActionBusy = false,
  });
}

/// Screen 01: Flagship UI/UX Pro Max Redesigned "Hôm nay" (`TodayPage`) —
/// Emerald Mesh Fintech Hero Card + Privacy Masking + 3-Tile Daily Pulse Bento +
/// Unified `LifeOS Inbox` + Honest Budget/Fund Bento + Customizable 4×2 Pinned Dock.
class TodayPage extends StatefulWidget {
  const TodayPage({super.key});

  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> {
  bool _showAllInbox = false;
  static const List<_ShortcutSpec> _allShortcuts = [
    _ShortcutSpec(
      id: 'bank_qr',
      label: 'Ngân hàng & QR',
      icon: Icons.qr_code_2_rounded,
      tone: LifeOsAccentTone.emerald,
      route: '/notifications-privacy',
    ),
    _ShortcutSpec(
      id: 'vehicles',
      label: 'Xe máy',
      icon: Icons.two_wheeler_rounded,
      tone: LifeOsAccentTone.emerald,
      route: '/assets',
    ),
    _ShortcutSpec(
      id: 'health',
      label: 'Sức khỏe',
      icon: Icons.favorite_outline_rounded,
      tone: LifeOsAccentTone.coral,
      route: '/health-hub',
      tileKey: Key('home_tile_health'),
    ),
    _ShortcutSpec(
      id: 'kitchen',
      label: 'Bếp & Đi chợ',
      icon: Icons.shopping_basket_outlined,
      tone: LifeOsAccentTone.emerald,
      route: '/kitchen-groceries',
      tileKey: Key('home_tile_kitchen'),
    ),
    _ShortcutSpec(
      id: 'evn',
      label: 'Điện nước',
      icon: Icons.electric_bolt_rounded,
      tone: LifeOsAccentTone.amber,
      route: '/home-living',
      tileKey: Key('home_tile_evn'),
    ),
    _ShortcutSpec(
      id: 'documents',
      label: 'Tài liệu',
      icon: Icons.folder_open_rounded,
      tone: LifeOsAccentTone.amber,
      route: '/family-documents',
    ),
    _ShortcutSpec(
      id: 'notes_salary',
      label: 'Lương & Thuế',
      icon: Icons.request_quote_outlined,
      tone: LifeOsAccentTone.purple,
      route: '/smart-notes-hub',
    ),
    _ShortcutSpec(
      id: 'settings',
      label: 'Cài đặt',
      icon: Icons.settings_outlined,
      tone: LifeOsAccentTone.neutral,
      route: '/settings-hub',
    ),
    _ShortcutSpec(
      id: 'habits',
      label: 'Thói quen',
      icon: Icons.local_fire_department_outlined,
      tone: LifeOsAccentTone.amber,
      route: '/habits-focus',
    ),
    _ShortcutSpec(
      id: 'wealth',
      label: 'Lãi vay & Bill',
      icon: Icons.calculate_outlined,
      tone: LifeOsAccentTone.blue,
      route: '/wealth-tools',
    ),
    _ShortcutSpec(
      id: 'widgets',
      label: 'Widget màn hình',
      icon: Icons.widgets_outlined,
      tone: LifeOsAccentTone.purple,
      route: '/home-widgets',
    ),
    _ShortcutSpec(
      id: 'gemini_ai',
      label: 'Ghi thông minh',
      icon: Icons.bolt_rounded,
      tone: LifeOsAccentTone.emerald,
      route: '/financial-ai',
      tileKey: Key('home_tile_gemini_ai'),
    ),
  ];

  final Set<String> _pinnedIds = <String>{
    'bank_qr',
    'vehicles',
    'health',
    'kitchen',
    'evn',
    'documents',
    'notes_salary',
    'settings',
  };

  bool _hideBalances = false;
  bool _isSyncingHideBalances = false;
  final Set<String> _approvingProvisionalIds = <String>{};

  @override
  void initState() {
    super.initState();
    _hydrateUserPrefs();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final isTickerEnabled = TickerMode.valuesOf(context).enabled;
    final isCurrentRoute = ModalRoute.isCurrentOf(context) ?? true;
    if (isTickerEnabled && isCurrentRoute) {
      _syncHideBalancesFromPrefs();
    }
  }

  @override
  void didUpdateWidget(covariant TodayPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncHideBalancesFromPrefs();
  }

  void _syncHideBalancesFromPrefs() {
    if (_isSyncingHideBalances) return;
    _isSyncingHideBalances = true;
    UserBehaviorPrefs.loadHideBalances().then((savedHide) {
      _isSyncingHideBalances = false;
      if (!mounted || savedHide == _hideBalances) return;
      setState(() => _hideBalances = savedHide);
    });
  }

  Future<void> _hydrateUserPrefs() async {
    await UserBehaviorPrefs.loadLastWalletId();
    await UserBehaviorPrefs.loadHabitShortcuts();
    final savedPinned = await UserBehaviorPrefs.loadPinnedShortcuts();
    final savedHide = await UserBehaviorPrefs.loadHideBalances();
    if (!mounted) return;
    setState(() {
      if (savedPinned != null) {
        _pinnedIds
          ..clear()
          ..addAll(savedPinned);
      }
      _hideBalances = savedHide;
    });
  }

  Future<void> _approveProvisionalTx(
    BuildContext context, {
    required String userId,
    required TransactionEntity tx,
  }) async {
    if (_approvingProvisionalIds.contains(tx.id)) return;
    final actionBloc = context.read<TransactionActionBloc>();
    if (actionBloc.state.status == ActionStatus.submitting) return;

    setState(() => _approvingProvisionalIds.add(tx.id));
    try {
      final waiter = actionBloc.stream
          .firstWhere(
            (s) =>
                s.status == ActionStatus.success ||
                s.status == ActionStatus.failure,
          )
          .timeout(
            const Duration(seconds: 8),
            onTimeout: () =>
                const TransactionActionState(status: ActionStatus.failure),
          );
      actionBloc.add(
        ProvisionalTransactionDecisionSubmitted(
          userId: userId,
          transactionId: tx.id,
          approve: true,
        ),
      );
      final outcome = await waiter;
      if (!mounted) return;
      if (outcome.status == ActionStatus.success) {
        LifeOsTopToast.show(
          this.context,
          outcome.successMessage ?? 'Đã duyệt giao dịch ${tx.merchant}.',
          kind: LifeOsToastKind.success,
        );
      } else {
        LifeOsTopToast.show(
          this.context,
          outcome.failure?.message ??
              'Không thể duyệt giao dịch ${tx.merchant} — vui lòng thử lại.',
          kind: LifeOsToastKind.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _approvingProvisionalIds.remove(tx.id));
      } else {
        _approvingProvisionalIds.remove(tx.id);
      }
    }
  }

  String _fmtMoney(int minor, {String prefix = ''}) {
    if (_hideBalances) return '$prefix•••••••• ₫';
    return '$prefix${VndAmount.format(minor)}';
  }

  static String _weekdayVi(int weekday) => switch (weekday) {
    DateTime.monday => 'Hai',
    DateTime.tuesday => 'Ba',
    DateTime.wednesday => 'Tư',
    DateTime.thursday => 'Năm',
    DateTime.friday => 'Sáu',
    DateTime.saturday => 'Bảy',
    _ => 'Chủ nhật',
  };

  static String _formatDateVi(DateTime dt) {
    if (dt.weekday == DateTime.sunday) {
      return 'Chủ nhật, ${dt.day} tháng ${dt.month}';
    }
    return 'Thứ ${_weekdayVi(dt.weekday)}, ${dt.day} tháng ${dt.month}';
  }

  void _showCustomizeShortcutsSheet(BuildContext context) {
    final c = TammySemanticColors.of(context);
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (ctx, setModal) => Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ghim tiện ích yêu thích trên Trang chủ',
                  style: TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w800,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _allShortcuts.map((item) {
                    final selected = _pinnedIds.contains(item.id);
                    return FilterChip(
                      selected: selected,
                      avatar: LifeOsIconSquircle(
                        icon: item.icon,
                        tone: item.tone,
                        size: 22,
                        iconSize: 13,
                      ),
                      label: Text(item.label),
                      onSelected: (val) {
                        if (!val && _pinnedIds.length <= 4) {
                          LifeOsTopToast.show(
                            ctx,
                            'Vui lòng giữ tối thiểu 4 tiện ích trên Trang chủ.',
                            kind: LifeOsToastKind.warning,
                          );
                          return;
                        }
                        setState(() {
                          if (val) {
                            _pinnedIds.add(item.id);
                          } else {
                            _pinnedIds.remove(item.id);
                          }
                        });
                        UserBehaviorPrefs.savePinnedShortcuts(_pinnedIds);
                        setModal(() {});
                      },
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final user = context.select((AuthBloc b) => b.state.user);
    final calEvents = context.select((CalendarBloc b) => b.state.events);
    final gcalConnected = context.select(
      (CalendarBloc b) => b.state.isGoogleAuthorized,
    );
    final allTasks = context.select((TaskBloc b) => b.state.tasks);
    final budgets = context.select((BudgetBloc b) => b.state.budgets);
    final activeFamily = context.select(
      (FamilyBloc b) => b.state.activeFamily,
    );
    final allTransactions = context.select(
      (TransactionListBloc b) => b.state.allTransactions,
    );
    final isTxActionSubmitting = context.select(
      (TransactionActionBloc b) => b.state.status == ActionStatus.submitting,
    );
    final vehicles = context.select((VehicleBloc b) => b.state.vehicles);
    final bills = context.select((VehicleBloc b) => b.state.bills);
    final bankConnected = context.select(
      (NotificationIngestionBloc b) =>
          (b.state.consent?.enabled ?? false) ||
          b.state.linkedBankAccounts.isNotEmpty,
    );
    DailyLifeBloc? dailyBloc;
    var dailySnap = DailyLifeSnapshot.empty;
    try {
      dailyBloc = context.watch<DailyLifeBloc>();
      dailySnap = dailyBloc.state.snapshot;
    } catch (_) {}

    final firstName = (user?.fullName ?? 'bạn').trim().split(' ').last;
    final now = DateTime.now();

    return Scaffold(
      body: LifeOsMintWaveCanvas(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              const LifeOsTopBrandHeader(title: 'LifeOS'),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  6,
                  AppSpacing.md,
                  4,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: AppSpacing.maxContentWidth,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Xin chào, $firstName',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.4,
                                  height: 1.18,
                                  color: c.textPrimary,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Material(
                          color: c.primarySubtle,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              AppSpacing.radiusPill,
                            ),
                            side: BorderSide(
                              color: c.primary.withValues(alpha: 0.28),
                              width: 0.9,
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            key: const Key('today_open_gemini_ai_pill'),
                            borderRadius: BorderRadius.circular(
                              AppSpacing.radiusPill,
                            ),
                            onTap: () => context.push('/financial-ai'),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 11,
                                vertical: 5.5,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const BananaGlassIcon(
                                    assetPath: AppAssets.ic3dAiSpark,
                                    fallbackIcon: Icons.auto_awesome_rounded,
                                    size: 20,
                                    borderRadius: 6.5,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Ghi nhanh',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: c.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: BlocBuilder<DashboardBloc, DashboardState>(
                  builder: (context, state) {
                    if (state.isLoading &&
                        state.data == TodayDashboardEntity.empty) {
                      return Semantics(
                        container: true,
                        label: 'Đang tải tổng quan hôm nay',
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.md,
                            8,
                            AppSpacing.md,
                            104,
                          ),
                          children: const [
                            LifeOsSkeletonBox(height: 156, borderRadius: 18),
                            SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: LifeOsSkeletonBox(
                                    height: 92,
                                    borderRadius: 18,
                                  ),
                                ),
                                SizedBox(width: 10),
                                Expanded(
                                  child: LifeOsSkeletonBox(
                                    height: 92,
                                    borderRadius: 18,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 12),
                            LifeOsSkeletonBox(height: 110, borderRadius: 18),
                          ],
                        ),
                      );
                    }
                    if (state.failure != null &&
                        state.data == TodayDashboardEntity.empty) {
                      return ErrorRetryView(
                        message: state.failure!.message,
                        onRetry: () {
                          if (user != null) {
                            context.read<DashboardBloc>().add(
                              DashboardWatchStarted(
                                userId: user.id,
                                familyId: user.activeFamilyId,
                              ),
                            );
                          }
                        },
                      );
                    }

                    final d = state.data;
                    final timeFmt = DateFormat('HH:mm');

                    final totalBudgetLimit = budgets.fold<int>(
                      0,
                      (sum, b) => sum + b.limitMinor,
                    );
                    final hasConfiguredBudget = totalBudgetLimit > 0;
                    final spentPct = hasConfiguredBudget
                        ? ((d.monthlyExpenseMinor * 100) / totalBudgetLimit)
                              .clamp(0, 999)
                              .round()
                        : 0;

                    final avatarNames =
                        activeFamily != null && activeFamily.members.isNotEmpty
                        ? activeFamily.members.map((m) => m.fullName).toList()
                        : (user != null && user.fullName.trim().isNotEmpty
                              ? <String>[user.fullName]
                              : const <String>[]);

                    // Unified Cross-Feature Inbox (100% Real Data — Strictly Scoped Today vs Upcoming)
                    final startOfToday = DateTime(now.year, now.month, now.day);
                    final endOfToday = DateTime(
                      now.year,
                      now.month,
                      now.day,
                      23,
                      59,
                      59,
                      999,
                    );
                    final upcomingEvents =
                        calEvents.where((e) => !e.endsAt.isBefore(now)).toList()
                          ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
                    final todayEvents = upcomingEvents
                        .where((e) => !e.startsAt.isAfter(endOfToday))
                        .toList();
                    final futureEvents = upcomingEvents
                        .where((e) => e.startsAt.isAfter(endOfToday))
                        .toList();

                    final provisionalTxs = allTransactions
                        .where(
                          (t) =>
                              t.verification ==
                                  TransactionVerification.provisional &&
                              !t.isReversed,
                        )
                        .toList();

                    final openTasks = allTasks
                        .where((t) => t.status != TaskWorkflowStatus.done)
                        .toList();
                    final overdueTasks = openTasks
                        .where(
                          (t) =>
                              t.dueAt != null &&
                              t.dueAt!.isBefore(startOfToday),
                        )
                        .toList();

                    final dueVehicles = vehicles
                        .where(
                          (v) => v.dueStateAt(now) != VehicleDueState.healthy,
                        )
                        .toList();

                    final dueBills = bills
                        .where((b) => b.nextDueDate.difference(now).inDays <= 7)
                        .toList();

                    // Compute Today's real spending & daily safe allowance for immediate awareness
                    final todayExpenseMinor = allTransactions
                        .where(
                          (t) =>
                              !t.isReversed &&
                              t.kind == TransactionKind.expense &&
                              t.occurredAt.year == now.year &&
                              t.occurredAt.month == now.month &&
                              t.occurredAt.day == now.day,
                        )
                        .fold<int>(0, (sum, t) => sum + t.amountMinor);
                    final daysInMonth = DateTime(
                      now.year,
                      now.month + 1,
                      0,
                    ).day;
                    final remainingDays = (daysInMonth - now.day + 1).clamp(
                      1,
                      31,
                    );
                    final remainingBudgetMinor = hasConfiguredBudget
                        ? (totalBudgetLimit - d.monthlyExpenseMinor).clamp(
                            0,
                            totalBudgetLimit,
                          )
                        : 0;
                    final safeDailyMinor = hasConfiguredBudget
                        ? (remainingBudgetMinor ~/ remainingDays)
                        : 0;
                    final dueMedsToday = dailySnap.dueScheduledMedications(
                      DateFormat('yyyy-MM-dd').format(now),
                    );

                    final inboxItems = <_InboxActionItem>[
                      if (provisionalTxs.isNotEmpty)
                        _InboxActionItem(
                          icon: Icons.account_balance_outlined,
                          tone: LifeOsAccentTone.amber,
                          title:
                              '${provisionalTxs.length} giao dịch mới chờ xác nhận',
                          subtitle:
                              '${provisionalTxs.first.merchant} · ${_fmtMoney(provisionalTxs.first.amountMinor)}',
                          badge: 'Chờ duyệt',
                          onTap: () => context.push(
                            '/auto-tx-review',
                            extra: provisionalTxs.first,
                          ),
                          quickActionLabel: user != null ? 'Duyệt' : null,
                          isQuickActionBusy:
                              _approvingProvisionalIds.contains(
                                provisionalTxs.first.id,
                              ) ||
                              isTxActionSubmitting,
                          onQuickAction: user == null
                              ? null
                              : () => _approveProvisionalTx(
                                  context,
                                  userId: user.id,
                                  tx: provisionalTxs.first,
                                ),
                        ),
                      if (todayEvents.isNotEmpty)
                        _InboxActionItem(
                          icon: Icons.event_available_rounded,
                          tone: LifeOsAccentTone.emerald,
                          title: todayEvents.first.title,
                          subtitle:
                              '${timeFmt.format(todayEvents.first.startsAt)} – ${timeFmt.format(todayEvents.first.endsAt)}${todayEvents.first.location != null && todayEvents.first.location!.isNotEmpty ? " · ${todayEvents.first.location}" : ""}',
                          badge: 'Hôm nay',
                          onTap: () => context.push(
                            '/event-detail',
                            extra: todayEvents.first,
                          ),
                        )
                      else if (futureEvents.isNotEmpty)
                        _InboxActionItem(
                          icon: Icons.calendar_month_rounded,
                          tone: LifeOsAccentTone.blue,
                          title: futureEvents.first.title,
                          subtitle:
                              '${DateFormat('dd/MM').format(futureEvents.first.startsAt)} · ${timeFmt.format(futureEvents.first.startsAt)} – ${timeFmt.format(futureEvents.first.endsAt)}${futureEvents.first.location != null && futureEvents.first.location!.isNotEmpty ? " · ${futureEvents.first.location}" : ""}',
                          badge:
                              'Sắp tới ${DateFormat('dd/MM').format(futureEvents.first.startsAt)}',
                          onTap: () => context.push(
                            '/event-detail',
                            extra: futureEvents.first,
                          ),
                        ),
                      if (openTasks.isNotEmpty)
                        _InboxActionItem(
                          icon: Icons.task_alt_rounded,
                          tone: overdueTasks.isNotEmpty
                              ? LifeOsAccentTone.coral
                              : LifeOsAccentTone.blue,
                          title: overdueTasks.isNotEmpty
                              ? overdueTasks.first.title
                              : openTasks.first.title,
                          subtitle: overdueTasks.isNotEmpty
                              ? 'Quá hạn ${overdueTasks.length} việc · Tổng còn ${openTasks.length} việc'
                              : (openTasks.length > 1
                                    ? 'Còn ${openTasks.length} việc cần làm'
                                    : 'Chạm để mở việc cần làm'),
                          badge: overdueTasks.isNotEmpty
                              ? 'Quá hạn'
                              : 'Việc làm',
                          onTap: () => context.push('/tasks-board'),
                          quickActionLabel: user != null ? '✓ Xong' : null,
                          onQuickAction: user == null
                              ? null
                              : () {
                                  final t = overdueTasks.isNotEmpty
                                      ? overdueTasks.first
                                      : openTasks.first;
                                  if (t.status == TaskWorkflowStatus.proposed) {
                                    context.read<TaskBloc>().add(
                                      TaskResponseSubmitted(
                                        RespondToTaskParams(
                                          actorUserId: user.id,
                                          task: t,
                                          accept: true,
                                        ),
                                      ),
                                    );
                                    LifeOsTopToast.show(
                                      context,
                                      'Đã nhận việc "${t.title}".',
                                    );
                                  } else {
                                    context.read<TaskBloc>().add(
                                      TaskStatusChanged(
                                        actorUserId: user.id,
                                        task: t,
                                        nextStatus: TaskWorkflowStatus.done,
                                      ),
                                    );
                                    LifeOsTopToast.show(
                                      context,
                                      'Đã hoàn thành "${t.title}"!',
                                    );
                                  }
                                },
                        ),
                      if (dueVehicles.isNotEmpty)
                        _InboxActionItem(
                          icon: dueVehicles.first.isMotorcycle
                              ? Icons.two_wheeler_rounded
                              : Icons.car_repair_rounded,
                          tone: LifeOsAccentTone.coral,
                          title: 'Bảo dưỡng xe: ${dueVehicles.first.name}',
                          subtitle:
                              'Mốc tiếp theo: ${dueVehicles.first.nextDueKm} km',
                          badge: 'Đến hạn',
                          onTap: () => context.push('/assets'),
                        ),
                      if (dueBills.isNotEmpty)
                        _InboxActionItem(
                          icon: Icons.receipt_long_outlined,
                          tone: LifeOsAccentTone.amber,
                          title: 'Hóa đơn sắp đến hạn: ${dueBills.first.title}',
                          subtitle:
                              'Dự kiến ${_fmtMoney(dueBills.first.estimatedAmountMinor)}',
                          badge: 'Hóa đơn',
                          onTap: () => context.push('/assets'),
                        ),
                      if (dueMedsToday.isNotEmpty)
                        _InboxActionItem(
                          icon: Icons.medication_outlined,
                          tone: LifeOsAccentTone.coral,
                          title: 'Nhắc uống thuốc: ${dueMedsToday.first.name}',
                          subtitle:
                              '${dueMedsToday.first.dosage} · Lúc ${dueMedsToday.first.formattedReminderTime}',
                          badge: 'Thuốc',
                          onTap: () => context.push('/health-hub'),
                          quickActionLabel: (user != null && dailyBloc != null)
                              ? '✓ Đã uống'
                              : null,
                          onQuickAction: (user == null || dailyBloc == null)
                              ? null
                              : () {
                                  dailyBloc!.add(
                                    MedicationTakenToggled(
                                      userId: user.id,
                                      item: dueMedsToday.first,
                                    ),
                                  );
                                  LifeOsTopToast.show(
                                    context,
                                    'Đã đánh dấu uống "${dueMedsToday.first.name}".',
                                  );
                                },
                        ),
                      if (dailySnap.hydration.reminderEnabled &&
                          !dailySnap.hydration.isGoalReached)
                        _InboxActionItem(
                          icon: Icons.water_drop_outlined,
                          tone: LifeOsAccentTone.blue,
                          title:
                              'Nhắc uống nước: ${dailySnap.hydration.waterMl}/${dailySnap.hydration.targetWaterMl} ml',
                          subtitle: () {
                            final nextWaterAt = dailySnap.hydration
                                .nextReminderAt(now);
                            final nextLabel = nextWaterAt != null
                                ? 'Nhắc lúc ${DateFormat("HH:mm").format(nextWaterAt)}'
                                : 'Mỗi ${dailySnap.hydration.intervalMinutes} phút';
                            return '$nextLabel · Còn thiếu ${dailySnap.hydration.remainingMl} ml';
                          }(),
                          badge: 'Nước',
                          onTap: () => context.push('/health-hub?tab=water'),
                          quickActionLabel: (user != null && dailyBloc != null)
                              ? '+${dailySnap.hydration.preferredCupMl}ml'
                              : null,
                          onQuickAction: (user == null || dailyBloc == null)
                              ? null
                              : () {
                                  final cupMl =
                                      dailySnap.hydration.preferredCupMl;
                                  dailyBloc!.add(
                                    WaterIntakeLogged(
                                      userId: user.id,
                                      deltaMl: cupMl,
                                      targetWaterMl:
                                          dailySnap.hydration.targetWaterMl,
                                    ),
                                  );
                                  LifeOsTopToast.show(
                                    context,
                                    'Đã ghi nhận +$cupMl ml nước uống.',
                                  );
                                },
                        ),
                      if (hasConfiguredBudget && spentPct >= 85)
                        _InboxActionItem(
                          icon: Icons.warning_amber_rounded,
                          tone: LifeOsAccentTone.coral,
                          title: 'Ngân sách tháng đã dùng $spentPct%',
                          subtitle:
                              '${_fmtMoney(d.monthlyExpenseMinor)} / ${_fmtMoney(totalBudgetLimit)}',
                          badge: 'Ngân sách',
                          onTap: () => context.go('/finance'),
                        ),
                    ];

                    final syncStatusLabel = gcalConnected && bankConnected
                        ? 'Đã nối Lịch & Ngân hàng'
                        : gcalConnected
                        ? 'Đã nối Google Calendar'
                        : bankConnected
                        ? 'Đã nối Ngân hàng'
                        : 'Đang đồng bộ';

                    final pinnedSpecs = _allShortcuts
                        .where((s) => _pinnedIds.contains(s.id))
                        .toList();

                    return Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: AppSpacing.maxContentWidth,
                        ),
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.md,
                            4,
                            AppSpacing.md,
                            104,
                          ),
                          children: [
                            // 0. OTA In-App Update Notification Banner
                            const AppUpdateBanner(),

                            // Thẻ 1 — Thẻ Mint Pastel "Hôm nay"
                            LifeOsMintHeroCard(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 13,
                                vertical: 11,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    children: [
                                      const LifeOsIconSquircle(
                                        icon: Icons.calendar_today_rounded,
                                        tone: LifeOsAccentTone.emerald,
                                        size: 28,
                                        iconSize: 15,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Hôm nay',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w800,
                                          color: c.textPrimary,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Align(
                                          alignment: Alignment.centerRight,
                                          child: FittedBox(
                                            fit: BoxFit.scaleDown,
                                            alignment: Alignment.centerRight,
                                            child: Text(
                                              _formatDateVi(now),
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: c.textSecondary,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  IntrinsicHeight(
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: _TodayMintMetricColumn(
                                            count: upcomingEvents.length,
                                            label: 'Sự kiện',
                                            valueColor: c.primary,
                                            onTap: () =>
                                                context.go('/planning'),
                                          ),
                                        ),
                                        VerticalDivider(
                                          width: 16,
                                          thickness: 1,
                                          color: c.separator,
                                        ),
                                        Expanded(
                                          child: _TodayMintMetricColumn(
                                            count: d.openTasksCount,
                                            label: 'Việc cần làm',
                                            valueColor: c.primary,
                                            onTap: () =>
                                                context.push('/tasks-board'),
                                          ),
                                        ),
                                        VerticalDivider(
                                          width: 16,
                                          thickness: 1,
                                          color: c.separator,
                                        ),
                                        Expanded(
                                          child: _TodayMintMetricColumn(
                                            count: inboxItems.length,
                                            label: 'Cần xử lý',
                                            valueColor: inboxItems.isNotEmpty
                                                ? const Color(0xFFD97706)
                                                : c.primary,
                                            onTap: () {
                                              if (inboxItems.isNotEmpty) {
                                                inboxItems.first.onTap();
                                              } else {
                                                context.push(
                                                  '/activity-notifications',
                                                );
                                              }
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),

                            // Thẻ 2 — Hàng 2 cột song song (Lịch sắp tới | Chi tiêu tháng này)
                            IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    child: UpcomingScheduleCycleCard(
                                      cardKey: const Key(
                                        'upcoming_schedule_cycle_card',
                                      ),
                                      weekCount:
                                          UpcomingScheduleCycleCard.countUpcomingInWindow(
                                            calEvents,
                                            now,
                                            const Duration(days: 7),
                                          ),
                                      monthCount:
                                          UpcomingScheduleCycleCard.countUpcomingInWindow(
                                            calEvents,
                                            now,
                                            const Duration(days: 30),
                                          ),
                                      yearCount:
                                          UpcomingScheduleCycleCard.countUpcomingInWindow(
                                            calEvents,
                                            now,
                                            const Duration(days: 365),
                                          ),
                                      onLongPressOpenPlanning: (horizon) =>
                                          context.go(
                                            '/planning?view=${horizon.name}',
                                          ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: LifeOsSoftCard(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 11,
                                        vertical: 10,
                                      ),
                                      borderRadius: 18,
                                      onTap: () => context.go('/finance'),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Row(
                                            children: [
                                              const LifeOsIconSquircle(
                                                icon: Icons.payments_outlined,
                                                tone: LifeOsAccentTone.emerald,
                                                size: 28,
                                                iconSize: 15,
                                              ),
                                              const SizedBox(width: 6),
                                              Expanded(
                                                child: FittedBox(
                                                  fit: BoxFit.scaleDown,
                                                  alignment:
                                                      Alignment.centerLeft,
                                                  child: Text(
                                                    'Chi tiêu tháng này',
                                                    style: TextStyle(
                                                      fontSize: 12.4,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      color: c.textPrimary,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 2),
                                              Icon(
                                                Icons.chevron_right_rounded,
                                                size: 17,
                                                color: c.textSecondary,
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 5),
                                          FittedBox(
                                            fit: BoxFit.scaleDown,
                                            alignment: Alignment.centerLeft,
                                            child: Text(
                                              _fmtMoney(d.monthlyExpenseMinor),
                                              style: TextStyle(
                                                fontSize: 17.5,
                                                fontWeight: FontWeight.w800,
                                                color: c.textPrimary,
                                                fontFeatures: const [
                                                  FontFeature.tabularFigures(),
                                                ],
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          FittedBox(
                                            fit: BoxFit.scaleDown,
                                            alignment: Alignment.centerLeft,
                                            child: Text(
                                              hasConfiguredBudget
                                                  ? '/ ${_fmtMoney(totalBudgetLimit)}'
                                                  : 'Chưa đặt hạn mức',
                                              style: TextStyle(
                                                fontSize: 11.2,
                                                fontWeight: FontWeight.w600,
                                                color: c.textSecondary,
                                                fontFeatures: const [
                                                  FontFeature.tabularFigures(),
                                                ],
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 5),
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                            child: LinearProgressIndicator(
                                              minHeight: 6,
                                              value: hasConfiguredBudget
                                                  ? (spentPct / 100).clamp(
                                                      0.04,
                                                      1.0,
                                                    )
                                                  : 0.08,
                                              backgroundColor: c.surfaceRaised,
                                              valueColor:
                                                  AlwaysStoppedAnimation<Color>(
                                                    (hasConfiguredBudget &&
                                                            spentPct >= 85)
                                                        ? c.error
                                                        : c.primary,
                                                  ),
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          FittedBox(
                                            fit: BoxFit.scaleDown,
                                            alignment: Alignment.centerLeft,
                                            child: Text(
                                              hasConfiguredBudget
                                                  ? 'Đã chi $spentPct% ngân sách'
                                                  : 'Chạm để đặt hạn mức',
                                              style: TextStyle(
                                                fontSize: 10.8,
                                                fontWeight: FontWeight.w600,
                                                color:
                                                    (hasConfiguredBudget &&
                                                        spentPct >= 85)
                                                    ? c.error
                                                    : c.textSecondary,
                                                fontFeatures: const [
                                                  FontFeature.tabularFigures(),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),

                            // Thẻ 3 — Thẻ 3D Emerald Vault "Quỹ gia đình & Tài sản"
                            LifeOsAnimatedItemEntrance(
                              key: const ValueKey('today_wealth_hero_entrance'),
                              itemId: 'today_wealth_hero',
                              staggerIndex: 0,
                              child: ProHeroGradientCard(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const BananaGlassIcon(
                                          assetPath: AppAssets.icNavFamily,
                                          fallbackIcon: Icons.groups_rounded,
                                          size: 30,
                                          borderRadius: 9.5,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: InkWell(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            onTap: () => context.go('/family'),
                                            child: const Padding(
                                              padding: EdgeInsets.symmetric(
                                                vertical: 2,
                                              ),
                                              child: FittedBox(
                                                fit: BoxFit.scaleDown,
                                                alignment: Alignment.centerLeft,
                                                child: Text(
                                                  'Quỹ gia đình & Tài sản',
                                                  style: TextStyle(
                                                    fontSize: 13.8,
                                                    fontWeight: FontWeight.w800,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Material(
                                          color: Colors.white.withValues(
                                            alpha: 0.16,
                                          ),
                                          shape: CircleBorder(
                                            side: BorderSide(
                                              color: Colors.white.withValues(
                                                alpha: 0.30,
                                              ),
                                              width: 0.9,
                                            ),
                                          ),
                                          clipBehavior: Clip.antiAlias,
                                          child: InkWell(
                                            key: const Key(
                                              'toggle_balance_privacy_btn',
                                            ),
                                            customBorder: const CircleBorder(),
                                            onTap: () {
                                              final nextHide = !_hideBalances;
                                              setState(
                                                () => _hideBalances = nextHide,
                                              );
                                              UserBehaviorPrefs.saveHideBalances(
                                                nextHide,
                                              );
                                              LifeOsTopToast.show(
                                                context,
                                                nextHide
                                                    ? 'Đã bật chế độ ẩn số dư riêng tư.'
                                                    : 'Đã hiển thị lại số dư tài chính.',
                                                kind: LifeOsToastKind.info,
                                                duration: const Duration(
                                                  milliseconds: 1800,
                                                ),
                                              );
                                            },
                                            child: Padding(
                                              padding: const EdgeInsets.all(
                                                6.5,
                                              ),
                                              child: Icon(
                                                _hideBalances
                                                    ? Icons
                                                          .visibility_off_outlined
                                                    : Icons.visibility_outlined,
                                                size: 16,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        InkWell(
                                          customBorder: const CircleBorder(),
                                          onTap: () => context.go('/family'),
                                          child: const Padding(
                                            padding: EdgeInsets.all(2),
                                            child: Icon(
                                              Icons.chevron_right_rounded,
                                              size: 18,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              FittedBox(
                                                fit: BoxFit.scaleDown,
                                                alignment: Alignment.centerLeft,
                                                child: LifeOsTruthfulNumericText(
                                                  formattedValue: _fmtMoney(
                                                    d.netWorthMinor,
                                                  ),
                                                  semanticsLabel: _hideBalances
                                                      ? 'Tổng tài sản ròng đang ẩn riêng tư'
                                                      : 'Tổng tài sản ròng ${_fmtMoney(d.netWorthMinor)}',
                                                  style: const TextStyle(
                                                    fontSize: 26,
                                                    fontWeight: FontWeight.w800,
                                                    letterSpacing: -0.5,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(height: 5),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 9,
                                                      vertical: 3.5,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: Colors.white
                                                      .withValues(alpha: 0.18),
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                        AppSpacing.radiusPill,
                                                      ),
                                                  border: Border.all(
                                                    color: Colors.white
                                                        .withValues(alpha: 0.26),
                                                    width: 0.8,
                                                  ),
                                                ),
                                                child: FittedBox(
                                                  fit: BoxFit.scaleDown,
                                                  alignment:
                                                      Alignment.centerLeft,
                                                  child: Text(
                                                    '↑ +${_fmtMoney(d.monthlyIncomeMinor)} (thu tháng)',
                                                    style: const TextStyle(
                                                      fontSize: 11.2,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: Color(0xFFB2F2BB),
                                                      fontFeatures: [
                                                        FontFeature
                                                            .tabularFigures(),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              if (avatarNames.isNotEmpty) ...[
                                                const SizedBox(height: 8),
                                                LifeOsAvatarStack(
                                                  names: avatarNames,
                                                  radius: 13.5,
                                                  onAddTap: () =>
                                                      context.go('/family'),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        CustomPaint(
                                          foregroundPainter:
                                              const LiquidGlassRimPainter(
                                                borderRadius: 18,
                                                isDark: true,
                                                accentRimColor: Color(
                                                  0xFF8CE99A,
                                                ),
                                                intensity: 1.2,
                                              ),
                                          child: Container(
                                            width: 68,
                                            height: 68,
                                            decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(18),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black
                                                      .withValues(alpha: 0.28),
                                                  blurRadius: 14,
                                                  offset: const Offset(0, 6),
                                                ),
                                              ],
                                            ),
                                            clipBehavior: Clip.antiAlias,
                                            child: Image.asset(
                                              AppAssets.hero3dWealthVault,
                                              width: 68,
                                              height: 68,
                                              cacheWidth: 204,
                                              cacheHeight: 204,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) =>
                                                  const Icon(
                                                    Icons.shield_outlined,
                                                    color: Colors.white,
                                                    size: 32,
                                                  ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: DecoratedBox(
                                            decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                              gradient: const LinearGradient(
                                                begin: Alignment.topCenter,
                                                end: Alignment.bottomCenter,
                                                colors: [
                                                  Color(0xFFFFFFFF),
                                                  Color(0xFFE7F9EE),
                                                ],
                                              ),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black
                                                      .withValues(alpha: 0.16),
                                                  blurRadius: 10,
                                                  offset: const Offset(0, 4),
                                                ),
                                              ],
                                            ),
                                            child: Material(
                                              color: Colors.transparent,
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                              child: InkWell(
                                                key: const Key(
                                                  'home_quick_expense_btn',
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(14),
                                                onTap: () =>
                                                    showVoiceSmartCaptureSheet(
                                                      context,
                                                      autoStartListening: true,
                                                    ),
                                                child: ConstrainedBox(
                                                  constraints:
                                                      const BoxConstraints(
                                                        minHeight: 42,
                                                      ),
                                                  child: const Padding(
                                                    padding:
                                                        EdgeInsets.symmetric(
                                                          horizontal: 10,
                                                          vertical: 8,
                                                        ),
                                                    child: FittedBox(
                                                      fit: BoxFit.scaleDown,
                                                      child: Row(
                                                        mainAxisAlignment:
                                                            MainAxisAlignment
                                                                .center,
                                                        children: [
                                                          BananaGlassIcon(
                                                            assetPath: AppAssets
                                                                .ic3dVoiceAi,
                                                            fallbackIcon: Icons
                                                                .mic_rounded,
                                                            size: 22,
                                                            borderRadius: 7,
                                                          ),
                                                          SizedBox(width: 6),
                                                          Text(
                                                            'Nói ghi nhanh',
                                                            style: TextStyle(
                                                              fontSize: 12.8,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w800,
                                                              color: Color(
                                                                0xFF065F28,
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Material(
                                            color: Colors.white.withValues(
                                              alpha: 0.16,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                              side: BorderSide(
                                                color: Colors.white.withValues(
                                                  alpha: 0.32,
                                                ),
                                                width: 1.0,
                                              ),
                                            ),
                                            clipBehavior: Clip.antiAlias,
                                            child: InkWell(
                                              key: const Key(
                                                'home_quick_schedule_btn',
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                              onTap: () =>
                                                  showLifeOsQuickCreateHub(
                                                    context,
                                                  ),
                                              child: ConstrainedBox(
                                                constraints:
                                                    const BoxConstraints(
                                                      minHeight: 42,
                                                    ),
                                                child: const Padding(
                                                  padding: EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 8,
                                                  ),
                                                  child: FittedBox(
                                                    fit: BoxFit.scaleDown,
                                                    child: Row(
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .center,
                                                      children: [
                                                        BananaGlassIcon(
                                                          assetPath: AppAssets
                                                              .icNavCalendar,
                                                          fallbackIcon: Icons
                                                              .event_note_rounded,
                                                          size: 22,
                                                          borderRadius: 7,
                                                        ),
                                                        SizedBox(width: 6),
                                                        Text(
                                                          'Thêm lịch / việc',
                                                          style: TextStyle(
                                                            fontSize: 12.8,
                                                            fontWeight:
                                                                FontWeight.w700,
                                                            color: Colors.white,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    LifeOsDetailsDiscloseSection(
                                      toggleKey: const Key(
                                        'today_hero_details_toggle',
                                      ),
                                      onDarkSurface: true,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: ProGlassStatPill(
                                                  icon: Icons.south_west_rounded,
                                                  label: 'Thu tháng',
                                                  value: _fmtMoney(
                                                    d.monthlyIncomeMinor,
                                                    prefix: '+',
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: ProGlassStatPill(
                                                  icon: Icons.north_east_rounded,
                                                  iconColor: const Color(
                                                    0xFFFECACA,
                                                  ),
                                                  label: 'Chi tháng',
                                                  value: _fmtMoney(
                                                    d.monthlyExpenseMinor,
                                                    prefix: '-',
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 11,
                                              vertical: 8,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.white.withValues(
                                                alpha: 0.14,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              border: Border.all(
                                                color: Colors.white.withValues(
                                                  alpha: 0.24,
                                                ),
                                                width: 0.9,
                                              ),
                                            ),
                                            child: Wrap(
                                              spacing: 12,
                                              runSpacing: 5,
                                              crossAxisAlignment:
                                                  WrapCrossAlignment.center,
                                              children: [
                                                Text(
                                                  'Hôm nay chi: ${_fmtMoney(todayExpenseMinor)}',
                                                  style: const TextStyle(
                                                    fontSize: 11.8,
                                                    fontWeight: FontWeight.w700,
                                                    color: Colors.white,
                                                    fontFeatures: [
                                                      FontFeature
                                                          .tabularFigures(),
                                                    ],
                                                  ),
                                                ),
                                                if (hasConfiguredBudget)
                                                  Text(
                                                    'Còn tiêu/ngày: ${_fmtMoney(safeDailyMinor)}',
                                                    style: const TextStyle(
                                                      fontSize: 11.8,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: Color(0xFFB2F2BB),
                                                      fontFeatures: [
                                                        FontFeature
                                                            .tabularFigures(),
                                                      ],
                                                    ),
                                                  ),
                                                Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Container(
                                                      width: 6.5,
                                                      height: 6.5,
                                                      decoration:
                                                          const BoxDecoration(
                                                            color: Color(
                                                              0xFF86EFAC,
                                                            ),
                                                            shape:
                                                                BoxShape.circle,
                                                          ),
                                                    ),
                                                    const SizedBox(width: 5),
                                                    Flexible(
                                                      child: Text(
                                                        syncStatusLabel,
                                                        softWrap: true,
                                                        style: TextStyle(
                                                          fontSize: 11.2,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          color: Colors.white
                                                              .withValues(
                                                                alpha: 0.88,
                                                              ),
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),

                            // 3. Unified `LifeOS Inbox` ("Việc cần chú ý") — 100% Real Data Only
                            LifeOsSoftCard(
                              padding: const EdgeInsets.all(13),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const LifeOsIconSquircle(
                                        icon: Icons
                                            .notifications_active_outlined,
                                        tone: LifeOsAccentTone.amber,
                                        size: 28,
                                        iconSize: 15,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Việc cần chú ý',
                                          softWrap: true,
                                          style: TextStyle(
                                            fontSize: 13.8,
                                            fontWeight: FontWeight.w800,
                                            color: c.textPrimary,
                                          ),
                                        ),
                                      ),
                                      if (inboxItems.isNotEmpty)
                                        LifeOsStatusPill(
                                          label: '${inboxItems.length} mục',
                                          tone: LifeOsAccentTone.emerald,
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  if (inboxItems.isEmpty)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 4,
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.check_circle_outline_rounded,
                                            size: 18,
                                            color: c.primary,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              'Chưa có việc gấp hôm nay.',
                                              style: TextStyle(
                                                fontSize: 12.2,
                                                color: c.textSecondary,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  else ...[
                                    ...(_showAllInbox
                                            ? inboxItems
                                            : inboxItems.take(4))
                                        .toList()
                                        .asMap()
                                        .entries
                                        .map((entry) {
                                          final idx = entry.key;
                                          final item = entry.value;
                                          return Column(
                                            children: [
                                              if (idx > 0)
                                                Divider(
                                                  height: 14,
                                                  color: c.separator,
                                                ),
                                              InkWell(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                onTap: item.onTap,
                                                child: Padding(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        vertical: 3,
                                                      ),
                                                  child: Row(
                                                    children: [
                                                      LifeOsIconSquircle(
                                                        icon: item.icon,
                                                        tone: item.tone,
                                                        size: 34,
                                                        iconSize: 17,
                                                      ),
                                                      const SizedBox(width: 10),
                                                      Expanded(
                                                        child: Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            Text(
                                                              item.title,
                                                              softWrap: true,
                                                              style: TextStyle(
                                                                fontSize: 13.4,
                                                                height: 1.24,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700,
                                                                color: c
                                                                    .textPrimary,
                                                                fontFeatures: const [
                                                                  FontFeature.tabularFigures(),
                                                                ],
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                              height: 2,
                                                            ),
                                                            Text(
                                                              item.subtitle,
                                                              softWrap: true,
                                                              style: TextStyle(
                                                                fontSize: 12,
                                                                height: 1.28,
                                                                color: c
                                                                    .textSecondary,
                                                                fontFeatures: const [
                                                                  FontFeature.tabularFigures(),
                                                                ],
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                      const SizedBox(width: 6),
                                                      if ((item.onQuickAction !=
                                                                  null ||
                                                              item.isQuickActionBusy) &&
                                                          item.quickActionLabel !=
                                                              null)
                                                        FilledButton.tonal(
                                                          style: FilledButton.styleFrom(
                                                            visualDensity:
                                                                VisualDensity
                                                                    .compact,
                                                            padding:
                                                                const EdgeInsets.symmetric(
                                                                  horizontal:
                                                                      10,
                                                                  vertical: 4,
                                                                ),
                                                          ),
                                                          onPressed: item
                                                                  .isQuickActionBusy
                                                              ? null
                                                              : item.onQuickAction,
                                                          child: Text(
                                                            item.isQuickActionBusy
                                                                ? 'Đang duyệt'
                                                                : item.quickActionLabel!,
                                                            style:
                                                                const TextStyle(
                                                                  fontSize:
                                                                      11.8,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w800,
                                                                  fontFeatures: [
                                                                    FontFeature.tabularFigures(),
                                                                  ],
                                                                ),
                                                          ),
                                                        )
                                                      else
                                                        LifeOsStatusPill(
                                                          label: item.badge,
                                                          tone: item.tone,
                                                        ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ],
                                          );
                                        }),
                                    if (inboxItems.length > 4) ...[
                                      Divider(height: 14, color: c.separator),
                                      Center(
                                        child: TextButton.icon(
                                          key: const Key(
                                            'today_toggle_all_inbox_btn',
                                          ),
                                          style: TextButton.styleFrom(
                                            visualDensity: VisualDensity.compact,
                                          ),
                                          onPressed: () => setState(
                                            () =>
                                                _showAllInbox = !_showAllInbox,
                                          ),
                                          icon: Icon(
                                            _showAllInbox
                                                ? Icons.expand_less_rounded
                                                : Icons.expand_more_rounded,
                                            size: 18,
                                          ),
                                          label: Text(
                                            _showAllInbox
                                                ? 'Thu gọn'
                                                : 'Xem tất cả (${inboxItems.length} mục)',
                                            style: const TextStyle(
                                              fontSize: 12.4,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                            LifeOsSoftCard(
                              padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: FittedBox(
                                            fit: BoxFit.scaleDown,
                                            alignment: Alignment.centerLeft,
                                            child: Text(
                                              'Tiện ích của bạn',
                                              style: TextStyle(
                                                fontSize: 13.5,
                                                fontWeight: FontWeight.w800,
                                                color: c.textPrimary,
                                              ),
                                            ),
                                          ),
                                        ),
                                        TextButton(
                                          key: const Key(
                                            'customize_home_shortcuts_btn',
                                          ),
                                          style: TextButton.styleFrom(
                                            visualDensity:
                                                VisualDensity.compact,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                            ),
                                          ),
                                          onPressed: () =>
                                              _showCustomizeShortcutsSheet(
                                                context,
                                              ),
                                          child: const Text('Tùy chỉnh'),
                                        ),
                                        InkWell(
                                          key: const Key(
                                            'open_super_app_directory_btn',
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          onTap: () =>
                                              context.push('/super-app-hub'),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 4,
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  'Tất cả',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w700,
                                                    color: c.primary,
                                                  ),
                                                ),
                                                Icon(
                                                  Icons.chevron_right_rounded,
                                                  size: 16,
                                                  color: c.primary,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  LifeOsResponsiveIconGrid(
                                    columns: 4,
                                    children: pinnedSpecs.map((spec) {
                                      return LifeOsCompactDockItem(
                                        key: spec.tileKey,
                                        icon: spec.icon,
                                        label: spec.label,
                                        tone: spec.tone,
                                        onTap: () => context.push(spec.route),
                                      );
                                    }).toList(),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),

                            // 6. Clean Full-Width Vertical Bento Strip (Zero Truncation)
                            IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    child: LifeOsFeatureBentoTile(
                                      tileKey: const Key(
                                        'open_pro_utilities_hub_card',
                                      ),
                                      icon: Icons.calculate_outlined,
                                      tone: LifeOsAccentTone.blue,
                                      title: 'Công cụ nâng cao',
                                      subtitle: 'Lãi vay · Tiết kiệm',
                                      onTap: () =>
                                          context.push('/pro-utilities'),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: LifeOsMintHeroCard(
                                      key: const Key('home_tile_all_services'),
                                      padding: const EdgeInsets.all(12),
                                      onTap: () =>
                                          context.push('/super-app-hub'),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Row(
                                            children: [
                                              const LifeOsIconSquircle(
                                                icon: Icons.apps_rounded,
                                                tone: LifeOsAccentTone.emerald,
                                                solidFill: true,
                                                size: 36,
                                                iconSize: 18,
                                              ),
                                              const Spacer(),
                                              Icon(
                                                Icons.chevron_right_rounded,
                                                size: 17,
                                                color: c.primary,
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Tất cả danh mục',
                                                softWrap: true,
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 13.2,
                                                  height: 1.22,
                                                  color: c.textPrimary,
                                                ),
                                              ),
                                              const SizedBox(height: 3),
                                              Text(
                                                'Đầy đủ 20+ tiện ích',
                                                softWrap: true,
                                                style: TextStyle(
                                                  fontSize: 11.5,
                                                  height: 1.25,
                                                  color: c.textSecondary,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TodayMintMetricColumn extends StatelessWidget {
  final int count;
  final String label;
  final Color valueColor;
  final VoidCallback onTap;

  const _TodayMintMetricColumn({
    required this.count,
    required this.label,
    required this.valueColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                count.toString(),
                style: TextStyle(
                  fontSize: 20,
                  height: 1.12,
                  fontWeight: FontWeight.w800,
                  color: valueColor,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11.6,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                  color: c.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum UpcomingScheduleHorizon {
  week,
  month,
  year;

  String get badgeLabelVi => switch (this) {
    UpcomingScheduleHorizon.week => 'Tuần',
    UpcomingScheduleHorizon.month => 'Tháng',
    UpcomingScheduleHorizon.year => 'Năm',
  };

  IconData get icon => switch (this) {
    UpcomingScheduleHorizon.week => Icons.schedule_rounded,
    UpcomingScheduleHorizon.month => Icons.calendar_month_rounded,
    UpcomingScheduleHorizon.year => Icons.event_repeat_rounded,
  };

  LifeOsAccentTone get tone => switch (this) {
    UpcomingScheduleHorizon.week => LifeOsAccentTone.emerald,
    UpcomingScheduleHorizon.month => LifeOsAccentTone.blue,
    UpcomingScheduleHorizon.year => LifeOsAccentTone.purple,
  };

  UpcomingScheduleHorizon get next => switch (this) {
    UpcomingScheduleHorizon.week => UpcomingScheduleHorizon.month,
    UpcomingScheduleHorizon.month => UpcomingScheduleHorizon.year,
    UpcomingScheduleHorizon.year => UpcomingScheduleHorizon.week,
  };
}

/// Interactive & gently auto-rotating "Lịch sắp tới" Bento card cycling across
/// `Tuần` (7 days) -> `Tháng` (30 days) -> `Năm` (365 days), or switching immediately on tap.
class UpcomingScheduleCycleCard extends StatefulWidget {
  final Key? cardKey;
  final int weekCount;
  final int monthCount;
  final int yearCount;
  final Duration autoCycleInterval;
  final ValueChanged<UpcomingScheduleHorizon>? onLongPressOpenPlanning;

  const UpcomingScheduleCycleCard({
    super.key,
    this.cardKey,
    required this.weekCount,
    required this.monthCount,
    required this.yearCount,
    this.autoCycleInterval = const Duration(seconds: 6),
    this.onLongPressOpenPlanning,
  });

  /// Counts real upcoming single, multi-day, and RRULE-recurring event occurrences inside `[now, now + window]`.
  static int countUpcomingInWindow(
    List<CalendarEventEntity> events,
    DateTime now,
    Duration window,
  ) {
    final winEnd = now.add(window);
    var total = 0;
    for (final ev in events) {
      final duration = ev.endsAt.isAfter(ev.startsAt)
          ? ev.endsAt.difference(ev.startsAt)
          : const Duration(hours: 1);
      if (ev.isRecurring) {
        final occs = ev.recurrence.expandOccurrences(
          firstStart: ev.startsAt,
          windowStart: now.subtract(duration),
          windowEnd: winEnd,
          maxInstances: 400,
        );
        for (final occStart in occs) {
          final occEnd = occStart.add(duration);
          if (!occEnd.isBefore(now) && !occStart.isAfter(winEnd)) {
            total++;
          }
        }
      } else {
        if (!ev.endsAt.isBefore(now) && !ev.startsAt.isAfter(winEnd)) {
          total++;
        }
      }
    }
    return total;
  }

  @override
  State<UpcomingScheduleCycleCard> createState() =>
      _UpcomingScheduleCycleCardState();
}

class _UpcomingScheduleCycleCardState extends State<UpcomingScheduleCycleCard> {
  UpcomingScheduleHorizon _horizon = UpcomingScheduleHorizon.week;
  Timer? _autoTimer;

  @override
  void initState() {
    super.initState();
    _restartAutoTimer();
  }

  @override
  void didUpdateWidget(covariant UpcomingScheduleCycleCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.autoCycleInterval != widget.autoCycleInterval) {
      _restartAutoTimer();
    }
  }

  void _restartAutoTimer() {
    _autoTimer?.cancel();
    _autoTimer = Timer.periodic(widget.autoCycleInterval, (_) {
      if (!mounted) return;
      if (!TickerMode.valuesOf(context).enabled) return;
      if (LifeOsMotionScope.read(context).isReducedMotion) return;
      setState(() {
        _horizon = _horizon.next;
      });
    });
  }

  void _handleManualTap() {
    LifeOsMotionScope.read(context).selectionHaptic();
    setState(() {
      _horizon = _horizon.next;
    });
    _restartAutoTimer();
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    super.dispose();
  }

  int _countFor(UpcomingScheduleHorizon h) => switch (h) {
    UpcomingScheduleHorizon.week => widget.weekCount,
    UpcomingScheduleHorizon.month => widget.monthCount,
    UpcomingScheduleHorizon.year => widget.yearCount,
  };

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final motion = LifeOsMotionScope.of(context);
    final switchDur = motion.resolveDuration(LifeOsMotionTokens.standard);
    final (bg, fg) = _horizon.tone.resolve(context);
    final count = _countFor(_horizon);

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onLongPress: widget.onLongPressOpenPlanning == null
          ? null
          : () => widget.onLongPressOpenPlanning!(_horizon),
      child: LifeOsSoftCard(
        key: widget.cardKey,
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 10),
        borderRadius: 18,
        onTap: _handleManualTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                AnimatedSwitcher(
                  duration: switchDur,
                  switchInCurve: LifeOsMotionTokens.standardCurve,
                  switchOutCurve: LifeOsMotionTokens.exitCurve,
                  child: LifeOsIconSquircle(
                    key: ValueKey('upcoming_icon_${_horizon.name}'),
                    icon: _horizon.icon,
                    tone: _horizon.tone,
                    size: 28,
                    iconSize: 15,
                  ),
                ),
                const Spacer(),
                AnimatedSwitcher(
                  duration: switchDur,
                  switchInCurve: LifeOsMotionTokens.standardCurve,
                  switchOutCurve: LifeOsMotionTokens.exitCurve,
                  transitionBuilder: (child, anim) {
                    if (motion.isReducedMotion) {
                      return FadeTransition(opacity: anim, child: child);
                    }
                    final slide = Tween<Offset>(
                      begin: const Offset(0, 0.24),
                      end: Offset.zero,
                    ).animate(anim);
                    return FadeTransition(
                      opacity: anim,
                      child: SlideTransition(position: slide, child: child),
                    );
                  },
                  child: FittedBox(
                    key: ValueKey('upcoming_cnt_${_horizon.name}_$count'),
                    fit: BoxFit.scaleDown,
                    child: Text(
                      count.toString().padLeft(2, '0'),
                      style: TextStyle(
                        fontSize: 18.5,
                        fontWeight: FontWeight.w800,
                        color: fg,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                'Lịch sắp tới',
                style: TextStyle(
                  fontSize: 12.2,
                  height: 1.18,
                  fontWeight: FontWeight.w700,
                  color: c.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: switchDur,
                    curve: LifeOsMotionTokens.standardCurve,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6.5,
                      vertical: 1.8,
                    ),
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: AnimatedSwitcher(
                      duration: switchDur,
                      child: Text(
                        _horizon.badgeLabelVi,
                        key: ValueKey('upcoming_badge_${_horizon.name}'),
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: fg,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  for (final h in UpcomingScheduleHorizon.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 3),
                      child: AnimatedContainer(
                        duration: switchDur,
                        curve: LifeOsMotionTokens.standardCurve,
                        width: h == _horizon ? 10 : 4,
                        height: 4,
                        decoration: BoxDecoration(
                          color: h == _horizon
                              ? fg
                              : c.textSecondary.withValues(alpha: 0.26),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
