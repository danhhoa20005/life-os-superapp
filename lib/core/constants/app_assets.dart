import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';

/// Centralized Nano Banana generated visual & 3D Glass Icon asset registry for Life OS (Tammy × Apple Design System).
abstract final class AppAssets {
  // Brand Logo & Hero Illustrations (Official LifeOS BrandKit 1.0)
  static const String logo = 'assets/images/logo_life_os.png';
  static const String brandLogoHorizontalPrimary =
      'assets/branding/logo_horizontal_primary.png';
  static const String brandLogoHorizontalWhite =
      'assets/branding/logo_horizontal_white.png';
  static const String brandLogoStackedPrimary =
      'assets/branding/logo_stacked_primary.png';
  static const String brandSymbolColor =
      'assets/branding/logo_symbol_color.png';
  static const String brandSymbolWhite =
      'assets/branding/logo_symbol_white.png';
  static const String brandAppIcon512 = 'assets/branding/app_icon_512.png';
  static const String splashHero = 'assets/images/splash_hero.png';
  static const String authHero = 'assets/images/auth_hero.png';
  static const String onboardingPrivacy = 'assets/images/onboarding_privacy.png';
  static const String dashboardBanner = 'assets/images/dashboard_banner.png';
  static const String financeIllustration = 'assets/images/finance_illustration.png';
  static const String familySplitIllustration = 'assets/images/family_split_illustration.png';
  static const String planningAssetsIllustration =
      'assets/images/planning_assets_illustration.png';

  // Nano Banana 3D Frosted Liquid Glass Navigation Icons (5 Tabs)
  static const String icNavToday = 'assets/icons/ic_nav_today.png';
  static const String icNavFinance = 'assets/icons/ic_nav_finance.png';
  static const String icNavCalendar = 'assets/icons/ic_nav_calendar.png';
  static const String icNavFamily = 'assets/icons/ic_nav_family.png';
  static const String icNavAssets = 'assets/icons/ic_nav_assets.png';

  // Nano Banana 3D Frosted Liquid Glass Category Icons
  static const String icCatFood = 'assets/icons/ic_cat_food.png';
  static const String icCatHousework = 'assets/icons/ic_cat_housework.png';
  static const String icCatHousing = 'assets/icons/ic_cat_housing.png';
  static const String icCatUtilities = 'assets/icons/ic_cat_utilities.png';
  static const String icCatShopping = 'assets/icons/ic_cat_shopping.png';
  static const String icCatIncome = 'assets/icons/ic_cat_income.png';
  static const String icCatVehicle = 'assets/icons/ic_cat_vehicle.png';
  static const String icCatHealth = 'assets/icons/ic_cat_health.png';

  // Nano Banana 3D Frosted Liquid Glass System Icons
  static const String icSysShield = 'assets/icons/ic_sys_shield.png';
  static const String icSysVietQr = 'assets/icons/ic_sys_vietqr.png';
  static const String icSysOtaUpdate = 'assets/icons/ic_sys_ota_update.png';

  static const List<String> allBananaIcons = <String>[
    icNavToday,
    icNavFinance,
    icNavCalendar,
    icNavFamily,
    icNavAssets,
    icCatFood,
    icCatHousework,
    icCatHousing,
    icCatUtilities,
    icCatShopping,
    icCatIncome,
    icCatVehicle,
    icCatHealth,
    icSysShield,
    icSysVietQr,
    icSysOtaUpdate,
  ];
}

/// Tactile squircle wrapper for Nano Banana 3D Frosted Liquid Glass icons (60/120 FPS GPU mipmapped).
class BananaGlassIcon extends StatelessWidget {
  final String assetPath;
  final IconData fallbackIcon;
  final Color? fallbackColor;
  final double size;
  final double borderRadius;
  final bool isSelected;
  final String? semanticLabel;

  const BananaGlassIcon({
    super.key,
    required this.assetPath,
    required this.fallbackIcon,
    this.fallbackColor,
    this.size = 40,
    this.borderRadius = 12,
    this.isSelected = false,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0;
    final decodePx = (size * dpr).round().clamp(48, 512);
    final effectiveColor = fallbackColor ?? c.primary;

    final badge = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: effectiveColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: isSelected
              ? c.primary.withValues(alpha: 0.65)
              : Colors.white.withValues(alpha: 0.35),
          width: isSelected ? 1.4 : 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: effectiveColor.withValues(alpha: isSelected ? 0.22 : 0.08),
            blurRadius: isSelected ? 10 : 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset(
        assetPath,
        width: size,
        height: size,
        cacheWidth: decodePx,
        cacheHeight: decodePx,
        filterQuality: FilterQuality.medium,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Icon(
          fallbackIcon,
          color: effectiveColor,
          size: size * 0.54,
        ),
      ),
    );

    if (semanticLabel == null || semanticLabel!.isEmpty) return badge;
    return Semantics(label: semanticLabel, image: true, child: badge);
  }
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
