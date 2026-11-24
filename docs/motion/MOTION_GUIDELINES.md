# LifeOS Motion Design Guidelines (`LIFEOS-MOTION-2026-11-24`)

## 1. Core Philosophy
LifeOS combines an **Emerald-Mint Daylight Studio** visual language with **Apple Liquid Glass** navigation chrome and dense personal/family productivity hubs. Motion in LifeOS serves three strict purposes:

1. **Continuity:** Show spatial origin and destination across navigation branches, calendar periods, and modal sheets.
2. **Tactile Responsiveness:** Confirm touch intent immediately via velocity-preserving `SpringSimulation` without altering interactive hit targets.
3. **Financial & Operational Truthfulness:** Never simulate fake determinate progress, never count balances up from zero, and never show a confirmation effect before an authoritative BLoC/domain state transition.

---

## 2. Single Source of Truth (`lib/core/motion/lifeos_motion_tokens.dart`)

### Duration Hierarchy
| Token | Value | Primary Use Case |
| :--- | ---: | :--- |
| `instant` | `0 ms` | Android Remove Animations / explicit `LifeOsMotionMode.off` |
| `feedbackFast` | `100 ms` | Press highlight & Reduce Motion opacity crossfade |
| `micro` | `160 ms` | Checkbox mark, status pill swap, truthful numeric crossfade |
| `standard` | `220 ms` | Primary branch glide, segmented pill slide, top toast entry |
| `medium` | `300 ms` | Shared-axis detail routes, calendar period transition, progress bar |
| `panel` | `340 ms` | Liquid Glass sliding dock capsule & modal bottom sheet reveal |
| `expressive` | `420 ms` | Single milestone confirmation |
| `longEmphasis` | `520 ms` | Hard upper ceiling for any non-blocking emphasis |

Exit durations (`exitFast = 140 ms`, `exitStandard = 180 ms`) are intentionally shorter than entrance durations so motion never blocks the user's next tap.

### Curves & Physics Springs
- **`standardCurve` (`Curves.easeOutCubic`):** Fast, predictable entrance with zero overshoot.
- **`emphasizedCurve` (`Cubic(0.2, 0.0, 0.0, 1.0)`):** Material 3 Emphasized curve for shared-axis routes and progress bars.
- **`dockCapsuleCurve` (`Cubic(0.22, 1.04, 0.32, 1.0)`):** Controlled Liquid Glass capsule settle; automatically switches to `Curves.easeOutCubic` with zero droplet stretch when Reduce Motion is active.
- **`pressSpring` (`mass: 1.0, stiffness: 600, damping: 43`):** Near-critically damped `SpringSimulation` used by `LifeOsPressable` (`0.97–0.98` visual scale while outer hit target remains 100% unchanged).

---

## 3. Accessibility & Reduce Motion Contract (`lib/core/motion/lifeos_motion_preferences.dart`)
1. **Platform Precedence:** Both Android (`MediaQueryData.disableAnimations`) and iOS/macOS (`PlatformDispatcher.accessibilityFeatures.reduceMotion`) **always override** decorative user preferences.
2. **User Override:** Users can toggle **Giảm chuyển động (Reduce Motion)** at any time in the Appearance Studio sheet (`showLifeOsAppearanceSheet`), persisted via `ThemeBloc` (`MotionModeChanged`).
3. **Degradation Rules:**
   - Spatial translations (`SlideTransition`, `Transform.translate`, dock droplet stretch) collapse to `Offset.zero`.
   - Scale bounces (`Curves.easeOutBack`, press scale) collapse to `1.0`.
   - Looping background effects (`LifeOsSkeletonBox` shimmer, `UpcomingScheduleCycleCard` auto-rotation, `EventAlarmPage` halo pulse) stop their tickers under Reduce Motion and offstage `TickerMode(enabled: false)`.
   - Screen readers receive explicit `Semantics` (`liveRegion`, `selected`, `checked`, `value`) independent of visual animation.

---

## 4. Clean Architecture & High-Integrity Finance Rules
- **Layer Isolation:** Zero `AnimationController`, `Curve`, `SpringDescription`, or `Widget` imports exist in `domain/` or `data/`. Zero `Cubit` classes exist anywhere in the codebase.
- **No Optimistic Celebration:** `FinancePage` listens to `TransactionActionBloc` with a strict `listenWhen` state transition guard, and `LifeOsAnimatedStatusBadge` distinguishes `provisional`, `needsReview`, `matchedPaymentOrder`, `userConfirmed`, `verified`, and `reversed`.
- **Stable List Identity (`TX-05`):** `LifeOsStableListRegistry` tracks domain IDs so existing ledger/task rows never replay entrance animations on stream rebuilds, and batch syncs (`> 5` items) skip stagger to preserve scroll stability.
