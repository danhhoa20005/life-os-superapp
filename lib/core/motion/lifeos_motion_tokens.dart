import 'package:flutter/animation.dart';
import 'package:flutter/physics.dart';

/// Single source of truth for LifeOS motion durations, curves, springs, and spatial bounds.
///
/// Designed around Material 3 Expressive & Apple HIG tactile clarity:
/// calm for routine activity, expressive for decisive actions, and restrained for financial data.
abstract final class LifeOsMotionTokens {
  // ── Duration Tokens ──────────────────────────────────────────────────────
  /// 0 ms — Replaces purely decorative motion when Reduce Motion / Remove Animations is active.
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

  /// Controlled Apple Liquid Glass dock capsule curve (subtle settle, no prolonged bounce).
  static const Curve dockCapsuleCurve = Cubic(0.22, 1.04, 0.32, 1.0);

  // ── Physics Springs (true velocity-preserving interruption) ──────────────
  /// Crisp press & release spring (`mass: 1, stiffness: 600, damping: 43` — near-critically damped).
  static const SpringDescription pressSpring = SpringDescription(
    mass: 1.0,
    stiffness: 600.0,
    damping: 43.0,
  );

  /// Dock capsule & selected chip settling spring (`mass: 1, stiffness: 430, damping: 37`).
  static const SpringDescription selectionSpring = SpringDescription(
    mass: 1.0,
    stiffness: 430.0,
    damping: 37.0,
  );

  /// Larger panel / expandable surface settling spring (`mass: 1, stiffness: 320, damping: 34`).
  static const SpringDescription panelSpring = SpringDescription(
    mass: 1.0,
    stiffness: 320.0,
    damping: 34.0,
  );

  /// Deterministic simulation tolerance so spring controllers settle cleanly in widget tests
  /// without keeping idle tickers alive.
  static const Tolerance springTolerance = Tolerance(
    distance: 0.001,
    velocity: 0.01,
  );

  // ── Geometry & Stagger Guardrails ────────────────────────────────────────
  /// Pressed visual scale for cards and full-width buttons (`0.97–0.985` contract).
  static const double pressedScaleStandard = 0.98;

  /// Pressed visual scale for compact icon pills and floating jewels.
  static const double pressedScaleCompact = 0.97;

  /// Local list/card entrance translation in logical pixels (`4–12 px` contract).
  static const double localEntranceOffsetPx = 8.0;

  /// Subtle fractional shell glide on primary tab change (~8.5 px on a 360 px screen).
  static const double shellBranchSlideFraction = 0.024;

  /// Delay between consecutive staggered items (`25–45 ms` contract).
  static const Duration staggerStep = Duration(milliseconds: 30);

  /// Maximum items allowed to stagger concurrently (`4–6 items` contract; never stagger long lists).
  static const int maxStaggeredItems = 5;

  /// Foreground toast deduplication window so identical burst events do not replay animations.
  static const Duration toastDedupeWindow = Duration(milliseconds: 1200);
}
