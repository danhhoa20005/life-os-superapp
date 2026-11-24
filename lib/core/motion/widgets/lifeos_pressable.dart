import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../lifeos_motion_preferences.dart';
import '../lifeos_motion_scope.dart';
import '../lifeos_motion_tokens.dart';

enum LifeOsPressHaptic { none, selection, light, medium }

/// Tactile physics-driven press wrapper (`SpringSimulation` with `pressSpring`).
///
/// Guarantees:
/// - Outer interactive hit target NEVER shrinks when scaling visual child.
/// - Safe across `onTapCancel`, rapid repeated taps, mid-flight reversal, disabled state, and `dispose`.
/// - Honors Reduce Motion (`LifeOsMotionScope`) by replacing scale movement with a short opacity highlight.
class LifeOsPressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final bool enabled;
  final String? semanticsLabel;
  final bool? semanticsSelected;
  final double pressedScale;
  final BorderRadius? borderRadius;
  final LifeOsPressHaptic haptic;
  final HitTestBehavior behavior;

  /// When `true`, uses raw pointer down/up/cancel listeners without entering the
  /// gesture arena — ideal for wrapping widgets that already own an `InkWell` or `FilledButton`.
  final bool passthroughPointerOnly;

  const LifeOsPressable({
    super.key,
    required this.child,
    this.onPressed,
    this.onLongPress,
    this.enabled = true,
    this.semanticsLabel,
    this.semanticsSelected,
    this.pressedScale = LifeOsMotionTokens.pressedScaleStandard,
    this.borderRadius,
    this.haptic = LifeOsPressHaptic.selection,
    this.behavior = HitTestBehavior.opaque,
    this.passthroughPointerOnly = false,
  });

  @override
  State<LifeOsPressable> createState() => _LifeOsPressableState();
}

class _LifeOsPressableState extends State<LifeOsPressable>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  LifeOsMotionPreferences _cachedMotion = const LifeOsMotionPreferences();
  bool _tickersEnabled = true;
  bool _isDeactivated = false;
  bool _isPressed = false;

  bool get _isInteractive =>
      widget.enabled &&
      (widget.passthroughPointerOnly ||
          widget.onPressed != null ||
          widget.onLongPress != null);

  @override
  void initState() {
    super.initState();
    // 0.0 = resting (scale 1.0), 1.0 = pressed (scale widget.pressedScale)
    _controller = AnimationController.unbounded(vsync: this, value: 0.0);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _cachedMotion = LifeOsMotionScope.of(context);
    _tickersEnabled = TickerMode.valuesOf(context).enabled;
  }

  @override
  void activate() {
    super.activate();
    _isDeactivated = false;
  }

  @override
  void deactivate() {
    _isDeactivated = true;
    _controller.stop();
    super.deactivate();
  }

  @override
  void didUpdateWidget(covariant LifeOsPressable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isInteractive && (_isPressed || _controller.value != 0.0)) {
      _isPressed = false;
      _animatePressTo(0.0);
    }
  }

  void _animatePressTo(double target) {
    if (!mounted || _isDeactivated) return;
    if (!_tickersEnabled || _cachedMotion.isMotionOff) {
      _controller.stop();
      _controller.value = target;
      return;
    }
    if (_cachedMotion.isReducedMotion) {
      _controller.animateTo(
        target,
        duration: LifeOsMotionTokens.feedbackFast,
        curve: Curves.easeOut,
      );
      return;
    }
    final simulation = SpringSimulation(
      LifeOsMotionTokens.pressSpring,
      _controller.value,
      target,
      _controller.velocity,
      tolerance: LifeOsMotionTokens.springTolerance,
    );
    _controller.animateWith(simulation);
  }

  void _handleTapDown(TapDownDetails _) {
    if (!_isInteractive || _isDeactivated) return;
    _isPressed = true;
    _animatePressTo(1.0);
  }

  void _handleTapUp(TapUpDetails _) {
    if (!_isInteractive || _isDeactivated) return;
    _isPressed = false;
    _animatePressTo(0.0);
  }

  void _handleTapCancel() {
    if (_isDeactivated || (!_isPressed && _controller.value == 0.0)) return;
    _isPressed = false;
    _animatePressTo(0.0);
  }

  void _handleTap() {
    if (!_isInteractive || _isDeactivated) return;
    switch (widget.haptic) {
      case LifeOsPressHaptic.none:
        break;
      case LifeOsPressHaptic.selection:
        _cachedMotion.selectionHaptic();
      case LifeOsPressHaptic.light:
        _cachedMotion.lightHaptic();
      case LifeOsPressHaptic.medium:
        _cachedMotion.mediumHaptic();
    }
    widget.onPressed?.call();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final motion = LifeOsMotionScope.of(context);
    final clampedTargetScale = widget.pressedScale.clamp(0.94, 1.0);

    Widget visual = AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final t = _controller.value.clamp(0.0, 1.2);
        if (t == 0.0) return child!;
        final opacity = (1.0 - (0.10 * t.clamp(0.0, 1.0))).clamp(0.85, 1.0);
        if (motion.isReducedMotion) {
          return Opacity(opacity: opacity, child: child);
        }
        final scale = 1.0 - ((1.0 - clampedTargetScale) * t);
        return Transform.scale(
          scale: scale,
          alignment: Alignment.center,
          child: Opacity(opacity: opacity, child: child),
        );
      },
    );

    if (widget.passthroughPointerOnly) {
      visual = Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _isInteractive
            ? (_) {
                if (_isDeactivated) return;
                _isPressed = true;
                _animatePressTo(1.0);
              }
            : null,
        onPointerUp: _isInteractive
            ? (_) {
                if (_isDeactivated) return;
                _isPressed = false;
                _animatePressTo(0.0);
              }
            : null,
        onPointerCancel: _isInteractive ? (_) => _handleTapCancel() : null,
        child: visual,
      );
    } else {
      // GestureDetector sits OUTSIDE Transform.scale so the interactive hit area never shrinks.
      visual = GestureDetector(
        behavior: widget.behavior,
        onTapDown: _isInteractive ? _handleTapDown : null,
        onTapUp: _isInteractive ? _handleTapUp : null,
        onTapCancel: _isInteractive ? _handleTapCancel : null,
        onTap: _isInteractive && widget.onPressed != null ? _handleTap : null,
        onLongPress: _isInteractive ? widget.onLongPress : null,
        child: visual,
      );
    }

    if (widget.semanticsLabel != null || widget.semanticsSelected != null) {
      return Semantics(
        button: widget.onPressed != null,
        enabled: _isInteractive,
        selected: widget.semanticsSelected,
        label: widget.semanticsLabel,
        child: visual,
      );
    }

    return visual;
  }
}
