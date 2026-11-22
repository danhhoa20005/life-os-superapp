import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../utils/vnd_amount.dart';
import 'status_widgets.dart';

/// Sunken pill container framing a `TabBar` as an Apple/Linear Segmented Control.
class ProPillTabContainer extends StatelessWidget {
  final TabBar tabBar;

  const ProPillTabContainer({super.key, required this.tabBar});

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 8, AppSpacing.md, 6),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSpacing.maxContentWidth),
          child: Container(
            height: 46,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: c.surfaceRaised,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: c.separator.withValues(alpha: 0.7), width: 0.8),
            ),
            child: tabBar,
          ),
        ),
      ),
    );
  }
}

/// Deep Emerald Mesh Hero Card with luminous ambient orbs (Apple Wallet / Revolut Pro Max style).
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
    final colors = gradientColors ??
        (isDark
            ? const [Color(0xFF073B1A), Color(0xFF0A5C28), Color(0xFF062914)]
            : const [Color(0xFF064E1E), Color(0xFF0B7A2A), Color(0xFF0E9447)]);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
        boxShadow: [
          BoxShadow(
            color: colors[1].withValues(alpha: isDark ? 0.32 : 0.24),
            blurRadius: 24,
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
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Colors.white.withValues(alpha: 0.16),
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
              width: 130,
              height: 130,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF63E6BE).withValues(alpha: 0.18),
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
    );
  }
}

/// Translucent glass stat pill placed inside `ProHeroGradientCard`.
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
        color: Colors.white.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18), width: 0.8),
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
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.78),
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Quick action button styled for Hero cards.
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
    return Material(
      color: Colors.white.withValues(alpha: 0.16),
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
    );
  }
}

/// Tactile Bento Grid Tile for 2x2 mobile & desktop dashboards.
class ProBentoTile extends StatelessWidget {
  final IconData icon;
  final Color accentColor;
  final String title;
  final String metric;
  final String badgeText;
  final SemanticStatusKind statusKind;
  final VoidCallback onTap;

  const ProBentoTile({
    super.key,
    required this.icon,
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

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: c.separator.withValues(alpha: isDark ? 0.85 : 0.55),
          width: 0.8,
        ),
        boxShadow: isDark
            ? const []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.035),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: isDark ? 0.22 : 0.12),
                        borderRadius: BorderRadius.circular(12),
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
                Text(
                  metric,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                SemanticStatusBadge(kind: statusKind, label: badgeText),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Physical-Digital Apple Wallet / Revolut Bank, Cash & Credit Card component.
class ProWalletCreditCard extends StatelessWidget {
  final String name;
  final String walletTypeKey; // 'cash' | 'bank' | 'creditCard'
  final int balanceMinor;
  final String? maskedAccount;
  final bool isEstimatedBalance;
  final bool hasPendingWrites;

  const ProWalletCreditCard({
    super.key,
    required this.name,
    required this.walletTypeKey,
    required this.balanceMinor,
    this.maskedAccount,
    required this.isEstimatedBalance,
    required this.hasPendingWrites,
  });

  @override
  Widget build(BuildContext context) {
    final (colors, typeLabel, typeIcon) = switch (walletTypeKey) {
      'bank' => (
          const [Color(0xFF0F294A), Color(0xFF1A4B84), Color(0xFF103562)],
          'Tài khoản Ngân hàng',
          Icons.account_balance_rounded,
        ),
      'creditCard' => (
          const [Color(0xFF1F2026), Color(0xFF343741), Color(0xFF18191E)],
          'Thẻ Tín dụng',
          Icons.credit_card_rounded,
        ),
      _ => (
          const [Color(0xFF085822), Color(0xFF0D8233), Color(0xFF09471D)],
          'Tiền mặt Sẵn có',
          Icons.payments_rounded,
        ),
    };

    return Container(
      width: 268,
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
            color: colors[0].withValues(alpha: 0.24),
            blurRadius: 18,
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
                    Icon(typeIcon, size: 17, color: Colors.white.withValues(alpha: 0.9)),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              // Metallic EMV card chip motif
              Container(
                width: 28,
                height: 20,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(5),
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFDE68A), Color(0xFFD97706)],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            VndAmount.format(balanceMinor),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            maskedAccount != null && maskedAccount!.isNotEmpty
                ? '$typeLabel · $maskedAccount'
                : '$typeLabel · ${isEstimatedBalance ? "Số dư ước tính" : "Đã đối soát"}',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.76),
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                hasPendingWrites ? Icons.cloud_upload_outlined : Icons.cloud_done_rounded,
                size: 14,
                color: hasPendingWrites ? const Color(0xFFFCD34D) : const Color(0xFF86EFAC),
              ),
              const SizedBox(width: 5),
              Text(
                hasPendingWrites ? 'Chờ đồng bộ Offline' : 'Đã lưu Cloud',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.88),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Curated Vietnamese category visual mapping (Squircle Icon + Harmonic Color).
abstract final class ProCategoryStyle {
  static ({IconData icon, Color color}) resolve(String categoryName, {bool isTransfer = false}) {
    if (isTransfer) {
      return (icon: Icons.swap_horiz_rounded, color: const Color(0xFF0066CC));
    }
    final lower = categoryName.toLowerCase();
    if (lower.contains('ăn') || lower.contains('cafe')) {
      return (icon: Icons.restaurant_rounded, color: const Color(0xFFE8590C));
    }
    if (lower.contains('việc nhà') || lower.contains('gia dụng')) {
      return (icon: Icons.cleaning_services_rounded, color: const Color(0xFF0CA678));
    }
    if (lower.contains('nhà cửa') || lower.contains('thuê')) {
      return (icon: Icons.home_work_rounded, color: const Color(0xFF5F3DC4));
    }
    if (lower.contains('điện') || lower.contains('nước') || lower.contains('internet')) {
      return (icon: Icons.bolt_rounded, color: const Color(0xFFD97706));
    }
    if (lower.contains('chợ') || lower.contains('mua sắm')) {
      return (icon: Icons.shopping_bag_rounded, color: const Color(0xFFD6336C));
    }
    if (lower.contains('bảo dưỡng') || lower.contains('sửa xe')) {
      return (icon: Icons.handyman_rounded, color: const Color(0xFF495057));
    }
    if (lower.contains('xe') || lower.contains('di chuyển')) {
      return (icon: Icons.two_wheeler_rounded, color: const Color(0xFF1971C2));
    }
    if (lower.contains('sức khỏe') || lower.contains('giáo dục')) {
      return (icon: Icons.favorite_rounded, color: const Color(0xFFC92A2A));
    }
    if (lower.contains('giải trí') || lower.contains('đăng ký')) {
      return (icon: Icons.movie_filter_rounded, color: const Color(0xFF7048E8));
    }
    if (lower.contains('lương') || lower.contains('thu nhập')) {
      return (icon: Icons.payments_rounded, color: const Color(0xFF0B7A2A));
    }
    if (lower.contains('tiết kiệm') || lower.contains('quỹ')) {
      return (icon: Icons.savings_rounded, color: const Color(0xFF087F5B));
    }
    return (icon: Icons.category_rounded, color: const Color(0xFF0B7A2A));
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
                    Text(
                      VndAmount.format(totalExpenseMinor),
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
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
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: c.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                        overflow: TextOverflow.ellipsis,
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
      canvas.drawArc(rect, startAngle + (gapRadians / 2), effectiveSweep, false, paint);
      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutRingPainter oldDelegate) {
    return oldDelegate.slices != slices || oldDelegate.emptyTrackColor != emptyTrackColor;
  }
}
