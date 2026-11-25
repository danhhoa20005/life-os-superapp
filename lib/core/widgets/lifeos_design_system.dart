import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/lifeos_brand_colors.dart';
import '../../app/theme/theme_bloc.dart';
import '../../features/authentication/domain/entities/user_entity.dart';
import '../../features/authentication/presentation/bloc/auth_bloc.dart';
import '../constants/app_assets.dart';
import '../motion/lifeos_motion_scope.dart';
import '../motion/lifeos_motion_tokens.dart';
import '../motion/widgets/lifeos_animated_visibility.dart';
import '../motion/widgets/lifeos_pressable.dart';
import 'lifeos_logo_side_drawer.dart';
import 'liquid_glass.dart';
import 'omni_command_palette_sheet.dart';
import 'quick_create_hub_sheet.dart';

export '../motion/lifeos_motion.dart';
export 'lifeos_logo_side_drawer.dart';
export 'lifeos_permissions_popup.dart';
export 'lifeos_top_toast.dart';
export 'liquid_glass.dart';

ThemeBloc? _maybeThemeBloc(BuildContext context, {bool listen = false}) {
  try {
    return BlocProvider.of<ThemeBloc>(context, listen: listen);
  } catch (_) {
    return null;
  }
}

UserEntity? _maybeAuthUser(BuildContext context) {
  try {
    return BlocProvider.of<AuthBloc>(context, listen: true).state.user;
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

    final authUser = _maybeAuthUser(context);
    final Widget? effectiveAvatarTrailing =
        profileTrailing ??
        (authUser != null ? _HeaderEdgeAvatarButton(user: authUser) : null);
    final isHomeBrand =
        title == 'LifeOS' || title.trim().startsWith('Xin chào');
    final hasContextualRow =
        trailingAction != null ||
        extraBrandActions.isNotEmpty ||
        (subtitle != null && subtitle!.isNotEmpty);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Bar 1: Facebook-Standard Single-Row Docked Top Bar
        // Left: LifeOS Wordmark (on Home) or Bold Tab Title  •  Right: (+) (🔍) (🔔) (Aa) + Flush-Right Avatar
        DecoratedBox(
          decoration: BoxDecoration(
            color: c.surface.withValues(alpha: isDark ? 0.94 : 0.97),
            border: Border(
              bottom: BorderSide(color: c.separator, width: 0.8),
            ),
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.md,
              compact ? 6 : 8,
              4,
              compact ? 6 : 8,
            ),
            child: Row(
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
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => showLifeOsLogoSideDrawer(context),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 2,
                                vertical: 3,
                              ),
                              child: isHomeBrand
                                  ? LifeOsBrandWordmark(
                                      iconSize: compact ? 30 : 32,
                                      fontSize: compact ? 19.5 : 21,
                                    )
                                  : Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        LifeOsLeafMark(
                                          size: compact ? 26 : 28,
                                          borderRadius: 8,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          title,
                                          style: TextStyle(
                                            fontSize: compact ? 19.5 : 21,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: -0.4,
                                            height: 1.15,
                                            color: c.textPrimary,
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
                ),
                const SizedBox(width: 6),
                _FbTopCircleIconBtn(
                  buttonKey: const Key('open_menu_directory_button'),
                  icon: Icons.grid_view_rounded,
                  tooltip: 'Menu',
                  onTap: () => context.push('/menu'),
                ),
                const SizedBox(width: 5),
                _FbTopCircleIconBtn(
                  icon: Icons.search_rounded,
                  tooltip: 'Tìm kiếm nhanh LifeOS',
                  onTap: () => showLifeOsOmniSearchSheet(context),
                ),
                const SizedBox(width: 5),
                _FbTopCircleIconBtn(
                  icon: Icons.notifications_none_rounded,
                  tooltip: 'Trung tâm Thông báo',
                  showUnreadDot: showUnreadNotificationDot,
                  onTap: () => context.push('/activity-notifications'),
                ),
                if (themeBloc != null) ...[
                  const SizedBox(width: 5),
                  _FbTopCircleIconBtn(
                    buttonKey: const Key('open_appearance_studio_button'),
                    icon: isDark
                        ? Icons.light_mode_outlined
                        : Icons.text_fields_rounded,
                    tooltip: 'Giao diện Sáng/Tối & Cỡ chữ',
                    onTap: () => showLifeOsAppearanceSheet(context),
                  ),
                ],
                if (effectiveAvatarTrailing != null) ...[
                  const SizedBox(width: 5),
                  effectiveAvatarTrailing,
                ],
              ],
            ),
          ),
        ),

        // Optional Contextual Sub-Strip ONLY when a tab provides primary actions/subtitles
        if (hasContextualRow)
          Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.md,
              compact ? 6 : 8,
              AppSpacing.md,
              compact ? 4 : 6,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: AppSpacing.maxContentWidth,
                ),
                child: Row(
                  children: [
                    if (subtitle != null && subtitle!.isNotEmpty)
                      Expanded(
                        child: Text(
                          subtitle!,
                          softWrap: true,
                          style: TextStyle(
                            fontSize: compact ? 12 : 12.5,
                            fontWeight: FontWeight.w500,
                            height: 1.25,
                            color: c.textSecondary,
                          ),
                        ),
                      )
                    else
                      const Spacer(),
                    if (extraBrandActions.isNotEmpty)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: extraBrandActions
                            .map(
                              (w) => Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: w,
                              ),
                            )
                            .toList(),
                      ),
                    if (trailingAction != null) ...[
                      const SizedBox(width: 6),
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
              ),
            ),
          ),
      ],
    );
  }
}

class _HeaderEdgeAvatarButton extends StatelessWidget {
  final UserEntity user;

  const _HeaderEdgeAvatarButton({required this.user});

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final photo = user.photoUrl;
    return Tooltip(
      message: 'Hồ sơ tài khoản',
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          key: const Key('open_account_profile_button'),
          customBorder: const CircleBorder(),
          onTap: () => context.push('/account-profile'),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [c.primary, c.secondary],
              ),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.72),
                width: 1.6,
              ),
              boxShadow: [
                BoxShadow(
                  color: c.primary.withValues(alpha: 0.22),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: photo != null && photo.isNotEmpty
                ? Image.network(
                    photo,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Center(
                      child: Text(
                        user.initials,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  )
                : Center(
                    child: Text(
                      user.initials,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _FbTopCircleIconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool showUnreadDot;
  final Key? buttonKey;

  const _FbTopCircleIconBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.showUnreadDot = false,
    this.buttonKey,
  });

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fillColor = isDark
        ? const Color(0xFF232C27)
        : const Color(0xFFF0F2F5);

    return Tooltip(
      message: tooltip,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [const Color(0xFF2B3630), const Color(0xFF1F2723)]
                : [const Color(0xFFFFFFFF), fillColor],
          ),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.14)
                : const Color(0xFFDCE5DF),
            width: 0.9,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.24 : 0.055),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: buttonKey,
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 34,
              height: 34,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(icon, size: 19, color: c.textPrimary),
                  if (showUnreadDot)
                    Positioned(
                      right: 6,
                      top: 6,
                      child: Container(
                        width: 7.5,
                        height: 7.5,
                        decoration: BoxDecoration(
                          color: c.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: fillColor, width: 1.3),
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
    final surface = LiquidGlassSurface(
      material: LiquidGlassMaterial.card,
      borderRadius: borderRadius,
      padding: padding,
      onTap: onTap,
      enableBlur: false,
      tintColor: backgroundColor,
      accentRimColor: borderColor,
      rimIntensity: 0.92,
      child: child,
    );
    if (onTap == null) return surface;
    return LifeOsPressable(
      passthroughPointerOnly: true,
      haptic: LifeOsPressHaptic.none,
      pressedScale: LifeOsMotionTokens.pressedScaleStandard,
      child: surface,
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
    final surface = LiquidGlassSurface(
      material: LiquidGlassMaterial.mintHero,
      borderRadius: 18,
      padding: padding,
      onTap: onTap,
      enableBlur: false,
      rimIntensity: 0.96,
      child: child,
    );
    if (onTap == null) return surface;
    return LifeOsPressable(
      passthroughPointerOnly: true,
      haptic: LifeOsPressHaptic.none,
      pressedScale: LifeOsMotionTokens.pressedScaleStandard,
      child: surface,
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

    final resolvedAsset =
        bananaAsset ?? AppAssets.resolveBananaIconForGlyph(icon);
    if (resolvedAsset != null) {
      return BananaGlassIcon(
        assetPath: resolvedAsset,
        fallbackIcon: icon,
        fallbackColor: fg,
        size: size,
        borderRadius: radius,
        isSelected: solidFill,
      );
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
    final button = SizedBox(
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

    if (onPressed == null) return button;
    return LifeOsPressable(
      enabled: true,
      passthroughPointerOnly: true,
      haptic: LifeOsPressHaptic.none,
      pressedScale: LifeOsMotionTokens.pressedScaleStandard,
      child: button,
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
    final motion = LifeOsMotionScope.of(context);
    final pillDuration = motion.resolveDuration(LifeOsMotionTokens.standard);
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
                  duration: pillDuration,
                  curve: motion.resolveCurve(LifeOsMotionTokens.standardCurve),
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

/// Global Omni-Search & Command Palette Sheet opened from `🔍` in `LifeOsTopBrandHeader`.
Future<void> showLifeOsOmniSearchSheet(BuildContext context) =>
    showLifeOsOmniCommandPaletteSheet(context);

/// Quick Create & AI Hub opened by the Center Emerald `+` Squircle Button in the Bottom Navigation Bar.
Future<void> showLifeOsQuickCreateHub(BuildContext context) =>
    showLifeOsQuickCreateHubSheet(context);

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
                  child: SingleChildScrollView(
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

                        // 4. Accessibility Reduce Motion Toggle
                        SwitchListTile.adaptive(
                          key: const Key('appearance_reduce_motion_switch'),
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            'Giảm chuyển động (Reduce Motion)',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: c.textPrimary,
                            ),
                          ),
                          subtitle: Text(
                            'Tối giản hiệu ứng trượt/nảy thành mờ nhẹ nhưng giữ nguyên trạng thái rõ ràng',
                            style: TextStyle(
                              fontSize: 11.8,
                              color: c.textSecondary,
                            ),
                          ),
                          value: state.prefersReducedMotion,
                          onChanged: (v) => themeBloc.add(
                            MotionModeChanged(
                              v
                                  ? LifeOsMotionMode.reduced
                                  : LifeOsMotionMode.system,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final mode in LifeOsMotionMode.values)
                              ChoiceChip(
                                key: Key('appearance_motion_mode_${mode.name}'),
                                label: Text(mode.labelVi),
                                selected: state.motionMode == mode,
                                onSelected: (_) =>
                                    themeBloc.add(MotionModeChanged(mode)),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            key: const Key('appearance_open_motion_gallery_btn'),
                            onPressed: () {
                              Navigator.of(sheetCtx).pop();
                              if (context.mounted) {
                                context.push('/motion-gallery');
                              }
                            },
                            icon: const Icon(
                              Icons.auto_awesome_motion_rounded,
                              size: 18,
                            ),
                            label: const FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text('Mở Motion Studio (66 mẫu)'),
                            ),
                          ),
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
  final bool showSubtitle;
  final LifeOsAccentTone tone;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  const LifeOsSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.showSubtitle = false,
    this.tone = LifeOsAccentTone.emerald,
    this.trailing,
    this.padding = const EdgeInsets.only(top: 14, bottom: 8, left: 2, right: 2),
  });

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final (_, fg) = tone.resolve(context);
    final hasSub = showSubtitle && subtitle != null && subtitle!.isNotEmpty;
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 4,
            height: hasSub ? 26 : 16,
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
                if (hasSub) ...[
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

/// Progressive disclosure button + animated collapsible container ("Chi tiết" / "Thu gọn")
/// keeping primary cards clean and free of dense secondary parameters until tapped.
class LifeOsDetailsDiscloseSection extends StatefulWidget {
  final Key? toggleKey;
  final String label;
  final String expandedLabel;
  final Widget child;
  final bool initiallyExpanded;
  final EdgeInsetsGeometry contentPadding;
  final bool onDarkSurface;

  const LifeOsDetailsDiscloseSection({
    super.key,
    this.toggleKey,
    this.label = 'Chi tiết',
    this.expandedLabel = 'Thu gọn',
    required this.child,
    this.initiallyExpanded = false,
    this.contentPadding = const EdgeInsets.only(top: 10),
    this.onDarkSurface = false,
  });

  @override
  State<LifeOsDetailsDiscloseSection> createState() =>
      _LifeOsDetailsDiscloseSectionState();
}

class _LifeOsDetailsDiscloseSectionState
    extends State<LifeOsDetailsDiscloseSection> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final motion = LifeOsMotionScope.of(context);
    final fg = widget.onDarkSurface
        ? Colors.white.withValues(alpha: 0.92)
        : c.textSecondary;
    final bg = widget.onDarkSurface
        ? Colors.white.withValues(alpha: 0.14)
        : c.surfaceRaised;
    final border = widget.onDarkSurface
        ? Colors.white.withValues(alpha: 0.24)
        : c.border.withValues(alpha: 0.7);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Material(
            color: bg,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: border, width: 0.85),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: widget.toggleKey,
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 5.5,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.tune_rounded,
                      size: 13.5,
                      color: widget.onDarkSurface ? Colors.white : c.primary,
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        _expanded ? widget.expandedLabel : widget.label,
                        softWrap: true,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: fg,
                        ),
                      ),
                    ),
                    const SizedBox(width: 3),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0.0,
                      duration: motion.resolveDuration(
                        LifeOsMotionTokens.micro,
                      ),
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 16,
                        color: fg,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        LifeOsAnimatedVisibility(
          visible: _expanded,
          duration: LifeOsMotionTokens.standard,
          child: Padding(padding: widget.contentPadding, child: widget.child),
        ),
      ],
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
