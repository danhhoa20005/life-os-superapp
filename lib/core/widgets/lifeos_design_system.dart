import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/lifeos_brand_colors.dart';
import '../../app/theme/theme_bloc.dart';
import '../../features/calendar/presentation/bloc/calendar_bloc.dart';
import '../../features/daily_life/presentation/bloc/daily_life_bloc.dart';
import '../../features/tasks/domain/entities/task_entities.dart';
import '../../features/tasks/presentation/bloc/task_bloc.dart';
import '../../features/transactions/domain/entities/transaction_entities.dart';
import '../../features/transactions/presentation/bloc/transaction_bloc.dart';
import '../constants/app_assets.dart';
import '../utils/vietnamese_search_matcher.dart';
import '../utils/vnd_amount.dart';
import 'lifeos_logo_side_drawer.dart';
import 'liquid_glass.dart';
import 'quick_create_hub_sheet.dart';

export 'lifeos_logo_side_drawer.dart';
export 'lifeos_top_toast.dart';
export 'liquid_glass.dart';

ThemeBloc? _maybeThemeBloc(BuildContext context, {bool listen = false}) {
  try {
    return BlocProvider.of<ThemeBloc>(context, listen: listen);
  } catch (_) {
    return null;
  }
}

/// Semantic pastel tone palette shared across all LifeOS screens.
enum LifeOsAccentTone { emerald, blue, purple, amber, coral, neutral }

extension LifeOsAccentToneColors on LifeOsAccentTone {
  (Color bg, Color fg) resolve(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return switch (this) {
      LifeOsAccentTone.emerald =>
        isDark
            ? (const Color(0xFF13331E), const Color(0xFF34D399))
            : (const Color(0xFFEAFBF0), const Color(0xFF12B847)),
      LifeOsAccentTone.blue =>
        isDark
            ? (const Color(0xFF13294B), const Color(0xFF60A5FA))
            : (const Color(0xFFEFF6FF), const Color(0xFF2563EB)),
      LifeOsAccentTone.purple =>
        isDark
            ? (const Color(0xFF271B47), const Color(0xFFA78BFA))
            : (const Color(0xFFF5F3FF), const Color(0xFF7C3AED)),
      LifeOsAccentTone.amber =>
        isDark
            ? (const Color(0xFF38290A), const Color(0xFFFBBF24))
            : (const Color(0xFFFEF7E0), const Color(0xFFD97706)),
      LifeOsAccentTone.coral =>
        isDark
            ? (const Color(0xFF3A1616), const Color(0xFFF87171))
            : (const Color(0xFFFEE2E2), const Color(0xFFDC2626)),
      LifeOsAccentTone.neutral =>
        isDark
            ? (const Color(0xFF222B26), const Color(0xFFA0AEB6))
            : (const Color(0xFFF1F5F3), const Color(0xFF475467)),
    };
  }
}

/// Official BrandKit 1.0 Symbol color variants (`01_Vector_SVG/LifeOS_Logo_Symbol_*.svg`).
enum LifeOsSymbolVariant { color, white, forest, black }

/// Official BrandKit 1.0 Wordmark color modes (`01_Vector_SVG/LifeOS_Logo_Horizontal_*.svg`).
enum LifeOsWordmarkStyle { auto, primary, white, black }

Path _lifeOsHousePath(double s) {
  return Path()
    ..moveTo(34 * s, 112 * s)
    ..cubicTo(34 * s, 103 * s, 38 * s, 98 * s, 46 * s, 92 * s)
    ..lineTo(111 * s, 41 * s)
    ..cubicTo(122 * s, 32 * s, 134 * s, 32 * s, 145 * s, 41 * s)
    ..lineTo(210 * s, 92 * s)
    ..cubicTo(218 * s, 98 * s, 222 * s, 103 * s, 222 * s, 112 * s)
    ..lineTo(222 * s, 158 * s)
    ..cubicTo(180 * s, 161 * s, 150 * s, 176 * s, 128 * s, 204 * s)
    ..cubicTo(106 * s, 176 * s, 76 * s, 161 * s, 34 * s, 158 * s)
    ..close();
}

Path _lifeOsLeftLeafPath(double s) {
  return Path()
    ..moveTo(27 * s, 168 * s)
    ..cubicTo(71 * s, 165 * s, 105 * s, 183 * s, 123 * s, 231 * s)
    ..cubicTo(78 * s, 230 * s, 43 * s, 208 * s, 27 * s, 168 * s)
    ..close();
}

Path _lifeOsRightLeafPath(double s) {
  return Path()
    ..moveTo(229 * s, 168 * s)
    ..cubicTo(185 * s, 165 * s, 151 * s, 183 * s, 133 * s, 231 * s)
    ..cubicTo(178 * s, 230 * s, 213 * s, 208 * s, 229 * s, 168 * s)
    ..close();
}

void _paintLifeOsFamilySilhouettes(
  Canvas canvas,
  double s, {
  required Color color,
  BlendMode blendMode = BlendMode.srcOver,
}) {
  final headPaint = Paint()
    ..color = color
    ..blendMode = blendMode
    ..style = PaintingStyle.fill
    ..isAntiAlias = true;

  canvas.drawCircle(Offset(91 * s, 107 * s), 14.5 * s, headPaint);
  canvas.drawCircle(Offset(165 * s, 107 * s), 14.5 * s, headPaint);
  canvas.drawCircle(Offset(128 * s, 135 * s), 10.8 * s, headPaint);

  final parentStroke = Paint()
    ..color = color
    ..blendMode = blendMode
    ..style = PaintingStyle.stroke
    ..strokeWidth = 14 * s
    ..strokeCap = StrokeCap.round
    ..isAntiAlias = true;

  final leftShoulder = Path()
    ..moveTo(57 * s, 158 * s)
    ..cubicTo(61 * s, 141 * s, 74 * s, 132 * s, 91 * s, 132 * s)
    ..cubicTo(101 * s, 132 * s, 108 * s, 137 * s, 112 * s, 144 * s);
  canvas.drawPath(leftShoulder, parentStroke);

  final rightShoulder = Path()
    ..moveTo(144 * s, 144 * s)
    ..cubicTo(148 * s, 137 * s, 155 * s, 132 * s, 165 * s, 132 * s)
    ..cubicTo(182 * s, 132 * s, 195 * s, 141 * s, 199 * s, 158 * s);
  canvas.drawPath(rightShoulder, parentStroke);

  final childStroke = Paint()
    ..color = color
    ..blendMode = blendMode
    ..style = PaintingStyle.stroke
    ..strokeWidth = 10 * s
    ..strokeCap = StrokeCap.round
    ..isAntiAlias = true;

  final childShoulder = Path()
    ..moveTo(111 * s, 170 * s)
    ..cubicTo(114 * s, 157 * s, 120 * s, 151 * s, 128 * s, 151 * s)
    ..cubicTo(137 * s, 151 * s, 143 * s, 157 * s, 146 * s, 170 * s);
  canvas.drawPath(childShoulder, childStroke);
}

/// Official frameless LifeOS Symbol (`LifeOS_Logo_Symbol_Color/White/Dark/Black.svg`):
/// Gradient/solid House roof with true negative-space knockout of 3 family members + 2 cradling leaves.
class LifeOsSymbolMark extends StatelessWidget {
  final double size;
  final LifeOsSymbolVariant variant;

  const LifeOsSymbolMark({
    super.key,
    this.size = 34,
    this.variant = LifeOsSymbolVariant.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _LifeOsSymbolPainter(variant: variant)),
    );
  }
}

class _LifeOsSymbolPainter extends CustomPainter {
  final LifeOsSymbolVariant variant;

  const _LifeOsSymbolPainter({required this.variant});

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width, size.height) / 256.0;
    final rect = Offset.zero & size;

    final Color? monoColor = switch (variant) {
      LifeOsSymbolVariant.color => null,
      LifeOsSymbolVariant.white => Colors.white,
      LifeOsSymbolVariant.forest => LifeOSBrandColors.forest,
      LifeOsSymbolVariant.black => const Color(0xFF111111),
    };

    // 1. House with true transparent people-knockout mask (`BlendMode.dstOut`)
    canvas.saveLayer(rect, Paint());
    final housePaint = Paint()
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    if (monoColor != null) {
      housePaint.color = monoColor;
    } else {
      housePaint.shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: LifeOSBrandColors.houseGradient,
        stops: LifeOSBrandColors.houseStops,
      ).createShader(Rect.fromLTWH(34 * s, 32 * s, 188 * s, 172 * s));
    }
    canvas.drawPath(_lifeOsHousePath(s), housePaint);
    _paintLifeOsFamilySilhouettes(
      canvas,
      s,
      color: Colors.black,
      blendMode: BlendMode.dstOut,
    );
    canvas.restore();

    // 2. Left & Right cradling leaves
    final leftLeafPaint = Paint()
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    final rightLeafPaint = Paint()
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    if (monoColor != null) {
      leftLeafPaint.color = monoColor;
      rightLeafPaint.color = monoColor;
    } else {
      leftLeafPaint.shader = const LinearGradient(
        begin: Alignment.bottomLeft,
        end: Alignment.topRight,
        colors: LifeOSBrandColors.leftLeafGradient,
      ).createShader(Rect.fromLTWH(27 * s, 165 * s, 96 * s, 66 * s));

      rightLeafPaint.shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: LifeOSBrandColors.rightLeafGradient,
      ).createShader(Rect.fromLTWH(133 * s, 165 * s, 96 * s, 66 * s));
    }

    canvas.drawPath(_lifeOsLeftLeafPath(s), leftLeafPaint);
    canvas.drawPath(_lifeOsRightLeafPath(s), rightLeafPaint);
  }

  @override
  bool shouldRepaint(covariant _LifeOsSymbolPainter oldDelegate) =>
      oldDelegate.variant != variant;
}

/// Official LifeOS App Icon Squircle Badge (`LifeOS_AppIcon_Master_FullBleed.svg`):
/// Emerald-Lime to Deep Green gradient squircle with white stroked house, 3 family members, and 2 leaves.
class LifeOsLeafMark extends StatelessWidget {
  final double size;
  final double borderRadius;

  const LifeOsLeafMark({super.key, this.size = 36, this.borderRadius = 11});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: LifeOSBrandColors.appIconBgGradient,
          stops: LifeOSBrandColors.appIconBgStops,
        ),
        boxShadow: [
          BoxShadow(
            color: LifeOSBrandColors.primary.withValues(alpha: 0.24),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: const CustomPaint(painter: _LifeOsAppIconForegroundPainter()),
      ),
    );
  }
}

class _LifeOsAppIconForegroundPainter extends CustomPainter {
  const _LifeOsAppIconForegroundPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Subtle top sheen from `LifeOS_AppIcon_Gloss_Optional.svg`
    final glossPath = Path()
      ..moveTo(0, 0)
      ..lineTo(w, 0)
      ..lineTo(w, h * 0.185)
      ..quadraticBezierTo(w * 0.48, h * 0.36, 0, h * 0.195)
      ..close();
    canvas.drawPath(
      glossPath,
      Paint()..color = Colors.white.withValues(alpha: 0.075),
    );

    // Exact BrandKit Master AppIcon transform: translate(160, 146) scale(2.75) on 1024x1024
    canvas.save();
    canvas.translate(w * (160.0 / 1024.0), h * (146.0 / 1024.0));
    final s = math.min(w, h) * (2.75 / 1024.0);

    final houseStroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12 * s
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    canvas.drawPath(_lifeOsHousePath(s), houseStroke);

    _paintLifeOsFamilySilhouettes(canvas, s, color: Colors.white);

    final leafFill = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    canvas.drawPath(_lifeOsLeftLeafPath(s), leafFill);
    canvas.drawPath(_lifeOsRightLeafPath(s), leafFill);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Official Horizontal Brand Logo (`[House-Family-Leaves Symbol] LifeOS`) following BrandKit 1.0:
/// - Light Mode (`primary`): Color Symbol + `Life` (`#113824` Forest) + `OS` (`#0B7A2A` Primary).
/// - Dark Mode (`white`): White Symbol + `LifeOS` (`#FFFFFF`).
class LifeOsBrandWordmark extends StatelessWidget {
  final double iconSize;
  final double fontSize;
  final LifeOsWordmarkStyle style;

  const LifeOsBrandWordmark({
    super.key,
    this.iconSize = 34,
    this.fontSize = 21,
    this.style = LifeOsWordmarkStyle.auto,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final effectiveStyle = style == LifeOsWordmarkStyle.auto
        ? (isDark ? LifeOsWordmarkStyle.white : LifeOsWordmarkStyle.primary)
        : style;

    final (symbolVariant, lifeColor, osColor) = switch (effectiveStyle) {
      LifeOsWordmarkStyle.primary => (
        LifeOsSymbolVariant.color,
        LifeOSBrandColors.forest,
        LifeOSBrandColors.primary,
      ),
      LifeOsWordmarkStyle.white => (
        LifeOsSymbolVariant.white,
        Colors.white,
        Colors.white,
      ),
      LifeOsWordmarkStyle.black => (
        LifeOsSymbolVariant.black,
        const Color(0xFF111111),
        const Color(0xFF111111),
      ),
      LifeOsWordmarkStyle.auto => (
        LifeOsSymbolVariant.color,
        LifeOSBrandColors.forest,
        LifeOSBrandColors.primary,
      ),
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        LifeOsSymbolMark(size: iconSize, variant: symbolVariant),
        SizedBox(width: iconSize * 0.22),
        Text.rich(
          TextSpan(
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
              height: 1.05,
            ),
            children: [
              TextSpan(
                text: 'Life',
                style: TextStyle(color: lifeColor),
              ),
              TextSpan(
                text: 'OS',
                style: TextStyle(color: osColor),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Official Stacked Brand Logo (`LifeOS_Logo_Stacked_Primary.svg`) for Hero / Welcome / About cards.
class LifeOsStackedBrandLogo extends StatelessWidget {
  final double symbolSize;
  final double fontSize;
  final bool showTagline;

  const LifeOsStackedBrandLogo({
    super.key,
    this.symbolSize = 76,
    this.fontSize = 28,
    this.showTagline = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LifeOsSymbolMark(
          size: symbolSize,
          variant: isDark
              ? LifeOsSymbolVariant.white
              : LifeOsSymbolVariant.color,
        ),
        const SizedBox(height: 8),
        Text.rich(
          TextSpan(
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.7,
              height: 1.08,
            ),
            children: [
              TextSpan(
                text: 'Life',
                style: TextStyle(
                  color: isDark ? Colors.white : LifeOSBrandColors.forest,
                ),
              ),
              TextSpan(
                text: 'OS',
                style: TextStyle(
                  color: isDark
                      ? LifeOSBrandColors.primaryLight
                      : LifeOSBrandColors.primary,
                ),
              ),
            ],
          ),
        ),
        if (showTagline) ...[
          const SizedBox(height: 6),
          Text(
            'Một ứng dụng. Cả cuộc sống.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: c.textSecondary,
            ),
          ),
        ],
      ],
    );
  }
}

/// Multi-orb refractive ambient light canvas shared across ALL LifeOS screens
/// so Apple Liquid Glass cards, capsules, and floating docks visibly refract subtle depth.
class LifeOsMintWaveCanvas extends StatelessWidget {
  final Widget child;

  const LifeOsMintWaveCanvas({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ColoredBox(
      color: c.background,
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _MintOrganicWavePainter(isDark: isDark),
                ),
              ),
            ),
          ),
          Material(type: MaterialType.transparency, child: child),
        ],
      ),
    );
  }
}

class _MintOrganicWavePainter extends CustomPainter {
  final bool isDark;

  const _MintOrganicWavePainter({required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // 1. Subtle Top-Right Daylight Studio Bloom (restrained, calm & professional)
    final topRightGlow = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.92, -0.82),
        radius: 1.0,
        colors: isDark
            ? [
                const Color(0xFF14532D).withValues(alpha: 0.14),
                Colors.transparent,
              ]
            : [
                const Color(0xFFDCFCE7).withValues(alpha: 0.34),
                Colors.transparent,
              ],
      ).createShader(rect);
    canvas.drawRect(rect, topRightGlow);

    // 2. Subtle Top-Left Cool Daylight Bloom
    final topLeftGlow = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.88, -0.78),
        radius: 0.90,
        colors: isDark
            ? [
                const Color(0xFF1E3A5F).withValues(alpha: 0.12),
                Colors.transparent,
              ]
            : [
                const Color(0xFFEFF6FF).withValues(alpha: 0.42),
                Colors.transparent,
              ],
      ).createShader(rect);
    canvas.drawRect(rect, topLeftGlow);

    // 3. Soft Lower Ambient Studio Light
    final lowerGlow = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.45, 0.92),
        radius: 0.95,
        colors: isDark
            ? [
                const Color(0xFF14532D).withValues(alpha: 0.10),
                Colors.transparent,
              ]
            : [
                const Color(0xFFF0FDF4).withValues(alpha: 0.36),
                Colors.transparent,
              ],
      ).createShader(rect);
    canvas.drawRect(rect, lowerGlow);
  }

  @override
  bool shouldRepaint(covariant _MintOrganicWavePainter oldDelegate) =>
      oldDelegate.isDark != isDark;
}

/// Circular Apple Liquid Glass icon orb used in `LifeOsTopBrandHeader` (Search, Bell, Back, Extra).
class LifeOsHeaderCircleButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool showUnreadDot;
  final Key? buttonKey;

  const LifeOsHeaderCircleButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.showUnreadDot = false,
    this.buttonKey,
  });

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return Tooltip(
      message: tooltip,
      child: LiquidGlassSurface(
        material: LiquidGlassMaterial.navigationChrome,
        borderRadius: 19,
        blurSigma: 20,
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            key: buttonKey,
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 38,
              height: 38,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(icon, size: 19, color: c.textPrimary),
                  if (showUnreadDot)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: c.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: c.surface, width: 1.5),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Redesigned Pro Max Top Header:
/// - Sub-pages (`showBackButton == true`): Sleek single-row bar (`< Back` + Title/Subtitle + Trailing), saving vertical space.
/// - Primary Tab Roots (`showBackButton == false`): Official `LifeOsBrandWordmark` + Unified Pill Action Capsule (`Aa · Search · Bell`) + Title Row.
class LifeOsTopBrandHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool showBackButton;
  final VoidCallback? onBack;
  final Widget? trailingAction;
  final List<Widget> extraBrandActions;
  final Widget? profileTrailing;
  final bool showUnreadNotificationDot;

  const LifeOsTopBrandHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.showBackButton = false,
    this.onBack,
    this.trailingAction,
    this.extraBrandActions = const [],
    this.profileTrailing,
    this.showUnreadNotificationDot = true,
  });

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final themeBloc = _maybeThemeBloc(context, listen: true);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final compact = themeBloc?.state.compactDensity ?? true;

    if (showBackButton) {
      return Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.md,
          compact ? 6 : 10,
          AppSpacing.md,
          compact ? 6 : 10,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppSpacing.maxContentWidth,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final splitTrailingBelow =
                    extraBrandActions.isNotEmpty &&
                    trailingAction != null &&
                    constraints.maxWidth < 430;
                final hasSub = subtitle != null && subtitle!.isNotEmpty;
                final fitSingleLineTitle = !hasSub && title.length <= 34;
                final titleText = Text(
                  title,
                  softWrap: !fitSingleLineTitle,
                  style: TextStyle(
                    fontSize: compact ? 17.5 : 18.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    height: 1.18,
                    color: c.textPrimary,
                  ),
                );

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        LifeOsHeaderCircleButton(
                          icon: Icons.chevron_left_rounded,
                          tooltip: 'Quay lại',
                          onTap:
                              onBack ??
                              () {
                                if (context.canPop()) {
                                  context.pop();
                                } else {
                                  context.go('/today');
                                }
                              },
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (fitSingleLineTitle)
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: titleText,
                                )
                              else
                                titleText,
                              if (hasSub && splitTrailingBelow) ...[
                                const SizedBox(height: 2),
                                Text(
                                  subtitle!,
                                  softWrap: true,
                                  style: TextStyle(
                                    fontSize: 12.2,
                                    fontWeight: FontWeight.w500,
                                    height: 1.25,
                                    color: c.textSecondary,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        ...extraBrandActions.map(
                          (w) => Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: w,
                          ),
                        ),
                        if (themeBloc != null &&
                            trailingAction == null &&
                            extraBrandActions.isEmpty) ...[
                          const SizedBox(width: 6),
                          LifeOsHeaderCircleButton(
                            buttonKey: const Key(
                              'open_appearance_studio_button',
                            ),
                            icon: isDark
                                ? Icons.light_mode_outlined
                                : Icons.text_fields_rounded,
                            tooltip: 'Giao diện Sáng/Tối & Cỡ chữ',
                            onTap: () => showLifeOsAppearanceSheet(context),
                          ),
                        ],
                        if (trailingAction != null && !splitTrailingBelow) ...[
                          const SizedBox(width: 8),
                          Flexible(
                            fit: FlexFit.loose,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerRight,
                              child: trailingAction!,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (hasSub && !splitTrailingBelow) ...[
                      const SizedBox(height: 3),
                      Padding(
                        padding: const EdgeInsets.only(left: 48),
                        child: Text(
                          subtitle!,
                          softWrap: true,
                          style: TextStyle(
                            fontSize: 12.2,
                            fontWeight: FontWeight.w500,
                            height: 1.25,
                            color: c.textSecondary,
                          ),
                        ),
                      ),
                    ],
                    if (splitTrailingBelow) ...[
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerRight,
                        child: trailingAction!,
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.md,
        compact ? 4 : 8,
        AppSpacing.md,
        compact ? 6 : 10,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppSpacing.maxContentWidth,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Row 1: Official Brand Wordmark + Unified Frosted Pill Capsule + Profile
              Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Tooltip(
                          message: 'Bảng tính năng LifeOS',
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              key: const Key('open_logo_side_drawer_button'),
                              borderRadius: BorderRadius.circular(14),
                              onTap: () => showLifeOsLogoSideDrawer(context),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 4,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.menu_rounded,
                                      size: compact ? 20 : 22,
                                      color: c.textPrimary,
                                    ),
                                    const SizedBox(width: 6),
                                    LifeOsBrandWordmark(
                                      iconSize: compact ? 30 : 34,
                                      fontSize: compact ? 18.5 : 20,
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
                  if (extraBrandActions.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Flexible(
                      fit: FlexFit.loose,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: extraBrandActions
                              .map(
                                (w) => Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: w,
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    ),
                  ],
                  LiquidGlassSurface(
                    material: LiquidGlassMaterial.navigationChrome,
                    borderRadius: 24,
                    blurSigma: 22,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 3,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (themeBloc != null)
                          _CapsuleIconBtn(
                            buttonKey: const Key(
                              'open_appearance_studio_button',
                            ),
                            icon: isDark
                                ? Icons.light_mode_outlined
                                : Icons.text_fields_rounded,
                            tooltip: 'Giao diện Sáng/Tối & Cỡ chữ',
                            onTap: () => showLifeOsAppearanceSheet(context),
                          ),
                        _CapsuleIconBtn(
                          icon: Icons.search_rounded,
                          tooltip: 'Tìm kiếm nhanh LifeOS',
                          onTap: () => showLifeOsOmniSearchSheet(context),
                        ),
                        _CapsuleIconBtn(
                          icon: Icons.notifications_none_rounded,
                          tooltip: 'Trung tâm Thông báo',
                          showUnreadDot: showUnreadNotificationDot,
                          onTap: () => context.push('/activity-notifications'),
                        ),
                      ],
                    ),
                  ),
                  if (profileTrailing != null) ...[
                    const SizedBox(width: 4),
                    profileTrailing!,
                  ],
                ],
              ),
              SizedBox(height: compact ? 8 : 11),

              // Row 2: Page Greeting / Title + Primary Action, with full-width subtitle below
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: title.length <= 28
                          ? FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                title,
                                style: TextStyle(
                                  fontSize: compact ? 20.5 : 23,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.4,
                                  height: 1.18,
                                  color: c.textPrimary,
                                ),
                              ),
                            )
                          : Text(
                              title,
                              softWrap: true,
                              style: TextStyle(
                                fontSize: compact ? 20.5 : 23,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.4,
                                height: 1.18,
                                color: c.textPrimary,
                              ),
                            ),
                    ),
                  ),
                  if (trailingAction != null) ...[
                    const SizedBox(width: 8),
                    Flexible(
                      fit: FlexFit.loose,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: trailingAction!,
                      ),
                    ),
                  ],
                ],
              ),
              if (subtitle != null && subtitle!.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  subtitle!,
                  softWrap: true,
                  style: TextStyle(
                    fontSize: compact ? 12.2 : 13,
                    fontWeight: FontWeight.w500,
                    height: 1.28,
                    color: c.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CapsuleIconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool showUnreadDot;
  final Key? buttonKey;

  const _CapsuleIconBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.showUnreadDot = false,
    this.buttonKey,
  });

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        key: buttonKey,
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: SizedBox(
          width: 34,
          height: 32,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(icon, size: 18.5, color: c.textPrimary),
              if (showUnreadDot)
                Positioned(
                  right: 7,
                  top: 6,
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: c.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: c.surface, width: 1.2),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Specular 60/120 FPS Apple Liquid Glass `22px` card surface.
class LifeOsSoftCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? backgroundColor;
  final Color? borderColor;
  final double borderRadius;

  const LifeOsSoftCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.backgroundColor,
    this.borderColor,
    this.borderRadius = 18,
  });

  @override
  Widget build(BuildContext context) {
    return LiquidGlassSurface(
      material: LiquidGlassMaterial.card,
      borderRadius: borderRadius,
      padding: padding,
      onTap: onTap,
      enableBlur: false,
      tintColor: backgroundColor,
      accentRimColor: borderColor,
      rimIntensity: 0.65,
      child: child,
    );
  }
}

/// Clean Porcelain-Mint Summary Card used across Home, Family, Funds, Tasks & Settings.
class LifeOsMintHeroCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  const LifeOsMintHeroCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return LiquidGlassSurface(
      material: LiquidGlassMaterial.mintHero,
      borderRadius: 18,
      padding: padding,
      onTap: onTap,
      enableBlur: false,
      rimIntensity: 0.72,
      child: child,
    );
  }
}

/// Unified `42×42` rounded Apple Liquid Glass squircle icon container.
/// Automatically renders its cohesive Nano Banana Pro 3D Liquid Glass icon asset when available.
class LifeOsIconSquircle extends StatelessWidget {
  final IconData icon;
  final LifeOsAccentTone tone;
  final double size;
  final double iconSize;
  final bool solidFill;
  final String? bananaAsset;

  const LifeOsIconSquircle({
    super.key,
    required this.icon,
    this.tone = LifeOsAccentTone.emerald,
    this.size = 42,
    this.iconSize = 21,
    this.solidFill = false,
    this.bananaAsset,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final (bg, fg) = tone.resolve(context);
    final radius = size * 0.32;

    if (!solidFill) {
      final resolvedAsset =
          bananaAsset ?? AppAssets.resolveBananaIconForGlyph(icon);
      if (resolvedAsset != null) {
        return BananaGlassIcon(
          assetPath: resolvedAsset,
          fallbackIcon: icon,
          fallbackColor: fg,
          size: size,
          borderRadius: radius,
        );
      }
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: solidFill
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color.lerp(fg, Colors.white, 0.16)!, fg],
              )
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.lerp(bg, Colors.white, isDark ? 0.08 : 0.42)!,
                  bg,
                ],
              ),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: solidFill
              ? Colors.white.withValues(alpha: 0.34)
              : fg.withValues(alpha: isDark ? 0.30 : 0.18),
          width: 0.9,
        ),
      ),
      child: Icon(icon, size: iconSize, color: solidFill ? Colors.white : fg),
    );
  }
}

/// Unified soft status / category pill (`✓ Đang tốt`, `Công việc`, `Gia đình`, `98%`).
class LifeOsStatusPill extends StatelessWidget {
  final String label;
  final IconData? icon;
  final LifeOsAccentTone tone;

  const LifeOsStatusPill({
    super.key,
    required this.label,
    this.icon,
    this.tone = LifeOsAccentTone.emerald,
  });

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = tone.resolve(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13.5, color: fg),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              softWrap: true,
              style: TextStyle(
                fontSize: 12.2,
                fontWeight: FontWeight.w700,
                height: 1.2,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-width Emerald CTA pill button (`+ Thêm việc mới`, `🔔 Lưu nhắc nhở`, `🔔 Đặt nhắc bảo dưỡng`).
class LifeOsPrimaryCtaButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final IconData? trailingIcon;
  final VoidCallback? onPressed;

  const LifeOsPrimaryCtaButton({
    super.key,
    required this.label,
    this.icon,
    this.trailingIcon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return SizedBox(
      height: 50,
      width: double.infinity,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: c.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(25),
          ),
          elevation: 0,
        ),
        onPressed: onPressed,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20, color: Colors.white),
                const SizedBox(width: 8),
              ],
              Text(
                label,
                style: const TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              if (trailingIcon != null) ...[
                const SizedBox(width: 8),
                Icon(trailingIcon, size: 19, color: Colors.white),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Overlapping circular member avatar stack + optional pending-invite badges + `+` invite button.
class LifeOsAvatarStack extends StatelessWidget {
  final List<String> names;
  final List<String> pendingNames;
  final VoidCallback? onAddTap;
  final double radius;

  const LifeOsAvatarStack({
    super.key,
    required this.names,
    this.pendingNames = const [],
    this.onAddTap,
    this.radius = 16,
  });

  static const List<Color> _palette = [
    Color(0xFF0EA5E9),
    Color(0xFFEC4899),
    Color(0xFFF59E0B),
    Color(0xFF8B5CF6),
    Color(0xFF10B981),
  ];

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final display = names.isEmpty ? const ['Tôi'] : names.take(4).toList();
    final pendingDisplay = pendingNames
        .take((5 - display.length).clamp(0, 2))
        .toList();
    final step = radius * 1.45;
    final count =
        display.length + pendingDisplay.length + (onAddTap != null ? 1 : 0);
    final totalWidth = count == 0 ? 0.0 : (count - 1) * step + radius * 2;

    return SizedBox(
      width: totalWidth,
      height: radius * 2,
      child: Stack(
        children: [
          for (var i = 0; i < display.length; i++)
            Positioned(
              left: i * step,
              child: Container(
                width: radius * 2,
                height: radius * 2,
                decoration: BoxDecoration(
                  color: _palette[i % _palette.length],
                  shape: BoxShape.circle,
                  border: Border.all(color: c.surface, width: 2),
                ),
                alignment: Alignment.center,
                child: Text(
                  display[i].trim().isEmpty
                      ? 'U'
                      : display[i].trim().characters.first.toUpperCase(),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: radius * 0.72,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          for (var j = 0; j < pendingDisplay.length; j++)
            Positioned(
              left: (display.length + j) * step,
              child: Tooltip(
                message: 'Đang chờ tham gia: ${pendingDisplay[j]}',
                child: Container(
                  width: radius * 2,
                  height: radius * 2,
                  decoration: BoxDecoration(
                    color: c.warningSubtle,
                    shape: BoxShape.circle,
                    border: Border.all(color: c.warning, width: 1.6),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    pendingDisplay[j].trim().isEmpty
                        ? '?'
                        : pendingDisplay[j]
                              .trim()
                              .characters
                              .first
                              .toUpperCase(),
                    style: TextStyle(
                      color: c.warning,
                      fontSize: radius * 0.68,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
          if (onAddTap != null)
            Positioned(
              left: (display.length + pendingDisplay.length) * step,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onAddTap,
                child: Container(
                  width: radius * 2,
                  height: radius * 2,
                  decoration: BoxDecoration(
                    color: c.primarySubtle,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: c.primary.withValues(alpha: 0.45),
                      width: 1.5,
                    ),
                  ),
                  child: Icon(
                    Icons.person_add_alt_1_rounded,
                    size: radius * 0.95,
                    color: c.primary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Square / Squircle feature icon tile used in Home `3×3` Grid and Vehicle `3-card` action row.
class LifeOsFeatureGridTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final LifeOsAccentTone tone;
  final VoidCallback onTap;

  const LifeOsFeatureGridTile({
    super.key,
    required this.icon,
    required this.label,
    this.tone = LifeOsAccentTone.emerald,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return LifeOsSoftCard(
      borderRadius: 18,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          LifeOsIconSquircle(icon: icon, tone: tone, size: 40, iconSize: 20),
          const SizedBox(height: 7),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.6,
                fontWeight: FontWeight.w700,
                height: 1.2,
                color: c.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Unified Apple Liquid Glass Segmented Pill Bar (`Ngày | Tuần | Tháng` or `Sáng | Tối | Hệ thống`).
class LifeOsSegmentedPills<T> extends StatelessWidget {
  final List<(T value, String label, IconData? icon)> options;
  final T selected;
  final ValueChanged<T> onChanged;

  const LifeOsSegmentedPills({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final rawIdx = options.indexWhere((o) => o.$1 == selected);
    final activeIdx = rawIdx < 0 ? 0 : rawIdx;
    final count = options.isEmpty ? 1 : options.length;

    return LiquidGlassSurface(
      material: LiquidGlassMaterial.segmentedTrough,
      borderRadius: 13,
      enableBlur: false,
      rimIntensity: 0.45,
      padding: const EdgeInsets.all(3.5),
      child: SizedBox(
        height: 37,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final itemWidth = constraints.maxWidth / count;
            return Stack(
              children: [
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  left: activeIdx * itemWidth,
                  top: 0,
                  bottom: 0,
                  width: itemWidth,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF2D3744) : Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.12)
                            : const Color(0xFFE2E8F0),
                        width: 0.8,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: isDark ? 0.22 : 0.06,
                          ),
                          blurRadius: 6,
                          offset: const Offset(0, 1.5),
                        ),
                      ],
                    ),
                  ),
                ),
                Row(
                  children: options.map((item) {
                    final isSelected = item.$1 == selected;
                    return Expanded(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => onChanged(item.$1),
                        child: Container(
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (item.$3 != null) ...[
                                  Icon(
                                    item.$3,
                                    size: 15.5,
                                    color: isSelected
                                        ? c.primary
                                        : c.textSecondary,
                                  ),
                                  const SizedBox(width: 5),
                                ],
                                Text(
                                  item.$2,
                                  style: TextStyle(
                                    fontSize: 13.2,
                                    fontWeight: isSelected
                                        ? FontWeight.w700
                                        : FontWeight.w600,
                                    letterSpacing: -0.1,
                                    color: isSelected
                                        ? c.textPrimary
                                        : c.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

T? _tryReadSearchBloc<T extends StateStreamableSource<Object?>>(
  BuildContext context,
) {
  try {
    return context.read<T>();
  } catch (_) {
    return null;
  }
}

/// Global Omni-Search Sheet opened from `🔍` in `LifeOsTopBrandHeader`.
/// Searches REAL user data (Transactions, Events, Tasks, Groceries, Notes) + App Screens simultaneously.
Future<void> showLifeOsOmniSearchSheet(BuildContext context) async {
  final txListBloc = _tryReadSearchBloc<TransactionListBloc>(context);
  final calBloc = _tryReadSearchBloc<CalendarBloc>(context);
  final taskBloc = _tryReadSearchBloc<TaskBloc>(context);
  final dailyBloc = _tryReadSearchBloc<DailyLifeBloc>(context);

  final searchItems =
      <
        ({
          String title,
          String subtitle,
          IconData icon,
          String route,
          LifeOsAccentTone tone,
          String? badge,
        })
      >[
        (
          title: 'Trang chủ LifeOS',
          subtitle: 'Tổng quan hôm nay',
          icon: Icons.home_rounded,
          route: '/today',
          tone: LifeOsAccentTone.emerald,
          badge: null,
        ),
        (
          title: 'Chi tiêu & Ngân sách',
          subtitle: 'Ví, thu chi & ngân sách tháng',
          icon: Icons.payments_outlined,
          route: '/finance',
          tone: LifeOsAccentTone.emerald,
          badge: null,
        ),
        (
          title: 'Chi tiết giao dịch (Tự động)',
          subtitle: 'Xác nhận giao dịch ngân hàng mới',
          icon: Icons.auto_awesome_rounded,
          route: '/auto-tx-review',
          tone: LifeOsAccentTone.emerald,
          badge: null,
        ),
        (
          title: 'Báo cáo chi tiêu & Gia đình',
          subtitle: 'Thống kê thu chi & xuất báo cáo',
          icon: Icons.bar_chart_rounded,
          route: '/finance-report',
          tone: LifeOsAccentTone.blue,
          badge: null,
        ),
        (
          title: 'Lịch trình & Google Calendar',
          subtitle: 'Lịch hẹn & đồng bộ Google Calendar',
          icon: Icons.calendar_month_rounded,
          route: '/planning',
          tone: LifeOsAccentTone.emerald,
          badge: null,
        ),
        (
          title: 'Báo thức sự kiện',
          subtitle: 'Hẹn giờ nhắc sự kiện',
          icon: Icons.alarm_on_rounded,
          route: '/event-alarm',
          tone: LifeOsAccentTone.emerald,
          badge: null,
        ),
        (
          title: 'Việc cần làm',
          subtitle: 'Việc cá nhân & phân công gia đình',
          icon: Icons.task_alt_rounded,
          route: '/tasks-board',
          tone: LifeOsAccentTone.blue,
          badge: null,
        ),
        (
          title: 'Quỹ gia đình & Mục tiêu chung',
          subtitle: 'Tiết kiệm chung & lịch sử đóng góp',
          icon: Icons.savings_outlined,
          route: '/family-funds',
          tone: LifeOsAccentTone.emerald,
          badge: null,
        ),
        (
          title: 'Tài liệu gia đình',
          subtitle: 'Hợp đồng, giấy tờ xe & bảo hiểm',
          icon: Icons.folder_copy_outlined,
          route: '/family-documents',
          tone: LifeOsAccentTone.amber,
          badge: null,
        ),
        (
          title: 'Xe cộ & Bảo dưỡng',
          subtitle: 'Thay dầu, bảo hiểm & đăng kiểm',
          icon: Icons.directions_car_outlined,
          route: '/assets',
          tone: LifeOsAccentTone.blue,
          badge: null,
        ),
        (
          title: 'Widget màn hình chính',
          subtitle: 'Ghim tiện ích ra màn hình điện thoại',
          icon: Icons.widgets_outlined,
          route: '/home-widgets',
          tone: LifeOsAccentTone.purple,
          badge: null,
        ),
        (
          title: 'Tiện ích Pro Tích hợp',
          subtitle: 'Thuê bao, lãi vay, thói quen & sổ hiếu hỷ',
          icon: Icons.workspace_premium_rounded,
          route: '/pro-utilities',
          tone: LifeOsAccentTone.emerald,
          badge: null,
        ),
        (
          title: 'Radar Gói Đăng ký & Phiếu Bảo hành',
          subtitle: 'Theo dõi phí gia hạn & hạn bảo hành',
          icon: Icons.radar_rounded,
          route: '/subscriptions-warranty',
          tone: LifeOsAccentTone.emerald,
          badge: null,
        ),
        (
          title: 'Quét Bill AI, Lãi Vay & Tự do FIRE',
          subtitle: 'Tách hóa đơn, tính lãi vay & tiết kiệm',
          icon: Icons.calculate_outlined,
          route: '/wealth-tools',
          tone: LifeOsAccentTone.blue,
          badge: null,
        ),
        (
          title: 'Thói quen, Uống nước & Tập trung',
          subtitle: 'Đồng hồ tập trung & nhắc uống nước',
          icon: Icons.local_fire_department_outlined,
          route: '/habits-focus',
          tone: LifeOsAccentTone.amber,
          badge: null,
        ),
        (
          title: 'Sổ Hiếu Hỷ & Hành lý Du lịch',
          subtitle: 'Ghi tiền mừng cưới & đồ mang đi chơi',
          icon: Icons.card_giftcard_rounded,
          route: '/social-ledger-travel',
          tone: LifeOsAccentTone.purple,
          badge: null,
        ),
        (
          title: 'Tất cả Dịch vụ 360°',
          subtitle: 'Tài chính, sức khỏe, đi chợ, điện nước & lương',
          icon: Icons.apps_rounded,
          route: '/super-app-hub',
          tone: LifeOsAccentTone.emerald,
          badge: null,
        ),
        (
          title: 'Sức khỏe & Tủ thuốc',
          subtitle: 'Nhắc uống thuốc, BMI & thẻ y tế khẩn cấp',
          icon: Icons.favorite_outline_rounded,
          route: '/health-hub',
          tone: LifeOsAccentTone.coral,
          badge: null,
        ),
        (
          title: 'Bếp & Đi chợ Thông minh',
          subtitle: 'Gợi ý món ăn, giỏ đi chợ & tủ lạnh',
          icon: Icons.shopping_basket_outlined,
          route: '/kitchen-groceries',
          tone: LifeOsAccentTone.emerald,
          badge: null,
        ),
        (
          title: 'Điện nước EVN & Nhà cửa',
          subtitle: 'Tính điện 5 bậc, nước & tiền thuê nhà',
          icon: Icons.electric_bolt_rounded,
          route: '/home-living',
          tone: LifeOsAccentTone.amber,
          badge: null,
        ),
        (
          title: 'Ghi chú & Lương Gross–Net',
          subtitle: 'Sổ tay nhanh & tính lương thực nhận',
          icon: Icons.sticky_note_2_outlined,
          route: '/smart-notes-hub',
          tone: LifeOsAccentTone.purple,
          badge: null,
        ),
        (
          title: 'Cài đặt',
          subtitle: 'Tài khoản, giao diện & kết nối ngân hàng',
          icon: Icons.settings_outlined,
          route: '/settings-hub',
          tone: LifeOsAccentTone.neutral,
          badge: null,
        ),
      ];

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    showDragHandle: false,
    builder: (sheetCtx) {
      return _OmniTextControllerHost(
        builder: (ctx, searchCtrl, setModalState) {
          final c = TammySemanticColors.of(ctx);
          final query = searchCtrl.text;
          final q = query.trim();

          final liveDataResults =
              <
                ({
                  String title,
                  String subtitle,
                  IconData icon,
                  String route,
                  LifeOsAccentTone tone,
                  String? badge,
                })
              >[];

          if (q.isNotEmpty) {
            final dateFmt = DateFormat('dd/MM HH:mm');
            // 1. Live Transactions
            final txs =
                txListBloc?.state.allTransactions ??
                const <TransactionEntity>[];
            for (final tx in txs.where(
              (t) => t.verification != TransactionVerification.rejected,
            )) {
              if (VietnameseSearchMatcher.matchesAny(q, [
                tx.merchant,
                tx.categoryName,
                tx.note,
                tx.walletName,
                tx.amountMinor.toString(),
                VndAmount.format(tx.amountMinor),
              ])) {
                liveDataResults.add((
                  title: tx.merchant,
                  subtitle:
                      '${tx.categoryName} · ${dateFmt.format(tx.occurredAt)}',
                  icon: Icons.receipt_long_rounded,
                  route: tx.verification == TransactionVerification.provisional
                      ? '/auto-tx-review'
                      : '/finance',
                  tone: LifeOsAccentTone.emerald,
                  badge:
                      '${tx.direction == 'credit' ? '+' : '-'}${VndAmount.format(tx.amountMinor)}',
                ));
                if (liveDataResults.length >= 6) break;
              }
            }

            // 2. Live Calendar Events
            final events = calBloc?.state.events ?? const [];
            for (final ev in events) {
              if (VietnameseSearchMatcher.matchesAny(q, [
                ev.title,
                ev.location,
                ev.description,
              ])) {
                liveDataResults.add((
                  title: ev.title,
                  subtitle:
                      'Lịch hẹn · ${dateFmt.format(ev.startsAt)}${ev.location != null && ev.location!.isNotEmpty ? " · ${ev.location}" : ""}',
                  icon: Icons.event_available_rounded,
                  route: '/planning',
                  tone: LifeOsAccentTone.blue,
                  badge: 'Lịch',
                ));
                if (liveDataResults.length >= 10) break;
              }
            }

            // 3. Live Tasks
            final tasks = taskBloc?.state.tasks ?? const <TaskEntity>[];
            for (final task in tasks) {
              if (VietnameseSearchMatcher.matchesAny(q, [
                task.title,
                task.description,
                task.assigneeName,
              ])) {
                liveDataResults.add((
                  title: task.title,
                  subtitle: task.status == TaskWorkflowStatus.done
                      ? 'Việc làm · Đã hoàn thành'
                      : 'Việc cần làm · Đang mở',
                  icon: Icons.task_alt_rounded,
                  route: '/tasks-board',
                  tone: LifeOsAccentTone.purple,
                  badge: 'Việc',
                ));
                if (liveDataResults.length >= 13) break;
              }
            }

            // 4. Live Groceries, Smart Notes & Medications
            final snap = dailyBloc?.state.snapshot;
            if (snap != null) {
              for (final g in snap.groceryItems) {
                if (VietnameseSearchMatcher.matchesAny(q, [g.name])) {
                  liveDataResults.add((
                    title: g.name,
                    subtitle: g.inFridgeStorage
                        ? 'Trong tủ lạnh'
                        : 'Giỏ đi chợ',
                    icon: Icons.shopping_basket_outlined,
                    route: '/kitchen-groceries',
                    tone: LifeOsAccentTone.amber,
                    badge: g.estimatedMinor > 0
                        ? VndAmount.format(g.estimatedMinor)
                        : 'Đi chợ',
                  ));
                  if (liveDataResults.length >= 16) break;
                }
              }
              for (final n in snap.notes) {
                if (VietnameseSearchMatcher.matchesAny(q, [
                  n.title,
                  n.content,
                  n.categoryTag,
                ])) {
                  liveDataResults.add((
                    title: n.title,
                    subtitle: n.content,
                    icon: Icons.sticky_note_2_outlined,
                    route: '/smart-notes-hub',
                    tone: LifeOsAccentTone.purple,
                    badge: 'Ghi chú',
                  ));
                  if (liveDataResults.length >= 18) break;
                }
              }
              for (final m in snap.medications) {
                if (VietnameseSearchMatcher.matchesAny(q, [
                  m.name,
                  m.dosage,
                ])) {
                  liveDataResults.add((
                    title: m.name,
                    subtitle: 'Thuốc · ${m.dosage} · ${m.formattedReminderTime}',
                    icon: Icons.medication_outlined,
                    route: '/health-hub',
                    tone: LifeOsAccentTone.coral,
                    badge: 'Thuốc',
                  ));
                  if (liveDataResults.length >= 20) break;
                }
              }
            }
          }

          final screenResults = q.isEmpty
              ? searchItems
              : searchItems
                    .where(
                      (it) => VietnameseSearchMatcher.matchesAny(q, [
                        it.title,
                        it.subtitle,
                      ]),
                    )
                    .toList();

          final combined = [...liveDataResults, ...screenResults];

          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.72,
            maxChildSize: 0.92,
            minChildSize: 0.45,
            builder: (_, scrollCtrl) => LiquidGlassSheetFrame(
              showHandle: true,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      key: const Key('omni_search_text_field'),
                      controller: searchCtrl,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText:
                            'Tìm chi tiêu, lịch hẹn, việc làm, ghi chú, tiện ích...',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: query.isEmpty
                            ? null
                            : IconButton(
                                key: const Key('omni_search_clear_btn'),
                                tooltip: 'Xóa',
                                onPressed: () => setModalState(() {
                                  searchCtrl.clear();
                                }),
                                icon: const Icon(Icons.close_rounded, size: 18),
                              ),
                      ),
                      onChanged: (_) => setModalState(() {}),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: combined.isEmpty
                          ? ListView(
                              controller: scrollCtrl,
                              children: [
                                const SizedBox(height: 24),
                                Icon(
                                  Icons.search_off_rounded,
                                  size: 42,
                                  color: c.textSecondary,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Chưa tìm thấy "$query" trong dữ liệu của bạn',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                    color: c.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Thử gõ từ khóa khác (có dấu hoặc không dấu) hoặc tạo nhanh bên dưới.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: c.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  alignment: WrapAlignment.center,
                                  children: [
                                    OutlinedButton.icon(
                                      onPressed: () => setModalState(() {
                                        searchCtrl.clear();
                                      }),
                                      icon: const Icon(
                                        Icons.filter_alt_off_rounded,
                                        size: 17,
                                      ),
                                      label: const Text('Xem tất cả tiện ích'),
                                    ),
                                    FilledButton.icon(
                                      onPressed: () {
                                        Navigator.of(sheetCtx).pop();
                                        showLifeOsQuickCreateHub(context);
                                      },
                                      icon: const Icon(Icons.add_rounded),
                                      label: const Text('Mở Thêm nhanh (+)'),
                                    ),
                                  ],
                                ),
                              ],
                            )
                          : ListView.separated(
                              controller: scrollCtrl,
                              itemCount: combined.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (_, idx) {
                                final item = combined[idx];
                                return LifeOsSoftCard(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 11,
                                  ),
                                  onTap: () {
                                    Navigator.of(sheetCtx).pop();
                                    if (item.route == '/today' ||
                                        item.route == '/finance' ||
                                        item.route == '/planning' ||
                                        item.route == '/family') {
                                      context.go(item.route);
                                    } else {
                                      context.push(item.route);
                                    }
                                  },
                                  child: Row(
                                    children: [
                                      LifeOsIconSquircle(
                                        icon: item.icon,
                                        tone: item.tone,
                                        size: 40,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              item.title,
                                              softWrap: true,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 14.5,
                                              ),
                                            ),
                                            Text(
                                              item.subtitle,
                                              softWrap: true,
                                              style: Theme.of(
                                                context,
                                              ).textTheme.bodySmall,
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (item.badge != null) ...[
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: c.primarySubtle,
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                          ),
                                          child: Text(
                                            item.badge!,
                                            style: TextStyle(
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w800,
                                              color: c.primary,
                                              fontFeatures: const [
                                                FontFeature.tabularFigures(),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ] else
                                        const Icon(
                                          Icons.chevron_right_rounded,
                                          size: 20,
                                        ),
                                    ],
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
        },
      );
    },
  );
}

/// Quick Create & AI Hub opened by the Center Emerald `+` Squircle Button in the Bottom Navigation Bar.
Future<void> showLifeOsQuickCreateHub(BuildContext context) =>
    showLifeOsQuickCreateHubSheet(context);

class _OmniTextControllerHost extends StatefulWidget {
  final Widget Function(
    BuildContext context,
    TextEditingController controller,
    StateSetter setModalState,
  ) builder;

  const _OmniTextControllerHost({required this.builder});

  @override
  State<_OmniTextControllerHost> createState() =>
      _OmniTextControllerHostState();
}

class _OmniTextControllerHostState extends State<_OmniTextControllerHost> {
  final TextEditingController _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _ctrl, setState);
}

class _DockGridModeScope extends InheritedWidget {
  final bool useHorizontalCapsule;

  const _DockGridModeScope({
    required this.useHorizontalCapsule,
    required super.child,
  });

  static bool useHorizontalOf(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_DockGridModeScope>();
    return scope?.useHorizontalCapsule ?? false;
  }

  @override
  bool updateShouldNotify(covariant _DockGridModeScope oldWidget) =>
      oldWidget.useHorizontalCapsule != useHorizontalCapsule;
}

/// Adaptive Super App shortcut item: renders as a spacious horizontal capsule
/// (`[Icon + Label]`) when paired in 2-column mobile rows so multi-word Vietnamese
/// labels read horizontally on 1 line, or as a centered icon tile on wide screens.
class LifeOsCompactDockItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final LifeOsAccentTone tone;
  final VoidCallback onTap;

  const LifeOsCompactDockItem({
    super.key,
    required this.icon,
    required this.label,
    this.tone = LifeOsAccentTone.emerald,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final useHorizontalCapsule = _DockGridModeScope.useHorizontalOf(context);

    if (useHorizontalCapsule) {
      return Material(
        color: c.surfaceRaised.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
              child: Row(
                children: [
                  LifeOsIconSquircle(
                    icon: icon,
                    tone: tone,
                    size: 34,
                    iconSize: 17.5,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: label.length <= 20
                        ? FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              label,
                              style: TextStyle(
                                fontSize: 12.4,
                                fontWeight: FontWeight.w700,
                                height: 1.2,
                                letterSpacing: -0.1,
                                color: c.textPrimary,
                              ),
                            ),
                          )
                        : Text(
                            label,
                            softWrap: true,
                            style: TextStyle(
                              fontSize: 12.4,
                              fontWeight: FontWeight.w700,
                              height: 1.2,
                              letterSpacing: -0.1,
                              color: c.textPrimary,
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            LifeOsIconSquircle(icon: icon, tone: tone, size: 42, iconSize: 21),
            const SizedBox(height: 6),
            Text(
              label,
              softWrap: true,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.2,
                fontWeight: FontWeight.w700,
                height: 1.22,
                letterSpacing: -0.1,
                color: c.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Auto-height responsive multi-column icon grid replacing fixed-aspect `GridView.count`.
/// Automatically steps 4-column docks down to symmetrical 2-column horizontal capsules
/// on compact phone viewports or enlarged font scales so Vietnamese phrases never stack
/// 1 word per line.
class LifeOsResponsiveIconGrid extends StatelessWidget {
  final List<Widget> children;
  final int columns;
  final double rowSpacing;
  final double columnSpacing;

  const LifeOsResponsiveIconGrid({
    super.key,
    required this.children,
    this.columns = 4,
    this.rowSpacing = 8,
    this.columnSpacing = 4,
  });

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        var effectiveCols = columns;
        var effectiveColSpacing = columnSpacing;
        var effectiveRowSpacing = rowSpacing;
        var useHorizontalCapsule = false;

        if (constraints.maxWidth.isFinite && columns >= 4) {
          final rawCellWidth =
              (constraints.maxWidth - (columns - 1) * columnSpacing) / columns;
          final logicalCellWidth = rawCellWidth / textScale;
          if (logicalCellWidth < 90) {
            effectiveCols = 2;
            effectiveColSpacing = 8;
            effectiveRowSpacing = 7;
            useHorizontalCapsule = true;
          }
        }

        final rows = <Widget>[];
        for (var i = 0; i < children.length; i += effectiveCols) {
          final rowCells = <Widget>[];
          for (var c = 0; c < effectiveCols; c++) {
            if (c > 0) {
              rowCells.add(SizedBox(width: effectiveColSpacing));
            }
            final idx = i + c;
            rowCells.add(
              Expanded(
                child: idx < children.length
                    ? children[idx]
                    : const SizedBox.shrink(),
              ),
            );
          }
          if (rows.isNotEmpty) {
            rows.add(SizedBox(height: effectiveRowSpacing));
          }
          rows.add(
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: rowCells,
              ),
            ),
          );
        }
        return _DockGridModeScope(
          useHorizontalCapsule: useHorizontalCapsule,
          child: Column(mainAxisSize: MainAxisSize.min, children: rows),
        );
      },
    );
  }
}

/// Live Display Studio Bottom Sheet (`☀️ Sáng / 🌙 Tối / 📱 Hệ thống` + `Aa Cỡ chữ 80%–125%` + `Mật độ Gọn`).
Future<void> showLifeOsAppearanceSheet(BuildContext context) async {
  final themeBloc = _maybeThemeBloc(context);
  if (themeBloc == null) return;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    showDragHandle: false,
    builder: (sheetCtx) {
      return BlocProvider<ThemeBloc>.value(
        value: themeBloc,
        child: BlocBuilder<ThemeBloc, ThemeState>(
          builder: (ctx, state) {
            final c = TammySemanticColors.of(ctx);
            return MediaQuery(
              data: MediaQuery.of(
                ctx,
              ).copyWith(textScaler: TextScaler.linear(state.textScale)),
              child: LiquidGlassSheetFrame(
                showHandle: true,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const LifeOsIconSquircle(
                              icon: Icons.palette_outlined,
                              tone: LifeOsAccentTone.emerald,
                              size: 38,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Giao diện Sáng/Tối & Cỡ chữ',
                                    style: TextStyle(
                                      fontSize: 16.5,
                                      fontWeight: FontWeight.w800,
                                      color: c.textPrimary,
                                    ),
                                  ),
                                  Text(
                                    'Áp dụng tức thì và tự lưu cho mọi màn hình',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: c.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // 1. Light / Dark / System Segmented Selector
                        Text(
                          'Chế độ màu sắc',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: c.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        LifeOsSegmentedPills<ThemeMode>(
                          selected: state.themeMode,
                          onChanged: (mode) =>
                              themeBloc.add(ThemeModeChanged(mode)),
                          options: const [
                            (ThemeMode.light, 'Sáng', Icons.light_mode_rounded),
                            (ThemeMode.dark, 'Tối', Icons.dark_mode_rounded),
                            (
                              ThemeMode.system,
                              'Hệ thống',
                              Icons.phone_android_rounded,
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // 2. Font Scale Quick Presets + Fine Slider
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Kích cỡ chữ hiển thị (Aa)',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: c.textPrimary,
                                ),
                              ),
                            ),
                            LifeOsStatusPill(
                              label: '${state.textScalePercent}%',
                              tone: LifeOsAccentTone.emerald,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final preset
                                in const <(double scale, String label)>[
                                  (0.85, 'Nhỏ gọn (85%)'),
                                  (0.92, 'Tối ưu (92%)'),
                                  (1.00, 'Chuẩn (100%)'),
                                  (1.12, 'Chữ lớn (112%)'),
                                ])
                              ChoiceChip(
                                label: Text(preset.$2),
                                selected:
                                    (state.textScale - preset.$1).abs() < 0.025,
                                onSelected: (_) =>
                                    themeBloc.add(TextScaleChanged(preset.$1)),
                              ),
                          ],
                        ),
                        Row(
                          children: [
                            Text(
                              'A-',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: c.textSecondary,
                              ),
                            ),
                            Expanded(
                              child: Slider(
                                key: const Key('appearance_font_scale_slider'),
                                value: state.textScale,
                                min: 0.80,
                                max: 1.25,
                                divisions: 18,
                                onChanged: (v) =>
                                    themeBloc.add(TextScaleChanged(v)),
                              ),
                            ),
                            Text(
                              'A+',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: c.textPrimary,
                              ),
                            ),
                          ],
                        ),

                        // 3. Spatial Compactness Toggle
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            'Tối ưu không gian gọn gàng',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: c.textPrimary,
                            ),
                          ),
                          subtitle: Text(
                            'Thu gọn khoảng đệm thừa để hiển thị trọn vẹn nội dung trên 1 màn hình',
                            style: TextStyle(
                              fontSize: 11.8,
                              color: c.textSecondary,
                            ),
                          ),
                          value: state.compactDensity,
                          onChanged: (v) =>
                              themeBloc.add(CompactDensityToggled(v)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );
    },
  );
}

/// Interactive BrandKit 1.0 Showcase Sheet ("Một ứng dụng. Cả cuộc sống.").
Future<void> showLifeOsBrandIdentitySheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (sheetCtx) {
      final c = TammySemanticColors.of(sheetCtx);
      final swatches = <(String, String, Color)>[
        ('Primary', '#0B7A2A', LifeOSBrandColors.primary),
        ('Light', '#55D52F', LifeOSBrandColors.primaryLight),
        ('Dark', '#03602B', LifeOSBrandColors.primaryDark),
        ('Forest', '#113824', LifeOSBrandColors.forest),
        ('Mint', '#E7F7EB', LifeOSBrandColors.mint),
        ('Ink', '#1D1D1F', LifeOSBrandColors.ink),
      ];

      return Container(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: c.border,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'LIFEOS / BRAND IDENTITY 1.0',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: LifeOSBrandColors.primary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Một ứng dụng. Cả cuộc sống.',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  color: c.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Biểu tượng kết hợp mái nhà, 3 thành viên gia đình và 2 chiếc lá nâng đỡ — đồng bộ trên toàn bộ ứng dụng, Android Adaptive Icon, iOS & Widget.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: c.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),

              // Row 1: Primary Horizontal on White + App Icon on Mint
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Container(
                      height: 112,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFE4E7EC)),
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'LOGO CHÍNH',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: LifeOSBrandColors.primary,
                            ),
                          ),
                          Spacer(),
                          Center(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: LifeOsBrandWordmark(
                                iconSize: 44,
                                fontSize: 28,
                                style: LifeOsWordmarkStyle.primary,
                              ),
                            ),
                          ),
                          Spacer(),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: Container(
                      height: 112,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: LifeOSBrandColors.mint,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'APP ICON',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: LifeOSBrandColors.primary,
                            ),
                          ),
                          Spacer(),
                          Center(
                            child: LifeOsLeafMark(size: 58, borderRadius: 15),
                          ),
                          Spacer(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Forest Reversed Horizontal Banner (`#113824`)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: LifeOSBrandColors.forest,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'DÙNG TRÊN NỀN TỐI (#113824)',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFA7F3D0),
                      ),
                    ),
                    SizedBox(height: 10),
                    Center(
                      child: LifeOsBrandWordmark(
                        iconSize: 42,
                        fontSize: 27,
                        style: LifeOsWordmarkStyle.white,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // 3 Symbol Variants Row (Color, Forest, Monochrome Black)
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE4E7EC)),
                      ),
                      child: const Column(
                        children: [
                          LifeOsSymbolMark(
                            size: 40,
                            variant: LifeOsSymbolVariant.color,
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Bản màu',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1D1D1F),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: LifeOSBrandColors.mint,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Column(
                        children: [
                          LifeOsSymbolMark(
                            size: 40,
                            variant: LifeOsSymbolVariant.forest,
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Forest',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: LifeOSBrandColors.forest,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE4E7EC)),
                      ),
                      child: const Column(
                        children: [
                          LifeOsSymbolMark(
                            size: 40,
                            variant: LifeOsSymbolVariant.black,
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Đơn sắc',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1D1D1F),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Official Color Tokens
              Text(
                'Bảng màu thương hiệu chuẩn',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: c.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: swatches.map((item) {
                  final (label, hex, color) = item;
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: c.surfaceRaised,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: c.border.withValues(alpha: 0.6),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(
                              color: Colors.black.withValues(alpha: 0.12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '$label $hex',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: c.textPrimary,
                          ),
                        ),
                      ],
                    ),
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

/// Clear visual section divider header (UI/UX Pro Max) that separates functional
/// domains on a screen so cards never blur into a single undifferentiated stack.
class LifeOsSectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final LifeOsAccentTone tone;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  const LifeOsSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.tone = LifeOsAccentTone.emerald,
    this.trailing,
    this.padding = const EdgeInsets.only(top: 14, bottom: 8, left: 2, right: 2),
  });

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final (_, fg) = tone.resolve(context);
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 4,
            height: subtitle != null ? 26 : 16,
            decoration: BoxDecoration(
              color: fg,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  softWrap: true,
                  style: TextStyle(
                    fontSize: 13.8,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.15,
                    color: c.textPrimary,
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 1),
                  Text(
                    subtitle!,
                    softWrap: true,
                    style: TextStyle(fontSize: 11.6, color: c.textSecondary),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
  }
}

/// Tactile 2-column Bento shortcut card (`>= 48dp` hit target, zero truncation, zero overflow).
/// Places the icon + corner chevron on top so `title` and `subtitle` get 100% of the card width
/// and display full Vietnamese labels without ever clipping to `...`.
class LifeOsFeatureBentoTile extends StatelessWidget {
  final Key? tileKey;
  final IconData icon;
  final LifeOsAccentTone tone;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const LifeOsFeatureBentoTile({
    super.key,
    this.tileKey,
    required this.icon,
    required this.tone,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return LifeOsSoftCard(
      key: tileKey,
      padding: const EdgeInsets.all(12),
      borderRadius: 18,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              LifeOsIconSquircle(
                icon: icon,
                tone: tone,
                size: 36,
                iconSize: 18,
              ),
              const Spacer(),
              Icon(
                Icons.chevron_right_rounded,
                size: 17,
                color: c.textSecondary,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                softWrap: true,
                style: TextStyle(
                  fontSize: 13.2,
                  height: 1.22,
                  fontWeight: FontWeight.w800,
                  color: c.textPrimary,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
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
    );
  }
}
