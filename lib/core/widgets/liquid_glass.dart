import 'dart:ui';

import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/lifeos_brand_colors.dart';

/// Optical material presets following Apple's Liquid Glass Design System
/// (iOS 26 / iPadOS 26 / macOS Tahoe / visionOS).
enum LiquidGlassMaterial {
  /// Floating bottom dock & primary navigation capsules (live optical refraction).
  floatingDock,

  /// Top navigation bars, header action capsules & circle buttons.
  navigationChrome,

  /// Dynamic-Island style top toast & floating banners.
  floatingToast,

  /// Modal bottom sheets & dialogs with live background blur.
  modalSheet,

  /// Sunken segmented control / pill tab trough.
  segmentedTrough,

  /// Elevated 60/120 FPS translucent card surface (specular glass without per-row blur jank).
  card,

  /// Pastel Emerald-Mint hero glass surface.
  mintHero,
}

/// Centralized optical tokens for Apple Liquid Glass across Light & Dark modes.
abstract final class LiquidGlassTokens {
  static double defaultBlurSigma(LiquidGlassMaterial material) {
    return switch (material) {
      LiquidGlassMaterial.floatingDock => 28.0,
      LiquidGlassMaterial.navigationChrome => 22.0,
      LiquidGlassMaterial.floatingToast => 26.0,
      LiquidGlassMaterial.modalSheet => 28.0,
      LiquidGlassMaterial.segmentedTrough => 18.0,
      LiquidGlassMaterial.card => 0.0,
      LiquidGlassMaterial.mintHero => 0.0,
    };
  }

  /// Multi-stop translucent glass fill gradient simulating light entering from top-left.
  static LinearGradient surfaceGradient({
    required bool isDark,
    required LiquidGlassMaterial material,
    Color? tintColor,
  }) {
    if (tintColor != null) {
      return LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          tintColor.withValues(alpha: isDark ? 0.90 : 0.94),
          tintColor.withValues(alpha: isDark ? 0.80 : 0.86),
        ],
      );
    }

    return switch (material) {
      LiquidGlassMaterial.floatingDock => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isDark
            ? [
                const Color(0xFF18241D).withValues(alpha: 0.78),
                const Color(0xFF0E1612).withValues(alpha: 0.70),
              ]
            : [
                Colors.white.withValues(alpha: 0.80),
                const Color(0xFFF3FAF5).withValues(alpha: 0.70),
              ],
      ),
      LiquidGlassMaterial.navigationChrome => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isDark
            ? [
                const Color(0xFF1A261F).withValues(alpha: 0.78),
                const Color(0xFF111915).withValues(alpha: 0.68),
              ]
            : [
                Colors.white.withValues(alpha: 0.82),
                const Color(0xFFF5FAF7).withValues(alpha: 0.72),
              ],
      ),
      LiquidGlassMaterial.floatingToast => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isDark
            ? [
                const Color(0xFF18241D).withValues(alpha: 0.88),
                const Color(0xFF101813).withValues(alpha: 0.82),
              ]
            : [
                Colors.white.withValues(alpha: 0.88),
                const Color(0xFFF6FBF8).withValues(alpha: 0.82),
              ],
      ),
      LiquidGlassMaterial.modalSheet => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: isDark
            ? [
                const Color(0xFF16211B).withValues(alpha: 0.90),
                const Color(0xFF0D1410).withValues(alpha: 0.95),
              ]
            : [
                Colors.white.withValues(alpha: 0.90),
                const Color(0xFFF4F8F6).withValues(alpha: 0.95),
              ],
      ),
      LiquidGlassMaterial.segmentedTrough => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: isDark
            ? [
                const Color(0xFF0D1410).withValues(alpha: 0.78),
                const Color(0xFF16201A).withValues(alpha: 0.72),
              ]
            : [
                const Color(0xFFE4ECE7).withValues(alpha: 0.76),
                const Color(0xFFF1F6F3).withValues(alpha: 0.82),
              ],
      ),
      LiquidGlassMaterial.card => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isDark
            ? [
                const Color(0xFF17211B).withValues(alpha: 0.92),
                const Color(0xFF111814).withValues(alpha: 0.88),
              ]
            : [
                Colors.white.withValues(alpha: 0.92),
                const Color(0xFFF9FCFA).withValues(alpha: 0.86),
              ],
      ),
      LiquidGlassMaterial.mintHero => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isDark
            ? [
                const Color(0xFF133320).withValues(alpha: 0.92),
                const Color(0xFF0E2116).withValues(alpha: 0.88),
              ]
            : [
                const Color(0xFFE6FAEE).withValues(alpha: 0.92),
                const Color(0xFFF5FCF8).withValues(alpha: 0.86),
              ],
      ),
    };
  }

  /// Dual-layer Apple Liquid Glass elevation shadow (soft ambient + subtle contact).
  static List<BoxShadow> elevationShadows({
    required bool isDark,
    required LiquidGlassMaterial material,
  }) {
    return switch (material) {
      LiquidGlassMaterial.floatingDock => [
        BoxShadow(
          color: const Color(
            0xFF07130C,
          ).withValues(alpha: isDark ? 0.48 : 0.10),
          blurRadius: 28,
          spreadRadius: 0,
          offset: const Offset(0, 10),
        ),
        BoxShadow(
          color: LifeOSBrandColors.primary.withValues(
            alpha: isDark ? 0.10 : 0.05,
          ),
          blurRadius: 14,
          offset: const Offset(0, 3),
        ),
      ],
      LiquidGlassMaterial.floatingToast => [
        BoxShadow(
          color: const Color(
            0xFF07130C,
          ).withValues(alpha: isDark ? 0.46 : 0.12),
          blurRadius: 26,
          offset: const Offset(0, 10),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.04),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ],
      LiquidGlassMaterial.navigationChrome => [
        BoxShadow(
          color: const Color(
            0xFF08140D,
          ).withValues(alpha: isDark ? 0.28 : 0.055),
          blurRadius: 14,
          offset: const Offset(0, 4),
        ),
      ],
      LiquidGlassMaterial.mintHero => [
        BoxShadow(
          color: LifeOSBrandColors.primary.withValues(
            alpha: isDark ? 0.18 : 0.075,
          ),
          blurRadius: 22,
          offset: const Offset(0, 8),
        ),
        if (!isDark)
          BoxShadow(
            color: const Color(0xFF0A1610).withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
      ],
      LiquidGlassMaterial.card => [
        BoxShadow(
          color: const Color(
            0xFF0B1510,
          ).withValues(alpha: isDark ? 0.26 : 0.048),
          blurRadius: 20,
          offset: const Offset(0, 7),
        ),
        if (!isDark)
          BoxShadow(
            color: const Color(0xFF0B1510).withValues(alpha: 0.024),
            blurRadius: 4,
            offset: const Offset(0, 1.5),
          ),
      ],
      LiquidGlassMaterial.modalSheet ||
      LiquidGlassMaterial.segmentedTrough => const [],
    };
  }
}

/// GPU-accelerated CustomPainter rendering Apple Liquid Glass's signature
/// asymmetric directional specular rim + curved top-edge light refraction.
class LiquidGlassRimPainter extends CustomPainter {
  final double borderRadius;
  final bool isDark;
  final double strokeWidth;
  final Color? accentRimColor;
  final double intensity;
  final bool topCornersOnly;

  const LiquidGlassRimPainter({
    required this.borderRadius,
    required this.isDark,
    this.strokeWidth = 1.15,
    this.accentRimColor,
    this.intensity = 1.0,
    this.topCornersOnly = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) {
      return;
    }
    final inset = strokeWidth / 2;
    final rect = Rect.fromLTWH(
      inset,
      inset,
      size.width - strokeWidth,
      size.height - strokeWidth,
    );
    if (rect.width <= 0 || rect.height <= 0) {
      return;
    }

    final rrect = topCornersOnly
        ? RRect.fromRectAndCorners(
            rect,
            topLeft: Radius.circular(borderRadius),
            topRight: Radius.circular(borderRadius),
          )
        : RRect.fromRectAndRadius(rect, Radius.circular(borderRadius));

    final k = intensity.clamp(0.0, 1.6);
    final Color peakLight = accentRimColor != null
        ? Color.lerp(Colors.white, accentRimColor!, isDark ? 0.38 : 0.22)!
        : Colors.white;
    final Color secondaryCatch =
        accentRimColor ?? (isDark ? const Color(0xFFA7F3D0) : Colors.white);

    // 1. Top-inner specular sheen band (curved glass meniscus highlight)
    final sheenHeight = (size.height * 0.36).clamp(8.0, 44.0);
    final sheenRect = Rect.fromLTWH(inset, inset, rect.width, sheenHeight);
    final sheenPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: (isDark ? 0.08 : 0.42) * k),
          Colors.white.withValues(alpha: 0.0),
        ],
      ).createShader(sheenRect);

    canvas.save();
    canvas.clipRRect(rrect);
    canvas.drawRect(sheenRect, sheenPaint);
    canvas.restore();

    // 2. Asymmetric directional specular rim (top-left peak -> flank falloff -> bottom-right prism catch)
    final rimPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..isAntiAlias = true
      ..shader = LinearGradient(
        begin: const Alignment(-1.0, -1.0),
        end: const Alignment(1.0, 1.0),
        stops: const [0.0, 0.34, 0.68, 1.0],
        colors: isDark
            ? [
                peakLight.withValues(alpha: (0.34 * k).clamp(0.0, 1.0)),
                Colors.white.withValues(alpha: (0.10 * k).clamp(0.0, 1.0)),
                Colors.white.withValues(alpha: (0.05 * k).clamp(0.0, 1.0)),
                secondaryCatch.withValues(alpha: (0.20 * k).clamp(0.0, 1.0)),
              ]
            : [
                peakLight.withValues(alpha: (0.96 * k).clamp(0.0, 1.0)),
                const Color(
                  0xFFD5E3DC,
                ).withValues(alpha: (0.62 * k).clamp(0.0, 1.0)),
                const Color(
                  0xFFCBDAD2,
                ).withValues(alpha: (0.48 * k).clamp(0.0, 1.0)),
                secondaryCatch.withValues(alpha: (0.82 * k).clamp(0.0, 1.0)),
              ],
      ).createShader(rect);

    canvas.drawRRect(rrect, rimPaint);
  }

  @override
  bool shouldRepaint(covariant LiquidGlassRimPainter oldDelegate) {
    return oldDelegate.borderRadius != borderRadius ||
        oldDelegate.isDark != isDark ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.accentRimColor != accentRimColor ||
        oldDelegate.intensity != intensity ||
        oldDelegate.topCornersOnly != topCornersOnly;
  }
}

/// Core Apple Liquid Glass container supporting both live optical blur (`enableBlur: true`
/// for floating bars, docks, pills, toasts & sheets) and 120 FPS specular glass
/// (`enableBlur: false` for dense scrollable lists & Bento cards).
class LiquidGlassSurface extends StatelessWidget {
  final Widget child;
  final LiquidGlassMaterial material;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final bool? enableBlur;
  final double? blurSigma;
  final Color? tintColor;
  final Color? accentRimColor;
  final double rimIntensity;
  final List<BoxShadow>? shadows;

  const LiquidGlassSurface({
    super.key,
    required this.child,
    this.material = LiquidGlassMaterial.card,
    this.borderRadius = 22,
    this.padding,
    this.onTap,
    this.enableBlur,
    this.blurSigma,
    this.tintColor,
    this.accentRimColor,
    this.rimIntensity = 1.0,
    this.shadows,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sigma = blurSigma ?? LiquidGlassTokens.defaultBlurSigma(material);
    final useBlur = enableBlur ?? (sigma > 0);
    final radius = BorderRadius.circular(borderRadius);

    Widget content = padding != null
        ? Padding(padding: padding!, child: child)
        : child;

    content = Material(
      type: MaterialType.transparency,
      borderRadius: radius,
      child: onTap != null
          ? InkWell(borderRadius: radius, onTap: onTap, child: content)
          : content,
    );

    Widget glassBody = CustomPaint(
      foregroundPainter: LiquidGlassRimPainter(
        borderRadius: borderRadius,
        isDark: isDark,
        accentRimColor: accentRimColor,
        intensity: rimIntensity,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          gradient: LiquidGlassTokens.surfaceGradient(
            isDark: isDark,
            material: material,
            tintColor: tintColor,
          ),
        ),
        child: content,
      ),
    );

    if (useBlur && sigma > 0) {
      glassBody = ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
          child: glassBody,
        ),
      );
    }

    final resolvedShadows =
        shadows ??
        LiquidGlassTokens.elevationShadows(isDark: isDark, material: material);

    if (resolvedShadows.isEmpty) {
      return glassBody;
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: resolvedShadows,
      ),
      child: glassBody,
    );
  }
}

/// Frosted Apple Liquid Glass frame for modal bottom sheets so live background
/// content softly refracts through the sheet surface.
class LiquidGlassSheetFrame extends StatelessWidget {
  final Widget child;
  final double topRadius;
  final bool showHandle;

  const LiquidGlassSheetFrame({
    super.key,
    required this.child,
    this.topRadius = 30,
    this.showHandle = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = TammySemanticColors.of(context);
    const borderRadius = BorderRadius.vertical(top: Radius.circular(30));

    return ClipRRect(
      borderRadius: BorderRadius.vertical(top: Radius.circular(topRadius)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: CustomPaint(
          foregroundPainter: LiquidGlassRimPainter(
            borderRadius: topRadius,
            isDark: isDark,
            topCornersOnly: true,
            intensity: 1.05,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: borderRadius,
              gradient: LiquidGlassTokens.surfaceGradient(
                isDark: isDark,
                material: LiquidGlassMaterial.modalSheet,
              ),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showHandle)
                    Padding(
                      padding: const EdgeInsets.only(top: 10, bottom: 4),
                      child: Container(
                        width: 38,
                        height: 4.5,
                        decoration: BoxDecoration(
                          color: c.textSecondary.withValues(alpha: 0.32),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                  Flexible(child: child),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Signature 3D Glossy Apple Liquid Glass Emerald `+` Jewel Button (`48×48` tactile target)
/// used at the center of LifeOS's floating Liquid Glass navigation dock.
class LiquidGlassJewelButton extends StatelessWidget {
  final Key? buttonKey;
  final String tooltip;
  final VoidCallback onTap;
  final IconData icon;
  final double size;

  const LiquidGlassJewelButton({
    super.key,
    this.buttonKey,
    required this.tooltip,
    required this.onTap,
    this.icon = Icons.add_rounded,
    this.size = 48,
  });

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final radius = size * 0.38;
    return Tooltip(
      message: tooltip,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          boxShadow: [
            BoxShadow(
              color: c.primary.withValues(alpha: 0.38),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
            BoxShadow(
              color: Colors.white.withValues(alpha: 0.22),
              blurRadius: 2,
              offset: const Offset(0, -0.5),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(radius),
          child: InkWell(
            key: buttonKey,
            borderRadius: BorderRadius.circular(radius),
            onTap: onTap,
            child: CustomPaint(
              foregroundPainter: _LiquidGlassJewelDomePainter(
                borderRadius: radius,
              ),
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radius),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: LifeOSBrandColors.appIconBgGradient,
                    stops: LifeOSBrandColors.appIconBgStops,
                  ),
                ),
                child: Icon(icon, color: Colors.white, size: size * 0.58),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LiquidGlassJewelDomePainter extends CustomPainter {
  final double borderRadius;

  const _LiquidGlassJewelDomePainter({required this.borderRadius});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
      rect.deflate(0.6),
      Radius.circular(borderRadius),
    );

    // Curved top glass lens dome reflection
    canvas.save();
    canvas.clipRRect(rrect);
    final domePath = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height * 0.38)
      ..quadraticBezierTo(
        size.width * 0.5,
        size.height * 0.54,
        0,
        size.height * 0.36,
      )
      ..close();
    canvas.drawPath(
      domePath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0.38),
            Colors.white.withValues(alpha: 0.04),
          ],
        ).createShader(Offset.zero & Size(size.width, size.height * 0.54)),
    );
    canvas.restore();

    // Specular rim around the jewel
    final rimPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..isAntiAlias = true
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: 0.72),
          Colors.white.withValues(alpha: 0.18),
          const Color(0xFFA7F3D0).withValues(alpha: 0.48),
        ],
      ).createShader(rect);
    canvas.drawRRect(rrect, rimPaint);
  }

  @override
  bool shouldRepaint(covariant _LiquidGlassJewelDomePainter oldDelegate) =>
      oldDelegate.borderRadius != borderRadius;
}
