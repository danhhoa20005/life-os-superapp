import {
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
  WalletRecord
} from "./bankingEngine";

/**
 * Serialized mutex-protected transactional store matching Cloud Firestore ACID transaction semantics
 * for fast, deterministic concurrency (`Promise.all`), retry, and fault-injection verification.
 */
export class SerializedMemoryBankingStore implements BankingBackendStore {
  public readonly serverConnections = new Map<string, ServerBankConnectionRecord>();
  public readonly userConnections = new Map<string, Map<string, Record<string, unknown>>>();
  public readonly inbox = new Map<string, InboxEventRecord>();
  public readonly outbox = new Map<string, NotificationOutboxRecord>();
  public readonly sourceEvents = new Map<string, { linkedTransactionId: string }>();
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

  async findActiveConnectionForAccount(params: {
    bankCode: string;
    gateway: string;
    accountNumber: string;
    subAccount: string;
  }): Promise<ServerBankConnectionRecord | null> {
    for (const c of this.serverConnections.values()) {
      if (c.status !== "connected" || c.consentStatus !== "granted") continue;
      if (c.accountNumber !== params.accountNumber) continue;
      if (c.bankCode.toUpperCase() !== params.bankCode.toUpperCase()) continue;
      if (params.subAccount && c.subAccount && c.subAccount !== params.subAccount) continue;
      return c;
    }
    return null;
  }

  async findAnyVerifiedConnectionByAccount(
    bankCode: string,
    accountNumber: string
  ): Promise<ServerBankConnectionRecord | null> {
    for (const c of this.serverConnections.values()) {
      if (
        c.bankCode.toUpperCase() === bankCode.toUpperCase() &&
        c.accountNumber === accountNumber &&
        c.status === "connected"
      ) {
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
      bankCode: record.bankCode,
      bankName: record.bankName,
      accountMasked: record.accountMasked,
      linkedWalletId: record.linkedWalletId,
      status: record.status
    });
  }

  async disconnectConnection(ownerId: string, connectionId: string, nowMs: number): Promise<void> {
    const c = this.serverConnections.get(connectionId);
    if (c && c.ownerId === ownerId) {
      this.serverConnections.set(connectionId, {
        ...c,
        status: "disconnected",
        consentStatus: "revoked",
        updatedAtMs: nowMs
      });
    }
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

  async claimOutboxForDelivery(
    notificationId: string,
    nowMs: number
  ): Promise<{ claimed: boolean; record: NotificationOutboxRecord | null }> {
    return this.runAtomic(async () => {
      const cur = this.outbox.get(notificationId) ?? null;
      if (!cur) return { claimed: false, record: null };
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
      this.outbox.set(notificationId, dispatching);
      return { claimed: true, record: dispatching };
    });
  }

  async listDueRetryableOutboxRecords(nowMs: number, limit = 50): Promise<NotificationOutboxRecord[]> {
    const due: NotificationOutboxRecord[] = [];
    for (const rec of this.outbox.values()) {
      if (rec.state === "FAILED_RETRYABLE" && (typeof rec.nextRetryAtMs !== "number" || rec.nextRetryAtMs <= nowMs)) {
        due.push(rec);
        if (due.length >= limit) break;
      }
    }
    return due;
  }

  async getOutboxRecord(notificationId: string): Promise<NotificationOutboxRecord | null> {
    return this.outbox.get(notificationId) ?? null;
  }

  async updateOutboxRecord(record: NotificationOutboxRecord): Promise<void> {
    this.outbox.set(record.id, record);
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
