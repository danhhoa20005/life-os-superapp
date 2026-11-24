import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:flutter/physics.dart';

/// Single source of truth for LifeOS Motion Design System v2.0:
/// Durations, curves, 6 calibrated physics springs, velocity handoff helpers,
/// rubber-band over-drag math, and stagger guardrails.
abstract final class LifeOsMotionTokens {
  // ── Duration Tokens ──────────────────────────────────────────────────────
  /// 0 ms — Replaces decorative motion when Remove Animations / Off is active.
  static const Duration instant = Duration.zero;

  /// 100 ms — Press-down response, focus highlight, and reduced-motion opacity crossfades.
  static const Duration feedbackFast = Duration(milliseconds: 100);

  /// 160 ms — Icon state swap, checkbox mark, status pill, and truthful counter crossfade.
  static const Duration micro = Duration(milliseconds: 160);

  /// 220 ms — Primary branch switch, segmented pill glide, small visibility toggle, toast entry.
  static const Duration standard = Duration(milliseconds: 220);

  /// 300 ms — Shared-axis parent/child screen transition, calendar period swap, filter fade-through.
  static const Duration medium = Duration(milliseconds: 300);

  /// 340 ms — Modal bottom sheet reveal, sliding dock capsule travel, major card expand.
  static const Duration panel = Duration(milliseconds: 340);

  /// 420 ms — Single authoritative confirmation mark or onboarding step transition.
  static const Duration expressive = Duration(milliseconds: 420);

  /// 520 ms maximum — Reserved strictly for rare, non-blocking milestone feedback.
  static const Duration longEmphasis = Duration(milliseconds: 520);

  // ── Exit / Reverse Durations (faster than enter so next action is never blocked) ──
  static const Duration exitFast = Duration(milliseconds: 140);
  static const Duration exitStandard = Duration(milliseconds: 180);

  // ── Easing Curves ────────────────────────────────────────────────────────
  /// Fast general entrance with smooth deceleration and zero overshoot.
  static const Curve standardCurve = Curves.easeOutCubic;

  /// Clean, non-blocking exit curve.
  static const Curve exitCurve = Curves.easeInCubic;

  /// Material 3 Emphasized curve for screen & panel transitions.
  static const Curve emphasizedCurve = Cubic(0.2, 0.0, 0.0, 1.0);

  /// Material 3 Emphasized decelerate for incoming elements.
  static const Curve emphasizedDecelerate = Cubic(0.05, 0.7, 0.1, 1.0);

  /// Material 3 Emphasized accelerate for outgoing elements.
  static const Curve emphasizedAccelerate = Cubic(0.3, 0.0, 0.8, 0.15);

  /// Controlled Apple Liquid Glass dock capsule curve (subtle settle, no prolonged bounce).
  static const Curve dockCapsuleCurve = Cubic(0.22, 1.04, 0.32, 1.0);

  // ── 6 Calibrated Physics Springs (true velocity-preserving interruption) ─
  /// 1. Crisp press & release spring (`m: 1, k: 600, c: 43`, zeta = 0.878, <0.3% overshoot).
  static const SpringDescription pressSpring = SpringDescription(
    mass: 1.0,
    stiffness: 600.0,
    damping: 43.0,
  );

  /// 2. Snappy UI control spring for segmented pills, tabs, switches (`m: 1, k: 500, c: 42.5`, zeta = 0.950).
  static const SpringDescription snappySpring = SpringDescription(
    mass: 1.0,
    stiffness: 500.0,
    damping: 42.5,
  );

  /// Backward-compatible alias for `snappySpring` / dock selection settling.
  static const SpringDescription selectionSpring = SpringDescription(
    mass: 1.0,
    stiffness: 430.0,
    damping: 37.0,
  );

  /// 3. Expressive bouncy spring for mascot hop, milestone pop & dock jewel (`m: 1, k: 380, c: 24`, zeta = 0.616).
  /// NEVER use on financial numbers or progress ratios.
  static const SpringDescription bouncySpring = SpringDescription(
    mass: 1.0,
    stiffness: 380.0,
    damping: 24.0,
  );

  /// 4. Critically-damped sheet/drawer detent snap spring (`m: 1, k: 340, c: 37`, zeta = 1.003, 0% overshoot).
  static const SpringDescription sheetSnapSpring = SpringDescription(
    mass: 1.0,
    stiffness: 340.0,
    damping: 37.0,
  );

  /// Backward-compatible alias for `panelSpring`.
  static const SpringDescription panelSpring = SpringDescription(
    mass: 1.0,
    stiffness: 320.0,
    damping: 34.0,
  );

  /// 5. 2D draggable card / swipe / fling settling spring (`m: 1, k: 260, c: 26`, zeta = 0.806).
  static const SpringDescription gestureThrowSpring = SpringDescription(
    mass: 1.0,
    stiffness: 260.0,
    damping: 26.0,
  );

  /// 6. Critically-damped chart & gauge morph spring (`m: 1, k: 240, c: 31`, zeta = 1.001, 0% overshoot).
  static const SpringDescription chartMorphSpring = SpringDescription(
    mass: 1.0,
    stiffness: 240.0,
    damping: 31.0,
  );

  // ── Coordinate-Aware Simulation Tolerances ───────────────────────────────
  /// Normalized `[0.0..1.0]` simulation tolerance.
  static const Tolerance springTolerance = Tolerance(
    distance: 0.001,
    velocity: 0.01,
  );

  /// Logical pixel-space simulation tolerance (2D drag offsets, sheet heights, drawer widths).
  static const Tolerance pixelSpringTolerance = Tolerance(
    distance: 0.5,
    velocity: 5.0,
  );

  // ── Physics & Velocity Utility Math ──────────────────────────────────────
  /// Computes exact damping ratio zeta = c / (2 * sqrt(m * k)).
  static double dampingRatioOf(SpringDescription spring) {
    final denom = 2.0 * math.sqrt(spring.mass * spring.stiffness);
    return denom <= 0 ? 1.0 : spring.damping / denom;
  }

  /// Clamps raw gesture fling velocity in logical pixels/second to safe bounds.
  static double clampVelocityPx(double rawPxPerSec, {double maxAbs = 5500.0}) {
    if (rawPxPerSec.isNaN || rawPxPerSec.isInfinite) return 0.0;
    return rawPxPerSec.clamp(-maxAbs, maxAbs);
  }

  /// Converts pixel velocity into normalized `[0..1]` units/second over `extentPx`.
  static double normalizeVelocity({
    required double velocityPxPerSec,
    required double extentPx,
    double maxUnitsPerSec = 18.0,
  }) {
    if (extentPx <= 1.0) return 0.0;
    final raw = clampVelocityPx(velocityPxPerSec) / extentPx;
    return raw.clamp(-maxUnitsPerSec, maxUnitsPerSec);
  }

  /// Hyperbolic rubber-band resistance (`smooth_sheets` / iOS scroll physics formula)
  /// when dragging past `min` or `max` bounds.
  static double rubberBandClamp(
    double value, {
    required double min,
    required double max,
    required double viewportExtent,
    double resistance = 0.55,
  }) {
    final d = math.max(1.0, viewportExtent * resistance);
    if (value < min) {
      final over = min - value;
      return min - (over * d) / (over + d);
    }
    if (value > max) {
      final over = value - max;
      return max + (over * d) / (over + d);
    }
    return value;
  }

  /// Projects position forward by [lookaheadSeconds] (`0.18s` default) using gesture velocity
  /// and selects the nearest detent in [detents].
  static double projectNearestDetent({
    required double current,
    required double velocityPerSec,
    required List<double> detents,
    double lookaheadSeconds = 0.18,
  }) {
    if (detents.isEmpty) return current;
    final projected = current + velocityPerSec * lookaheadSeconds;
    var best = detents.first;
    var bestDist = (best - projected).abs();
    for (var i = 1; i < detents.length; i++) {
      final dist = (detents[i] - projected).abs();
      if (dist < bestDist) {
        bestDist = dist;
        best = detents[i];
      }
    }
    return best;
  }

  // ── Geometry & Stagger Guardrails ────────────────────────────────────────
  static const double pressedScaleStandard = 0.98;
  static const double pressedScaleCompact = 0.97;
  static const double localEntranceOffsetPx = 8.0;
  static const double shellBranchSlideFraction = 0.024;
  static const Duration staggerStep = Duration(milliseconds: 30);
  static const int maxStaggeredItems = 5;
  static const Duration toastDedupeWindow = Duration(milliseconds: 1200);
}
