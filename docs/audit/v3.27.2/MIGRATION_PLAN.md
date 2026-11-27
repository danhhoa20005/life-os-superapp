# LIFE OS — MIGRATION & ROLLBACK PLAN (v3.27.2 -> v3.27.3)

## 1. Firestore Rules, Composite Indexes & Cloud Functions Rollout Order

Deploy strictly in the following order to prevent client/server mismatches:

1. **Firestore Composite Indexes (`firestore.indexes.json`) — Deploy FIRST:**
   - Adds required indexes for `notification_outbox` (`(state, nextRetryAtMs)`, `(state, leaseExpiresAtMs)`, `(state, createdAtMs)`) and `sepay_webhook_inbox` (`(state, receivedAtMs)`, `(state, nextRetryAtMs)`, `(ownerId, receivedAtMs)`).
   - Wait until Firebase Console reports all indexes `ENABLED` before enabling scheduled sweepers.
2. **Cloud Functions (`functions/`) — Deploy SECOND:**
   - Deploys `deleteUserAccountData` (with `auth_time <= 300s` check, atomic lease, deletion tombstone, Auth revocation/deletion), `recoverStaleAccountDeletions`, `recoverPendingWebhookInboxWorker`, updated `retryFailedNotificationOutboxWorker`, and `reconcileBankConnectionViaApi` (`BANK-03` safe watermark/cursor).
   - Keep `LIFEOS_ENFORCE_APP_CHECK=false` (monitor mode) initially; switch to `LIFEOS_ENFORCE_APP_CHECK=true` only after verifying valid Play Integrity attestation on staging.
3. **Firestore Security Rules (`firestore.rules`) — Deploy THIRD (after verifying client compatibility):**
   - `SEC-01`: Blocks client creates/updates forging `verified`, `VERIFIED`, `verifiedByBank`, `verified_by_bank`, or `sourceKind in ['bankWebhook', 'bankApi']`.
   - `DEL-03/04`: Blocks direct client `DELETE /users/{uid}` and freezes all client writes under `users/{uid}` when `account_deletion_tombstones/{uid}` exists.
   - `SEC-02/03`: Locks `server_source_events`, `account_deletion_tombstones`, `api_rate_limits`, append-only `ledger_audits` / `automation_audits`, and read-only client mirrors (`financial_notifications` allowlisted to read/dismiss only; `bank_connections` allowlisted to `pendingRevocation` only).
   - **Rollback:** Keep previous `firestore.rules` snapshot from commit `8d5d3a8`; if any legacy client version (`<= v3.27.1`) breaks on `users/{uid}` deletion or `financial_notifications` update, roll back Rules temporarily while forcing upgrade to `v3.27.3+`.

## 2. Transaction Verification & Ledger Backfill (`SEC-01`, `SEC-02`)

- **Existing Data Audit (staging dry-run before production):**
  - Scan `users/*/transactions` where `verification in ['verified', 'verifiedByBank']` and `sourceKind not in ['bankWebhook', 'bankApi']`.
  - Downgrade any legacy client-authored record lacking server provenance (`externalTransactionId` + `server_source_events` match) to `verification: 'userConfirmed'` with audit metadata `migratedFromLegacyVerification: true`.
- **Archived Wallets:**
  - Wallets with existing transactions or `linkedBankConnectionId` are soft-archived (`archived: true`) instead of hard-deleted; `bankingEngine.ts` never resurrects an archived wallet.

## 3. Document Vault Physical Files & Index (`VAULT-01`, `VAULT-02`, `VAULT-03`)

- **Forward Migration:**
  - All new uploads write to `<vaultRoot>/<safeUid>/<attachmentId>.enc` + `<attachmentId>.meta.json` and update `<vaultRoot>/<safeUid>/attachment_index.json` atomically via per-UID mutex + `.tmp` + `.bak` + `renameSync`.
  - Legacy files using `<folder>_<digest>_<name>.enc` remain readable via `attachment_index.json` or fallback scan of `*.meta.json`.
  - On delete, `deleteAttachmentForUser` reference-counts aliases in `attachment_index.json` and only unlinks the physical `.enc` file when refcount reaches `0`.
  - Failed local deletions enqueue into `<vaultRoot>/<safeUid>/pending_cleanups.json` for deterministic retry via `retryPendingLocalCleanups(userId)`.
- **Rollback:** Backward compatible — older index entries and `.meta.json` files continue to open without destructive rewrite.

## 4. OfflineOutbox Storage & Corruption Quarantine (`DATA-01`)

- Every operation is serialized via FIFO async lock `_opChain` and scoped by UID.
- If a legacy/corrupted JSON string is detected, the raw payload is preserved under `${storageKey}__corrupted_<epochMs>` instead of silently erased, allowing manual inspection or recovery.
- Legacy un-keyed entries remain readable during active session and receive stable `operationId`s.

## 5. Backup Archive Codec v4 (`DATA-03`) & Replace Restore (`DATA-02`)

- **Format Upgrade:** New exports default to `LIFEOS_BACKUP_V4` (NIST AES-256-GCM + PBKDF2-HMAC-SHA256 `210,000` iterations + 16B salt + 12B nonce + AAD header binding). Plaintext export is blocked unless `allowPlaintextExport: true` is explicitly passed.
- **Backward Compatibility:** v1, v2, and v3 archives remain readable with `isLegacyFormat: true` warning metadata; no silent downgrade on re-export.
- **Safe Replace Restore:** Validates schema/checksum/wallet references before touching Firestore, records `daily_preferences/backup_restore_checkpoint`, writes restored records FIRST, never deletes immutable server-verified bank transactions (archiving their wallets instead), and prunes obsolete non-verified records only after 100% of writes commit cleanly.

## 6. Personal Alarms Legacy Quarantine (`ALARM-01`)

- Active alarms are stored under `lifeos_personal_alarms_v2__u_<uid>` and OS AlarmManager IDs are namespaced as `palarm_<safeUid>_<alarmId>`.
- Legacy device-global `lifeos_personal_alarms_v1` is **NOT silently deleted**: it is moved into `lifeos_personal_alarms_legacy_quarantine_v1`. Users can explicitly inspect (`loadQuarantinedLegacyAlarms`), import into their UID (`importQuarantinedLegacyAlarmsForActiveUser`), or discard (`discardQuarantinedLegacyAlarms`).
