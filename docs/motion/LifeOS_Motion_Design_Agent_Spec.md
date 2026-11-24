# LIFEOS - MOTION DESIGN SYSTEM
## Agent implementation specification and acceptance contract

**Document ID:** LIFEOS-MOTION-2026-11-24  
**Status:** Ready for engineering agent  
**Target application:** LifeOS, Flutter mobile super app  
**Repository:** https://github.com/danhhoa20005/life-os-superapp  
**Reference snapshot:** `main`, inspected 2026-11-24; `pubspec.yaml` declares `version: 3.15.0+30`, Dart `^3.10.0`, Flutter `>=3.24.0`, `flutter_bloc`, `go_router` and Firebase dependencies.  
**Important:** The LOCAL working tree, current lockfile, installed SDK and tests are authoritative at execution time. This document is a design and execution plan, not a claim that code has already been changed.

---

## 0. AGENT EXECUTION INSTRUCTION - READ FIRST

You are the **Lead Flutter Motion Engineer, UX Animation Designer, Accessibility Engineer and Performance Engineer** for LifeOS. Your task is to implement a cohesive, expressive, responsive and low-jank motion system inspired by Google's Material 3 / Material 3 Expressive design principles, adapted to LifeOS's existing visual language and architecture.

**Primary outcome:** all major user journeys should feel intentionally connected, physically responsive, fast, accessible and visually consistent. Motion must communicate state, continuity and feedback, not merely decorate screens.

### Mandatory operating rules

1. Inspect the **local** repository before changing any file. Start with `git status`, `flutter --version`, `dart --version`, `flutter pub get`, `flutter analyze` and a focused test baseline. Record unavailable commands or infrastructure blockers rather than pretending they passed.
2. **Preserve Clean Architecture and BLoC.** Use `flutter_bloc` and existing event/state abstractions. Do NOT introduce Cubit, move animations to Domain/Data layers, replace dependency injection, or rewrite authentication, banking, calendar sync or Firebase integration.
3. Do NOT erase or rebuild existing Liquid Glass, navigation, toast, branding or other functioning visual systems merely to add animations. Extend or refactor surgically behind stable interfaces.
4. Existing behaviors are contractual: branch navigation stacks, deep links, scroll positions, text input, offline/online state, bank transaction accuracy, permission prompts, scheduled alarms and notification handling must continue to work.
5. Check package license, SDK constraints, maintenance and footprint **before** adding dependencies. Native Flutter animation APIs are the default; third-party packages must deliver demonstrable value.
6. Implement and test **Reduce Motion** and full accessibility from the start; do not retrofit it after the system is built.
7. Treat bank transaction confirmation, balances, transfers and alerts as **high-integrity states**. An animation is not evidence that an operation succeeded. Show success only after an authoritative BLoC/domain success state.
8. Work in small reversible changes; run focused tests after each stage. Do not request routine technical confirmations. If a dependency, device or credential is unavailable, choose the safest reversible path, log the limitation and continue on independent work.
9. Do NOT push, merge, deploy, upload private data, modify production Firebase rules or make destructive changes without explicit authorization. Implement in the local project/worktree; provide reviewable changes and a final report.
10. Do not claim a performance target, accessibility behavior or test result is achieved without measurements or successful tests.

### Final deliverables

- `lib/core/motion/` or the project's closest existing presentation-level shared directory, containing documented motion tokens, accessibility gate, reusable interaction widgets and feedback primitives.
- Consistent animation integration for primary navigation, finance, calendar/tasks, family, notifications and selected daily-life modules, phased by priority below.
- Focused widget, navigation, accessibility and regression tests (and integration tests where infrastructure exists).
- Before/after performance evidence from real **profile-mode** measurements on named devices, if devices are available.
- `docs/motion/MOTION_GUIDELINES.md`, `docs/motion/MOTION_COVERAGE_MATRIX.md`, `docs/motion/QA_CHECKLIST.md` and `docs/motion/IMPLEMENTATION_REPORT.md` (or equivalent project structure).
- A concise changelog, file list, dependency decision record, screenshots or short screen recordings where possible, and documented known limitations.

### Definition of done

This project is **not done** merely because effects look attractive in one demo. It is done when core journeys are covered, regressions are absent, motion can be interrupted and reversed correctly, accessibility works, performance is measured and the acceptance matrix in Section 15 is satisfied or each exception is clearly documented.

---

## 1. VERIFIED STARTING POINT AND REQUIRED AUDIT

The following observations were made from the repository's `main` branch on 2026-11-24. They are **not** a replacement for inspecting the agent's local files.

| Path / component | Observed baseline | Impact on implementation |
|---|---|---|
| `pubspec.yaml` | Flutter/BLoC/go_router/Firebase application; no dedicated animation, Lottie, Rive or Skeletonizer dependency listed | Verify with the local lockfile; add only compatible and necessary packages |
| `lib/app/app_router.dart` | `StatefulShellRoute.indexedStack` with four branches (`/today`, `/finance`, `/planning`, `/family`) | Preserve each nested navigator and its branch state |
| `lib/app/app_router.dart` around L752-L820 | `_SlidingShellViewport` uses directional slide and fade with a 220 ms `AnimationController` | Review duplication with any new shell animation; do not accidentally double-animate |
| `lib/app/app_router.dart` around L680-L745 | `LiquidGlassSlidingDock` wrapped in `RepaintBoundary`; center quick-add action | Keep dock responsive, stable and accessible |
| `lib/core/widgets/liquid_glass.dart` | `LiquidGlassSlidingDock` has a 360 ms controller, a custom cubic curve, `AnimatedBuilder` and haptics | Preserve glass capsule mechanics, improve shared tokens and interruption handling |
| `lib/core/widgets/liquid_glass.dart` | `BackdropFilter` in glass surfaces/sheets | Profile GPU cost while transitions run; avoid animating multiple expensive blurred layers |
| `lib/core/widgets/lifeos_top_toast.dart` | Animated top toast with slide/fade and enter/exit durations | Unify durations/easing; retain dismissal and foreground push semantics |
| `lib/core/widgets/lifeos_design_system.dart` | Shared cards, CTA, segmented pills, and `AnimatedPositioned` | Reuse existing widgets and move only truly shared motion concerns into core motion |
| `lib/features/dashboard/presentation/pages/today_page.dart` | Main dashboard, hero cards, quick creation and bottom sheets | Priority launch surface; keep live data stable |
| `lib/features/transactions/presentation/pages/finance_page.dart` | Finance hub, statements, categories, budgets, analytics, quick entry | Priority precision UX; preserve numeric and transaction correctness |
| `lib/features/calendar/presentation/pages/planning_page.dart` | Calendar, timeline and planning surfaces | Priority continuity between day/week/event/task views |
| `lib/app/app.dart` | `MaterialApp.router`, `ThemeBloc`, `AuthBloc`, `AppUpdateBloc` | Connect app-level motion preferences without altering business state ownership |

### Audit procedure

1. Run `git status --short`, `git branch --show-current`, `git log -1 --oneline`, `flutter --version`, `dart --version`.
2. Read `pubspec.yaml`, `pubspec.lock`, `lib/app/app_router.dart`, `lib/app/app.dart`, all `lib/app/theme/` and key `lib/core/widgets/` files.
3. Search code for `AnimationController`, `Tween`, `Animated*`, `Hero`, `BackdropFilter`, `TickerProvider`, `CustomTransitionPage`, `PageRoute`, `showModalBottomSheet`, `RepaintBoundary`, `TickerMode` and `HapticFeedback`.
4. Record existing animations in a **Motion Inventory**: widget, trigger, current duration, easing/spring, ownership, reduced-motion behavior, possible perf cost, risk, and proposed action (`keep`, `tune`, `replace`, `remove duplicate`).
5. Record baseline behavior by executing at least: change all primary tabs; open and close quick-create; scroll finance; open an event; return to a tab; trigger a toast; deep-link to review a transaction if test setup permits.
6. Record current warning/error counts from analyzer and tests **before editing**. Distinguish pre-existing failures from introduced regressions.

**No implementation step may assume that a file, class, field or route still exists just because it appears in this document.**

---

## 2. EXPERIENCE PRINCIPLES AND MOTION LANGUAGE

### 2.1 Visual direction

LifeOS has a green/mint brand language, soft cards, Liquid Glass navigation and multiple information-dense functional hubs. The motion language should be **calm for routine activity, expressive for decisive actions, and restrained for financial information**.

- **Continuity first:** show where an element came from and where it goes.
- **Physical but controlled:** spring settling for press, selection and panel transitions; no prolonged bounce or elastic overshoot on dense data.
- **Hierarchy aware:** animate a primary surface before its child content; a large number of simultaneous animations is a defect.
- **Feedback before decoration:** every effect should explain press, selection, expanding, loading, completion, rejection, or navigation.
- **Quick recovery:** animations must stop, reverse or retarget under repeated user input; avoid queuing stale controller sequences.
- **Reduced motion is first class:** all non-essential motion can be minimized without hiding state changes.
- **Brand consistency:** preserve LifeOS colors and typography; do not import external demo color schemes.

### 2.2 Motion pattern selection

| Pattern | When to use | When NOT to use |
|---|---|---|
| Press spring | Primary CTA, compact action, selectable chip, dock tab | Dense table rows on every touch; repeated looping |
| Container transform | Card/transaction/event preview expands into details | Cross-navigator routes with unsafe Hero contexts or unstable identifiers |
| Shared axis | Wizard, onboarding, calendar period navigation, related parent-child screens | Unrelated primary-tab changes without spatial meaning |
| Fade-through | Switch category/filter/data view when content is replaced | Changes to numbers requiring continuous tracking |
| Hero/shared element | Persistent identifiable photo/icon/card between two routes | Duplicate hero tags, changing data item IDs, overlapping nested navigators |
| Animated list diff | One row inserted/removed/reordered, completed task | Rebuilding whole list on every Firestore update |
| Progress and content reveal | Known progress or resolved load state | Fake determinate progress when server progress is unknown |
| Short success mark | Authoritative save/sync/transaction completion | While request is pending or result is merely optimistic |
| Skeleton | Loading layout with uncertain content delay | Existing populated content during background refresh if it causes flashing |
| Subtle haptic | Explicit select, commit or completed action with user settings respected | Repeated frame callbacks, every scroll tick or bank push |

### 2.3 Animation priority

**P0 - essential**: visual feedback, navigation continuity, finance correctness, reduce-motion, safe loading states.  
**P1 - important**: card expansion, forms/sheets, calendar/time transitions, task completion, targeted notifications.  
**P2 - selective polish**: onboarding illustration, nuanced empty states, Rive/Lottie assets, optional custom shapes.

---

## 3. MOTION TOKENS - INITIAL DESIGN SPECIFICATION

These values are **starting hypotheses for LifeOS**, not mandatory Google constants. The agent must tune them on physical devices, keep a single source of truth, and document final values.

### 3.1 Duration tokens

| Token name | Initial value | Example usage |
|---|---:|---|
| `instant` | 0 ms | Reduce Motion: replace purely decorative transition |
| `feedbackFast` | 100 ms | Press-down response, focus highlight |
| `micro` | 160 ms | Icon state, checkbox, counter emphasis |
| `standard` | 220 ms | Tabs, small UI visibility, toast entry |
| `medium` | 300 ms | Shared-axis screen transition, filter/content swap |
| `panel` | 340 ms | Bottom sheet reveal, major card expand |
| `expressive` | 420 ms | Single important success or onboarding gesture |
| `longEmphasis` | 520 ms maximum | Reserved for rare, non-blocking celebratory feedback |

Timing guidance: enter motion may be slightly more expressive than exit; exit should not block the next action. Avoid multiple nested components each independently adding 300+ ms of perceived delay.

### 3.2 Easing and spring tokens

Maintain named `Curve` and `SpringDescription` presets. Suggested initial profiles (Flutter simulation values; must be measured):

| Token | Suggested starting configuration | Intended feel |
|---|---|---|
| `curveStandard` | `Curves.easeOutCubic` | Fast general entrance |
| `curveEmphasized` | `Cubic(0.2, 0.0, 0.0, 1.0)` | Strong entry with smooth finish |
| `springPress` | `SpringDescription(mass: 1.0, stiffness: 600, damping: 43)` | Quick press/release |
| `springSelection` | `SpringDescription(mass: 1.0, stiffness: 430, damping: 37)` | Dock capsule and selected chip |
| `springPanel` | `SpringDescription(mass: 1.0, stiffness: 320, damping: 34)` | Larger surface settling |

**Implementation caution:** `AnimationController.animateWith(SpringSimulation(...))` is different from interpolating a spring-like cubic curve. Use true physics only where interruption/velocity matters. Prefer ordinary curves for predictable short content fade and accessibility.

### 3.3 Geometry and amplitude

- Pressed scale: **0.97-0.985**, not dramatic shrinking; tap target hitbox must remain unchanged.
- Content translation: **4-12 logical pixels** for local entry; avoid full-screen horizontal drift for ordinary tab changes.
- Selected pill: animate geometry and highlight, but preserve text legibility and touch target size.
- Card expansion: animate outer shape/position or material bounds; child text must not stretch or distort.
- Stagger: **25-45 ms** between visible items, cap animation count to approximately 4-6 items at one time; never stagger hundreds of rows.
- Overshoot: subtle or none for text, charts, money and dense navigation; limited for isolated success marks.
- Continuous decorative animation: generally disabled on main dashboards; never run indefinitely in offstage branches.

### 3.4 Motion preferences

Define a presentation-level `MotionPreferences` model with `standard`, `reduced` and optionally `off` behavior. Honor platform accessibility **above** decorative user preferences.

- Android: inspect `MediaQueryData.disableAnimations` or framework accessibility flag.
- iOS: inspect `PlatformDispatcher.accessibilityFeatures.reduceMotion` as a separate signal; do not assume `MediaQuery.disableAnimations` covers iOS.
- Allow a user override if existing settings UX supports it; persistence should follow the existing settings architecture, not a new unmanaged state store.
- In reduced mode, replace movement with short opacity change or an immediate state swap; never hide meaningful loading/error/success text.
- Animations must not gate keyboard focus, semantics announcements or screen reader access.

---

## 4. ARCHITECTURE CONTRACT - CLEAN ARCHITECTURE + BLOC

### 4.1 Layer boundaries

**Presentation / core motion:** animation controllers, springs, curves, transitions, gesture feedback, skeletons and motion settings.  
**Presentation BLoC:** authoritative UI state and events; one-time effects are triggered by state transitions via `BlocListener` where appropriate.  
**Domain:** business invariants and use cases stay unchanged.  
**Data/infrastructure:** repositories, Firebase, notification ingestion, device permissions and persistence remain independent from animation details.

Never place `AnimationController`, `TickerProvider`, `BuildContext`, `Curve`, `SpringDescription` or `Widget` in Domain entities or repositories.

### 4.2 Proposed file structure (adapt to project conventions)

```text
lib/core/motion/
  lifeos_motion_tokens.dart          # single duration, curve and spring source
  lifeos_motion_preferences.dart     # platform and app reduced-motion decisions
  lifeos_motion_scope.dart           # inherited/configurable motion theme
  lifeos_motion_feedback.dart        # one-shot success/error state animations
  widgets/
    lifeos_pressable.dart            # press feedback, cancel/interruption safe
    lifeos_animated_visibility.dart # fade/size without jump
    lifeos_animated_list.dart       # stable-key list diff/entrance
    lifeos_motion_card.dart         # shared card/expand wrapper
    lifeos_skeleton.dart            # bounded loading animation
  navigation/
    lifeos_page_transitions.dart    # route transition definitions
    lifeos_branch_transition.dart   # only if branch-container migration justified

test/core/motion/
  motion_tokens_test.dart
  motion_preferences_test.dart
  pressable_widget_test.dart
  branch_navigation_test.dart
  feedback_state_test.dart

docs/motion/
  MOTION_GUIDELINES.md
  MOTION_COVERAGE_MATRIX.md
  QA_CHECKLIST.md
  IMPLEMENTATION_REPORT.md
```

### 4.3 Suggested stable public API

```dart
abstract final class LifeOsMotionTokens {
  static const Duration feedbackFast = Duration(milliseconds: 100);
  static const Duration micro = Duration(milliseconds: 160);
  static const Duration standard = Duration(milliseconds: 220);
  static const Duration medium = Duration(milliseconds: 300);
  static const Duration panel = Duration(milliseconds: 340);
  static const Duration expressive = Duration(milliseconds: 420);

  static const Curve standardCurve = Curves.easeOutCubic;
  static const Curve emphasizedCurve = Cubic(0.2, 0.0, 0.0, 1.0);
  static const SpringDescription selectionSpring = SpringDescription(
    mass: 1.0,
    stiffness: 430.0,
    damping: 37.0,
  );
}
```

The final code must import the correct Flutter libraries, obey the project's analyzer rules and compile against the installed SDK. This example defines an API direction; it does not require copying an untested snippet blindly.

### 4.4 Widget interface requirements

- `LifeOsPressable` accepts `child`, `onPressed`, `enabled`, `semanticsLabel`, optional haptic mode and motion preset. It must honor pointer cancel, disabled state, repeated taps, `dispose` and reduce-motion. Do not modify the gesture recognizer's interactive hit area while scaling visual content.
- `LifeOsAnimatedVisibility` has `visible`, `child`, optional `maintainState`, and explicit semantics behavior. No invisible overlay should intercept taps.
- `LifeOsMotionCard` supports `id`, `child`, `onTap`, optional transition source and unique Hero tag namespace. Existing `LifeOsSoftCard` and `LifeOsMintHeroCard` stay the visual source of truth.
- `LifeOsAnimatedList` uses stable domain IDs and a small diff, preserves current scroll position and avoids rebuilding unaffected rows. Do not animate every server snapshot as an initial-load sequence.
- `LifeOsMotionFeedback` consumes a unique effect event or a documented previous-to-current BLoC transition; never repeat success animation simply because the widget rebuilt.
- All controllers use `vsync`, check `mounted` when required and dispose correctly. Avoid nested controllers for the same transition.

### 4.5 BLoC example of authoritative feedback (pseudo-code)

```dart
BlocListener<TransactionBloc, TransactionState>(
  listenWhen: (previous, current) {
    // Compare the app's real immutable transaction status fields.
    // Trigger only on a distinct authoritative transition to success.
    return isNewlyConfirmed(previous, current);
  },
  listener: (context, state) {
    // Presentation-only feedback. Do not write transactions here.
    LifeOsFeedbackPresenter.of(context).showSuccess(
      message: 'Transaction saved',
    );
  },
  child: const TransactionScreenContent(),
)
```

Do not invent `isNewlyConfirmed` or `LifeOsFeedbackPresenter` as existing project APIs. Implement them only if appropriate after inspecting the actual BLoC state shape.

---

## 5. NAVIGATION AND ROUTE MOTION - HIGHEST RISK AREA

### 5.1 Preserve stateful shell behavior

The current router uses `StatefulShellRoute.indexedStack` with four persistent branches. This is important for scroll state, the calendar's selected date, form contents and navigation stacks. The default `indexedStack` route does **not** itself animate between branches; LifeOS presently adds `_SlidingShellViewport` around its shell.

**Recommended order:**

1. Keep the `StatefulShellRoute.indexedStack` and existing `_SlidingShellViewport` for the first iteration.
2. Move only timing, curve and motion-preference decisions into shared tokens. Fix rapid tab switching/reversal and avoid duplicate fade effects.
3. Test switching between all branch pairs, fast repeated taps, back navigation, auth redirect, deep links and the current dock selection indicator.
4. Consider custom `navigatorContainerBuilder` **only if** profiling/UX tests establish a material improvement. If migrated, preserve per-branch Navigator keys, offstage layout, ticker disabling, nested routing, focus and semantics. Feature-flag the migration and retain a rollback path.
5. Use `CustomTransitionPage`, a supported route transition or `Hero`/`OpenContainer` for **individual detail routes**, not as an excuse to rebuild the shell.

Reference: https://pub.dev/documentation/go_router/latest/go_router/StatefulShellRoute-class.html and the official custom example in Section 16.

### 5.2 Mapping for core journeys

| User journey | Preferred treatment | State constraint |
|---|---|---|
| Today -> Finance -> Planning -> Family | Dock pill slides; content lightly fades/translates by direction if unobtrusive | Preserve each branch's scroll and child stack |
| Dashboard finance card -> Finance page | Contextual card-to-page transform if source/destination coexist reliably; otherwise short route fade | Avoid opening a duplicate nested navigator or resetting finance selection |
| Transaction list -> review/detail | Container transform or targeted shared element; reverse on pop | Unique transaction ID/tag; no double transition |
| Planning calendar -> event detail | Hero for stable event marker/card OR shared-axis slide | Retain selected date, timezone and event state |
| Quick-add jewel -> create sheet | Press spring, one controlled panel open animation | Dismiss by swipe/back; keyboard/safe areas work |
| Login -> onboarding -> today | Shared axis for related pages; short fade for auth outcome | Auth guard and redirects take precedence over visual continuity |
| Notification -> transaction review | Short route transition | Deep links, cold start, authentication redirect remain valid |

### 5.3 Interruptibility tests

- Tap from tab 0 to 2, immediately to 1, then 3; the selected pill and body must agree.
- Tap the same tab repeatedly; current branch reset behavior remains as originally intended.
- Start opening a bottom sheet, then press back or swipe down; no stuck scrim or ghost touch target.
- Start a route transition, then trigger auth redirect; old page must not flash or leak sensitive content.
- Return from a detail view to a long list; item and scroll position should match the user's context.
- A Hero transition may be skipped if source item has been removed; fallback must be a valid normal transition.

---

## 6. FINANCE: INTEGRITY-FIRST MOTION

Finance is the most important place to avoid misleading animation. Scope includes `finance_page.dart`, transaction lists, quick entry, budget/fund cards, bank notifications and transaction review.

### 6.1 Must implement

1. Transaction item appearance on genuinely new items (fade + small translation); dedupe by stable ID, never by visible position.
2. Pending -> confirmed, pending -> failed, synchronization -> refreshed: clear textual/icon state transition; no fake green check before confirmation.
3. Amount change/summary refresh: use short, legible crossfade or a controlled numeric transition; keep raw displayed amount correct throughout; no intermediate misleading number.
4. Category selection and quick entry: pressed state, selected pill movement and short confirmation feedback. Do not delay a transaction submit call for animation.
5. Budget progress: animate from actual previous percentage to actual next percentage; clamp only drawing bounds, never change the underlying value or hide overspending.
6. Finance loading: skeleton only for currently unavailable data, not as a flashing replacement during an ordinary background refresh.
7. FCM/banking push: animate a truthful new alert once; handle duplicates, late events, reversals, offline caching, deep links and permission denial as separate functional states.

### 6.2 Do not implement

- Confetti, aggressive bouncing, flashing amount text or casino-style money effects.
- Counting to a displayed balance from zero on every screen entry.
- An irreversible success state based solely on a local optimistic tap.
- Animation that reorders a financial ledger unpredictably without keeping visible row identity.
- Notification animations that leak transaction contents over a locked/obscured app state.

### 6.3 Finance acceptance scenarios

- The amount and currency remain correct before/during/after all animations.
- A failed save visibly remains failed, with retry behavior intact.
- Receiving the same bank event twice does not retrigger false success or create duplicate rows.
- Rapid switching between finance tabs does not reset filters, text fields or scroll without intended behavior.
- Accessible names expose precise amounts and statuses independent of graphical animation.

---

## 7. OTHER FEATURES: INTERACTION CONTRACTS

### 7.1 Today dashboard

- Initial entry: selected hero card + up to 4-6 visible cards may enter sequentially only once per meaningful navigation, not on every BLoC emission.
- Content refresh: update changed regions in place; preserve existing cards and scrolling.
- Quick-create: center action has immediate press feedback, then a single sheet entrance; avoid scaling the full screen and blur in the same frame if it causes jank.
- Dashboard numbers: no random number rolling; use precise updates and optional gentle crossfade.

### 7.2 Calendar, planning and tasks

- Date selection: selected chip/background changes with a short spring or ease; the chosen date is always programmatically correct.
- Month/week/day switching: restrained shared-axis motion aligned with temporal direction; follow local calendar/timezone rules.
- Event detail: preserved date/time and form data on reverse transition.
- Task completion: checkbox checkmark + optional task row collapse only **after** authoritative completion state; support undo when domain supports it.
- Task reorder and assignments: animate stable-key positions; keep semantics readable and accessible; respect shared family privacy rules.
- Alarm screens: never postpone scheduled notification/alarm operation for an effect; alert accessibility and priority outrank animations.

### 7.3 Family and shared funds

- Member tile expansion and invite status use small motion.
- Invitation accepted/rejected animations reflect verified network state; no perceived authorization before permission changes complete.
- Family funds keep identical truthfulness rules to personal finance. Private schedules remain private; animation does not expose otherwise hidden data.

### 7.4 Vehicles, documents, utilities and daily life

- Maintenance status cards can expand in place; progress reflects actual time/distance values.
- Documents: reveal previews without showing private contents over a locked surface; preserve secure-vault behavior.
- Habits: small completion feedback; no endless attention-grabbing particles.
- Kitchen, groceries, notes and subscriptions: animate list diffs and bottom sheets, not whole-screen data on each update.

### 7.5 Notifications and errors

- Top toast may slide from top with opacity, but must never obscure a critical permission dialog or in-progress payment control.
- Error feedback should be calm and informative; reduce motion for accessibility; screen readers receive semantics independent of animation.
- Toast queue policy: dedupe equivalent foreground events, cap simultaneous surface count, handle route changes and cancellation without crashes.

---

## 8. THIRD-PARTY REPOSITORIES AND DEPENDENCY DECISIONS

Use these as **references**, not as code to copy wholesale. Inspect license, current release, maintenance, tests, Flutter/Dart constraints and platform support at implementation time.

| Project | URL | Primary value | Decision rule |
|---|---|---|---|
| Flutter `animations` | https://github.com/flutter/packages/tree/main/packages/animations | `OpenContainer`, shared axis, fade-through, fade | High priority if compatible and simpler than custom animation |
| Flutter `go_router` examples | https://github.com/flutter/packages/tree/main/packages/go_router/example | Stateful nested navigation and transitions | Required reference for shell customization |
| Flutter official samples | https://github.com/flutter/samples/tree/main/animations | Hero, physics, stagger, animation fundamentals | Reference and test patterns |
| `flutter_animate` | https://github.com/gskinner/flutter_animate | Quick decorative or entrance effects | Optional; avoid duplicating native widgets unnecessarily |
| Skeletonizer | https://github.com/Milad-Akarie/skeletonizer | Data loading surfaces | Good candidate for finance/dashboard loading |
| Rive Flutter | https://github.com/rive-app/rive-flutter | State-machine vector animations | Optional for branded onboarding/illustrations only |
| Lottie Flutter | https://github.com/xvrh/lottie-flutter | JSON micro-illustrations | Optional for one-shot success/empty states |
| Expressive M3 community | https://pub.dev/packages/expressive_m3 | Token/spring reference and experimental widgets | Evaluate separately; not an official Google Flutter package |

### Compatibility checkpoint

The inspected `pubspec.yaml` declares Dart `^3.10.0`, but the **installed** SDK, lockfile and package constraints must be checked locally. On pub.dev as inspected 2026-11-24, `animations` 3.0.0 requires Dart 3.12+, while 2.2.0 lists Dart 3.9 minimum. Do **not** hardcode the newest version into the project without confirming compatible constraints. Use `flutter pub outdated` and package release notes; keep dependency additions minimal.

A conservative initial implementation can use Flutter SDK primitives **without any new packages**. Add `animations` only for meaningful container/shared-axis cases; add Skeletonizer only if skeleton quality and performance are demonstrably better than existing loading widgets; add Rive/Lottie only with approved/licensed assets.

---

## 9. PERFORMANCE ENGINEERING RULES

### 9.1 Establish a baseline

- Run on at least one real Android mid-range device in **profile mode**; include iOS if available.
- Record model, OS, refresh rate, Flutter engine/runtime version, build mode, route and dataset size.
- Use Flutter DevTools Performance view; capture separate UI and raster frame time, janky frames, first-run shader behavior, memory and raster hotspots.
- Test with realistic data: many transactions, non-empty calendar, tasks and mixed card states. A blank demo screen is not enough.
- Report 60 Hz (~16.7 ms per frame) and 120 Hz (~8.3 ms per frame) budgets as **device-dependent goals**, not promises.

### 9.2 Optimization rules

- Prefer paint/compositor-friendly `Transform`, `SlideTransition`, `FadeTransition` and narrow `AnimatedBuilder` child subtrees.
- Place expensive static card content behind an appropriate `RepaintBoundary` **only after profiling**; excess boundaries may consume memory and layers.
- Avoid changing whole-screen layout on every animation tick; do not animate every cell of a large list.
- Limit simultaneous `BackdropFilter`, shadows, clipping, `saveLayer` and opacity group compositions, especially on Liquid Glass sheets/dock.
- Avoid animating complex charts via full-page rebuilds; isolate chart animation and preserve its axes/labels.
- Use `ListView.builder`/slivers for large datasets, stable keys and visibility-limited animation.
- Disable ticker work on offstage routes; do not retain running looping controllers in inactive navigator branches.
- Profile first-open and repeat-open separately; pre-warm heavy assets only when worthwhile, without increasing startup time.
- Avoid multiple nested animation packages applying overlapping fade/scale to the same element.

### 9.3 Measurement and gate

Provide a before/after comparison for: primary tab change, opening quick-create sheet, opening transaction detail, long finance list scrolling, calendar date change, and background push notification when testable.

**Acceptable:** comparable or better UI/raster frame distributions with no visible new jank on the representative test devices, and no substantial memory growth from sustained navigation.  
**Not acceptable:** a visually impressive transition that consistently drops frames, delays the user's tap, blocks UI, drains battery while idle or holds large live blur layers offscreen.

If no device is available, run analyzer/tests and clearly label performance validation **NOT RUN - DEVICE REQUIRED**. Never invent FPS metrics.

---

## 10. ACCESSIBILITY, INTERNATIONALIZATION AND USER CONTROL

1. Check both Android `disableAnimations` and iOS `reduceMotion`; configure semantics through a single tested presentation-level policy.
2. Reduced motion should preserve essential state changes. For instance: instant checked state + screen reader announcement instead of an animated checkmark.
3. Do not make content visible only after an animation completion callback if that would block assistive technology.
4. Maintain all minimum touch targets and focus order when visually scaling controls.
5. Do not rely exclusively on color, movement or haptics to express success, failure, selection or financial status.
6. Test light/dark themes, text scaling (including large accessibility fonts), compact density and high contrast modes already present in LifeOS.
7. Maintain Vietnamese and English localization; motion must not assume English text lengths or a fixed 1-line label.
8. Respect keyboard/screen reader navigation, `Hero` semantics and modal focus management.
9. Respect hardware/software animation settings and battery/performance constraints when known.
10. One-shot feedback must not play forever after app lifecycle pause/resume.

**Important technical note:** Flutter's `MediaQueryData.disableAnimations` does not by itself represent iOS Reduce Motion. Use platform accessibility features as well. A custom MediaQuery override is not guaranteed to change the behavior of every `AnimationController`; test the final implementation, not merely the boolean value.

---

## 11. IMPLEMENTATION PLAN - AUTONOMOUS EXECUTION PHASES

### Phase A - audit and baseline (P0)

**Work:** inventory animations, list high-risk routes and BLoC transitions, record test status and performance baselines.  
**Outputs:** baseline report + coverage matrix with current state; dependency decision proposal.  
**Gate:** no assumptions about current code; every proposed modification has an owner and reason.

### Phase B - motion foundation (P0)

**Work:** implement reusable duration/curve/spring tokens, reduced-motion policy, `LifeOsPressable` and transition helpers. Use native Flutter APIs first.  
**Outputs:** shared APIs, sample usage in one low-risk screen, unit/widget tests.  
**Gate:** all motion components handle tap cancel/repeat, interruption and dispose. Existing widgets continue to render identically when animation is disabled.

### Phase C - shell, dock and quick-create (P0)

**Work:** unify `_SlidingShellViewport`, Liquid Glass dock and toast tokens; refine interruptibility; animate quick-create without stacking unnecessary blur.  
**Outputs:** preserved branch state and reviewed route animation; navigation/widget tests.  
**Gate:** zero branch-stack regressions, no duplicate transition, all four tabs work under rapid interaction and back navigation.

### Phase D - finance and bank notifications (P0)

**Work:** transaction list diff, stable row entrance, amount/status transitions, budget progress, quick entry and authoritative success/error feedback; audit notification privacy.  
**Outputs:** finance motion and high-integrity state tests.  
**Gate:** duplicate event, network failure, offline, retry and deep link behavior covered; displayed amounts never mislead.

### Phase E - planning, tasks and family (P1)

**Work:** calendar direction motion, event detail, task completion and reorder, member tile/invitation response, shared fund states.  
**Outputs:** reusable patterns in actual feature pages and regression tests.  
**Gate:** selected date/task/family context stays intact after navigation, cancellation and async updates.

### Phase F - vehicles, utilities and polish (P1/P2)

**Work:** carefully apply list diff, card expansion and feedback to vehicles, subscriptions, documents and other utility pages; optionally branded onboarding/empty state animation.  
**Outputs:** motion coverage parity without gratuitous effects.  
**Gate:** no heavyweight package unless justified by a measured improvement and documented asset/license compliance.

### Phase G - quality hardening and handoff (P0)

**Work:** flutter analyze/tests, automated navigation tests, manual accessibility sweep, DevTools comparisons, rollback review and documentation.  
**Outputs:** final implementation report, coverage matrix, QA evidence, remaining limitations.  
**Gate:** acceptance matrix signed off or explicit documented exception per failing item.

**Execution discipline:** At each phase: inspect -> plan small patch -> implement -> format -> analyze -> test -> manual smoke-check -> record result -> continue. Stop unsafe changes, not the entire project, when an external credential or device is unavailable.

---

## 12. REQUIRED TEST MATRIX

Tests must validate behavior and semantics, not animation durations alone.

| Test ID | Scenario | Minimum assertion |
|---|---|---|
| NAV-01 | Switch all 4 primary tabs | Correct selected tab, body and dock pill synchronized |
| NAV-02 | Rapid tab changes during active animation | Final destination correct; no stale queued movement |
| NAV-03 | Switch away from long-scrolled finance list and back | Scroll state preserved |
| NAV-04 | Nested detail push/pop then branch switch | Per-branch navigator stack preserved |
| NAV-05 | Deep link from banking notification | Correct route/auth redirect; no duplicate open |
| NAV-06 | Press Android back / iOS swipe-back mid-transition | No crash, flash or unreachable route |
| SHEET-01 | Open, swipe-dismiss, reopen quick-create | Overlay removed, gestures and focus functional |
| SHEET-02 | Keyboard open when sheet shows form | No keyboard occlusion or unsafe scrolling |
| TX-01 | Transaction save success | Feedback exactly once after actual success state |
| TX-02 | Transaction save failure or timeout | No success animation; error/retry visible |
| TX-03 | Same bank event delivered twice | No duplicate transaction or duplicate success effects |
| TX-04 | Amount and balance update | Accurate value and currency throughout transition |
| TX-05 | Many new transactions while scrolling | Stable keys and scroll; no bulk stagger or jump |
| CAL-01 | Switch dates rapidly | Final date selected; data/transition direction aligned |
| CAL-02 | Event detail open/back | Event date/time and calendar position retained |
| TASK-01 | Complete task then undo (if supported) | State and checkmark reversible |
| FAMILY-01 | Invite pending/success/failure | Motion follows authoritative permission/network state |
| A11Y-01 | Android Remove animations | Nonessential motion off/reduced and state still clear |
| A11Y-02 | iOS Reduce Motion | Nonessential motion off/reduced and state still clear |
| A11Y-03 | Screen reader + large text | Usable labels, focus, hit targets and no clipping |
| PERF-01 | Scroll long finance ledger | No new sustained UI/raster spikes relative to baseline |
| PERF-02 | Open dock, sheet and glass surfaces | No consistent raster jank or retained live ticker |
| PERF-03 | 10 min idle after navigation | No unnecessary looping animations / obvious battery drain |
| TEST-01 | `flutter analyze` | No newly introduced analyzer errors |
| TEST-02 | `flutter test` | No new failing tests; failures documented with provenance |

### Testing guidelines

- Use `tester.pump()` and bounded `pump(Duration(...))` intentionally for spring tests. Some spring simulations may not settle predictably under `pumpAndSettle`; define a maximum and assert stable states rather than hanging.
- Inject test motion preferences instead of changing global platform state ad hoc when possible.
- Do not rely on exact pixel snapshots for every animation frame; reserve golden tests for stable resting states and reduced-motion states.
- Use accessibility/semantics assertions for button labels, loading status and completion/failure messaging.
- Test widget disposal while controllers run and test cancellation/interruptibility.
- Distinguish manual device checks from automated tests. Mark unexecuted checks as `NOT RUN` rather than `PASS`.

---

## 13. BUILD, QUALITY AND REPRODUCIBILITY COMMANDS

Start with the project's documented setup. Run only commands supported by the local toolchain and configuration.

```bash
git status --short
git branch --show-current
git log -1 --oneline
flutter --version
dart --version
flutter pub get
flutter pub outdated
flutter analyze
flutter test
```

For real performance measurement, use an available device and an appropriate configured flavor/environment:

```bash
flutter devices
flutter run --profile
```

If integration tests exist and are configured:

```bash
flutter test integration_test
```

Do not run Firebase deployment, change remote data, reset services or publish an app as part of this assignment.

### Recommended static checks

- Dependency package versions and SDK constraints are compatible with lockfile.
- No global `AnimationController` or controller retained in singleton BLoC/service.
- No duplicated `Hero` tags in simultaneously mounted Navigator scopes.
- All new controllers are disposed; `TickerMode` and offstage behavior verified.
- No duplicate success feedback after repeated BLoC state emissions.
- No hard-coded runtime accessibility or theme assumptions.
- No new unlicensed vector/JSON motion assets.

---

## 14. KNOWN RISKS AND MITIGATIONS

| Risk | Mitigation |
|---|---|
| Replacing indexed stack loses navigation history | Preserve current shell; consider migration only behind flag and regression tests |
| Dock animation and page animation conflict | One owner per visual region; central tokens; no double fade/slide |
| Excess glass blur causes raster-thread jank | Profile; freeze background blur if appropriate; animate a lightweight foreground |
| Spring controller outlives widget | `dispose`; `mounted` checks; no async callback after route removal |
| Replayed bank notifications trigger false success | Use stable event IDs and authoritative business state; separate receipt from confirmation |
| Animating balances creates inaccurate transient values | Crossfade only verified final values or show stable digits |
| Hero tag collision in nested navigators | Namespaced unique IDs, fallback to plain transition |
| Skeleton hides important cached data | Use stale-while-revalidate with current data visible where appropriate |
| Modal sheet becomes unreachable to accessibility | Correct focus, semantics, drag-dismiss and reduced-motion behavior |
| New package forces SDK upgrade | Keep native Flutter fallback; pin compatible major version |
| Animation increases battery use while app idle | No unnecessary looping tickers; use lifecycle/visibility management |
| Agent cannot profile due to no device | Mark blocker and finish static/widget tests; do not fabricate metrics |

---

## 15. ACCEPTANCE AND SIGN-OFF CHECKLIST

### Architecture and scope

- [ ] Local repository snapshot and baseline results recorded.
- [ ] Existing Clean Architecture and BLoC preserved; no Cubit introduced.
- [ ] Existing Firebase/banking/calendar/notification logic unchanged unless a verified bug fix was necessary.
- [ ] Motion tokens centralize timing/easing/spring and are actually used by components.
- [ ] No redundant or unreviewed heavy animation dependency added.
- [ ] Existing branding and Liquid Glass visual identity maintained.

### Functional and UX

- [ ] Bottom dock, route body and selected tab stay synchronized during rapid taps.
- [ ] Stateful branch navigators preserve scroll, back stack, form input and date/filter state.
- [ ] Quick-create and detail sheets can be canceled/reversed without stuck overlays.
- [ ] Transaction success/failure animations reflect authoritative results only.
- [ ] Numbers, amounts and currencies remain accurate during transitions.
- [ ] New/removed rows have stable identity; long lists do not replay mass entrance effects.
- [ ] Toast and notification behavior is deduplicated and privacy-aware.
- [ ] Calendar, task and family transitions retain business semantics.
- [ ] Transitions do not block actual actions while waiting for decorative completion.

### Accessibility and quality

- [ ] Android and iOS reduced-motion behavior implemented and tested.
- [ ] Screen readers can perceive all meaningful statuses without animation.
- [ ] Large text, dark mode, high contrast and touch targets pass smoke-check.
- [ ] `flutter analyze` reports no newly introduced errors.
- [ ] Focused widget/navigation tests pass; pre-existing failures clearly separated.
- [ ] Real-device profile measurements recorded when hardware exists; otherwise explicitly NOT RUN.
- [ ] No major new jank, memory leak, controller/ticker leak or excessive idle animations.
- [ ] Implementation notes, coverage matrix, package decisions and rollback strategy delivered.

**Release rule:** An unchecked high-integrity finance, accessibility or navigation item is a release blocker, not a cosmetic backlog item.

---

## 16. REFERENCE SOURCES AND RECOMMENDED READING

These links are for agent verification and engineering research. Check the relevant version before relying on implementation specifics.

### Official Flutter and Google-aligned references

1. Flutter `animations`: https://pub.dev/packages/animations
2. Flutter Material Motion patterns (package documentation): https://pub.dev/documentation/animations/latest/
3. Official `go_router` StatefulShellRoute API: https://pub.dev/documentation/go_router/latest/go_router/StatefulShellRoute-class.html
4. Official custom stateful shell example: https://github.com/flutter/packages/blob/main/packages/go_router/example/lib/others/custom_stateful_shell_route.dart
5. Official Flutter Hero animations: https://docs.flutter.dev/ui/animations/hero-animations
6. Official Flutter animation samples: https://github.com/flutter/samples/tree/main/animations
7. Flutter DevTools Performance view: https://docs.flutter.dev/tools/devtools/performance
8. Flutter performance best practices: https://docs.flutter.dev/perf/best-practices
9. Flutter rendering performance: https://docs.flutter.dev/perf/rendering-performance
10. Flutter `MediaQueryData.disableAnimations`: https://api.flutter.dev/flutter/widgets/MediaQueryData/disableAnimations.html
11. Flutter accessibility feature API: https://api.flutter.dev/flutter/dart-ui/AccessibilityFeatures-class.html
12. Material Design motion overview: https://m3.material.io/styles/motion/overview/how-it-works

### Source code and optional packages

13. Flutter packages repository: https://github.com/flutter/packages
14. Flutter Animate: https://github.com/gskinner/flutter_animate
15. Skeletonizer: https://github.com/Milad-Akarie/skeletonizer
16. Rive Flutter: https://github.com/rive-app/rive-flutter
17. Lottie Flutter: https://github.com/xvrh/lottie-flutter
18. Community expressive M3 package (NOT official): https://pub.dev/packages/expressive_m3
19. `animations` SDK-version history: https://pub.dev/packages/animations/versions
20. LifeOS source: https://github.com/danhhoa20005/life-os-superapp

---

## 17. REQUIRED AGENT COMPLETION REPORT FORMAT

At the end of the coding task, provide a real report, not a generic completion statement.

```text
LIFEOS MOTION IMPLEMENTATION REPORT

1. Repository snapshot:
   - Branch / commit:
   - Flutter / Dart versions:
   - Working tree state at start and finish:

2. Audit summary:
   - Existing motion retained:
   - Modified motion:
   - New components:
   - Deferred/nonessential effects:

3. Files changed (one-line purpose each):
   - ...

4. Dependencies changed and why:
   - ...

5. Feature coverage:
   - Today / navigation:
   - Finance / bank notifications:
   - Calendar / tasks:
   - Family:
   - Vehicles / utilities:

6. Verification:
   - flutter analyze: PASS / FAIL / NOT RUN + details
   - flutter test: PASS / FAIL / NOT RUN + details
   - integration tests: PASS / FAIL / NOT RUN + details
   - accessibility: PASS / FAIL / NOT RUN + details
   - performance device/profile results: BEFORE / AFTER or NOT RUN

7. Risks, blockers, regressions and follow-up work:
   - ...

8. Explicit acceptance checklist status:
   - ...

9. Review / rollback:
   - Commit(s) or diff path:
   - Feature flags:
   - How to revert safely:
```

### Final instruction to the agent

**Implement deliberately, not theatrically.** Reuse the working LifeOS motion foundation, make the system coherent at scale, preserve core functionality, prove quality with tests, document what you verified and finish every safe executable phase without routine confirmation prompts. If a claimed requirement cannot be validated with the available environment, state the limitation explicitly and do not call it complete.
