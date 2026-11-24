import 'dart:async';

import 'package:flutter/widgets.dart';

import '../lifeos_motion_scope.dart';
import '../lifeos_motion_tokens.dart';

/// Tracks stable domain IDs across stream/BLoC rebuilds so that:
/// 1. Existing rows NEVER replay entrance animations on stream updates or scroll rebuilds.
/// 2. Initial hydration staggers at most [LifeOsMotionTokens.maxStaggeredItems] items (or none if disabled).
/// 3. Bulk sync bursts (> [LifeOsMotionTokens.maxStaggeredItems] new IDs at once) skip mass stagger (`TX-05`).
class LifeOsStableListRegistry {
  final Set<String> _seenIds = <String>{};
  bool _hydrated = false;
  final bool animateInitialItems;

  LifeOsStableListRegistry({this.animateInitialItems = false});

  bool get isHydrated => _hydrated;

  /// Registers the current list of stable domain IDs and returns the subset of IDs
  /// (capped at [LifeOsMotionTokens.maxStaggeredItems]) that should play a one-shot entrance.
  Set<String> registerSnapshot(Iterable<String> currentIds) {
    final incoming = currentIds.toList(growable: false);
    if (!_hydrated) {
      _hydrated = true;
      _seenIds.addAll(incoming);
      if (!animateInitialItems) {
        return const <String>{};
      }
      return incoming.take(LifeOsMotionTokens.maxStaggeredItems).toSet();
    }

    final newlyAdded = <String>[];
    for (final id in incoming) {
      if (_seenIds.add(id)) {
        newlyAdded.add(id);
      }
    }

    // TX-05: If a large batch arrives simultaneously, skip mass entrance animation to avoid scroll jump/jank.
    if (newlyAdded.isEmpty ||
        newlyAdded.length > LifeOsMotionTokens.maxStaggeredItems) {
      return const <String>{};
    }
    return newlyAdded.toSet();
  }

  void reset() {
    _seenIds.clear();
    _hydrated = false;
  }
}

/// One-shot subtle fade + `8 px` vertical entrance for genuinely new list items or initial hero cards.
///
/// Safe under widget disposal, offstage `TickerMode(enabled: false)`, and Reduce Motion.
class LifeOsAnimatedItemEntrance extends StatefulWidget {
  final String itemId;
  final bool animateOnMount;
  final int staggerIndex;
  final Duration duration;
  final double offsetY;
  final Widget child;

  const LifeOsAnimatedItemEntrance({
    super.key,
    required this.itemId,
    required this.child,
    this.animateOnMount = true,
    this.staggerIndex = 0,
    this.duration = LifeOsMotionTokens.standard,
    this.offsetY = LifeOsMotionTokens.localEntranceOffsetPx,
  });

  @override
  State<LifeOsAnimatedItemEntrance> createState() =>
      _LifeOsAnimatedItemEntranceState();
}

class _LifeOsAnimatedItemEntranceState extends State<LifeOsAnimatedItemEntrance>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  Timer? _staggerTimer;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    if (!widget.animateOnMount) {
      _completed = true;
      return;
    }
    _controller = AnimationController(vsync: this, duration: widget.duration);
    WidgetsBinding.instance.addPostFrameCallback((_) => _startIfEligible());
  }

  void _startIfEligible() {
    if (!mounted || _completed) return;
    final ctrl = _controller;
    if (ctrl == null) return;

    final motion = LifeOsMotionScope.read(context);
    final tickersEnabled = TickerMode.valuesOf(context).enabled;
    if (!tickersEnabled || motion.isMotionOff) {
      _completed = true;
      ctrl.value = 1.0;
      if (mounted) setState(() {});
      return;
    }

    ctrl.duration = motion.resolveDuration(widget.duration);
    final clampedIndex = widget.staggerIndex.clamp(
      0,
      LifeOsMotionTokens.maxStaggeredItems - 1,
    );
    final delay = motion.isReducedMotion || clampedIndex == 0
        ? Duration.zero
        : LifeOsMotionTokens.staggerStep * clampedIndex;

    if (delay == Duration.zero) {
      ctrl.forward().whenComplete(() {
        if (mounted) {
          setState(() => _completed = true);
        }
      });
    } else {
      _staggerTimer = Timer(delay, () {
        if (!mounted || _completed) return;
        ctrl.forward().whenComplete(() {
          if (mounted) {
            setState(() => _completed = true);
          }
        });
      });
    }
  }

  @override
  void dispose() {
    _staggerTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _controller;
    if (_completed || ctrl == null) {
      return widget.child;
    }
    final motion = LifeOsMotionScope.of(context);
    final resolvedDy = motion.isReducedMotion ? 0.0 : widget.offsetY;

    return AnimatedBuilder(
      animation: ctrl,
      child: widget.child,
      builder: (context, child) {
        final curved = LifeOsMotionTokens.standardCurve.transform(
          ctrl.value.clamp(0.0, 1.0),
        );
        final dy = resolvedDy * (1.0 - curved);
        return Opacity(
          opacity: curved.clamp(0.0, 1.0),
          child: dy == 0.0
              ? child
              : Transform.translate(offset: Offset(0.0, dy), child: child),
        );
      },
    );
  }
}
