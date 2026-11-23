import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/utils/vnd_amount.dart';
import '../../../../core/widgets/lifeos_design_system.dart';
import '../../../../core/widgets/status_widgets.dart';
import '../../../../core/widgets/voice_smart_capture_sheet.dart';
import '../../../app_update/presentation/widgets/app_update_widgets.dart';
import '../../../authentication/presentation/bloc/auth_bloc.dart';
import '../../../authentication/presentation/pages/account_profile_page.dart';
import '../../../budgets/presentation/bloc/budget_bloc.dart';
import '../../../calendar/presentation/bloc/calendar_bloc.dart';
import '../../../family/presentation/bloc/family_bloc.dart';
import '../../../notifications/presentation/bloc/notification_ingestion_bloc.dart';
import '../../../tasks/domain/entities/task_entities.dart';
import '../../../tasks/presentation/bloc/task_bloc.dart';
import '../../../transactions/domain/entities/transaction_entities.dart';
import '../../../transactions/presentation/bloc/transaction_bloc.dart';
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
  final bool isBranchGo;
  final Key? tileKey;

  const _ShortcutSpec({
    required this.id,
    required this.label,
    required this.icon,
    required this.tone,
    required this.route,
    this.isBranchGo = false,
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

  const _InboxActionItem({
    required this.icon,
    required this.tone,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.onTap,
  });
}

/// Screen 01: Action-First "Hôm nay" (`TodayPage`) with Unified `LifeOS Inbox`,
/// 100% Data Honesty (zero fake events, zero fake 20M budget, distinct Net Worth vs Family Fund),
/// and customizable pinned shortcuts.
class TodayPage extends StatefulWidget {
  const TodayPage({super.key});

  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> {
  static const List<_ShortcutSpec> _allShortcuts = [
    _ShortcutSpec(
      id: 'finance',
      label: 'Chi tiêu',
      icon: Icons.payments_outlined,
      tone: LifeOsAccentTone.emerald,
      route: '/finance',
      isBranchGo: true,
    ),
    _ShortcutSpec(
      id: 'family',
      label: 'Tổ ấm & Nhóm',
      icon: Icons.groups_outlined,
      tone: LifeOsAccentTone.emerald,
      route: '/family',
      isBranchGo: true,
    ),
    _ShortcutSpec(
      id: 'vehicles',
      label: 'Xe cộ',
      icon: Icons.directions_car_outlined,
      tone: LifeOsAccentTone.blue,
      route: '/assets',
      isBranchGo: true,
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
      label: 'Bếp & Chợ',
      icon: Icons.shopping_basket_outlined,
      tone: LifeOsAccentTone.emerald,
      route: '/kitchen-groceries',
      tileKey: Key('home_tile_kitchen'),
    ),
    _ShortcutSpec(
      id: 'evn',
      label: 'Điện EVN',
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
      id: 'settings',
      label: 'Cài đặt',
      icon: Icons.settings_outlined,
      tone: LifeOsAccentTone.neutral,
      route: '/settings-hub',
    ),
    _ShortcutSpec(
      id: 'notes_salary',
      label: 'Lương & Thuế',
      icon: Icons.request_quote_outlined,
      tone: LifeOsAccentTone.purple,
      route: '/smart-notes-hub',
    ),
    _ShortcutSpec(
      id: 'calendar',
      label: 'Lịch trình',
      icon: Icons.calendar_today_rounded,
      tone: LifeOsAccentTone.emerald,
      route: '/planning',
      isBranchGo: true,
    ),
    _ShortcutSpec(
      id: 'widgets',
      label: 'Widget M3',
      icon: Icons.widgets_outlined,
      tone: LifeOsAccentTone.purple,
      route: '/home-widgets',
    ),
  ];

  final Set<String> _pinnedIds = <String>{
    'finance',
    'family',
    'vehicles',
    'health',
    'kitchen',
    'evn',
    'documents',
    'settings',
  };

  void _showCustomizeShortcutsSheet(BuildContext context) {
    final c = TammySemanticColors.of(context);
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (ctx, setModal) => Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 22),
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
                const SizedBox(height: 4),
                Text(
                  'Chọn tối thiểu 4 tiện ích bạn dùng hằng ngày để mở nhanh 1 chạm.',
                  style: TextStyle(fontSize: 12.2, color: c.textSecondary),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _allShortcuts.map((item) {
                    final selected = _pinnedIds.contains(item.id);
                    return FilterChip(
                      selected: selected,
                      avatar: Icon(item.icon, size: 16),
                      label: Text(item.label),
                      onSelected: (val) {
                        if (!val && _pinnedIds.length <= 4) return;
                        setState(() {
                          if (val) {
                            _pinnedIds.add(item.id);
                          } else {
                            _pinnedIds.remove(item.id);
                          }
                        });
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
    final user = context.watch<AuthBloc>().state.user;
    final calState = context.watch<CalendarBloc>().state;
    final taskState = context.watch<TaskBloc>().state;
    final budgetState = context.watch<BudgetBloc>().state;
    final familyState = context.watch<FamilyBloc>().state;
    final txState = context.watch<TransactionListBloc>().state;
    final vehicleState = context.watch<VehicleBloc>().state;
    final notifState = context.watch<NotificationIngestionBloc>().state;

    final firstName = (user?.fullName ?? 'bạn').trim().split(' ').last;
    final now = DateTime.now();
    const weekdays = <int, String>{
      DateTime.monday: 'Thứ Hai',
      DateTime.tuesday: 'Thứ Ba',
      DateTime.wednesday: 'Thứ Tư',
      DateTime.thursday: 'Thứ Năm',
      DateTime.friday: 'Thứ Sáu',
      DateTime.saturday: 'Thứ Bảy',
      DateTime.sunday: 'Chủ Nhật',
    };
    final todayDateLabel = '${weekdays[now.weekday]}, ${now.day} tháng ${now.month}';

    return Scaffold(
      body: LifeOsMintWaveCanvas(
        child: SafeArea(
          child: Column(
            children: [
              LifeOsTopBrandHeader(
                title: 'Xin chào, $firstName',
                subtitle: 'Tổng quan công việc, lịch hẹn và tài chính cần chú ý.',
                profileTrailing: user == null
                    ? null
                    : IconButton(
                        key: const Key('open_account_profile_button'),
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Hồ sơ & Bảo mật tài khoản',
                        onPressed: () => context.push('/account-profile'),
                        icon: UserAvatarBadge(user: user, radius: 16),
                      ),
              ),
              Expanded(
                child: BlocBuilder<DashboardBloc, DashboardState>(
                  builder: (context, state) {
                    if (state.isLoading && state.data == TodayDashboardEntity.empty) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (state.failure != null && state.data == TodayDashboardEntity.empty) {
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

                    // Honest Budget & Fund metrics (ZERO fake 20M fallback & ZERO netWorth-as-familyFund mixup)
                    final totalBudgetLimit = budgetState.budgets.fold<int>(
                      0,
                      (sum, b) => sum + b.limitMinor,
                    );
                    final hasConfiguredBudget = totalBudgetLimit > 0;
                    final spentPct = hasConfiguredBudget
                        ? ((d.monthlyExpenseMinor * 100) / totalBudgetLimit).clamp(0, 999).round()
                        : 0;

                    final totalFundsBalance = budgetState.funds.fold<int>(
                      0,
                      (sum, f) => sum + f.balanceMinor,
                    );
                    final hasFamilyFunds = budgetState.funds.isNotEmpty;

                    // Build Unified Cross-Feature `LifeOS Inbox` from REAL user data only
                    final upcomingEvents = calState.events
                        .where((e) => !e.endsAt.isBefore(now))
                        .toList()
                      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));

                    final provisionalTxs = txState.allTransactions
                        .where(
                          (t) =>
                              t.verification == TransactionVerification.provisional &&
                              !t.isReversed,
                        )
                        .toList();

                    final openTasks = taskState.tasks
                        .where((t) => t.status != TaskWorkflowStatus.done)
                        .toList();

                    final dueVehicles = vehicleState.vehicles
                        .where((v) => v.dueStateAt(now) != VehicleDueState.healthy)
                        .toList();

                    final dueBills = vehicleState.bills
                        .where((b) => b.nextDueDate.difference(now).inDays <= 7)
                        .toList();

                    final inboxItems = <_InboxActionItem>[
                      if (provisionalTxs.isNotEmpty)
                        _InboxActionItem(
                          icon: Icons.account_balance_outlined,
                          tone: LifeOsAccentTone.amber,
                          title: '${provisionalTxs.length} giao dịch ngân hàng chờ xác nhận',
                          subtitle:
                              '${provisionalTxs.first.merchant} · ${VndAmount.format(provisionalTxs.first.amountMinor)}',
                          badge: 'Đối soát',
                          onTap: () =>
                              context.push('/auto-tx-review', extra: provisionalTxs.first),
                        ),
                      if (upcomingEvents.isNotEmpty)
                        _InboxActionItem(
                          icon: Icons.event_available_rounded,
                          tone: LifeOsAccentTone.emerald,
                          title: upcomingEvents.first.title,
                          subtitle:
                              '${timeFmt.format(upcomingEvents.first.startsAt)} – ${timeFmt.format(upcomingEvents.first.endsAt)}${upcomingEvents.first.location != null ? " · ${upcomingEvents.first.location}" : ""}',
                          badge: 'Sự kiện',
                          onTap: () =>
                              context.push('/event-detail', extra: upcomingEvents.first),
                        ),
                      if (openTasks.isNotEmpty)
                        _InboxActionItem(
                          icon: Icons.task_alt_rounded,
                          tone: LifeOsAccentTone.blue,
                          title: openTasks.first.title,
                          subtitle: openTasks.length > 1
                              ? 'Còn ${openTasks.length} việc cần hoàn thành'
                              : 'Chạm mở bảng việc cần làm',
                          badge: 'Việc làm',
                          onTap: () => context.push('/tasks-board'),
                        ),
                      if (dueVehicles.isNotEmpty)
                        _InboxActionItem(
                          icon: Icons.car_repair_rounded,
                          tone: LifeOsAccentTone.coral,
                          title: 'Bảo dưỡng xe: ${dueVehicles.first.name}',
                          subtitle:
                              'ODO hiện tại ${dueVehicles.first.currentOdometerKm} km · Mốc kế ${dueVehicles.first.nextDueKm} km',
                          badge: 'Đến hạn',
                          onTap: () => context.go('/assets'),
                        ),
                      if (dueBills.isNotEmpty)
                        _InboxActionItem(
                          icon: Icons.receipt_long_outlined,
                          tone: LifeOsAccentTone.amber,
                          title: 'Hóa đơn sắp đến hạn: ${dueBills.first.title}',
                          subtitle:
                              'Dự kiến ${VndAmount.format(dueBills.first.estimatedAmountMinor)}',
                          badge: 'Hóa đơn',
                          onTap: () => context.go('/assets'),
                        ),
                      if (hasConfiguredBudget && spentPct >= 85)
                        _InboxActionItem(
                          icon: Icons.warning_amber_rounded,
                          tone: LifeOsAccentTone.coral,
                          title: 'Cảnh báo ngân sách tháng đã dùng $spentPct%',
                          subtitle:
                              '${VndAmount.format(d.monthlyExpenseMinor)} / ${VndAmount.format(totalBudgetLimit)}',
                          badge: 'Ngân sách',
                          onTap: () => context.go('/finance'),
                        ),
                    ];

                    final bankConnected =
                        (notifState.consent?.enabled ?? false) ||
                        (notifState.savedSePayMaskedToken != null);
                    final gcalConnected = calState.isGoogleAuthorized;
                    final pinnedSpecs = _allShortcuts
                        .where((s) => _pinnedIds.contains(s.id))
                        .toList();

                    return Center(
                      child: ConstrainedBox(
                        constraints:
                            const BoxConstraints(maxWidth: AppSpacing.maxContentWidth),
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.md,
                            2,
                            AppSpacing.md,
                            AppSpacing.xl,
                          ),
                          children: [
                            // 0. OTA In-App Update Notification Banner (hidden when up to date)
                            const AppUpdateBanner(),

                            // 1. Action-First Summary Strip ("Việc cần làm · Lịch sắp tới · Cần xử lý")
                            LifeOsMintHeroCard(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.wb_sunny_outlined,
                                        size: 16,
                                        color: c.primary,
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          todayDateLabel,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                            color: c.textPrimary,
                                          ),
                                        ),
                                      ),
                                      LifeOsStatusPill(
                                        icon: (bankConnected || gcalConnected)
                                            ? Icons.sync_rounded
                                            : Icons.cloud_done_outlined,
                                        label: gcalConnected && bankConnected
                                            ? 'Lịch & Ngân hàng đã nối'
                                            : gcalConnected
                                                ? 'Google Calendar bật'
                                                : bankConnected
                                                    ? 'Tự động ngân hàng bật'
                                                    : 'Đồng bộ Cloud',
                                        tone: LifeOsAccentTone.emerald,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  IntrinsicHeight(
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: _TopKpiCounter(
                                            count: d.openTasksCount,
                                            label: 'Việc cần làm',
                                            onTap: () => context.push('/tasks-board'),
                                          ),
                                        ),
                                        VerticalDivider(width: 12, color: c.separator),
                                        Expanded(
                                          child: _TopKpiCounter(
                                            count: upcomingEvents.length,
                                            label: 'Lịch sắp tới',
                                            onTap: () => context.go('/planning'),
                                          ),
                                        ),
                                        VerticalDivider(width: 12, color: c.separator),
                                        Expanded(
                                          child: _TopKpiCounter(
                                            count: inboxItems.length,
                                            label: 'Cần xử lý',
                                            highlightCoral: provisionalTxs.isNotEmpty ||
                                                dueVehicles.isNotEmpty,
                                            onTap: () {
                                              if (inboxItems.isNotEmpty) {
                                                inboxItems.first.onTap();
                                              } else {
                                                context.push('/activity-feed');
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
                            const SizedBox(height: 10),

                            // 2. Primary Quick Actions Row ("Ghi chi tiêu / Giọng nói" | "Thêm lịch / việc")
                            Row(
                              children: [
                                Expanded(
                                  child: FilledButton.icon(
                                    key: const Key('home_quick_expense_btn'),
                                    onPressed: () => showVoiceSmartCaptureSheet(context),
                                    icon: const Icon(Icons.add_card_rounded, size: 18),
                                    label: const Text(
                                      'Ghi chi tiêu',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: FilledButton.tonalIcon(
                                    key: const Key('home_quick_schedule_btn'),
                                    onPressed: () => showLifeOsQuickCreateHub(context),
                                    icon: const Icon(Icons.event_note_rounded, size: 18),
                                    label: const Text(
                                      'Thêm lịch / việc',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              ],
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
                                      Icon(
                                        Icons.inbox_rounded,
                                        size: 17,
                                        color: c.primary,
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          'LifeOS Inbox · Việc cần chú ý',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 13.8,
                                            fontWeight: FontWeight.w800,
                                            color: c.textPrimary,
                                          ),
                                        ),
                                      ),
                                      if (inboxItems.isNotEmpty)
                                        Text(
                                          '${inboxItems.length} mục',
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w700,
                                            color: c.primary,
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  if (inboxItems.isEmpty)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 6),
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
                                              'Hiện không có giao dịch chờ duyệt, hóa đơn quá hạn hay lịch hẹn khẩn.',
                                              style: TextStyle(
                                                fontSize: 12.2,
                                                color: c.textSecondary,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  else
                                    ...inboxItems.take(4).toList().asMap().entries.map((entry) {
                                      final idx = entry.key;
                                      final item = entry.value;
                                      return Column(
                                        children: [
                                          if (idx > 0) Divider(height: 14, color: c.separator),
                                          InkWell(
                                            borderRadius: BorderRadius.circular(12),
                                            onTap: item.onTap,
                                            child: Padding(
                                              padding: const EdgeInsets.symmetric(vertical: 3),
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
                                                          CrossAxisAlignment.start,
                                                      children: [
                                                        Text(
                                                          item.title,
                                                          maxLines: 1,
                                                          overflow: TextOverflow.ellipsis,
                                                          style: TextStyle(
                                                            fontSize: 12.8,
                                                            fontWeight: FontWeight.w700,
                                                            color: c.textPrimary,
                                                          ),
                                                        ),
                                                        Text(
                                                          item.subtitle,
                                                          maxLines: 1,
                                                          overflow: TextOverflow.ellipsis,
                                                          style: TextStyle(
                                                            fontSize: 11.3,
                                                            color: c.textSecondary,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
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
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),

                            // 4. 2-Column Honest Finance Split: "Chi tháng này" | "Tài sản ròng & Quỹ chung"
                            IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    child: LifeOsSoftCard(
                                      padding: const EdgeInsets.all(12),
                                      onTap: () => context.go('/finance'),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Icon(
                                                Icons.payments_outlined,
                                                size: 16,
                                                color: c.primary,
                                              ),
                                              const SizedBox(width: 5),
                                              Expanded(
                                                child: Text(
                                                  'Chi tháng này',
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w800,
                                                    color: c.textPrimary,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            VndAmount.format(d.monthlyExpenseMinor),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 17,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: -0.3,
                                              color: c.textPrimary,
                                              fontFeatures: const [
                                                FontFeature.tabularFigures(),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          if (hasConfiguredBudget) ...[
                                            Text(
                                              '/ ${VndAmount.format(totalBudgetLimit)} ($spentPct%)',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 11.2,
                                                color: c.textSecondary,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            ClipRRect(
                                              borderRadius: BorderRadius.circular(6),
                                              child: LinearProgressIndicator(
                                                minHeight: 6,
                                                value: (spentPct / 100).clamp(0.03, 1.0),
                                                backgroundColor: c.surfaceRaised,
                                                valueColor: AlwaysStoppedAnimation<Color>(
                                                  spentPct >= 85 ? c.error : c.primary,
                                                ),
                                              ),
                                            ),
                                          ] else
                                            Text(
                                              'Chưa đặt hạn mức tháng · Chạm thiết lập',
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 11.2,
                                                color: c.textSecondary,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: LifeOsSoftCard(
                                      padding: const EdgeInsets.all(12),
                                      onTap: () => context.push('/family-funds'),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Icon(
                                                Icons.account_balance_wallet_outlined,
                                                size: 16,
                                                color: c.primary,
                                              ),
                                              const SizedBox(width: 5),
                                              Expanded(
                                                child: Text(
                                                  'Tài sản & Quỹ',
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w800,
                                                    color: c.textPrimary,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            VndAmount.format(d.netWorthMinor),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 17,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: -0.3,
                                              color: c.textPrimary,
                                              fontFeatures: const [
                                                FontFeature.tabularFigures(),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            hasFamilyFunds
                                                ? 'Quỹ chung: ${VndAmount.format(totalFundsBalance)}'
                                                : familyState.activeFamily != null
                                                    ? '${familyState.activeFamily!.name} · Chưa tạo quỹ chung'
                                                    : 'Cá nhân · Chưa tạo quỹ mục tiêu',
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 11.2,
                                              color: c.textSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),

                            // 5. Customizable Pinned Shortcuts ("Tiện ích của bạn · Tùy chỉnh")
                            LifeOsSoftCard(
                              padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 4),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            'Tiện ích của bạn',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 13.5,
                                              fontWeight: FontWeight.w800,
                                              color: c.textPrimary,
                                            ),
                                          ),
                                        ),
                                        TextButton(
                                          key: const Key('customize_home_shortcuts_btn'),
                                          style: TextButton.styleFrom(
                                            visualDensity: VisualDensity.compact,
                                            padding: const EdgeInsets.symmetric(horizontal: 8),
                                          ),
                                          onPressed: () => _showCustomizeShortcutsSheet(context),
                                          child: const Text('Tùy chỉnh'),
                                        ),
                                        InkWell(
                                          key: const Key('open_super_app_directory_btn'),
                                          borderRadius: BorderRadius.circular(12),
                                          onTap: () => context.push('/super-app-hub'),
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
                                  GridView.count(
                                    shrinkWrap: true,
                                    physics: const NeverScrollableScrollPhysics(),
                                    crossAxisCount: 4,
                                    mainAxisSpacing: 4,
                                    crossAxisSpacing: 4,
                                    childAspectRatio: 1.05,
                                    children: pinnedSpecs.map((spec) {
                                      return LifeOsCompactDockItem(
                                        key: spec.tileKey,
                                        icon: spec.icon,
                                        label: spec.label,
                                        tone: spec.tone,
                                        onTap: () {
                                          if (spec.isBranchGo) {
                                            context.go(spec.route);
                                          } else {
                                            context.push(spec.route);
                                          }
                                        },
                                      );
                                    }).toList(),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),

                            // 6. Clean Utility Strip (Bộ công cụ nâng cao | Danh mục tất cả tính năng)
                            IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    child: LifeOsSoftCard(
                                      key: const Key('open_pro_utilities_hub_card'),
                                      padding: const EdgeInsets.all(11),
                                      onTap: () => context.push('/pro-utilities'),
                                      child: Row(
                                        children: [
                                          const LifeOsIconSquircle(
                                            icon: Icons.calculate_outlined,
                                            tone: LifeOsAccentTone.blue,
                                            size: 34,
                                            iconSize: 18,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Text(
                                                  'Công cụ nâng cao',
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: 12.5,
                                                    color: c.textPrimary,
                                                  ),
                                                ),
                                                Text(
                                                  'Lãi vay · FIRE · Bảo hành',
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: c.textSecondary,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: LifeOsMintHeroCard(
                                      key: const Key('home_tile_all_services'),
                                      padding: const EdgeInsets.all(11),
                                      onTap: () => context.push('/super-app-hub'),
                                      child: Row(
                                        children: [
                                          const LifeOsIconSquircle(
                                            icon: Icons.apps_rounded,
                                            tone: LifeOsAccentTone.emerald,
                                            solidFill: true,
                                            size: 34,
                                            iconSize: 18,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Text(
                                                  'Tất cả danh mục',
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: 12.5,
                                                    color: c.textPrimary,
                                                  ),
                                                ),
                                                Text(
                                                  'Tài chính · Gia đình · Xe',
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: c.textSecondary,
                                                  ),
                                                ),
                                              ],
                                            ),
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

class _TopKpiCounter extends StatelessWidget {
  final int count;
  final String label;
  final VoidCallback onTap;
  final bool highlightCoral;

  const _TopKpiCounter({
    required this.count,
    required this.label,
    required this.onTap,
    this.highlightCoral = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              count.toString().padLeft(2, '0'),
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w800,
                color: highlightCoral ? c.error : c.primary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: c.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
