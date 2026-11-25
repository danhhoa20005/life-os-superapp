/// Unified route & deep-link contract for LifeOS Super App modules.
/// Eliminates hardcoded route drift across Directory, Side Drawer, and Deep Links.
abstract final class FeatureRegistry {
  static const String routeToday = '/today';
  static const String routeFinance = '/finance';
  static const String routePlanning = '/planning';
  static const String routePlanningCalendar = '/planning?tab=calendar';
  static const String routePlanningTasks = '/planning?tab=tasks';
  static const String routePlanningTools = '/planning?tab=tools';
  static const String routeFamily = '/family';
  static const String routeMenu = '/menu';

  static const String routeWealthReceipt = '/wealth-tools?tab=receipt';
  static const String routeWealthLoan = '/wealth-tools?tab=loan';
  static const String routeWealthFire = '/wealth-tools?tab=fire';

  static const String routeSmartNotes = '/smart-notes-hub?tab=notes';
  static const String routeSalaryTax = '/smart-notes-hub?tab=salary';

  static const String routeHealthOverview = '/health-hub';
  static const String routeHealthWater = '/health-hub?tab=water';
  static const String routeHealthCabinet = '/health-hub?tab=meds';

  static const String routeMotionGallery = '/motion-gallery';
  static const String routeAutomationStudio = '/automation-studio';
  static const String routeLifeTimeline = '/life-timeline';

  /// Normalizes `?tab=` query values for `WealthToolsPage`.
  static String normalizeWealthToolTab(String? rawTab) {
    return switch ((rawTab ?? '').trim().toLowerCase()) {
      'loan' || 'lai-vay' => 'loan',
      'fire' || 'jars' || '6-lo' => 'fire',
      _ => 'receipt',
    };
  }

  /// Normalizes `?tab=` query values for `SmartNotesSalaryPage`.
  static String normalizeSmartNotesSalaryTab(String? rawTab) {
    return switch ((rawTab ?? '').trim().toLowerCase()) {
      'salary' || 'tax' || 'gross-net' || 'luong' => 'salary',
      _ => 'notes',
    };
  }

  /// Normalizes `?tab=` query values for `PlanningPage` (`0`: Calendar, `1`: Tasks, `2`: Tools/Alarms).
  static int normalizePlanningTabIndex(String? rawTab) {
    return switch ((rawTab ?? '').trim().toLowerCase()) {
      'tasks' || 'viec' || 'kanban' => 1,
      'tools' || 'alarms' || 'utilities' => 2,
      _ => 0,
    };
  }
}
