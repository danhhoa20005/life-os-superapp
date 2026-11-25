# Changelog — LifeOS Super App

All notable changes to LifeOS Super App are documented in this file.

## [3.27.0+45] — 2026-11-25 (Local Verified Release Candidate on `agy/v3.27.0-upgrade`)

### Security & Financial Integrity (P0)
- **Hardened `firestore.rules` Family Funds & Financial Ledgers (`AUD-001`..`AUD-005`, `AUD-010`, `AUD-011`, `AUD-021`):**
  - Enforced `balanceMinor == 0` on fund creation and atomic `!exists && existsAfter` `fund_audits` balance math (`previous + delta == new`) linked to `contributions` and 9-state `expenses` (`draft -> pending_approval -> approved -> executed -> reconciled`, plus `rejected`, `cancelled`, `disputed`, `reversed`) with manager separation-of-duties (`requesterId != auth.uid`).
  - Blocked unilateral debtor `settlements` creation, unverified `'bank_transfer'` settlement forgery, and duplicate reversal replay; enforced creditor receipt or atomic 2-step `settlement_requests` (`stl_req_<id>`) and single deterministic `rev_<origId>` reversal.
  - Enforced member-only keys on `split_bills.sharesByUserId`, forbade deleting `locked`/`settled` bills for all roles, locked `ownerId`/`uploadedBy` immutability on `availability`, `documents`, `shared_events`, `vehicles`, and `bills`, added `bannedUserIds` re-join prevention, tightened `wallets` audit verification, extended locked fields on `verified` transactions, and made `deletionInProgress: true` monotonic.
- **Ledger & Math Guarantees (`AUD-006`, `AUD-013`):**
  - Unified personal wallet debit + family fund contribution into a single atomic `runTransaction` writing both `ledger_audits` and `fund_audits`; removed silent `.limit(10)` fund history truncation; enforced role & separation-of-duties controls on `FamilyFundsPage`.
  - Fixed `VehicleRemoteDataSource` (`recordMaintenance`, `payRecurringBill`) to emit `LedgerIntegrityEngine` audits + `lastAuditId`, and fixed `TaskRemoteDataSource` recurring task `createdBy` attribution.
  - Hardened `SmartMoneySplitAiEngine.apportionExactVnd` / `apportionExactVndBigInt` + added `apportionExactVndBasisPoints` with strict NaN/negative rejection and zero-weight protection; enforced `sum(netBalance) == 0` on `optimizeSettlementTransfers` with Exact Zero-Sum Subset DP (`M <= 12`) and Bounded Greedy heuristic (`M > 12`).
- **Cloud Functions (`AUD-012`, `AUD-007`):**
  - Synchronized `lastAuditId` & exact `deltaMinor` in `bankingEngine.ts` / `firestoreStore.ts`, tightened `subAccount` matching, required `status === 'connected' && consentStatus === 'granted'` in `reconcileBankConnectionViaApi`, enforced `email_verified` & masked contacts in `familyInvites.ts`, and added server-authoritative `deleteUserAccountData` callable.
- **Privacy, Multi-Account Isolation & Safe Account Deletion (`AUD-007`, `AUD-008`, `AUD-009`, `AUD-020`):**
  - Encrypted `LifeOsBankSignalQueueDb` SQLite `title`/`body` with Android Keystore `AES-256-GCM` (`LifeOsSecureVault`), expanded Kotlin OTP/PIN/CVV/PAN masking & promo filtering, added TTL purge & dead-letter cap (`5`), fixed un-ACKed early returns on blocked notifications, excluded bank DB/prefs in `backup_rules.xml` & `data_extraction_rules.xml`.
  - Added unified native wipe on sign-out across bank queue, consent prefs, home widgets (with `is_signed_out` action lock), alarm daemons (`PREFS_HYDRATION_DAEMON`, `PREFS_MED_DAEMON`), and cached files.
  - Added `NativePrivacyScreenBridge` (`FLAG_SECURE` + `setRecentsScreenshotEnabled`) and enabled `FLAG_SECURE` by default on `LifeOsWidgetQuickOverlayActivity`.
  - Added visible Account Deletion flow on `AccountProfilePage` with multi-member family-owner pre-check (`FAMILY_OWNER_TRANSFER_REQUIRED`), recent-login check (`REQUIRES_RECENT_LOGIN`), and full subcollection cleanup (`monthly_summaries`, `automation_rules`, `automation_audits`, `source_claims`, `vehicles/{id}/fuel_logs`).

### Local Vietnamese AI (`AUD-014`)
- Retrained both quantized `INT8 LFTQ v1` FastText models with an explicit `__ood__` rejection class, learned positive OOD prior bias, and leak-free `T* >= 0.85` temperature calibration on strictly disjoint multi-stratum OOD datasets (`0.0%` leakage verified):
  - **Financial AI (`v3.0.0`, `984.37 KB`):** Held-out **Macro F1 `97.72%`** · Unseen 4-stratum **OOD Rejection `97.94%`** (`332/339`, up from `60.0%`) · AUROC `0.9947` · Warm Dart latency P50 `0.407 ms`.
  - **Money Split AI (`v2.0.0`, `409.00 KB`):** Held-out **Macro F1 `96.80%`** · Unseen 5-stratum **OOD Rejection `97.73%`** (`431/441`, incl. 110 single-person transaction near-OOD) · AUROC `0.9931`.

### Voice Assistant, Android Native & Dual-Flavor Distribution (`AUD-015`..`AUD-019`)
- Implemented formal 9-state `VoiceCaptureState` FSM across Kotlin, `NativeVoiceAssistantBridge` (`sessionToken` filtering), and `VoiceSmartCaptureSheet` (`WidgetsBindingObserver`, 250ms debounce, always-editable transcript); fixed `LifeOsWidgetQuickOverlayActivity.onStop()` mic release and inline fallback flag reset.
- Fixed `LifeOsAlarmScheduler` reboot/timezone rollover for medication & hydration daemons, fixed `LifeOsDeviceCalendar` UTC midnight all-day event encoding/decoding, and hardened `LifeOsSecureVault` key synchronization & AAD binding.
- Split Android distribution into **`github`** (Split-ABI OTA APKs with `REQUEST_INSTALL_PACKAGES`) and **`play`** (Google Play `.aab` with **zero** `REQUEST_INSTALL_PACKAGES` and **zero** `USE_EXACT_ALARM`, OTA self-update disabled).
- Reduced primary `arm64-v8a` release APK from **`97.59 MB` (`v3.26.0`) to `36.89 MB` (`-62.20%`)** via `--split-per-abi`, R8 code/resource shrinking, right-sized rasters, and Flat 2D icons.

### UI/UX & Product Expansion (`AUD-022`)
- Centered the primary emerald **`+`** action button dead-center of the bottom navigation bar (`Hôm nay · Tài chính · [ + ] · Lịch & Việc · Gia đình`) and moved `Menu` to a 1-tap header action.
- Replaced all 32 legacy 3D glossy icons with cohesive Nano Banana Flat 2D Duotone icons (`0.80 MB` total) and simplified `BananaGlassIcon` to crisp 2D flat squircles.
- Added **Life Timeline** (`/life-timeline`) aggregating live cross-domain activity chronologically without duplicating business records, plus Smart Inbox, Global Search & Command Palette, Receipt Scanner & Itemized Split, Smart Automation Studio, Encrypted `.lfbk` Backup & Restore, Cross-Domain Life Insights, 7/30/90-day Cashflow Forecast, Subscription Intelligence, Vehicle Fuel/TCO, Calendar Time-Blocking & `OfflineOutboxService`.
- Hardened `.github/workflows/ci.yml` with least-privilege permissions, `dart format --set-exit-if-changed`, `flutter test --coverage`, dual-flavor builds, and live Auth + Firestore Emulator security gates.

## [3.26.0+44] — 2026-11-25
- Baseline release (`4bc371ef1c3f0b0029f28a6d44228f32f6b6aabd`): Money Split Offline AI v1, upstream SpeechBroker fixes, and 18-screen UI polish (`97.59 MB` fat APK).
