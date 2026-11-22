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
import '../../../../core/widgets/voice_smart_capture_sheet.dart';
import '../../../app_update/presentation/widgets/app_update_widgets.dart';
import '../../../authentication/presentation/bloc/auth_bloc.dart';
import '../../../authentication/presentation/pages/account_profile_page.dart';
import '../../domain/entities/dashboard_entities.dart';
import '../bloc/dashboard_bloc.dart';

class TodayPage extends StatefulWidget {
  const TodayPage({super.key});

  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> {
  bool _obscureAmounts = false;

  String _fmt(int minor, {bool showPlus = false}) {
    if (_obscureAmounts) return '•••••• ₫';
    return VndAmount.format(minor, showPlus: showPlus);
  }

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
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: c.success,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    'QUẢN TRỊ TÀI SẢN · CLOUD SYNC',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.7,
                      color: c.primary,
                    ),
                  ),
                ),
              ],
            ),
            Text(
              user?.fullName ?? 'Life OS Wealth',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ],
        ),
        actions: [
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Đối soát SePay & Quyền riêng tư',
            onPressed: () => context.push('/notifications-privacy'),
            icon: const Icon(Icons.verified_user_outlined, size: 21),
          ),
          BlocBuilder<ThemeBloc, ThemeState>(
            builder: (context, themeState) {
              final isDark = themeState.themeMode == ThemeMode.dark;
              return IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Đổi giao diện Sáng / Tối',
                onPressed: () {
                  context.read<ThemeBloc>().add(
                        ThemeModeChanged(isDark ? ThemeMode.light : ThemeMode.dark),
                      );
                },
                icon: Icon(
                  isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                  size: 21,
                ),
              );
            },
          ),
          if (user != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: IconButton(
                key: const Key('open_account_profile_button'),
                visualDensity: VisualDensity.compact,
                tooltip: 'Hồ sơ & Bảo mật tài khoản',
                onPressed: () => context.push('/account-profile'),
                icon: UserAvatarBadge(user: user, radius: 16),
              ),
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
            final runway = EmergencyRunwaySnapshot.compute(
              netLiquidMinor: d.netWorthMinor,
              monthlyExpenseMinor: d.monthlyExpenseMinor,
            );

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
                    // 0. Automatic OTA In-App Update Notification Banner
                    const AppUpdateBanner(),

                    // 1. Flagship Private-Banking Net Worth & Cashflow Hero Card
                    ProHeroGradientCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Flexible(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Flexible(
                                      child: Text(
                                        'TỔNG TÀI SẢN RÒNG',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.9,
                                          color: Colors.white.withValues(alpha: 0.84),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    InkWell(
                                      borderRadius: BorderRadius.circular(20),
                                      onTap: () =>
                                          setState(() => _obscureAmounts = !_obscureAmounts),
                                      child: Padding(
                                        padding: const EdgeInsets.all(4),
                                        child: Icon(
                                          _obscureAmounts
                                              ? Icons.visibility_off_outlined
                                              : Icons.visibility_outlined,
                                          size: 16,
                                          color: Colors.white.withValues(alpha: 0.85),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.22),
                                    width: 0.7,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      d.monthlyIncomeMinor > 0 && d.netCashFlowMinor >= 0
                                          ? Icons.trending_up_rounded
                                          : Icons.lock_rounded,
                                      size: 13,
                                      color: const Color(0xFF8CE99A),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      d.monthlyIncomeMinor > 0
                                          ? 'Tiết kiệm ${d.savingsRatePct.clamp(-99, 99).toStringAsFixed(0)}%'
                                          : 'Sổ cái Bảo mật',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        fontFeatures: [FontFeature.tabularFigures()],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _obscureAmounts
                                          ? '•••••••••• ₫'
                                          : VndAmount.format(d.netWorthMinor),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 32,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white,
                                        letterSpacing: -0.8,
                                        fontFeatures: [FontFeature.tabularFigures()],
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${d.walletCount > 0 ? d.walletCount : 1} nguồn vốn · Chuẩn đối soát Kép (VND)',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.white.withValues(alpha: 0.76),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              ProHeroSparkline(
                                netWorthMinor: d.netWorthMinor,
                                dailyIncomesMinor: d.recent7DayIncomesMinor,
                                dailyExpensesMinor: d.recent7DayExpensesMinor,
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Symmetric 3-Column Financial Strip (Thu tháng · Chi tháng · Chi hôm nay)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.16),
                                width: 0.8,
                              ),
                            ),
                            child: IntrinsicHeight(
                              child: Row(
                                children: [
                                  _HeroLedgerMetric(
                                    label: '↓ Thu tháng',
                                    value: _fmt(d.monthlyIncomeMinor),
                                    accentColor: const Color(0xFF86EFAC),
                                  ),
                                  VerticalDivider(
                                    width: 14,
                                    thickness: 0.8,
                                    color: Colors.white.withValues(alpha: 0.18),
                                  ),
                                  _HeroLedgerMetric(
                                    label: '↑ Chi tháng',
                                    value: _fmt(d.monthlyExpenseMinor),
                                    accentColor: const Color(0xFFFDE68A),
                                  ),
                                  VerticalDivider(
                                    width: 14,
                                    thickness: 0.8,
                                    color: Colors.white.withValues(alpha: 0.18),
                                  ),
                                  _HeroLedgerMetric(
                                    label: '⚡ Hôm nay',
                                    value: _fmt(d.todayExpenseMinor),
                                    accentColor: const Color(0xFFFCA5A5),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),

                          // Symmetric 4-Button Banking & Voice AI Action Dock
                          Row(
                            children: [
                              ProHeroBankingDockItem(
                                icon: Icons.mic_rounded,
                                label: 'Giọng nói AI',
                                onTap: () => showVoiceSmartCaptureSheet(context),
                              ),
                              ProHeroBankingDockItem(
                                icon: Icons.add_card_rounded,
                                label: 'Thu / Chi',
                                onTap: () => context.go('/finance'),
                              ),
                              ProHeroBankingDockItem(
                                icon: Icons.qr_code_2_rounded,
                                label: 'Chia bill QR',
                                onTap: () => context.go('/family'),
                              ),
                              ProHeroBankingDockItem(
                                icon: Icons.widgets_rounded,
                                label: '4 Widget',
                                onTap: () => context.push('/home-widgets'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: AppSpacing.sm),

                    // 1b. Zero-Touch Auto-Update & 4 Home Screen Widgets Quick Strip
                    Container(
                      decoration: BoxDecoration(
                        color: c.surface,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: c.primary.withValues(alpha: 0.32),
                          width: 0.9,
                        ),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          key: const Key('open_home_widgets_studio_card'),
                          borderRadius: BorderRadius.circular(18),
                          onTap: () => context.push('/home-widgets'),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                            child: Row(
                              children: [
                                Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [Color(0xFF064E1E), Color(0xFF10B981)],
                                    ),
                                    borderRadius: BorderRadius.circular(11),
                                  ),
                                  child: const Icon(
                                    Icons.widgets_rounded,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 11),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Tự động Cập nhật & 4 Widget Màn Hình Chính',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                              fontWeight: FontWeight.w800,
                                            ),
                                      ),
                                      Text(
                                        'Bắt số dư không cần ghi tay · Ghim 4 Widget · Nói để chia tiền',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context).textTheme.labelSmall,
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton.filledTonal(
                                  visualDensity: VisualDensity.compact,
                                  tooltip: 'Nói để Ghi / Chia tiền ngay',
                                  onPressed: () => showVoiceSmartCaptureSheet(
                                    context,
                                    autoStartListening: true,
                                  ),
                                  icon: const Icon(Icons.mic_rounded, size: 18),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: AppSpacing.md),

                    // 2. 7-Day Cashflow Bar Chart & Capital Allocation Pulse Card
                    ProCashflowPulseCard(
                      dailyIncomesMinor: d.recent7DayIncomesMinor,
                      dailyExpensesMinor: d.recent7DayExpensesMinor,
                      liquidAssetsMinor: d.liquidAssetsMinor,
                      savingsAssetsMinor: d.savingsAssetsMinor,
                      dailySafeToSpendMinor: d.dailySafeToSpendMinor,
                      financialHealthScore: d.financialHealthScore,
                      obscureAmounts: _obscureAmounts,
                      onTapAnalytics: () => context.go('/finance'),
                    ),

                    const SizedBox(height: AppSpacing.md),

                    // 3. Wealth-First 2x2 Bento Grid
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
                              icon: Icons.account_balance_wallet_rounded,
                              bananaIconAsset: AppAssets.icNavFinance,
                              accentColor: const Color(0xFF0B7A2A),
                              title: d.provisionalPendingCount > 0
                                  ? 'Giao dịch chờ duyệt'
                                  : 'Thặng dư Dòng tiền',
                              metric: d.provisionalPendingCount > 0
                                  ? '${d.provisionalPendingCount} khoản'
                                  : _fmt(d.netCashFlowMinor, showPlus: true),
                              badgeText: d.provisionalPendingCount > 0
                                  ? 'Cần xác nhận SMS'
                                  : 'Đã đối soát sạch',
                              statusKind: d.provisionalPendingCount > 0
                                  ? SemanticStatusKind.provisional
                                  : SemanticStatusKind.success,
                              onTap: () => context.go('/finance'),
                            ),
                            ProBentoTile(
                              icon: Icons.shield_rounded,
                              bananaIconAsset: AppAssets.icSysShield,
                              accentColor: const Color(0xFF0CA678),
                              title: 'Sức bền Quỹ Dự phòng',
                              metric: _obscureAmounts
                                  ? '••• tháng'
                                  : '${runway.monthsOfRunway.toStringAsFixed(1)} tháng',
                              badgeText: runway.statusBadge,
                              statusKind: runway.monthsOfRunway >= 3.0
                                  ? SemanticStatusKind.success
                                  : SemanticStatusKind.warning,
                              onTap: () => context.go('/finance'),
                            ),
                            ProBentoTile(
                              icon: Icons.event_available_rounded,
                              bananaIconAsset: AppAssets.icNavCalendar,
                              accentColor: const Color(0xFF1971C2),
                              title: 'Lịch thanh toán & Việc',
                              metric: '${d.upcomingEventsCount} lịch · ${d.openTasksCount} việc',
                              badgeText: d.proposedTasksForMeCount > 0
                                  ? '${d.proposedTasksForMeCount} đề xuất mới'
                                  : 'Đồng bộ Google',
                              statusKind: d.proposedTasksForMeCount > 0
                                  ? SemanticStatusKind.warning
                                  : SemanticStatusKind.info,
                              onTap: () => context.go('/planning'),
                            ),
                            ProBentoTile(
                              icon: Icons.two_wheeler_rounded,
                              bananaIconAsset: AppAssets.icCatVehicle,
                              accentColor: const Color(0xFF5F3DC4),
                              title: 'Tài sản & Chi phí Xe',
                              metric: '${d.dueVehiclesCount} đến hạn',
                              badgeText: d.dueVehiclesCount > 0
                                  ? 'Sắp đến hạn km'
                                  : 'Chi phí ổn định',
                              statusKind: d.dueVehiclesCount > 0
                                  ? SemanticStatusKind.warning
                                  : SemanticStatusKind.success,
                              onTap: () => context.go('/assets'),
                            ),
                          ],
                        );
                      },
                    ),

                    if (d.topCategories.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.md),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Top Tỷ Trọng Chi Tiêu Trong Tháng',
                                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                          fontWeight: FontWeight.w800,
                                        ),
                                  ),
                                  TextButton(
                                    onPressed: () => context.go('/finance'),
                                    child: const Text('Chi tiết →'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              ...d.topCategories.map((cat) {
                                final style = ProCategoryStyle.resolve(cat.categoryName);
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: Row(
                                    children: [
                                      ProCategoryStyle.buildCategoryBadge(
                                        cat.categoryName,
                                        size: 38,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Flexible(
                                                  child: Text(
                                                    cat.categoryName,
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      fontSize: 13,
                                                      fontWeight: FontWeight.w700,
                                                    ),
                                                  ),
                                                ),
                                                Text(
                                                  '${_fmt(cat.amountMinor)} (${cat.sharePct.toStringAsFixed(0)}%)',
                                                  style: const TextStyle(
                                                    fontSize: 12.5,
                                                    fontWeight: FontWeight.w800,
                                                    fontFeatures: [FontFeature.tabularFigures()],
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 5),
                                            ClipRRect(
                                              borderRadius: BorderRadius.circular(5),
                                              child: LinearProgressIndicator(
                                                minHeight: 6,
                                                value: (cat.sharePct / 100.0).clamp(0.02, 1.0),
                                                color: style.color,
                                                backgroundColor:
                                                    style.color.withValues(alpha: 0.12),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: AppSpacing.lg),
                    Row(
                      children: [
                        Icon(Icons.auto_awesome_rounded, size: 18, color: c.primary),
                        const SizedBox(width: 6),
                        Text(
                          'Kiểm toán Tự động & Cảnh báo Sổ quỹ',
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
                              BananaGlassIcon(
                                assetPath: AppAssets.icSysShield,
                                fallbackIcon: Icons.verified_rounded,
                                fallbackColor: c.success,
                                size: 46,
                                borderRadius: 13,
                              ),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Sổ cái cân bằng & Đối soát an toàn',
                                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Mọi bút toán đều khớp số dư ví, không có hóa đơn trễ hạn hay biến động bất thường.',
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

class _HeroLedgerMetric extends StatelessWidget {
  final String label;
  final String value;
  final Color accentColor;

  const _HeroLedgerMetric({
    required this.label,
    required this.value,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: accentColor,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
