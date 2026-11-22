import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';

/// Centralized Nano Banana generated visual asset registry for Life OS (Tammy × Apple Design System).
abstract final class AppAssets {
  static const String logo = 'assets/images/logo_life_os.png';
  static const String splashHero = 'assets/images/splash_hero.png';
  static const String authHero = 'assets/images/auth_hero.png';
  static const String onboardingPrivacy = 'assets/images/onboarding_privacy.png';
  static const String dashboardBanner = 'assets/images/dashboard_banner.png';
  static const String financeIllustration = 'assets/images/finance_illustration.png';
  static const String familySplitIllustration = 'assets/images/family_split_illustration.png';
  static const String planningAssetsIllustration =
      'assets/images/planning_assets_illustration.png';
}

/// Brand squircle app logo widget with graceful fallback icon if rendered in headless unit tests.
class BrandLogoMark extends StatelessWidget {
  final double size;
  final double borderRadius;

  const BrandLogoMark({
    super.key,
    this.size = 44,
    this.borderRadius = 12,
  });

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return Semantics(
      label: 'Biểu trưng Life OS',
      image: true,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: c.primarySubtle,
          borderRadius: BorderRadius.circular(borderRadius),
          boxShadow: [
            BoxShadow(
              color: c.primary.withValues(alpha: 0.14),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Image.asset(
          AppAssets.logo,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Icon(
            Icons.shield_outlined,
            color: c.primary,
            size: size * 0.56,
          ),
        ),
      ),
    );
  }
}

/// Panoramic / Hero visual banner with rounded Tammy × Apple framing and accessible fallback.
class BrandVisualBanner extends StatelessWidget {
  final String assetPath;
  final double height;
  final String semanticLabel;
  final IconData fallbackIcon;
  final BoxFit fit;

  const BrandVisualBanner({
    super.key,
    required this.assetPath,
    this.height = 136,
    required this.semanticLabel,
    this.fallbackIcon = Icons.auto_awesome_rounded,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return Semantics(
      label: semanticLabel,
      image: true,
      child: Container(
        height: height,
        width: double.infinity,
        decoration: BoxDecoration(
          color: c.primarySubtle.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          border: Border.all(color: c.separator),
        ),
        clipBehavior: Clip.antiAlias,
        child: Image.asset(
          assetPath,
          height: height,
          width: double.infinity,
          fit: fit,
          errorBuilder: (_, __, ___) => Center(
            child: Icon(fallbackIcon, size: 42, color: c.primary),
          ),
        ),
      ),
    );
  }
}
