# IMPLEMENTATION PLAN — LIFEOS SUPER APP v3.27.0 (DAG EXECUTION)

## Execution Architecture & File-Ownership Isolation

All active engineering waves execute strictly against a clean local checkpoint branch `agy/v3.27.0-upgrade` (keeping `main` at `4bc371e` untouched and performing zero remote pushes/deploys without user authorization). Existing local user changes (Center `+` Bottom Bar & 32 Nano Banana 2D icons) are strictly preserved.

### Wave 1 — 3 Parallel Isolated Worktree Streams (Zero File Overlap)
1. **`DEV-SEC-FUNDS-RULES` (Worktree 1 — Phases 1 & 2):**
   - Owns: `firestore.rules`, `lib/features/budgets/**`, `lib/features/family/{data,presentation/pages/family_funds_page.dart}`, `lib/features/vehicles/data/repositories/vehicle_repository_impl.dart`, `lib/features/tasks/data/repositories/task_repository_impl.dart`, `lib/core/utils/smart_money_split_ai_engine.dart`, `functions/src/**`, `firebase/rules_tests/run_emulator_rules_tests.mjs`, `test/unit/v327_financial_security_property_test.dart`.
   - Delivers: `AUD-001`..`AUD-006`, `AUD-010`..`AUD-013`, `AUD-021` + 11 live Firestore Emulator attack tests + 2,000+ seeded financial property tests.
2. **`DEV-AI-OOD-EVAL` (Worktree 2 — Phase 4):**
   - Owns: `tools/financial_ai/**`, `assets/models/**`, `lib/features/financial_ai/**`, `test/unit/v327_ai_ood_and_nlu_test.dart`.
   - Delivers: `AUD-014` — disjoint `>=250`-sample multi-stratum OOD sets for BOTH `Financial AI` and `Money Split AI`, retrained INT8 `.ftq` models with explicit `__ood__` class + positive bias + leak-free `T* >= 0.85` calibration, unified runtime OOD policy (`>= 95%` OOD rejection & `>= 95%` Macro F1), full evaluation report JSONs.
3. **`DEV-ANDROID-VOICE-PRIVACY-FLAVORS` (Worktree 3 — Phases 3, 5, 10, 11, 13):**
   - Owns: `android/**`, `lib/core/services/{native_voice_assistant_bridge,android_notification_bridge,native_app_updater_bridge,native_privacy_screen_bridge}.dart`, `lib/core/widgets/voice_smart_capture_sheet.dart`, `lib/features/notifications/data/repositories/notifications_repository_impl.dart`, `lib/features/authentication/presentation/{bloc/auth_bloc.dart,pages/account_profile_page.dart}`, `test/unit/v327_voice_fsm_banking_privacy_test.dart`.
   - Delivers: `AUD-007`, `AUD-008`, `AUD-009`, `AUD-015`, `AUD-016`, `AUD-017`, `AUD-020` — `github`/`play` flavors, `FLAG_SECURE`, encrypted SQLite bank queue + TTL + dead-letter + sign-out wipe, 9-state Voice FSM, reboot/timezone med+water daemon rollover, UTC all-day calendar fix, hardened SecureVault, and safe Account Deletion UI/repo flow.

### Wave 2 — Lead Integration, `Life Timeline`, DI/Router/CI & Full Verification (Phases 14–16)
1. Cherry-pick all 3 verified worktree commits sequentially onto `agy/v3.27.0-upgrade` and verify zero conflict & clean scope.
2. Implement `AUD-022` (`LifeTimelineEngine` + `LifeTimelinePage` `/life-timeline`, wired cleanly without duplicating data).
3. Wire `FamilyRemoteDataSource` + `NativePrivacyScreenBridge` in `dependency_injection.dart`, update `pubspec.yaml` (`AUD-018`), and harden `.github/workflows/ci.yml` (`AUD-019`).
4. Run full verification gates:
   - `dart format --output=none --set-exit-if-changed lib test`
   - `flutter analyze --fatal-infos --fatal-warnings --no-pub`
   - `flutter test --coverage --no-pub`
   - `npm --prefix functions run build` + `firebase emulators:exec --only auth,firestore` (all attack & backend suites)
   - `flutter build web --release --no-pub`
   - `flutter build apk --release --flavor github --split-per-abi --no-pub`
   - `flutter build appbundle --release --flavor play --no-pub`
   - Verify `git diff --check` & measure final APK/AAB sizes + SHA-256 checksums.

### Wave 3 — Phase 23 Audit Handover Suite & `CHANGELOG.md`
Generate all 10 required handover reports in `docs/audit/` and root `CHANGELOG.md` with honest `VERIFIED / PASS / FAIL / PARTIAL / NOT_RUN / BLOCKED` statuses.
