import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/lifeos_brand_colors.dart';
import '../motion/lifeos_motion_preferences.dart';
import '../motion/lifeos_motion_scope.dart';
import '../motion/lifeos_motion_tokens.dart';
import '../motion/widgets/lifeos_pressable.dart';

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
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: isDark
            ? [
                const Color(0xFF242D38).withValues(alpha: 0.90),
                const Color(0xFF1C242E).withValues(alpha: 0.86),
              ]
            : [
                Colors.white.withValues(alpha: 0.92),
                const Color(0xFFF8FAFC).withValues(alpha: 0.86),
              ],
      ),
      LiquidGlassMaterial.navigationChrome => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: isDark
            ? [
                const Color(0xFF252E3A).withValues(alpha: 0.90),
                const Color(0xFF1E2630).withValues(alpha: 0.84),
              ]
            : [
                Colors.white.withValues(alpha: 0.94),
                const Color(0xFFF9FAFB).withValues(alpha: 0.88),
              ],
      ),
      LiquidGlassMaterial.floatingToast => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isDark
            ? [
                const Color(0xFF2C3542).withValues(alpha: 0.95),
                const Color(0xFF222A35).withValues(alpha: 0.92),
              ]
            : [
                const Color(0xFFFFFFFF).withValues(alpha: 0.97),
                const Color(0xFFF8FAFC).withValues(alpha: 0.94),
              ],
      ),
      LiquidGlassMaterial.modalSheet => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: isDark
            ? [
                const Color(0xFF222A34).withValues(alpha: 0.96),
                const Color(0xFF1A2129).withValues(alpha: 0.98),
              ]
            : [
                Colors.white.withValues(alpha: 0.97),
                const Color(0xFFF8FAFC).withValues(alpha: 0.99),
              ],
      ),
      LiquidGlassMaterial.segmentedTrough => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: isDark
            ? [
                const Color(0xFF171D24),
                const Color(0xFF1B222A),
              ]
            : [
                const Color(0xFFEAEEF3),
                const Color(0xFFEEF2F6),
              ],
      ),
      LiquidGlassMaterial.card => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isDark
            ? [
                const Color(0xFF252E3A),
                const Color(0xFF1D242E),
              ]
            : [
                const Color(0xFFFFFFFF),
                const Color(0xFFF7FBF9),
              ],
      ),
      LiquidGlassMaterial.mintHero => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isDark
            ? [
                const Color(0xFF1D3829),
                const Color(0xFF172720),
              ]
            : [
                const Color(0xFFECFBF2),
                const Color(0xFFFFFFFF),
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
            alpha: isDark ? 0.24 : 0.11,
          ),
          blurRadius: 24,
          offset: const Offset(0, 9),
        ),
        if (!isDark)
          BoxShadow(
            color: const Color(0xFF0A1610).withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2.5),
          ),
      ],
      LiquidGlassMaterial.card => [
        BoxShadow(
          color: const Color(
            0xFF0A1811,
          ).withValues(alpha: isDark ? 0.34 : 0.072),
          blurRadius: 22,
          offset: const Offset(0, 8),
        ),
        if (!isDark)
          BoxShadow(
            color: const Color(0xFF0B1510).withValues(alpha: 0.032),
            blurRadius: 5,
            offset: const Offset(0, 2),
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

    // 3. Subtle bottom 3D thickness chamfer (gives cards & docks tactile Apple 3D relief)
    if (!topCornersOnly && size.height >= 28) {
      final bottomEdgePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..isAntiAlias = true
        ..color = isDark
            ? Colors.black.withValues(alpha: 0.22 * k.clamp(0.0, 1.0))
            : const Color(0xFFD2DFD8).withValues(alpha: 0.55 * k.clamp(0.0, 1.0));
      final pad = (borderRadius * 0.65).clamp(6.0, size.width * 0.3);
      canvas.drawLine(
        Offset(pad, size.height - 0.6),
        Offset(size.width - pad, size.height - 0.6),
        bottomEdgePaint,
      );
    }
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

/// Signature Emerald `+` Center Action Button (`48×48` crisp modern 2D fintech target)
/// used dead-center of LifeOS's bottom navigation bar.
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
    final radius = size * 0.5;
    return Tooltip(
      message: tooltip,
      child: LifeOsPressable(
        passthroughPointerOnly: true,
        haptic: LifeOsPressHaptic.light,
        pressedScale: LifeOsMotionTokens.pressedScaleCompact,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            boxShadow: [
              BoxShadow(
                color: c.primary.withValues(alpha: 0.28),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Material(
            color: c.primary,
            borderRadius: BorderRadius.circular(radius),
            child: InkWell(
              key: buttonKey,
              borderRadius: BorderRadius.circular(radius),
              onTap: onTap,
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radius),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.28),
                    width: 1.2,
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

/// Metadata descriptor for each tab in [LiquidGlassSlidingDock].
class LiquidGlassDockItem {
  final int branchIndex;
  final String label;
  final Widget Function(BuildContext context, bool isSelected, Color color)
  iconBuilder;

  const LiquidGlassDockItem({
    required this.branchIndex,
    required this.label,
    required this.iconBuilder,
  });
}

/// Apple iOS 26 Liquid Glass Sliding Floating Bottom Dock:
/// - Physics-driven sliding glass capsule (`Key('lifeos_sliding_dock_pill')`) that morphs
///   like a liquid droplet during tab transitions and glides seamlessly beneath the center `+` jewel.
/// - Interactive horizontal finger scrubbing (`onHorizontalDrag*`) along the bar with real-time
///   optical lens magnification and tactile selection haptics.
class LiquidGlassSlidingDock extends StatefulWidget {
  final Key? dockKey;
  final List<LiquidGlassDockItem> items;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final Widget centerJewel;
  final double jewelSlotWidth;

  const LiquidGlassSlidingDock({
    super.key,
    this.dockKey,
    required this.items,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.centerJewel,
    this.jewelSlotWidth = 58.0,
  }) : assert(items.length == 4, 'Symmetrical 4-tab + center jewel layout');

  @override
  State<LiquidGlassSlidingDock> createState() => _LiquidGlassSlidingDockState();
}

class _LiquidGlassSlidingDockState extends State<LiquidGlassSlidingDock>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late double _fromVisualTab;
  late double _toVisualTab;
  LifeOsMotionPreferences _motion = const LifeOsMotionPreferences();

  bool _isDragging = false;
  double _dragLeftPx = 0.0;
  double _dragVelocityStretchPx = 0.0;
  double _lastTabSlotWidth = 72.0;

  @override
  void initState() {
    super.initState();
    final initial = widget.selectedIndex.clamp(0, 3).toDouble();
    _fromVisualTab = initial;
    _toVisualTab = initial;
    _controller = AnimationController.unbounded(
      vsync: this,
      value: initial,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _motion = LifeOsMotionScope.of(context);
  }

  double _currentAnimatedVisualTab() {
    if (!_controller.isAnimating && !_isDragging) {
      return _toVisualTab;
    }
    return _controller.value;
  }

  void _drivePillTransition({
    required double from,
    required double to,
    double? initialVelocity,
  }) {
    _motion = LifeOsMotionScope.read(context);
    final preservedVelocity = initialVelocity ?? _controller.velocity;
    _fromVisualTab = from;
    _toVisualTab = to;
    final tickersEnabled = TickerMode.valuesOf(context).enabled;
    if (_motion.isMotionOff || !tickersEnabled) {
      _controller.stop();
      _controller.value = to;
      return;
    }
    if (_motion.isReducedMotion) {
      _controller.stop();
      _controller.value = from;
      _controller.animateTo(
        to,
        duration: _motion.resolveDuration(LifeOsMotionTokens.panel),
        curve: LifeOsMotionTokens.standardCurve,
      );
      return;
    }
    if ((from - to).abs() <= LifeOsMotionTokens.springTolerance.distance &&
        preservedVelocity.abs() <=
            LifeOsMotionTokens.springTolerance.velocity) {
      _controller.stop();
      _controller.value = to;
      return;
    }
    final simulation = SpringSimulation(
      LifeOsMotionTokens.snappySpring,
      from,
      to,
      preservedVelocity,
      tolerance: LifeOsMotionTokens.springTolerance,
    );
    _controller.animateWith(simulation).whenComplete(() {
      if (mounted && !_isDragging && !_controller.isAnimating) {
        _controller.value = _toVisualTab;
      }
    });
  }

  @override
  void didUpdateWidget(covariant LiquidGlassSlidingDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex && !_isDragging) {
      _drivePillTransition(
        from: _controller.value,
        to: widget.selectedIndex.clamp(0, 3).toDouble(),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _visualTabToLeftPx(double visualTab, double tabW) {
    final jewelW = widget.jewelSlotWidth;
    if (visualTab <= 1.0) {
      return visualTab * tabW;
    }
    if (visualTab < 2.0) {
      return tabW + (visualTab - 1.0) * (tabW + jewelW);
    }
    return (visualTab * tabW) + jewelW;
  }

  double _leftPxToVisualTab(double leftPx, double tabW) {
    final jewelW = widget.jewelSlotWidth;
    if (tabW <= 1.0) return widget.selectedIndex.toDouble();
    if (leftPx <= tabW) {
      return (leftPx / tabW).clamp(0.0, 1.0);
    }
    if (leftPx < (2.0 * tabW) + jewelW) {
      return 1.0 + ((leftPx - tabW) / (tabW + jewelW));
    }
    return (2.0 + ((leftPx - ((2.0 * tabW) + jewelW)) / tabW)).clamp(2.0, 3.0);
  }

  int? _hitTabIndexAtDx(double dx, double tabW, double innerWidth) {
    if (dx < 0 || dx > innerWidth) return null;
    final jewelStart = 2.0 * tabW;
    final jewelEnd = jewelStart + widget.jewelSlotWidth;
    if (dx < tabW) return 0;
    if (dx < jewelStart) return 1;
    if (dx >= jewelEnd && dx < jewelEnd + tabW) return 2;
    if (dx >= jewelEnd + tabW) return 3;
    return null; // Inside center `+` jewel bridge
  }

  void _handleScrubPosition(
    double localDx, {
    required double innerWidth,
    required double tabW,
    double deltaDx = 0.0,
  }) {
    final maxLeft = (innerWidth - tabW).clamp(0.0, double.infinity);
    final nextLeft = (localDx - (tabW / 2.0)).clamp(0.0, maxLeft);
    setState(() {
      _dragLeftPx = nextLeft;
      _dragVelocityStretchPx = (deltaDx.abs() * 0.65).clamp(0.0, 16.0);
    });

    final hovered = _hitTabIndexAtDx(localDx, tabW, innerWidth);
    if (hovered != null && hovered != widget.selectedIndex) {
      _motion.selectionHaptic();
      widget.onDestinationSelected(hovered);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return LiquidGlassSurface(
      key: widget.dockKey,
      material: LiquidGlassMaterial.floatingDock,
      borderRadius: 32,
      blurSigma: 28,
      rimIntensity: 1.18,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: SizedBox(
        height: 68,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final innerWidth = constraints.maxWidth;
            final tabW = ((innerWidth - widget.jewelSlotWidth) / 4.0).clamp(
              44.0,
              240.0,
            );
            _lastTabSlotWidth = tabW;

            return GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragStart: (details) {
                _controller.stop();
                setState(() => _isDragging = true);
                _handleScrubPosition(
                  details.localPosition.dx,
                  innerWidth: innerWidth,
                  tabW: tabW,
                );
              },
              onHorizontalDragUpdate: (details) {
                _handleScrubPosition(
                  details.localPosition.dx,
                  innerWidth: innerWidth,
                  tabW: tabW,
                  deltaDx: details.primaryDelta ?? 0.0,
                );
              },
              onHorizontalDragEnd: (details) {
                final settledFrom = _leftPxToVisualTab(
                  _dragLeftPx,
                  _lastTabSlotWidth,
                );
                final normalizedVelocity =
                    LifeOsMotionTokens.normalizeVelocity(
                      velocityPxPerSec:
                          details.primaryVelocity ??
                          details.velocity.pixelsPerSecond.dx,
                      extentPx: _lastTabSlotWidth,
                    );
                _controller.value = settledFrom;
                setState(() {
                  _isDragging = false;
                  _dragVelocityStretchPx = 0.0;
                });
                _drivePillTransition(
                  from: settledFrom,
                  to: widget.selectedIndex.clamp(0, 3).toDouble(),
                  initialVelocity: normalizedVelocity,
                );
              },
              onHorizontalDragCancel: () {
                final settledFrom = _leftPxToVisualTab(
                  _dragLeftPx,
                  _lastTabSlotWidth,
                );
                _controller.value = settledFrom;
                setState(() {
                  _isDragging = false;
                  _dragVelocityStretchPx = 0.0;
                });
                _drivePillTransition(
                  from: settledFrom,
                  to: widget.selectedIndex.clamp(0, 3).toDouble(),
                  initialVelocity: 0.0,
                );
              },
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // 1. Sliding Liquid Glass Droplet Pill (glides smoothly across slots & beneath `+` jewel)
                  AnimatedBuilder(
                    animation: _controller,
                    builder: (context, _) {
                      final double baseLeft;
                      final double stretchW;
                      final double pillHeight;

                      if (_isDragging) {
                        baseLeft = _dragLeftPx;
                        stretchW = _motion.isReducedMotion
                            ? 0.0
                            : (4.0 + _dragVelocityStretchPx);
                        pillHeight = _motion.isReducedMotion ? 58.0 : 60.0;
                      } else {
                        final vTab = _currentAnimatedVisualTab();
                        baseLeft = _visualTabToLeftPx(vTab, tabW);
                        final speedTabsPerSec = _controller.isAnimating
                            ? _controller.velocity.abs()
                            : 0.0;
                        final stretchFactor = _motion.isReducedMotion
                            ? 0.0
                            : math
                                  .pow(
                                    (speedTabsPerSec / 4.2).clamp(0.0, 1.0),
                                    0.65,
                                  )
                                  .toDouble();
                        final travelPx =
                            (_visualTabToLeftPx(_toVisualTab, tabW) -
                                    _visualTabToLeftPx(_fromVisualTab, tabW))
                                .abs();
                        final maxStretch = math.max(
                          (travelPx * 0.16).clamp(0.0, 22.0),
                          (speedTabsPerSec * tabW * 0.05).clamp(0.0, 18.0),
                        );
                        stretchW = maxStretch * stretchFactor;
                        pillHeight = 58.0 - (2.2 * stretchFactor);
                      }

                      final baseCenter = baseLeft + (tabW / 2.0);
                      final pillWidth = ((tabW - 4.0) + stretchW).clamp(
                        36.0,
                        innerWidth,
                      );
                      final maxPillLeft = (innerWidth - pillWidth - 1.0).clamp(
                        1.0,
                        double.infinity,
                      );
                      final pillLeft = (baseCenter - (pillWidth / 2.0)).clamp(
                        1.0,
                        maxPillLeft,
                      );
                      final pillTop = (68.0 - pillHeight) / 2.0;

                      return Positioned(
                        left: pillLeft,
                        top: pillTop,
                        width: pillWidth,
                        height: pillHeight,
                        child: IgnorePointer(
                          child: DecoratedBox(
                            key: const Key('lifeos_sliding_dock_pill'),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(24),
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: isDark
                                    ? [
                                        c.primary.withValues(
                                          alpha: _isDragging ? 0.36 : 0.28,
                                        ),
                                        const Color(0xFF152C20).withValues(
                                          alpha: _isDragging ? 0.90 : 0.80,
                                        ),
                                      ]
                                    : [
                                        Colors.white.withValues(alpha: 0.96),
                                        c.primarySubtle.withValues(alpha: 0.88),
                                      ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: c.primary.withValues(
                                    alpha: _isDragging
                                        ? (isDark ? 0.34 : 0.18)
                                        : (isDark ? 0.22 : 0.11),
                                  ),
                                  blurRadius: _isDragging ? 16 : 11,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: CustomPaint(
                              foregroundPainter: LiquidGlassRimPainter(
                                borderRadius: 24,
                                isDark: isDark,
                                accentRimColor: c.primary,
                                strokeWidth: _isDragging ? 1.35 : 1.1,
                                intensity: _isDragging ? 1.42 : 1.18,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),

                  // 2. Symmetrical 4 Tab Targets (2 Left + Jewel Spacer + 2 Right)
                  Row(
                    children: [
                      _SlidingDockTabButton(
                        item: widget.items[0],
                        isSelected:
                            widget.selectedIndex == widget.items[0].branchIndex,
                        onTap: () {
                          _motion.selectionHaptic();
                          widget.onDestinationSelected(
                            widget.items[0].branchIndex,
                          );
                        },
                      ),
                      _SlidingDockTabButton(
                        item: widget.items[1],
                        isSelected:
                            widget.selectedIndex == widget.items[1].branchIndex,
                        onTap: () {
                          _motion.selectionHaptic();
                          widget.onDestinationSelected(
                            widget.items[1].branchIndex,
                          );
                        },
                      ),
                      SizedBox(width: widget.jewelSlotWidth),
                      _SlidingDockTabButton(
                        item: widget.items[2],
                        isSelected:
                            widget.selectedIndex == widget.items[2].branchIndex,
                        onTap: () {
                          _motion.selectionHaptic();
                          widget.onDestinationSelected(
                            widget.items[2].branchIndex,
                          );
                        },
                      ),
                      _SlidingDockTabButton(
                        item: widget.items[3],
                        isSelected:
                            widget.selectedIndex == widget.items[3].branchIndex,
                        onTap: () {
                          _motion.selectionHaptic();
                          widget.onDestinationSelected(
                            widget.items[3].branchIndex,
                          );
                        },
                      ),
                    ],
                  ),

                  // 3. Elevated Center `+` Jewel (sits optically above the sliding glass lens)
                  Align(
                    alignment: Alignment.center,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      child: widget.centerJewel,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SlidingDockTabButton extends StatelessWidget {
  final LiquidGlassDockItem item;
  final bool isSelected;
  final VoidCallback onTap;

  const _SlidingDockTabButton({
    required this.item,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final motion = LifeOsMotionScope.of(context);
    final color = isSelected ? c.primary : c.textSecondary;
    final stateDuration = motion.resolveDuration(LifeOsMotionTokens.standard);
    final microDuration = motion.resolveDuration(LifeOsMotionTokens.micro);

    return Expanded(
      child: Semantics(
        button: true,
        selected: isSelected,
        label: item.label,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(22),
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedSlide(
                      duration: stateDuration,
                      curve: LifeOsMotionTokens.standardCurve,
                      offset: motion.resolveOffset(
                        isSelected ? const Offset(0, -0.05) : Offset.zero,
                      ),
                      child: AnimatedScale(
                        duration: stateDuration,
                        curve: motion.isReducedMotion
                            ? LifeOsMotionTokens.standardCurve
                            : Curves.easeOutBack,
                        scale: motion.resolveScale(isSelected ? 1.08 : 1.0),
                        child: AnimatedOpacity(
                          duration: microDuration,
                          opacity: isSelected ? 1.0 : 0.80,
                          child: item.iconBuilder(context, isSelected, color),
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: AnimatedDefaultTextStyle(
                        duration: microDuration,
                        curve: LifeOsMotionTokens.standardCurve,
                        style: TextStyle(
                          fontSize: 11.2,
                          fontWeight: isSelected
                              ? FontWeight.w800
                              : FontWeight.w600,
                          color: color,
                        ),
                        child: Text(item.label, maxLines: 1),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
