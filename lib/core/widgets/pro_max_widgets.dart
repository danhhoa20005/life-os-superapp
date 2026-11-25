import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../constants/app_assets.dart';
import '../motion/lifeos_motion.dart';
import '../utils/vnd_amount.dart';
import 'liquid_glass.dart';
import 'status_widgets.dart';
import 'trust_ux_widgets.dart';

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
            borderRadius: 14,
            enableBlur: false,
            rimIntensity: 0.45,
            padding: const EdgeInsets.all(3.5),
            child: SizedBox(height: 37, child: responsiveTabBar),
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
            ? const [Color(0xFF166B33), Color(0xFF1C8540), Color(0xFF135C2B)]
            : const [Color(0xFF0F7F36), Color(0xFF159943), Color(0xFF1CB04F)]);

    return RepaintBoundary(
      child: CustomPaint(
        foregroundPainter: const LiquidGlassRimPainter(
          borderRadius: 24,
          isDark: true,
          accentRimColor: Color(0xFFE6FFF0),
          intensity: 0.92,
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
                color: colors[1].withValues(alpha: isDark ? 0.28 : 0.22),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.16 : 0.06),
                blurRadius: 5,
                offset: const Offset(0, 2.5),
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
    final resolvedBanana =
        bananaIconAsset ?? AppAssets.resolveBananaIconForGlyph(icon);

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
              if (resolvedBanana != null)
                BananaGlassIcon(
                  assetPath: resolvedBanana,
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

    final skinAsset = AppAssets.resolveBankCardSkin(
      walletTypeKey: walletTypeKey,
      bankCode: bankCode,
      walletName: name,
    );

    final cardBody = CustomPaint(
      foregroundPainter: LiquidGlassRimPainter(
        borderRadius: 22,
        isDark: true,
        accentRimColor: isSelected ? const Color(0xFF63E6BE) : null,
        strokeWidth: isSelected ? 2.0 : 1.15,
        intensity: isSelected ? 1.35 : 1.08,
      ),
      child: AnimatedContainer(
        duration: LifeOsMotionScope.of(
          context,
        ).resolveDuration(LifeOsMotionTokens.micro),
        width: 276,
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
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned.fill(
              child: Image.asset(
                skinAsset,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.black.withValues(alpha: 0.10),
                      Colors.black.withValues(alpha: 0.30),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
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
                      obscureBalance
                          ? '•••••••• ₫'
                          : VndAmount.format(balanceMinor),
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
          ],
        ),
      ),
    );

    if (onTap == null) {
      return cardBody;
    }
    return LifeOsPressable(
      onPressed: onTap,
      semanticsSelected: isSelected,
      semanticsLabel:
          'Ví $name, ${obscureBalance ? "đang ẩn số dư" : VndAmount.format(balanceMinor)}',
      child: cardBody,
    );
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
    if (lower.contains('ô tô') || lower.contains('oto')) {
      return (
        icon: Icons.directions_car_filled_outlined,
        color: const Color(0xFF1971C2),
        assetPath: AppAssets.icCatVehicle,
      );
    }
    if (lower.contains('bảo dưỡng') || lower.contains('sửa xe')) {
      return (
        icon: Icons.two_wheeler_rounded,
        color: const Color(0xFF0B7A2A),
        assetPath: AppAssets.icCatScooter,
      );
    }
    if (lower.contains('xe') ||
        lower.contains('di chuyển') ||
        lower.contains('xăng')) {
      return (
        icon: Icons.two_wheeler_rounded,
        color: const Color(0xFF087F5B),
        assetPath: AppAssets.icCatScooter,
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
        assetPath: AppAssets.icToolSubscription,
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
    final radius = size * 0.30;
    if (isCredit && !isTransfer) {
      return BananaGlassIcon(
        assetPath: AppAssets.icCatIncome,
        fallbackIcon: Icons.south_west_rounded,
        fallbackColor: const Color(0xFF0B7A2A),
        size: size,
        borderRadius: radius,
      );
    }
    final resolved = resolve(categoryName, isTransfer: isTransfer);
    return BananaGlassIcon(
      assetPath: resolved.assetPath,
      fallbackIcon: resolved.icon,
      fallbackColor: resolved.color,
      size: size,
      borderRadius: radius,
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

class ProDonutChart extends StatefulWidget {
  final List<ProDonutSlice> slices;
  final int totalExpenseMinor;
  final String centerTitle;

  const ProDonutChart({
    super.key,
    required this.slices,
    required this.totalExpenseMinor,
    this.centerTitle = 'Tổng chi',
  });

  @override
  State<ProDonutChart> createState() => _ProDonutChartState();
}

class _ProDonutChartState extends State<ProDonutChart> {
  int? _selectedIdx;

  @override
  void didUpdateWidget(covariant ProDonutChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_selectedIdx != null && _selectedIdx! >= widget.slices.length) {
      _selectedIdx = null;
    }
  }

  void _toggleSlice(int idx) {
    LifeOsMotionScope.read(context).selectionHaptic();
    setState(() {
      _selectedIdx = _selectedIdx == idx ? null : idx;
    });
  }

  void _handleRingTap(Offset localPos, Size ringSize) {
    if (widget.slices.isEmpty) return;
    final center = Offset(ringSize.width / 2, ringSize.height / 2);
    final delta = localPos - center;
    final dist = delta.distance;
    final outerR = ringSize.width / 2;
    if (dist < outerR * 0.42 || dist > outerR * 1.06) {
      if (_selectedIdx != null) {
        setState(() => _selectedIdx = null);
      }
      return;
    }

    var angle = math.atan2(delta.dy, delta.dx) + (math.pi / 2);
    if (angle < 0) angle += math.pi * 2;

    final visible = widget.slices.where((s) => s.pct > 0).toList();
    if (visible.isEmpty) return;
    final totalPct = visible.fold<double>(0.0, (sum, s) => sum + s.pct);
    if (totalPct <= 0) return;

    var cursor = 0.0;
    for (var i = 0; i < widget.slices.length; i++) {
      final s = widget.slices[i];
      if (s.pct <= 0) continue;
      final sweep = (s.pct / totalPct) * (math.pi * 2);
      if (angle >= cursor && angle <= cursor + sweep) {
        _toggleSlice(i);
        return;
      }
      cursor += sweep;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final motion = LifeOsMotionScope.of(context);
    final tickersEnabled = TickerMode.valuesOf(context).enabled;
    final donutDataKey = ValueKey<int>(
      Object.hash(
        widget.totalExpenseMinor,
        Object.hashAll(
          widget.slices.map((s) => Object.hash(s.label, s.amountMinor)),
        ),
      ),
    );
    final activeSlice =
        (_selectedIdx != null && _selectedIdx! < widget.slices.length)
        ? widget.slices[_selectedIdx!]
        : null;
    final topSlices = widget.slices.take(6).toList(growable: false);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 430;
        const ringDim = 176.0;

        final donutRing = SizedBox(
          width: ringDim,
          height: ringDim,
          child: GestureDetector(
            key: const Key('pro_donut_ring_gesture'),
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) => _handleRingTap(
              details.localPosition,
              const Size(ringDim, ringDim),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                TweenAnimationBuilder<double>(
                  key: donutDataKey,
                  tween: Tween<double>(
                    begin: (motion.isReducedMotion || !tickersEnabled)
                        ? 1.0
                        : 0.0,
                    end: 1.0,
                  ),
                  duration: motion.resolveDuration(LifeOsMotionTokens.medium),
                  curve: LifeOsMotionTokens.emphasizedCurve,
                  builder: (context, sweepProgress, _) {
                    return CustomPaint(
                      size: const Size(ringDim, ringDim),
                      painter: _DonutRingPainter(
                        slices: widget.slices,
                        selectedIndex: _selectedIdx,
                        sweepProgress: sweepProgress.clamp(0.0, 1.0),
                        emptyTrackColor: c.separator.withValues(alpha: 0.45),
                        innerRingColor: c.separator.withValues(alpha: 0.25),
                      ),
                    );
                  },
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: AnimatedSwitcher(
                    duration: motion.resolveDuration(
                      LifeOsMotionTokens.standard,
                    ),
                    switchInCurve: LifeOsMotionTokens.standardCurve,
                    child: Column(
                      key: ValueKey<String>(
                        activeSlice != null
                            ? 'slice_${activeSlice.label}'
                            : 'total_${widget.totalExpenseMinor}',
                      ),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          activeSlice?.label ?? widget.centerTitle,
                          textAlign: TextAlign.center,
                          softWrap: true,
                          style: TextStyle(
                            fontSize: 11.2,
                            height: 1.15,
                            fontWeight: FontWeight.w700,
                            color: activeSlice != null
                                ? activeSlice.color
                                : c.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 3),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            VndAmount.format(
                              activeSlice?.amountMinor ??
                                  widget.totalExpenseMinor,
                            ),
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: c.textPrimary,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          activeSlice != null
                              ? '${activeSlice.pct.toStringAsFixed(1)}% tỷ trọng'
                              : (widget.slices.isEmpty
                                    ? '0 danh mục'
                                    : '${widget.slices.length} danh mục · Chạm xem'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 10.2,
                            fontWeight: FontWeight.w600,
                            color: c.textSecondary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );

        final legendList = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: List.generate(topSlices.length, (i) {
            final s = topSlices[i];
            final isSelected = _selectedIdx == i;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2.5),
              child: InkWell(
                key: Key('pro_donut_legend_$i'),
                borderRadius: BorderRadius.circular(10),
                onTap: () => _toggleSlice(i),
                child: AnimatedContainer(
                  duration: LifeOsMotionScope.of(
                    context,
                  ).resolveDuration(LifeOsMotionTokens.micro),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? s.color.withValues(alpha: 0.12)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected
                          ? s.color.withValues(alpha: 0.40)
                          : Colors.transparent,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: s.color,
                          borderRadius: BorderRadius.circular(3.5),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          s.label,
                          softWrap: true,
                          style: TextStyle(
                            fontSize: 12.4,
                            height: 1.2,
                            color: c.textPrimary,
                            fontWeight: isSelected
                                ? FontWeight.w800
                                : FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        VndAmount.formatCompact(s.amountMinor),
                        style: TextStyle(
                          fontSize: 11.8,
                          fontWeight: FontWeight.w700,
                          color: c.textSecondary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1.5,
                        ),
                        decoration: BoxDecoration(
                          color: s.color.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${s.pct.toStringAsFixed(1)}%',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: s.color,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        );

        if (isWide) {
          return Semantics(
            container: true,
            label:
                'Biểu đồ cơ cấu ${widget.centerTitle}, tổng ${VndAmount.format(widget.totalExpenseMinor)}, ${widget.slices.length} danh mục',
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                donutRing,
                const SizedBox(width: AppSpacing.lg),
                Expanded(child: legendList),
              ],
            ),
          );
        }

        return Semantics(
          container: true,
          label:
              'Biểu đồ cơ cấu ${widget.centerTitle}, tổng ${VndAmount.format(widget.totalExpenseMinor)}, ${widget.slices.length} danh mục',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(child: donutRing),
              if (topSlices.isNotEmpty) ...[
                const SizedBox(height: 12),
                legendList,
              ],
            ],
          ),
        );
      },
    );
  }
}

class _DonutRingPainter extends CustomPainter {
  final List<ProDonutSlice> slices;
  final int? selectedIndex;
  final double sweepProgress;
  final Color emptyTrackColor;
  final Color innerRingColor;

  const _DonutRingPainter({
    required this.slices,
    this.selectedIndex,
    this.sweepProgress = 1.0,
    required this.emptyTrackColor,
    required this.innerRingColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const baseStroke = 19.0;
    const activeStroke = 24.0;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) - activeStroke - 4) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Subtle inner depth guide ring
    canvas.drawCircle(
      center,
      radius - baseStroke / 2 - 4,
      Paint()
        ..color = innerRingColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9,
    );

    final trackPaint = Paint()
      ..color = emptyTrackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = baseStroke;
    canvas.drawArc(rect, 0, math.pi * 2, false, trackPaint);

    final positiveSlices = slices.where((s) => s.pct > 0).toList();
    if (positiveSlices.isEmpty || sweepProgress <= 0.0) return;

    final totalPct = positiveSlices.fold<double>(0.0, (sum, s) => sum + s.pct);
    if (totalPct <= 0) return;

    var startAngle = -math.pi / 2;
    var traversed = 0.0;
    final maxTotalSweep = (math.pi * 2) * sweepProgress.clamp(0.0, 1.0);
    final gapRadians = positiveSlices.length > 1 ? 0.032 : 0.0;

    for (var i = 0; i < slices.length; i++) {
      if (traversed >= maxTotalSweep) break;
      final slice = slices[i];
      if (slice.pct <= 0) continue;
      final sweep = (slice.pct / totalPct) * (math.pi * 2);
      if (sweep <= 0.004) continue;

      final visibleSweep = math.min(sweep, maxTotalSweep - traversed);
      if (visibleSweep <= 0.004) {
        traversed += sweep;
        startAngle += sweep;
        continue;
      }

      final isSelected = selectedIndex == i;
      final hasSelection = selectedIndex != null;
      final effectiveSweep = math.max(0.004, visibleSweep - gapRadians);
      final arcStart = startAngle + (gapRadians / 2);

      if (isSelected) {
        canvas.drawArc(
          rect,
          arcStart,
          effectiveSweep,
          false,
          Paint()
            ..color = slice.color.withValues(alpha: 0.26)
            ..style = PaintingStyle.stroke
            ..strokeWidth = activeStroke + 5
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
        );
      }

      final paint = Paint()
        ..color = (hasSelection && !isSelected)
            ? slice.color.withValues(alpha: 0.58)
            : slice.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = isSelected ? activeStroke : baseStroke
        ..strokeCap = StrokeCap.butt
        ..isAntiAlias = true;

      canvas.drawArc(rect, arcStart, effectiveSweep, false, paint);
      traversed += sweep;
      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutRingPainter oldDelegate) {
    return oldDelegate.slices != slices ||
        oldDelegate.selectedIndex != selectedIndex ||
        oldDelegate.sweepProgress != sweepProgress ||
        oldDelegate.emptyTrackColor != emptyTrackColor ||
        oldDelegate.innerRingColor != innerRingColor;
  }
}

/// Luminous Private-Banking Wealth Sparkline Curve rendered inside `ProHeroGradientCard`.
/// Draws an honest flat baseline when 7-day net worth delta is 0 (zero fake upward slopes).
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
    while (pts.length < 7) {
      pts.insert(0, pts.isEmpty ? netWorthMinor.toDouble() : pts.first);
    }

    final minV = pts.reduce(math.min);
    final maxV = pts.reduce(math.max);
    final isFlat = (maxV - minV).abs() < 1.0;

    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        size: Size(width, height),
        painter: _SparklineCurvePainter(points: pts, isFlat: isFlat),
      ),
    );
  }
}

class _SparklineCurvePainter extends CustomPainter {
  final List<double> points;
  final bool isFlat;

  const _SparklineCurvePainter({required this.points, required this.isFlat});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final minVal = points.reduce(math.min);
    final maxVal = points.reduce(math.max);
    final span = math.max(1.0, maxVal - minVal);

    // Subtle baseline reference dash
    final refY = size.height * 0.56;
    final dashPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..strokeWidth = 0.8;
    for (var x = 4.0; x < size.width - 6; x += 6.0) {
      canvas.drawLine(Offset(x, refY), Offset(x + 3.0, refY), dashPaint);
    }

    final coords = <Offset>[];
    for (var i = 0; i < points.length; i++) {
      final x = (i / (points.length - 1)) * (size.width - 10) + 5;
      final y = isFlat
          ? refY
          : ((size.height - 8) -
                ((points[i] - minVal) / span) * (size.height - 15) +
                4);
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
          const Color(0xFF63E6BE).withValues(alpha: isFlat ? 0.16 : 0.34),
          const Color(0xFF63E6BE).withValues(alpha: 0.0),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawPath(fillPath, fillPaint);

    final linePaint = Paint()
      ..color = const Color(0xFF8CE99A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.3
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    canvas.drawPath(path, linePaint);

    final end = coords.last;
    canvas.drawCircle(
      end,
      6.2,
      Paint()..color = const Color(0xFF8CE99A).withValues(alpha: 0.28),
    );
    canvas.drawCircle(end, 3.2, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _SparklineCurvePainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.isFlat != isFlat;
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
class ProCashflowPulseCard extends StatefulWidget {
  final List<int> dailyIncomesMinor;
  final List<int> dailyExpensesMinor;
  final int liquidAssetsMinor;
  final int savingsAssetsMinor;
  final int dailySafeToSpendMinor;
  final int financialHealthScore;
  final bool obscureAmounts;
  final DateTime? referenceDate;
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
    this.referenceDate,
    this.onTapAnalytics,
  });

  @override
  State<ProCashflowPulseCard> createState() => _ProCashflowPulseCardState();
}

class _ProCashflowPulseCardState extends State<ProCashflowPulseCard> {
  int? _selectedDayIndex;

  void _selectBucketFromDx(double dx, double width, {required bool toggle}) {
    if (width <= 0) return;
    final idx = ((dx / width) * 7).floor().clamp(0, 6);
    if (toggle && _selectedDayIndex == idx) {
      LifeOsMotionScope.read(context).selectionHaptic();
      setState(() => _selectedDayIndex = null);
      return;
    }
    if (_selectedDayIndex != idx) {
      LifeOsMotionScope.read(context).selectionHaptic();
      setState(() => _selectedDayIndex = idx);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final motion = LifeOsMotionScope.of(context);
    final tickersEnabled = TickerMode.valuesOf(context).enabled;
    final barsDataKey = ValueKey<int>(
      Object.hash(
        Object.hashAll(widget.dailyIncomesMinor),
        Object.hashAll(widget.dailyExpensesMinor),
      ),
    );
    final score = widget.financialHealthScore;
    final scoreLabel = score >= 80
        ? 'Xuất sắc'
        : (score >= 65 ? 'Tốt' : 'Cần tối ưu');
    final scoreColor = score >= 80
        ? c.success
        : (score >= 65 ? c.primary : c.warning);
    const expenseBarColor = Color(0xFFF59F00);

    final now = widget.referenceDate ?? DateTime.now();
    final dayDates = List<DateTime>.generate(
      7,
      (idx) => now.subtract(Duration(days: 6 - idx)),
    );
    final weekdayLabels = dayDates
        .map((d) {
          return switch (d.weekday) {
            DateTime.sunday => 'CN',
            final w => 'T${w + 1}',
          };
        })
        .toList(growable: false);

    var maxVal = 0;
    for (final v in widget.dailyIncomesMinor) {
      if (v > maxVal) maxVal = v;
    }
    for (final v in widget.dailyExpensesMinor) {
      if (v > maxVal) maxVal = v;
    }

    final sel = _selectedDayIndex;
    final selInc = (sel != null && sel < widget.dailyIncomesMinor.length)
        ? widget.dailyIncomesMinor[sel]
        : 0;
    final selExp = (sel != null && sel < widget.dailyExpensesMinor.length)
        ? widget.dailyExpensesMinor[sel]
        : 0;

    String fmtCompact(int minor, {String prefix = ''}) {
      if (widget.obscureAmounts) return '•••• ₫';
      if (minor <= 0) return '0 ₫';
      return '$prefix${VndAmount.formatCompact(minor)}';
    }

    return Semantics(
      container: true,
      label:
          'Biểu đồ dòng tiền 7 ngày, điểm sức khỏe tài chính $score điểm ($scoreLabel)',
      child: LiquidGlassSurface(
        material: LiquidGlassMaterial.card,
        borderRadius: 20,
        padding: const EdgeInsets.all(AppSpacing.md),
        onTap: widget.onTapAnalytics,
        enableBlur: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
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
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Dòng tiền 7 ngày',
                            softWrap: true,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          Text(
                            'Chạm cột để xem từng ngày',
                            softWrap: true,
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
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
                        '$score điểm · $scoreLabel',
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
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 6,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ChartLegendDot(color: c.success, label: 'Thu'),
                    const SizedBox(width: 10),
                    const _ChartLegendDot(color: expenseBarColor, label: 'Chi'),
                  ],
                ),
                if (sel != null)
                  InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => setState(() => _selectedDayIndex = null),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: c.primary.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${weekdayLabels[sel]} (${dayDates[sel].day.toString().padLeft(2, '0')}/${dayDates[sel].month.toString().padLeft(2, '0')}): '
                        'Thu ${fmtCompact(selInc, prefix: '+')} · Chi ${fmtCompact(selExp, prefix: '-')}',
                        softWrap: true,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: c.textPrimary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  )
                else
                  Text(
                    maxVal > 0
                        ? 'Đỉnh: ${fmtCompact(maxVal)}'
                        : 'Chưa phát sinh',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: c.textSecondary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, constraints) {
                return GestureDetector(
                  key: const Key('pro_cashflow_chart_area'),
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) => _selectBucketFromDx(
                    d.localPosition.dx,
                    constraints.maxWidth,
                    toggle: true,
                  ),
                  onHorizontalDragUpdate: (d) => _selectBucketFromDx(
                    d.localPosition.dx,
                    constraints.maxWidth,
                    toggle: false,
                  ),
                  child: SizedBox(
                    height: 98,
                    width: double.infinity,
                    child: TweenAnimationBuilder<double>(
                      key: barsDataKey,
                      tween: Tween<double>(
                        begin: (motion.isReducedMotion || !tickersEnabled)
                            ? 1.0
                            : 0.0,
                        end: 1.0,
                      ),
                      duration: motion.resolveDuration(
                        LifeOsMotionTokens.medium,
                      ),
                      curve: LifeOsMotionTokens.emphasizedCurve,
                      builder: (context, barProgress, _) {
                        return CustomPaint(
                          painter: _CashflowBarsPainter(
                            incomes: widget.dailyIncomesMinor,
                            expenses: widget.dailyExpensesMinor,
                            selectedDayIndex: _selectedDayIndex,
                            barProgress: barProgress.clamp(0.0, 1.0),
                            incomeColor: c.success,
                            expenseColor: expenseBarColor,
                            highlightColor: c.primary.withValues(alpha: 0.08),
                            gridColor: c.separator.withValues(alpha: 0.55),
                          ),
                        );
                      },
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 6),
            Row(
              children: List.generate(7, (idx) {
                final isToday = idx == 6;
                final isSelected = _selectedDayIndex == idx;
                return Expanded(
                  child: InkWell(
                    key: Key('pro_cashflow_day_$idx'),
                    borderRadius: BorderRadius.circular(6),
                    onTap: () {
                      LifeOsMotionScope.read(context).selectionHaptic();
                      setState(() {
                        _selectedDayIndex = isSelected ? null : idx;
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        weekdayLabels[idx],
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: (isSelected || isToday)
                              ? FontWeight.w800
                              : FontWeight.w500,
                          color: isSelected
                              ? c.primary
                              : (isToday ? c.textPrimary : c.textSecondary),
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
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
                  value: widget.obscureAmounts
                      ? '•••••• ₫'
                      : VndAmount.format(widget.liquidAssetsMinor),
                  valueColor: c.textPrimary,
                ),
                Container(
                  width: 1,
                  height: 28,
                  color: c.separator.withValues(alpha: 0.6),
                ),
                _CapitalColumn(
                  label: 'Tích lũy',
                  value: widget.obscureAmounts
                      ? '•••••• ₫'
                      : VndAmount.format(widget.savingsAssetsMinor),
                  valueColor: c.success,
                ),
                Container(
                  width: 1,
                  height: 28,
                  color: c.separator.withValues(alpha: 0.6),
                ),
                _CapitalColumn(
                  label: 'Hạn mức / ngày',
                  value: widget.obscureAmounts
                      ? '•••••• ₫'
                      : VndAmount.format(widget.dailySafeToSpendMinor),
                  valueColor: c.secondary,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ChartLegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _ChartLegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: c.textSecondary,
          ),
        ),
      ],
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
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(label, style: Theme.of(context).textTheme.labelSmall),
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
  final int? selectedDayIndex;
  final double barProgress;
  final Color incomeColor;
  final Color expenseColor;
  final Color highlightColor;
  final Color gridColor;

  const _CashflowBarsPainter({
    required this.incomes,
    required this.expenses,
    required this.selectedDayIndex,
    this.barProgress = 1.0,
    required this.incomeColor,
    required this.expenseColor,
    required this.highlightColor,
    required this.gridColor,
  });

  void _drawDashedLine(Canvas canvas, double y, double width, Paint paint) {
    const dashW = 4.0;
    const gapW = 4.0;
    var x = 0.0;
    while (x < width) {
      canvas.drawLine(
        Offset(x, y),
        Offset(math.min(width, x + dashW), y),
        paint,
      );
      x += dashW + gapW;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.85;

    _drawDashedLine(canvas, 2.0, size.width, gridPaint);
    _drawDashedLine(canvas, size.height * 0.5, size.width, gridPaint);
    canvas.drawLine(
      Offset(0, size.height - 1),
      Offset(size.width, size.height - 1),
      gridPaint,
    );

    var maxVal = 0;
    for (final v in incomes) {
      if (v > maxVal) maxVal = v;
    }
    for (final v in expenses) {
      if (v > maxVal) maxVal = v;
    }

    final usableH = math.max(12.0, size.height - 6.0);

    // Balanced power-curve scaling (gamma = 0.68): preserves visual honesty
    // while keeping normal daily expenses legible next to larger salary days,
    // and strictly renders 0 VND as a flat 2px baseline tick.
    double barHeightFor(int val) {
      if (val <= 0 || maxVal <= 0) return 2.0;
      final ratio = (val / maxVal).clamp(0.0, 1.0);
      final targetH = math.max(7.0, math.pow(ratio, 0.68).toDouble() * usableH);
      return 2.0 + (targetH - 2.0) * barProgress.clamp(0.0, 1.0);
    }

    final slotW = size.width / 7;
    final barW = math.min(10.5, math.max(6.0, slotW * 0.24));

    if (selectedDayIndex != null &&
        selectedDayIndex! >= 0 &&
        selectedDayIndex! < 7) {
      final left = slotW * selectedDayIndex! + 3.0;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, 0, math.max(8.0, slotW - 6.0), size.height),
          const Radius.circular(8),
        ),
        Paint()..color = highlightColor,
      );
    }

    for (var i = 0; i < 7; i++) {
      final inc = i < incomes.length ? incomes[i] : 0;
      final exp = i < expenses.length ? expenses[i] : 0;
      final cx = slotW * i + slotW / 2;
      final dimmed = selectedDayIndex != null && selectedDayIndex != i;

      final incH = barHeightFor(inc);
      final expH = barHeightFor(exp);

      final incRect = Rect.fromLTWH(
        cx - barW - 1.5,
        size.height - 1 - incH,
        barW,
        incH,
      );
      final expRect = Rect.fromLTWH(
        cx + 1.5,
        size.height - 1 - expH,
        barW,
        expH,
      );

      final incPaint = Paint();
      if (inc > 0 && maxVal > 0) {
        final topC = dimmed ? incomeColor.withValues(alpha: 0.42) : incomeColor;
        final botC = dimmed
            ? incomeColor.withValues(alpha: 0.24)
            : incomeColor.withValues(alpha: 0.72);
        incPaint.shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [topC, botC],
        ).createShader(incRect);
      } else {
        incPaint.color = gridColor;
      }

      final expPaint = Paint();
      if (exp > 0 && maxVal > 0) {
        final topC = dimmed
            ? expenseColor.withValues(alpha: 0.42)
            : expenseColor;
        final botC = dimmed
            ? expenseColor.withValues(alpha: 0.24)
            : expenseColor.withValues(alpha: 0.72);
        expPaint.shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [topC, botC],
        ).createShader(expRect);
      } else {
        expPaint.color = gridColor;
      }

      canvas.drawRRect(
        RRect.fromRectAndCorners(
          incRect,
          topLeft: const Radius.circular(4.5),
          topRight: const Radius.circular(4.5),
          bottomLeft: const Radius.circular(1.5),
          bottomRight: const Radius.circular(1.5),
        ),
        incPaint,
      );
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          expRect,
          topLeft: const Radius.circular(4.5),
          topRight: const Radius.circular(4.5),
          bottomLeft: const Radius.circular(1.5),
          bottomRight: const Radius.circular(1.5),
        ),
        expPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CashflowBarsPainter oldDelegate) {
    return oldDelegate.incomes != incomes ||
        oldDelegate.expenses != expenses ||
        oldDelegate.selectedDayIndex != selectedDayIndex ||
        oldDelegate.barProgress != barProgress ||
        oldDelegate.incomeColor != incomeColor ||
        oldDelegate.expenseColor != expenseColor ||
        oldDelegate.highlightColor != highlightColor ||
        oldDelegate.gridColor != gridColor;
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
  final bool isProvisional;
  final bool needsReview;
  final bool isDisputed;
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
    this.isProvisional = false,
    this.needsReview = false,
    this.isDisputed = false,
    this.hasPendingWrites = false,
    this.splitSummary,
    this.obscureAmounts = false,
    this.onTap,
  });

  FinancialTrustStatus _resolveTrustStatus() {
    if (isReversed) return FinancialTrustStatus.reversed;
    if (isDisputed) return FinancialTrustStatus.disputed;
    if (hasPendingWrites) return FinancialTrustStatus.syncing;
    if (needsReview) return FinancialTrustStatus.needsReview;
    if (isProvisional) return FinancialTrustStatus.pendingConfirmation;
    if (isVerified) return FinancialTrustStatus.reconciled;
    return FinancialTrustStatus.saved;
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final trustStatus = _resolveTrustStatus();
    final (_, trustFg, _, _) = trustStatus.resolveVisual(c);

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

    final viewportWidth = MediaQuery.sizeOf(context).width;
    final maxRightWidth = (math.min(viewportWidth, 640.0) * 0.34).clamp(
      92.0,
      156.0,
    );

    return Semantics(
      container: true,
      label:
          '$merchant, ${metaParts.join(", ")}, $formattedAmount, trạng thái ${trustStatus.labelVi}',
      child: LiquidGlassSurface(
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
                  size: 44,
                ),
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    width: 17,
                    height: 17,
                    decoration: BoxDecoration(
                      color: c.surface,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: trustFg.withValues(alpha: 0.35),
                        width: 0.8,
                      ),
                    ),
                    padding: const EdgeInsets.all(1.5),
                    child: Icon(trustStatus.icon, size: 12.5, color: trustFg),
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
                      decoration: isReversed
                          ? TextDecoration.lineThrough
                          : null,
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
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxRightWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      formattedAmount,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: amountColor,
                        decoration: isReversed
                            ? TextDecoration.lineThrough
                            : null,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  if (balanceAfterMinor != null &&
                      !obscureAmounts &&
                      !isReversed) ...[
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        'SD: ${VndAmount.format(balanceAfterMinor!)}',
                        style: TextStyle(
                          fontSize: 10.8,
                          fontWeight: FontWeight.w600,
                          color: c.textSecondary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 3),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(trustStatus.icon, size: 11.5, color: trustFg),
                        const SizedBox(width: 3),
                        Text(
                          trustStatus.labelVi,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: trustFg,
                          ),
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
    );
  }
}
