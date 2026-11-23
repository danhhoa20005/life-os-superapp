import 'package:flutter/material.dart';

/// Unified LifeOS Fresh Emerald-Mint Design System tokens (Light & True Dark Mode).
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
    secondary: Color(0xFF2563EB),
    onSecondary: Color(0xFFFFFFFF),
    background: Color(0xFFF2F5F3),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFF4F7F5),
    textPrimary: Color(0xFF0F172A),
    textSecondary: Color(0xFF475467),
    border: Color(0xFFDCE4DF),
    separator: Color(0xFFE7EDE9),
    success: Color(0xFF0B7A2A),
    successSubtle: Color(0xFFE7F7EB),
    warning: Color(0xFFD97706),
    warningSubtle: Color(0xFFFEF3C7),
    error: Color(0xFFDC2626),
    errorSubtle: Color(0xFFFEE2E2),
  );

  static const TammySemanticColors dark = TammySemanticColors(
    primary: Color(0xFF22C55E),
    onPrimary: Color(0xFFFFFFFF),
    primarySubtle: Color(0xFF102D1C),
    secondary: Color(0xFF60A5FA),
    onSecondary: Color(0xFF080C0A),
    background: Color(0xFF080C0A),
    surface: Color(0xFF121915),
    surfaceRaised: Color(0xFF19231D),
    textPrimary: Color(0xFFF8FAFC),
    textSecondary: Color(0xFFCBD5E1),
    border: Color(0xFF2B3B31),
    separator: Color(0xFF202D25),
    success: Color(0xFF34D399),
    successSubtle: Color(0xFF0F2F21),
    warning: Color(0xFFFBBF24),
    warningSubtle: Color(0xFF38290A),
    error: Color(0xFFF87171),
    errorSubtle: Color(0xFF3A1616),
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
