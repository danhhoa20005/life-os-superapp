# MASTER AUDIT REPORT — LIFEOS SUPER APP (v3.27.0 ENGINEERING)

- **Audit Date:** `2026-11-25`
- **Repository:** `https://github.com/danhhoa20005/life-os-superapp` (`g:\superapp`)
- **Base Tag / Commit:** `v3.26.0+44` (`4bc371ef1c3f0b0029f28a6d44228f32f6b6aabd`) + verified local pre-v3.27.0 changes (Center `+` Bottom Bar, 32 Nano Banana 2D icons, FIX-001..008, 11 product modules)
- **Toolchain Verified:** Flutter `3.47.0` (stable), Dart `3.13.0`, Node `v24.11.1`, OpenJDK `21.0.10 LTS`, Firebase CLI `15.27.0`, Python `3.14.7`

---

## 1. Executive Audit Findings

Direct line-by-line inspection across `firestore.rules`, `functions/src/`, `lib/`, `android/`, and `tools/financial_ai/` identified **22 genuine, verified engineering issues** (`9` P0, `8` P1, `4` P2, `1` P3) that must be resolved before `v3.27.0` can be considered production-ready.

### Critical P0 Findings Confirmed on Local Source
1. **`AUD-001` (`firestore.rules:532-554`):** Arbitrary Family Fund `balanceMinor` tampering by any plain member; unvalidated `expenses.status` allowing self/auto-approval on create; no state transitions, field immutability, separation of duties, or atomic balance coupling on `funds` / `contributions` / `expenses`; zero `fund_audits`.
2. **`AUD-002` (`firestore.rules:642-678`):** Any debtor can unilaterally forge a confirmed `settlements` document without creditor confirmation, putting another member into fake debt; unlimited duplicate `rev_*` contra-reversals possible.
3. **`AUD-003` (`firestore.rules:623-639`):** `split_bills` does not validate that `sharesByUserId.keys()` are actual family members, and managers can delete `'locked'`/`'settled'` bills, corrupting Debt Simplifier history.
4. **`AUD-004` (`firestore.rules:564-570`, `611-620`):** Any member can overwrite `ownerId` on another member's `availability` slot or `uploadedBy` on another member's shared `documents/{docId}` and delete it.
5. **`AUD-005` (`firestore.rules:420-531`):** Removed members can re-join via unrevoked `reusableGroup` invite codes previously read from `families.pendingInvites`; `families.create` does not constrain `memberIds == [auth.uid]`; admin `update` lacks `affectedKeys().hasOnly(...)`.
6. **`AUD-006` (`family_funds_page.dart:976-979, 1721-1768`, `budget_repository_impl.dart:66-75, 306-389`):** Approve/Reject UI shown to plain members; `canAutoApprove` trusted for family funds; non-atomic 2-transaction wallet deduction + fund credit; `.limit(10).get()` truncating fund histories; only 3 expense states instead of full 9-state auditable lifecycle.
7. **`AUD-007` (`notifications_repository_impl.dart:1546-1669`, `account_profile_page.dart`):** Account deletion deletes Firestore data *before* `current.delete()` and swallows `requires-recent-login`, leaving zombie auth accounts; breaks for family owners under `firestore.rules:491`; misses 5 personal subcollections + `fuel_logs` + server-only collections; no Delete Account entry on `AccountProfilePage`.
8. **`AUD-008` (`auth_bloc.dart:411-429`, `BankNotificationListenerService.kt`, `LifeOsAlarmScheduler.kt`, `LifeOsHomeWidgets.kt`):** Sign-out / account switch does NOT disable/wipe the plaintext SQLite bank queue (`lifeos_bank_signal_queue.db`), alarm daemon prefs (`PREFS_HYDRATION_DAEMON`, `PREFS_MED_DAEMON`), or lock home widgets — causing cross-account bank & command leakage. Also un-ACKed early returns in `notifications_repository_impl.dart:442, 461`.
9. **`AUD-009` (`MainActivity.kt`, `LifeOsHomeWidgets.kt`, `backup_rules.xml`, `data_extraction_rules.xml`):** Zero `FLAG_SECURE` / recents screenshot protection anywhere in Android; `lifeos_bank_signal_queue.db` and `lifeos_bank_listener_prefs.xml` omitted from `data_extraction_rules.xml`.

### High-Priority P1 Findings Confirmed on Local Source
10. **`AUD-010` (`vehicle_repository_impl.dart:414-417, 545-548`, `firestore.rules:82-86`):** `VehicleRemoteDataSource` mutates `wallets.balanceMinor` without `lastAuditId`/`ledger_audits` (active `permission-denied` defect), and `firestore.rules` permits reusing an existing `lastAuditId`.
11. **`AUD-011` (`task_repository_impl.dart:180-204`, `firestore.rules:556-604`):** Recurring task spawn by an assignee fails `createdBy == auth.uid`; `tasks` assignee can rewrite `title`/`dueAt`; `shared_events`/`vehicles`/`bills` omit `ownerId` immutability.
12. **`AUD-012` (`functions/src/bankingEngine.ts:662-674`, `firestoreStore.ts:207-224, 307`, `index.ts:284-290`, `familyInvites.ts:783-793`):** Missing `lastAuditId` on `upsertWallet`, `deltaMinor` invariant drift on `accumulatedMinor > 0`, missing `connected + granted` check on `reconcileBankConnectionViaApi`, empty-string `subAccount` match bug, missing `email_verified` check.
13. **`AUD-013` (`smart_money_split_ai_engine.dart:289-380`):** `apportionExactVnd` silently converts invalid/negative/NaN weights instead of strict validation + zero-weight tie-break guard; `optimizeSettlementTransfers` omits `sum(netBalance) == 0` conservation check and overclaims Greedy optimality.
14. **`AUD-014` (`tools/financial_ai/train.py`, `evaluate.py`, `train_money_split_ai.py`, `eval_report.json`):** Financial AI OOD rejection is **60.0%** (53.3% on unseen OOD) due to 25-sample OOD exposure, zero bias, and `T* = 0.56` sharpening floor; Money Split AI OOD test has only 10 leaked paraphrases (drops to **55–75%** on unseen chatter & single-person tx near-OOD); runtime thresholds mismatch evaluation thresholds.
15. **`AUD-015` (`LifeOsSpeechRecognizerHelper.kt`, `MainActivity.kt:346-355, 1183-1190`, `voice_smart_capture_sheet.dart`):** No formal 9-state Voice FSM; 5 overlapping booleans; `isAwaitingVoicePermissionOrDialog` stuck `true` on dialog fallback; missing `WidgetsBindingObserver` & `LifeOsWidgetQuickOverlayActivity.onStop()` mic release.
16. **`AUD-016` (`LifeOsAlarmScheduler.kt:933-961`, `LifeOsDeviceCalendar.kt:294-315`, `LifeOsSecureVault.kt:32-80`):** Medication daemons not rolled over on reboot/timezone change; CalendarContract all-day events written with local epoch instead of UTC midnight; SecureVault missing `@Synchronized` & AAD key binding on `writeSecret`.
17. **`AUD-017` (`android/app/build.gradle.kts`, `AndroidManifest.xml:5, 10`):** No `github` vs `play` distribution flavors; `REQUEST_INSTALL_PACKAGES` and `USE_EXACT_ALARM` sit in main manifest, blocking Google Play compliance.

### Medium / Structural Findings (`P2` / `P3`)
18. **`AUD-018` (`pubspec.yaml:7-8, 19, 4`):** SDK lower bounds (`^3.10.0` / `>=3.24.0`) conflict with `pubspec.lock` (`>=3.13.0` / `>=3.47.0`); unbounded `intl: any`; version still `3.26.0+44`.
19. **`AUD-019` (`.github/workflows/ci.yml`):** Top-level `permissions: contents: write` too broad; missing `dart format --output=none --set-exit-if-changed`, `flutter test --coverage`, and Play `.aab` vs GitHub split-ABI `.apk` flavor build gates.
20. **`AUD-020` (`BankNotificationListenerService.kt:235-238`):** Kotlin `OTP_REGEX` narrower than Dart `OtpRedactor` (missing `s-otp`, `m-otp`, `digital otp`, `cvc`, `3ds`, PAN masking).
21. **`AUD-021` (`firestore.rules:14-18, 62-64, 139-166`):** `transactions` verified lock misses `isRefund`, `occurredAt`, `monthKey`, `balanceAfterMinor`, `splitLines`; `deletionInProgress` can be toggled back to `false`.
22. **`AUD-022` (`Section 20 — Life Timeline`):** Missing unified read-only cross-domain `Life Timeline` view aggregating Transactions, Calendar Events, Tasks, Reminders, Vehicle Maintenance, Bills, Family Updates & Goals chronologically without duplicating data.
