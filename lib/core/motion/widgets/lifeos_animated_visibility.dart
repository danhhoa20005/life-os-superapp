import 'package:flutter/widgets.dart';

import '../lifeos_motion_scope.dart';
import '../lifeos_motion_tokens.dart';

/// Smoothly reveals or collapses [child] without layout jumps while guaranteeing
/// that hidden content never intercepts pointers or pollutes assistive semantics.
class LifeOsAnimatedVisibility extends StatelessWidget {
  final bool visible;
  final Widget child;
  final bool maintainState;
  final Duration duration;
  final AlignmentGeometry alignment;
  final Axis axis;

  const LifeOsAnimatedVisibility({
    super.key,
    required this.visible,
    required this.child,
    this.maintainState = false,
    this.duration = LifeOsMotionTokens.standard,
    this.alignment = Alignment.topCenter,
    this.axis = Axis.vertical,
  });

  @override
  Widget build(BuildContext context) {
    final motion = LifeOsMotionScope.of(context);
    final resolvedDuration = motion.resolveDuration(duration);

    if (!maintainState && !visible && resolvedDuration == Duration.zero) {
      return const SizedBox.shrink();
    }

    final effectiveChild = visible
        ? child
        : (maintainState
              ? Offstage(offstage: true, child: child)
              : const SizedBox.shrink());

    if (motion.isReducedMotion) {
      if (!visible && !maintainState) {
        return const SizedBox.shrink();
      }
      return IgnorePointer(
        ignoring: !visible,
        child: ExcludeSemantics(
          excluding: !visible,
          child: AnimatedOpacity(
            duration: resolvedDuration,
            curve: Curves.linear,
            opacity: visible ? 1.0 : 0.0,
            child: effectiveChild,
          ),
        ),
      );
    }

    return IgnorePointer(
      ignoring: !visible,
      child: ExcludeSemantics(
        excluding: !visible,
        child: AnimatedSize(
          duration: resolvedDuration,
          curve: LifeOsMotionTokens.standardCurve,
          alignment: alignment,
          child: AnimatedOpacity(
            duration: resolvedDuration,
            curve: visible
                ? LifeOsMotionTokens.standardCurve
                : LifeOsMotionTokens.exitCurve,
            opacity: visible ? 1.0 : 0.0,
            child: effectiveChild,
          ),
        ),
      ),
    );
  }
}
