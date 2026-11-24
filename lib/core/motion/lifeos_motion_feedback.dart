import 'package:flutter/material.dart';

import '../widgets/lifeos_design_system.dart';

/// Tracks authoritative one-shot feedback keys (e.g. transaction save/failure IDs or
/// BLoC sequence tokens) so success/error animations NEVER replay merely because a
/// widget rebuilt or a duplicate bank push arrived (`TX-01`, `TX-02`, `TX-03`).
class LifeOsOneShotEffectTracker {
  final int maxCapacity;
  final Set<String> _consumedKeys = <String>{};

  LifeOsOneShotEffectTracker({this.maxCapacity = 256});

  /// Returns `true` the first time [effectKey] is observed, and `false` for all
  /// subsequent rebuilds or duplicate deliveries.
  bool consumeOnce(String? effectKey) {
    if (effectKey == null || effectKey.trim().isEmpty) return false;
    if (_consumedKeys.contains(effectKey)) return false;
    if (_consumedKeys.length >= maxCapacity) {
      _consumedKeys.remove(_consumedKeys.first);
    }
    _consumedKeys.add(effectKey);
    return true;
  }

  bool hasConsumed(String effectKey) => _consumedKeys.contains(effectKey);
}

/// Truthful numeric/currency readout (`TX-04`, `Section 6.1 #3`, `Section 6.2`):
/// - Enforces `FontFeature.tabularFigures()` so digits never jitter horizontally.
/// - Uses a short, legible crossfade (`160 ms`) between authoritative formatted values.
/// - NEVER counts up from zero and NEVER displays interpolated intermediate fake amounts.
class LifeOsTruthfulNumericText extends StatelessWidget {
  final String formattedValue;
  final TextStyle style;
  final TextAlign? textAlign;
  final int? maxLines;
  final String? semanticsLabel;

  const LifeOsTruthfulNumericText({
    super.key,
    required this.formattedValue,
    required this.style,
    this.textAlign,
    this.maxLines = 1,
    this.semanticsLabel,
  });

  @override
  Widget build(BuildContext context) {
    final motion = LifeOsMotionScope.of(context);
    final duration = motion.resolveDuration(LifeOsMotionTokens.micro);
    final tabularStyle = style.copyWith(
      fontFeatures: <FontFeature>[
        ...?style.fontFeatures,
        const FontFeature.tabularFigures(),
      ],
    );

    final textWidget = Text(
      formattedValue,
      key: ValueKey<String>(formattedValue),
      style: tabularStyle,
      textAlign: textAlign,
      maxLines: maxLines,
      semanticsLabel: semanticsLabel,
    );

    if (duration == Duration.zero) {
      return textWidget;
    }

    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: LifeOsMotionTokens.standardCurve,
      switchOutCurve: LifeOsMotionTokens.exitCurve,
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: textWidget,
    );
  }
}

/// High-integrity financial / operational status pill (`Section 6.1 #2` & `Section 10 #5`):
/// Smoothly transitions icon + Vietnamese label + semantic tone only when the authoritative
/// domain status changes, pairing icon + text so status never relies on color or motion alone.
class LifeOsAnimatedStatusBadge extends StatelessWidget {
  final String statusKey;
  final String label;
  final IconData icon;
  final LifeOsAccentTone tone;

  const LifeOsAnimatedStatusBadge({
    super.key,
    required this.statusKey,
    required this.label,
    required this.icon,
    required this.tone,
  });

  @override
  Widget build(BuildContext context) {
    final motion = LifeOsMotionScope.of(context);
    final duration = motion.resolveDuration(LifeOsMotionTokens.micro);

    final badge = Semantics(
      container: true,
      label: 'Trạng thái: $label',
      child: LifeOsStatusPill(
        key: ValueKey<String>('status_pill_$statusKey'),
        label: label,
        icon: icon,
        tone: tone,
      ),
    );

    if (duration == Duration.zero) {
      return badge;
    }

    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: LifeOsMotionTokens.standardCurve,
      switchOutCurve: LifeOsMotionTokens.exitCurve,
      transitionBuilder: (child, animation) {
        if (motion.isReducedMotion) {
          return FadeTransition(opacity: animation, child: child);
        }
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1.0).animate(animation),
            child: child,
          ),
        );
      },
      child: badge,
    );
  }
}

/// Controlled progress bar (`Section 6.1 #5`):
/// Animates smoothly from actual previous ratio to actual next ratio while clamping ONLY
/// drawing bounds (`0.0..1.0`) — never altering underlying values or hiding overspending.
class LifeOsAnimatedProgressBar extends StatelessWidget {
  final double progressRatio;
  final Color color;
  final Color? trackColor;
  final double height;
  final double borderRadius;
  final String? semanticsLabel;
  final String? semanticsValue;

  const LifeOsAnimatedProgressBar({
    super.key,
    required this.progressRatio,
    required this.color,
    this.trackColor,
    this.height = 8.0,
    this.borderRadius = 99.0,
    this.semanticsLabel,
    this.semanticsValue,
  });

  @override
  Widget build(BuildContext context) {
    final motion = LifeOsMotionScope.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final resolvedTrack =
        trackColor ??
        (isDark
            ? Colors.white.withValues(alpha: 0.10)
            : const Color(0xFFE5EAEF));
    final clampedVisual = progressRatio.isNaN
        ? 0.0
        : progressRatio.clamp(0.0, 1.0);
    final duration = motion.resolveDuration(LifeOsMotionTokens.medium);

    return Semantics(
      label: semanticsLabel,
      value: semanticsValue ?? '${(progressRatio * 100).round()}%',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: DecoratedBox(
            decoration: BoxDecoration(color: resolvedTrack),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final targetWidth = constraints.maxWidth * clampedVisual;
                return Align(
                  alignment: Alignment.centerLeft,
                  child: AnimatedContainer(
                    duration: duration,
                    curve: LifeOsMotionTokens.emphasizedCurve,
                    width: targetWidth,
                    height: height,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(borderRadius),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
