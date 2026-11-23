/// 4pt base grid, border radii, hit targets, and responsive breakpoints from `a.docx`.
abstract final class AppSpacing {
  static const double xxs = 4.0;
  static const double xs = 8.0;
  static const double sm = 12.0;
  static const double md = 16.0;
  static const double lg = 20.0;
  static const double xl = 24.0;
  static const double xxl = 32.0;
  static const double xxxl = 48.0;
  static const double dockClearance = 104.0;

  static const double radiusSm = 8.0;
  static const double radiusMd = 12.0;
  static const double radiusLg = 16.0;
  static const double radiusXl = 24.0;
  static const double radiusPill = 999.0;

  /// Apple HIG + WCAG 2.2 minimum comfortable pointer/touch target (44 x 44 pt).
  static const double minHitTarget = 44.0;
  static const double buttonHeightM = 46.0;
  static const double buttonHeightL = 52.0;
  static const double inputHeight = 50.0;

  /// Responsive layout breakpoints.
  static const double tabletBreakpoint = 840.0;
  static const double maxContentWidth = 1000.0;
}
