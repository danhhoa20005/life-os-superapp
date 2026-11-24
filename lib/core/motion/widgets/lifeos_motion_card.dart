import 'package:flutter/material.dart';

import '../../widgets/lifeos_design_system.dart';

/// Shared motion card wrapper that keeps [LifeOsSoftCard] / [LifeOsMintHeroCard]
/// as the 100% visual source of truth while adding:
/// - Tactile `LifeOsPressable` spring feedback when [onTap] is provided.
/// - Collision-safe, namespaced [Hero] support that automatically falls back to
///   a plain widget when Reduce Motion is enabled or [heroNamespace] is omitted.
class LifeOsMotionCard extends StatelessWidget {
  final String id;
  final String? heroNamespace;
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final bool mintHero;
  final Color? backgroundColor;
  final Color? borderColor;
  final String? semanticsLabel;

  const LifeOsMotionCard({
    super.key,
    required this.id,
    required this.child,
    this.heroNamespace,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius = 18,
    this.mintHero = false,
    this.backgroundColor,
    this.borderColor,
    this.semanticsLabel,
  });

  String? get resolvedHeroTag {
    final ns = heroNamespace?.trim();
    if (ns == null || ns.isEmpty || id.trim().isEmpty) return null;
    return 'lifeos_hero_${ns}_$id';
  }

  @override
  Widget build(BuildContext context) {
    final motion = LifeOsMotionScope.of(context);

    // Delegate visual styling strictly to LifeOsMintHeroCard / LifeOsSoftCard
    // without passing onTap inside so LifeOsPressable owns press physics cleanly.
    Widget cardSurface = mintHero
        ? LifeOsMintHeroCard(padding: padding, child: child)
        : LifeOsSoftCard(
            padding: padding,
            borderRadius: borderRadius,
            backgroundColor: backgroundColor,
            borderColor: borderColor,
            child: child,
          );

    if (onTap != null) {
      cardSurface = LifeOsPressable(
        onPressed: onTap,
        semanticsLabel: semanticsLabel,
        pressedScale: LifeOsMotionTokens.pressedScaleStandard,
        child: cardSurface,
      );
    }

    final tag = resolvedHeroTag;
    if (tag != null && !motion.isReducedMotion) {
      cardSurface = Hero(
        tag: tag,
        flightShuttleBuilder:
            (
              flightContext,
              animation,
              flightDirection,
              fromHeroContext,
              toHeroContext,
            ) {
              return Material(
                type: MaterialType.transparency,
                child: toHeroContext.widget,
              );
            },
        child: cardSurface,
      );
    }

    return cardSurface;
  }
}
