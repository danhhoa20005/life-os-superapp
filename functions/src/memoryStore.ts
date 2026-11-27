import {
  BackfillCursorRecord,
  BankAccountClaimRecord,
  BankingBackendStore,
  BankingTxContext,
  CanonicalTransactionRecord,
  DEFAULT_NOTIFICATION_PREFS,
  FinancialNotificationRecord,
  InboxEventRecord,
  NotificationOutboxRecord,
  ServerBankConnectionRecord,
  UserDeviceRecord,
  UserNotificationPreferences,
  WalletRecord,
  isConnectionActiveAndGranted
} from "./bankingEngine";
import { INBOX_TERMINAL_TTL_MS } from "./schema";

/**
 * Serialized mutex-protected transactional store matching Cloud Firestore ACID transaction semantics
 * for fast, deterministic concurrency (`Promise.all`), retry, and fault-injection verification.
 */
export class SerializedMemoryBankingStore implements BankingBackendStore {
  public readonly serverConnections = new Map<string, ServerBankConnectionRecord>();
  public readonly bankAccountClaims = new Map<string, BankAccountClaimRecord>();
  public readonly userConnections = new Map<string, Map<string, Record<string, unknown>>>();
  public readonly inbox = new Map<string, InboxEventRecord>();
  public readonly outbox = new Map<string, NotificationOutboxRecord>();
  public readonly sourceEvents = new Map<string, { linkedTransactionId: string }>();
  public readonly serverSourceEvents = new Map<
    string,
    {
      ownerId: string;
      eventKey: string;
      linkedTransactionId: string;
      connectionId?: string;
      source: string;
      status: string;
      receivedAtMs: number;
    }
  >();
  public readonly accountDeletionTombstones = new Map<string, Record<string, unknown>>();
  public readonly wallets = new Map<string, WalletRecord>();
  public readonly transactions = new Map<string, CanonicalTransactionRecord>();
  public readonly audits = new Map<string, Record<string, unknown>>();
  public readonly financialNotifications = new Map<string, FinancialNotificationRecord>();
  public readonly userPrefs = new Map<string, UserNotificationPreferences>();
  public readonly userDevices = new Map<string, UserDeviceRecord[]>();
  public readonly legacyConsents = new Map<
    string,
    { apiToken?: string; bankCode?: string; accountNumber?: string; walletId?: string }
  >();

  public simulateInboxWriteFailure = false;
  private mutexChain: Promise<unknown> = Promise.resolve();

  async runAtomic<T>(fn: (ctx: BankingTxContext) => Promise<T>): Promise<T> {
    const run = async (): Promise<T> => {
      const ctx: BankingTxContext = {
        isUserDeletionFrozen: async (ownerId) =>
          this.accountDeletionTombstones.has(ownerId.trim()),
        getConnectionById: async (connectionId) =>
          this.serverConnections.get(connectionId) ?? null,
        getInboxEvent: async (key) => this.inbox.get(key) ?? null,
        setInboxEvent: async (rec) => {
          this.inbox.set(rec.providerEventKey, rec);
        },
        getSourceEvent: async (ownerId, eventKey) =>
          this.sourceEvents.get(`${ownerId}::${eventKey}`) ?? null,
        setSourceEvent: async (ownerId, eventKey, data) => {
          this.sourceEvents.set(`${ownerId}::${eventKey}`, {
            linkedTransactionId: data.linkedTransactionId
          });
        },
        getServerSourceEvent: async (ownerId, eventKey) => {
          const rec = this.serverSourceEvents.get(`${ownerId}::${eventKey}`);
          return rec ? { linkedTransactionId: rec.linkedTransactionId } : null;
        },
        setServerSourceEvent: async (ownerId, eventKey, data) => {
          this.serverSourceEvents.set(`${ownerId}::${eventKey}`, {
            ownerId,
            eventKey,
            linkedTransactionId: data.linkedTransactionId,
            connectionId: data.connectionId,
            source: data.source,
            status: data.status,
            receivedAtMs: data.receivedAtMs
          });
        },
        findCandidateTransactions: async (ownerId, softFps) => {
          const res: CanonicalTransactionRecord[] = [];
          for (const tx of this.transactions.values()) {
            if (tx.ownerId === ownerId && softFps.includes(tx.softWindowFingerprint)) {
              res.push(tx);
            }
          }
          return res;
        },
        getWallet: async (ownerId, walletId) =>
          this.wallets.get(`${ownerId}::${walletId}`) ?? null,
        upsertWallet: async (ownerId, wallet) => {
          this.wallets.set(`${ownerId}::${wallet.id}`, wallet);
        },
        upsertTransaction: async (ownerId, tx) => {
          this.transactions.set(`${ownerId}::${tx.id}`, tx);
        },
        appendLedgerAudit: async (ownerId, auditId, data) => {
          this.audits.set(`${ownerId}::${auditId}`, data);
        },
        upsertFinancialNotification: async (ownerId, notif) => {
          this.financialNotifications.set(`${ownerId}::${notif.id}`, notif);
        },
        upsertNotificationOutbox: async (outboxRec) => {
          this.outbox.set(outboxRec.id, outboxRec);
        },
        updateConnectionLastSync: async (_ownerId, connectionId, syncedAtMs) => {
          const c = this.serverConnections.get(connectionId);
          if (c) {
            this.serverConnections.set(connectionId, {
              ...c,
              lastSyncedAtMs: syncedAtMs,
              updatedAtMs: syncedAtMs
            });
          }
        },
        markConnectionWarning: async (ownerId, connectionId, warning, nowMs) => {
          const c = this.serverConnections.get(connectionId);
          if (c && c.ownerId === ownerId) {
            this.serverConnections.set(connectionId, {
              ...c,
              statusWarning: warning,
              updatedAtMs: nowMs
            });
          }
          const userMap = this.userConnections.get(ownerId);
          const mirror = userMap?.get(connectionId);
          if (userMap && mirror) {
            userMap.set(connectionId, {
              ...mirror,
              statusWarning: warning,
              updatedAtMs: nowMs
            });
          }
        },
        getBankAccountClaim: async (claimId) => this.bankAccountClaims.get(claimId) ?? null,
        upsertBankAccountClaim: async (claim) => {
          this.bankAccountClaims.set(claim.claimId, claim);
        },
        saveVerifiedConnectionTx: async (record) => {
          await this.saveVerifiedConnection(record);
        }
      };
      return fn(ctx);
    };

    const next = this.mutexChain.then(run, run);
    this.mutexChain = next.then(
      () => undefined,
      () => undefined
    );
    return next;
  }

  async isUserDeletionFrozen(ownerId: string): Promise<boolean> {
    return this.accountDeletionTombstones.has(ownerId.trim());
  }

  async getConnectionById(connectionId: string): Promise<ServerBankConnectionRecord | null> {
    return this.serverConnections.get(connectionId) ?? null;
  }

  async findActiveConnectionForAccount(params: {
    bankCode: string;
    gateway: string;
    accountNumber: string;
    subAccount: string;
  }): Promise<ServerBankConnectionRecord | null> {
    const incomingSub = String(params.subAccount ?? "").trim();
    for (const c of this.serverConnections.values()) {
      if (!isConnectionActiveAndGranted(c)) continue;
      if (c.accountNumber !== params.accountNumber) continue;
      if (c.bankCode.toUpperCase() !== params.bankCode.toUpperCase()) continue;
      const expectedSub = String(c.subAccount ?? "").trim();
      if (expectedSub !== incomingSub) continue;
      return c;
    }
    return null;
  }

  async findAnyVerifiedConnectionByAccount(
    bankCode: string,
    accountNumber: string,
    subAccount?: string
  ): Promise<ServerBankConnectionRecord | null> {
    const expectedSub = String(subAccount ?? "").trim().toUpperCase();
    for (const c of this.serverConnections.values()) {
      if (
        c.bankCode.toUpperCase() === bankCode.toUpperCase() &&
        c.accountNumber === accountNumber &&
        isConnectionActiveAndGranted(c)
      ) {
        const docSub = String(c.subAccount ?? "").trim().toUpperCase();
        if (expectedSub !== docSub) continue;
        return c;
      }
    }
    return null;
  }

  async saveVerifiedConnection(record: ServerBankConnectionRecord): Promise<void> {
    this.serverConnections.set(record.id, record);
    if (!this.userConnections.has(record.ownerId)) {
      this.userConnections.set(record.ownerId, new Map());
    }
    this.userConnections.get(record.ownerId)!.set(record.id, {
      id: record.id,
      ownerId: record.ownerId,
      provider: record.provider,
      providerConnectionId: record.providerConnectionId,
      bankCode: record.bankCode,
      bankName: record.bankName,
      accountMasked: record.accountMasked,
      subAccount: record.subAccount,
      linkedWalletId: record.linkedWalletId,
      consentStatus: record.consentStatus,
      consentEnabled: record.consentEnabled !== false,
      grantVersion: record.grantVersion ?? 1,
      status: record.status,
      updatedAtMs: record.updatedAtMs
    });
  }

  async disconnectConnection(ownerId: string, connectionId: string, nowMs: number): Promise<void> {
    await this.runAtomic(async () => {
      const c = this.serverConnections.get(connectionId);
      if (c && c.ownerId !== ownerId) {
        throw new Error("FORBIDDEN_CONNECTION_OWNER");
      }
      const nextGrantVersion =
        (c && typeof c.grantVersion === "number" ? c.grantVersion : 1) + 1;
      if (c && c.ownerId === ownerId) {
        this.serverConnections.set(connectionId, {
          ...c,
          status: "revoked",
          consentStatus: "revoked",
          consentEnabled: false,
          grantVersion: nextGrantVersion,
          revokedAtMs: nowMs,
          updatedAtMs: nowMs
        });
      }
      if (!this.userConnections.has(ownerId)) {
        this.userConnections.set(ownerId, new Map());
      }
      const existingUserMirror = this.userConnections.get(ownerId)!.get(connectionId) ?? {};
      this.userConnections.get(ownerId)!.set(connectionId, {
        ...existingUserMirror,
        id: connectionId,
        ownerId,
        status: "disconnected",
        consentStatus: "revoked",
        consentEnabled: false,
        grantVersion: nextGrantVersion,
        revokedAtMs: nowMs,
        updatedAtMs: nowMs
      });
      for (const [claimId, claim] of this.bankAccountClaims.entries()) {
        if (claim.ownerId === ownerId && claim.connectionId === connectionId) {
          this.bankAccountClaims.set(claimId, {
            ...claim,
            status: "disconnected",
            updatedAtMs: nowMs
          });
        }
      }
    });
  }

  async revokeConnection(ownerId: string, connectionId: string, nowMs: number = Date.now()): Promise<void> {
    return this.disconnectConnection(ownerId, connectionId, nowMs);
  }

  async getInboxEvent(providerEventKey: string): Promise<InboxEventRecord | null> {
    return this.inbox.get(providerEventKey) ?? null;
  }

  async createDurableInboxIfAbsent(
    record: InboxEventRecord
  ): Promise<{ created: boolean; existing?: InboxEventRecord }> {
    if (this.simulateInboxWriteFailure) {
      throw new Error("SIMULATED_FIRESTORE_WRITE_ERROR");
    }
    return this.runAtomic(async () => {
      const existing = this.inbox.get(record.providerEventKey);
      if (existing) {
        return { created: false, existing };
      }
      this.inbox.set(record.providerEventKey, record);
      return { created: true };
    });
  }

  async claimInboxEvent(
    providerEventKey: string,
    nowMs: number,
    leaseOwner: string,
    leaseTtlMs: number = 60_000
  ): Promise<{ claimed: boolean; record: InboxEventRecord | null }> {
    return this.runAtomic(async () => {
      const cur = this.inbox.get(providerEventKey) ?? null;
      if (!cur) return { claimed: false, record: null };

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
      this.inbox.set(providerEventKey, claimedRecord);
      return { claimed: true, record: claimedRecord };
    });
  }

  async updateInboxRecord(record: InboxEventRecord): Promise<void> {
    this.inbox.set(record.providerEventKey, record);
  }

  async listRecoverableInboxRecords(
    nowMs: number,
    limit: number = 50,
    pendingGraceMs: number = 30_000
  ): Promise<{ records: InboxEventRecord[]; oldestPendingAgeMs: number }> {
    const candidates: Array<{ rec: InboxEventRecord; dueAtMs: number }> = [];
    let oldestPendingAgeMs = 0;

    for (const rec of this.inbox.values()) {
      if (rec.state !== "PENDING_PROCESSING" && rec.state !== "FAILED_RETRYABLE") {
        continue;
      }
      const age = Math.max(0, nowMs - rec.receivedAtMs);
      if (age > oldestPendingAgeMs) {
        oldestPendingAgeMs = age;
      }

      if (rec.state === "PENDING_PROCESSING") {
        const leaseExpired =
          rec.leaseExpiresAtMs != null
            ? rec.leaseExpiresAtMs <= nowMs
            : rec.receivedAtMs <= nowMs - pendingGraceMs;
        if (leaseExpired) {
          candidates.push({
            rec,
            dueAtMs: rec.leaseExpiresAtMs ?? rec.receivedAtMs
          });
        }
      } else if (rec.state === "FAILED_RETRYABLE") {
        const due = (rec.nextRetryAtMs ?? 0) <= nowMs;
        const leaseFree = rec.leaseExpiresAtMs == null || rec.leaseExpiresAtMs <= nowMs;
        if (due && leaseFree) {
          candidates.push({
            rec,
            dueAtMs: rec.nextRetryAtMs ?? rec.receivedAtMs
          });
        }
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
    let purged = 0;
    for (const [key, rec] of this.inbox.entries()) {
      if (purged >= limit) break;
      const expiredByTtl = rec.expiresAtMs != null && rec.expiresAtMs <= nowMs;
      const expiredLegacyUnlinked =
        rec.ownerId === null &&
        rec.expiresAtMs == null &&
        rec.receivedAtMs <= nowMs - INBOX_TERMINAL_TTL_MS;
      if (expiredByTtl || expiredLegacyUnlinked) {
        this.inbox.delete(key);
        purged += 1;
      }
    }
    return { purged, deletedCount: purged };
  }

  async claimNotificationOutbox(
    outboxId: string,
    nowMs: number,
    leaseOwner: string,
    leaseTtlMs: number = 60_000
  ): Promise<{ claimed: boolean; record: NotificationOutboxRecord | null }> {
    return this.runAtomic(async () => {
      const cur = this.outbox.get(outboxId) ?? null;
      if (!cur) return { claimed: false, record: null };

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
        version: (typeof cur.version === "number" ? cur.version : 1) + 1,
        attemptCount: (typeof cur.attemptCount === "number" ? cur.attemptCount : 0) + 1,
        state: "DISPATCHING",
        leaseOwner: leaseOwner.trim() || "worker",
        leaseExpiresAtMs: nowMs + leaseTtlMs,
        updatedAtMs: nowMs
      };
      this.outbox.set(outboxId, dispatching);
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
    return this.runAtomic(async () => {
      const cur = this.outbox.get(params.outboxId) ?? null;
      if (!cur) return { committed: false, record: null };

      if (
        (typeof cur.version === "number" ? cur.version : 1) !== params.expectedVersion ||
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
      this.outbox.set(params.outboxId, committedRecord);
      return { committed: true, record: committedRecord };
    });
  }

  async listRecoverableOutboxIds(nowMs: number, limit: number = 50): Promise<string[]> {
    const staleCutoffMs = nowMs - 30_000;
    const candidates: Array<{ id: string; dueAtMs: number }> = [];

    for (const rec of this.outbox.values()) {
      if (rec.state === "FAILED_RETRYABLE" && (rec.nextRetryAtMs ?? 0) <= nowMs) {
        candidates.push({ id: rec.id, dueAtMs: rec.nextRetryAtMs ?? 0 });
      } else if (rec.state === "DISPATCHING" && (rec.leaseExpiresAtMs ?? 0) <= nowMs) {
        candidates.push({ id: rec.id, dueAtMs: rec.leaseExpiresAtMs ?? 0 });
      } else if (
        (rec.state === "PENDING" || rec.state === "PENDING_DELIVERY") &&
        rec.createdAtMs <= staleCutoffMs
      ) {
        candidates.push({ id: rec.id, dueAtMs: rec.createdAtMs });
      }
    }

    candidates.sort((a, b) => a.dueAtMs - b.dueAtMs);
    return candidates.slice(0, limit).map((c) => c.id);
  }

  async listDueRetryableOutboxRecords(nowMs: number, limit = 50): Promise<NotificationOutboxRecord[]> {
    const due: NotificationOutboxRecord[] = [];
    for (const rec of this.outbox.values()) {
      if (rec.state === "FAILED_RETRYABLE" && (typeof rec.nextRetryAtMs !== "number" || rec.nextRetryAtMs <= nowMs)) {
        due.push(rec);
      }
    }
    due.sort((a, b) => (a.nextRetryAtMs ?? 0) - (b.nextRetryAtMs ?? 0));
    return due.slice(0, limit);
  }

  async getOutboxRecord(notificationId: string): Promise<NotificationOutboxRecord | null> {
    return this.outbox.get(notificationId) ?? null;
  }

  async updateOutboxRecord(record: NotificationOutboxRecord): Promise<void> {
    this.outbox.set(record.id, record);
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
    return this.runAtomic(async () => {
      const conn = this.serverConnections.get(params.connectionId) ?? null;
      if (
        !conn ||
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

      this.serverConnections.set(conn.id, updated);
      return { committed: true, connection: updated };
    });
  }

  async getUserNotificationPreferences(ownerId: string): Promise<UserNotificationPreferences> {
    return this.userPrefs.get(ownerId) ?? DEFAULT_NOTIFICATION_PREFS;
  }

  async listActiveUserDevices(ownerId: string): Promise<UserDeviceRecord[]> {
    return (this.userDevices.get(ownerId) ?? []).filter((d) => d.pushEnabled);
  }

  async deactivateInvalidTokens(ownerId: string, invalidTokens: readonly string[]): Promise<void> {
    const cur = this.userDevices.get(ownerId) ?? [];
    this.userDevices.set(
      ownerId,
      cur.map((d) => (invalidTokens.includes(d.fcmToken) ? { ...d, pushEnabled: false } : d))
    );
  }

  async readAndDeleteLegacySePayConsent(ownerId: string) {
    const v = this.legacyConsents.get(ownerId) ?? null;
    this.legacyConsents.delete(ownerId);
    return v;
  }
}
