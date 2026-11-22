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

/// Screen 01: "Trang chủ" (`01_Trang_chu.png`) following Unified LifeOS Design System.
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
                subtitle: 'Quản lý cuộc sống, đơn giản hơn mỗi ngày.',
                profileTrailing: user == null
                    ? null
                    : IconButton(
                        key: const Key('open_account_profile_button'),
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Hồ sơ & Bảo mật tài khoản',
                        onPressed: () => context.push('/account-profile'),
                        icon: UserAvatarBadge(user: user, radius: 17),
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
                    final upcomingEvents = calState.events.take(3).toList();

                    return Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: AppSpacing.maxContentWidth),
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.md,
                            2,
                            AppSpacing.md,
                            AppSpacing.xxl,
                          ),
                          children: [
                            // 0. Automatic OTA In-App Update Notification Banner
                            const AppUpdateBanner(),

                            // 1. Pastel Mint "Hôm nay" Summary Card (3 Columns: Sự kiện | Việc cần làm | Đã hoàn thành)
                            LifeOsMintHeroCard(
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
                                            size: 19,
                                            color: c.primary,
                                          ),
                                          const SizedBox(width: 7),
                                          Text(
                                            'Hôm nay',
                                            style: TextStyle(
                                              fontSize: 16,
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
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w600,
                                            color: c.textSecondary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 14),
                                  IntrinsicHeight(
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: InkWell(
                                            onTap: () => context.go('/planning'),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  '${calState.events.length}',
                                                  style: TextStyle(
                                                    fontSize: 25,
                                                    fontWeight: FontWeight.w800,
                                                    color: c.primary,
                                                    fontFeatures: const [
                                                      FontFeature.tabularFigures(),
                                                    ],
                                                  ),
                                                ),
                                                Text(
                                                  'Sự kiện',
                                                  style: TextStyle(
                                                    fontSize: 12.5,
                                                    fontWeight: FontWeight.w600,
                                                    color: c.textSecondary,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        VerticalDivider(width: 16, color: c.separator),
                                        Expanded(
                                          child: InkWell(
                                            onTap: () => context.push('/tasks-board'),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  '${d.openTasksCount}',
                                                  style: TextStyle(
                                                    fontSize: 25,
                                                    fontWeight: FontWeight.w800,
                                                    color: c.primary,
                                                    fontFeatures: const [
                                                      FontFeature.tabularFigures(),
                                                    ],
                                                  ),
                                                ),
                                                Text(
                                                  'Việc cần làm',
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontSize: 12.5,
                                                    fontWeight: FontWeight.w600,
                                                    color: c.textSecondary,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        VerticalDivider(width: 16, color: c.separator),
                                        Expanded(
                                          child: InkWell(
                                            onTap: () => context.push('/tasks-board'),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Icon(
                                                  Icons.check_circle_outline_rounded,
                                                  color: c.primary,
                                                  size: 24,
                                                ),
                                                const SizedBox(height: 3),
                                                Text(
                                                  '$completedTasksCount đã hoàn thành',
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
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
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),

                            // 2. 2-Column Split Row: "Lịch sắp tới" | "Chi tiêu tháng này"
                            IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // Left Card: Lịch sắp tới
                                  Expanded(
                                    child: LifeOsSoftCard(
                                      padding: const EdgeInsets.all(14),
                                      onTap: () => context.go('/planning'),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Icon(
                                                Icons.calendar_today_rounded,
                                                size: 17,
                                                color: c.primary,
                                              ),
                                              const SizedBox(width: 6),
                                              Expanded(
                                                child: Text(
                                                  'Lịch sắp tới',
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w800,
                                                    color: c.textPrimary,
                                                  ),
                                                ),
                                              ),
                                              Icon(
                                                Icons.chevron_right_rounded,
                                                size: 18,
                                                color: c.textSecondary,
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 12),
                                          if (upcomingEvents.isEmpty) ...[
                                            _MiniScheduleBarItem(
                                              barColor: c.primary,
                                              title: 'Họp team & kế hoạch',
                                              time: '10:00 – 11:00',
                                            ),
                                            const SizedBox(height: 9),
                                            const _MiniScheduleBarItem(
                                              barColor: Color(0xFF3B82F6),
                                              title: 'Ăn tối cùng gia đình',
                                              time: '19:00 – 20:00',
                                            ),
                                          ] else
                                            ...upcomingEvents.asMap().entries.map((e) {
                                              final idx = e.key;
                                              final ev = e.value;
                                              return Padding(
                                                padding: EdgeInsets.only(
                                                  bottom:
                                                      idx < upcomingEvents.length - 1 ? 8 : 0,
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
                                  const SizedBox(width: 12),

                                  // Right Card: Chi tiêu tháng này
                                  Expanded(
                                    child: LifeOsSoftCard(
                                      padding: const EdgeInsets.all(14),
                                      onTap: () => context.go('/finance'),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Icon(
                                                Icons.payments_outlined,
                                                size: 17,
                                                color: c.primary,
                                              ),
                                              const SizedBox(width: 6),
                                              Expanded(
                                                child: Text(
                                                  'Chi tiêu tháng này',
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w800,
                                                    color: c.textPrimary,
                                                  ),
                                                ),
                                              ),
                                              Icon(
                                                Icons.chevron_right_rounded,
                                                size: 18,
                                                color: c.textSecondary,
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 12),
                                          Text(
                                            VndAmount.format(d.monthlyExpenseMinor),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 19,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: -0.4,
                                              color: c.textPrimary,
                                              fontFeatures: const [
                                                FontFeature.tabularFigures(),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '/ ${VndAmount.format(effectiveBudget)}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: c.textSecondary,
                                            ),
                                          ),
                                          const Spacer(),
                                          const SizedBox(height: 10),
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(8),
                                            child: LinearProgressIndicator(
                                              minHeight: 8,
                                              value: (spentPct / 100).clamp(0.05, 1.0),
                                              backgroundColor: c.surfaceRaised,
                                              valueColor:
                                                  AlwaysStoppedAnimation<Color>(c.primary),
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            'Đã chi $spentPct% ngân sách',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 11.5,
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
                            const SizedBox(height: 12),

                            // 3. "Quỹ gia đình" Card with Member Avatars (`01_Trang_chu.png`)
                            LifeOsSoftCard(
                              onTap: () => context.push('/family-funds'),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.groups_outlined, size: 20, color: c.primary),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Quỹ gia đình & Tài sản ròng',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 15.5,
                                            fontWeight: FontWeight.w800,
                                            color: c.textPrimary,
                                          ),
                                        ),
                                      ),
                                      Icon(
                                        Icons.chevron_right_rounded,
                                        color: c.textSecondary,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              VndAmount.format(familyFundDisplay),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 23,
                                                fontWeight: FontWeight.w800,
                                                letterSpacing: -0.5,
                                                color: c.textPrimary,
                                                fontFeatures: const [
                                                  FontFeature.tabularFigures(),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            LifeOsStatusPill(
                                              icon: Icons.arrow_upward_rounded,
                                              label:
                                                  '+${VndAmount.format(d.monthlyIncomeMinor)} (thu tháng)',
                                              tone: LifeOsAccentTone.emerald,
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          LifeOsAvatarStack(
                                            names: memberNames,
                                            radius: 16,
                                            onAddTap: () => context.go('/family'),
                                          ),
                                          const SizedBox(height: 5),
                                          Text(
                                            '${memberNames.length} thành viên',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: c.textSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),

                            // 4. Unified 3×3 Feature Squircle Grid (`01_Trang_chu.png` + Full Suite)
                            GridView.count(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              crossAxisCount: 3,
                              mainAxisSpacing: 10,
                              crossAxisSpacing: 10,
                              childAspectRatio: 1.06,
                              children: [
                                LifeOsFeatureGridTile(
                                  icon: Icons.calendar_today_rounded,
                                  label: 'Lịch',
                                  tone: LifeOsAccentTone.emerald,
                                  onTap: () => context.go('/planning'),
                                ),
                                LifeOsFeatureGridTile(
                                  icon: Icons.payments_outlined,
                                  label: 'Chi tiêu',
                                  tone: LifeOsAccentTone.emerald,
                                  onTap: () => context.go('/finance'),
                                ),
                                LifeOsFeatureGridTile(
                                  icon: Icons.groups_outlined,
                                  label: 'Tổ ấm & Nhóm',
                                  tone: LifeOsAccentTone.emerald,
                                  onTap: () => context.go('/family'),
                                ),
                                LifeOsFeatureGridTile(
                                  icon: Icons.check_box_outlined,
                                  label: 'Việc làm',
                                  tone: LifeOsAccentTone.emerald,
                                  onTap: () => context.push('/tasks-board'),
                                ),
                                LifeOsFeatureGridTile(
                                  icon: Icons.directions_car_outlined,
                                  label: 'Xe cộ',
                                  tone: LifeOsAccentTone.blue,
                                  onTap: () => context.go('/assets'),
                                ),
                                LifeOsFeatureGridTile(
                                  icon: Icons.notifications_none_rounded,
                                  label: 'Thông báo',
                                  tone: LifeOsAccentTone.emerald,
                                  onTap: () => context.push('/activity-notifications'),
                                ),
                                LifeOsFeatureGridTile(
                                  icon: Icons.savings_outlined,
                                  label: 'Quỹ chung',
                                  tone: LifeOsAccentTone.emerald,
                                  onTap: () => context.push('/family-funds'),
                                ),
                                LifeOsFeatureGridTile(
                                  icon: Icons.folder_open_rounded,
                                  label: 'Tài liệu',
                                  tone: LifeOsAccentTone.amber,
                                  onTap: () => context.push('/family-documents'),
                                ),
                                LifeOsFeatureGridTile(
                                  icon: Icons.settings_outlined,
                                  label: 'Cài đặt',
                                  tone: LifeOsAccentTone.emerald,
                                  onTap: () => context.push('/settings-hub'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // 4b. Paid-Market Replacement Pro Suite Banner ("Tiện ích Pro 0₫")
                            LifeOsSoftCard(
                              key: const Key('open_pro_utilities_hub_card'),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              onTap: () => context.push('/pro-utilities'),
                              child: Row(
                                children: [
                                  const LifeOsIconSquircle(
                                    icon: Icons.workspace_premium_rounded,
                                    tone: LifeOsAccentTone.emerald,
                                    size: 42,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                'Tiện ích Pro 0₫ (Thay 6 App Trả Phí)',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 13.8,
                                                  color: c.textPrimary,
                                                ),
                                              ),
                                            ),
                                            const LifeOsStatusPill(
                                              label: 'MỚI',
                                              tone: LifeOsAccentTone.emerald,
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Radar Gói đăng ký & Bảo hành · Quét Bill AI · Pomodoro · Sổ Hiếu Hỷ',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: c.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(Icons.chevron_right_rounded, color: c.textSecondary),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),

                            // 5. Voice Sentence Split AI & 4 Android Home Screen Widgets Quick Card
                            LifeOsMintHeroCard(
                              key: const Key('open_home_widgets_studio_card'),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              onTap: () => context.push('/home-widgets'),
                              child: Row(
                                children: [
                                  const LifeOsIconSquircle(
                                    icon: Icons.widgets_outlined,
                                    tone: LifeOsAccentTone.emerald,
                                    solidFill: true,
                                    size: 40,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Tự động Cập nhật & 4 Widget Màn Hình Chính',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 13.8,
                                            color: c.textPrimary,
                                          ),
                                        ),
                                        Text(
                                          'Bắt số dư tự động · Ghim 4 Widget · Nói câu chia tiền AI',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: c.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton.filled(
                                    visualDensity: VisualDensity.compact,
                                    tooltip: 'Nói câu chia tiền bằng Giọng nói AI',
                                    onPressed: () => showVoiceSmartCaptureSheet(
                                      context,
                                      autoStartListening: true,
                                    ),
                                    icon: const Icon(Icons.mic_rounded, size: 18),
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
            width: 3.5,
            decoration: BoxDecoration(
              color: barColor,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.8,
                    fontWeight: FontWeight.w700,
                    color: c.textPrimary,
                  ),
                ),
                Text(
                  time,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: c.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
