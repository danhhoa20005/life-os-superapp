import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_spacing.dart';
import 'app_typography.dart';

abstract final class AppTheme {
  static ThemeData light({
    bool highContrast = false,
    bool compactDensity = true,
  }) {
    final c = highContrast
        ? TammySemanticColors.light.copyWith(
            primary: const Color(0xFF0B8A33),
            border: const Color(0xFF344054),
          )
        : TammySemanticColors.light;
    return _build(Brightness.light, c, compactDensity: compactDensity);
  }

  static ThemeData dark({
    bool highContrast = false,
    bool compactDensity = true,
  }) {
    final c = highContrast
        ? TammySemanticColors.dark.copyWith(
            surface: const Color(0xFF101512),
            border: const Color(0xFFA0AEB6),
          )
        : TammySemanticColors.dark;
    return _build(Brightness.dark, c, compactDensity: compactDensity);
  }

  static ThemeData _build(
    Brightness brightness,
    TammySemanticColors c, {
    bool compactDensity = true,
  }) {
    final isDark = brightness == Brightness.dark;
    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: c.primary,
      onPrimary: c.onPrimary,
      primaryContainer: c.primarySubtle,
      onPrimaryContainer: c.textPrimary,
      secondary: c.secondary,
      onSecondary: c.onSecondary,
      error: c.error,
      onError: Colors.white,
      surface: c.surface,
      onSurface: c.textPrimary,
      outline: c.border,
      outlineVariant: c.separator,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      visualDensity: compactDensity
          ? const VisualDensity(horizontal: -1, vertical: -1)
          : VisualDensity.standard,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: c.background,
      textTheme: AppTypography.buildTextTheme(c),
      extensions: [c],
      dividerTheme: DividerThemeData(
        color: c.separator.withValues(alpha: 0.8),
        thickness: 0.9,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: c.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.4,
          color: c.textPrimary,
        ),
      ),
      cardTheme: CardThemeData(
        color: c.surface,
        elevation: 0,
        shadowColor: const Color(0xFF0F172A).withValues(alpha: 0.04),
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: c.border, width: 1.0),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.white;
          return isDark ? const Color(0xFFCBD5E1) : Colors.white;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return c.primary;
          return isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1);
        }),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      tabBarTheme: TabBarThemeData(
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.tab,
        labelColor: c.textPrimary,
        unselectedLabelColor: c.textSecondary,
        labelStyle: const TextStyle(
          fontSize: 13.2,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.15,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 13.2,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.1,
        ),
        indicator: BoxDecoration(
          color: isDark ? const Color(0xFF2D3744) : Colors.white,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.12)
                : const Color(0xFFE2E8F0),
            width: 0.8,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.06),
              blurRadius: 6,
              offset: const Offset(0, 1.5),
            ),
          ],
        ),
        splashBorderRadius: BorderRadius.circular(11),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shadowColor: const Color(
          0xFF0F172A,
        ).withValues(alpha: isDark ? 0.40 : 0.10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: c.border, width: 1.0),
        ),
        titleTextStyle: TextStyle(
          fontSize: 18.5,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.3,
          color: c.textPrimary,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        modalBarrierColor: const Color(
          0xFF0F172A,
        ).withValues(alpha: isDark ? 0.48 : 0.24),
        dragHandleColor: c.textSecondary.withValues(alpha: 0.30),
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          side: BorderSide(color: c.border, width: 1.0),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: c.surface,
        selectedColor: c.primarySubtle,
        side: BorderSide(color: c.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        labelStyle: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: c.textPrimary,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size(AppSpacing.minHitTarget, 48),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
          ),
          textStyle: const TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.1,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.textPrimary,
          minimumSize: const Size(AppSpacing.minHitTarget, 48),
          side: BorderSide(color: c.border),
          backgroundColor: c.surface,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
          ),
          textStyle: const TextStyle(
            fontSize: 14.2,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.primary,
          minimumSize: const Size(
            AppSpacing.minHitTarget,
            AppSpacing.minHitTarget,
          ),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF1A2029) : Colors.white,
        hintMaxLines: 2,
        errorMaxLines: 3,
        helperMaxLines: 3,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: BorderSide(color: c.border, width: 1.0),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: BorderSide(color: c.border, width: 1.0),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: BorderSide(color: c.primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: BorderSide(color: c.error, width: 1.4),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: c.primarySubtle,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        height: 68,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            letterSpacing: -0.1,
            color: isSelected ? c.primary : c.textSecondary,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: isSelected ? c.primary : c.textSecondary,
            size: 23,
          );
        }),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}
