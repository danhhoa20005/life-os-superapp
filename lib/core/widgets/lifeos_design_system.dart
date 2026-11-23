import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/lifeos_brand_colors.dart';
import '../../app/theme/theme_bloc.dart';
import 'voice_smart_capture_sheet.dart';

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
      LifeOsAccentTone.emerald => isDark
          ? (const Color(0xFF13331E), const Color(0xFF34D399))
          : (const Color(0xFFEAFBF0), const Color(0xFF12B847)),
      LifeOsAccentTone.blue => isDark
          ? (const Color(0xFF13294B), const Color(0xFF60A5FA))
          : (const Color(0xFFEFF6FF), const Color(0xFF2563EB)),
      LifeOsAccentTone.purple => isDark
          ? (const Color(0xFF271B47), const Color(0xFFA78BFA))
          : (const Color(0xFFF5F3FF), const Color(0xFF7C3AED)),
      LifeOsAccentTone.amber => isDark
          ? (const Color(0xFF38290A), const Color(0xFFFBBF24))
          : (const Color(0xFFFEF7E0), const Color(0xFFD97706)),
      LifeOsAccentTone.coral => isDark
          ? (const Color(0xFF3A1616), const Color(0xFFF87171))
          : (const Color(0xFFFEE2E2), const Color(0xFFDC2626)),
      LifeOsAccentTone.neutral => isDark
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
      child: CustomPaint(
        painter: _LifeOsSymbolPainter(variant: variant),
      ),
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

  const LifeOsLeafMark({
    super.key,
    this.size = 36,
    this.borderRadius = 11,
  });

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
        child: const CustomPaint(
          painter: _LifeOsAppIconForegroundPainter(),
        ),
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
          variant: isDark ? LifeOsSymbolVariant.white : LifeOsSymbolVariant.color,
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

/// Top-right soft organic mint leaf wave background shared across ALL LifeOS screens.
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
          Positioned(
            top: 0,
            right: 0,
            left: 0,
            height: 250,
            child: IgnorePointer(
              child: CustomPaint(
                painter: _MintOrganicWavePainter(isDark: isDark),
              ),
            ),
          ),
          child,
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
    final w = size.width;
    final h = size.height;

    final softWave1 = Paint()
      ..style = PaintingStyle.fill
      ..shader = LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: isDark
            ? [
                const Color(0xFF14532D).withValues(alpha: 0.26),
                const Color(0xFF0B0F0D).withValues(alpha: 0.0),
              ]
            : [
                const Color(0xFFBBF7D0).withValues(alpha: 0.55),
                const Color(0xFFDCFCE7).withValues(alpha: 0.12),
              ],
      ).createShader(Rect.fromLTWH(w * 0.35, 0, w * 0.65, h));

    final p1 = Path()
      ..moveTo(w * 0.52, h * 0.72)
      ..quadraticBezierTo(w * 0.72, h * 0.36, w, h * 0.32)
      ..lineTo(w, h * 0.88)
      ..quadraticBezierTo(w * 0.78, h * 0.92, w * 0.52, h * 0.72)
      ..close();
    canvas.drawPath(p1, softWave1);

    final softWave2 = Paint()
      ..style = PaintingStyle.fill
      ..color = isDark
          ? const Color(0xFF166534).withValues(alpha: 0.18)
          : const Color(0xFF86EFAC).withValues(alpha: 0.30);

    final p2 = Path()
      ..moveTo(w * 0.70, h * 0.76)
      ..quadraticBezierTo(w * 0.84, h * 0.45, w, h * 0.44)
      ..lineTo(w, h * 0.82)
      ..close();
    canvas.drawPath(p2, softWave2);
  }

  @override
  bool shouldRepaint(covariant _MintOrganicWavePainter oldDelegate) =>
      oldDelegate.isDark != isDark;
}

/// Circular soft icon button used in `LifeOsTopBrandHeader` (Search, Bell, Back, Extra).
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
      child: Material(
        color: c.surfaceRaised,
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
                Icon(icon, size: 20, color: c.textPrimary),
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
                        border: Border.all(color: c.surface, width: 1.4),
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
}

/// Unified LifeOS Top Brand + Page Title Header following the 10-screen Design Rule.
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

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.md,
        compact ? 4 : 8,
        AppSpacing.md,
        compact ? 6 : 10,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSpacing.maxContentWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Row 1: Brand Wordmark + Appearance/Font (☀️/🌙 Aa) + Search + Bell + Profile
              Row(
                children: [
                  LifeOsBrandWordmark(
                    iconSize: compact ? 30 : 34,
                    fontSize: compact ? 18.5 : 20,
                  ),
                  const Spacer(),
                  ...extraBrandActions.map(
                    (w) => Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: w,
                    ),
                  ),
                  if (themeBloc != null) ...[
                    LifeOsHeaderCircleButton(
                      buttonKey: const Key('open_appearance_studio_button'),
                      icon: isDark ? Icons.light_mode_outlined : Icons.text_fields_rounded,
                      tooltip: 'Giao diện Sáng/Tối & Cỡ chữ',
                      onTap: () => showLifeOsAppearanceSheet(context),
                    ),
                    const SizedBox(width: 6),
                  ],
                  LifeOsHeaderCircleButton(
                    icon: Icons.search_rounded,
                    tooltip: 'Tìm kiếm nhanh LifeOS',
                    onTap: () => showLifeOsOmniSearchSheet(context),
                  ),
                  const SizedBox(width: 6),
                  LifeOsHeaderCircleButton(
                    icon: Icons.notifications_none_rounded,
                    tooltip: 'Trung tâm Thông báo',
                    showUnreadDot: showUnreadNotificationDot,
                    onTap: () => context.push('/activity-notifications'),
                  ),
                  if (profileTrailing != null) ...[
                    const SizedBox(width: 4),
                    profileTrailing!,
                  ],
                ],
              ),
              SizedBox(height: compact ? 8 : 12),

              // Row 2: Either `< Back + Detail Title` OR `Page Title + Subtitle + Trailing`
              if (showBackButton)
                Row(
                  children: [
                    LifeOsHeaderCircleButton(
                      icon: Icons.chevron_left_rounded,
                      tooltip: 'Quay lại',
                      onTap: onBack ??
                          () {
                            if (context.canPop()) {
                              context.pop();
                            } else {
                              context.go('/today');
                            }
                          },
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: compact ? 18.5 : 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                          color: c.textPrimary,
                        ),
                      ),
                    ),
                    if (trailingAction != null) ...[
                      const SizedBox(width: 8),
                      trailingAction!,
                    ],
                  ],
                )
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: compact ? 21 : 24,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.4,
                              height: 1.15,
                              color: c.textPrimary,
                            ),
                          ),
                          if (subtitle != null && subtitle!.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              subtitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: compact ? 12.2 : 13,
                                fontWeight: FontWeight.w500,
                                color: c.textSecondary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (trailingAction != null) ...[
                      const SizedBox(width: 8),
                      trailingAction!,
                    ],
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Crisp white / dark `22px` card following the unified LifeOS surface rule.
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
    this.borderRadius = 22,
  });

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: backgroundColor ?? c.surface,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: borderColor ?? c.separator,
          width: 1,
        ),
        boxShadow: isDark
            ? const []
            : [
                BoxShadow(
                  color: const Color(0xFF101828).withValues(alpha: 0.045),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(borderRadius),
          onTap: onTap,
          child: Padding(
            padding: padding,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Signature Pastel Mint Summary Card used at the top of Home, Family, Funds, Tasks, Event Detail & Settings.
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const [Color(0xFF112C1B), Color(0xFF15221A)]
              : const [Color(0xFFEAFBF0), Color(0xFFF6FDF8)],
        ),
        border: Border.all(
          color: isDark ? const Color(0xFF1E4D2F) : const Color(0xFFC8F2D6),
          width: 1,
        ),
        boxShadow: isDark
            ? const []
            : [
                BoxShadow(
                  color: const Color(0xFF12B847).withValues(alpha: 0.06),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Padding(
            padding: padding,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Unified `42×42` rounded squircle icon container with semantic pastel background.
class LifeOsIconSquircle extends StatelessWidget {
  final IconData icon;
  final LifeOsAccentTone tone;
  final double size;
  final double iconSize;
  final bool solidFill;

  const LifeOsIconSquircle({
    super.key,
    required this.icon,
    this.tone = LifeOsAccentTone.emerald,
    this.size = 42,
    this.iconSize = 21,
    this.solidFill = false,
  });

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = tone.resolve(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: solidFill ? fg : bg,
        borderRadius: BorderRadius.circular(size * 0.31),
      ),
      child: Icon(
        icon,
        size: iconSize,
        color: solidFill ? Colors.white : fg,
      ),
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
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
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
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 20, color: Colors.white),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
            if (trailingIcon != null) ...[
              const SizedBox(width: 8),
              Icon(trailingIcon, size: 19, color: Colors.white),
            ],
          ],
        ),
      ),
    );
  }
}

/// Overlapping circular member avatar stack + optional `+` invite circle.
class LifeOsAvatarStack extends StatelessWidget {
  final List<String> names;
  final VoidCallback? onAddTap;
  final double radius;

  const LifeOsAvatarStack({
    super.key,
    required this.names,
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
    final display = names.isEmpty ? const ['Bố', 'Mẹ', 'Bạn'] : names.take(4).toList();
    final step = radius * 1.45;
    final count = display.length + (onAddTap != null ? 1 : 0);
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
          if (onAddTap != null)
            Positioned(
              left: display.length * step,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onAddTap,
                child: Container(
                  width: radius * 2,
                  height: radius * 2,
                  decoration: BoxDecoration(
                    color: c.surfaceRaised,
                    shape: BoxShape.circle,
                    border: Border.all(color: c.separator, width: 1.5),
                  ),
                  child: Icon(Icons.add_rounded, size: radius * 1.05, color: c.textSecondary),
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 13),
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          LifeOsIconSquircle(icon: icon, tone: tone, size: 42, iconSize: 21),
          const SizedBox(height: 8),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: c.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Unified Segmented Pill Bar (`Ngày | Tuần | Tháng` or `Danh sách | Bảng`).
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
    return Container(
      height: 46,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: c.separator),
      ),
      child: Row(
        children: options.map((item) {
          final isSelected = item.$1 == selected;
          return Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(21),
              onTap: () => onChanged(item.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                decoration: BoxDecoration(
                  color: isSelected ? c.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(21),
                ),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (item.$3 != null) ...[
                      Icon(
                        item.$3,
                        size: 16,
                        color: isSelected ? Colors.white : c.textSecondary,
                      ),
                      const SizedBox(width: 5),
                    ],
                    Flexible(
                      child: Text(
                        item.$2,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: isSelected ? Colors.white : c.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// Global Omni-Search Sheet opened from `🔍` in `LifeOsTopBrandHeader`.
Future<void> showLifeOsOmniSearchSheet(BuildContext context) async {
  final searchItems = <({String title, String subtitle, IconData icon, String route, LifeOsAccentTone tone})>[
    (
      title: 'Trang chủ LifeOS',
      subtitle: 'Tổng quan sự kiện, việc cần làm, chi tiêu & quỹ gia đình',
      icon: Icons.home_rounded,
      route: '/today',
      tone: LifeOsAccentTone.emerald,
    ),
    (
      title: 'Chi tiêu & Ngân sách',
      subtitle: 'Biểu đồ theo ngày, danh mục & sao kê giao dịch',
      icon: Icons.payments_outlined,
      route: '/finance',
      tone: LifeOsAccentTone.emerald,
    ),
    (
      title: 'Chi tiết giao dịch (Tự động)',
      subtitle: 'Đối soát biến động số dư ngân hàng theo bộ quy tắc & xác nhận',
      icon: Icons.auto_awesome_rounded,
      route: '/auto-tx-review',
      tone: LifeOsAccentTone.emerald,
    ),
    (
      title: 'Báo cáo chi tiêu & Gia đình',
      subtitle: 'Phân tích W1–W4 theo tuần/tháng & xuất CSV',
      icon: Icons.bar_chart_rounded,
      route: '/finance-report',
      tone: LifeOsAccentTone.blue,
    ),
    (
      title: 'Lịch trình & Google Calendar',
      subtitle: 'Xem Ngày / Tuần / Tháng & đồng bộ 2 chiều Google',
      icon: Icons.calendar_month_rounded,
      route: '/planning',
      tone: LifeOsAccentTone.emerald,
    ),
    (
      title: 'Báo thức sự kiện toàn màn hình',
      subtitle: 'Nhắc hẹn phát âm thanh, hoãn 5 phút hoặc tắt báo thức',
      icon: Icons.alarm_on_rounded,
      route: '/event-alarm',
      tone: LifeOsAccentTone.emerald,
    ),
    (
      title: 'Phân công công việc (Việc làm)',
      subtitle: 'Danh sách & bảng Kanban theo thành viên',
      icon: Icons.task_alt_rounded,
      route: '/tasks-board',
      tone: LifeOsAccentTone.blue,
    ),
    (
      title: 'Quỹ gia đình & Mục tiêu chung',
      subtitle: 'Du lịch hè, quỹ khẩn cấp & lịch sử đóng góp',
      icon: Icons.savings_outlined,
      route: '/family-funds',
      tone: LifeOsAccentTone.emerald,
    ),
    (
      title: 'Tài liệu gia đình (Kho lưu trữ)',
      subtitle: 'Hóa đơn & Hợp đồng, Giấy tờ xe, Bảo hiểm, Căn cước',
      icon: Icons.folder_copy_outlined,
      route: '/family-documents',
      tone: LifeOsAccentTone.amber,
    ),
    (
      title: 'Xe cộ & Bảo dưỡng',
      subtitle: 'Theo dõi Odometer, thay dầu, bảo hiểm & đăng kiểm',
      icon: Icons.directions_car_outlined,
      route: '/assets',
      tone: LifeOsAccentTone.blue,
    ),
    (
      title: '4 Widget Màn hình chính & Giọng nói AI',
      subtitle: 'Ghim widget ra màn hình chính & nói câu chia tiền tự động',
      icon: Icons.widgets_outlined,
      route: '/home-widgets',
      tone: LifeOsAccentTone.purple,
    ),
    (
      title: 'Tiện ích Tài chính & Đời sống nâng cao',
      subtitle: 'Radar Gói đăng ký & Bảo hành, Quét Bill, Pomodoro, Sổ Hiếu Hỷ',
      icon: Icons.workspace_premium_rounded,
      route: '/pro-utilities',
      tone: LifeOsAccentTone.emerald,
    ),
    (
      title: 'Radar Gói Đăng ký & Phiếu Bảo hành',
      subtitle: 'Phát hiện phí thuê bao trừ ngầm & đếm ngược hạn bảo hành thiết bị',
      icon: Icons.radar_rounded,
      route: '/subscriptions-warranty',
      tone: LifeOsAccentTone.emerald,
    ),
    (
      title: 'Quét Bill AI, Lãi Vay & Tự do FIRE',
      subtitle: 'Bóc tách hóa đơn nhiều món, tính dư nợ giảm dần & 6 Chiếc Lọ',
      icon: Icons.calculate_outlined,
      route: '/wealth-tools',
      tone: LifeOsAccentTone.blue,
    ),
    (
      title: 'Chuỗi Thói quen, Uống Nước & Pomodoro',
      subtitle: 'Đồng hồ tập trung sâu 25p/45p, nhắc uống nước & chuỗi không tiêu thừa',
      icon: Icons.local_fire_department_outlined,
      route: '/habits-focus',
      tone: LifeOsAccentTone.amber,
    ),
    (
      title: 'Sổ Hiếu Hỷ "Có Đi Có Lại" & Hành lý Du lịch',
      subtitle: 'Tra cứu tiền mừng cưới/tân gia hai chiều & mẫu đồ đi biển/Tết',
      icon: Icons.card_giftcard_rounded,
      route: '/social-ledger-travel',
      tone: LifeOsAccentTone.purple,
    ),
    (
      title: 'Tất cả Dịch vụ Siêu ứng dụng 360°',
      subtitle: ' Trung tâm 20+ phân hệ: Tài chính, Sức khỏe, Đi chợ, Điện EVN, Lương',
      icon: Icons.apps_rounded,
      route: '/super-app-hub',
      tone: LifeOsAccentTone.emerald,
    ),
    (
      title: 'Sức khỏe, Tủ thuốc & Thẻ Y tế SOS 115',
      subtitle: 'Lịch uống thuốc, BMI Châu Á, huyết áp & mã số BHYT khẩn cấp',
      icon: Icons.favorite_outline_rounded,
      route: '/health-hub',
      tone: LifeOsAccentTone.coral,
    ),
    (
      title: 'Bếp Gia đình, "Hôm nay ăn gì?" & Đi chợ',
      subtitle: 'Thực đơn cơm nhà, giỏ chợ 1 chạm trừ Ví & tủ lạnh chống hỏng',
      icon: Icons.shopping_basket_outlined,
      route: '/kitchen-groceries',
      tone: LifeOsAccentTone.emerald,
    ),
    (
      title: 'Điện 6 bậc EVN, Nước & Hợp đồng Thuê nhà',
      subtitle: 'Tính công tơ điện bậc thang +8% VAT, chia phòng trọ & tiền cọc',
      icon: Icons.electric_bolt_rounded,
      route: '/home-living',
      tone: LifeOsAccentTone.amber,
    ),
    (
      title: 'Sổ tay Ghi chú Ghim & Lương Gross ⇄ Net',
      subtitle: 'Ghim ghi chú, nhật ký tâm trạng & tính thuế TNCN 7 bậc',
      icon: Icons.sticky_note_2_outlined,
      route: '/smart-notes-hub',
      tone: LifeOsAccentTone.purple,
    ),
    (
      title: 'Cài đặt & Kết nối tích hợp',
      subtitle: 'Google Calendar, SePay Bank Hub, Chế độ tối & Bảo mật',
      icon: Icons.settings_outlined,
      route: '/settings-hub',
      tone: LifeOsAccentTone.neutral,
    ),
  ];

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetCtx) {
      var query = '';
      return StatefulBuilder(
        builder: (ctx, setModalState) {
          final q = query.trim().toLowerCase();
          final filtered = q.isEmpty
              ? searchItems
              : searchItems
                  .where(
                    (it) =>
                        it.title.toLowerCase().contains(q) ||
                        it.subtitle.toLowerCase().contains(q),
                  )
                  .toList();
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.72,
            maxChildSize: 0.92,
            minChildSize: 0.45,
            builder: (_, scrollCtrl) => Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Tìm kiếm màn hình, chi tiêu, lịch, tài liệu...',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                    onChanged: (v) => setModalState(() => query = v),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView.separated(
                      controller: scrollCtrl,
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, idx) {
                        final item = filtered[idx];
                        return LifeOsSoftCard(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                          onTap: () {
                            Navigator.of(sheetCtx).pop();
                            if (item.route == '/today' ||
                                item.route == '/finance' ||
                                item.route == '/planning' ||
                                item.route == '/family' ||
                                item.route == '/assets') {
                              context.go(item.route);
                            } else {
                              context.push(item.route);
                            }
                          },
                          child: Row(
                            children: [
                              LifeOsIconSquircle(icon: item.icon, tone: item.tone, size: 40),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.title,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14.5,
                                      ),
                                    ),
                                    Text(
                                      item.subtitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right_rounded, size: 20),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

/// Quick Create & AI Hub opened by the Center Emerald `+` Squircle Button in the Bottom Navigation Bar.
Future<void> showLifeOsQuickCreateHub(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    builder: (sheetCtx) {
      final c = TammySemanticColors.of(sheetCtx);
      final actions = <({
        String title,
        String subtitle,
        IconData icon,
        LifeOsAccentTone tone,
        VoidCallback onTap,
      })>[
        (
          title: 'Nói câu Ghi & Chia tiền bằng Giọng nói AI',
          subtitle: 'VD: "Ăn lẩu bò 450 nghìn chia đều 3 người"',
          icon: Icons.mic_rounded,
          tone: LifeOsAccentTone.emerald,
          onTap: () {
            Navigator.of(sheetCtx).pop();
            showVoiceSmartCaptureSheet(context, autoStartListening: true);
          },
        ),
        (
          title: 'Duyệt Giao dịch Ngân hàng Chờ Xác nhận',
          subtitle: 'Kiểm tra và xác nhận biến động số dư vừa bắt được',
          icon: Icons.auto_awesome_rounded,
          tone: LifeOsAccentTone.emerald,
          onTap: () {
            Navigator.of(sheetCtx).pop();
            context.push('/auto-tx-review');
          },
        ),
        (
          title: 'Ghi Chi tiêu / Thu nhập mới',
          subtitle: 'Cập nhật sổ cái cá nhân & ngân sách tháng',
          icon: Icons.payments_outlined,
          tone: LifeOsAccentTone.blue,
          onTap: () {
            Navigator.of(sheetCtx).pop();
            context.go('/finance');
          },
        ),
        (
          title: 'Tạo Sự kiện Lịch & Đặt Báo thức',
          subtitle: 'Đồng bộ Google Calendar & chuông nhắc đúng giờ',
          icon: Icons.event_available_rounded,
          tone: LifeOsAccentTone.emerald,
          onTap: () {
            Navigator.of(sheetCtx).pop();
            context.go('/planning');
          },
        ),
        (
          title: 'Giao Việc nhà & Phân công Gia đình',
          subtitle: 'Theo dõi tiến độ Danh sách / Kanban theo thành viên',
          icon: Icons.assignment_turned_in_outlined,
          tone: LifeOsAccentTone.purple,
          onTap: () {
            Navigator.of(sheetCtx).pop();
            context.push('/tasks-board');
          },
        ),
        (
          title: 'Mở Trung tâm Siêu ứng dụng Đời sống 360°',
          subtitle: 'Sức khỏe & Tủ thuốc · Đi chợ · Điện EVN 6 bậc · Lương Gross–Net',
          icon: Icons.apps_rounded,
          tone: LifeOsAccentTone.emerald,
          onTap: () {
            Navigator.of(sheetCtx).pop();
            context.push('/super-app-hub');
          },
        ),
        (
          title: 'Mở Tiện ích Pro 0₫ (Quét Bill AI · Sổ Hiếu Hỷ · Pomodoro)',
          subtitle: '4 bộ công cụ cao cấp: Gói đăng ký, Lãi vay, FIRE, Thói quen',
          icon: Icons.workspace_premium_rounded,
          tone: LifeOsAccentTone.emerald,
          onTap: () {
            Navigator.of(sheetCtx).pop();
            context.push('/pro-utilities');
          },
        ),
        (
          title: 'Thêm Tài liệu vào Kho Gia đình',
          subtitle: 'Hóa đơn, hợp đồng, giấy tờ xe & bảo hiểm',
          icon: Icons.create_new_folder_outlined,
          tone: LifeOsAccentTone.amber,
          onTap: () {
            Navigator.of(sheetCtx).pop();
            context.push('/family-documents');
          },
        ),
      ];

      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const LifeOsLeafMark(size: 32, borderRadius: 10),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Tạo nhanh LifeOS',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: c.textPrimary,
                            ),
                          ),
                          Text(
                            'Chọn thao tác nhanh cho chi tiêu, lịch, công việc hoặc tài liệu',
                            style: TextStyle(fontSize: 12.5, color: c.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                ...actions.map(
                  (a) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: LifeOsSoftCard(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                      onTap: a.onTap,
                      child: Row(
                        children: [
                          LifeOsIconSquircle(icon: a.icon, tone: a.tone, size: 42),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  a.title,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                    color: c.textPrimary,
                                  ),
                                ),
                                Text(
                                  a.subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 12, color: c.textSecondary),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded, color: c.textSecondary),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// Compact 4-column Super App mini-icon item (MoMo / Grab / Apple style) that avoids
/// heavy card borders and fits 8 shortcuts cleanly inside a single grouped container.
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
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            LifeOsIconSquircle(
              icon: icon,
              tone: tone,
              size: 40,
              iconSize: 20,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11.8,
                fontWeight: FontWeight.w700,
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

/// Live Display Studio Bottom Sheet (`☀️ Sáng / 🌙 Tối / 📱 Hệ thống` + `Aa Cỡ chữ 80%–125%` + `Mật độ Gọn`).
Future<void> showLifeOsAppearanceSheet(BuildContext context) async {
  final themeBloc = _maybeThemeBloc(context);
  if (themeBloc == null) return;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetCtx) {
      return BlocProvider<ThemeBloc>.value(
        value: themeBloc,
        child: BlocBuilder<ThemeBloc, ThemeState>(
          builder: (ctx, state) {
            final c = TammySemanticColors.of(ctx);
            return MediaQuery(
              data: MediaQuery.of(ctx).copyWith(
                textScaler: TextScaler.linear(state.textScale),
              ),
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
                                  style: TextStyle(fontSize: 12, color: c.textSecondary),
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
                        onChanged: (mode) => themeBloc.add(ThemeModeChanged(mode)),
                        options: const [
                          (ThemeMode.light, 'Sáng', Icons.light_mode_rounded),
                          (ThemeMode.dark, 'Tối', Icons.dark_mode_rounded),
                          (ThemeMode.system, 'Hệ thống', Icons.phone_android_rounded),
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
                          for (final preset in const <(double scale, String label)>[
                            (0.85, 'Nhỏ gọn (85%)'),
                            (0.92, 'Tối ưu (92%)'),
                            (1.00, 'Chuẩn (100%)'),
                            (1.12, 'Chữ lớn (112%)'),
                          ])
                            ChoiceChip(
                              label: Text(preset.$2),
                              selected: (state.textScale - preset.$1).abs() < 0.025,
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
                              onChanged: (v) => themeBloc.add(TextScaleChanged(v)),
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
                          style: TextStyle(fontSize: 11.8, color: c.textSecondary),
                        ),
                        value: state.compactDensity,
                        onChanged: (v) => themeBloc.add(CompactDensityToggled(v)),
                      ),
                    ],
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
                style: TextStyle(fontSize: 12.5, color: c.textSecondary, height: 1.4),
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
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: c.surfaceRaised,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: c.border.withValues(alpha: 0.6)),
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
