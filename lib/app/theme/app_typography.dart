import 'package:flutter/material.dart';
import 'app_colors.dart';

abstract final class AppTypography {
  static const List<FontFeature> _tabular = [FontFeature.tabularFigures()];

  static TextTheme buildTextTheme(TammySemanticColors colors) {
    return TextTheme(
      displaySmall: TextStyle(
        fontSize: 32,
        height: 1.2,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.7,
        fontFeatures: _tabular,
        color: colors.textPrimary,
      ),
      headlineMedium: TextStyle(
        fontSize: 25,
        height: 1.24,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.45,
        fontFeatures: _tabular,
        color: colors.textPrimary,
      ),
      titleLarge: TextStyle(
        fontSize: 19,
        height: 1.3,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.25,
        fontFeatures: _tabular,
        color: colors.textPrimary,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        height: 1.35,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.15,
        fontFeatures: _tabular,
        color: colors.textPrimary,
      ),
      titleSmall: TextStyle(
        fontSize: 14.5,
        height: 1.35,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.1,
        fontFeatures: _tabular,
        color: colors.textPrimary,
      ),
      bodyLarge: TextStyle(
        fontSize: 16,
        height: 1.42,
        fontWeight: FontWeight.w500,
        color: colors.textPrimary,
      ),
      bodyMedium: TextStyle(
        fontSize: 14.5,
        height: 1.42,
        fontWeight: FontWeight.w500,
        color: colors.textPrimary,
      ),
      bodySmall: TextStyle(
        fontSize: 13.2,
        height: 1.38,
        fontWeight: FontWeight.w500,
        color: colors.textSecondary,
      ),
      labelLarge: TextStyle(
        fontSize: 14,
        height: 1.34,
        fontWeight: FontWeight.w700,
        fontFeatures: _tabular,
        color: colors.textPrimary,
      ),
      labelMedium: TextStyle(
        fontSize: 12.8,
        height: 1.32,
        fontWeight: FontWeight.w600,
        color: colors.textSecondary,
      ),
      labelSmall: TextStyle(
        fontSize: 12,
        height: 1.3,
        fontWeight: FontWeight.w600,
        fontFeatures: _tabular,
        color: colors.textSecondary,
      ),
    );
  }
}
