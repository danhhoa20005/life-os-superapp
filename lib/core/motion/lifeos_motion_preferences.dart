import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'lifeos_motion_tokens.dart';

/// User-selectable motion preference stored alongside LifeOS appearance settings.
///
/// Platform accessibility (`MediaQueryData.disableAnimations` on Android and
/// `AccessibilityFeatures.reduceMotion` on iOS/macOS) ALWAYS takes precedence
/// over decorative user preferences.
enum LifeOsMotionMode {
  /// Follow OS accessibility settings (`standard` unless OS requests reduced motion).
  system,

  /// Standard expressive motion (still yields to OS accessibility if OS reduces motion).
  standard,

  /// Minimize spatial movement to short opacity transitions while keeping state changes clear.
  reduced,

  /// Instant state swaps (`0 ms`) with zero decorative transitions.
  off,
}

extension LifeOsMotionModeLabel on LifeOsMotionMode {
  String get labelVi => switch (this) {
    LifeOsMotionMode.system => 'Theo hệ thống',
    LifeOsMotionMode.standard => 'Tiêu chuẩn',
    LifeOsMotionMode.reduced => 'Giảm chuyển động',
    LifeOsMotionMode.off => 'Tắt hiệu ứng',
  };
}

/// Resolved, immutable motion policy for a subtree.
@immutable
final class LifeOsMotionPreferences {
  final LifeOsMotionMode userMode;
  final bool platformDisableAnimations;
  final bool platformReduceMotion;
  final bool hapticsEnabled;

  const LifeOsMotionPreferences({
    this.userMode = LifeOsMotionMode.system,
    this.platformDisableAnimations = false,
    this.platformReduceMotion = false,
    this.hapticsEnabled = true,
  });

  /// Inspects both Android (`MediaQueryData.disableAnimations`) and iOS/macOS
  /// (`PlatformDispatcher.accessibilityFeatures.reduceMotion`) signals.
  factory LifeOsMotionPreferences.fromPlatform(
    BuildContext context, {
    LifeOsMotionMode userMode = LifeOsMotionMode.system,
    bool hapticsEnabled = true,
  }) {
    final mqDisable = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final viewFeatures = View.maybeOf(
      context,
    )?.platformDispatcher.accessibilityFeatures;
    final globalFeatures = PlatformDispatcher.instance.accessibilityFeatures;
    final osReduceMotion =
        (viewFeatures?.reduceMotion ?? false) ||
        (viewFeatures?.disableAnimations ?? false) ||
        globalFeatures.reduceMotion ||
        globalFeatures.disableAnimations;

    return LifeOsMotionPreferences(
      userMode: userMode,
      platformDisableAnimations: mqDisable,
      platformReduceMotion: osReduceMotion,
      hapticsEnabled: hapticsEnabled,
    );
  }

  /// Non-subscribing read variant safe inside `initState`, callbacks, and event handlers.
  factory LifeOsMotionPreferences.readFromPlatform(
    BuildContext context, {
    LifeOsMotionMode userMode = LifeOsMotionMode.system,
    bool hapticsEnabled = true,
  }) {
    final mqElement = context.getElementForInheritedWidgetOfExactType<MediaQuery>();
    final mqWidget = mqElement?.widget;
    final mqDisable = mqWidget is MediaQuery
        ? mqWidget.data.disableAnimations
        : false;
    final globalFeatures = PlatformDispatcher.instance.accessibilityFeatures;
    final osReduceMotion =
        globalFeatures.reduceMotion || globalFeatures.disableAnimations;

    return LifeOsMotionPreferences(
      userMode: userMode,
      platformDisableAnimations: mqDisable,
      platformReduceMotion: osReduceMotion,
      hapticsEnabled: hapticsEnabled,
    );
  }

  /// True whenever platform accessibility OR user preference requests reduced motion.
  /// Platform accessibility strictly overrides decorative `standard` preference.
  bool get isReducedMotion =>
      platformDisableAnimations ||
      platformReduceMotion ||
      userMode == LifeOsMotionMode.reduced ||
      userMode == LifeOsMotionMode.off;

  /// True when animations should complete in `0 ms` (Android Remove Animations or explicit `off`).
  bool get isMotionOff =>
      platformDisableAnimations || userMode == LifeOsMotionMode.off;

  /// Resolves a transition duration according to active accessibility & user preferences.
  Duration resolveDuration(Duration normal, {Duration? reduced}) {
    if (isMotionOff) return LifeOsMotionTokens.instant;
    if (isReducedMotion) return reduced ?? LifeOsMotionTokens.feedbackFast;
    return normal;
  }

  /// Suppresses overshoot curves when reduced motion is active.
  Curve resolveCurve(Curve normal, {Curve reduced = Curves.linear}) {
    if (isReducedMotion) return reduced;
    return normal;
  }

  /// Eliminates spatial translation when reduced motion is active.
  Offset resolveOffset(Offset normal) {
    return isReducedMotion ? Offset.zero : normal;
  }

  /// Eliminates scale bounce/shrink when reduced motion is active.
  double resolveScale(double normal) {
    return isReducedMotion ? 1.0 : normal;
  }

  void selectionHaptic() {
    if (!hapticsEnabled || isMotionOff) return;
    HapticFeedback.selectionClick();
  }

  void lightHaptic() {
    if (!hapticsEnabled || isMotionOff) return;
    HapticFeedback.lightImpact();
  }

  void mediumHaptic() {
    if (!hapticsEnabled || isMotionOff) return;
    HapticFeedback.mediumImpact();
  }

  LifeOsMotionPreferences copyWith({
    LifeOsMotionMode? userMode,
    bool? platformDisableAnimations,
    bool? platformReduceMotion,
    bool? hapticsEnabled,
  }) {
    return LifeOsMotionPreferences(
      userMode: userMode ?? this.userMode,
      platformDisableAnimations:
          platformDisableAnimations ?? this.platformDisableAnimations,
      platformReduceMotion: platformReduceMotion ?? this.platformReduceMotion,
      hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LifeOsMotionPreferences &&
          other.userMode == userMode &&
          other.platformDisableAnimations == platformDisableAnimations &&
          other.platformReduceMotion == platformReduceMotion &&
          other.hapticsEnabled == hapticsEnabled;

  @override
  int get hashCode => Object.hash(
    userMode,
    platformDisableAnimations,
    platformReduceMotion,
    hapticsEnabled,
  );
}
