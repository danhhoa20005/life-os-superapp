/// 4pt base grid, border radii, hit targets, and responsive breakpoints from `a.docx`.
abstract final class AppSpacing {
  static const double xxs = 4.0;
  static const double xs = 8.0;
  static const double sm = 12.0;
  static const double md = 16.0;
  static const double lg = 20.0;
  static const double xl = 24.0;
  static const double xxl = 32.0;
  static const double xl2 = 40.0;
  static const double xxxl = 48.0;
  static const double dockClearance = 104.0;

  static const double radiusSm = 8.0;
  static const double radiusMd = 12.0;
  static const double radiusLg = 16.0;
  static const double radiusXl = 24.0;
  static const double radiusPill = 999.0;

  /// WCAG 2.2 AA & Material 3 minimum comfortable pointer/touch target (48 x 48 dp).
  static const double minHitTarget = 48.0;
  static const double buttonHeightM = 48.0;
  static const double buttonHeightL = 52.0;
  static const double inputHeight = 50.0;

  /// Responsive layout breakpoints.
  static const double tabletBreakpoint = 840.0;
  static const double maxContentWidth = 1000.0;
}
