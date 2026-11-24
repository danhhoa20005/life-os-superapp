# LifeOS Motion QA & Acceptance Checklist (`LIFEOS-MOTION-2026-11-24`)

## 1. Automated Test Matrix Status (Section 12)

| Test ID | Scenario | Automated Test File | Status |
| :--- | :--- | :--- | :--- |
| `NAV-01` | Switch all 4 primary tabs (`Hôm nay`, `Tài chính`, `Lịch & Việc`, `Gia đình`) | `test/core/motion/branch_navigation_test.dart` & `test/widget/top_toast_and_pro_max_redesign_test.dart` | **PASS** |
| `NAV-02` | Rapid mid-flight tab changes (`0 -> 2 -> 1 -> 3` at `40 ms` intervals) | `test/core/motion/branch_navigation_test.dart` | **PASS** |
| `NAV-03` | Switch away from long-scrolled Finance list (`28` seeded rows) and back | `test/core/motion/branch_navigation_test.dart` | **PASS** |
| `NAV-04` | Nested detail/drawer open & close then branch switch | `test/core/motion/branch_navigation_test.dart` & `test/widget/logo_side_drawer_navigation_test.dart` | **PASS** |
| `NAV-05` | Deep link & banking notification review routing | `test/unit/release_hardening_and_audit_v3_16_test.dart` & `test/widget/unified_lifeos_pages_test.dart` | **PASS** |
| `NAV-06` | Dismiss / back mid-transition without crash or stuck overlay | `test/core/motion/branch_navigation_test.dart` & `test/core/motion/pressable_widget_test.dart` | **PASS** |
| `SHEET-01` | Open, dismiss, and verify Quick-Create overlay cleanup | `test/core/motion/branch_navigation_test.dart` | **PASS** |
| `SHEET-02` | Keyboard `viewInsets` (`280 px`) open inside Quick-Create form | `test/core/motion/branch_navigation_test.dart` | **PASS** |
| `TX-01` | Transaction save authoritative success feedback once | `test/core/motion/feedback_state_test.dart` & `test/widget/app_widget_test.dart` | **PASS** |
| `TX-02` | Transaction failure / provisional / needs-review truthful status | `test/core/motion/feedback_state_test.dart` & `test/unit/release_hardening_and_audit_v3_16_test.dart` | **PASS** |
| `TX-03` | Duplicate bank event / foreground toast burst deduplication | `test/core/motion/feedback_state_test.dart` & `test/integration/financial_ai_integration_test.dart` | **PASS** |
| `TX-04` | Accurate VND amount & overspent budget ratio mid-transition | `test/core/motion/feedback_state_test.dart` | **PASS** |
| `TX-05` | Bulk transaction snapshot (`> 5` items) skips mass stagger | `test/core/motion/motion_tokens_test.dart` & `test/core/motion/branch_navigation_test.dart` | **PASS** |
| `CAL-01` | Rapid calendar horizon/date switching | `test/core/motion/branch_navigation_test.dart` & `test/widget/top_toast_and_pro_max_redesign_test.dart` | **PASS** |
| `CAL-02` | Event detail open/back & alarm full-screen priority | `test/features/calendar/alarm_system_accuracy_test.dart` | **PASS** |
| `TASK-01` | Complete task then undo (`accepted -> done -> accepted`) | `test/core/motion/branch_navigation_test.dart` | **PASS** |
| `FAMILY-01` | Invite pending/accepted/revoked follows authoritative `FamilyState` | `test/widget/top_toast_and_pro_max_redesign_test.dart` | **PASS** |
| `A11Y-01` | Android `MediaQuery.disableAnimations` precedence | `test/core/motion/motion_preferences_test.dart` & `test/core/motion/feedback_state_test.dart` | **PASS** |
| `A11Y-02` | iOS `AccessibilityFeatures.reduceMotion` precedence | `test/core/motion/motion_preferences_test.dart` | **PASS** |
| `A11Y-03` | Screen reader semantics + `112%–125%` text scale + dark high-contrast | `test/core/motion/feedback_state_test.dart` & `test/widget/top_toast_and_pro_max_redesign_test.dart` | **PASS** |
| `PERF-01` | Hardware profile-mode raster/UI frame trace on physical Android/iOS | Manual hardware DevTools check (`flutter run --profile`) | **NOT RUN - DEVICE REQUIRED** |
| `PERF-02` | Offstage `TickerMode(false)` & Reduce Motion stop live skeleton/alarm tickers | `test/core/motion/pressable_widget_test.dart` | **PASS** (Static/Widget) / **NOT RUN** (Hardware Raster) |
| `PERF-03` | Idle ticker hygiene (no infinite offstage/reduced-motion loops) | `test/core/motion/pressable_widget_test.dart` & `today_page.dart` | **PASS** (Widget) / **NOT RUN** (10m Battery Trace) |
| `TEST-01` | `flutter analyze --fatal-infos --fatal-warnings` | Repository-wide strict static analysis | **PASS (`0` issues)** |
| `TEST-02` | `flutter test` | Full unit, BLoC, widget, motion, privacy-masking & integration suite | **PASS (`165/165` tests)** |

---

## 2. Manual Real-Device Profiling Procedure (When Hardware Device Is Attached)
1. Attach a mid-range Android (`60 Hz` / `120 Hz`) or iOS device via USB and verify `flutter devices`.
2. Launch profile build: `flutter run --profile`.
3. Open **Flutter DevTools → Performance** and record UI/Raster frame times across:
   - Rapid 4-tab switching + horizontal finger scrubbing on `LiquidGlassSlidingDock`.
   - Opening and swiping down the center `+` `QuickCreateHubSheet`.
   - Scrolling `FinancePage` with `>= 50` transactions while toggling wallet filters.
   - Stepping months/weeks in `PlanningPage`.
   - Toggling **OS Reduce Motion / Remove Animations** and **Giao diện → Giảm chuyển động**.
