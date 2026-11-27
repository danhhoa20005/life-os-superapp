import * as admin from "firebase-admin";
import { Timestamp } from "firebase-admin/firestore";
import {
  BackfillCursorRecord,
  BankAccountClaimRecord,
  BankingBackendStore,
  BankingTxContext,
  CanonicalTransactionRecord,
  DEFAULT_NOTIFICATION_PREFS,
  FcmMulticastResult,
  FcmPushSender,
  InboxEventRecord,
  NotificationOutboxRecord,
  NotificationOutboxState,
  ServerBankConnectionRecord,
  UserDeviceRecord,
  UserNotificationPreferences,
  buildNormalizedAccountClaimId,
  buildProviderAccountIdClaimId,
  isConnectionActiveAndGranted
} from "./bankingEngine";
import { resolveBankCapability } from "./capabilities";
import { INBOX_TERMINAL_TTL_MS } from "./schema";
import { maskAccountNumber } from "./security";

export class FirebaseAdminFcmSender implements FcmPushSender {
  constructor(private readonly messaging: admin.messaging.Messaging) {}

  async sendToUserDevices(params: {
    tokens: readonly string[];
    notificationId: string;
    title: string;
    body: string;
    lockscreenPrivate: boolean;
    soundEnabled: boolean;
    data: Record<string, string>;
  }): Promise<FcmMulticastResult> {
    const res = await this.messaging.sendEachForMulticast({
      tokens: [...params.tokens],
      notification: {
        title: params.title,
        body: params.body
      },
      data: params.data,
      android: {
        priority: "high",
        collapseKey: params.notificationId,
        notification: {
          channelId: "lifeos_banking_realtime",
          tag: params.notificationId,
          visibility: params.lockscreenPrivate ? "private" : "public",
          sound: params.soundEnabled ? "default" : undefined
        }
      },
      apns: {
        headers: {
          "apns-collapse-id": params.notificationId
        },
        payload: {
          aps: {
            sound: params.soundEnabled ? "default" : undefined,
            "mutable-content": 1
          }
        }
      }
    });

    const invalidTokens: string[] = [];
    const succeededTokens: string[] = [];
    const failedTokens: Record<string, string> = {};
    let retryableError: string | undefined;

    res.responses.forEach((r, idx) => {
      const token = params.tokens[idx];
      if (r.success) {
        succeededTokens.push(token);
      } else if (r.error) {
        const code = r.error.code || "messaging/unknown";
        if (
          code === "messaging/registration-token-not-registered" ||
          code === "messaging/invalid-registration-token"
        ) {
          invalidTokens.push(token);
        } else {
          failedTokens[token] = code;
          retryableError = `${code}: ${r.error.message}`;
        }
      } else {
        failedTokens[token] = "messaging/unknown";
        retryableError = retryableError ?? "messaging/unknown";
      }
    });

    return {
      successCount: res.successCount,
      failureCount: res.failureCount,
      invalidTokens,
      succeededTokens,
      failedTokens,
      retryableError
    };
  }
}

function stripUndefined<T extends Record<string, unknown>>(obj: T): Record<string, unknown> {
  const clean: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(obj)) {
    if (v === undefined) continue;
    if (v !== null && typeof v === "object" && !Array.isArray(v) && !(v instanceof Timestamp)) {
      clean[k] = stripUndefined(v as Record<string, unknown>);
    } else {
      clean[k] = v;
    }
  }
  return clean;
}

function mapBackfillCursor(raw: unknown): BackfillCursorRecord | null {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null;
  const d = raw as Record<string, unknown>;
  if (typeof d.connectionId !== "string" || typeof d.nextPage !== "number") return null;
  return {
    connectionId: d.connectionId,
    grantVersion: typeof d.grantVersion === "number" && Number.isFinite(d.grantVersion) ? d.grantVersion : 1,
    nextPage: d.nextPage,
    beforeExternalTxId: typeof d.beforeExternalTxId === "string" ? d.beforeExternalTxId : null,
    pendingNewestValidExternalTxId:
      typeof d.pendingNewestValidExternalTxId === "string"
        ? d.pendingNewestValidExternalTxId
        : null,
    previousWatermarkExternalTxId:
      typeof d.previousWatermarkExternalTxId === "string"
        ? d.previousWatermarkExternalTxId
        : null,
    updatedAtMs: typeof d.updatedAtMs === "number" ? d.updatedAtMs : 0
  };
}

function mapServerConnectionDoc(
  id: string,
  d: Record<string, unknown>
): ServerBankConnectionRecord {
  return {
    id: String(d.id ?? id),
    ownerId: String(d.ownerId ?? ""),
    provider: (d.provider as ServerBankConnectionRecord["provider"]) ?? "sepay",
    providerConnectionId: String(d.providerConnectionId ?? ""),
    bankCode: String(d.bankCode ?? ""),
    bankName: String(d.bankName ?? ""),
    accountNumber: String(d.accountNumber ?? ""),
    accountMasked: String(d.accountMasked ?? ""),
    subAccount: String(d.subAccount ?? ""),
    linkedWalletId: String(d.linkedWalletId ?? ""),
    consentStatus: d.consentStatus === "revoked" ? "revoked" : "granted",
    consentEnabled: d.consentEnabled !== false,
    status: (d.status as ServerBankConnectionRecord["status"]) ?? "pending_verification",
    grantVersion: typeof d.grantVersion === "number" && Number.isFinite(d.grantVersion) ? d.grantVersion : 1,
    webhookSecretHash: typeof d.webhookSecretHash === "string" ? d.webhookSecretHash : undefined,
    encryptedApiToken: typeof d.encryptedApiToken === "string" ? d.encryptedApiToken : undefined,
    capabilities: d.capabilities as ServerBankConnectionRecord["capabilities"],
    lastSyncedAtMs: typeof d.lastSyncedAtMs === "number" ? d.lastSyncedAtMs : null,
    lastSyncedExternalTxId:
      typeof d.lastSyncedExternalTxId === "string" ? d.lastSyncedExternalTxId : null,
    lastReconciledExternalTxId:
      typeof d.lastReconciledExternalTxId === "string" ? d.lastReconciledExternalTxId : null,
    lastReconciledAtMs:
      typeof d.lastReconciledAtMs === "number"
        ? d.lastReconciledAtMs
        : d.lastReconciledAt instanceof Timestamp
          ? d.lastReconciledAt.toMillis()
          : null,
    backfillCursor: mapBackfillCursor(d.backfillCursor),
    statusWarning: typeof d.statusWarning === "string" ? d.statusWarning : null,
    revokedAtMs:
      typeof d.revokedAtMs === "number"
        ? d.revokedAtMs
        : d.revokedAt instanceof Timestamp
          ? d.revokedAt.toMillis()
          : null,
    createdAtMs: typeof d.createdAtMs === "number" ? d.createdAtMs : 0,
    updatedAtMs: typeof d.updatedAtMs === "number" ? d.updatedAtMs : 0
  };
}

function mapNotificationOutboxDoc(
  id: string,
  d: Record<string, unknown>
): NotificationOutboxRecord {
  const rawFailed = d.failedTokens;
  const failedTokens: Record<string, string> = {};
  if (rawFailed && typeof rawFailed === "object" && !Array.isArray(rawFailed)) {
    for (const [k, v] of Object.entries(rawFailed as Record<string, unknown>)) {
      if (typeof v === "string") failedTokens[k] = v;
    }
  }
  return {
    id: String(d.id ?? id),
    ownerId: String(d.ownerId ?? ""),
    transactionId: String(d.transactionId ?? ""),
    walletId: String(d.walletId ?? ""),
    connectionId: String(d.connectionId ?? ""),
    grantVersion: typeof d.grantVersion === "number" ? d.grantVersion : undefined,
    direction: d.direction === "debit" ? "debit" : "credit",
    amountMinor: Number(d.amountMinor ?? 0),
    bankCode: String(d.bankCode ?? ""),
    bankName: String(d.bankName ?? ""),
    accountMasked: String(d.accountMasked ?? ""),
    content: String(d.content ?? ""),
    occurredAtMs: Number(d.occurredAtMs ?? 0),
    verificationStatus: (d.verificationStatus as NotificationOutboxRecord["verificationStatus"]) ?? "VERIFIED",
    state: (d.state as NotificationOutboxState) ?? "PENDING_DELIVERY",
    attemptCount: typeof d.attemptCount === "number" && Number.isFinite(d.attemptCount) ? d.attemptCount : 0,
    version: typeof d.version === "number" && Number.isFinite(d.version) ? d.version : 1,
    leaseOwner: typeof d.leaseOwner === "string" ? d.leaseOwner : null,
    leaseExpiresAtMs: typeof d.leaseExpiresAtMs === "number" ? d.leaseExpiresAtMs : null,
    deliveredTokens: Array.isArray(d.deliveredTokens) ? d.deliveredTokens.map(String) : [],
    failedTokens,
    deadLetteredAtMs: typeof d.deadLetteredAtMs === "number" ? d.deadLetteredAtMs : null,
    lastError: typeof d.lastError === "string" ? d.lastError : null,
    nextRetryAtMs: typeof d.nextRetryAtMs === "number" ? d.nextRetryAtMs : null,
    createdAtMs: typeof d.createdAtMs === "number" ? d.createdAtMs : 0,
    updatedAtMs: typeof d.updatedAtMs === "number" ? d.updatedAtMs : 0
  };
}

function mapInboxEventDoc(
  id: string,
  d: Record<string, unknown>
): InboxEventRecord {
  return {
    ...(d as unknown as InboxEventRecord),
    providerEventKey: String(d.providerEventKey ?? id),
    attemptCount: typeof d.attemptCount === "number" && Number.isFinite(d.attemptCount) ? d.attemptCount : 0,
    leaseOwner: typeof d.leaseOwner === "string" ? d.leaseOwner : null,
    leaseExpiresAtMs: typeof d.leaseExpiresAtMs === "number" ? d.leaseExpiresAtMs : null,
    nextRetryAtMs: typeof d.nextRetryAtMs === "number" ? d.nextRetryAtMs : null,
    expiresAtMs: typeof d.expiresAtMs === "number" ? d.expiresAtMs : null,
    deadLetterReason: typeof d.deadLetterReason === "string" ? d.deadLetterReason : null,
    receivedAtMs:
      typeof d.receivedAtMs === "number"
        ? d.receivedAtMs
        : d.receivedAt instanceof Timestamp
          ? d.receivedAt.toMillis()
          : 0,
    updatedAtMs:
      typeof d.updatedAtMs === "number"
        ? d.updatedAtMs
        : d.updatedAt instanceof Timestamp
          ? d.updatedAt.toMillis()
          : 0
  };
}

function serverSourceEventDocId(ownerId: string, eventKey: string): string {
  return `${ownerId}__${eventKey}`;
}

export class FirestoreAdminBankingStore implements BankingBackendStore {
  constructor(private readonly db: admin.firestore.Firestore) {}

  async runAtomic<T>(fn: (ctx: BankingTxContext) => Promise<T>): Promise<T> {
    return this.db.runTransaction(async (tx) => {
      const ctx: BankingTxContext = {
        isUserDeletionFrozen: async (ownerId) => {
          const cleanUid = ownerId.trim();
          if (!cleanUid) return false;
          const snap = await tx.get(this.db.collection("account_deletion_tombstones").doc(cleanUid));
          return snap.exists;
        },
        getConnectionById: async (connectionId) => {
          const snap = await tx.get(this.db.collection("server_bank_connections").doc(connectionId));
          if (!snap.exists) return null;
          return mapServerConnectionDoc(snap.id, (snap.data() ?? {}) as Record<string, unknown>);
        },
        getInboxEvent: async (providerEventKey) => {
          const snap = await tx.get(this.db.collection("sepay_webhook_inbox").doc(providerEventKey));
          return snap.exists ? mapInboxEventDoc(snap.id, (snap.data() ?? {}) as Record<string, unknown>) : null;
        },
        setInboxEvent: async (record) => {
          tx.set(
            this.db.collection("sepay_webhook_inbox").doc(record.providerEventKey),
            stripUndefined({
              ...record,
              expiresAt: record.expiresAtMs != null ? Timestamp.fromMillis(record.expiresAtMs) : null,
              updatedAt: Timestamp.fromMillis(record.updatedAtMs)
            })
          );
        },
        getSourceEvent: async (ownerId, eventKey) => {
          const ref = this.db.collection("users").doc(ownerId).collection("source_events").doc(eventKey);
          const snap = await tx.get(ref);
          if (!snap.exists) return null;
          const d = snap.data() ?? {};
          return { linkedTransactionId: String(d.linkedTransactionId ?? "") };
        },
        setSourceEvent: async (ownerId, eventKey, data) => {
          const ref = this.db.collection("users").doc(ownerId).collection("source_events").doc(eventKey);
          tx.set(ref, {
            eventKey,
            source: data.source,
            status: data.status,
            linkedTransactionId: data.linkedTransactionId,
            receivedAt: Timestamp.fromMillis(data.receivedAtMs)
          });
        },
        getServerSourceEvent: async (ownerId, eventKey) => {
          const ref = this.db.collection("server_source_events").doc(serverSourceEventDocId(ownerId, eventKey));
          const snap = await tx.get(ref);
          if (!snap.exists) return null;
          const d = snap.data() ?? {};
          return { linkedTransactionId: String(d.linkedTransactionId ?? "") };
        },
        setServerSourceEvent: async (ownerId, eventKey, data) => {
          const ref = this.db.collection("server_source_events").doc(serverSourceEventDocId(ownerId, eventKey));
          tx.set(
            ref,
            stripUndefined({
              ownerId,
              eventKey,
              source: data.source,
              status: data.status,
              linkedTransactionId: data.linkedTransactionId,
              connectionId: data.connectionId,
              receivedAtMs: data.receivedAtMs,
              receivedAt: Timestamp.fromMillis(data.receivedAtMs)
            })
          );
        },
        findCandidateTransactions: async (ownerId, softWindowFingerprints) => {
          if (softWindowFingerprints.length === 0) return [];
          const q = this.db
            .collection("users")
            .doc(ownerId)
            .collection("transactions")
            .where("softWindowFingerprint", "in", [...softWindowFingerprints]);
          const snap = await tx.get(q);
          return snap.docs.map((doc) => {
            const d = doc.data();
            const occ = d.occurredAt instanceof Timestamp ? d.occurredAt.toMillis() : Number(d.occurredAtMs ?? Date.now());
            const cre = d.createdAt instanceof Timestamp ? d.createdAt.toMillis() : Number(d.createdAtMs ?? occ);
            return {
              id: doc.id,
              ownerId: String(d.ownerId ?? ownerId),
              walletId: String(d.walletId ?? "wallet_bank_default"),
              walletName: typeof d.walletName === "string" ? d.walletName : undefined,
              connectionId: typeof d.connectionId === "string" ? d.connectionId : undefined,
              sourceProvider: (d.sourceProvider as CanonicalTransactionRecord["sourceProvider"]) ?? "android_device",
              sourceKind: (d.sourceKind as CanonicalTransactionRecord["sourceKind"]) ?? "androidNotification",
              externalTransactionId: typeof d.externalTransactionId === "string" ? d.externalTransactionId : undefined,
              referenceCode: typeof d.referenceCode === "string" ? d.referenceCode : undefined,
              kind: d.kind === "income" ? "income" : "expense",
              direction: d.direction === "credit" ? "credit" : "debit",
              amountMinor: Number(d.amountMinor ?? 0),
              currencyCode: "VND",
              bankCode: typeof d.bankCode === "string" ? d.bankCode : undefined,
              accountMasked: typeof d.accountMasked === "string" ? d.accountMasked : undefined,
              accountTail: typeof d.accountTail === "string" ? d.accountTail : undefined,
              counterpartyDisplay: typeof d.counterpartyDisplay === "string" ? d.counterpartyDisplay : undefined,
              merchant: String(d.merchant ?? ""),
              description: String(d.description ?? d.merchant ?? ""),
              categoryName: String(d.categoryName ?? "Chi tiêu khác"),
              occurredAtMs: occ,
              receivedAtMs: Number(d.receivedAtMs ?? cre),
              monthKey: String(d.monthKey ?? ""),
              verification: (d.verification as CanonicalTransactionRecord["verification"]) ?? "provisional",
              verificationStatus: (d.verificationStatus as CanonicalTransactionRecord["verificationStatus"]) ?? "PROVISIONAL",
              reconciliationStatus:
                (d.reconciliationStatus as CanonicalTransactionRecord["reconciliationStatus"]) ?? "unreconciled_provisional",
              sourceEventKey: String(d.sourceEventKey ?? ""),
              crossSourceFingerprint: String(d.crossSourceFingerprint ?? ""),
              softWindowFingerprint: String(d.softWindowFingerprint ?? ""),
              balanceAfterMinor: typeof d.balanceAfterMinor === "number" ? d.balanceAfterMinor : null,
              balanceType: (d.balanceType as CanonicalTransactionRecord["balanceType"]) ?? "unknownBalance",
              balanceObservationSkippedStale: d.balanceObservationSkippedStale === true,
              ledgerApplied:
                typeof d.ledgerApplied === "boolean"
                  ? d.ledgerApplied
                  : d.verification === "verified" || d.verification === "userConfirmed",
              isVehicleMaintenanceHint: Boolean(d.isVehicleMaintenanceHint),
              isRecurringCandidate: Boolean(d.isRecurringCandidate),
              createdAtMs: cre,
              updatedAtMs: Date.now()
            };
          });
        },
        getWallet: async (ownerId, walletId) => {
          const ref = this.db.collection("users").doc(ownerId).collection("wallets").doc(walletId);
          const snap = await tx.get(ref);
          if (!snap.exists) return null;
          const d = snap.data() ?? {};
          return {
            id: walletId,
            ownerId,
            name: String(d.name ?? "Ngân hàng"),
            balanceMinor: Number(d.balanceMinor ?? 0),
            isEstimatedBalance: d.isEstimatedBalance !== false,
            lastAuditId: typeof d.lastAuditId === "string" ? d.lastAuditId : undefined,
            lastObservedBalanceAtEpochMs:
              typeof d.lastObservedBalanceAtEpochMs === "number" ? d.lastObservedBalanceAtEpochMs : null,
            lastObservedBalanceEventId:
              typeof d.lastObservedBalanceEventId === "string" ? d.lastObservedBalanceEventId : null,
            bankCode: typeof d.bankCode === "string" ? d.bankCode : undefined,
            maskedAccount: typeof d.maskedAccount === "string" ? d.maskedAccount : undefined,
            archived: d.archived === true || d.isArchived === true,
            isArchived: d.isArchived === true || d.archived === true,
            archivedAtMs:
              typeof d.archivedAtMs === "number"
                ? d.archivedAtMs
                : d.archivedAt instanceof Timestamp
                  ? d.archivedAt.toMillis()
                  : null,
            updatedAtMs: Date.now()
          };
        },
        upsertWallet: async (ownerId, wallet) => {
          const ref = this.db.collection("users").doc(ownerId).collection("wallets").doc(wallet.id);
          tx.set(
            ref,
            {
              id: wallet.id,
              ownerId,
              name: wallet.name,
              type: "bank",
              balanceMinor: wallet.balanceMinor,
              isEstimatedBalance: wallet.isEstimatedBalance,
              ...(wallet.lastAuditId ? { lastAuditId: wallet.lastAuditId } : {}),
              ...(wallet.lastObservedBalanceAtEpochMs !== undefined
                ? { lastObservedBalanceAtEpochMs: wallet.lastObservedBalanceAtEpochMs }
                : {}),
              ...(wallet.lastObservedBalanceEventId !== undefined
                ? { lastObservedBalanceEventId: wallet.lastObservedBalanceEventId }
                : {}),
              bankCode: wallet.bankCode ?? null,
              maskedAccount: wallet.maskedAccount ?? null,
              updatedAt: Timestamp.fromMillis(wallet.updatedAtMs)
            },
            { merge: true }
          );
        },
        upsertTransaction: async (ownerId, t) => {
          const ref = this.db.collection("users").doc(ownerId).collection("transactions").doc(t.id);
          tx.set(
            ref,
            stripUndefined({
              ...t,
              occurredAt: Timestamp.fromMillis(t.occurredAtMs),
              receivedAt: Timestamp.fromMillis(t.receivedAtMs),
              createdAt: Timestamp.fromMillis(t.createdAtMs),
              updatedAt: Timestamp.fromMillis(t.updatedAtMs),
              schemaVersion: 2
            }),
            { merge: true }
          );
        },
        appendLedgerAudit: async (ownerId, auditId, data) => {
          const ref = this.db.collection("users").doc(ownerId).collection("ledger_audits").doc(auditId);
          tx.set(
            ref,
            stripUndefined({
              ...data,
              createdAt: Timestamp.fromMillis(Number(data.createdAtMs ?? Date.now()))
            })
          );
        },
        upsertFinancialNotification: async (ownerId, notif) => {
          const ref = this.db.collection("users").doc(ownerId).collection("financial_notifications").doc(notif.id);
          tx.set(
            ref,
            stripUndefined({
              ...notif,
              occurredAt: Timestamp.fromMillis(notif.occurredAtMs),
              createdAt: Timestamp.fromMillis(notif.createdAtMs)
            })
          );
        },
        upsertNotificationOutbox: async (outbox) => {
          const ref = this.db.collection("notification_outbox").doc(outbox.id);
          tx.set(
            ref,
            stripUndefined({
              ...outbox,
              createdAt: Timestamp.fromMillis(outbox.createdAtMs),
              updatedAt: Timestamp.fromMillis(outbox.updatedAtMs)
            })
          );
        },
        updateConnectionLastSync: async (ownerId, connectionId, syncedAtMs) => {
          const ts = Timestamp.fromMillis(syncedAtMs);
          tx.set(
            this.db.collection("server_bank_connections").doc(connectionId),
            { lastSyncedAtMs: syncedAtMs, lastSyncedAt: ts, updatedAtMs: syncedAtMs },
            { merge: true }
          );
          tx.set(
            this.db.collection("users").doc(ownerId).collection("bank_connections").doc(connectionId),
            { lastSyncedAtMs: syncedAtMs, lastSyncedAt: ts, updatedAt: ts },
            { merge: true }
          );
        },
        markConnectionWarning: async (ownerId, connectionId, warning, nowMs) => {
          const ts = Timestamp.fromMillis(nowMs);
          tx.set(
            this.db.collection("server_bank_connections").doc(connectionId),
            { statusWarning: warning, updatedAtMs: nowMs, updatedAt: ts },
            { merge: true }
          );
          tx.set(
            this.db.collection("users").doc(ownerId).collection("bank_connections").doc(connectionId),
            { statusWarning: warning, updatedAt: ts },
            { merge: true }
          );
        },
        getBankAccountClaim: async (claimId) => {
          const snap = await tx.get(this.db.collection("server_bank_account_claims").doc(claimId));
          if (!snap.exists) return null;
          return snap.data() as BankAccountClaimRecord;
        },
        upsertBankAccountClaim: async (claim) => {
          tx.set(
            this.db.collection("server_bank_account_claims").doc(claim.claimId),
            stripUndefined({ ...claim })
          );
        },
        saveVerifiedConnectionTx: async (record) => {
          this.writeVerifiedConnection((ref, data) => tx.set(ref, data), record);
        }
      };

      return fn(ctx);
    });
  }

  async isUserDeletionFrozen(ownerId: string): Promise<boolean> {
    const cleanUid = ownerId.trim();
    if (!cleanUid) return false;
    const snap = await this.db.collection("account_deletion_tombstones").doc(cleanUid).get();
    return snap.exists;
  }

  private writeVerifiedConnection(
    setDoc: (ref: admin.firestore.DocumentReference, data: Record<string, unknown>) => void,
    record: ServerBankConnectionRecord
  ): void {
    const ts = Timestamp.fromMillis(record.updatedAtMs);
    setDoc(
      this.db.collection("server_bank_connections").doc(record.id),
      stripUndefined({
        ...record,
        consentEnabled: record.consentEnabled !== false,
        grantVersion: record.grantVersion ?? 1
      })
    );
    // User-readable document NEVER stores full accountNumber or provider tokens (Section 7 & 14)
    setDoc(
      this.db.collection("users").doc(record.ownerId).collection("bank_connections").doc(record.id),
      stripUndefined({
        id: record.id,
        ownerId: record.ownerId,
        provider: record.provider,
        providerConnectionId: record.providerConnectionId,
        bankCode: record.bankCode,
        bankName: record.bankName,
        accountMasked: maskAccountNumber(record.accountNumber),
        subAccount: record.subAccount,
        linkedWalletId: record.linkedWalletId,
        consentStatus: record.consentStatus,
        consentEnabled: record.consentEnabled !== false,
        grantVersion: record.grantVersion ?? 1,
        status: record.status,
        capabilities: record.capabilities,
        lastSyncedAt: ts,
        revokedAt: record.revokedAtMs ? Timestamp.fromMillis(record.revokedAtMs) : null,
        createdAt: Timestamp.fromMillis(record.createdAtMs),
        updatedAt: ts
      })
    );
  }

  async getConnectionById(connectionId: string): Promise<ServerBankConnectionRecord | null> {
    const snap = await this.db.collection("server_bank_connections").doc(connectionId).get();
    if (!snap.exists) return null;
    return mapServerConnectionDoc(snap.id, (snap.data() ?? {}) as Record<string, unknown>);
  }

  async findActiveConnectionForAccount(params: {
    bankCode: string;
    gateway: string;
    accountNumber: string;
    subAccount: string;
  }): Promise<ServerBankConnectionRecord | null> {
    const snap = await this.db
      .collection("server_bank_connections")
      .where("accountNumber", "==", params.accountNumber)
      .where("status", "in", ["connected", "active"])
      .get();

    for (const doc of snap.docs) {
      const d = mapServerConnectionDoc(doc.id, (doc.data() ?? {}) as Record<string, unknown>);
      if (!isConnectionActiveAndGranted(d)) continue;
      if (d.bankCode.toUpperCase() === params.bankCode.toUpperCase()) {
        const expectedSub = String(d.subAccount ?? "").trim();
        const incomingSub = String(params.subAccount ?? "").trim();
        if (expectedSub !== incomingSub) continue;
        return d;
      }
    }
    return null;
  }

  async findAnyVerifiedConnectionByAccount(
    bankCode: string,
    accountNumber: string,
    subAccount?: string
  ): Promise<ServerBankConnectionRecord | null> {
    const snap = await this.db
      .collection("server_bank_connections")
      .where("bankCode", "==", bankCode)
      .where("accountNumber", "==", accountNumber)
      .where("status", "in", ["connected", "active"])
      .get();
    if (snap.empty) return null;
    const expectedSub = String(subAccount ?? "").trim().toUpperCase();
    for (const doc of snap.docs) {
      const d = mapServerConnectionDoc(doc.id, (doc.data() ?? {}) as Record<string, unknown>);
      if (!isConnectionActiveAndGranted(d)) continue;
      const docSub = String(d.subAccount ?? "").trim().toUpperCase();
      if (expectedSub && docSub && docSub !== expectedSub) continue;
      if (expectedSub && !docSub) continue;
      if (!expectedSub && docSub) continue;
      return d;
    }
    return null;
  }

  async saveVerifiedConnection(record: ServerBankConnectionRecord): Promise<void> {
    const batch = this.db.batch();
    this.writeVerifiedConnection((ref, data) => batch.set(ref, data), record);
    await batch.commit();
  }

  async disconnectConnection(ownerId: string, connectionId: string, nowMs: number): Promise<void> {
    const serverRef = this.db.collection("server_bank_connections").doc(connectionId);
    const userConnRef = this.db.collection("users").doc(ownerId).collection("bank_connections").doc(connectionId);
    const ts = Timestamp.fromMillis(nowMs);

    await this.db.runTransaction(async (tx) => {
      const snap = await tx.get(serverRef);
      if (snap.exists && snap.data()?.ownerId !== ownerId) {
        throw new Error("FORBIDDEN_CONNECTION_OWNER");
      }

      const d = snap.exists
        ? mapServerConnectionDoc(snap.id, (snap.data() ?? {}) as Record<string, unknown>)
        : null;
      const claimRefsToRead: admin.firestore.DocumentReference[] = [];
      if (d) {
        claimRefsToRead.push(
          this.db
            .collection("server_bank_account_claims")
            .doc(buildNormalizedAccountClaimId(d.bankCode, d.accountNumber, d.subAccount ?? ""))
        );
        if (d.providerConnectionId?.startsWith("sepay_ba_")) {
          const providerAcctId = d.providerConnectionId.slice("sepay_ba_".length).trim();
          if (providerAcctId) {
            claimRefsToRead.push(
              this.db
                .collection("server_bank_account_claims")
                .doc(buildProviderAccountIdClaimId(providerAcctId))
            );
          }
        }
      }

      const claimQuerySnap = await tx.get(
        this.db
          .collection("server_bank_account_claims")
          .where("ownerId", "==", ownerId)
          .where("connectionId", "==", connectionId)
      );
      const claimSnaps = await Promise.all(claimRefsToRead.map((ref) => tx.get(ref)));

      const nextGrantVersion = (d ? d.grantVersion : 1) + 1;

      if (snap.exists) {
        tx.set(
          serverRef,
          {
            status: "revoked",
            consentStatus: "revoked",
            consentEnabled: false,
            grantVersion: nextGrantVersion,
            revokedAtMs: nowMs,
            revokedAt: ts,
            updatedAtMs: nowMs,
            updatedAt: ts
          },
          { merge: true }
        );
      }

      tx.set(
        userConnRef,
        {
          id: connectionId,
          ownerId,
          status: "disconnected",
          consentStatus: "revoked",
          consentEnabled: false,
          grantVersion: nextGrantVersion,
          revokedAt: ts,
          updatedAt: ts
        },
        { merge: true }
      );

      const seenClaimPaths = new Set<string>();
      for (const claimSnap of [...claimSnaps, ...claimQuerySnap.docs]) {
        if (!claimSnap.exists || seenClaimPaths.has(claimSnap.ref.path)) continue;
        seenClaimPaths.add(claimSnap.ref.path);
        if (claimSnap.data()?.ownerId === ownerId) {
          tx.set(
            claimSnap.ref,
            { status: "disconnected", updatedAtMs: nowMs },
            { merge: true }
          );
        }
      }
    });
  }

  async revokeConnection(ownerId: string, connectionId: string, nowMs: number = Date.now()): Promise<void> {
    return this.disconnectConnection(ownerId, connectionId, nowMs);
  }

  async getInboxEvent(providerEventKey: string): Promise<InboxEventRecord | null> {
    const snap = await this.db.collection("sepay_webhook_inbox").doc(providerEventKey).get();
    return snap.exists ? mapInboxEventDoc(snap.id, (snap.data() ?? {}) as Record<string, unknown>) : null;
  }

  async createDurableInboxIfAbsent(
    record: InboxEventRecord
  ): Promise<{ created: boolean; existing?: InboxEventRecord }> {
    const ref = this.db.collection("sepay_webhook_inbox").doc(record.providerEventKey);
    return this.db.runTransaction(async (tx) => {
      const existing = await tx.get(ref);
      if (existing.exists) {
        return {
          created: false,
          existing: mapInboxEventDoc(existing.id, (existing.data() ?? {}) as Record<string, unknown>)
        };
      }
      tx.set(
        ref,
        stripUndefined({
          ...record,
          expiresAt: record.expiresAtMs != null ? Timestamp.fromMillis(record.expiresAtMs) : null,
          receivedAt: Timestamp.fromMillis(record.receivedAtMs),
          updatedAt: Timestamp.fromMillis(record.updatedAtMs)
        })
      );
      return { created: true };
    });
  }

  async claimInboxEvent(
    providerEventKey: string,
    nowMs: number,
    leaseOwner: string,
    leaseTtlMs: number = 60_000
  ): Promise<{ claimed: boolean; record: InboxEventRecord | null }> {
    const ref = this.db.collection("sepay_webhook_inbox").doc(providerEventKey);
    return this.db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) return { claimed: false, record: null };
      const cur = mapInboxEventDoc(snap.id, (snap.data() ?? {}) as Record<string, unknown>);

      const leaseExpired = cur.leaseExpiresAtMs == null || cur.leaseExpiresAtMs <= nowMs;
      const isEligiblePending = cur.state === "PENDING_PROCESSING" && leaseExpired;
      const isEligibleRetry =
        cur.state === "FAILED_RETRYABLE" &&
        (cur.nextRetryAtMs ?? 0) <= nowMs &&
        leaseExpired;

      if (!isEligiblePending && !isEligibleRetry) {
        return { claimed: false, record: cur };
      }

      const claimedRecord: InboxEventRecord = {
        ...cur,
        attemptCount: (cur.attemptCount ?? 0) + 1,
        leaseOwner,
        leaseExpiresAtMs: nowMs + leaseTtlMs,
        updatedAtMs: nowMs
      };
      tx.set(
        ref,
        stripUndefined({
          ...claimedRecord,
          updatedAt: Timestamp.fromMillis(nowMs)
        }),
        { merge: true }
      );
      return { claimed: true, record: claimedRecord };
    });
  }

  async updateInboxRecord(record: InboxEventRecord): Promise<void> {
    await this.db
      .collection("sepay_webhook_inbox")
      .doc(record.providerEventKey)
      .set(
        stripUndefined({
          ...record,
          expiresAt: record.expiresAtMs != null ? Timestamp.fromMillis(record.expiresAtMs) : null,
          updatedAt: Timestamp.fromMillis(record.updatedAtMs)
        }),
        { merge: true }
      );
  }

  async listRecoverableInboxRecords(
    nowMs: number,
    limit: number = 50,
    pendingGraceMs: number = 30_000
  ): Promise<{ records: InboxEventRecord[]; oldestPendingAgeMs: number }> {
    const [pendingSnap, retrySnap] = await Promise.all([
      this.db
        .collection("sepay_webhook_inbox")
        .where("state", "==", "PENDING_PROCESSING")
        .orderBy("receivedAtMs", "asc")
        .limit(limit * 3)
        .get(),
      this.db
        .collection("sepay_webhook_inbox")
        .where("state", "==", "FAILED_RETRYABLE")
        .where("nextRetryAtMs", "<=", nowMs)
        .orderBy("nextRetryAtMs", "asc")
        .limit(limit)
        .get()
    ]);

    const seen = new Set<string>();
    const candidates: Array<{ rec: InboxEventRecord; dueAtMs: number }> = [];
    let oldestPendingAgeMs = 0;

    for (const doc of pendingSnap.docs) {
      const rec = mapInboxEventDoc(doc.id, (doc.data() ?? {}) as Record<string, unknown>);
      const age = Math.max(0, nowMs - rec.receivedAtMs);
      if (age > oldestPendingAgeMs) oldestPendingAgeMs = age;

      const leaseExpired =
        rec.leaseExpiresAtMs != null
          ? rec.leaseExpiresAtMs <= nowMs
          : rec.receivedAtMs <= nowMs - pendingGraceMs;
      if (leaseExpired && !seen.has(rec.providerEventKey)) {
        seen.add(rec.providerEventKey);
        candidates.push({ rec, dueAtMs: rec.leaseExpiresAtMs ?? rec.receivedAtMs });
      }
    }

    for (const doc of retrySnap.docs) {
      const rec = mapInboxEventDoc(doc.id, (doc.data() ?? {}) as Record<string, unknown>);
      const age = Math.max(0, nowMs - rec.receivedAtMs);
      if (age > oldestPendingAgeMs) oldestPendingAgeMs = age;

      const leaseFree = rec.leaseExpiresAtMs == null || rec.leaseExpiresAtMs <= nowMs;
      if (leaseFree && !seen.has(rec.providerEventKey)) {
        seen.add(rec.providerEventKey);
        candidates.push({ rec, dueAtMs: rec.nextRetryAtMs ?? rec.receivedAtMs });
      }
    }

    candidates.sort((a, b) => a.dueAtMs - b.dueAtMs);
    return {
      records: candidates.slice(0, limit).map((c) => c.rec),
      oldestPendingAgeMs
    };
  }

  async purgeExpiredInboxRecords(
    nowMs: number,
    limit: number = 100
  ): Promise<{ purged: number; deletedCount: number }> {
    const expiredSnap = await this.db
      .collection("sepay_webhook_inbox")
      .where("expiresAtMs", "<=", nowMs)
      .orderBy("expiresAtMs", "asc")
      .limit(limit)
      .get();

    const refsToDelete = new Map<string, admin.firestore.DocumentReference>();
    for (const doc of expiredSnap.docs) {
      refsToDelete.set(doc.ref.path, doc.ref);
    }

    if (refsToDelete.size < limit) {
      const legacyCutoffMs = nowMs - INBOX_TERMINAL_TTL_MS;
      const legacyUnlinkedSnap = await this.db
        .collection("sepay_webhook_inbox")
        .where("ownerId", "==", null)
        .where("receivedAtMs", "<=", legacyCutoffMs)
        .limit(limit - refsToDelete.size)
        .get();
      for (const doc of legacyUnlinkedSnap.docs) {
        const d = doc.data() ?? {};
        if (d.expiresAtMs == null && !refsToDelete.has(doc.ref.path)) {
          refsToDelete.set(doc.ref.path, doc.ref);
        }
      }
    }

    if (refsToDelete.size === 0) {
      return { purged: 0, deletedCount: 0 };
    }

    const batch = this.db.batch();
    for (const ref of refsToDelete.values()) {
      batch.delete(ref);
    }
    await batch.commit();
    const purged = refsToDelete.size;
    return { purged, deletedCount: purged };
  }

  async claimNotificationOutbox(
    outboxId: string,
    nowMs: number,
    leaseOwner: string,
    leaseTtlMs: number = 60_000
  ): Promise<{ claimed: boolean; record: NotificationOutboxRecord | null }> {
    const ref = this.db.collection("notification_outbox").doc(outboxId);
    return this.db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) return { claimed: false, record: null };
      const cur = mapNotificationOutboxDoc(snap.id, (snap.data() ?? {}) as Record<string, unknown>);

      const isPending = cur.state === "PENDING" || cur.state === "PENDING_DELIVERY";
      const isDueRetry =
        cur.state === "FAILED_RETRYABLE" && (cur.nextRetryAtMs ?? 0) <= nowMs;
      const isExpiredDispatch =
        cur.state === "DISPATCHING" && (cur.leaseExpiresAtMs ?? 0) <= nowMs;

      if (!isPending && !isDueRetry && !isExpiredDispatch) {
        return { claimed: false, record: cur };
      }

      const dispatching: NotificationOutboxRecord = {
        ...cur,
        version: cur.version + 1,
        attemptCount: cur.attemptCount + 1,
        state: "DISPATCHING",
        leaseOwner: leaseOwner.trim() || "worker",
        leaseExpiresAtMs: nowMs + leaseTtlMs,
        updatedAtMs: nowMs
      };
      tx.set(ref, stripUndefined({ ...dispatching, updatedAt: Timestamp.fromMillis(nowMs) }), { merge: true });
      return { claimed: true, record: dispatching };
    });
  }

  async claimOutboxForDelivery(
    notificationId: string,
    nowMs: number
  ): Promise<{ claimed: boolean; record: NotificationOutboxRecord | null }> {
    return this.claimNotificationOutbox(notificationId, nowMs, "default_worker", 60_000);
  }

  async commitNotificationOutboxWithCas(params: {
    outboxId: string;
    expectedVersion: number;
    expectedLeaseOwner: string;
    nextRecord: NotificationOutboxRecord;
  }): Promise<{ committed: boolean; record: NotificationOutboxRecord | null }> {
    const ref = this.db.collection("notification_outbox").doc(params.outboxId);
    return this.db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) return { committed: false, record: null };
      const cur = mapNotificationOutboxDoc(snap.id, (snap.data() ?? {}) as Record<string, unknown>);

      if (
        cur.version !== params.expectedVersion ||
        cur.state !== "DISPATCHING" ||
        cur.leaseOwner !== params.expectedLeaseOwner
      ) {
        return { committed: false, record: cur };
      }

      const committedRecord: NotificationOutboxRecord = {
        ...params.nextRecord,
        version: params.expectedVersion + 1,
        leaseOwner: null,
        leaseExpiresAtMs: null
      };
      tx.set(
        ref,
        stripUndefined({
          ...committedRecord,
          updatedAt: Timestamp.fromMillis(committedRecord.updatedAtMs)
        }),
        { merge: true }
      );
      return { committed: true, record: committedRecord };
    });
  }

  async listRecoverableOutboxIds(nowMs: number, limit: number = 50): Promise<string[]> {
    const staleCutoffMs = nowMs - 30_000;
    const [retrySnap, dispatchingSnap, pendingDeliverySnap, pendingSnap] = await Promise.all([
      this.db
        .collection("notification_outbox")
        .where("state", "==", "FAILED_RETRYABLE")
        .where("nextRetryAtMs", "<=", nowMs)
        .orderBy("nextRetryAtMs", "asc")
        .limit(limit)
        .get(),
      this.db
        .collection("notification_outbox")
        .where("state", "==", "DISPATCHING")
        .where("leaseExpiresAtMs", "<=", nowMs)
        .orderBy("leaseExpiresAtMs", "asc")
        .limit(limit)
        .get(),
      this.db
        .collection("notification_outbox")
        .where("state", "==", "PENDING_DELIVERY")
        .where("createdAtMs", "<=", staleCutoffMs)
        .orderBy("createdAtMs", "asc")
        .limit(limit)
        .get(),
      this.db
        .collection("notification_outbox")
        .where("state", "==", "PENDING")
        .where("createdAtMs", "<=", staleCutoffMs)
        .orderBy("createdAtMs", "asc")
        .limit(limit)
        .get()
    ]);

    const seen = new Set<string>();
    const candidates: Array<{ id: string; dueAtMs: number }> = [];

    for (const doc of retrySnap.docs) {
      if (seen.has(doc.id)) continue;
      seen.add(doc.id);
      const d = doc.data() ?? {};
      candidates.push({ id: doc.id, dueAtMs: Number(d.nextRetryAtMs ?? 0) });
    }
    for (const doc of dispatchingSnap.docs) {
      if (seen.has(doc.id)) continue;
      seen.add(doc.id);
      const d = doc.data() ?? {};
      candidates.push({ id: doc.id, dueAtMs: Number(d.leaseExpiresAtMs ?? 0) });
    }
    for (const doc of [...pendingDeliverySnap.docs, ...pendingSnap.docs]) {
      if (seen.has(doc.id)) continue;
      seen.add(doc.id);
      const d = doc.data() ?? {};
      candidates.push({ id: doc.id, dueAtMs: Number(d.createdAtMs ?? 0) });
    }

    candidates.sort((a, b) => a.dueAtMs - b.dueAtMs);
    return candidates.slice(0, limit).map((c) => c.id);
  }

  async listDueRetryableOutboxRecords(nowMs: number, limit = 50): Promise<NotificationOutboxRecord[]> {
    const snap = await this.db
      .collection("notification_outbox")
      .where("state", "==", "FAILED_RETRYABLE")
      .where("nextRetryAtMs", "<=", nowMs)
      .orderBy("nextRetryAtMs", "asc")
      .limit(limit)
      .get();
    return snap.docs.map((doc) =>
      mapNotificationOutboxDoc(doc.id, (doc.data() ?? {}) as Record<string, unknown>)
    );
  }

  async getOutboxRecord(notificationId: string): Promise<NotificationOutboxRecord | null> {
    const snap = await this.db.collection("notification_outbox").doc(notificationId).get();
    return snap.exists ? mapNotificationOutboxDoc(snap.id, (snap.data() ?? {}) as Record<string, unknown>) : null;
  }

  async updateOutboxRecord(record: NotificationOutboxRecord): Promise<void> {
    await this.db
      .collection("notification_outbox")
      .doc(record.id)
      .set(stripUndefined({ ...record, updatedAt: Timestamp.fromMillis(record.updatedAtMs) }), { merge: true });
  }

  async commitReconciliationStateCas(params: {
    ownerId: string;
    connectionId: string;
    expectedGrantVersion: number;
    incomplete: boolean;
    newestValidExternalTxId: string | null;
    resumableCursor: BackfillCursorRecord | null;
    nowMs: number;
  }): Promise<{ committed: boolean; reason?: string; connection: ServerBankConnectionRecord | null }> {
    const serverRef = this.db.collection("server_bank_connections").doc(params.connectionId);
    const ts = Timestamp.fromMillis(params.nowMs);
    return this.db.runTransaction(async (tx) => {
      const snap = await tx.get(serverRef);
      if (!snap.exists) {
        return {
          committed: false,
          reason: "CONNECTION_NOT_FOUND",
          connection: null
        };
      }
      const conn = mapServerConnectionDoc(snap.id, (snap.data() ?? {}) as Record<string, unknown>);
      if (
        conn.ownerId !== params.ownerId ||
        !isConnectionActiveAndGranted(conn) ||
        (conn.grantVersion ?? 1) !== params.expectedGrantVersion
      ) {
        return {
          committed: false,
          reason: "CONNECTION_REVOKED_OR_GRANT_CHANGED",
          connection: conn
        };
      }

      const patch: Record<string, unknown> = params.incomplete
        ? {
            backfillCursor: params.resumableCursor,
            updatedAtMs: params.nowMs,
            updatedAt: ts
          }
        : {
            backfillCursor: null,
            lastReconciledAtMs: params.nowMs,
            lastReconciledAt: ts,
            ...(params.newestValidExternalTxId !== null
              ? {
                  lastSyncedExternalTxId: params.newestValidExternalTxId,
                  lastReconciledExternalTxId: params.newestValidExternalTxId
                }
              : {}),
            updatedAtMs: params.nowMs,
            updatedAt: ts
          };

      tx.set(serverRef, stripUndefined(patch), { merge: true });

      const updated: ServerBankConnectionRecord = params.incomplete
        ? {
            ...conn,
            backfillCursor: params.resumableCursor,
            updatedAtMs: params.nowMs
          }
        : {
            ...conn,
            backfillCursor: null,
            lastReconciledAtMs: params.nowMs,
            ...(params.newestValidExternalTxId !== null
              ? {
                  lastSyncedExternalTxId: params.newestValidExternalTxId,
                  lastReconciledExternalTxId: params.newestValidExternalTxId
                }
              : {}),
            updatedAtMs: params.nowMs
          };
      return { committed: true, connection: updated };
    });
  }

  async getUserNotificationPreferences(ownerId: string): Promise<UserNotificationPreferences> {
    const snap = await this.db
      .collection("users")
      .doc(ownerId)
      .collection("notification_preferences")
      .doc("settings")
      .get();
    if (!snap.exists) return DEFAULT_NOTIFICATION_PREFS;
    const d = snap.data() ?? {};
    return {
      notifyCredit: d.notifyCredit !== false,
      notifyDebit: d.notifyDebit !== false,
      minAmountMinor: typeof d.minAmountMinor === "number" ? d.minAmountMinor : 0,
      hideAmountOnLockscreen: d.hideAmountOnLockscreen !== false,
      hideCounterpartyAndContent: Boolean(d.hideCounterpartyAndContent),
      soundEnabled: d.soundEnabled !== false,
      mutedConnectionIds: Array.isArray(d.mutedConnectionIds)
        ? d.mutedConnectionIds.map(String)
        : [],
      notifyUnverified: d.notifyUnverified !== false
    };
  }

  async listActiveUserDevices(ownerId: string): Promise<UserDeviceRecord[]> {
    const snap = await this.db
      .collection("users")
      .doc(ownerId)
      .collection("devices")
      .where("pushEnabled", "==", true)
      .get();
    return snap.docs.map((doc) => {
      const d = doc.data();
      return {
        deviceId: doc.id,
        ownerId: String(d.ownerId ?? ownerId),
        fcmToken: String(d.fcmToken ?? ""),
        platform: (d.platform as UserDeviceRecord["platform"]) ?? "android",
        pushEnabled: Boolean(d.pushEnabled),
        updatedAtMs: Date.now()
      };
    });
  }

  async deactivateInvalidTokens(ownerId: string, invalidTokens: readonly string[]): Promise<void> {
    if (invalidTokens.length === 0) return;
    const snap = await this.db.collection("users").doc(ownerId).collection("devices").get();
    const batch = this.db.batch();
    for (const doc of snap.docs) {
      const tok = String(doc.data().fcmToken ?? "");
      if (invalidTokens.includes(tok)) {
        batch.update(doc.ref, {
          pushEnabled: false,
          invalidatedAt: Timestamp.now()
        });
      }
    }
    await batch.commit();
  }

  async readAndDeleteLegacySePayConsent(ownerId: string): Promise<{
    apiToken?: string;
    bankCode?: string;
    accountNumber?: string;
    walletId?: string;
  } | null> {
    const legacyRef = this.db.collection("users").doc(ownerId).collection("consents").doc("sepay_api");
    const snap = await legacyRef.get();
    if (!snap.exists) return null;
    const d = snap.data() ?? {};
    const extracted = {
      apiToken: typeof d.apiToken === "string" ? d.apiToken : undefined,
      bankCode: typeof d.bankCode === "string" ? d.bankCode : undefined,
      accountNumber: typeof d.accountNumber === "string" ? d.accountNumber : undefined,
      walletId: typeof d.walletId === "string" ? d.walletId : undefined
    };
    await legacyRef.delete();
    return extracted;
  }
}

export { resolveBankCapability };
