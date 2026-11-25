# PROJECT AUDIT — LIFE OS v3.26.0+44 BASELINE

## 1. Repository & Runtime Snapshot
- **Branch / HEAD:** `main` @ `4bc371ef1c3f0b0029f28a6d44228f32f6b6aabd` (clean working tree)
- **Baseline Automated Tests:** `213/213` PASS, `flutter analyze --fatal-infos --fatal-warnings`: `0` issues
- **Navigation Structure (`lib/app/app_router.dart`):**
  - 5 primary shell branches (`StatefulShellRoute.indexedStack`): `/today` (`Hôm nay`), `/finance` (`Tài chính`), `/planning` (`Lịch & Việc`), `/family` (`Gia đình`), `/menu` (`Menu`).
  - 26 authenticated sub-routes wrapped in `_ScopedAuthenticatedProviders`.
- **Native Bridges (`MainActivity.kt`):**
  1. `vn.lifeos.app/bank_listener_methods` + `bank_listener_events` (`BankNotificationListenerService.kt`)
  2. `vn.lifeos.app/home_widgets` (`LifeOsHomeWidgets.kt` — 4 interactive AppWidgets)
  3. `vn.lifeos.app/voice_assistant` (`LifeOsSpeechRecognizerHelper.kt`)
  4. `vn.lifeos.app/app_updater` (OTA SHA-256 + signing cert lineage check)
  5. `vn.lifeos.app/secure_vault` (`LifeOsSecureVault.kt` — Android Keystore AES-256-GCM)
  6. `vn.lifeos.app/alarm_scheduler` (`LifeOsAlarmScheduler.kt`)
  7. `vn.lifeos.app/device_calendar` (`LifeOsDeviceCalendar.kt`)
  8. `vn.lifeos.app/permissions`

## 2. Key Architectural Findings
1. **Data Truncation in Financial Rollups (`FIX-001`):** `DashboardRepositoryImpl` consumes `watchTransactions` which defaults to `limit = 100`, truncating monthly income/expense totals whenever a user exceeds 100 monthly transactions. `TodayPage` also filters `TransactionListBloc.allTransactions` without `t.isConfirmedInLedger`.
2. **Client Join Permission Deadlock & Invite PII Exposure (`FIX-002`, `FIX-003`):** `FamilyRepositoryImpl.joinFamilyByInvite` calls `tx.get(familyRef)` inside a client Firestore transaction before `uid` is in `memberIds`, triggering `PERMISSION_DENIED` under `firestore.rules:365`. `family_invites/{code}` also stores raw `inviteeName`/`inviteeContact` without atomic `usedCount`/`maxUses` enforcement.
3. **Silent Fallthrough in Money Split & Naive Substring Member Match (`FIX-004`, `FIX-005`):** Invalid percentage sums (`60% + 50%`), mismatched exact totals, and oversized private extras silently fall through to `SplitMethod.equal`; `_resolveParticipantId` uses `.contains(...)` and maps `'anh'`/`'em'` to `currentUserId`.
4. **Ghost `'bank_transfer'` Node in `DebtSimplifier` & Unused `settlement_requests` (`FIX-006`):** Auto-settled bank transfers create a `'bank_transfer'` creditor node in `DebtSimplifier.summarize`; two-step `settlement_requests` rules exist in `firestore.rules` but are unwired in Dart.
5. **Incomplete `ledger_audits` & Mutable Verified Fields (`FIX-007`):** Wallet transfers, reversals, provisional approvals, and bank notifications do not consistently update `lastAuditId` / `ledger_audits`; `firestore.rules` allows updating `transactions/{txId}` fields even when `verification == 'verified'`.
6. **Plaintext Local Document Attachments (`FIX-008`):** `SparkSafeFileStorageService` writes raw bytes to `secure_doc_vault` without AES-256-GCM file encryption, `DocumentVaultRepositoryImpl` is not wired to `FileStorageService` on delete, and `AndroidManifest.xml` lacks `android:allowBackup="false"`.
7. **APK Size Root Cause (`97.59 MB`):** `73.91 MB` (`75.7%`) comes from bundling 3 ABIs (`x86_64`, `arm64-v8a`, `armeabi-v7a`) in a single Fat APK, `7.73 MB` from unminified DEX (`isMinifyEnabled = false`), and `14.43 MB` from unoptimized PNG/JPG assets.
