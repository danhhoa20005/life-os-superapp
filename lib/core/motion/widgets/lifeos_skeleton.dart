import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../lifeos_motion_scope.dart';

/// Bounded, accessible skeleton placeholder for initial loading states.
///
/// Performance & Accessibility guarantees (`PERF-02`, `PERF-03`, `A11Y-01..03`):
/// - Automatically stops its ticker when `TickerMode` is disabled (offstage tabs) or Reduce Motion is active.
/// - Renders a clean static placeholder under Reduce Motion.
/// - Exposes localized screen-reader status via [semanticsLabel].
class LifeOsSkeletonBox extends StatefulWidget {
  final double? width;
  final double height;
  final double borderRadius;
  final String? semanticsLabel;

  const LifeOsSkeletonBox({
    super.key,
    this.width,
    required this.height,
    this.borderRadius = 12,
    this.semanticsLabel,
  });

  @override
  State<LifeOsSkeletonBox> createState() => _LifeOsSkeletonBoxState();
}

class _LifeOsSkeletonBoxState extends State<LifeOsSkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncTickerState();
  }

  void _syncTickerState() {
    final motion = LifeOsMotionScope.of(context);
    final tickersEnabled = TickerMode.valuesOf(context).enabled;
    final shouldAnimate = tickersEnabled && !motion.isReducedMotion;
    if (shouldAnimate && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!shouldAnimate && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0.35;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _syncTickerState();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = TammySemanticColors.of(context);
    final baseColor = isDark
        ? const Color(0xFF232C36)
        : c.surfaceRaised.withValues(alpha: 0.92);
    final highlightColor = isDark
        ? const Color(0xFF2F3B48)
        : const Color(0xFFE2E8F0);

    final box = AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final color =
            Color.lerp(baseColor, highlightColor, _controller.value) ??
            baseColor;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(widget.borderRadius),
          ),
        );
      },
    );

    if (widget.semanticsLabel != null) {
      return Semantics(label: widget.semanticsLabel, child: box);
    }
    return ExcludeSemantics(child: box);
  }
}

/// Stale-while-revalidate loading wrapper (`Section 6.1 #6` & `Section 14`):
/// Shows [skeleton] ONLY when [hasData] is false and [isLoading] is true —
/// NEVER hiding or flashing over already-cached financial or dashboard data during background sync.
class LifeOsStaleWhileRevalidate extends StatelessWidget {
  final bool isLoading;
  final bool hasData;
  final Widget skeleton;
  final Widget child;

  const LifeOsStaleWhileRevalidate({
    super.key,
    required this.isLoading,
    required this.hasData,
    required this.skeleton,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (!hasData && isLoading) {
      return Semantics(
        container: true,
        label: 'Đang tải dữ liệu',
        child: skeleton,
      );
    }
    return child;
  }
}
