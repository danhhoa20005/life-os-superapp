# SECURITY & PRIVACY AUDIT — LIFE OS

## 1. Critical Findings Being Remediated
1. **`SEC-F01` (`FIX-002` / `FIX-003` — Family Invites & Join):**
   - Remove raw `inviteeName` / `inviteeContact` requirement from `family_invites/{inviteCode}`; store normalized SHA-256 `targetHash`, `maxUses`, `usedCount`, `status`, `consumedBy`, `consumedAt`, `revokedAt`.
   - Keep `families/{familyId}` unreadable to non-members (`allow read: if isSignedIn() && request.auth.uid in resource.data.memberIds`). Enable atomic self-join via `WriteBatch` + `getAfter` cross-document validation in `firestore.rules` AND server-authoritative Cloud Functions (`previewFamilyInvite`, `joinFamilyByInvite`, `revokeFamilyInvite`).
2. **`SEC-F02` (`FIX-007` — Wallet Balance & Verified Transaction Tampering):**
   - Require `lastAuditId` update + `existsAfter(/users/$(userId)/ledger_audits/$(lastAuditId))` on EVERY `wallets/{walletId}` update that changes `balanceMinor`.
   - Lock `verification`, `verificationStatus`, `sourceKind`, `externalTransactionId`, `referenceCode`, `observedBalanceMinor`, `amountMinor`, `walletId`, and `kind` on `transactions/{txId}` once `verification == 'verified'` (allowing only category/note metadata edits or valid `reversedById` linkage).
3. **`SEC-F03` (`FIX-008` — Local Document Vault & Android Backup):**
   - Encrypt vault attachment bytes using authenticated `AES-256-GCM` (12-byte random IV, 128-bit auth tag, AAD = `userId|docId`) backed by Android Keystore (`LifeOsSecureVault.kt`) with SHA-256 plaintext/ciphertext verification on read.
   - Set `android:allowBackup="false"`, configure `backup_rules.xml` & `data_extraction_rules.xml`, and remove root `.` exposure from `file_paths.xml`.
4. **`SEC-F04` (`Section 16` — Hybrid Gemini PII Protection):**
   - Always run `OtpRedactor.redact` regardless of user toggle, and strip spaced/hyphenated phone numbers, card PANs, bank account numbers, CCCD/Passport, BHYT, `FAM-*` invite codes, and license plates before any optional Gemini API call. Never allow Gemini output to execute ledger or RBAC mutations without user confirmation and domain schema validation.
