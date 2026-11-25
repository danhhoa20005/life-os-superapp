import * as admin from "firebase-admin";
import { Timestamp } from "firebase-admin/firestore";
import {
  BankingBackendStore,
  BankingTxContext,
  CanonicalTransactionRecord,
  DEFAULT_NOTIFICATION_PREFS,
  FcmMulticastResult,
  FcmPushSender,
  InboxEventRecord,
  NotificationOutboxRecord,
  ServerBankConnectionRecord,
  UserDeviceRecord,
  UserNotificationPreferences
} from "./bankingEngine";
import { resolveBankCapability } from "./capabilities";
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
    let retryableError: string | undefined;

    res.responses.forEach((r, idx) => {
      if (!r.success && r.error) {
        const code = r.error.code;
        if (
          code === "messaging/registration-token-not-registered" ||
          code === "messaging/invalid-registration-token"
        ) {
          invalidTokens.push(params.tokens[idx]);
        } else {
          retryableError = `${code}: ${r.error.message}`;
        }
      }
    });

    return {
      successCount: res.successCount,
      failureCount: res.failureCount,
      invalidTokens,
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

export class FirestoreAdminBankingStore implements BankingBackendStore {
  constructor(private readonly db: admin.firestore.Firestore) {}

  async runAtomic<T>(fn: (ctx: BankingTxContext) => Promise<T>): Promise<T> {
    return this.db.runTransaction(async (tx) => {
      const ctx: BankingTxContext = {
        getInboxEvent: async (providerEventKey) => {
          const snap = await tx.get(this.db.collection("sepay_webhook_inbox").doc(providerEventKey));
          return snap.exists ? (snap.data() as InboxEventRecord) : null;
        },
        setInboxEvent: async (record) => {
          tx.set(
            this.db.collection("sepay_webhook_inbox").doc(record.providerEventKey),
            stripUndefined({
              ...record,
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
            bankCode: typeof d.bankCode === "string" ? d.bankCode : undefined,
            maskedAccount: typeof d.maskedAccount === "string" ? d.maskedAccount : undefined,
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
        }
      };

      return fn(ctx);
    });
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
      .where("status", "==", "connected")
      .get();

    for (const doc of snap.docs) {
      const d = doc.data() as ServerBankConnectionRecord;
      if (d.consentStatus !== "granted") continue;
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
    accountNumber: string
  ): Promise<ServerBankConnectionRecord | null> {
    const snap = await this.db
      .collection("server_bank_connections")
      .where("bankCode", "==", bankCode)
      .where("accountNumber", "==", accountNumber)
      .where("status", "==", "connected")
      .limit(1)
      .get();
    if (snap.empty) return null;
    return snap.docs[0].data() as ServerBankConnectionRecord;
  }

  async saveVerifiedConnection(record: ServerBankConnectionRecord): Promise<void> {
    const batch = this.db.batch();
    const ts = Timestamp.fromMillis(record.updatedAtMs);
    batch.set(this.db.collection("server_bank_connections").doc(record.id), stripUndefined({ ...record }));
    // User-readable document NEVER stores full accountNumber or provider tokens (Section 7 & 14)
    batch.set(
      this.db.collection("users").doc(record.ownerId).collection("bank_connections").doc(record.id),
      {
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
        status: record.status,
        capabilities: record.capabilities,
        lastSyncedAt: ts,
        createdAt: Timestamp.fromMillis(record.createdAtMs),
        updatedAt: ts
      }
    );
    await batch.commit();
  }

  async disconnectConnection(ownerId: string, connectionId: string, nowMs: number): Promise<void> {
    const serverRef = this.db.collection("server_bank_connections").doc(connectionId);
    const snap = await serverRef.get();
    if (snap.exists && snap.data()?.ownerId !== ownerId) {
      throw new Error("FORBIDDEN_CONNECTION_OWNER");
    }
    const ts = Timestamp.fromMillis(nowMs);
    const batch = this.db.batch();
    batch.set(
      serverRef,
      { status: "disconnected", consentStatus: "revoked", updatedAtMs: nowMs },
      { merge: true }
    );
    batch.set(
      this.db.collection("users").doc(ownerId).collection("bank_connections").doc(connectionId),
      { status: "disconnected", consentStatus: "revoked", updatedAt: ts },
      { merge: true }
    );
    await batch.commit();
  }

  async getInboxEvent(providerEventKey: string): Promise<InboxEventRecord | null> {
    const snap = await this.db.collection("sepay_webhook_inbox").doc(providerEventKey).get();
    return snap.exists ? (snap.data() as InboxEventRecord) : null;
  }

  async createDurableInboxIfAbsent(
    record: InboxEventRecord
  ): Promise<{ created: boolean; existing?: InboxEventRecord }> {
    const ref = this.db.collection("sepay_webhook_inbox").doc(record.providerEventKey);
    return this.db.runTransaction(async (tx) => {
      const existing = await tx.get(ref);
      if (existing.exists) {
        return { created: false, existing: existing.data() as InboxEventRecord };
      }
      tx.set(
        ref,
        stripUndefined({
          ...record,
          receivedAt: Timestamp.fromMillis(record.receivedAtMs),
          updatedAt: Timestamp.fromMillis(record.updatedAtMs)
        })
      );
      return { created: true };
    });
  }

  async claimOutboxForDelivery(
    notificationId: string,
    nowMs: number
  ): Promise<{ claimed: boolean; record: NotificationOutboxRecord | null }> {
    const ref = this.db.collection("notification_outbox").doc(notificationId);
    return this.db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) return { claimed: false, record: null };
      const cur = snap.data() as NotificationOutboxRecord;
      if (cur.state !== "PENDING_DELIVERY" && cur.state !== "FAILED_RETRYABLE") {
        return { claimed: false, record: cur };
      }
      if (cur.state === "FAILED_RETRYABLE" && typeof cur.nextRetryAtMs === "number" && cur.nextRetryAtMs > nowMs) {
        return { claimed: false, record: cur };
      }
      const dispatching: NotificationOutboxRecord = {
        ...cur,
        state: "DISPATCHING",
        updatedAtMs: nowMs
      };
      tx.set(ref, stripUndefined({ ...dispatching, updatedAt: Timestamp.fromMillis(nowMs) }), { merge: true });
      return { claimed: true, record: dispatching };
    });
  }

  async listDueRetryableOutboxRecords(nowMs: number, limit = 50): Promise<NotificationOutboxRecord[]> {
    const snap = await this.db
      .collection("notification_outbox")
      .where("state", "==", "FAILED_RETRYABLE")
      .limit(limit * 2)
      .get();
    const due: NotificationOutboxRecord[] = [];
    for (const doc of snap.docs) {
      const rec = doc.data() as NotificationOutboxRecord;
      if (typeof rec.nextRetryAtMs !== "number" || rec.nextRetryAtMs <= nowMs) {
        due.push(rec);
        if (due.length >= limit) break;
      }
    }
    return due;
  }

  async getOutboxRecord(notificationId: string): Promise<NotificationOutboxRecord | null> {
    const snap = await this.db.collection("notification_outbox").doc(notificationId).get();
    return snap.exists ? (snap.data() as NotificationOutboxRecord) : null;
  }

  async updateOutboxRecord(record: NotificationOutboxRecord): Promise<void> {
    await this.db
      .collection("notification_outbox")
      .doc(record.id)
      .set(stripUndefined({ ...record, updatedAt: Timestamp.fromMillis(record.updatedAtMs) }), { merge: true });
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
