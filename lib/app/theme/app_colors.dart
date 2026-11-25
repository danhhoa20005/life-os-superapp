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
    primarySubtle: Color(0xFFECFDF3),
    secondary: Color(0xFF2563EB),
    onSecondary: Color(0xFFFFFFFF),
    background: Color(0xFFF6F8FA),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFF9FAFB),
    textPrimary: Color(0xFF0F172A),
    textSecondary: Color(0xFF5B6777),
    border: Color(0xFFE2E8F0),
    separator: Color(0xFFEDF2F7),
    success: Color(0xFF0B7A2A),
    successSubtle: Color(0xFFECFDF3),
    warning: Color(0xFFB45309),
    warningSubtle: Color(0xFFFEF3C7),
    error: Color(0xFFDC2626),
    errorSubtle: Color(0xFFFEE2E2),
  );

  static const TammySemanticColors dark = TammySemanticColors(
    primary: Color(0xFF19C23E),
    onPrimary: Color(0xFF021608),
    primarySubtle: Color(0xFF163524),
    secondary: Color(0xFF60A5FA),
    onSecondary: Color(0xFF13181F),
    background: Color(0xFF161B22),
    surface: Color(0xFF202731),
    surfaceRaised: Color(0xFF28313D),
    textPrimary: Color(0xFFF8FAFC),
    textSecondary: Color(0xFFCBD5E1),
    border: Color(0xFF333F4D),
    separator: Color(0xFF293340),
    success: Color(0xFF34D399),
    successSubtle: Color(0xFF163526),
    warning: Color(0xFFFBBF24),
    warningSubtle: Color(0xFF3B2D12),
    error: Color(0xFFF87171),
    errorSubtle: Color(0xFF3D1D1E),
  );

  static const TammySemanticColors highContrastLight = TammySemanticColors(
    primary: Color(0xFF065F1E),
    onPrimary: Color(0xFFFFFFFF),
    primarySubtle: Color(0xFFDDF7E6),
    secondary: Color(0xFF1D4ED8),
    onSecondary: Color(0xFFFFFFFF),
    background: Color(0xFFFFFFFF),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFF1F5F9),
    textPrimary: Color(0xFF020617),
    textSecondary: Color(0xFF1E293B),
    border: Color(0xFF334155),
    separator: Color(0xFF64748B),
    success: Color(0xFF065F1E),
    successSubtle: Color(0xFFDDF7E6),
    warning: Color(0xFF92400E),
    warningSubtle: Color(0xFFFEF3C7),
    error: Color(0xFF991B1B),
    errorSubtle: Color(0xFFFEE2E2),
  );

  static const TammySemanticColors highContrastDark = TammySemanticColors(
    primary: Color(0xFF34E85D),
    onPrimary: Color(0xFF021A08),
    primarySubtle: Color(0xFF0F3D22),
    secondary: Color(0xFF93C5FD),
    onSecondary: Color(0xFF081426),
    background: Color(0xFF14181F),
    surface: Color(0xFF1D232C),
    surfaceRaised: Color(0xFF28313D),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xFFF1F5F9),
    border: Color(0xFFCBD5E1),
    separator: Color(0xFF64748B),
    success: Color(0xFF4ADE80),
    successSubtle: Color(0xFF0F3D22),
    warning: Color(0xFFFDE047),
    warningSubtle: Color(0xFF423007),
    error: Color(0xFFFCA5A5),
    errorSubtle: Color(0xFF4C1414),
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
  TammySemanticColors lerp(
    ThemeExtension<TammySemanticColors>? other,
    double t,
  ) {
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
