# BASELINE TEST REPORT — PRE-v3.27.0 AUDIT SNAPSHOT

- **Snapshot Date:** `2026-11-25`
- **Base Commit:** `4bc371ef1c3f0b0029f28a6d44228f32f6b6aabd` (`v3.26.0+44`) + preserved local UI/engineering upgrades (Center `+` Bottom Bar, 32 Nano Banana 2D icons, `FIX-001`..`FIX-008`, 11 expansion modules).

| Check | Command | Baseline Result |
|---|---|---|
| Static Analysis | `flutter analyze --fatal-infos --fatal-warnings --no-pub` | **PASS** (`0` issues) |
| Flutter Test Suite | `flutter test --no-pub` | **PASS** (`260 / 260` passed, `0` failed, `0` skipped) |
| Cloud Functions Build & Unit Tests | `npm --prefix functions run build && npm --prefix functions test` | **PASS** (`11 / 11` passed) |
| Live Auth + Firestore Emulator Suite | `firebase emulators:exec --only auth,firestore ...` | **PASS** (`17 / 17` passed across 4 suites, `0` skipped) |
| Production Web Build | `flutter build web --release --no-pub` | **PASS** (`build/web`) |
| Android Split-ABI Release APK | `flutter build apk --release --split-per-abi --no-pub` | **PASS** (`app-arm64-v8a-release.apk` = `36.62 MB`, `-62.48%` vs `97.59 MB` v3.26.0 fat APK) |
| Financial AI OOD Rejection (`eval_report.json`) | Existing `evaluate.py` (20 OOD) / 15 unseen OOD | **FAIL** (`60.0%` reported / `53.3%` unseen — below `95%` target) |
| Money Split AI Unseen OOD Rejection | 20 unseen chatter + single-person tx OOD | **FAIL** (`55.0%–75.0%` unseen — reported `100%` leaked on 10 near-duplicate prompts) |
| `firestore.rules` Family Funds / Settlements / Docs Attack Tests | Static Audit | **FAIL** (9 P0 security loopholes unguarded prior to Phase 1) |
| Android `playRelease` AAB Flavor Separation | `android/app/build.gradle.kts` | **NOT_RUN / MISSING** (`REQUEST_INSTALL_PACKAGES` still in main manifest) |
| Physical USB Android Hardware Runtime | Hardware sensors / Doze / Boot | **NOT_RUN** (No physical USB device connected) |
