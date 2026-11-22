import 'package:flutter/material.dart';

/// Semantic color tokens implementing the "Tammy × Apple" Design System (`a.docx`).
@immutable
class TammySemanticColors extends ThemeExtension<TammySemanticColors> {
  final Color primary;
  final Color onPrimary;
  final Color primarySubtle;
  final Color secondary;
  final Color onSecondary;
  final Color background;
  final Color surface;
  final Color surfaceRaised;
  final Color textPrimary;
  final Color textSecondary;
  final Color border;
  final Color separator;
  final Color success;
  final Color successSubtle;
  final Color warning;
  final Color warningSubtle;
  final Color error;
  final Color errorSubtle;

  const TammySemanticColors({
    required this.primary,
    required this.onPrimary,
    required this.primarySubtle,
    required this.secondary,
    required this.onSecondary,
    required this.background,
    required this.surface,
    required this.surfaceRaised,
    required this.textPrimary,
    required this.textSecondary,
    required this.border,
    required this.separator,
    required this.success,
    required this.successSubtle,
    required this.warning,
    required this.warningSubtle,
    required this.error,
    required this.errorSubtle,
  });

  static const TammySemanticColors light = TammySemanticColors(
    primary: Color(0xFF0B7A2A),
    onPrimary: Color(0xFFFFFFFF),
    primarySubtle: Color(0xFFE7F7EB),
    secondary: Color(0xFF0057B8),
    onSecondary: Color(0xFFFFFFFF),
    background: Color(0xFFF2F2F7),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFF7F7FA),
    textPrimary: Color(0xFF1D1D1F),
    textSecondary: Color(0xFF54545A),
    border: Color(0xFF8E8E93),
    separator: Color(0xFFD1D1D6),
    success: Color(0xFF006D5B),
    successSubtle: Color(0xFFE8F7F2),
    warning: Color(0xFF8A4B00),
    warningSubtle: Color(0xFFFFF7E6),
    error: Color(0xFFB42318),
    errorSubtle: Color(0xFFFFF0EE),
  );

  static const TammySemanticColors dark = TammySemanticColors(
    primary: Color(0xFF19C23E),
    onPrimary: Color(0xFF000000),
    primarySubtle: Color(0xFF123C1F),
    secondary: Color(0xFF64D2FF),
    onSecondary: Color(0xFF000000),
    background: Color(0xFF000000),
    surface: Color(0xFF1C1C1E),
    surfaceRaised: Color(0xFF2C2C2E),
    textPrimary: Color(0xFFF5F5F7),
    textSecondary: Color(0xFFB8B8BE),
    border: Color(0xFF747478),
    separator: Color(0xFF3A3A3C),
    success: Color(0xFF63E6BE),
    successSubtle: Color(0xFF10352E),
    warning: Color(0xFFFFD60A),
    warningSubtle: Color(0xFF3A2C05),
    error: Color(0xFFFF453A),
    errorSubtle: Color(0xFF3A1715),
  );

  static TammySemanticColors of(BuildContext context) {
    return Theme.of(context).extension<TammySemanticColors>() ?? light;
  }

  @override
  TammySemanticColors copyWith({
    Color? primary,
    Color? onPrimary,
    Color? primarySubtle,
    Color? secondary,
    Color? onSecondary,
    Color? background,
    Color? surface,
    Color? surfaceRaised,
    Color? textPrimary,
    Color? textSecondary,
    Color? border,
    Color? separator,
    Color? success,
    Color? successSubtle,
    Color? warning,
    Color? warningSubtle,
    Color? error,
    Color? errorSubtle,
  }) {
    return TammySemanticColors(
      primary: primary ?? this.primary,
      onPrimary: onPrimary ?? this.onPrimary,
      primarySubtle: primarySubtle ?? this.primarySubtle,
      secondary: secondary ?? this.secondary,
      onSecondary: onSecondary ?? this.onSecondary,
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      border: border ?? this.border,
      separator: separator ?? this.separator,
      success: success ?? this.success,
      successSubtle: successSubtle ?? this.successSubtle,
      warning: warning ?? this.warning,
      warningSubtle: warningSubtle ?? this.warningSubtle,
      error: error ?? this.error,
      errorSubtle: errorSubtle ?? this.errorSubtle,
    );
  }

  @override
  TammySemanticColors lerp(ThemeExtension<TammySemanticColors>? other, double t) {
    if (other is! TammySemanticColors) return this;
    return TammySemanticColors(
      primary: Color.lerp(primary, other.primary, t)!,
      onPrimary: Color.lerp(onPrimary, other.onPrimary, t)!,
      primarySubtle: Color.lerp(primarySubtle, other.primarySubtle, t)!,
      secondary: Color.lerp(secondary, other.secondary, t)!,
      onSecondary: Color.lerp(onSecondary, other.onSecondary, t)!,
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      border: Color.lerp(border, other.border, t)!,
      separator: Color.lerp(separator, other.separator, t)!,
      success: Color.lerp(success, other.success, t)!,
      successSubtle: Color.lerp(successSubtle, other.successSubtle, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningSubtle: Color.lerp(warningSubtle, other.warningSubtle, t)!,
      error: Color.lerp(error, other.error, t)!,
      errorSubtle: Color.lerp(errorSubtle, other.errorSubtle, t)!,
    );
  }
}
