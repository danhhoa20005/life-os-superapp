import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../lifeos_motion_scope.dart';
import '../lifeos_motion_tokens.dart';

enum LifeOsSharedAxis { horizontal, vertical }

/// Route transition factory for detail & wizard `GoRoute`s (`Section 5.1 & 5.2`).
///
/// Never replaces `StatefulShellRoute.indexedStack`. Automatically degrades to a short
/// opacity fade (or `0 ms` swap) when Reduce Motion is enabled.
abstract final class LifeOsPageTransitions {
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

        final primaryCurved = animation.drive(
          CurveTween(curve: LifeOsMotionTokens.emphasizedCurve),
        );

        final beginOffset = axis == LifeOsSharedAxis.horizontal
            ? const Offset(0.035, 0.0)
            : const Offset(0.0, 0.03);

        // Secondary outgoing nudge when another detail route pushes on top
        final secondaryCurved = secondaryAnimation.drive(
          CurveTween(curve: LifeOsMotionTokens.standardCurve),
        );
        final outgoingOffset = axis == LifeOsSharedAxis.horizontal
            ? Tween<Offset>(
                begin: Offset.zero,
                end: const Offset(-0.018, 0.0),
              ).animate(secondaryCurved)
            : Tween<Offset>(
                begin: Offset.zero,
                end: const Offset(0.0, -0.015),
              ).animate(secondaryCurved);

        return SlideTransition(
          position: outgoingOffset,
          child: FadeTransition(
            opacity: animation.drive(
              CurveTween(curve: const Interval(0.0, 0.75, curve: Curves.easeOut)),
            ),
            child: SlideTransition(
              position: Tween<Offset>(
                begin: beginOffset,
                end: Offset.zero,
              ).animate(primaryCurved),
              child: pageChild,
            ),
          ),
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
      transitionsBuilder: (context, animation, _, pageChild) {
        final motion = LifeOsMotionScope.of(context);
        if (motion.isMotionOff) {
          return pageChild;
        }
        final curved = animation.drive(
          CurveTween(curve: LifeOsMotionTokens.standardCurve),
        );
        if (motion.isReducedMotion) {
          return FadeTransition(opacity: curved, child: pageChild);
        }
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.985, end: 1.0).animate(curved),
            child: pageChild,
          ),
        );
      },
    );
  }
}
