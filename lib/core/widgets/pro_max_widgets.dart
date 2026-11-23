import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../constants/app_assets.dart';
import '../utils/vnd_amount.dart';
import 'liquid_glass.dart';
import 'status_widgets.dart';

/// Sunken Apple Liquid Glass pill container framing a `TabBar` as an iOS 26 Segmented Control.
class ProPillTabContainer extends StatelessWidget {
  final TabBar tabBar;

  const ProPillTabContainer({super.key, required this.tabBar});

  @override
  Widget build(BuildContext context) {
    final responsiveTabs = tabBar.tabs
        .map((w) {
          if (w is Tab && w.text != null && w.child == null && w.icon == null) {
            return Tab(
              key: w.key,
              height: w.height,
              child: FittedBox(fit: BoxFit.scaleDown, child: Text(w.text!)),
            );
          }
          return w;
        })
        .toList(growable: false);

    final responsiveTabBar = TabBar(
      key: tabBar.key,
      controller: tabBar.controller,
      isScrollable: tabBar.isScrollable,
      padding: tabBar.padding,
      indicatorColor: tabBar.indicatorColor,
      automaticIndicatorColorAdjustment:
          tabBar.automaticIndicatorColorAdjustment,
      indicatorWeight: tabBar.indicatorWeight,
      indicatorPadding: tabBar.indicatorPadding,
      indicator: tabBar.indicator,
      indicatorSize: tabBar.indicatorSize,
      dividerColor: tabBar.dividerColor,
      dividerHeight: tabBar.dividerHeight,
      labelColor: tabBar.labelColor,
      labelStyle: tabBar.labelStyle,
      labelPadding:
          tabBar.labelPadding ?? const EdgeInsets.symmetric(horizontal: 6),
      unselectedLabelColor: tabBar.unselectedLabelColor,
      unselectedLabelStyle: tabBar.unselectedLabelStyle,
      onTap: tabBar.onTap,
      tabs: responsiveTabs,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 8, AppSpacing.md, 6),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppSpacing.maxContentWidth,
          ),
          child: LiquidGlassSurface(
            material: LiquidGlassMaterial.segmentedTrough,
            borderRadius: 23,
            enableBlur: false,
            padding: const EdgeInsets.all(4),
            child: SizedBox(height: 38, child: responsiveTabBar),
          ),
        ),
      ),
    );
  }
}

/// Deep Emerald Mesh Hero Card with luminous ambient orbs & Apple Liquid Glass specular rim.
class ProHeroGradientCard extends StatelessWidget {
  final Widget child;
  final List<Color>? gradientColors;

  const ProHeroGradientCard({
    super.key,
    required this.child,
    this.gradientColors,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors =
        gradientColors ??
        (isDark
            ? const [Color(0xFF073B1A), Color(0xFF0A5C28), Color(0xFF062914)]
            : const [Color(0xFF064E1E), Color(0xFF0B7A2A), Color(0xFF0E9447)]);

    return RepaintBoundary(
      child: CustomPaint(
        foregroundPainter: const LiquidGlassRimPainter(
          borderRadius: 24,
          isDark: true,
          accentRimColor: Color(0xFF63E6BE),
          intensity: 1.12,
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: colors,
            ),
            boxShadow: [
              BoxShadow(
                color: colors[1].withValues(alpha: isDark ? 0.36 : 0.26),
                blurRadius: 26,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Positioned(
                right: -36,
                top: -42,
                child: Container(
                  width: 164,
                  height: 164,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        Colors.white.withValues(alpha: 0.20),
                        Colors.white.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: -28,
                bottom: -48,
                child: Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        const Color(0xFF63E6BE).withValues(alpha: 0.20),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: child,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Translucent Liquid Glass stat pill placed inside `ProHeroGradientCard`.
class ProGlassStatPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color iconColor;

  const ProGlassStatPill({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.iconColor = const Color(0xFF8CE99A),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.20),
            Colors.white.withValues(alpha: 0.10),
          ],
        ),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.28),
          width: 0.95,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: 7),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  softWrap: true,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.86),
                  ),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
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

/// Quick action Liquid Glass pill button styled for Hero cards.
class ProHeroQuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const ProHeroQuickAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.24),
            Colors.white.withValues(alpha: 0.13),
          ],
        ),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.30),
          width: 0.9,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: Colors.white),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Tactile Apple Liquid Glass Bento Grid Tile for 2x2 mobile & desktop dashboards.
class ProBentoTile extends StatelessWidget {
  final IconData icon;
  final String? bananaIconAsset;
  final Color accentColor;
  final String title;
  final String metric;
  final String badgeText;
  final SemanticStatusKind statusKind;
  final VoidCallback onTap;

  const ProBentoTile({
    super.key,
    required this.icon,
    this.bananaIconAsset,
    required this.accentColor,
    required this.title,
    required this.metric,
    required this.badgeText,
    required this.statusKind,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return LiquidGlassSurface(
      material: LiquidGlassMaterial.card,
      borderRadius: 20,
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      enableBlur: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (bananaIconAsset != null)
                BananaGlassIcon(
                  assetPath: bananaIconAsset!,
                  fallbackIcon: icon,
                  fallbackColor: accentColor,
                  size: 40,
                  borderRadius: 12,
                )
              else
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: isDark ? 0.22 : 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: accentColor.withValues(alpha: 0.22),
                      width: 0.85,
                    ),
                  ),
                  child: Icon(icon, size: 20, color: accentColor),
                ),
              Icon(
                Icons.north_east_rounded,
                size: 16,
                color: c.textSecondary.withValues(alpha: 0.7),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              metric,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            title,
            softWrap: true,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          SemanticStatusBadge(kind: statusKind, label: badgeText),
        ],
      ),
    );
  }
}

/// Physical-Digital Apple Wallet / Revolut Bank, Cash, Savings & Credit Card component.
class ProWalletCreditCard extends StatelessWidget {
  final String name;
  final String walletTypeKey; // 'cash' | 'bank' | 'creditCard' | 'savings'
  final int balanceMinor;
  final String? bankCode;
  final String? maskedAccount;
  final bool isEstimatedBalance;
  final bool hasPendingWrites;
  final bool obscureBalance;
  final bool isSelected;
  final VoidCallback? onTap;

  const ProWalletCreditCard({
    super.key,
    required this.name,
    required this.walletTypeKey,
    required this.balanceMinor,
    this.bankCode,
    this.maskedAccount,
    required this.isEstimatedBalance,
    required this.hasPendingWrites,
    this.obscureBalance = false,
    this.isSelected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final (colors, typeLabel, typeIcon, badgeLabel) = switch (walletTypeKey) {
      'bank' => (
        const [Color(0xFF0A2240), Color(0xFF14427A), Color(0xFF0D2E59)],
        'Tài khoản ngân hàng',
        Icons.account_balance_rounded,
        bankCode != null && bankCode!.isNotEmpty ? bankCode! : 'NGÂN HÀNG',
      ),
      'creditCard' => (
        const [Color(0xFF181A20), Color(0xFF2E323D), Color(0xFF121318)],
        'Thẻ tín dụng',
        Icons.credit_card_rounded,
        bankCode != null && bankCode!.isNotEmpty ? bankCode! : 'THẺ TÍN DỤNG',
      ),
      'savings' => (
        const [Color(0xFF543405), Color(0xFF925A0C), Color(0xFF3E2604)],
        'Tiết kiệm & tích lũy',
        Icons.savings_rounded,
        'TIẾT KIỆM',
      ),
      _ => (
        const [Color(0xFF064E1E), Color(0xFF0B7A2A), Color(0xFF073B17)],
        'Tiền mặt sẵn có',
        Icons.payments_rounded,
        'TIỀN MẶT',
      ),
    };

    final cardBody = CustomPaint(
      foregroundPainter: LiquidGlassRimPainter(
        borderRadius: 22,
        isDark: true,
        accentRimColor: isSelected ? const Color(0xFF63E6BE) : null,
        strokeWidth: isSelected ? 2.0 : 1.15,
        intensity: isSelected ? 1.35 : 1.05,
      ),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 276,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
          ),
          boxShadow: [
            BoxShadow(
              color: colors[0].withValues(alpha: isSelected ? 0.38 : 0.24),
              blurRadius: isSelected ? 22 : 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(
                        typeIcon,
                        size: 17,
                        color: Colors.white.withValues(alpha: 0.92),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          name,
                          softWrap: true,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14.5,
                            height: 1.18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.contactless_rounded,
                      size: 16,
                      color: Colors.white.withValues(alpha: 0.65),
                    ),
                    const SizedBox(width: 5),
                    Container(
                      width: 28,
                      height: 20,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(5),
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFDE68A), Color(0xFFD97706)],
                        ),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.35),
                          width: 0.6,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                obscureBalance ? '•••••••• ₫' : VndAmount.format(balanceMinor),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              maskedAccount != null && maskedAccount!.isNotEmpty
                  ? '$typeLabel · $maskedAccount'
                  : '$typeLabel · ${isEstimatedBalance ? "Số dư ước tính" : "Số dư hiện tại"}',
              softWrap: true,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.82),
                fontSize: 11.8,
                height: 1.24,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        hasPendingWrites
                            ? Icons.cloud_upload_outlined
                            : Icons.verified_user_rounded,
                        size: 13.5,
                        color: hasPendingWrites
                            ? const Color(0xFFFCD34D)
                            : const Color(0xFF86EFAC),
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          hasPendingWrites ? 'Đang lưu' : 'Đã đồng bộ',
                          softWrap: true,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    badgeLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (onTap == null) {
      return cardBody;
    }
    return GestureDetector(onTap: onTap, child: cardBody);
  }
}

/// Curated Vietnamese category visual mapping (Nano Banana 3D Glass Squircle Icon + Harmonic Color).
abstract final class ProCategoryStyle {
  static ({IconData icon, Color color, String assetPath}) resolve(
    String categoryName, {
    bool isTransfer = false,
  }) {
    if (isTransfer) {
      return (
        icon: Icons.swap_horiz_rounded,
        color: const Color(0xFF0066CC),
        assetPath: AppAssets.icSysVietQr,
      );
    }
    final lower = categoryName.toLowerCase();
    if (lower.contains('ăn') ||
        lower.contains('cafe') ||
        lower.contains('phở')) {
      return (
        icon: Icons.restaurant_rounded,
        color: const Color(0xFFE8590C),
        assetPath: AppAssets.icCatFood,
      );
    }
    if (lower.contains('việc nhà') || lower.contains('gia dụng')) {
      return (
        icon: Icons.cleaning_services_rounded,
        color: const Color(0xFF0CA678),
        assetPath: AppAssets.icCatHousework,
      );
    }
    if (lower.contains('nhà cửa') ||
        lower.contains('thuê') ||
        lower.contains('trọ')) {
      return (
        icon: Icons.home_work_rounded,
        color: const Color(0xFF5F3DC4),
        assetPath: AppAssets.icCatHousing,
      );
    }
    if (lower.contains('điện') ||
        lower.contains('nước') ||
        lower.contains('internet')) {
      return (
        icon: Icons.bolt_rounded,
        color: const Color(0xFFD97706),
        assetPath: AppAssets.icCatUtilities,
      );
    }
    if (lower.contains('chợ') || lower.contains('mua sắm')) {
      return (
        icon: Icons.shopping_bag_rounded,
        color: const Color(0xFFD6336C),
        assetPath: AppAssets.icCatShopping,
      );
    }
    if (lower.contains('bảo dưỡng') || lower.contains('sửa xe')) {
      return (
        icon: Icons.handyman_rounded,
        color: const Color(0xFF495057),
        assetPath: AppAssets.icCatVehicle,
      );
    }
    if (lower.contains('xe') ||
        lower.contains('di chuyển') ||
        lower.contains('xăng')) {
      return (
        icon: Icons.two_wheeler_rounded,
        color: const Color(0xFF1971C2),
        assetPath: AppAssets.icCatVehicle,
      );
    }
    if (lower.contains('sức khỏe') || lower.contains('giáo dục')) {
      return (
        icon: Icons.favorite_rounded,
        color: const Color(0xFFC92A2A),
        assetPath: AppAssets.icCatHealth,
      );
    }
    if (lower.contains('giải trí') || lower.contains('đăng ký')) {
      return (
        icon: Icons.movie_filter_rounded,
        color: const Color(0xFF7048E8),
        assetPath: AppAssets.icCatShopping,
      );
    }
    if (lower.contains('lương') || lower.contains('thu nhập')) {
      return (
        icon: Icons.payments_rounded,
        color: const Color(0xFF0B7A2A),
        assetPath: AppAssets.icCatIncome,
      );
    }
    if (lower.contains('tiết kiệm') || lower.contains('quỹ')) {
      return (
        icon: Icons.savings_rounded,
        color: const Color(0xFF087F5B),
        assetPath: AppAssets.icCatIncome,
      );
    }
    return (
      icon: Icons.category_rounded,
      color: const Color(0xFF0B7A2A),
      assetPath: AppAssets.icNavFinance,
    );
  }

  static Widget buildCategoryBadge(
    String categoryName, {
    bool isCredit = false,
    bool isTransfer = false,
    double size = 44,
  }) {
    if (isCredit && !isTransfer) {
      return BananaGlassIcon(
        assetPath: AppAssets.icCatIncome,
        fallbackIcon: Icons.south_west_rounded,
        fallbackColor: const Color(0xFF0B7A2A),
        size: size,
        borderRadius: 13,
      );
    }
    final resolved = resolve(categoryName, isTransfer: isTransfer);
    return BananaGlassIcon(
      assetPath: resolved.assetPath,
      fallbackIcon: resolved.icon,
      fallbackColor: resolved.color,
      size: size,
      borderRadius: 13,
    );
  }
}

/// GPU-Rendered 60 FPS Multi-Segment Donut Chart (`CustomPainter`) for Personal Finance Analytics.
class ProDonutSlice {
  final String label;
  final int amountMinor;
  final double pct;
  final Color color;

  const ProDonutSlice({
    required this.label,
    required this.amountMinor,
    required this.pct,
    required this.color,
  });
}

class ProDonutChart extends StatelessWidget {
  final List<ProDonutSlice> slices;
  final int totalExpenseMinor;

  const ProDonutChart({
    super.key,
    required this.slices,
    required this.totalExpenseMinor,
  });

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return Wrap(
      spacing: AppSpacing.lg,
      runSpacing: AppSpacing.md,
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 168,
          height: 168,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: const Size(168, 168),
                painter: _DonutRingPainter(
                  slices: slices,
                  emptyTrackColor: c.separator.withValues(alpha: 0.45),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Tổng chi',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        VndAmount.format(totalExpenseMinor),
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 180, maxWidth: 280),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: slices.take(5).map((s) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: s.color,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        s.label,
                        softWrap: true,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: c.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${s.pct.toStringAsFixed(1)}%',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class _DonutRingPainter extends CustomPainter {
  final List<ProDonutSlice> slices;
  final Color emptyTrackColor;

  const _DonutRingPainter({
    required this.slices,
    required this.emptyTrackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const strokeWidth = 20.0;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final trackPaint = Paint()
      ..color = emptyTrackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawArc(rect, 0, math.pi * 2, false, trackPaint);

    if (slices.isEmpty) return;

    var startAngle = -math.pi / 2;
    final gapRadians = slices.length > 1 ? 0.04 : 0.0;

    for (final slice in slices) {
      final sweep = (slice.pct / 100.0) * (math.pi * 2);
      if (sweep <= 0.005) continue;
      final effectiveSweep = math.max(0.01, sweep - gapRadians);
      final paint = Paint()
        ..color = slice.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(
        rect,
        startAngle + (gapRadians / 2),
        effectiveSweep,
        false,
        paint,
      );
      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutRingPainter oldDelegate) {
    return oldDelegate.slices != slices ||
        oldDelegate.emptyTrackColor != emptyTrackColor;
  }
}

/// Luminous Private-Banking Wealth Sparkline Curve rendered inside `ProHeroGradientCard`.
class ProHeroSparkline extends StatelessWidget {
  final int netWorthMinor;
  final List<int> dailyIncomesMinor;
  final List<int> dailyExpensesMinor;
  final double width;
  final double height;

  const ProHeroSparkline({
    super.key,
    required this.netWorthMinor,
    required this.dailyIncomesMinor,
    required this.dailyExpensesMinor,
    this.width = 112,
    this.height = 46,
  });

  @override
  Widget build(BuildContext context) {
    final pts = <double>[];
    var cursor = netWorthMinor.toDouble();
    final revPoints = <double>[cursor];
    final n = math.min(dailyIncomesMinor.length, dailyExpensesMinor.length);
    for (var i = n - 1; i >= 1; i--) {
      final delta = (dailyIncomesMinor[i] - dailyExpensesMinor[i]).toDouble();
      cursor -= delta;
      revPoints.add(cursor);
    }
    pts.addAll(revPoints.reversed);
    if (pts.length < 7) {
      while (pts.length < 7) {
        pts.insert(0, netWorthMinor * 0.94);
      }
    }
    // Ensure subtle visual progression when flat so the sparkline stays informative
    final minV = pts.reduce(math.min);
    final maxV = pts.reduce(math.max);
    final series = (maxV - minV).abs() < 1.0
        ? <double>[0.35, 0.42, 0.40, 0.54, 0.51, 0.68, 0.78]
        : pts;

    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        size: Size(width, height),
        painter: _SparklineCurvePainter(points: series),
      ),
    );
  }
}

class _SparklineCurvePainter extends CustomPainter {
  final List<double> points;

  const _SparklineCurvePainter({required this.points});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final minVal = points.reduce(math.min);
    final maxVal = points.reduce(math.max);
    final span = math.max(1.0, maxVal - minVal);

    final coords = <Offset>[];
    for (var i = 0; i < points.length; i++) {
      final x = (i / (points.length - 1)) * (size.width - 8) + 4;
      final norm = (points[i] - minVal) / span;
      final y = (size.height - 8) - norm * (size.height - 14) + 4;
      coords.add(Offset(x, y));
    }

    final path = Path()..moveTo(coords.first.dx, coords.first.dy);
    for (var i = 0; i < coords.length - 1; i++) {
      final p0 = coords[i];
      final p1 = coords[i + 1];
      final ctrlX = (p0.dx + p1.dx) / 2;
      path.cubicTo(ctrlX, p0.dy, ctrlX, p1.dy, p1.dx, p1.dy);
    }

    final fillPath = Path.from(path)
      ..lineTo(coords.last.dx, size.height)
      ..lineTo(coords.first.dx, size.height)
      ..close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFF63E6BE).withValues(alpha: 0.34),
          const Color(0xFF63E6BE).withValues(alpha: 0.0),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawPath(fillPath, fillPaint);

    final linePaint = Paint()
      ..color = const Color(0xFF8CE99A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    canvas.drawPath(path, linePaint);

    // Glowing terminal pulse dot
    final end = coords.last;
    canvas.drawCircle(
      end,
      6.5,
      Paint()..color = const Color(0xFF8CE99A).withValues(alpha: 0.28),
    );
    canvas.drawCircle(end, 3.3, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _SparklineCurvePainter oldDelegate) =>
      oldDelegate.points != points;
}

/// Symmetric 1-Row Banking Quick-Action Squircle Button inside `ProHeroGradientCard`.
class ProHeroBankingDockItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const ProHeroBankingDockItem({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withValues(alpha: 0.24),
                        Colors.white.withValues(alpha: 0.12),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.30),
                      width: 0.9,
                    ),
                  ),
                  child: Icon(icon, size: 20, color: Colors.white),
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  softWrap: true,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Executive 7-Day Cashflow Bar Chart + Wealth Allocation & Financial Health Score Card.
class ProCashflowPulseCard extends StatelessWidget {
  final List<int> dailyIncomesMinor;
  final List<int> dailyExpensesMinor;
  final int liquidAssetsMinor;
  final int savingsAssetsMinor;
  final int dailySafeToSpendMinor;
  final int financialHealthScore;
  final bool obscureAmounts;
  final VoidCallback? onTapAnalytics;

  const ProCashflowPulseCard({
    super.key,
    required this.dailyIncomesMinor,
    required this.dailyExpensesMinor,
    required this.liquidAssetsMinor,
    required this.savingsAssetsMinor,
    required this.dailySafeToSpendMinor,
    required this.financialHealthScore,
    this.obscureAmounts = false,
    this.onTapAnalytics,
  });

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final scoreLabel = financialHealthScore >= 80
        ? 'Xuất sắc'
        : (financialHealthScore >= 65 ? 'Tốt' : 'Cần tối ưu');
    final scoreColor = financialHealthScore >= 80
        ? c.success
        : (financialHealthScore >= 65 ? c.primary : c.warning);

    final now = DateTime.now();
    final weekdayLabels = List<String>.generate(7, (idx) {
      final d = now.subtract(Duration(days: 6 - idx));
      return switch (d.weekday) {
        DateTime.sunday => 'CN',
        final w => 'T${w + 1}',
      };
    });

    return LiquidGlassSurface(
      material: LiquidGlassMaterial.card,
      borderRadius: 20,
      padding: const EdgeInsets.all(AppSpacing.md),
      onTap: onTapAnalytics,
      enableBlur: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: c.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.candlestick_chart_rounded,
                  size: 19,
                  color: c.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Dòng tiền 7 ngày',
                      softWrap: true,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'Thu chi thực tế trong tuần',
                      softWrap: true,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: scoreColor.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                  border: Border.all(
                    color: scoreColor.withValues(alpha: 0.3),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.workspace_premium_rounded,
                      size: 14,
                      color: scoreColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$financialHealthScore điểm · $scoreLabel',
                      style: TextStyle(
                        color: scoreColor,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 92,
            width: double.infinity,
            child: CustomPaint(
              painter: _CashflowBarsPainter(
                incomes: dailyIncomesMinor,
                expenses: dailyExpensesMinor,
                incomeColor: c.success,
                expenseColor: const Color(0xFFF59F00),
                gridColor: c.separator.withValues(alpha: 0.45),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: List.generate(7, (idx) {
              final isToday = idx == 6;
              return Expanded(
                child: Text(
                  weekdayLabels[idx],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
                    color: isToday ? c.primary : c.textSecondary,
                  ),
                ),
              );
            }),
          ),
          const Divider(height: 22),
          Row(
            children: [
              _CapitalColumn(
                label: 'Thanh khoản',
                value: obscureAmounts
                    ? '•••••• ₫'
                    : VndAmount.format(liquidAssetsMinor),
                valueColor: c.textPrimary,
              ),
              Container(
                width: 1,
                height: 28,
                color: c.separator.withValues(alpha: 0.6),
              ),
              _CapitalColumn(
                label: 'Tích lũy',
                value: obscureAmounts
                    ? '•••••• ₫'
                    : VndAmount.format(savingsAssetsMinor),
                valueColor: c.success,
              ),
              Container(
                width: 1,
                height: 28,
                color: c.separator.withValues(alpha: 0.6),
              ),
              _CapitalColumn(
                label: 'Hạn mức / ngày',
                value: obscureAmounts
                    ? '•••••• ₫'
                    : VndAmount.format(dailySafeToSpendMinor),
                valueColor: c.secondary,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CapitalColumn extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;

  const _CapitalColumn({
    required this.label,
    required this.value,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              softWrap: true,
              style: Theme.of(context).textTheme.labelSmall,
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 12.8,
                  fontWeight: FontWeight.w800,
                  color: valueColor,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CashflowBarsPainter extends CustomPainter {
  final List<int> incomes;
  final List<int> expenses;
  final Color incomeColor;
  final Color expenseColor;
  final Color gridColor;

  const _CashflowBarsPainter({
    required this.incomes,
    required this.expenses,
    required this.incomeColor,
    required this.expenseColor,
    required this.gridColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.8;

    for (final frac in const [0.0, 0.5, 1.0]) {
      final y = size.height * frac;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    var maxVal = 1;
    for (final v in incomes) {
      if (v > maxVal) maxVal = v;
    }
    for (final v in expenses) {
      if (v > maxVal) maxVal = v;
    }

    // Use logarithmic / dampened scaling so normal daily expenses (e.g. 100k) stay visible
    // next to a monthly salary spike (e.g. 18.5M)!
    double normHeight(int val) {
      if (val <= 0) return 4.0;
      final logV = math.log(val.toDouble() + 1);
      final logMax = math.log(maxVal.toDouble() + 1);
      return (logV / math.max(1.0, logMax)) * (size.height - 8);
    }

    final slotW = size.width / 7;
    const barW = 9.0;

    for (var i = 0; i < 7; i++) {
      final inc = i < incomes.length ? incomes[i] : 0;
      final exp = i < expenses.length ? expenses[i] : 0;
      final cx = slotW * i + slotW / 2;

      final incH = inc > 0 ? math.max(8.0, normHeight(inc)) : 4.0;
      final expH = exp > 0 ? math.max(8.0, normHeight(exp)) : 4.0;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(cx - barW - 1.5, size.height - incH, barW, incH),
          const Radius.circular(4),
        ),
        Paint()..color = inc > 0 ? incomeColor : gridColor,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(cx + 1.5, size.height - expH, barW, expH),
          const Radius.circular(4),
        ),
        Paint()..color = exp > 0 ? expenseColor : gridColor,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CashflowBarsPainter oldDelegate) {
    return oldDelegate.incomes != incomes || oldDelegate.expenses != expenses;
  }
}

/// Bank-Passbook Grade Transaction Row (Revolut / Mercury / Private Banking aesthetic).
class ProFintechStatementTile extends StatelessWidget {
  final String merchant;
  final String categoryName;
  final String? walletName;
  final String timeLabel;
  final int amountMinor;
  final int? balanceAfterMinor;
  final bool isCredit;
  final bool isTransfer;
  final bool isReversed;
  final bool isVerified;
  final bool hasPendingWrites;
  final String? splitSummary;
  final bool obscureAmounts;
  final VoidCallback? onTap;

  const ProFintechStatementTile({
    super.key,
    required this.merchant,
    required this.categoryName,
    this.walletName,
    required this.timeLabel,
    required this.amountMinor,
    this.balanceAfterMinor,
    required this.isCredit,
    required this.isTransfer,
    this.isReversed = false,
    this.isVerified = true,
    this.hasPendingWrites = false,
    this.splitSummary,
    this.obscureAmounts = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);

    final amountColor = isReversed
        ? c.textSecondary
        : (isTransfer ? c.secondary : (isCredit ? c.success : c.textPrimary));

    final formattedAmount = obscureAmounts
        ? '•••••• ₫'
        : (isTransfer
              ? '⇄ ${VndAmount.format(amountMinor)}'
              : VndAmount.format(
                  isCredit ? amountMinor : -amountMinor,
                  showPlus: true,
                ));

    final metaParts = <String>[
      categoryName,
      if (walletName != null && walletName!.isNotEmpty) walletName!,
      timeLabel,
    ];

    return LiquidGlassSurface(
      material: LiquidGlassMaterial.card,
      borderRadius: 18,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      onTap: onTap,
      enableBlur: false,
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              ProCategoryStyle.buildCategoryBadge(
                categoryName,
                isCredit: isCredit,
                isTransfer: isTransfer,
                size: 46,
              ),
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: c.surface,
                    shape: BoxShape.circle,
                  ),
                  padding: const EdgeInsets.all(1.5),
                  child: Icon(
                    hasPendingWrites
                        ? Icons.cloud_upload_rounded
                        : (isVerified
                              ? Icons.verified_rounded
                              : Icons.check_circle_rounded),
                    size: 13,
                    color: hasPendingWrites ? c.warning : c.success,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  merchant,
                  softWrap: true,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.22,
                    decoration: isReversed ? TextDecoration.lineThrough : null,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  metaParts.join(' · '),
                  softWrap: true,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(fontSize: 12, height: 1.28),
                ),
                if (splitSummary != null && splitSummary!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    splitSummary!,
                    softWrap: true,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: c.primary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formattedAmount,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  color: amountColor,
                  decoration: isReversed ? TextDecoration.lineThrough : null,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 3),
              Text(
                isReversed
                    ? 'Đã hoàn tác'
                    : (balanceAfterMinor != null && !obscureAmounts
                          ? 'SD: ${VndAmount.format(balanceAfterMinor!)}'
                          : (hasPendingWrites ? 'Chờ đồng bộ' : 'Đã lưu')),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: c.textSecondary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
