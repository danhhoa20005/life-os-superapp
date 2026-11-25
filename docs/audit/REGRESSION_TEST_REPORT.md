# REGRESSION & QUALITY ASSURANCE TEST REPORT — LIFEOS v3.27.0

- **Date:** `2026-11-25`
- **Overall Automated QA Status:** `PASS` (`0` Failures, `0` Skipped across Dart, Flutter, TypeScript & Live Firebase Emulator)

---

## 1. Executed Test Suites & Exact Results

| Layer | Command / Suite | Passed | Failed | Skipped | Status |
|---|---|---:|---:|---:|---|
| Dart Code Formatting | `dart format --output=none --set-exit-if-changed lib test` (`287` files) | `287` | `0` | `0` | **PASS** |
| Static Analysis | `flutter analyze --fatal-infos --fatal-warnings --no-pub` | `0` issues | `0` | `0` | **PASS** |
| Full Flutter Suite (Unit, Property/Fuzz 2,500+, BLoC, Motion, Accessibility, Widget & E2E Vertical Slices) | `flutter test --coverage --no-pub --timeout 45s` | **`287`** | **`0`** | **`0`** | **PASS** |
| Code Coverage (`coverage/lcov.info`) | Measured across entire `lib/` (`37,595 / 58,618` lines hit) | **`64.14%`** | — | — | **VERIFIED** |
| Cloud Functions TypeScript Build | `npm --prefix functions run build` (`tsc`) | `0` errors | `0` | `0` | **PASS** |
| Live Firestore Rules P0 Security & Attack Suite | `firebase/rules_tests/run_emulator_rules_tests.mjs` | **`12`** | **`0`** | **`0`** | **PASS** |
| Cloud Functions Family Invites Suite | `functions/lib/test/family_invites.test.js` | **`3`** | **`0`** | **`0`** | **PASS** |
| Live Firestore Emulator Banking Admin Store | `functions/lib/test/firestore_emulator.test.js` | **`1`** | **`0`** | **`0`** | **PASS** |
| Cloud Functions Real-Time Banking T01..T24 Suite | `functions/lib/test/realtime_banking.test.js` | **`8`** | **`0`** | **`0`** | **PASS** |
| Local AI Independent Multi-Stratum Evaluation | `python -u tools/financial_ai/evaluate_all_models.py` | Both `>=95%` F1 & OOD | `0` | `0` | **PASS** |

---

## 2. New v3.27.0 Regression & Property Test Coverage Added
1. `test/unit/v327_financial_security_property_test.dart`: **2,000+ seeded property-based tests** (`Random(20261125)`) for `apportionExactVndBigInt` / `apportionExactVndBasisPoints` (zero VND drift, zero-weight protection, NaN/negative rejection), `optimizeSettlementTransfers` (`sum == 0` enforcement, Exact DP vs Bounded Greedy), 9-state Family Fund lifecycle, separation-of-duties, single-transaction wallet->fund contribution, unbounded hydration (>25 items), Vehicle `ledger_audits`, recurring task `createdBy`, and Family `bannedUserIds`/`confirmSettlementRequest`/`operationId`.
2. `test/unit/v327_ai_ood_and_nlu_test.dart`: LFTQ v1 SHA-256 & `__ood__` bias verification on both models, `>= 95%` OOD rejection on 64 unseen prompts per model in Dart runtime, colloquial VND amount parsing, and 4-clause compound multi-intent parsing.
3. `test/unit/v327_voice_fsm_banking_privacy_test.dart`: 9-state `VoiceCaptureState` FSM, `sessionToken` stale filtering, lifecycle/debounce/editable transcript, ACK on `blockedOtpOrSecret`/`blockedConsentDisabled`, unified sign-out native wipe, Play/GitHub OTA flavor gating, `NativePrivacyScreenBridge`, and `AccountProfilePage` deletion flow at `360×800 @ 112%`.
4. `test/unit/v327_life_timeline_test.dart`: Cross-domain deduplication, reverse-chronological sorting, multi-token Vietnamese accent-folded search, domain filtering & responsive `360×800 @ 112%` rendering.
5. `firebase/rules_tests/run_emulator_rules_tests.mjs` (Tests 6–12): All 11 P0 business-attack scenarios executed live against Cloud Firestore Emulator.

---

## 3. End-to-End Business Scenario Coverage Matrix (Section 19)

| E2E Scenario | Automated Verification Status | Test Location |
|---|---|---|
| 1. Register -> Login -> Onboarding | **PASS** | `app_widget_test.dart`, `mvp_vertical_slice_test.dart` |
| 2. Create Wallet -> Record Income/Expense -> Balance & Audit | **PASS** | `mvp_vertical_slice_test.dart`, `fix_001_007_008_ledger_aggregation_vault_test.dart` |
| 3. Bank Notification -> AI Classification -> Confirm / Upgrade | **PASS** | `mvp_vertical_slice_test.dart`, `release_hardening_and_audit_v3_16_test.dart` |
| 4. Internal Wallet Transfer -> Zero Double-Counting | **PASS** | `fix_001_007_008_ledger_aggregation_vault_test.dart` |
| 5. Split Bill -> 2-Step Settlement -> Debt Conservation | **PASS** | `fix_002_003_006_family_invite_debt_test.dart`, `v327_financial_security_property_test.dart` |
| 6. Create Family -> 3-Mode Invite -> RBAC -> Remove & Ban | **PASS** | `top_toast_and_pro_max_redesign_test.dart`, `run_emulator_rules_tests.mjs` |
| 7. Fund Contribution -> Approve -> Execute -> Reconcile / Reverse | **PASS** | `v327_financial_security_property_test.dart`, `run_emulator_rules_tests.mjs` |
| 8. Calendar Event -> Reminder -> Edit -> Time-Block / Conflict | **PASS** | `alarm_system_accuracy_test.dart`, `product_expansion_ui_flows_test.dart` |
| 9. Vehicle ODO -> Maintenance -> Wallet Ledger Audit | **PASS** | `v327_financial_security_property_test.dart`, `vehicle_delete_test.dart` |
| 10. Document Vault -> AES-256-GCM Encrypt -> Tamper Check -> Delete Unlink | **PASS** | `fix_001_007_008_ledger_aggregation_vault_test.dart` |
| 11. Offline Mutation -> Outbox Queue -> Idempotent Sync & Conflict | **PASS** | `product_expansion_engines_test.dart` |
| 12. Concurrent Updates (2 Devices / `Promise.all` Invites & Funds) | **PASS** | `family_invites.test.js`, `realtime_banking.test.js`, `run_emulator_rules_tests.mjs` |
| 13. Sign Out -> Native Wipe -> Switch Account Isolation | **PASS** | `v327_voice_fsm_banking_privacy_test.dart` |
| 14. Legacy Plaintext Vault & Backup Schema Migration | **PASS** | `fix_001_007_008_ledger_aggregation_vault_test.dart`, `product_expansion_engines_test.dart` |
| 15. Encrypted Backup -> SHA-256 Preview -> Restore | **PASS** | `product_expansion_ui_flows_test.dart`, `product_expansion_engines_test.dart` |
| 16. Account Deletion -> Owner Guard -> Purge & Verify | **PASS** | `mvp_vertical_slice_test.dart`, `v327_voice_fsm_banking_privacy_test.dart`, `firestore_emulator.test.js` |
| 17. Physical Android Handset Hardware (Mic, Camera, Reboot, Doze) | **NOT_RUN** | Requires physical USB Android device (see `BLOCKED_TASKS.md`) |
