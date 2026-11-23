import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/lifeos_brand_colors.dart';
import '../../../../core/utils/user_behavior_prefs.dart';
import '../../../../core/utils/vnd_amount.dart';
import '../../../../core/widgets/lifeos_design_system.dart';
import '../../../../core/widgets/pro_max_widgets.dart';
import '../../../../core/widgets/status_widgets.dart';
import '../../../app_update/presentation/widgets/app_update_widgets.dart';
import '../../../authentication/presentation/bloc/auth_bloc.dart';
import '../../../authentication/presentation/pages/account_profile_page.dart';
import '../../../budgets/presentation/bloc/budget_bloc.dart';
import '../../../calendar/presentation/bloc/calendar_bloc.dart';
import '../../../family/presentation/bloc/family_bloc.dart';
import '../../../notifications/presentation/bloc/notification_ingestion_bloc.dart';
import '../../../tasks/domain/entities/task_entities.dart';
import '../../../tasks/domain/repositories/task_repository.dart';
import '../../../tasks/presentation/bloc/task_bloc.dart';
import '../../../transactions/domain/entities/transaction_entities.dart';
import '../../../transactions/presentation/bloc/transaction_bloc.dart';
import '../../../transactions/presentation/bloc/transaction_event.dart';
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

  const _InboxActionItem({
    required this.icon,
    required this.tone,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.onTap,
    this.quickActionLabel,
    this.onQuickAction,
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

  @override
  void initState() {
    super.initState();
    _hydrateUserPrefs();
  }

  Future<void> _hydrateUserPrefs() async {
    await UserBehaviorPrefs.loadLastWalletId();
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

  String _fmtMoney(int minor, {String prefix = ''}) {
    if (_hideBalances) return '$prefix•••••••• ₫';
    return '$prefix${VndAmount.format(minor)}';
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
                const SizedBox(height: 4),
                Text(
                  'Chọn tối thiểu 4 tiện ích thường dùng — tự động ghi nhớ cho các lần mở sau.',
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
    final funds = context.select((BudgetBloc b) => b.state.funds);
    final activeFamilyName = context.select(
      (FamilyBloc b) => b.state.activeFamily?.name,
    );
    final allTransactions = context.select(
      (TransactionListBloc b) => b.state.allTransactions,
    );
    final vehicles = context.select((VehicleBloc b) => b.state.vehicles);
    final bills = context.select((VehicleBloc b) => b.state.bills);
    final bankConnected = context.select(
      (NotificationIngestionBloc b) =>
          (b.state.consent?.enabled ?? false) ||
          b.state.linkedBankAccounts.isNotEmpty,
    );

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
    final todayDateLabel =
        '${UserBehaviorPrefs.contextualTimeSubtitle(now)} · ${weekdays[now.weekday]}, ${now.day} thg ${now.month}';

    return Scaffold(
      body: LifeOsMintWaveCanvas(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              LifeOsTopBrandHeader(
                title: 'Xin chào, $firstName',
                subtitle: todayDateLabel,
                profileTrailing: user == null
                    ? null
                    : IconButton(
                        key: const Key('open_account_profile_button'),
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Hồ sơ tài khoản',
                        onPressed: () => context.push('/account-profile'),
                        icon: UserAvatarBadge(user: user, radius: 16),
                      ),
              ),
              Expanded(
                child: BlocBuilder<DashboardBloc, DashboardState>(
                  builder: (context, state) {
                    if (state.isLoading &&
                        state.data == TodayDashboardEntity.empty) {
                      return const Center(child: CircularProgressIndicator());
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

                    final totalFundsBalance = funds.fold<int>(
                      0,
                      (sum, f) => sum + f.balanceMinor,
                    );
                    final hasFamilyFunds = funds.isNotEmpty;

                    // Unified Cross-Feature Inbox (100% Real Data)
                    final upcomingEvents =
                        calEvents.where((e) => !e.endsAt.isBefore(now)).toList()
                          ..sort((a, b) => a.startsAt.compareTo(b.startsAt));

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
                          onQuickAction: user == null
                              ? null
                              : () {
                                  final firstTx = provisionalTxs.first;
                                  context.read<TransactionActionBloc>().add(
                                    ProvisionalTransactionDecisionSubmitted(
                                      userId: user.id,
                                      transactionId: firstTx.id,
                                      approve: true,
                                    ),
                                  );
                                  LifeOsTopToast.show(
                                    context,
                                    'Đã duyệt giao dịch ${firstTx.merchant}.',
                                  );
                                },
                        ),
                      if (upcomingEvents.isNotEmpty)
                        _InboxActionItem(
                          icon: Icons.event_available_rounded,
                          tone: LifeOsAccentTone.emerald,
                          title: upcomingEvents.first.title,
                          subtitle:
                              '${timeFmt.format(upcomingEvents.first.startsAt)} – ${timeFmt.format(upcomingEvents.first.endsAt)}${upcomingEvents.first.location != null && upcomingEvents.first.location!.isNotEmpty ? " · ${upcomingEvents.first.location}" : ""}',
                          badge: 'Lịch hẹn',
                          onTap: () => context.push(
                            '/event-detail',
                            extra: upcomingEvents.first,
                          ),
                        ),
                      if (openTasks.isNotEmpty)
                        _InboxActionItem(
                          icon: Icons.task_alt_rounded,
                          tone: LifeOsAccentTone.blue,
                          title: openTasks.first.title,
                          subtitle: openTasks.length > 1
                              ? 'Còn ${openTasks.length} việc cần làm'
                              : 'Chạm để mở việc cần làm',
                          badge: 'Việc làm',
                          onTap: () => context.push('/tasks-board'),
                          quickActionLabel: user != null ? '✓ Xong' : null,
                          onQuickAction: user == null
                              ? null
                              : () {
                                  final t = openTasks.first;
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
                            2,
                            AppSpacing.md,
                            104,
                          ),
                          children: [
                            // 0. OTA In-App Update Notification Banner
                            const AppUpdateBanner(),

                            // 1. Flagship Emerald-Forest Fintech Hero Card (Apple Wallet × Revolut)
                            ProHeroGradientCard(
                              gradientColors: const [
                                LifeOSBrandColors.forest,
                                LifeOSBrandColors.primary,
                                Color(0xFF159E3A),
                              ],
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(
                                            alpha: 0.14,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                          border: Border.all(
                                            color: Colors.white.withValues(
                                              alpha: 0.22,
                                            ),
                                            width: 0.8,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Container(
                                              width: 6.5,
                                              height: 6.5,
                                              decoration: const BoxDecoration(
                                                color: Color(0xFF86EFAC),
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              syncStatusLabel,
                                              style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const Spacer(),
                                      InkWell(
                                        key: const Key(
                                          'toggle_balance_privacy_btn',
                                        ),
                                        borderRadius: BorderRadius.circular(18),
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
                                                ? 'Đã bật chế độ ẩn số dư riêng tư (tự nhớ cho lần sau).'
                                                : 'Đã hiển thị lại số dư tài chính.',
                                            kind: LifeOsToastKind.info,
                                            duration: const Duration(
                                              milliseconds: 1800,
                                            ),
                                          );
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.all(6),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withValues(
                                              alpha: 0.14,
                                            ),
                                            shape: BoxShape.circle,
                                          ),
                                          child: Icon(
                                            _hideBalances
                                                ? Icons.visibility_off_outlined
                                                : Icons.visibility_outlined,
                                            size: 17,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Tổng tài sản ròng cá nhân',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white.withValues(
                                        alpha: 0.82,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      _fmtMoney(d.netWorthMinor),
                                      style: const TextStyle(
                                        fontSize: 27.5,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: -0.6,
                                        color: Colors.white,
                                        fontFeatures: [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: 0.12,
                                      ),
                                      borderRadius: BorderRadius.circular(11),
                                    ),
                                    child: Wrap(
                                      spacing: 12,
                                      runSpacing: 4,
                                      children: [
                                        Text(
                                          'Hôm nay chi: ${_fmtMoney(todayExpenseMinor)}',
                                          style: TextStyle(
                                            fontSize: 11.8,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.white.withValues(
                                              alpha: 0.94,
                                            ),
                                            fontFeatures: const [
                                              FontFeature.tabularFigures(),
                                            ],
                                          ),
                                        ),
                                        if (hasConfiguredBudget)
                                          Text(
                                            'Còn tiêu/ngày: ${_fmtMoney(safeDailyMinor)}',
                                            style: const TextStyle(
                                              fontSize: 11.8,
                                              fontWeight: FontWeight.w700,
                                              color: Color(0xFF86EFAC),
                                              fontFeatures: [
                                                FontFeature.tabularFigures(),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _HeroGlassCapsule(
                                          icon: Icons.south_west_rounded,
                                          iconColor: const Color(0xFF86EFAC),
                                          label: 'Thu tháng',
                                          value: _fmtMoney(
                                            d.monthlyIncomeMinor,
                                            prefix: '+',
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: _HeroGlassCapsule(
                                          icon: Icons.north_east_rounded,
                                          iconColor: const Color(0xFFFCA5A5),
                                          label: 'Chi tháng',
                                          value: _fmtMoney(
                                            d.monthlyExpenseMinor,
                                            prefix: '-',
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Material(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                          child: InkWell(
                                            key: const Key(
                                              'home_quick_expense_btn',
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                            onTap: () =>
                                                showLifeOsQuickCreateHub(
                                                  context,
                                                ),
                                            child: ConstrainedBox(
                                              constraints: const BoxConstraints(
                                                minHeight: 44,
                                              ),
                                              child: const Padding(
                                                padding: EdgeInsets.symmetric(
                                                  horizontal: 10,
                                                  vertical: 10,
                                                ),
                                                child: FittedBox(
                                                  fit: BoxFit.scaleDown,
                                                  child: Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .center,
                                                    children: [
                                                      Icon(
                                                        Icons.mic_rounded,
                                                        size: 17,
                                                        color: LifeOSBrandColors
                                                            .primary,
                                                      ),
                                                      SizedBox(width: 6),
                                                      Text(
                                                        'Ghi chi tiêu',
                                                        style: TextStyle(
                                                          fontSize: 13,
                                                          fontWeight:
                                                              FontWeight.w800,
                                                          color:
                                                              LifeOSBrandColors
                                                                  .forest,
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
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Material(
                                          color: Colors.white.withValues(
                                            alpha: 0.16,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                            side: BorderSide(
                                              color: Colors.white.withValues(
                                                alpha: 0.28,
                                              ),
                                            ),
                                          ),
                                          child: InkWell(
                                            key: const Key(
                                              'home_quick_schedule_btn',
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                            onTap: () =>
                                                showLifeOsQuickCreateHub(
                                                  context,
                                                ),
                                            child: ConstrainedBox(
                                              constraints: const BoxConstraints(
                                                minHeight: 44,
                                              ),
                                              child: const Padding(
                                                padding: EdgeInsets.symmetric(
                                                  horizontal: 10,
                                                  vertical: 10,
                                                ),
                                                child: FittedBox(
                                                  fit: BoxFit.scaleDown,
                                                  child: Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .center,
                                                    children: [
                                                      Icon(
                                                        Icons
                                                            .event_note_rounded,
                                                        size: 17,
                                                        color: Colors.white,
                                                      ),
                                                      SizedBox(width: 6),
                                                      Text(
                                                        'Thêm lịch / việc',
                                                        style: TextStyle(
                                                          fontSize: 13,
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
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),

                            // 2. 3-Column Daily Pulse Bento Row
                            IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    child: _PulseMiniBentoCard(
                                      icon: Icons.task_alt_rounded,
                                      tone: LifeOsAccentTone.blue,
                                      count: d.openTasksCount,
                                      label: 'Việc cần làm',
                                      onTap: () => context.push('/tasks-board'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _PulseMiniBentoCard(
                                      icon: Icons.schedule_rounded,
                                      tone: LifeOsAccentTone.emerald,
                                      count: upcomingEvents.length,
                                      label: 'Lịch sắp tới',
                                      onTap: () => context.go('/planning'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _PulseMiniBentoCard(
                                      icon: Icons.inbox_rounded,
                                      tone:
                                          (provisionalTxs.isNotEmpty ||
                                              dueVehicles.isNotEmpty)
                                          ? LifeOsAccentTone.coral
                                          : LifeOsAccentTone.amber,
                                      count: inboxItems.length,
                                      label: 'Cần xử lý',
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
                                        Icons.bolt_rounded,
                                        size: 18,
                                        color: c.primary,
                                      ),
                                      const SizedBox(width: 5),
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
                                  else
                                    ...inboxItems.take(4).toList().asMap().entries.map((
                                      entry,
                                    ) {
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
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
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
                                                                FontWeight.w700,
                                                            color:
                                                                c.textPrimary,
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
                                                            color:
                                                                c.textSecondary,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  if (item.onQuickAction !=
                                                          null &&
                                                      item.quickActionLabel !=
                                                          null)
                                                    FilledButton.tonal(
                                                      style: FilledButton.styleFrom(
                                                        visualDensity:
                                                            VisualDensity
                                                                .compact,
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 10,
                                                              vertical: 4,
                                                            ),
                                                      ),
                                                      onPressed:
                                                          item.onQuickAction,
                                                      child: Text(
                                                        item.quickActionLabel!,
                                                        style: const TextStyle(
                                                          fontSize: 11.8,
                                                          fontWeight:
                                                              FontWeight.w800,
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
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),

                            // 4. 2-Column Honest Finance Split: "Ngân sách tháng" | "Quỹ mục tiêu"
                            IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    child: LifeOsSoftCard(
                                      padding: const EdgeInsets.all(12),
                                      onTap: () => context.go('/finance'),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Icon(
                                                Icons.donut_large_rounded,
                                                size: 16,
                                                color: c.primary,
                                              ),
                                              const SizedBox(width: 5),
                                              Expanded(
                                                child: Text(
                                                  'Ngân sách tháng',
                                                  softWrap: true,
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
                                          if (hasConfiguredBudget) ...[
                                            FittedBox(
                                              fit: BoxFit.scaleDown,
                                              alignment: Alignment.centerLeft,
                                              child: Text(
                                                '$spentPct% đã dùng',
                                                style: TextStyle(
                                                  fontSize: 16.5,
                                                  fontWeight: FontWeight.w800,
                                                  color: spentPct >= 85
                                                      ? c.error
                                                      : c.textPrimary,
                                                  fontFeatures: const [
                                                    FontFeature.tabularFigures(),
                                                  ],
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 3),
                                            Text(
                                              'Hạn mức: ${_fmtMoney(totalBudgetLimit)}',
                                              softWrap: true,
                                              style: TextStyle(
                                                fontSize: 11.8,
                                                height: 1.25,
                                                color: c.textSecondary,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              child: LinearProgressIndicator(
                                                minHeight: 6,
                                                value: (spentPct / 100).clamp(
                                                  0.03,
                                                  1.0,
                                                ),
                                                backgroundColor:
                                                    c.surfaceRaised,
                                                valueColor:
                                                    AlwaysStoppedAnimation<
                                                      Color
                                                    >(
                                                      spentPct >= 85
                                                          ? c.error
                                                          : c.primary,
                                                    ),
                                              ),
                                            ),
                                          ] else ...[
                                            Text(
                                              'Chưa đặt hạn mức',
                                              softWrap: true,
                                              style: TextStyle(
                                                fontSize: 14.5,
                                                fontWeight: FontWeight.w800,
                                                color: c.textPrimary,
                                              ),
                                            ),
                                            const SizedBox(height: 3),
                                            Text(
                                              'Chạm để thiết lập hạn mức chi tiêu thật',
                                              softWrap: true,
                                              style: TextStyle(
                                                fontSize: 11.8,
                                                height: 1.25,
                                                color: c.textSecondary,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: LifeOsSoftCard(
                                      padding: const EdgeInsets.all(12),
                                      onTap: () =>
                                          context.push('/family-funds'),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Icon(
                                                Icons.savings_outlined,
                                                size: 16,
                                                color: c.primary,
                                              ),
                                              const SizedBox(width: 5),
                                              Expanded(
                                                child: Text(
                                                  'Quỹ mục tiêu',
                                                  softWrap: true,
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
                                          FittedBox(
                                            fit: BoxFit.scaleDown,
                                            alignment: Alignment.centerLeft,
                                            child: Text(
                                              hasFamilyFunds
                                                  ? _fmtMoney(totalFundsBalance)
                                                  : 'Chưa tạo quỹ',
                                              style: TextStyle(
                                                fontSize: hasFamilyFunds
                                                    ? 16.5
                                                    : 14.5,
                                                fontWeight: FontWeight.w800,
                                                color: c.textPrimary,
                                                fontFeatures: const [
                                                  FontFeature.tabularFigures(),
                                                ],
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            activeFamilyName != null
                                                ? 'Nhóm: $activeFamilyName'
                                                : 'Chưa tạo nhóm chung',
                                            softWrap: true,
                                            style: TextStyle(
                                              fontSize: 11.8,
                                              height: 1.25,
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
                            // 5. Clearly Separated Section: Lối tắt nhanh & Khám phá 360°
                            const LifeOsSectionHeader(
                              title: 'Lối tắt chuyên sâu',
                              tone: LifeOsAccentTone.purple,
                              padding: EdgeInsets.only(
                                top: 10,
                                bottom: 6,
                                left: 2,
                                right: 2,
                              ),
                            ),
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
                                          child: Text(
                                            'Tiện ích của bạn',
                                            softWrap: true,
                                            style: TextStyle(
                                              fontSize: 13.5,
                                              fontWeight: FontWeight.w800,
                                              color: c.textPrimary,
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

class _HeroGlassCapsule extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;

  const _HeroGlassCapsule({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.2),
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Icon(icon, size: 14, color: iconColor),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  softWrap: true,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.86),
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
              value,
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PulseMiniBentoCard extends StatelessWidget {
  final IconData icon;
  final LifeOsAccentTone tone;
  final int count;
  final String label;
  final VoidCallback onTap;

  const _PulseMiniBentoCard({
    required this.icon,
    required this.tone,
    required this.count,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final (_, fg) = tone.resolve(context);
    return LifeOsSoftCard(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      borderRadius: 18,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              LifeOsIconSquircle(
                icon: icon,
                tone: tone,
                size: 28,
                iconSize: 15,
              ),
              const Spacer(),
              Text(
                count.toString().padLeft(2, '0'),
                style: TextStyle(
                  fontSize: 18.5,
                  fontWeight: FontWeight.w800,
                  color: fg,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            label,
            softWrap: true,
            style: TextStyle(
              fontSize: 12.2,
              height: 1.2,
              fontWeight: FontWeight.w700,
              color: c.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
