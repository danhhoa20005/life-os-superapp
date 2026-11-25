import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../lifeos_motion_preferences.dart';
import '../lifeos_motion_scope.dart';
import '../lifeos_motion_tokens.dart';

/// 1D velocity-preserving Spring Controller (`flutter_physics` architectural port).
///
/// Preserves C0 position and C1 velocity continuity across mid-flight retargeting,
/// finger catch (`stop()`), fling handoff (`animateTo(..., velocity: v)`),
/// offstage `TickerMode(enabled: false)`, and OS Reduce Motion.
class LifeOsSpringController extends ChangeNotifier {
  final AnimationController _ctrl;
  SpringDescription spring;
  Tolerance tolerance;

  LifeOsSpringController({
    required TickerProvider vsync,
    double initialValue = 0.0,
    this.spring = LifeOsMotionTokens.snappySpring,
    this.tolerance = LifeOsMotionTokens.springTolerance,
  }) : _ctrl = AnimationController.unbounded(
         vsync: vsync,
         value: initialValue,
       ) {
    _ctrl.addListener(notifyListeners);
  }

  double get value => _ctrl.value;
  double get velocity => _ctrl.velocity;
  bool get isAnimating => _ctrl.isAnimating;
  ValueListenable<double> get listenable => _ctrl;

  /// Immediately sets position and halts active simulation (e.g. during finger drag).
  void jumpTo(double newValue) {
    _ctrl.stop(canceled: false);
    if (_ctrl.value != newValue) {
      _ctrl.value = newValue;
    }
  }

  void stop() => _ctrl.stop(canceled: false);

  /// Retargets smoothly from current `[value, velocity]` (or explicit gesture [velocity])
  /// to [target] while respecting [motion] and [tickersEnabled].
  TickerFuture animateTo(
    double target, {
    double? velocity,
    SpringDescription? springOverride,
    LifeOsMotionPreferences? motion,
    bool tickersEnabled = true,
    double timeDilationFactor = 1.0,
  }) {
    if (!tickersEnabled || (motion?.isMotionOff ?? false)) {
      jumpTo(target);
      return TickerFuture.complete();
    }

    if (motion?.isReducedMotion ?? false) {
      final baseMs = LifeOsMotionTokens.feedbackFast.inMilliseconds;
      final scaledMs = (baseMs / timeDilationFactor.clamp(0.1, 4.0)).round();
      return _ctrl.animateTo(
        target,
        duration: Duration(milliseconds: scaledMs),
        curve: Curves.easeOut,
      );
    }

    final baseSpring = springOverride ?? spring;
    // Scale stiffness by speed^2 and damping by speed so slow-mo (e.g. 0.25x) preserves exact damping ratio zeta!
    final speed = timeDilationFactor.clamp(0.15, 3.0);
    final effectiveSpring = speed == 1.0
        ? baseSpring
        : SpringDescription(
            mass: baseSpring.mass,
            stiffness: baseSpring.stiffness * speed * speed,
            damping: baseSpring.damping * speed,
          );

    final v0 = velocity ?? _ctrl.velocity;
    if ((_ctrl.value - target).abs() <= tolerance.distance &&
        v0.abs() <= tolerance.velocity) {
      jumpTo(target);
      return TickerFuture.complete();
    }

    final sim = SpringSimulation(
      effectiveSpring,
      _ctrl.value,
      target,
      v0,
      tolerance: tolerance,
    );
    return _ctrl.animateWith(sim);
  }

  @override
  void dispose() {
    _ctrl.removeListener(notifyListeners);
    _ctrl.dispose();
    super.dispose();
  }
}

/// 2D velocity-preserving Spring Controller driving independent X/Y `SpringSimulation`s
/// for free-throw cards, magnetic corner snapping, and 2D gesture tracking.
class LifeOsSpring2DController extends ChangeNotifier {
  late final AnimationController _xCtrl;
  late final AnimationController _yCtrl;
  SpringDescription spring;
  Tolerance tolerance;

  LifeOsSpring2DController({
    required TickerProvider vsync,
    Offset initialOffset = Offset.zero,
    this.spring = LifeOsMotionTokens.gestureThrowSpring,
    this.tolerance = LifeOsMotionTokens.pixelSpringTolerance,
  }) {
    _xCtrl = AnimationController.unbounded(
      vsync: vsync,
      value: initialOffset.dx,
    )..addListener(notifyListeners);
    _yCtrl = AnimationController.unbounded(
      vsync: vsync,
      value: initialOffset.dy,
    )..addListener(notifyListeners);
  }

  Offset get value => Offset(_xCtrl.value, _yCtrl.value);
  Offset get velocity => Offset(_xCtrl.velocity, _yCtrl.velocity);
  bool get isAnimating => _xCtrl.isAnimating || _yCtrl.isAnimating;

  void jumpTo(Offset offset) {
    _xCtrl.stop(canceled: false);
    _yCtrl.stop(canceled: false);
    _xCtrl.value = offset.dx;
    _yCtrl.value = offset.dy;
  }

  void addDelta(Offset delta) {
    jumpTo(value + delta);
  }

  void stop() {
    _xCtrl.stop(canceled: false);
    _yCtrl.stop(canceled: false);
  }

  void animateTo(
    Offset target, {
    Offset? velocityPxPerSec,
    SpringDescription? springOverride,
    LifeOsMotionPreferences? motion,
    bool tickersEnabled = true,
    double timeDilationFactor = 1.0,
  }) {
    if (!tickersEnabled || (motion?.isMotionOff ?? false)) {
      jumpTo(target);
      return;
    }

    if (motion?.isReducedMotion ?? false) {
      final dur = Duration(
        milliseconds:
            (LifeOsMotionTokens.feedbackFast.inMilliseconds /
                    timeDilationFactor.clamp(0.1, 4.0))
                .round(),
      );
      _xCtrl.animateTo(target.dx, duration: dur, curve: Curves.easeOut);
      _yCtrl.animateTo(target.dy, duration: dur, curve: Curves.easeOut);
      return;
    }

    final base = springOverride ?? spring;
    final speed = timeDilationFactor.clamp(0.15, 3.0);
    final effectiveSpring = speed == 1.0
        ? base
        : SpringDescription(
            mass: base.mass,
            stiffness: base.stiffness * speed * speed,
            damping: base.damping * speed,
          );

    final vx = velocityPxPerSec != null
        ? LifeOsMotionTokens.clampVelocityPx(velocityPxPerSec.dx)
        : _xCtrl.velocity;
    final vy = velocityPxPerSec != null
        ? LifeOsMotionTokens.clampVelocityPx(velocityPxPerSec.dy)
        : _yCtrl.velocity;

    _xCtrl.animateWith(
      SpringSimulation(
        effectiveSpring,
        _xCtrl.value,
        target.dx,
        vx,
        tolerance: tolerance,
      ),
    );
    _yCtrl.animateWith(
      SpringSimulation(
        effectiveSpring,
        _yCtrl.value,
        target.dy,
        vy,
        tolerance: tolerance,
      ),
    );
  }

  @override
  void dispose() {
    _xCtrl.removeListener(notifyListeners);
    _yCtrl.removeListener(notifyListeners);
    _xCtrl.dispose();
    _yCtrl.dispose();
    super.dispose();
  }
}

/// Velocity-preserving implicitly physics-animated container (`flutter_physics` `AContainer` port).
/// Resizing or retargeting mid-flight preserves momentum instead of snapping velocity to 0.
class LifeOsPhysicsAnimatedBox extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;
  final Color color;
  final SpringDescription spring;
  final Widget? child;
  final AlignmentGeometry alignment;
  final EdgeInsetsGeometry? padding;

  const LifeOsPhysicsAnimatedBox({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 18.0,
    required this.color,
    this.spring = LifeOsMotionTokens.snappySpring,
    this.alignment = Alignment.center,
    this.padding,
    this.child,
  });

  @override
  State<LifeOsPhysicsAnimatedBox> createState() =>
      _LifeOsPhysicsAnimatedBoxState();
}

class _LifeOsPhysicsAnimatedBoxState extends State<LifeOsPhysicsAnimatedBox>
    with TickerProviderStateMixin {
  late final LifeOsSpringController _wCtrl;
  late final LifeOsSpringController _hCtrl;
  late final LifeOsSpringController _rCtrl;

  @override
  void initState() {
    super.initState();
    _wCtrl = LifeOsSpringController(
      vsync: this,
      initialValue: widget.width,
      spring: widget.spring,
      tolerance: LifeOsMotionTokens.pixelSpringTolerance,
    );
    _hCtrl = LifeOsSpringController(
      vsync: this,
      initialValue: widget.height,
      spring: widget.spring,
      tolerance: LifeOsMotionTokens.pixelSpringTolerance,
    );
    _rCtrl = LifeOsSpringController(
      vsync: this,
      initialValue: widget.borderRadius,
      spring: widget.spring,
      tolerance: LifeOsMotionTokens.pixelSpringTolerance,
    );
  }

  @override
  void didUpdateWidget(covariant LifeOsPhysicsAnimatedBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    final motion = LifeOsMotionScope.read(context);
    final tickers = TickerMode.valuesOf(context).enabled;
    _wCtrl.spring = widget.spring;
    _hCtrl.spring = widget.spring;
    _rCtrl.spring = widget.spring;
    if (oldWidget.width != widget.width) {
      _wCtrl.animateTo(widget.width, motion: motion, tickersEnabled: tickers);
    }
    if (oldWidget.height != widget.height) {
      _hCtrl.animateTo(widget.height, motion: motion, tickersEnabled: tickers);
    }
    if (oldWidget.borderRadius != widget.borderRadius) {
      _rCtrl.animateTo(
        widget.borderRadius,
        motion: motion,
        tickersEnabled: tickers,
      );
    }
  }

  @override
  void dispose() {
    _wCtrl.dispose();
    _hCtrl.dispose();
    _rCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final motion = LifeOsMotionScope.of(context);
    return AnimatedBuilder(
      animation: Listenable.merge([_wCtrl, _hCtrl, _rCtrl]),
      child: widget.child,
      builder: (context, child) {
        return AnimatedContainer(
          duration: motion.resolveDuration(LifeOsMotionTokens.micro),
          curve: Curves.easeOut,
          width: math.max(1.0, _wCtrl.value),
          height: math.max(1.0, _hCtrl.value),
          padding: widget.padding,
          alignment: widget.alignment,
          decoration: BoxDecoration(
            color: widget.color,
            borderRadius: BorderRadius.circular(math.max(0.0, _rCtrl.value)),
          ),
          child: child,
        );
      },
    );
  }
}

/// Custom perspective carousel (`gskinnerTeam/flutter_custom_carousel` architectural port)
/// exposing continuous `scrollRatio` in `[-1.0 .. +1.0]` around the active item.
typedef LifeOsCarouselEffectsBuilder =
    Widget Function(
      BuildContext context,
      int index,
      double scrollRatio,
      Widget child,
    );

class LifeOsPerspectiveCarousel extends StatefulWidget {
  final List<Widget> children;
  final double height;
  final double viewportFraction;
  final int initialIndex;
  final ValueChanged<int>? onSelectedIndexChanged;
  final LifeOsCarouselEffectsBuilder? effectsBuilder;

  const LifeOsPerspectiveCarousel({
    super.key,
    required this.children,
    this.height = 176,
    this.viewportFraction = 0.82,
    this.initialIndex = 0,
    this.onSelectedIndexChanged,
    this.effectsBuilder,
  });

  @override
  State<LifeOsPerspectiveCarousel> createState() =>
      _LifeOsPerspectiveCarouselState();
}

class _LifeOsPerspectiveCarouselState extends State<LifeOsPerspectiveCarousel> {
  late PageController _pageController;
  double _currentPage = 0.0;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialIndex.toDouble();
    _pageController = PageController(
      initialPage: widget.initialIndex,
      viewportFraction: widget.viewportFraction,
    )..addListener(_onScroll);
  }

  void _onScroll() {
    final p = _pageController.page;
    if (p != null && mounted) {
      setState(() => _currentPage = p);
    }
  }

  @override
  void dispose() {
    _pageController.removeListener(_onScroll);
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final motion = LifeOsMotionScope.of(context);
    return SizedBox(
      height: widget.height,
      child: PageView.builder(
        controller: _pageController,
        itemCount: widget.children.length,
        onPageChanged: widget.onSelectedIndexChanged,
        physics: const BouncingScrollPhysics(),
        itemBuilder: (context, index) {
          final rawRatio = (index - _currentPage).clamp(-1.5, 1.5);
          final child = widget.children[index];

          if (motion.isReducedMotion) {
            final opacity = (1.0 - rawRatio.abs() * 0.25).clamp(0.65, 1.0);
            return Opacity(
              opacity: opacity,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: child,
              ),
            );
          }

          if (widget.effectsBuilder != null) {
            return widget.effectsBuilder!(context, index, rawRatio, child);
          }

          final scale = (1.0 - rawRatio.abs() * 0.10).clamp(0.86, 1.0);
          final rotateY = rawRatio * -0.22;
          final translateY = rawRatio.abs() * 10.0;

          final matrix = Matrix4.identity()
            ..setEntry(3, 2, 0.0012)
            ..translateByDouble(0.0, translateY, 0.0, 1.0)
            ..rotateY(rotateY)
            ..scaleByDouble(scale, scale, 1.0, 1.0);

          return Transform(
            alignment: Alignment.center,
            transform: matrix,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: child,
            ),
          );
        },
      ),
    );
  }
}
