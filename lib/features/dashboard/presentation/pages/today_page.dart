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
import '../../../tasks/domain/entities/task_entities.dart';
import '../../../tasks/presentation/bloc/task_bloc.dart';
import '../../domain/entities/dashboard_entities.dart';
import '../bloc/dashboard_bloc.dart';

/// Screen 01: Airy, Space-Optimized "Trang chủ" (`TodayPage`) — shows essential
/// daily KPIs + a clean 4×2 quick-access dock instead of cramming 20+ tiles vertically.
class TodayPage extends StatelessWidget {
  const TodayPage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final user = context.watch<AuthBloc>().state.user;
    final calState = context.watch<CalendarBloc>().state;
    final taskState = context.watch<TaskBloc>().state;
    final budgetState = context.watch<BudgetBloc>().state;
    final familyState = context.watch<FamilyBloc>().state;

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
                subtitle: 'Quản lý cuộc sống gọn nhẹ mỗi ngày.',
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
                    final completedTasksCount = taskState.tasks
                        .where((t) => t.status == TaskWorkflowStatus.done)
                        .length;
                    final totalBudgetLimit = budgetState.budgets.fold<int>(
                      0,
                      (sum, b) => sum + b.limitMinor,
                    );
                    final effectiveBudget =
                        totalBudgetLimit > 0 ? totalBudgetLimit : 20000000;
                    final spentPct = effectiveBudget > 0
                        ? ((d.monthlyExpenseMinor * 100) / effectiveBudget)
                            .clamp(0, 100)
                            .round()
                        : 0;

                    final totalFundsBalance = budgetState.funds.fold<int>(
                      0,
                      (sum, f) => sum + f.balanceMinor,
                    );
                    final familyFundDisplay =
                        totalFundsBalance > 0 ? totalFundsBalance : d.netWorthMinor;

                    final memberNames =
                        familyState.activeFamily?.members.map((m) => m.fullName).toList() ??
                            <String>[user?.fullName ?? 'Tôi'];

                    final timeFmt = DateFormat('HH:mm');
                    final upcomingEvents = calState.events.take(2).toList();

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

                            // 1. Compact Pastel Mint "Hôm nay" Summary Strip
                            LifeOsMintHeroCard(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.calendar_today_rounded,
                                            size: 16,
                                            color: c.primary,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            'Hôm nay',
                                            style: TextStyle(
                                              fontSize: 14.5,
                                              fontWeight: FontWeight.w800,
                                              color: c.textPrimary,
                                            ),
                                          ),
                                        ],
                                      ),
                                      Flexible(
                                        child: Text(
                                          todayDateLabel,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: c.textSecondary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  IntrinsicHeight(
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: InkWell(
                                            onTap: () => context.go('/planning'),
                                            child: Row(
                                              children: [
                                                Text(
                                                  '${calState.events.length}',
                                                  style: TextStyle(
                                                    fontSize: 21,
                                                    fontWeight: FontWeight.w800,
                                                    color: c.primary,
                                                    fontFeatures: const [
                                                      FontFeature.tabularFigures(),
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                Flexible(
                                                  child: Text(
                                                    'Sự kiện',
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.w600,
                                                      color: c.textSecondary,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        VerticalDivider(width: 12, color: c.separator),
                                        Expanded(
                                          child: InkWell(
                                            onTap: () => context.push('/tasks-board'),
                                            child: Row(
                                              children: [
                                                Text(
                                                  '${d.openTasksCount}',
                                                  style: TextStyle(
                                                    fontSize: 21,
                                                    fontWeight: FontWeight.w800,
                                                    color: c.primary,
                                                    fontFeatures: const [
                                                      FontFeature.tabularFigures(),
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                Flexible(
                                                  child: Text(
                                                    'Việc làm',
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.w600,
                                                      color: c.textSecondary,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        VerticalDivider(width: 12, color: c.separator),
                                        Expanded(
                                          child: InkWell(
                                            onTap: () => context.push('/tasks-board'),
                                            child: Row(
                                              children: [
                                                Icon(
                                                  Icons.check_circle_outline_rounded,
                                                  color: c.primary,
                                                  size: 18,
                                                ),
                                                const SizedBox(width: 4),
                                                Flexible(
                                                  child: Text(
                                                    '$completedTasksCount xong',
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.w600,
                                                      color: c.textSecondary,
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
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),

                            // 2. 2-Column Bento Split: "Lịch sắp tới" | "Chi tháng này"
                            IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    child: LifeOsSoftCard(
                                      padding: const EdgeInsets.all(12),
                                      onTap: () => context.go('/planning'),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Icon(
                                                Icons.schedule_rounded,
                                                size: 16,
                                                color: c.primary,
                                              ),
                                              const SizedBox(width: 5),
                                              Expanded(
                                                child: Text(
                                                  'Lịch sắp tới',
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontSize: 13.2,
                                                    fontWeight: FontWeight.w800,
                                                    color: c.textPrimary,
                                                  ),
                                                ),
                                              ),
                                              Icon(
                                                Icons.chevron_right_rounded,
                                                size: 17,
                                                color: c.textSecondary,
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 10),
                                          if (upcomingEvents.isEmpty) ...[
                                            _MiniScheduleBarItem(
                                              barColor: c.primary,
                                              title: 'Họp & kế hoạch ngày',
                                              time: '10:00 – 11:00',
                                            ),
                                            const SizedBox(height: 7),
                                            const _MiniScheduleBarItem(
                                              barColor: Color(0xFF3B82F6),
                                              title: 'Ăn tối gia đình',
                                              time: '19:00 – 20:00',
                                            ),
                                          ] else
                                            ...upcomingEvents.asMap().entries.map((e) {
                                              final idx = e.key;
                                              final ev = e.value;
                                              return Padding(
                                                padding: EdgeInsets.only(
                                                  bottom: idx < upcomingEvents.length - 1
                                                      ? 7
                                                      : 0,
                                                ),
                                                child: _MiniScheduleBarItem(
                                                  barColor: idx.isEven
                                                      ? c.primary
                                                      : const Color(0xFF3B82F6),
                                                  title: ev.title,
                                                  time:
                                                      '${timeFmt.format(ev.startsAt)} – ${timeFmt.format(ev.endsAt)}',
                                                ),
                                              );
                                            }),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
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
                                                    fontSize: 13.2,
                                                    fontWeight: FontWeight.w800,
                                                    color: c.textPrimary,
                                                  ),
                                                ),
                                              ),
                                              Icon(
                                                Icons.chevron_right_rounded,
                                                size: 17,
                                                color: c.textSecondary,
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 10),
                                          Text(
                                            VndAmount.format(d.monthlyExpenseMinor),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 17.5,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: -0.3,
                                              color: c.textPrimary,
                                              fontFeatures: const [
                                                FontFeature.tabularFigures(),
                                              ],
                                            ),
                                          ),
                                          Text(
                                            '/ ${VndAmount.format(effectiveBudget)}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 11.2,
                                              color: c.textSecondary,
                                            ),
                                          ),
                                          const Spacer(),
                                          const SizedBox(height: 8),
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(6),
                                            child: LinearProgressIndicator(
                                              minHeight: 6,
                                              value: (spentPct / 100).clamp(0.05, 1.0),
                                              backgroundColor: c.surfaceRaised,
                                              valueColor:
                                                  AlwaysStoppedAnimation<Color>(c.primary),
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Đã chi $spentPct% ngân sách',
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
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),

                            // 3. Compact "Quỹ & Tài sản ròng" Card
                            LifeOsSoftCard(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              onTap: () => context.push('/family-funds'),
                              child: Row(
                                children: [
                                  Expanded(
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
                                            const SizedBox(width: 6),
                                            Flexible(
                                              child: Text(
                                                'Quỹ gia đình & Tài sản ròng',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 13.5,
                                                  fontWeight: FontWeight.w800,
                                                  color: c.textPrimary,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          VndAmount.format(familyFundDisplay),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: -0.4,
                                            color: c.textPrimary,
                                            fontFeatures: const [
                                              FontFeature.tabularFigures(),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        LifeOsStatusPill(
                                          icon: Icons.arrow_upward_rounded,
                                          label:
                                              '+${VndAmount.format(d.monthlyIncomeMinor)} thu tháng',
                                          tone: LifeOsAccentTone.emerald,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      LifeOsAvatarStack(
                                        names: memberNames,
                                        radius: 14,
                                        onAddTap: () => context.go('/family'),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${memberNames.length} thành viên',
                                        style: TextStyle(
                                          fontSize: 11.2,
                                          color: c.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),

                            // 4. Clean 4×2 Quick Launcher Dock inside ONE Card (replaces 15 sprawling tiles!)
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
                                            'Tiện ích thường dùng',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 13.5,
                                              fontWeight: FontWeight.w800,
                                              color: c.textPrimary,
                                            ),
                                          ),
                                        ),
                                        InkWell(
                                          key: const Key('open_super_app_directory_btn'),
                                          borderRadius: BorderRadius.circular(12),
                                          onTap: () => context.push('/super-app-hub'),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  'Tất cả 21+',
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
                                    children: [
                                      LifeOsCompactDockItem(
                                        icon: Icons.calendar_today_rounded,
                                        label: 'Lịch',
                                        tone: LifeOsAccentTone.emerald,
                                        onTap: () => context.go('/planning'),
                                      ),
                                      LifeOsCompactDockItem(
                                        icon: Icons.payments_outlined,
                                        label: 'Chi tiêu',
                                        tone: LifeOsAccentTone.emerald,
                                        onTap: () => context.go('/finance'),
                                      ),
                                      LifeOsCompactDockItem(
                                        icon: Icons.groups_outlined,
                                        label: 'Tổ ấm & Nhóm',
                                        tone: LifeOsAccentTone.emerald,
                                        onTap: () => context.go('/family'),
                                      ),
                                      LifeOsCompactDockItem(
                                        icon: Icons.favorite_outline_rounded,
                                        label: 'Sức khỏe',
                                        key: const Key('home_tile_health'),
                                        tone: LifeOsAccentTone.coral,
                                        onTap: () => context.push('/health-hub'),
                                      ),
                                      LifeOsCompactDockItem(
                                        icon: Icons.shopping_basket_outlined,
                                        label: 'Bếp & Đi chợ',
                                        key: const Key('home_tile_kitchen'),
                                        tone: LifeOsAccentTone.emerald,
                                        onTap: () => context.push('/kitchen-groceries'),
                                      ),
                                      LifeOsCompactDockItem(
                                        icon: Icons.electric_bolt_rounded,
                                        label: 'Điện EVN',
                                        key: const Key('home_tile_evn'),
                                        tone: LifeOsAccentTone.amber,
                                        onTap: () => context.push('/home-living'),
                                      ),
                                      LifeOsCompactDockItem(
                                        icon: Icons.folder_open_rounded,
                                        label: 'Tài liệu',
                                        tone: LifeOsAccentTone.amber,
                                        onTap: () => context.push('/family-documents'),
                                      ),
                                      LifeOsCompactDockItem(
                                        icon: Icons.settings_outlined,
                                        label: 'Cài đặt',
                                        tone: LifeOsAccentTone.neutral,
                                        onTap: () => context.push('/settings-hub'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),

                            // 5. Compact 2-Column Ecosystem Strip (Pro 0₫ | Kho 21+ Dịch vụ & Giọng nói AI)
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
                                            icon: Icons.workspace_premium_rounded,
                                            tone: LifeOsAccentTone.blue,
                                            size: 36,
                                            iconSize: 19,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Text(
                                                  'Tiện ích Pro 0₫',
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: 12.8,
                                                    color: c.textPrimary,
                                                  ),
                                                ),
                                                Text(
                                                  'Bill AI · Lãi vay · Hiếu hỷ',
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
                                            size: 36,
                                            iconSize: 19,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Text(
                                                  'Kho Dịch vụ 360°',
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: 12.8,
                                                    color: c.textPrimary,
                                                  ),
                                                ),
                                                Text(
                                                  'Ghi chú · Lương · Widget',
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
                                          InkWell(
                                            borderRadius: BorderRadius.circular(16),
                                            onTap: () => showVoiceSmartCaptureSheet(
                                              context,
                                              autoStartListening: true,
                                            ),
                                            child: Padding(
                                              padding: const EdgeInsets.all(4),
                                              child: Icon(
                                                Icons.mic_rounded,
                                                size: 18,
                                                color: c.primary,
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

class _MiniScheduleBarItem extends StatelessWidget {
  final Color barColor;
  final String title;
  final String time;

  const _MiniScheduleBarItem({
    required this.barColor,
    required this.title,
    required this.time,
  });

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return IntrinsicHeight(
      child: Row(
        children: [
          Container(
            width: 3,
            decoration: BoxDecoration(
              color: barColor,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: c.textPrimary,
                  ),
                ),
                Text(
                  time,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10.8, color: c.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
