import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../lifeos_motion_scope.dart';
import '../lifeos_motion_tokens.dart';

enum LifeOsSharedAxis { horizontal, vertical, scaled }

/// Material Motion route & container transition builders (`animations ^2.2.0`).
///
/// Honors `StatefulShellRoute.indexedStack` for root shell tabs, uses official Material
/// Motion (`SharedAxisTransition`, `FadeThroughTransition`, `FadeScaleTransition`,
/// `OpenContainer`) for detail/modal flows, and automatically degrades under Reduce Motion.
abstract final class LifeOsPageTransitions {
  static SharedAxisTransitionType _mapAxis(LifeOsSharedAxis axis) {
    return switch (axis) {
      LifeOsSharedAxis.horizontal => SharedAxisTransitionType.horizontal,
      LifeOsSharedAxis.vertical => SharedAxisTransitionType.vertical,
      LifeOsSharedAxis.scaled => SharedAxisTransitionType.scaled,
    };
  }

  static CustomTransitionPage<T> sharedAxis<T>({
    required GoRouterState state,
    required Widget child,
    LifeOsSharedAxis axis = LifeOsSharedAxis.horizontal,
    String? name,
  }) {
    return CustomTransitionPage<T>(
      key: state.pageKey,
      name: name ?? state.name ?? state.path,
      transitionDuration: LifeOsMotionTokens.medium,
      reverseTransitionDuration: LifeOsMotionTokens.exitStandard,
      child: child,
      transitionsBuilder: (context, animation, secondaryAnimation, pageChild) {
        final motion = LifeOsMotionScope.of(context);
        if (motion.isMotionOff) {
          return pageChild;
        }
        if (motion.isReducedMotion) {
          return FadeTransition(opacity: animation, child: pageChild);
        }
        return SharedAxisTransition(
          animation: animation,
          secondaryAnimation: secondaryAnimation,
          transitionType: _mapAxis(axis),
          fillColor: Colors.transparent,
          child: pageChild,
        );
      },
    );
  }

  static CustomTransitionPage<T> fadeThrough<T>({
    required GoRouterState state,
    required Widget child,
    String? name,
  }) {
    return CustomTransitionPage<T>(
      key: state.pageKey,
      name: name ?? state.name ?? state.path,
      transitionDuration: LifeOsMotionTokens.standard,
      reverseTransitionDuration: LifeOsMotionTokens.exitFast,
      child: child,
      transitionsBuilder: (context, animation, secondaryAnimation, pageChild) {
        final motion = LifeOsMotionScope.of(context);
        if (motion.isMotionOff) {
          return pageChild;
        }
        if (motion.isReducedMotion) {
          return FadeTransition(opacity: animation, child: pageChild);
        }
        return FadeThroughTransition(
          animation: animation,
          secondaryAnimation: secondaryAnimation,
          fillColor: Colors.transparent,
          child: pageChild,
        );
      },
    );
  }

  static CustomTransitionPage<T> fadeScale<T>({
    required GoRouterState state,
    required Widget child,
    String? name,
  }) {
    return CustomTransitionPage<T>(
      key: state.pageKey,
      name: name ?? state.name ?? state.path,
      transitionDuration: LifeOsMotionTokens.standard,
      reverseTransitionDuration: LifeOsMotionTokens.exitFast,
      child: child,
      transitionsBuilder: (context, animation, _, pageChild) {
        final motion = LifeOsMotionScope.of(context);
        if (motion.isMotionOff) {
          return pageChild;
        }
        if (motion.isReducedMotion) {
          return FadeTransition(opacity: animation, child: pageChild);
        }
        return FadeScaleTransition(animation: animation, child: pageChild);
      },
    );
  }
}

/// Accessible Material Motion `OpenContainer` wrapper that morphs a card/FAB into a detail
/// view in Standard mode, and falls back to a clean fade/instant route under Reduce Motion.
class LifeOsOpenContainer<T extends Object?> extends StatelessWidget {
  final CloseContainerBuilder closedBuilder;
  final OpenContainerBuilder<T> openBuilder;
  final ShapeBorder closedShape;
  final Color? closedColor;
  final Color? openColor;
  final double closedElevation;
  final ClosedCallback<T?>? onClosed;

  const LifeOsOpenContainer({
    super.key,
    required this.closedBuilder,
    required this.openBuilder,
    this.closedShape = const RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(18)),
    ),
    this.closedColor,
    this.openColor,
    this.closedElevation = 0.0,
    this.onClosed,
  });

  @override
  Widget build(BuildContext context) {
    final motion = LifeOsMotionScope.of(context);
    final surface = Theme.of(context).colorScheme.surface;
    final resolvedClosed = closedColor ?? surface;
    final resolvedOpen = openColor ?? surface;

    if (motion.isReducedMotion) {
      return Material(
        color: resolvedClosed,
        elevation: closedElevation,
        shape: closedShape,
        clipBehavior: Clip.antiAlias,
        child: Builder(
          builder: (ctx) => closedBuilder(ctx, () async {
            final res = await Navigator.of(ctx).push<T>(
              PageRouteBuilder<T>(
                transitionDuration: motion.resolveDuration(
                  LifeOsMotionTokens.feedbackFast,
                ),
                reverseTransitionDuration: motion.resolveDuration(
                  LifeOsMotionTokens.feedbackFast,
                ),
                pageBuilder: (routeCtx, anim, _) => FadeTransition(
                  opacity: anim,
                  child: Builder(
                    builder: (innerCtx) => openBuilder(
                      innerCtx,
                      ({T? returnValue}) =>
                          Navigator.of(innerCtx).pop<T>(returnValue),
                    ),
                  ),
                ),
              ),
            );
            onClosed?.call(res);
          }),
        ),
      );
    }

    return OpenContainer<T>(
      transitionDuration: LifeOsMotionTokens.medium,
      transitionType: ContainerTransitionType.fadeThrough,
      closedShape: closedShape,
      closedElevation: closedElevation,
      openElevation: 0.0,
      closedColor: resolvedClosed,
      openColor: resolvedOpen,
      middleColor: resolvedClosed,
      onClosed: onClosed,
      closedBuilder: closedBuilder,
      openBuilder: openBuilder,
    );
  }
}

/// Inline content switcher powered by Material Motion `PageTransitionSwitcher`.
class LifeOsMaterialContentSwitcher extends StatelessWidget {
  final Widget child;
  final bool reverse;
  final LifeOsSharedAxis? sharedAxis;
  final Duration duration;

  const LifeOsMaterialContentSwitcher({
    super.key,
    required this.child,
    this.reverse = false,
    this.sharedAxis,
    this.duration = LifeOsMotionTokens.standard,
  });

  @override
  Widget build(BuildContext context) {
    final motion = LifeOsMotionScope.of(context);
    final dur = motion.resolveDuration(duration);
    if (dur == Duration.zero) {
      return child;
    }

    return PageTransitionSwitcher(
      duration: dur,
      reverse: reverse,
      transitionBuilder: (widgetChild, primary, secondary) {
        if (motion.isReducedMotion) {
          return FadeTransition(opacity: primary, child: widgetChild);
        }
        if (sharedAxis != null) {
          return SharedAxisTransition(
            animation: primary,
            secondaryAnimation: secondary,
            transitionType: switch (sharedAxis!) {
              LifeOsSharedAxis.horizontal =>
                SharedAxisTransitionType.horizontal,
              LifeOsSharedAxis.vertical => SharedAxisTransitionType.vertical,
              LifeOsSharedAxis.scaled => SharedAxisTransitionType.scaled,
            },
            fillColor: Colors.transparent,
            child: widgetChild,
          );
        }
        return FadeThroughTransition(
          animation: primary,
          secondaryAnimation: secondary,
          fillColor: Colors.transparent,
          child: widgetChild,
        );
      },
      child: child,
    );
  }
}
