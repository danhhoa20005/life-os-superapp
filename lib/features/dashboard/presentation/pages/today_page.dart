import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/theme_bloc.dart';
import '../../../../core/constants/app_assets.dart';
import '../../../../core/utils/smart_quick_entry_parser.dart';
import '../../../../core/utils/vnd_amount.dart';
import '../../../../core/widgets/pro_max_widgets.dart';
import '../../../../core/widgets/status_widgets.dart';
import '../../../app_update/presentation/widgets/app_update_widgets.dart';
import '../../../authentication/presentation/bloc/auth_bloc.dart';
import '../../../authentication/presentation/bloc/auth_event.dart';
import '../../../authentication/presentation/pages/account_profile_page.dart';
import '../../domain/entities/dashboard_entities.dart';
import '../bloc/dashboard_bloc.dart';

class TodayPage extends StatelessWidget {
  const TodayPage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final authState = context.watch<AuthBloc>().state;
    final user = authState.user;

    return Scaffold(
      appBar: LiquidGlassBar(
        leading: const Padding(
          padding: EdgeInsets.all(8.0),
          child: BrandLogoMark(size: 36, borderRadius: 11),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Xin chào, ${user?.fullName ?? 'Life OS'}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              'Trung tâm Điều hành Hôm nay',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
        actions: [
          if (user != null)
            IconButton(
              key: const Key('open_account_profile_button'),
              tooltip: 'Hồ sơ & Bảo mật tài khoản',
              onPressed: () => context.push('/account-profile'),
              icon: UserAvatarBadge(user: user, radius: 16),
            ),
          IconButton(
            tooltip: 'Thông báo ngân hàng & Quyền riêng tư',
            onPressed: () => context.push('/notifications-privacy'),
            icon: const Icon(Icons.shield_outlined),
          ),
          BlocBuilder<ThemeBloc, ThemeState>(
            builder: (context, themeState) {
              final isDark = themeState.themeMode == ThemeMode.dark;
              return IconButton(
                tooltip: 'Đổi giao diện Sáng / Tối',
                onPressed: () {
                  context.read<ThemeBloc>().add(
                        ThemeModeChanged(isDark ? ThemeMode.light : ThemeMode.dark),
                      );
                },
                icon: Icon(isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded),
              );
            },
          ),
          IconButton(
            tooltip: 'Đăng xuất',
            onPressed: () => context.read<AuthBloc>().add(const AuthSignOutRequested()),
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: SafeArea(
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
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: AppSpacing.maxContentWidth),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.sm,
                    AppSpacing.md,
                    AppSpacing.xl,
                  ),
                  children: [
                    // 0. Automatic OTA In-App Update Notification Banner (when new release exists)
                    const AppUpdateBanner(),

                    // 1. Flagship Emerald Mesh Hero Card (UI/UX Pro Max)
                    ProHeroGradientCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              Text(
                                'TÀI SẢN RÒNG ƯỚC TÍNH',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.9,
                                  color: Colors.white.withValues(alpha: 0.8),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.lock_rounded, size: 12, color: Colors.white),
                                    SizedBox(width: 4),
                                    Text(
                                      'Chỉ mình bạn thấy',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            VndAmount.format(d.netWorthMinor),
                            style: const TextStyle(
                              fontSize: 34,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: -0.8,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              ProGlassStatPill(
                                icon: Icons.south_west_rounded,
                                label: 'Thu tháng này',
                                value: VndAmount.format(d.monthlyIncomeMinor),
                                iconColor: const Color(0xFF86EFAC),
                              ),
                              ProGlassStatPill(
                                icon: Icons.north_east_rounded,
                                label: 'Chi tháng này',
                                value: VndAmount.format(d.monthlyExpenseMinor),
                                iconColor: const Color(0xFFFDE68A),
                              ),
                              ProGlassStatPill(
                                icon: Icons.today_rounded,
                                label: 'Chi hôm nay',
                                value: VndAmount.format(d.todayExpenseMinor),
                                iconColor: const Color(0xFFFCA5A5),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              ProHeroQuickAction(
                                icon: Icons.add_card_rounded,
                                label: 'Ghi chi tiêu',
                                onTap: () => context.go('/finance'),
                              ),
                              ProHeroQuickAction(
                                icon: Icons.call_split_rounded,
                                label: 'Chia tiền nhóm',
                                onTap: () => context.go('/family'),
                              ),
                              ProHeroQuickAction(
                                icon: Icons.add_task_rounded,
                                label: 'Giao việc',
                                onTap: () => context.go('/planning'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: AppSpacing.md),

                    // 2. True 2x2 Bento Grid (Mobile & Tablet Responsive!)
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final cols = constraints.maxWidth >= 720 ? 4 : 2;
                        final aspect = constraints.maxWidth >= 720
                            ? 1.25
                            : (constraints.maxWidth >= 380 ? 1.18 : 1.05);
                        return GridView.count(
                          crossAxisCount: cols,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: aspect,
                          children: [
                            ProBentoTile(
                              icon: Icons.pending_actions_rounded,
                              accentColor: const Color(0xFFD97706),
                              title: 'Giao dịch chờ duyệt',
                              metric: '${d.provisionalPendingCount}',
                              badgeText: d.provisionalPendingCount > 0
                                  ? 'Cần xác nhận'
                                  : 'Đã đối soát sạch',
                              statusKind: d.provisionalPendingCount > 0
                                  ? SemanticStatusKind.provisional
                                  : SemanticStatusKind.success,
                              onTap: () => context.go('/finance'),
                            ),
                            ProBentoTile(
                              icon: Icons.task_alt_rounded,
                              accentColor: const Color(0xFF0CA678),
                              title: 'Nhiệm vụ & Việc nhà',
                              metric: '${d.openTasksCount} mở',
                              badgeText: d.proposedTasksForMeCount > 0
                                  ? '${d.proposedTasksForMeCount} lời mời mới'
                                  : 'Đồng thuận ổn định',
                              statusKind: d.proposedTasksForMeCount > 0
                                  ? SemanticStatusKind.warning
                                  : SemanticStatusKind.info,
                              onTap: () => context.go('/planning'),
                            ),
                            ProBentoTile(
                              icon: Icons.event_available_rounded,
                              accentColor: const Color(0xFF1971C2),
                              title: 'Lịch trình sắp tới',
                              metric: '${d.upcomingEventsCount}',
                              badgeText: 'Riêng tư & Gia đình',
                              statusKind: SemanticStatusKind.info,
                              onTap: () => context.go('/planning'),
                            ),
                            ProBentoTile(
                              icon: Icons.two_wheeler_rounded,
                              accentColor: const Color(0xFF5F3DC4),
                              title: 'Bảo dưỡng xe',
                              metric: '${d.dueVehiclesCount} xe',
                              badgeText:
                                  d.dueVehiclesCount > 0 ? 'Sắp đến hạn km' : 'Vận hành tốt',
                              statusKind: d.dueVehiclesCount > 0
                                  ? SemanticStatusKind.warning
                                  : SemanticStatusKind.success,
                              onTap: () => context.go('/assets'),
                            ),
                          ],
                        );
                      },
                    ),

                    const SizedBox(height: AppSpacing.md),
                    Builder(
                      builder: (context) {
                        final runway = EmergencyRunwaySnapshot.compute(
                          netLiquidMinor: d.netWorthMinor,
                          monthlyExpenseMinor: d.monthlyExpenseMinor,
                        );
                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpacing.md),
                            child: Row(
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: c.primarySubtle,
                                    borderRadius: BorderRadius.circular(13),
                                  ),
                                  child: Icon(Icons.health_and_safety_rounded, color: c.primary),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 4,
                                        crossAxisAlignment: WrapCrossAlignment.center,
                                        children: [
                                          Text(
                                            'Quỹ Dự phòng Khẩn cấp',
                                            style: Theme.of(context).textTheme.titleSmall,
                                          ),
                                          SemanticStatusBadge(
                                            kind: runway.monthsOfRunway >= 3.0
                                                ? SemanticStatusKind.success
                                                : SemanticStatusKind.warning,
                                            label: runway.statusBadge,
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        runway.headline,
                                        style: Theme.of(context).textTheme.bodySmall,
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

                    const SizedBox(height: AppSpacing.lg),
                    Row(
                      children: [
                        Icon(Icons.auto_awesome_rounded, size: 18, color: c.primary),
                        const SizedBox(width: 6),
                        Text(
                          'Trợ lý Quan sát & Gợi ý Tự động',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    if (d.highlights.isEmpty)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: Image.asset(
                                  AppAssets.dashboardBanner,
                                  width: 76,
                                  height: 64,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      Icon(Icons.check_circle_rounded, color: c.success, size: 32),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Nhịp sống hôm nay rất cân bằng!',
                                      style: Theme.of(context).textTheme.titleMedium,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Không có cảnh báo hóa đơn bất thường, xe quá hạn hay giao dịch chờ xác nhận.',
                                      style: Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      ...d.highlights.map(
                        (item) => Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                          child: Card(
                            child: ListTile(
                              leading: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: (item.isUrgent ? c.warning : c.primary)
                                      .withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  item.isUrgent
                                      ? Icons.notification_important_rounded
                                      : Icons.auto_awesome_rounded,
                                  color: item.isUrgent ? c.warning : c.primary,
                                ),
                              ),
                              title: Text(
                                item.title,
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                              subtitle: Text(item.subtitle),
                              trailing: const Icon(Icons.chevron_right_rounded),
                              onTap: () {
                                if (item.category == 'provisional_tx') {
                                  context.go('/finance');
                                } else {
                                  context.go('/assets');
                                }
                              },
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
