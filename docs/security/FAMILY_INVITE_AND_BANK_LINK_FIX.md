# Security & Data-Integrity Remediation Notes — Findings 2, 3 & 7

**Baseline:** `efb4d29` (`v3.27.0`)  
**Deployment status:** Local workspace changes only. Production Firebase Security Rules and Cloud Functions have **NOT** been deployed by this task.

---

## Finding 2 — Targeted Family Invite Recipient Binding

### Architectural Authority Decision
- **Chosen authority:** Keep **Direct-Firestore** as the default app path (matching `lib/bootstrap.dart`, `configureDependencies()`, and Spark-plan support) and make **`firestore.rules`** the strict server-side authority, while keeping Cloud Function `joinFamilyByInvite` (`functions/src/familyInvites.ts`) synchronized on the exact same verification rules.
- **Why this over forcing Cloud Functions-only:** `lib/bootstrap.dart` initializes dependencies without `functionsInvokerOverride`, meaning production builds default to Direct-Firestore batch commits on the Spark-compatible path. Locking `firestore.rules` guarantees that neither current clients, older clients, nor raw Firestore REST/SDK calls can bypass targeted recipient binding or split member/useCount updates.

### Rules & Server Enforcement (`firestore.rules` & `functions/src/familyInvites.ts`)
- A targeted invite is identified whenever `inviteKind == 'targeted'`, `isTargeted == true`, or any of `inviteeUid`, `inviteeEmail`, or `intendedRecipientHash` is a non-empty string.
- Targeted invite creation fails closed unless `maxUses == 1` and at least one of `inviteeUid`, `inviteeEmail`, or `intendedRecipientHash` is set.
- Acceptance authorization (`isAuthorizedForInvite` in `firestore.rules` and `FamilyInviteCoordinator.joinFamilyByInvite` in `functions/src/familyInvites.ts`):
  1. If `inviteeUid` is set -> `request.auth.uid == invData.inviteeUid`.
  2. Else if `inviteeEmail` is set -> `request.auth.token.email_verified == true` **and** lowercased `request.auth.token.email` equals lowercased `inviteeEmail`.
  3. Else if `intendedRecipientHash` is set (LifeOS zero-PII design) -> lowercase SHA-256 hex (`hashing.sha256(text.toUtf8()).toHexString().lower()`) matches `intendedRecipientHash` against `request.auth.uid`, **verified** email (`email_verified == true`), or Firebase-verified `phone_number` (including VN `+84` -> `0...` normalization).
- Open invites (`oneTime`, `reusableGroup` without `isTargeted` or recipient fields) preserve existing semantics.
- **Atomic dual-doc binding:** Both `family_invites/{inviteCode}` update and `families/{familyId}` branch-3 join rule enforce `existsAfter(...)` and `getAfter(...)` cross-checks so `usedCount == prev + 1` and `memberIds.size() == prev + 1` (+ `memberRoles[uid] == 'member'`, `consumedBy == uid`, `lastJoinedInviteCode == inviteCode`) can never be updated independently.

### App Enforcement (`lib/features/family/data/repositories/family_repository_impl.dart`)
- Before accepting any targeted invite, reloads `FirebaseAuth.currentUser` (`reload()` + `getIdToken(true)`).
- Rejects unverified emails with the explicit Vietnamese message: `"Cần xác minh email trước khi tham gia nhóm"`.
- Removed the spoofable fallback that read `users/{userId}` when `_firebaseAuth == null` (now fails closed).
- Maps `permission-denied` from Rules (when the caller is not already an existing member) to a clear Vietnamese prompt advising the user to update the app or ask the owner to resend the invite.

---

## Finding 3 — SePay Multi-Bank Ambiguity, Wallet Ownership & Atomic Linking

### SePay Response Verification (`functions/src/bankingEngine.ts` & `functions/src/index.ts`)
- `verifyAndLinkBankConnection` delegates full `/userapi/bankaccounts/list` matching to `matchVerifiedSePayAccount(...)`.
- Optional SePay API fields modeled fail-closed (`SePayBankAccountApiItem`: `id`, `account_number`, `bank_short_name`, `bank_code`, `bank_brand_name`, `bank_name`, `sub_account`, `va`, `accumulated`, `active`, `status`).
- Matches strictly on normalized `account_number` **and** resolved bank capability (`bankCode`), **and** `sub_account` / `va` when `subAccount` is provided.
- Fails closed on:
  - Missing or unrecognized bank code (`BANK_CODE_REQUIRED`, `UNSUPPORTED_PROVIDER_BANK`, `BANK_MISMATCH_OR_UNVERIFIED`)
  - Mismatched sub-account (`SUBACCOUNT_MISMATCH`)
  - 0 matches (`SEPAY_ACCOUNT_NOT_FOUND`) or >1 matches (`AMBIGUOUS_SEPAY_ACCOUNT`)
  - Missing SePay `id` (`INVALID_SEPAY_ACCOUNT_ID`)
  - Explicitly inactive/disabled SePay status (`INACTIVE_SEPAY_ACCOUNT`)
- Stores **only** SePay-sourced verified values (`bankCode`, `bankName`, `subAccount`, `providerConnectionId: "sepay_ba_<id>"`), never trusting raw client-sent values.

### Wallet Ownership & Single Firestore Transaction (`functions/src/firestoreStore.ts` & `functions/src/memoryStore.ts`)
- `RealtimeBankingCoordinator.verifyAndConnectBankAccount` runs inside one `runAtomic` Firestore transaction:
  1. Verifies `users/{authenticatedUserId}/wallets/{linkedWalletId}` exists and belongs to `authenticatedUserId` (`WALLET_NOT_FOUND_OR_FORBIDDEN`).
  2. Reads deterministic claim documents in `server_bank_account_claims` (`sepay_acct_<hash(bankCode:accountNumber:subAccount)>` and `sepay_id_<hash(providerAccountId)>`).
  3. Allows idempotent re-link by the **same** `ownerId`; rejects active claim owned by another user (`ACCOUNT_ALREADY_LINKED_OTHER_USER`).
  4. Atomically writes claim document(s), `server_bank_connections/{id}`, and sanitized `users/{uid}/bank_connections/{id}` inside the **same** transaction.
- `disconnectConnection` transactionally marks associated `server_bank_account_claims` as `"disconnected"`, and `deleteServerOnlyUserAccountData` deletes owner-scoped `server_bank_account_claims` records alongside `server_bank_connections`.
- `firestore.rules` locks `/server_bank_account_claims/{claimId}` (`allow read, write: if false;`) to Admin SDK / Cloud Functions only.

---

## Finding 7 — Split Bill Share Sum Invariant & Reconciliation State

### Authoritative Validation (`firestore.rules` + Dart UseCase / DataSource)
- `firestore.rules` enforces `hasValidSplitBillShares(request.resource.data, familyId)` on **both** `create` and `update` of `/families/{familyId}/split_bills/{billId}`:
  - `sharesByUserId` is a map with `1..20` entries (bills with `> 20` participants are denied).
  - Every value in `sharesByUserId.values()` is an integer `>= 0` (`allSharesNonNegativeInts`).
  - Bounded summation (`sumUpTo20Shares`) strictly equals `totalAmountMinor`.
- Enforced identically on client creation in `CreateSharedBillSplitUseCase` (`family_usecases.dart`) and `FamilyRemoteDataSource.createSharedBillSplit` (`family_repository_impl.dart`).

### Legacy Inconsistent Bill Detection & UI (`family_entities.dart` & `family_page.dart`)
- `SharedBillSplitEntity` exposes `sharesSumMinor`, `isSharesBalanced`, `reconciliationStatus` (`SharedBillReconciliationStatus.reconciled` / `needsReconciliation`), `needsReconciliation`, and `discrepancyMinor`.
- `DebtSimplifier.summarize` isolates inconsistent bills (`!bill.isSharesBalanced` or invalid payer) from reconciled spending, topic totals, member balances, and transfer suggestions, recording them in `SharedLedgerSummary.inconsistentBillCount`, `inconsistentBillIds`, and `unverifiedSharedSpendMinor` so aggregates never mix divergent bases.
- `FamilyPage` renders `"Cần đối soát"` in both the bill cards (`Sổ Khoản chi Chung`) and the debt summary (`Cân đối chi tiêu thành viên` + hero summary), displaying matching reconciled figures.

---

## Old-App Compatibility Impact (`v3.26` / `v3.27`) & Integration Notes
1. **Direct-Firestore targeted invites (Breaking for unverified/legacy clients):** Old `v3.26`/`v3.27` clients using Direct-Firestore without verified email tokens, or sending non-atomic batches / mismatched `pendingInvites` updates, will now be rejected with `permission-denied` by `firestore.rules` on targeted invites. Open invites (`oneTime`, `reusableGroup`) continue working unchanged. Users hitting `permission-denied` are guided to verify email, update the app, or ask the group owner to resend the invite.
2. **Legacy split bills:** Existing mismatched `split_bills` documents in Firestore remain readable; however, any attempt to `update` a legacy mismatched bill without fixing `sharesByUserId` so `sum == totalAmountMinor` (within `<= 20` participants) will be rejected by `firestore.rules`. Clients displaying legacy bills mark them `"Cần đối soát"` cleanly.
3. **SePay connections:** Requires caller wallet (`users/{uid}/wallets/{linkedWalletId}`) to exist before `verifyAndLinkBankConnection` succeeds and requires accurate `bankCode` + SePay account status.
4. **Integration note on existing widget test:** `test/widget/top_toast_and_pro_max_redesign_test.dart` (around line 689, outside this task's writable paths) constructs `MockUser(uid: inviteeUid, email: 'lan@lifeos.vn', ...)` without `isEmailVerified: true` while joining an email-targeted invite (`lan@lifeos.vn`). Lead/QA should add `isEmailVerified: true` on that mock user so the widget test aligns with the verified-email enforcement.
