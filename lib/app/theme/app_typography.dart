import 'package:flutter/material.dart';
import 'app_colors.dart';

abstract final class AppTypography {
  static const List<FontFeature> _tabular = [FontFeature.tabularFigures()];

  static TextTheme buildTextTheme(TammySemanticColors colors) {
    return TextTheme(
      displaySmall: TextStyle(
        fontSize: 34,
        height: 40 / 34,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.8,
        fontFeatures: _tabular,
        color: colors.textPrimary,
      ),
      headlineMedium: TextStyle(
        fontSize: 26,
        height: 32 / 26,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
        fontFeatures: _tabular,
        color: colors.textPrimary,
      ),
      titleLarge: TextStyle(
        fontSize: 20,
        height: 26 / 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        fontFeatures: _tabular,
        color: colors.textPrimary,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        height: 22 / 16,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        fontFeatures: _tabular,
        color: colors.textPrimary,
      ),
      bodyLarge: TextStyle(
        fontSize: 16,
        height: 22 / 16,
        fontWeight: FontWeight.w400,
        color: colors.textPrimary,
      ),
      bodyMedium: TextStyle(
        fontSize: 14.5,
        height: 20 / 14.5,
        fontWeight: FontWeight.w400,
        color: colors.textPrimary,
      ),
      bodySmall: TextStyle(
        fontSize: 13,
        height: 18 / 13,
        fontWeight: FontWeight.w400,
        color: colors.textSecondary,
      ),
      labelLarge: TextStyle(
        fontSize: 14,
        height: 19 / 14,
        fontWeight: FontWeight.w600,
        fontFeatures: _tabular,
        color: colors.textPrimary,
      ),
      labelMedium: TextStyle(
        fontSize: 12.5,
        height: 16 / 12.5,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
        color: colors.textSecondary,
      ),
      labelSmall: TextStyle(
        fontSize: 11.5,
        height: 15 / 11.5,
        fontWeight: FontWeight.w500,
        fontFeatures: _tabular,
        color: colors.textSecondary,
      ),
    );
  }
}
