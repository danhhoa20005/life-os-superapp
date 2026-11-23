import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../widgets/liquid_glass.dart';

/// Centralized Nano Banana Pro 3D Apple Liquid Glass Icon & Bank Card Skin registry for LifeOS.
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
  static const String onboardingPrivacy =
      'assets/images/onboarding_privacy.png';
  static const String dashboardBanner = 'assets/images/dashboard_banner.png';
  static const String financeIllustration =
      'assets/images/finance_illustration.png';
  static const String familySplitIllustration =
      'assets/images/family_split_illustration.png';
  static const String planningAssetsIllustration =
      'assets/images/planning_assets_illustration.png';

  // 1. Core Navigation & Quick Actions (Nano Banana Pro iOS 26 Liquid Glass 3D)
  static const String icNavToday = 'assets/icons/ic_nav_today.png';
  static const String icNavFinance = 'assets/icons/ic_nav_finance.png';
  static const String icNavCalendar = 'assets/icons/ic_nav_calendar.png';
  static const String icNavFamily = 'assets/icons/ic_nav_family.png';
  static const String icNavAssets = 'assets/icons/ic_nav_assets.png';
  static const String icQuickSplit = 'assets/icons/ic_quick_split.png';

  // 2. Finance, Wealth & Transaction Categories (Nano Banana Pro iOS 26 Liquid Glass 3D)
  static const String icCatFood = 'assets/icons/ic_cat_food.png';
  static const String icCatHousework = 'assets/icons/ic_cat_housework.png';
  static const String icCatHousing = 'assets/icons/ic_cat_housing.png';
  static const String icCatUtilities = 'assets/icons/ic_cat_utilities.png';
  static const String icCatShopping = 'assets/icons/ic_cat_shopping.png';
  static const String icCatIncome = 'assets/icons/ic_cat_income.png';
  static const String icCatVehicle = 'assets/icons/ic_cat_vehicle.png';
  static const String icCatScooter = 'assets/icons/ic_cat_scooter.png';
  static const String icCatHealth = 'assets/icons/ic_cat_health.png';
  static const String icToolReceiptAi = 'assets/icons/ic_tool_receipt_ai.png';
  static const String icToolAnalytics = 'assets/icons/ic_tool_analytics.png';
  static const String icToolSubscription =
      'assets/icons/ic_tool_subscription.png';

  // 3. Daily Life, Productivity & System (Nano Banana Pro iOS 26 Liquid Glass 3D)
  static const String icLifeDocuments = 'assets/icons/ic_life_documents.png';
  static const String icLifeTasks = 'assets/icons/ic_life_tasks.png';
  static const String icLifeHabits = 'assets/icons/ic_life_habits.png';
  static const String icLifeNotes = 'assets/icons/ic_life_notes.png';
  static const String icLifeSocialTravel =
      'assets/icons/ic_life_social_travel.png';
  static const String icSysShield = 'assets/icons/ic_sys_shield.png';
  static const String icSysVietQr = 'assets/icons/ic_sys_vietqr.png';
  static const String icSysOtaUpdate = 'assets/icons/ic_sys_ota_update.png';
  static const String icSysAllServices = 'assets/icons/ic_sys_all_services.png';

  // 4. Clean Luxury Bank & Wallet Card Skins (16:10 Apple Wallet / Revolut Metal & Liquid Glass)
  static const String cardVcbEmerald = 'assets/bank_cards/card_vcb_emerald.png';
  static const String cardTcbCrimson = 'assets/bank_cards/card_tcb_crimson.png';
  static const String cardMbbRoyal = 'assets/bank_cards/card_mbb_royal.png';
  static const String cardBidvTeal = 'assets/bank_cards/card_bidv_teal.png';
  static const String cardTpbViolet = 'assets/bank_cards/card_tpb_violet.png';
  static const String cardBlackTitanium =
      'assets/bank_cards/card_black_titanium.png';
  static const String cardSavingsGold =
      'assets/bank_cards/card_savings_gold.png';

  static const List<String> allBananaIcons = <String>[
    icNavToday,
    icNavFinance,
    icNavCalendar,
    icNavFamily,
    icNavAssets,
    icQuickSplit,
    icCatFood,
    icCatHousework,
    icCatHousing,
    icCatUtilities,
    icCatShopping,
    icCatIncome,
    icCatVehicle,
    icCatScooter,
    icCatHealth,
    icToolReceiptAi,
    icToolAnalytics,
    icToolSubscription,
    icLifeDocuments,
    icLifeTasks,
    icLifeHabits,
    icLifeNotes,
    icLifeSocialTravel,
    icSysShield,
    icSysVietQr,
    icSysOtaUpdate,
    icSysAllServices,
  ];

  static const List<String> allBankCardSkins = <String>[
    cardVcbEmerald,
    cardTcbCrimson,
    cardMbbRoyal,
    cardBidvTeal,
    cardTpbViolet,
    cardBlackTitanium,
    cardSavingsGold,
  ];

  /// Maps a bank code / wallet name / wallet type to its clean Nano Banana Pro Bank Card Skin.
  static String resolveBankCardSkin({
    required String walletTypeKey,
    String? bankCode,
    String? walletName,
  }) {
    final token = '${bankCode ?? ""} ${walletName ?? ""}'.toUpperCase();

    if (walletTypeKey == 'savings') {
      return cardSavingsGold;
    }
    if (token.contains('TCB') ||
        token.contains('TECHCOM') ||
        token.contains('CTG') ||
        token.contains('VIETIN') ||
        token.contains('HSBC') ||
        token.contains('AGRIBANK')) {
      return cardTcbCrimson;
    }
    if (token.contains('TPB') ||
        token.contains('TPBANK') ||
        token.contains('TIMO') ||
        token.contains('CAKE') ||
        token.contains('MOMO')) {
      return cardTpbViolet;
    }
    if (token.contains('BIDV') ||
        token.contains('MSB') ||
        token.contains('OCB') ||
        token.contains('VIB')) {
      return cardBidvTeal;
    }
    if (token.contains('MB') ||
        token.contains('ACB') ||
        token.contains('STB') ||
        token.contains('SACOM') ||
        token.contains('SHB') ||
        token.contains('HDB')) {
      return cardMbbRoyal;
    }
    if (walletTypeKey == 'creditCard') {
      return cardBlackTitanium;
    }
    if (walletTypeKey == 'bank') {
      if (token.contains('VCB') ||
          token.contains('VIETCOM') ||
          token.contains('VPB')) {
        return cardVcbEmerald;
      }
      return cardMbbRoyal;
    }
    return cardVcbEmerald;
  }

  /// Resolves any feature Material `IconData` used across LifeOS into its cohesive
  /// Nano Banana Pro 3D Apple Liquid Glass icon asset.
  static String? resolveBananaIconForGlyph(IconData icon) {
    final code = icon.codePoint;

    if (code == Icons.home_rounded.codePoint ||
        code == Icons.home_outlined.codePoint) {
      return icNavToday;
    }
    if (code == Icons.account_balance_wallet_outlined.codePoint ||
        code == Icons.payments_outlined.codePoint ||
        code == Icons.payments_rounded.codePoint ||
        code == Icons.account_balance_outlined.codePoint ||
        code == Icons.account_balance_rounded.codePoint ||
        code == Icons.credit_card_rounded.codePoint ||
        code == Icons.add_card_rounded.codePoint) {
      return icNavFinance;
    }
    if (code == Icons.savings_outlined.codePoint ||
        code == Icons.savings_rounded.codePoint ||
        code == Icons.south_west_rounded.codePoint) {
      return icCatIncome;
    }
    if (code == Icons.groups_outlined.codePoint ||
        code == Icons.groups_rounded.codePoint ||
        code == Icons.family_restroom_rounded.codePoint ||
        code == Icons.group_add_outlined.codePoint ||
        code == Icons.child_care_rounded.codePoint) {
      return icNavFamily;
    }
    if (code == Icons.swap_horiz_rounded.codePoint ||
        code == Icons.volunteer_activism_outlined.codePoint) {
      return icQuickSplit;
    }
    if (code == Icons.qr_code_2_rounded.codePoint) {
      return icSysVietQr;
    }
    if (code == Icons.calendar_month_rounded.codePoint ||
        code == Icons.calendar_month_outlined.codePoint ||
        code == Icons.calendar_today_rounded.codePoint ||
        code == Icons.calendar_today_outlined.codePoint ||
        code == Icons.event_available_rounded.codePoint ||
        code == Icons.event_rounded.codePoint ||
        code == Icons.event_outlined.codePoint ||
        code == Icons.event_busy_rounded.codePoint ||
        code == Icons.event_busy_outlined.codePoint ||
        code == Icons.edit_calendar_rounded.codePoint ||
        code == Icons.alarm_on_rounded.codePoint ||
        code == Icons.alarm_add_rounded.codePoint) {
      return icNavCalendar;
    }
    if (code == Icons.task_alt_rounded.codePoint ||
        code == Icons.fact_check_outlined.codePoint ||
        code == Icons.check_box_outlined.codePoint ||
        code == Icons.playlist_add_check_circle_outlined.codePoint) {
      return icLifeTasks;
    }
    if (code == Icons.restaurant_rounded.codePoint ||
        code == Icons.soup_kitchen_outlined.codePoint) {
      return icCatFood;
    }
    if (code == Icons.shopping_basket_outlined.codePoint ||
        code == Icons.shopping_basket_rounded.codePoint ||
        code == Icons.kitchen_outlined.codePoint ||
        code == Icons.kitchen_rounded.codePoint ||
        code == Icons.cleaning_services_rounded.codePoint) {
      return icCatHousework;
    }
    if (code == Icons.shopping_bag_rounded.codePoint ||
        code == Icons.shopping_cart_outlined.codePoint ||
        code == Icons.inventory_2_outlined.codePoint) {
      return icCatShopping;
    }
    if (code == Icons.two_wheeler_rounded.codePoint ||
        code == Icons.electric_moped_rounded.codePoint ||
        code == Icons.moped_rounded.codePoint ||
        code == Icons.sports_motorsports_rounded.codePoint) {
      return icCatScooter;
    }
    if (code == Icons.directions_car_outlined.codePoint ||
        code == Icons.directions_car_filled_outlined.codePoint ||
        code == Icons.directions_car_filled_rounded.codePoint ||
        code == Icons.car_repair_rounded.codePoint ||
        code == Icons.handyman_rounded.codePoint ||
        code == Icons.build_circle_outlined.codePoint ||
        code == Icons.oil_barrel_outlined.codePoint ||
        code == Icons.tire_repair_outlined.codePoint) {
      return icCatVehicle;
    }
    if (code == Icons.electric_bolt_rounded.codePoint ||
        code == Icons.bolt_rounded.codePoint ||
        code == Icons.electric_meter_outlined.codePoint ||
        code == Icons.water_drop_outlined.codePoint ||
        code == Icons.wifi_rounded.codePoint) {
      return icCatUtilities;
    }
    if (code == Icons.home_work_rounded.codePoint ||
        code == Icons.home_work_outlined.codePoint ||
        code == Icons.apartment_rounded.codePoint) {
      return icCatHousing;
    }
    if (code == Icons.favorite_outline_rounded.codePoint ||
        code == Icons.favorite_rounded.codePoint ||
        code == Icons.favorite_border_rounded.codePoint ||
        code == Icons.medical_services_rounded.codePoint ||
        code == Icons.medication_outlined.codePoint ||
        code == Icons.medication_liquid_rounded.codePoint ||
        code == Icons.local_hospital_rounded.codePoint ||
        code == Icons.emergency_rounded.codePoint ||
        code == Icons.monitor_weight_outlined.codePoint) {
      return icCatHealth;
    }
    if (code == Icons.folder_open_rounded.codePoint ||
        code == Icons.folder_copy_outlined.codePoint ||
        code == Icons.folder_rounded.codePoint ||
        code == Icons.rule_folder_outlined.codePoint ||
        code == Icons.description_outlined.codePoint ||
        code == Icons.badge_outlined.codePoint) {
      return icLifeDocuments;
    }
    if (code == Icons.request_quote_outlined.codePoint ||
        code == Icons.receipt_long_rounded.codePoint ||
        code == Icons.receipt_long_outlined.codePoint ||
        code == Icons.calculate_outlined.codePoint ||
        code == Icons.auto_awesome_rounded.codePoint) {
      return icToolReceiptAi;
    }
    if (code == Icons.bar_chart_rounded.codePoint ||
        code == Icons.candlestick_chart_rounded.codePoint) {
      return icToolAnalytics;
    }
    if (code == Icons.radar_rounded.codePoint ||
        code == Icons.autorenew_rounded.codePoint ||
        code == Icons.sync_rounded.codePoint ||
        code == Icons.workspace_premium_rounded.codePoint ||
        code == Icons.movie_filter_rounded.codePoint) {
      return icToolSubscription;
    }
    if (code == Icons.local_fire_department_outlined.codePoint ||
        code == Icons.local_fire_department_rounded.codePoint ||
        code == Icons.schedule_rounded.codePoint ||
        code == Icons.access_time_rounded.codePoint) {
      return icLifeHabits;
    }
    if (code == Icons.sticky_note_2_outlined.codePoint ||
        code == Icons.edit_note_rounded.codePoint ||
        code == Icons.note_add_outlined.codePoint ||
        code == Icons.notes_rounded.codePoint) {
      return icLifeNotes;
    }
    if (code == Icons.card_giftcard_rounded.codePoint ||
        code == Icons.luggage_outlined.codePoint ||
        code == Icons.casino_outlined.codePoint) {
      return icLifeSocialTravel;
    }
    if (code == Icons.apps_rounded.codePoint ||
        code == Icons.widgets_outlined.codePoint ||
        code == Icons.inbox_rounded.codePoint) {
      return icSysAllServices;
    }
    if (code == Icons.settings_outlined.codePoint ||
        code == Icons.shield_outlined.codePoint ||
        code == Icons.shield_moon_rounded.codePoint ||
        code == Icons.verified_user_outlined.codePoint ||
        code == Icons.fingerprint_rounded.codePoint ||
        code == Icons.password_rounded.codePoint ||
        code == Icons.palette_outlined.codePoint) {
      return icSysShield;
    }
    if (code == Icons.system_update_rounded.codePoint) {
      return icSysOtaUpdate;
    }
    return null;
  }
}

/// Tactile Apple Liquid Glass squircle wrapper for Nano Banana Pro 3D icons (60/120 FPS GPU mipmapped).
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0;
    final decodePx = (size * dpr).round().clamp(64, 512);
    final effectiveColor = fallbackColor ?? c.primary;

    final badge = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: [
          BoxShadow(
            color: effectiveColor.withValues(
              alpha: isSelected ? 0.24 : (isDark ? 0.18 : 0.08),
            ),
            blurRadius: isSelected ? 12 : 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: CustomPaint(
        foregroundPainter: LiquidGlassRimPainter(
          borderRadius: borderRadius,
          isDark: isDark,
          accentRimColor: isSelected ? c.primary : null,
          strokeWidth: isSelected ? 1.4 : 1.0,
          intensity: isSelected ? 1.25 : 1.0,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(borderRadius),
          child: SizedBox(
            width: size,
            height: size,
            child: Image.asset(
              assetPath,
              width: size,
              height: size,
              cacheWidth: decodePx,
              cacheHeight: decodePx,
              filterQuality: FilterQuality.medium,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => ColoredBox(
                color: effectiveColor.withValues(alpha: 0.14),
                child: Icon(
                  fallbackIcon,
                  color: effectiveColor,
                  size: size * 0.54,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    if (semanticLabel == null || semanticLabel!.isEmpty) {
      return badge;
    }
    return Semantics(label: semanticLabel, image: true, child: badge);
  }
}

/// Brand squircle app logo widget with graceful fallback icon if rendered in headless unit tests.
class BrandLogoMark extends StatelessWidget {
  final double size;
  final double borderRadius;

  const BrandLogoMark({super.key, this.size = 44, this.borderRadius = 12});

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
          errorBuilder: (_, __, ___) =>
              Icon(Icons.shield_outlined, color: c.primary, size: size * 0.56),
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
          errorBuilder: (_, __, ___) =>
              Center(child: Icon(fallbackIcon, size: 42, color: c.primary)),
        ),
      ),
    );
  }
}
