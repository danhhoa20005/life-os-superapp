import * as crypto from "node:crypto";
import {
  BankIntegrationCapability,
  checkWebhookDirectionSupport,
  resolveBankCapability
} from "./capabilities";
import {
  BackfillCursorRecord,
  BalanceType,
  INBOX_DEAD_LETTER_TTL_MS,
  INBOX_TERMINAL_TTL_MS,
  InboxEventRecord,
  InboxProcessingState,
  NotificationOutboxRecord,
  ServerBankConnectionRecord,
  ValidatedSePayWebhookPayload,
  VerificationStatus,
  classifyVietnameseTransaction,
  computeCrossSourceFingerprint,
  computeOverlappingSoftWindowFingerprints,
  computeSoftWindowFingerprint,
  evaluateMonotonicObservedBalance,
  extractAccountTail,
  formatVndCompactNotification,
  isConnectionActiveAndGranted,
  minimizeInboxPayload,
  parseAndValidateSePayPayload
} from "./schema";
export type {
  BackfillCursorRecord,
  InboxEventRecord,
  NotificationOutboxEvent,
  NotificationOutboxRecord,
  NotificationOutboxState,
  SepayWebhookInboxEvent,
  ServerBankConnection,
  ServerBankConnectionRecord
} from "./schema";
export {
  evaluateMonotonicObservedBalance,
  extractAccountTail,
  isConnectionActiveAndGranted
} from "./schema";
import {
  MAX_WEBHOOK_BODY_BYTES,
  maskAccountNumber,
  sha256Hex,
  verifySePayWebhookSignature
} from "./security";

export interface SePayBankAccountApiItem {
  readonly id?: string | number;
  readonly account_number?: string;
  readonly bank_short_name?: string;
  readonly bank_code?: string;
  readonly bank_brand_name?: string;
  readonly bank_name?: string;
  readonly sub_account?: string;
  readonly va?: string;
  readonly accumulated?: number | string;
  readonly active?: boolean | number | string;
  readonly status?: string;
}

export interface BankAccountClaimRecord {
  readonly claimId: string;
  readonly ownerId: string;
  readonly connectionId: string;
  readonly provider: "sepay";
  readonly providerConnectionId: string;
  readonly providerAccountId?: string;
  readonly bankCode: string;
  readonly accountNumber: string;
  readonly subAccount: string;
  readonly status: "connected" | "disconnected";
  readonly updatedAtMs: number;
}

export function buildNormalizedAccountClaimId(
  bankCode: string,
  accountNumber: string,
  subAccount = ""
): string {
  const cleanBank = bankCode.trim().toUpperCase();
  const cleanAcc = accountNumber.replace(/[^A-Za-z0-9]/g, "").trim();
  const cleanSub = subAccount.trim().toUpperCase();
  return `sepay_acct_${sha256Hex(`${cleanBank}:${cleanAcc}:${cleanSub}`).slice(0, 28)}`;
}

export function buildProviderAccountIdClaimId(providerAccountId: string): string {
  return `sepay_id_${sha256Hex(providerAccountId.trim()).slice(0, 28)}`;
}

export function isSePayAccountActive(acc: SePayBankAccountApiItem): boolean {
  if (acc.active !== undefined && acc.active !== null) {
    if (typeof acc.active === "boolean") {
      if (!acc.active) return false;
    } else if (typeof acc.active === "number") {
      if (acc.active !== 1) return false;
    } else if (typeof acc.active === "string") {
      const norm = acc.active.trim().toLowerCase();
      if (!["1", "true", "active", "enabled", "yes"].includes(norm)) return false;
    } else {
      return false;
    }
  }
  if (acc.status !== undefined && acc.status !== null) {
    const normStatus = String(acc.status).trim().toLowerCase();
    if (!normStatus) return false;
    if (!["1", "true", "active", "connected", "enabled"].includes(normStatus)) {
      return false;
    }
  }
  return true;
}

export function resolveSePayItemBankCapability(
  acc: SePayBankAccountApiItem
): { capability: BankIntegrationCapability | null; ambiguous: boolean } {
  const hints = [acc.bank_short_name, acc.bank_code, acc.bank_brand_name, acc.bank_name]
    .filter((v): v is string => typeof v === "string" && v.trim().length > 0);
  const resolved: BankIntegrationCapability[] = [];
  for (const hint of hints) {
    const cap = resolveBankCapability(hint);
    if (cap && !resolved.some((r) => r.bankCode === cap.bankCode)) {
      resolved.push(cap);
    }
  }
  if (resolved.length === 0) return { capability: null, ambiguous: false };
  if (resolved.length > 1) return { capability: null, ambiguous: true };
  return { capability: resolved[0], ambiguous: false };
}

export type SePayMatchResult =
  | {
      readonly ok: true;
      readonly capability: BankIntegrationCapability;
      readonly accountNumber: string;
      readonly subAccount: string;
      readonly providerAccountId: string;
      readonly providerConnectionId: string;
      readonly observedAccumulatedMinor: number | null;
    }
  | { readonly ok: false; readonly errorCode: string };

export function matchVerifiedSePayAccount(params: {
  sepayAccounts: readonly SePayBankAccountApiItem[];
  requestedBankCode: string;
  requestedAccountNumber: string;
  requestedSubAccount?: string;
}): SePayMatchResult {
  const cleanAcc = params.requestedAccountNumber.replace(/[^A-Za-z0-9]/g, "").trim();
  if (cleanAcc.length < 6) {
    return { ok: false, errorCode: "INVALID_ACCOUNT_NUMBER" };
  }
  const cleanReqBank = params.requestedBankCode.trim();
  if (!cleanReqBank) {
    return { ok: false, errorCode: "BANK_CODE_REQUIRED" };
  }
  const requestedCap = resolveBankCapability(cleanReqBank);
  if (!requestedCap || !requestedCap.supportsWebhookCredit) {
    return { ok: false, errorCode: "UNSUPPORTED_PROVIDER_BANK" };
  }
  const cleanReqSub = (params.requestedSubAccount ?? "").trim();

  const accountMatches = params.sepayAccounts.filter((acc) => {
    const remoteAcc = String(acc.account_number ?? "").replace(/[^A-Za-z0-9]/g, "").trim();
    return remoteAcc.length >= 6 && remoteAcc === cleanAcc;
  });

  if (accountMatches.length === 0) {
    return { ok: false, errorCode: "SEPAY_ACCOUNT_NOT_FOUND" };
  }

  let sawAmbiguousBankHint = false;
  let sawSubMismatch = false;
  const matchedEntries: Array<{
    item: SePayBankAccountApiItem;
    capability: BankIntegrationCapability;
    subAccount: string;
  }> = [];

  for (const acc of accountMatches) {
    const { capability: remoteCap, ambiguous } = resolveSePayItemBankCapability(acc);
    if (ambiguous) {
      sawAmbiguousBankHint = true;
      continue;
    }
    if (!remoteCap || !remoteCap.supportsWebhookCredit) {
      continue;
    }
    if (remoteCap.bankCode !== requestedCap.bankCode) {
      continue;
    }
    const remoteSub = String(acc.sub_account ?? acc.va ?? "").trim();
    if (cleanReqSub.length > 0) {
      if (!remoteSub || remoteSub.toUpperCase() !== cleanReqSub.toUpperCase()) {
        sawSubMismatch = true;
        continue;
      }
    }
    matchedEntries.push({
      item: acc,
      capability: remoteCap,
      subAccount: remoteSub
    });
  }

  if (matchedEntries.length === 0) {
    if (sawAmbiguousBankHint) {
      return { ok: false, errorCode: "AMBIGUOUS_SEPAY_ACCOUNT" };
    }
    if (sawSubMismatch) {
      return { ok: false, errorCode: "SUBACCOUNT_MISMATCH" };
    }
    return { ok: false, errorCode: "BANK_MISMATCH_OR_UNVERIFIED" };
  }

  if (matchedEntries.length > 1) {
    return { ok: false, errorCode: "AMBIGUOUS_SEPAY_ACCOUNT" };
  }

  const chosen = matchedEntries[0];
  const rawId =
    chosen.item.id !== undefined && chosen.item.id !== null
      ? String(chosen.item.id).trim()
      : "";
  if (!rawId) {
    return { ok: false, errorCode: "INVALID_SEPAY_ACCOUNT_ID" };
  }
  if (!isSePayAccountActive(chosen.item)) {
    return { ok: false, errorCode: "INACTIVE_SEPAY_ACCOUNT" };
  }

  const parsedAcc = Number(chosen.item.accumulated);
  const observedAccumulatedMinor =
    Number.isSafeInteger(parsedAcc) && parsedAcc > 0 ? parsedAcc : null;

  return {
    ok: true,
    capability: chosen.capability,
    accountNumber: cleanAcc,
    subAccount: chosen.subAccount,
    providerAccountId: rawId,
    providerConnectionId: `sepay_ba_${rawId}`,
    observedAccumulatedMinor
  };
}

export interface CanonicalTransactionRecord {
  readonly id: string;
  readonly ownerId: string;
  readonly walletId: string;
  readonly walletName?: string;
  readonly connectionId?: string;
  readonly sourceProvider: "sepay" | "android_device" | "manual" | "csv";
  readonly sourceKind: "bankWebhook" | "bankApi" | "androidNotification" | "manual" | "csv";
  readonly externalTransactionId?: string;
  readonly referenceCode?: string;
  readonly kind: "income" | "expense";
  readonly direction: "credit" | "debit";
  readonly amountMinor: number;
  readonly currencyCode: "VND";
  readonly bankCode?: string;
  readonly accountMasked?: string;
  readonly accountTail?: string;
  readonly counterpartyDisplay?: string;
  readonly merchant: string;
  readonly description: string;
  readonly categoryName: string;
  readonly occurredAtMs: number;
  readonly receivedAtMs: number;
  readonly monthKey: string;
  readonly verification: "provisional" | "verified" | "userConfirmed" | "rejected" | "needsReview";
  readonly verificationStatus: VerificationStatus;
  readonly reconciliationStatus:
    | "unreconciled_provisional"
    | "canonical_verified"
    | "reconciled_cross_source"
    | "ambiguous_collision";
  readonly sourceEventKey: string;
  readonly crossSourceFingerprint: string;
  readonly softWindowFingerprint: string;
  readonly balanceAfterMinor: number | null;
  readonly balanceType: BalanceType;
  readonly balanceObservationSkippedStale?: boolean;
  readonly ledgerApplied: boolean;
  readonly isVehicleMaintenanceHint: boolean;
  readonly isRecurringCandidate: boolean;
  readonly createdAtMs: number;
  readonly updatedAtMs: number;
}

export interface WalletRecord {
  readonly id: string;
  readonly ownerId: string;
  readonly name: string;
  readonly balanceMinor: number;
  readonly isEstimatedBalance: boolean;
  readonly lastAuditId?: string;
  readonly lastObservedBalanceAtEpochMs?: number | null;
  readonly lastObservedBalanceEventId?: string | null;
  readonly bankCode?: string;
  readonly maskedAccount?: string;
  readonly archived?: boolean;
  readonly isArchived?: boolean;
  readonly archivedAtMs?: number | null;
  readonly updatedAtMs: number;
}

export interface UserDeviceRecord {
  readonly deviceId: string;
  readonly ownerId: string;
  readonly fcmToken: string;
  readonly platform: "android" | "ios" | "web";
  readonly pushEnabled: boolean;
  readonly updatedAtMs: number;
}

export interface UserNotificationPreferences {
  readonly notifyCredit: boolean;
  readonly notifyDebit: boolean;
  readonly minAmountMinor: number;
  readonly hideAmountOnLockscreen: boolean;
  readonly hideCounterpartyAndContent: boolean;
  readonly soundEnabled: boolean;
  readonly mutedConnectionIds: readonly string[];
  readonly notifyUnverified: boolean;
}

export const DEFAULT_NOTIFICATION_PREFS: UserNotificationPreferences = {
  notifyCredit: true,
  notifyDebit: true,
  minAmountMinor: 0,
  hideAmountOnLockscreen: true, // Default protects sensitive lockscreen info (Section 11)
  hideCounterpartyAndContent: false,
  soundEnabled: true,
  mutedConnectionIds: [],
  notifyUnverified: true
};

export interface FinancialNotificationRecord {
  readonly id: string;
  readonly ownerId: string;
  readonly transactionId: string;
  readonly walletId: string;
  readonly connectionId: string;
  readonly direction: "credit" | "debit";
  readonly amountMinor: number;
  readonly bankCode: string;
  readonly bankName: string;
  readonly accountMasked: string;
  readonly title: string;
  readonly body: string;
  readonly lockscreenRedactedBody: string;
  readonly content: string;
  readonly verificationStatus: VerificationStatus;
  readonly sourceKind: string;
  readonly isRead: boolean;
  readonly isTestNotification: boolean;
  readonly occurredAtMs: number;
  readonly createdAtMs: number;
}

export interface FcmMulticastResult {
  readonly successCount: number;
  readonly failureCount: number;
  readonly invalidTokens: readonly string[];
  readonly succeededTokens?: readonly string[];
  readonly failedTokens?: Readonly<Record<string, string>>;
  readonly retryableError?: string;
}

export interface FcmPushSender {
  sendToUserDevices(params: {
    tokens: readonly string[];
    notificationId: string;
    title: string;
    body: string;
    lockscreenPrivate: boolean;
    soundEnabled: boolean;
    data: Record<string, string>;
  }): Promise<FcmMulticastResult>;
}

/**
 * Transactional context executed atomically (maps 1:1 to Firestore Transaction).
 */
export interface BankingTxContext {
  isUserDeletionFrozen(ownerId: string): Promise<boolean>;
  getConnectionById(connectionId: string): Promise<ServerBankConnectionRecord | null>;
  getInboxEvent(providerEventKey: string): Promise<InboxEventRecord | null>;
  setInboxEvent(record: InboxEventRecord): Promise<void>;
  getSourceEvent(ownerId: string, eventKey: string): Promise<{ linkedTransactionId: string } | null>;
  setSourceEvent(
    ownerId: string,
    eventKey: string,
    data: { source: string; status: string; linkedTransactionId: string; receivedAtMs: number }
  ): Promise<void>;
  getServerSourceEvent(ownerId: string, eventKey: string): Promise<{ linkedTransactionId: string } | null>;
  setServerSourceEvent(
    ownerId: string,
    eventKey: string,
    data: {
      source: string;
      status: string;
      linkedTransactionId: string;
      receivedAtMs: number;
      connectionId?: string;
    }
  ): Promise<void>;
  findCandidateTransactions(
    ownerId: string,
    softWindowFingerprints: readonly string[]
  ): Promise<CanonicalTransactionRecord[]>;
  getWallet(ownerId: string, walletId: string): Promise<WalletRecord | null>;
  upsertWallet(ownerId: string, wallet: WalletRecord): Promise<void>;
  upsertTransaction(ownerId: string, tx: CanonicalTransactionRecord): Promise<void>;
  appendLedgerAudit(
    ownerId: string,
    auditId: string,
    data: Record<string, unknown>
  ): Promise<void>;
  upsertFinancialNotification(ownerId: string, notif: FinancialNotificationRecord): Promise<void>;
  upsertNotificationOutbox(outbox: NotificationOutboxRecord): Promise<void>;
  updateConnectionLastSync(ownerId: string, connectionId: string, syncedAtMs: number): Promise<void>;
  markConnectionWarning(ownerId: string, connectionId: string, warning: string, nowMs: number): Promise<void>;
  getBankAccountClaim(claimId: string): Promise<BankAccountClaimRecord | null>;
  upsertBankAccountClaim(claim: BankAccountClaimRecord): Promise<void>;
  saveVerifiedConnectionTx(record: ServerBankConnectionRecord): Promise<void>;
}

export interface BankingBackendStore {
  runAtomic<T>(fn: (ctx: BankingTxContext) => Promise<T>): Promise<T>;
  isUserDeletionFrozen(ownerId: string): Promise<boolean>;
  getConnectionById(connectionId: string): Promise<ServerBankConnectionRecord | null>;
  findActiveConnectionForAccount(params: {
    bankCode: string;
    gateway: string;
    accountNumber: string;
    subAccount: string;
  }): Promise<ServerBankConnectionRecord | null>;
  findAnyVerifiedConnectionByAccount(
    bankCode: string,
    accountNumber: string,
    subAccount?: string
  ): Promise<ServerBankConnectionRecord | null>;
  saveVerifiedConnection(record: ServerBankConnectionRecord): Promise<void>;
  disconnectConnection(ownerId: string, connectionId: string, nowMs: number): Promise<void>;
  getInboxEvent(providerEventKey: string): Promise<InboxEventRecord | null>;
  createDurableInboxIfAbsent(record: InboxEventRecord): Promise<{ created: boolean; existing?: InboxEventRecord }>;
  claimInboxEvent(
    providerEventKey: string,
    nowMs: number,
    leaseOwner: string,
    leaseTtlMs?: number
  ): Promise<{ claimed: boolean; record: InboxEventRecord | null }>;
  updateInboxRecord(record: InboxEventRecord): Promise<void>;
  listRecoverableInboxRecords(
    nowMs: number,
    limit?: number,
    pendingGraceMs?: number
  ): Promise<{ records: InboxEventRecord[]; oldestPendingAgeMs: number }>;
  purgeExpiredInboxRecords(
    nowMs: number,
    limit?: number
  ): Promise<{ purged: number; deletedCount: number }>;
  claimNotificationOutbox(
    outboxId: string,
    nowMs: number,
    leaseOwner: string,
    leaseTtlMs?: number
  ): Promise<{ claimed: boolean; record: NotificationOutboxRecord | null }>;
  claimOutboxForDelivery(notificationId: string, nowMs: number): Promise<{ claimed: boolean; record: NotificationOutboxRecord | null }>;
  commitNotificationOutboxWithCas(params: {
    outboxId: string;
    expectedVersion: number;
    expectedLeaseOwner: string;
    nextRecord: NotificationOutboxRecord;
  }): Promise<{ committed: boolean; record: NotificationOutboxRecord | null }>;
  listRecoverableOutboxIds(nowMs: number, limit?: number): Promise<string[]>;
  listDueRetryableOutboxRecords(nowMs: number, limit?: number): Promise<NotificationOutboxRecord[]>;
  getOutboxRecord(notificationId: string): Promise<NotificationOutboxRecord | null>;
  updateOutboxRecord(record: NotificationOutboxRecord): Promise<void>;
  commitReconciliationStateCas(params: {
    ownerId: string;
    connectionId: string;
    expectedGrantVersion: number;
    incomplete: boolean;
    newestValidExternalTxId: string | null;
    resumableCursor: BackfillCursorRecord | null;
    nowMs: number;
  }): Promise<{ committed: boolean; reason?: string; connection: ServerBankConnectionRecord | null }>;
  getUserNotificationPreferences(ownerId: string): Promise<UserNotificationPreferences>;
  listActiveUserDevices(ownerId: string): Promise<UserDeviceRecord[]>;
  deactivateInvalidTokens(ownerId: string, invalidTokens: readonly string[]): Promise<void>;
  readAndDeleteLegacySePayConsent(ownerId: string): Promise<{ apiToken?: string; bankCode?: string; accountNumber?: string; walletId?: string } | null>;
}

function normalizeBankCodeForMatch(raw?: string | null): string {
  const trimmed = (raw ?? "").trim();
  if (!trimmed) return "";
  return resolveBankCapability(trimmed)?.bankCode ?? trimmed.toUpperCase();
}

/**
 * M8: Strictly scopes Android notification candidates to the exact linked wallet,
 * bankCode (if present on candidate), and accountTail (if present on both).
 * Prevents cross-wallet or cross-account reconciliation corruption.
 */
export function findCandidateAndroidTransactions(params: {
  candidates: readonly CanonicalTransactionRecord[];
  connection: ServerBankConnectionRecord;
  incomingExternalTxId: string;
  incomingOccurredAtMs: number;
  incomingReferenceCode?: string;
  windowMs?: number;
}): CanonicalTransactionRecord[] {
  const windowMs = params.windowMs ?? 15 * 60 * 1000;
  const connBankCode = normalizeBankCodeForMatch(params.connection.bankCode);
  const connTail =
    extractAccountTail(params.connection.accountNumber) ??
    extractAccountTail(params.connection.accountMasked);
  const incomingRef = (params.incomingReferenceCode ?? "").trim().toUpperCase();

  return params.candidates.filter((c) => {
    if (c.verification === "rejected") return false;
    if (c.sourceKind !== "androidNotification") return false;
    if (Math.abs(c.occurredAtMs - params.incomingOccurredAtMs) > windowMs) return false;

    // M8: Strict wallet isolation — never merge across different wallets!
    if (c.walletId !== params.connection.linkedWalletId) return false;

    // M8: If candidate has bankCode, it must match connection's bankCode
    const candBankCode = normalizeBankCodeForMatch(c.bankCode);
    if (candBankCode && connBankCode && candBankCode !== connBankCode) {
      return false;
    }

    // M8: If both candidate and connection have account tail/suffix, they must match
    const candTail = extractAccountTail(c.accountTail) ?? extractAccountTail(c.accountMasked);
    if (candTail && connTail && candTail !== connTail) {
      return false;
    }

    if (c.externalTransactionId && c.externalTransactionId !== params.incomingExternalTxId) {
      return false;
    }

    const candRef = (c.referenceCode ?? "").trim().toUpperCase();
    if (candRef && incomingRef && candRef !== incomingRef) {
      return false;
    }

    return true;
  });
}

export function formatVietnamTimeHm(epochMs: number): string {
  const vnDate = new Date(epochMs + 7 * 3600 * 1000);
  const hh = vnDate.getUTCHours().toString().padStart(2, "0");
  const mm = vnDate.getUTCMinutes().toString().padStart(2, "0");
  return `${hh}:${mm}`;
}

export function formatMonthKeyVn(epochMs: number): string {
  const vnDate = new Date(epochMs + 7 * 3600 * 1000);
  const yyyy = vnDate.getUTCFullYear().toString().padStart(4, "0");
  const mm = (vnDate.getUTCMonth() + 1).toString().padStart(2, "0");
  return `${yyyy}-${mm}`;
}

/**
 * Formats user-facing push notification copy strictly per Section 11:
 * - Never claims unfounded percentages like "98% chính xác".
 * - Distinguishes verified provider events from unverified Android signals.
 * - Supports privacy redaction of amount & counterparty/content.
 */
export function buildBankingNotificationCopy(params: {
  direction: "credit" | "debit";
  amountMinor: number;
  bankName: string;
  accountMasked: string;
  content: string;
  occurredAtMs: number;
  verificationStatus: VerificationStatus;
  prefs: UserNotificationPreferences;
}): { title: string; fullBody: string; pushBody: string } {
  const { direction, amountMinor, bankName, accountMasked, content, occurredAtMs, verificationStatus, prefs } = params;
  const sign = direction === "credit" ? "+" : "-";
  const amountLabel = `${sign}${formatVndCompactNotification(amountMinor)}`;
  const timeHm = formatVietnamTimeHm(occurredAtMs);
  const cleanContent = content.trim() || (direction === "credit" ? "Nhận chuyển khoản" : "Thanh toán giao dịch");

  if (verificationStatus === "PROVISIONAL" || verificationStatus === "NEEDS_REVIEW") {
    const title = "🔔 Life OS — Phát hiện biến động ngân hàng";
    const statusLabel = verificationStatus === "NEEDS_REVIEW" ? "Cần kiểm tra đối soát" : "Chờ đối soát";
    const fullBody = `${amountLabel}\nNguồn: Thông báo Android\nTrạng thái: ${statusLabel}`;
    const pushBody = prefs.hideAmountOnLockscreen
      ? `Phát hiện biến động mới (${bankName}) · Chạm để kiểm tra trong Life OS`
      : fullBody;
    return { title, fullBody, pushBody };
  }

  const title =
    direction === "credit" ? "💰 Life OS — Tiền vừa về!" : "💸 Life OS — Giao dịch chi tiêu";
  const shownContent = prefs.hideCounterpartyAndContent ? "Nội dung đã ẩn theo cài đặt riêng tư" : cleanContent;
  const fullBody = `${amountLabel}\nNgân hàng: ${bankName} (${accountMasked})\nNội dung: ${shownContent}\n${timeHm} · Đã xác minh`;

  if (prefs.hideAmountOnLockscreen) {
    const redactedContent = prefs.hideCounterpartyAndContent
      ? `${bankName} ${accountMasked} · ${timeHm} · Đã xác minh`
      : `${bankName} ${accountMasked} · ${shownContent} · ${timeHm}`;
    return {
      title,
      fullBody,
      pushBody: ` Giao dịch mới đã xác minh · ${redactedContent}`.trim()
    };
  }

  return { title, fullBody, pushBody: fullBody };
}

export interface WebhookHttpInput {
  readonly method: string;
  readonly rawBody: Buffer;
  readonly headers: Record<string, string | undefined>;
  readonly nowMs?: number;
}

export interface WebhookHttpResponse {
  readonly statusCode: number;
  readonly body: Record<string, unknown>;
  readonly providerEventKey?: string;
}

export const OUTBOX_DEFAULT_LEASE_TTL_MS = 60_000;
export const OUTBOX_STALE_PENDING_GRACE_MS = 30_000;
export const OUTBOX_MAX_ATTEMPTS = 5;
export const INBOX_DEFAULT_LEASE_TTL_MS = 60_000;
export const INBOX_STALE_PENDING_GRACE_MS = 30_000;
export const INBOX_MAX_ATTEMPTS = 6;

export interface ReconcilePagesResult {
  readonly pagesFetched: number;
  readonly fetchedCount: number;
  readonly processedCount: number;
  readonly duplicateCount: number;
  readonly invalidCount: number;
  readonly skippedCount: number;
  readonly reachedPreviousWatermark: boolean;
  readonly incomplete: boolean;
  readonly watermarkAdvanced: boolean;
  readonly watermarkAbortedReason?: string;
  readonly newestValidExternalTxId: string | null;
  readonly newestExternalTxId?: string;
  readonly resumableCursor: BackfillCursorRecord | null;
}

/**
 * Core Real-Time Banking Backend Coordinator:
 * 1. Authenticates & validates SePay Webhooks (`POST /webhooks/sepay`)
 * 2. Persists Durable Inbox BEFORE acknowledging HTTP 200 `{"success": true}`
 * 3. Runs idempotent, single-balance-effect Canonical Ledger Worker
 * 4. Dispatches privacy-aware FCM notifications via Outbox without rolling back transactions on push failure
 */
export class RealtimeBankingCoordinator {
  constructor(
    private readonly store: BankingBackendStore,
    private readonly fcmSender: FcmPushSender,
    private readonly getWebhookSecret: () => string | undefined
  ) {}

  /**
   * Stage 1: Fast, durable HTTP Webhook Receiver (`POST /webhooks/sepay`).
   */
  async handleSePayWebhookHttp(req: WebhookHttpInput): Promise<WebhookHttpResponse> {
    const nowMs = req.nowMs ?? Date.now();

    if (req.method.toUpperCase() !== "POST") {
      return { statusCode: 405, body: { success: false, error: "METHOD_NOT_ALLOWED" } };
    }

    if (req.rawBody.byteLength === 0 || req.rawBody.byteLength > MAX_WEBHOOK_BODY_BYTES) {
      return { statusCode: 413, body: { success: false, error: "PAYLOAD_TOO_LARGE_OR_EMPTY" } };
    }

    const sigHeader = req.headers["x-sepay-signature"] ?? req.headers["X-SePay-Signature"];
    const tsHeader = req.headers["x-sepay-timestamp"] ?? req.headers["X-SePay-Timestamp"];

    const sigCheck = verifySePayWebhookSignature({
      rawBody: req.rawBody,
      signatureHeader: sigHeader,
      timestampHeader: tsHeader,
      secret: this.getWebhookSecret(),
      nowEpochSeconds: Math.floor(nowMs / 1000)
    });

    if (!sigCheck.ok) {
      return {
        statusCode: sigCheck.statusCode,
        body: { success: false, error: sigCheck.errorCode ?? "UNAUTHORIZED" }
      };
    }

    const parsed = parseAndValidateSePayPayload(req.rawBody);
    if (!parsed.valid || !parsed.payload) {
      return {
        statusCode: 400,
        body: { success: false, error: parsed.errorCode ?? "INVALID_PAYLOAD", message: parsed.message }
      };
    }

    const p = parsed.payload;
    const cap = resolveBankCapability(p.gateway);
    const bankCode = cap?.bankCode ?? p.gateway.toUpperCase().replace(/[^A-Z0-9]/g, "").slice(0, 12);

    // Resolve server-verified connection BEFORE acknowledging or scope key to account hash
    const matchedConnection = await this.store.findActiveConnectionForAccount({
      bankCode,
      gateway: p.gateway,
      accountNumber: p.accountNumber,
      subAccount: p.subAccount
    });

    const scopePart = matchedConnection
      ? matchedConnection.id
      : `unlinked_${bankCode}_${sha256Hex(p.accountNumber).slice(0, 10)}`;
    const providerEventKey = `sepay_${scopePart}_${p.id}`;

    const deletionFrozen = matchedConnection
      ? await this.store.isUserDeletionFrozen(matchedConnection.ownerId)
      : false;

    let initialState: InboxProcessingState;
    let initialStatus: string;
    let errorReason: string | undefined;
    let expiresAtMs: number | null = null;
    let stripText = false;

    if (!matchedConnection) {
      initialState = "FAILED_PERMANENT";
      initialStatus = "ignored_unlinked_or_revoked";
      errorReason = "UNLINKED_OR_INACTIVE_BANK_ACCOUNT";
      expiresAtMs = nowMs + INBOX_TERMINAL_TTL_MS;
      stripText = true;
    } else if (deletionFrozen) {
      initialState = "skipped_account_deleting";
      initialStatus = "skipped_account_deleting";
      errorReason = "ACCOUNT_DELETION_FROZEN";
      expiresAtMs = nowMs + INBOX_TERMINAL_TTL_MS;
      stripText = true;
    } else {
      initialState = "PENDING_PROCESSING";
      initialStatus = "pending_processing";
      stripText = false;
    }

    const inboxRecord: InboxEventRecord = {
      providerEventKey,
      provider: "sepay",
      externalTransactionId: String(p.id),
      connectionId: matchedConnection?.id ?? null,
      ownerId: matchedConnection?.ownerId ?? null,
      walletId: matchedConnection?.linkedWalletId ?? null,
      grantVersion: matchedConnection ? (matchedConnection.grantVersion ?? 1) : null,
      state: initialState,
      status: initialStatus,
      payload: minimizeInboxPayload(p, { stripText }),
      errorReason,
      reason: errorReason,
      attemptCount: 0,
      leaseOwner: null,
      leaseExpiresAtMs: null,
      nextRetryAtMs: null,
      expiresAtMs,
      deadLetterReason: null,
      receivedAtMs: nowMs,
      updatedAtMs: nowMs
    };

    try {
      await this.store.createDurableInboxIfAbsent(inboxRecord);
    } catch {
      // Never return HTTP 200 if durable persistence failed (Section 6 & 15)!
      return {
        statusCode: 503,
        body: { success: false, error: "DURABLE_INBOX_UNAVAILABLE" }
      };
    }

    return {
      statusCode: 200,
      body: { success: true },
      providerEventKey
    };
  }

  /**
   * Stage 2: Asynchronous Worker — Processes a durable inbox record into a single Canonical Transaction
   * and enqueues Notification Outbox atomically.
   * H3: Strictly loads exact connection by `inbox.connectionId` inside the transaction and validates
   * `ownerId`, active consent, `grantVersion`, and `walletId` — never re-queries by bank account!
   */
  async processInboxEvent(
    providerEventKey: string,
    nowMs: number = Date.now(),
    options?: { readonly expectedLeaseOwner?: string }
  ): Promise<{
    state: InboxProcessingState;
    transactionId?: string;
    notificationId?: string;
    reason?: string;
  }> {
    const outerInbox = await this.store.getInboxEvent(providerEventKey);
    if (!outerInbox) {
      return { state: "FAILED_PERMANENT" };
    }
    if (outerInbox.state === "PROCESSED" || outerInbox.state === "DUPLICATE") {
      return { state: "DUPLICATE", transactionId: outerInbox.linkedTransactionId };
    }
    if (outerInbox.state === "DEAD_LETTER") {
      return {
        state: "DEAD_LETTER",
        reason: outerInbox.deadLetterReason ?? outerInbox.errorReason
      };
    }
    if (outerInbox.state === "skipped_account_deleting") {
      return {
        state: "skipped_account_deleting",
        reason: outerInbox.reason ?? outerInbox.errorReason
      };
    }
    if (outerInbox.state === "skipped_archived_wallet") {
      return {
        state: "skipped_archived_wallet",
        reason: outerInbox.reason ?? outerInbox.errorReason
      };
    }
    if (outerInbox.state === "skipped_revoked_or_reassigned") {
      return {
        state: "skipped_revoked_or_reassigned",
        reason: outerInbox.reason ?? outerInbox.errorReason
      };
    }
    if (outerInbox.state === "FAILED_PERMANENT" || !outerInbox.connectionId || !outerInbox.ownerId) {
      return { state: "FAILED_PERMANENT", reason: outerInbox.errorReason };
    }

    const prefs = await this.store.getUserNotificationPreferences(outerInbox.ownerId);

    return this.store.runAtomic(async (ctx) => {
      // 1. All transactional reads MUST occur before any writes (Cloud Firestore constraint)
      const inbox = await ctx.getInboxEvent(providerEventKey);
      if (!inbox) {
        return { state: "FAILED_PERMANENT" as const };
      }
      if (inbox.state === "PROCESSED" || inbox.state === "DUPLICATE") {
        return {
          state: "DUPLICATE" as const,
          transactionId: inbox.linkedTransactionId
        };
      }
      if (inbox.state === "DEAD_LETTER") {
        return {
          state: "DEAD_LETTER" as const,
          reason: inbox.deadLetterReason ?? inbox.errorReason
        };
      }
      if (inbox.state === "skipped_account_deleting") {
        return {
          state: "skipped_account_deleting" as const,
          reason: inbox.reason ?? inbox.errorReason
        };
      }
      if (inbox.state === "skipped_archived_wallet") {
        return {
          state: "skipped_archived_wallet" as const,
          reason: inbox.reason ?? inbox.errorReason
        };
      }
      if (inbox.state === "skipped_revoked_or_reassigned") {
        return {
          state: "skipped_revoked_or_reassigned" as const,
          reason: inbox.reason ?? inbox.errorReason
        };
      }
      if (inbox.state === "FAILED_PERMANENT" || !inbox.connectionId || !inbox.ownerId) {
        return { state: "FAILED_PERMANENT" as const, reason: inbox.errorReason };
      }

      if (
        options?.expectedLeaseOwner &&
        inbox.leaseOwner &&
        inbox.leaseOwner !== options.expectedLeaseOwner &&
        (inbox.leaseExpiresAtMs ?? 0) > nowMs
      ) {
        return {
          state: inbox.state,
          reason: "INBOX_LEASE_HELD_BY_OTHER_WORKER"
        };
      }

      // DEL-04 / BANK-02: Never ingest new transactions/notifications when user deletion tombstone exists!
      const deletionFrozen = await ctx.isUserDeletionFrozen(inbox.ownerId);
      // H3: Load exact connection by `inbox.connectionId` — NEVER re-query by bank account!
      const connection = await ctx.getConnectionById(inbox.connectionId);

      if (deletionFrozen) {
        await ctx.setInboxEvent({
          ...inbox,
          state: "skipped_account_deleting",
          status: "skipped_account_deleting",
          errorReason: "ACCOUNT_DELETION_FROZEN",
          reason: "ACCOUNT_DELETION_FROZEN",
          payload: minimizeInboxPayload(inbox.payload, { stripText: true }),
          leaseOwner: null,
          leaseExpiresAtMs: null,
          nextRetryAtMs: null,
          expiresAtMs: nowMs + INBOX_TERMINAL_TTL_MS,
          updatedAtMs: nowMs
        });
        return {
          state: "skipped_account_deleting" as const,
          reason: "ACCOUNT_DELETION_FROZEN"
        };
      }

      const expectedGrantVersion = inbox.grantVersion ?? 1;
      let skipReason: string | null = null;
      if (!connection) {
        skipReason = "CONNECTION_NOT_FOUND";
      } else if (connection.ownerId !== inbox.ownerId) {
        skipReason = "CONNECTION_OWNER_MISMATCH";
      } else if (!isConnectionActiveAndGranted(connection)) {
        skipReason = "CONNECTION_REVOKED_OR_INACTIVE";
      } else if ((connection.grantVersion ?? 1) !== expectedGrantVersion) {
        skipReason = "CONNECTION_GRANT_VERSION_MISMATCH";
      } else if (inbox.walletId && connection.linkedWalletId !== inbox.walletId) {
        skipReason = "CONNECTION_WALLET_MISMATCH";
      }

      if (skipReason !== null || !connection) {
        const finalReason = skipReason ?? "CONNECTION_REVOKED_OR_INACTIVE";
        await ctx.setInboxEvent({
          ...inbox,
          state: "skipped_revoked_or_reassigned",
          status: "skipped_revoked_or_reassigned",
          errorReason: finalReason,
          reason: finalReason,
          payload: minimizeInboxPayload(inbox.payload, { stripText: true }),
          leaseOwner: null,
          leaseExpiresAtMs: null,
          nextRetryAtMs: null,
          expiresAtMs: nowMs + INBOX_TERMINAL_TTL_MS,
          updatedAtMs: nowMs
        });
        return {
          state: "skipped_revoked_or_reassigned" as const,
          reason: finalReason
        };
      }

      const p = inbox.payload;
      const cap = resolveBankCapability(p.gateway);

      // Section 5 & T22: Enforce real SePay bank capability rules (e.g. debit only on STB/TPB/CTG with TKP)
      const dirSupport = checkWebhookDirectionSupport(cap, p.transferType, p.subAccount);
      if (!dirSupport.supported) {
        await ctx.setInboxEvent({
          ...inbox,
          ownerId: connection.ownerId,
          connectionId: connection.id,
          walletId: connection.linkedWalletId,
          grantVersion: connection.grantVersion ?? 1,
          state: "FAILED_PERMANENT",
          status: "failed_permanent",
          errorReason: dirSupport.reason ?? "UNSUPPORTED_BANK_DIRECTION",
          reason: dirSupport.reason ?? "UNSUPPORTED_BANK_DIRECTION",
          payload: minimizeInboxPayload(inbox.payload, { stripText: true }),
          leaseOwner: null,
          leaseExpiresAtMs: null,
          nextRetryAtMs: null,
          expiresAtMs: nowMs + INBOX_TERMINAL_TTL_MS,
          updatedAtMs: nowMs
        });
        return {
          state: "FAILED_PERMANENT" as const,
          reason: dirSupport.reason ?? "UNSUPPORTED_BANK_DIRECTION"
        };
      }

      const ownerId = connection.ownerId;
      const walletId = connection.linkedWalletId;

      // SEC-03: Check server-owned `server_source_events` FIRST so deleting/tampering with
      // client `users/{uid}/source_events` can NEVER cause duplicate transaction posting or hijack dedup!
      const existingServerSourceEv = await ctx.getServerSourceEvent(ownerId, providerEventKey);
      // Read client source_events for transactional read-before-write compliance
      await ctx.getSourceEvent(ownerId, providerEventKey);

      if (existingServerSourceEv) {
        await ctx.setInboxEvent({
          ...inbox,
          ownerId,
          connectionId: connection.id,
          walletId,
          grantVersion: connection.grantVersion ?? 1,
          state: "DUPLICATE",
          status: "duplicate",
          linkedTransactionId: existingServerSourceEv.linkedTransactionId,
          payload: minimizeInboxPayload(inbox.payload, { stripText: true }),
          leaseOwner: null,
          leaseExpiresAtMs: null,
          nextRetryAtMs: null,
          expiresAtMs: nowMs + INBOX_TERMINAL_TTL_MS,
          updatedAtMs: nowMs
        });
        return {
          state: "DUPLICATE" as const,
          transactionId: existingServerSourceEv.linkedTransactionId
        };
      }

      const softFp = computeSoftWindowFingerprint({
        ownerId,
        direction: p.direction,
        amountMinor: p.transferAmount,
        occurredAtMs: p.occurredAtMs
      });
      const candidateWindowFps = computeOverlappingSoftWindowFingerprints({
        ownerId,
        direction: p.direction,
        amountMinor: p.transferAmount,
        occurredAtMs: p.occurredAtMs
      });

      const rawCandidates = await ctx.findCandidateTransactions(ownerId, candidateWindowFps);
      const existingWallet = await ctx.getWallet(ownerId, walletId);

      const windowMs = 15 * 60 * 1000;
      const windowCandidates = rawCandidates.filter((c) => {
        if (c.verification === "rejected") return false;
        if (Math.abs(c.occurredAtMs - p.occurredAtMs) > windowMs) return false;
        return true;
      });

      // Exact provider external ID duplicate check scoped to same wallet/connection (T21 + M8)
      const exactSameExternal = windowCandidates.find(
        (c) =>
          c.walletId === walletId &&
          c.externalTransactionId &&
          c.externalTransactionId === String(p.id)
      );
      if (exactSameExternal) {
        await ctx.setServerSourceEvent(ownerId, providerEventKey, {
          source: "sepay_webhook",
          status: "duplicate_already_synced",
          linkedTransactionId: exactSameExternal.id,
          receivedAtMs: nowMs,
          connectionId: connection.id
        });
        await ctx.setSourceEvent(ownerId, providerEventKey, {
          source: "sepay_webhook",
          status: "duplicate_already_synced",
          linkedTransactionId: exactSameExternal.id,
          receivedAtMs: nowMs
        });
        await ctx.setInboxEvent({
          ...inbox,
          ownerId,
          connectionId: connection.id,
          walletId,
          grantVersion: connection.grantVersion ?? 1,
          state: "DUPLICATE",
          status: "duplicate",
          linkedTransactionId: exactSameExternal.id,
          payload: minimizeInboxPayload(inbox.payload, { stripText: true }),
          leaseOwner: null,
          leaseExpiresAtMs: null,
          nextRetryAtMs: null,
          expiresAtMs: nowMs + INBOX_TERMINAL_TTL_MS,
          updatedAtMs: nowMs
        });
        return { state: "DUPLICATE" as const, transactionId: exactSameExternal.id };
      }

      // SEC-02: If linked wallet already exists and is archived (`archived === true` / `isArchived === true`),
      // NEVER resurrect or mutate it — route event to NEEDS_REVIEW and mark connection warning!
      const isWalletArchived =
        existingWallet !== null &&
        (existingWallet.archived === true || existingWallet.isArchived === true);

      if (isWalletArchived && existingWallet) {
        const canonicalTxId = `ver_${sha256Hex(providerEventKey).slice(0, 20)}`;
        const combinedText = `${p.content} ${p.description}`.trim();
        const classified = classifyVietnameseTransaction(combinedText, p.direction);

        await ctx.markConnectionWarning(ownerId, connection.id, "LINKED_WALLET_ARCHIVED", nowMs);

        const archivedReviewTx: CanonicalTransactionRecord = {
          id: canonicalTxId,
          ownerId,
          walletId,
          walletName: existingWallet.name,
          connectionId: connection.id,
          sourceProvider: "sepay",
          sourceKind: "bankWebhook",
          externalTransactionId: String(p.id),
          referenceCode: p.referenceCode || undefined,
          kind: p.direction === "credit" ? "income" : "expense",
          direction: p.direction,
          amountMinor: p.transferAmount,
          currencyCode: "VND",
          bankCode: connection.bankCode,
          accountMasked: connection.accountMasked,
          accountTail: extractAccountTail(connection.accountNumber) ?? undefined,
          counterpartyDisplay: p.content || p.description || connection.bankName,
          merchant: p.content || p.description || `${connection.bankName} giao dịch`,
          description: combinedText,
          categoryName: classified.categoryName,
          occurredAtMs: p.occurredAtMs,
          receivedAtMs: nowMs,
          monthKey: formatMonthKeyVn(p.occurredAtMs),
          verification: "needsReview",
          verificationStatus: "NEEDS_REVIEW",
          reconciliationStatus: "ambiguous_collision",
          sourceEventKey: providerEventKey,
          crossSourceFingerprint: computeCrossSourceFingerprint({
            ownerId,
            direction: p.direction,
            amountMinor: p.transferAmount,
            occurredAtMs: p.occurredAtMs,
            referenceCode: p.referenceCode
          }),
          softWindowFingerprint: softFp,
          balanceAfterMinor: null,
          balanceType: "unknownBalance",
          ledgerApplied: false,
          isVehicleMaintenanceHint: classified.isVehicleMaintenanceHint,
          isRecurringCandidate: classified.isRecurringCandidate,
          createdAtMs: nowMs,
          updatedAtMs: nowMs
        };

        await ctx.upsertTransaction(ownerId, archivedReviewTx);
        await ctx.setServerSourceEvent(ownerId, providerEventKey, {
          source: "sepay_webhook",
          status: "needs_review_archived_wallet",
          linkedTransactionId: canonicalTxId,
          receivedAtMs: nowMs,
          connectionId: connection.id
        });
        await ctx.setSourceEvent(ownerId, providerEventKey, {
          source: "sepay_webhook",
          status: "needs_review_archived_wallet",
          linkedTransactionId: canonicalTxId,
          receivedAtMs: nowMs
        });

        const notifId = `notif_${sha256Hex(providerEventKey).slice(0, 24)}`;
        const copy = buildBankingNotificationCopy({
          direction: p.direction,
          amountMinor: p.transferAmount,
          bankName: connection.bankName,
          accountMasked: connection.accountMasked,
          content: p.content || p.description,
          occurredAtMs: p.occurredAtMs,
          verificationStatus: "NEEDS_REVIEW",
          prefs
        });

        await ctx.upsertFinancialNotification(ownerId, {
          id: notifId,
          ownerId,
          transactionId: canonicalTxId,
          walletId,
          connectionId: connection.id,
          direction: p.direction,
          amountMinor: p.transferAmount,
          bankCode: connection.bankCode,
          bankName: connection.bankName,
          accountMasked: connection.accountMasked,
          title: copy.title,
          body: copy.fullBody,
          lockscreenRedactedBody: copy.pushBody,
          content: p.content || p.description,
          verificationStatus: "NEEDS_REVIEW",
          sourceKind: "sepay_webhook",
          isRead: false,
          isTestNotification: false,
          occurredAtMs: p.occurredAtMs,
          createdAtMs: nowMs
        });

        await ctx.upsertNotificationOutbox({
          id: notifId,
          ownerId,
          transactionId: canonicalTxId,
          walletId,
          connectionId: connection.id,
          grantVersion: connection.grantVersion ?? 1,
          direction: p.direction,
          amountMinor: p.transferAmount,
          bankCode: connection.bankCode,
          bankName: connection.bankName,
          accountMasked: connection.accountMasked,
          content: p.content || p.description,
          occurredAtMs: p.occurredAtMs,
          verificationStatus: "NEEDS_REVIEW",
          state: "PENDING_DELIVERY",
          attemptCount: 0,
          version: 1,
          leaseOwner: null,
          leaseExpiresAtMs: null,
          deliveredTokens: [],
          failedTokens: {},
          deadLetteredAtMs: null,
          createdAtMs: nowMs,
          updatedAtMs: nowMs
        });

        await ctx.setInboxEvent({
          ...inbox,
          ownerId,
          connectionId: connection.id,
          walletId,
          grantVersion: connection.grantVersion ?? 1,
          state: "NEEDS_REVIEW",
          status: "needs_review",
          errorReason: "LINKED_WALLET_ARCHIVED",
          reason: "LINKED_WALLET_ARCHIVED",
          linkedTransactionId: canonicalTxId,
          payload: minimizeInboxPayload(inbox.payload, { stripText: true }),
          leaseOwner: null,
          leaseExpiresAtMs: null,
          nextRetryAtMs: null,
          expiresAtMs: nowMs + INBOX_TERMINAL_TTL_MS,
          updatedAtMs: nowMs
        });

        return {
          state: "NEEDS_REVIEW" as const,
          transactionId: canonicalTxId,
          notificationId: notifId,
          reason: "LINKED_WALLET_ARCHIVED"
        };
      }

      // M8: Strictly scope cross-source Android candidates to same wallet, bankCode & accountTail
      const reconcilableAndroidCandidates = findCandidateAndroidTransactions({
        candidates: windowCandidates,
        connection,
        incomingExternalTxId: String(p.id),
        incomingOccurredAtMs: p.occurredAtMs,
        incomingReferenceCode: p.referenceCode,
        windowMs
      });

      const isAmbiguousCollision = reconcilableAndroidCandidates.length > 1;
      const matchedAndroidTx = reconcilableAndroidCandidates.length === 1 ? reconcilableAndroidCandidates[0] : null;

      const wallet =
        existingWallet ?? {
          id: walletId,
          ownerId,
          name: `${connection.bankName} ${connection.accountMasked}`,
          balanceMinor: 0,
          isEstimatedBalance: true,
          lastObservedBalanceAtEpochMs: null,
          lastObservedBalanceEventId: null,
          bankCode: connection.bankCode,
          maskedAccount: connection.accountMasked,
          updatedAtMs: nowMs
        };

      const delta = p.direction === "credit" ? p.transferAmount : -p.transferAmount;
      const alreadyAppliedInLedger = matchedAndroidTx?.ledgerApplied === true;

      // M9: Monotonic observed balance guard & historical separation
      const existingLastObservedAt = wallet.lastObservedBalanceAtEpochMs ?? null;
      const isOlderThanLastObserved =
        existingLastObservedAt !== null && p.occurredAtMs < existingLastObservedAt;
      const balanceDecision = evaluateMonotonicObservedBalance({
        observedBalanceMinor: p.accumulatedMinor,
        eventOccurredAtEpochMs: p.occurredAtMs,
        existingLastObservedAtEpochMs: existingLastObservedAt
      });
      const balanceObservationSkippedStale =
        !isAmbiguousCollision &&
        (balanceDecision.balanceObservationSkippedStale || isOlderThanLastObserved);

      // CRITICAL P0 INVARIANT (T05, T15, T24, M9):
      // - If matchedAndroidTx already applied its delta (`ledgerApplied === true`), DO NOT apply `delta` a second time!
      // - If `accumulatedMinor !== null && accumulatedMinor > 0`, ONLY update wallet balance if monotonic guard permits!
      // - If event is older than `lastObservedBalanceAtEpochMs`, record transaction idempotently with `balanceObservationSkippedStale: true` without touching `wallet.balanceMinor`!
      // - If `isAmbiguousCollision`, mark NEEDS_REVIEW and do NOT mutate wallet balance until user resolves!
      let nextWalletBal = wallet.balanceMinor;
      let nextIsEstimated = wallet.isEstimatedBalance;
      let nextLastObservedAt = wallet.lastObservedBalanceAtEpochMs ?? null;
      let nextLastObservedEventId = wallet.lastObservedBalanceEventId ?? null;
      let txLedgerApplied = alreadyAppliedInLedger;
      let txBalanceAfter: number | null = null;
      let txBalanceType: BalanceType = p.balanceType;

      if (!isAmbiguousCollision) {
        if (balanceDecision.shouldUpdateObservedBalance && p.accumulatedMinor !== null) {
          nextWalletBal = p.accumulatedMinor;
          nextIsEstimated = false;
          nextLastObservedAt = p.occurredAtMs;
          nextLastObservedEventId = providerEventKey;
          txLedgerApplied = true;
          txBalanceAfter = nextWalletBal;
          txBalanceType = "observedBankBalance";
        } else if (balanceObservationSkippedStale) {
          // Stale out-of-order webhook or historical backfill item older than newest observed balance:
          // Preserve wallet.balanceMinor untouched and record transaction idempotently.
          txLedgerApplied = true;
          txBalanceAfter =
            p.accumulatedMinor !== null && p.accumulatedMinor > 0 ? p.accumulatedMinor : null;
          txBalanceType =
            p.accumulatedMinor !== null && p.accumulatedMinor > 0
              ? "observedBankBalance"
              : "unknownBalance";
        } else if (!alreadyAppliedInLedger) {
          nextWalletBal = wallet.balanceMinor + delta;
          txLedgerApplied = true;
          txBalanceAfter = nextWalletBal;
          txBalanceType = "estimatedWalletBalance";
        } else {
          // Balance delta was ALREADY applied when user/auto confirmed Android signal -> preserve single balance effect!
          txBalanceAfter = wallet.balanceMinor;
          txBalanceType = wallet.isEstimatedBalance ? "estimatedWalletBalance" : "observedBankBalance";
        }

        const shouldUpsertWallet =
          nextWalletBal !== wallet.balanceMinor ||
          nextIsEstimated !== wallet.isEstimatedBalance ||
          nextLastObservedAt !== (wallet.lastObservedBalanceAtEpochMs ?? null) ||
          nextLastObservedEventId !== (wallet.lastObservedBalanceEventId ?? null);

        if (shouldUpsertWallet) {
          const auditId = `aud_${providerEventKey}`;
          const exactDeltaMinor = nextWalletBal - wallet.balanceMinor;
          const balanceChanged = exactDeltaMinor !== 0;
          await ctx.upsertWallet(ownerId, {
            ...wallet,
            balanceMinor: nextWalletBal,
            isEstimatedBalance: nextIsEstimated,
            ...(balanceChanged ? { lastAuditId: auditId } : {}),
            lastObservedBalanceAtEpochMs: nextLastObservedAt,
            lastObservedBalanceEventId: nextLastObservedEventId,
            bankCode: connection.bankCode,
            maskedAccount: connection.accountMasked,
            updatedAtMs: nowMs
          });
          if (balanceChanged || nextIsEstimated !== wallet.isEstimatedBalance) {
            await ctx.appendLedgerAudit(ownerId, auditId, {
              id: auditId,
              ownerId,
              txId: matchedAndroidTx?.id ?? `ver_${sha256Hex(providerEventKey).slice(0, 20)}`,
              walletId,
              walletName: wallet.name,
              previousBalanceMinor: wallet.balanceMinor,
              deltaMinor: exactDeltaMinor,
              newBalanceMinor: nextWalletBal,
              balanceType: txBalanceType,
              kind: p.direction === "credit" ? "income" : "expense",
              createdAtMs: nowMs
            });
          }
        }
      }

      const combinedText = `${p.content} ${p.description}`.trim();
      const classified = classifyVietnameseTransaction(combinedText, p.direction);
      const canonicalTxId =
        matchedAndroidTx?.id ?? `ver_${sha256Hex(providerEventKey).slice(0, 20)}`;

      const verification: CanonicalTransactionRecord["verification"] = isAmbiguousCollision
        ? "needsReview"
        : "verified";
      const verificationStatus: VerificationStatus = isAmbiguousCollision
        ? "NEEDS_REVIEW"
        : "VERIFIED";

      const canonicalTx: CanonicalTransactionRecord = {
        id: canonicalTxId,
        ownerId,
        walletId,
        walletName: wallet.name,
        connectionId: connection.id,
        sourceProvider: "sepay",
        sourceKind: "bankWebhook",
        externalTransactionId: String(p.id),
        referenceCode: p.referenceCode || undefined,
        kind: p.direction === "credit" ? "income" : "expense",
        direction: p.direction,
        amountMinor: p.transferAmount,
        currencyCode: "VND",
        bankCode: connection.bankCode,
        accountMasked: connection.accountMasked,
        accountTail: extractAccountTail(connection.accountNumber) ?? undefined,
        counterpartyDisplay: p.content || p.description || connection.bankName,
        merchant: matchedAndroidTx?.merchant || p.content || p.description || `${connection.bankName} giao dịch`,
        description: combinedText,
        categoryName: matchedAndroidTx?.categoryName || classified.categoryName,
        occurredAtMs: p.occurredAtMs,
        receivedAtMs: nowMs,
        monthKey: formatMonthKeyVn(p.occurredAtMs),
        verification,
        verificationStatus,
        reconciliationStatus: isAmbiguousCollision
          ? "ambiguous_collision"
          : matchedAndroidTx
            ? "reconciled_cross_source"
            : "canonical_verified",
        sourceEventKey: providerEventKey,
        crossSourceFingerprint: computeCrossSourceFingerprint({
          ownerId,
          direction: p.direction,
          amountMinor: p.transferAmount,
          occurredAtMs: p.occurredAtMs,
          referenceCode: p.referenceCode
        }),
        softWindowFingerprint: softFp,
        balanceAfterMinor: txBalanceAfter,
        balanceType: txBalanceType,
        ...(balanceObservationSkippedStale ? { balanceObservationSkippedStale: true } : {}),
        ledgerApplied: txLedgerApplied,
        isVehicleMaintenanceHint:
          matchedAndroidTx?.isVehicleMaintenanceHint || classified.isVehicleMaintenanceHint,
        isRecurringCandidate: classified.isRecurringCandidate,
        createdAtMs: matchedAndroidTx?.createdAtMs ?? nowMs,
        updatedAtMs: nowMs
      };

      await ctx.upsertTransaction(ownerId, canonicalTx);
      await ctx.setServerSourceEvent(ownerId, providerEventKey, {
        source: "sepay_webhook",
        status: isAmbiguousCollision ? "needs_review" : "verified_processed",
        linkedTransactionId: canonicalTxId,
        receivedAtMs: nowMs,
        connectionId: connection.id
      });
      await ctx.setSourceEvent(ownerId, providerEventKey, {
        source: "sepay_webhook",
        status: isAmbiguousCollision ? "needs_review" : "verified_processed",
        linkedTransactionId: canonicalTxId,
        receivedAtMs: nowMs
      });

      const notifId = `notif_${sha256Hex(providerEventKey).slice(0, 24)}`;
      const copy = buildBankingNotificationCopy({
        direction: p.direction,
        amountMinor: p.transferAmount,
        bankName: connection.bankName,
        accountMasked: connection.accountMasked,
        content: p.content || p.description,
        occurredAtMs: p.occurredAtMs,
        verificationStatus,
        prefs
      });

      await ctx.upsertFinancialNotification(ownerId, {
        id: notifId,
        ownerId,
        transactionId: canonicalTxId,
        walletId,
        connectionId: connection.id,
        direction: p.direction,
        amountMinor: p.transferAmount,
        bankCode: connection.bankCode,
        bankName: connection.bankName,
        accountMasked: connection.accountMasked,
        title: copy.title,
        body: copy.fullBody,
        lockscreenRedactedBody: copy.pushBody,
        content: p.content || p.description,
        verificationStatus,
        sourceKind: "sepay_webhook",
        isRead: false,
        isTestNotification: false,
        occurredAtMs: p.occurredAtMs,
        createdAtMs: nowMs
      });

      await ctx.upsertNotificationOutbox({
        id: notifId,
        ownerId,
        transactionId: canonicalTxId,
        walletId,
        connectionId: connection.id,
        grantVersion: connection.grantVersion ?? 1,
        direction: p.direction,
        amountMinor: p.transferAmount,
        bankCode: connection.bankCode,
        bankName: connection.bankName,
        accountMasked: connection.accountMasked,
        content: p.content || p.description,
        occurredAtMs: p.occurredAtMs,
        verificationStatus,
        state: "PENDING_DELIVERY",
        attemptCount: 0,
        version: 1,
        leaseOwner: null,
        leaseExpiresAtMs: null,
        deliveredTokens: [],
        failedTokens: {},
        deadLetteredAtMs: null,
        createdAtMs: nowMs,
        updatedAtMs: nowMs
      });

      await ctx.updateConnectionLastSync(ownerId, connection.id, nowMs);

      const finalState: InboxProcessingState = isAmbiguousCollision ? "NEEDS_REVIEW" : "PROCESSED";
      await ctx.setInboxEvent({
        ...inbox,
        ownerId,
        connectionId: connection.id,
        walletId,
        grantVersion: connection.grantVersion ?? 1,
        state: finalState,
        status: finalState === "NEEDS_REVIEW" ? "needs_review" : "processed",
        linkedTransactionId: canonicalTxId,
        payload: minimizeInboxPayload(inbox.payload, { stripText: true }),
        leaseOwner: null,
        leaseExpiresAtMs: null,
        nextRetryAtMs: null,
        expiresAtMs: nowMs + INBOX_TERMINAL_TTL_MS,
        ...(balanceObservationSkippedStale ? { balanceObservationSkippedStale: true } : {}),
        updatedAtMs: nowMs
      });

      return {
        state: finalState,
        transactionId: canonicalTxId,
        notificationId: notifId
      };
    });
  }

  /**
   * BANK-01: Atomically claims an outbox record with CAS version + lease TTL.
   */
  async claimNotificationOutbox(
    outboxId: string,
    nowMs: number = Date.now(),
    leaseOwner: string = `worker_${crypto.randomUUID()}`,
    leaseTtlMs: number = OUTBOX_DEFAULT_LEASE_TTL_MS
  ): Promise<{ claimed: boolean; record: NotificationOutboxRecord | null }> {
    return this.store.claimNotificationOutbox(outboxId, nowMs, leaseOwner, leaseTtlMs);
  }

  /**
   * Stage 3: Notification Outbox -> FCM Delivery Worker.
   * Never rolls back financial transactions if FCM fails (T14); deduplicates via deterministic notificationId (T18).
   */
  async dispatchNotificationOutbox(
    notificationId: string,
    nowMs: number = Date.now(),
    leaseOwner: string = `worker_${crypto.randomUUID()}`,
    leaseTtlMs: number = OUTBOX_DEFAULT_LEASE_TTL_MS
  ): Promise<NotificationOutboxRecord | null> {
    // Atomic CAS lease claim prevents concurrent outbox workers from sending duplicate FCM pushes (T18 / BANK-01)!
    const claim = await this.store.claimNotificationOutbox(
      notificationId,
      nowMs,
      leaseOwner,
      leaseTtlMs
    );
    if (!claim.record) return null;
    if (!claim.claimed) {
      return claim.record;
    }
    const outbox = claim.record;
    const expectedVersion = outbox.version;
    const expectedLeaseOwner = outbox.leaseOwner ?? leaseOwner;

    const commitCas = async (nextRecord: NotificationOutboxRecord): Promise<NotificationOutboxRecord | null> => {
      const committed = await this.store.commitNotificationOutboxWithCas({
        outboxId: outbox.id,
        expectedVersion,
        expectedLeaseOwner,
        nextRecord
      });
      return committed.record;
    };

    // If a worker repeatedly crashed during DISPATCHING and exhausted the max retry budget, dead-letter cleanly.
    if (outbox.attemptCount > OUTBOX_MAX_ATTEMPTS) {
      return commitCas({
        ...outbox,
        state: "FAILED_PERMANENT",
        lastError: outbox.lastError ?? "MAX_ATTEMPTS_EXCEEDED_AFTER_CRASH",
        nextRetryAtMs: null,
        deadLetteredAtMs: nowMs,
        updatedAtMs: nowMs
      });
    }

    const deletionFrozen = await this.store.isUserDeletionFrozen(outbox.ownerId);
    if (deletionFrozen) {
      return commitCas({
        ...outbox,
        state: "skipped_revoked_or_reassigned",
        lastError: "ACCOUNT_DELETION_FROZEN",
        nextRetryAtMs: null,
        updatedAtMs: nowMs
      });
    }

    // H3: Strictly verify connection ownerId, active consent, grantVersion & walletId before dispatching!
    const connection = outbox.connectionId
      ? await this.store.getConnectionById(outbox.connectionId)
      : null;
    const expectedGrantVersion = outbox.grantVersion ?? 1;
    let dropReason: string | null = null;
    if (!connection) {
      dropReason = "CONNECTION_NOT_FOUND";
    } else if (connection.ownerId !== outbox.ownerId) {
      dropReason = "CONNECTION_OWNER_MISMATCH";
    } else if (!isConnectionActiveAndGranted(connection)) {
      dropReason = "CONNECTION_REVOKED_OR_INACTIVE";
    } else if ((connection.grantVersion ?? 1) !== expectedGrantVersion) {
      dropReason = "CONNECTION_GRANT_VERSION_MISMATCH";
    } else if (outbox.walletId && connection.linkedWalletId !== outbox.walletId) {
      dropReason = "CONNECTION_WALLET_MISMATCH";
    }

    if (dropReason !== null) {
      return commitCas({
        ...outbox,
        state: "skipped_revoked_or_reassigned",
        lastError: dropReason,
        nextRetryAtMs: null,
        updatedAtMs: nowMs
      });
    }

    const prefs = await this.store.getUserNotificationPreferences(outbox.ownerId);
    const suppressed =
      (outbox.direction === "credit" && !prefs.notifyCredit) ||
      (outbox.direction === "debit" && !prefs.notifyDebit) ||
      outbox.amountMinor < prefs.minAmountMinor ||
      prefs.mutedConnectionIds.includes(outbox.connectionId) ||
      (outbox.verificationStatus !== "VERIFIED" && !prefs.notifyUnverified);

    if (suppressed) {
      return commitCas({
        ...outbox,
        state: "SUPPRESSED_BY_PREFS",
        nextRetryAtMs: null,
        updatedAtMs: nowMs
      });
    }

    const devices = await this.store.listActiveUserDevices(outbox.ownerId);
    const allActiveTokens = Array.from(
      new Set(
        devices
          .filter((d) => d.ownerId === outbox.ownerId && d.pushEnabled && d.fcmToken.trim().length > 0)
          .map((d) => d.fcmToken.trim())
      )
    );
    const alreadyDeliveredSet = new Set(outbox.deliveredTokens ?? []);

    if (allActiveTokens.length === 0) {
      return commitCas({
        ...outbox,
        state: alreadyDeliveredSet.size > 0 ? "DELIVERED" : "NO_ACTIVE_DEVICES",
        failedTokens: {},
        lastError: null,
        nextRetryAtMs: null,
        updatedAtMs: nowMs
      });
    }

    // BANK-01: Exclude already-delivered tokens so retries NEVER re-send to already-delivered devices!
    const tokensToSend = allActiveTokens.filter((token) => !alreadyDeliveredSet.has(token));
    if (tokensToSend.length === 0) {
      return commitCas({
        ...outbox,
        state: "DELIVERED",
        deliveredTokens: Array.from(alreadyDeliveredSet),
        failedTokens: {},
        lastError: null,
        nextRetryAtMs: null,
        updatedAtMs: nowMs
      });
    }

    const copy = buildBankingNotificationCopy({
      direction: outbox.direction,
      amountMinor: outbox.amountMinor,
      bankName: outbox.bankName,
      accountMasked: outbox.accountMasked,
      content: outbox.content,
      occurredAtMs: outbox.occurredAtMs,
      verificationStatus: outbox.verificationStatus,
      prefs
    });

    try {
      const sendRes = await this.fcmSender.sendToUserDevices({
        tokens: tokensToSend,
        notificationId: outbox.id,
        title: copy.title,
        body: copy.pushBody,
        lockscreenPrivate: prefs.hideAmountOnLockscreen,
        soundEnabled: prefs.soundEnabled,
        data: {
          type: "bank_transaction",
          targetUid: outbox.ownerId,
          ownerId: outbox.ownerId,
          notificationId: outbox.id,
          transactionId: outbox.transactionId,
          walletId: outbox.walletId,
          connectionId: outbox.connectionId,
          direction: outbox.direction,
          verificationStatus: outbox.verificationStatus
        }
      });

      if (sendRes.invalidTokens.length > 0) {
        await this.store.deactivateInvalidTokens(outbox.ownerId, sendRes.invalidTokens);
      }

      const invalidSet = new Set(sendRes.invalidTokens);
      let newlySucceeded: string[];
      if (sendRes.succeededTokens !== undefined) {
        newlySucceeded = sendRes.succeededTokens.filter(
          (t) => tokensToSend.includes(t) && !invalidSet.has(t)
        );
      } else if (sendRes.failureCount === 0 && sendRes.successCount >= tokensToSend.length) {
        newlySucceeded = [...tokensToSend];
      } else if (sendRes.successCount <= 0) {
        newlySucceeded = [];
      } else {
        newlySucceeded = tokensToSend
          .filter((t) => !invalidSet.has(t))
          .slice(0, sendRes.successCount);
      }

      const newlySucceededSet = new Set(newlySucceeded);
      const nextFailedTokens: Record<string, string> = {};
      if (sendRes.failedTokens !== undefined) {
        for (const [tok, errCode] of Object.entries(sendRes.failedTokens)) {
          if (!invalidSet.has(tok) && !newlySucceededSet.has(tok) && !alreadyDeliveredSet.has(tok)) {
            nextFailedTokens[tok] = errCode || "messaging/transient-error";
          }
        }
      }
      if (sendRes.failedTokens === undefined || sendRes.failureCount > sendRes.invalidTokens.length) {
        for (const tok of tokensToSend) {
          if (!invalidSet.has(tok) && !newlySucceededSet.has(tok) && !(tok in nextFailedTokens)) {
            nextFailedTokens[tok] = sendRes.retryableError ?? "messaging/transient-error";
          }
        }
      }

      const nextDeliveredTokens = Array.from(
        new Set([...alreadyDeliveredSet, ...newlySucceeded])
      );
      const retryableFailedTokens = Object.keys(nextFailedTokens);

      const allRemainingResolved =
        retryableFailedTokens.length === 0 &&
        (nextDeliveredTokens.length > 0 || !sendRes.retryableError);

      if (allRemainingResolved) {
        return commitCas({
          ...outbox,
          state: nextDeliveredTokens.length > 0 ? "DELIVERED" : "NO_ACTIVE_DEVICES",
          deliveredTokens: nextDeliveredTokens,
          failedTokens: {},
          lastError: null,
          nextRetryAtMs: null,
          deadLetteredAtMs: null,
          updatedAtMs: nowMs
        });
      }

      const currentAttempt = outbox.attemptCount;
      const nextState = currentAttempt >= OUTBOX_MAX_ATTEMPTS ? "FAILED_PERMANENT" : "FAILED_RETRYABLE";
      const firstErr =
        sendRes.retryableError ??
        Object.values(nextFailedTokens)[0] ??
        "FCM_ALL_TOKENS_FAILED";

      return commitCas({
        ...outbox,
        state: nextState,
        deliveredTokens: nextDeliveredTokens,
        failedTokens: nextFailedTokens,
        lastError: firstErr,
        nextRetryAtMs:
          nextState === "FAILED_RETRYABLE"
            ? nowMs + RealtimeBankingCoordinator.computeOutboxRetryDelayMs(currentAttempt)
            : null,
        deadLetteredAtMs: nextState === "FAILED_PERMANENT" ? nowMs : null,
        updatedAtMs: nowMs
      });
    } catch (err) {
      const currentAttempt = outbox.attemptCount;
      const nextState = currentAttempt >= OUTBOX_MAX_ATTEMPTS ? "FAILED_PERMANENT" : "FAILED_RETRYABLE";
      const errMsg = err instanceof Error ? err.message : "FCM_TRANSPORT_ERROR";
      const nextFailedTokens: Record<string, string> = {};
      for (const tok of tokensToSend) {
        nextFailedTokens[tok] = errMsg;
      }
      return commitCas({
        ...outbox,
        state: nextState,
        deliveredTokens: Array.from(alreadyDeliveredSet),
        failedTokens: nextFailedTokens,
        lastError: errMsg,
        nextRetryAtMs:
          nextState === "FAILED_RETRYABLE"
            ? nowMs + RealtimeBankingCoordinator.computeOutboxRetryDelayMs(currentAttempt)
            : null,
        deadLetteredAtMs: nextState === "FAILED_PERMANENT" ? nowMs : null,
        updatedAtMs: nowMs
      });
    }
  }

  /**
   * Exponential backoff schedule for `FAILED_RETRYABLE` FCM outbox records:
   * Attempt 1 -> 30s, Attempt 2 -> 2m, Attempt 3 -> 8m, Attempt 4 -> 30m, Attempt >= 5 -> FAILED_PERMANENT.
   */
  static computeOutboxRetryDelayMs(attemptCount: number): number {
    switch (attemptCount) {
      case 1:
        return 30_000;
      case 2:
        return 120_000;
      case 3:
        return 480_000;
      default:
        return 1_800_000;
    }
  }

  static computeInboxRetryDelayMs(attemptCount: number): number {
    switch (attemptCount) {
      case 1:
        return 30_000;
      case 2:
        return 120_000;
      case 3:
        return 480_000;
      case 4:
        return 1_800_000;
      default:
        return 3_600_000;
    }
  }

  /**
   * BANK-01: Starvation-free outbox recovery sweeper covering due `FAILED_RETRYABLE`,
   * expired `DISPATCHING` leases (crashed workers), and stale `PENDING` / `PENDING_DELIVERY` records.
   */
  async recoverNotificationOutbox(
    nowMs: number = Date.now(),
    limit: number = 50
  ): Promise<{
    scanned: number;
    attempted: number;
    delivered: number;
    stillRetryable: number;
    permanentFailures: number;
  }> {
    const ids = await this.store.listRecoverableOutboxIds(nowMs, limit);
    let attempted = 0;
    let delivered = 0;
    let stillRetryable = 0;
    let permanentFailures = 0;

    for (const outboxId of ids) {
      attempted += 1;
      const updated = await this.dispatchNotificationOutbox(outboxId, nowMs);
      if (updated?.state === "DELIVERED") {
        delivered += 1;
      } else if (updated?.state === "FAILED_PERMANENT") {
        permanentFailures += 1;
      } else if (updated?.state === "FAILED_RETRYABLE") {
        stillRetryable += 1;
      }
    }

    return {
      scanned: ids.length,
      attempted,
      delivered,
      stillRetryable,
      permanentFailures
    };
  }

  /**
   * F12 / BG-02: Autonomous scheduled retry sweep for recoverable outbox notifications.
   * Never creates duplicate `financial_notifications` and guarantees at-most-once delivery per attempt window.
   */
  async retryDueNotificationOutboxBatch(
    nowMs = Date.now(),
    limit = 50
  ): Promise<{
    attempted: number;
    delivered: number;
    stillRetryable: number;
    permanentFailures: number;
  }> {
    const res = await this.recoverNotificationOutbox(nowMs, limit);
    return {
      attempted: res.attempted,
      delivered: res.delivered,
      stillRetryable: res.stillRetryable,
      permanentFailures: res.permanentFailures
    };
  }

  /**
   * BANK-02: Sweeps `PENDING_PROCESSING` (past grace/lease) and due `FAILED_RETRYABLE`
   * webhook inbox events with lease protection and retry budget (`maxAttempts = 6` -> `DEAD_LETTER`).
   */
  async recoverPendingWebhookInbox(
    nowMs: number = Date.now(),
    limit: number = 50,
    pendingGraceMs: number = INBOX_STALE_PENDING_GRACE_MS
  ): Promise<{
    scanned: number;
    processed: number;
    retried: number;
    deadLettered: number;
    oldestPendingAgeMs: number;
  }> {
    const { records, oldestPendingAgeMs } = await this.store.listRecoverableInboxRecords(
      nowMs,
      limit,
      pendingGraceMs
    );
    const leaseOwner = `inbox_sweeper_${crypto.randomUUID()}`;

    let scanned = 0;
    let processed = 0;
    let retried = 0;
    let deadLettered = 0;

    for (const rec of records) {
      const claim = await this.store.claimInboxEvent(
        rec.providerEventKey,
        nowMs,
        leaseOwner,
        INBOX_DEFAULT_LEASE_TTL_MS
      );
      if (!claim.claimed || !claim.record) {
        continue;
      }
      scanned += 1;
      const claimedRec = claim.record;
      const attempts = claimedRec.attemptCount ?? 1;

      if (attempts > INBOX_MAX_ATTEMPTS) {
        const reason = claimedRec.errorReason ?? "MAX_ATTEMPTS_EXCEEDED";
        await this.store.updateInboxRecord({
          ...claimedRec,
          state: "DEAD_LETTER",
          status: "dead_letter",
          deadLetterReason: reason,
          errorReason: reason,
          payload: minimizeInboxPayload(claimedRec.payload, { stripText: true }),
          leaseOwner: null,
          leaseExpiresAtMs: null,
          nextRetryAtMs: null,
          expiresAtMs: nowMs + INBOX_DEAD_LETTER_TTL_MS,
          updatedAtMs: nowMs
        });
        deadLettered += 1;
        continue;
      }

      try {
        const out = await this.processInboxEvent(claimedRec.providerEventKey, nowMs, {
          expectedLeaseOwner: leaseOwner
        });
        if (out.state === "FAILED_RETRYABLE") {
          retried += 1;
        } else if (out.state === "DEAD_LETTER") {
          deadLettered += 1;
        } else {
          processed += 1;
        }
      } catch (err) {
        const errMsg = err instanceof Error ? err.message : "INBOX_PROCESSING_ERROR";
        if (attempts >= INBOX_MAX_ATTEMPTS) {
          await this.store.updateInboxRecord({
            ...claimedRec,
            state: "DEAD_LETTER",
            status: "dead_letter",
            deadLetterReason: errMsg,
            errorReason: errMsg,
            payload: minimizeInboxPayload(claimedRec.payload, { stripText: true }),
            leaseOwner: null,
            leaseExpiresAtMs: null,
            nextRetryAtMs: null,
            expiresAtMs: nowMs + INBOX_DEAD_LETTER_TTL_MS,
            updatedAtMs: nowMs
          });
          deadLettered += 1;
        } else {
          await this.store.updateInboxRecord({
            ...claimedRec,
            state: "FAILED_RETRYABLE",
            status: "failed_retryable",
            errorReason: errMsg,
            leaseOwner: null,
            leaseExpiresAtMs: null,
            nextRetryAtMs: nowMs + RealtimeBankingCoordinator.computeInboxRetryDelayMs(attempts),
            updatedAtMs: nowMs
          });
          retried += 1;
        }
      }
    }

    return {
      scanned,
      processed,
      retried,
      deadLettered,
      oldestPendingAgeMs
    };
  }

  /**
   * BANK-02: Purges unlinked (`ownerId == null`) and expired inbox documents past `expiresAtMs`.
   */
  async purgeExpiredInboxRecords(
    nowMs: number = Date.now(),
    limit: number = 100
  ): Promise<{ purged: number; deletedCount: number }> {
    return this.store.purgeExpiredInboxRecords(nowMs, limit);
  }

  /**
   * F13 / FIN-05, M9 & BANK-03: Multi-page idempotent SePay REST reconciliation engine with
   * strict pre-watermark validation, resumable `(connectionId, grantVersion)` cursor,
   * incomplete backfill detection (never advances watermark on truncation), and CAS watermark commit.
   */
  async reconcilePaginatedSePayPages(params: {
    ownerId: string;
    connectionId: string;
    accountNumber: string;
    subAccount?: string;
    bankName: string;
    fetchPage: (
      pageIndex: number,
      pageLimit: number,
      cursor?: { beforeExternalTxId?: string | null }
    ) => Promise<Array<Record<string, unknown>>>;
    pageSize?: number;
    maxPages?: number;
    stopAtExternalTxId?: string;
    cursor?: BackfillCursorRecord | null;
    startPage?: number;
    resetCursor?: boolean;
    nowMs?: number;
  }): Promise<ReconcilePagesResult> {
    const pageSize = Math.max(1, Math.min(params.pageSize ?? 100, 200));
    const maxPages = Math.max(1, Math.min(params.maxPages ?? 10, 25));
    const nowMs = params.nowMs ?? Date.now();

    const deletionFrozen = await this.store.isUserDeletionFrozen(params.ownerId);
    if (deletionFrozen) {
      throw new Error("ACCOUNT_DELETION_FROZEN");
    }

    const conn = await this.store.getConnectionById(params.connectionId);
    if (!conn || conn.ownerId !== params.ownerId || !isConnectionActiveAndGranted(conn)) {
      throw new Error("CONNECTION_REVOKED_OR_INACTIVE");
    }

    const expectedGrantVersion = conn.grantVersion ?? 1;
    const previousWatermarkExternalTxId =
      params.stopAtExternalTxId !== undefined
        ? params.stopAtExternalTxId.trim() || undefined
        : (conn.lastSyncedExternalTxId ?? conn.lastReconciledExternalTxId ?? undefined);

    const savedCursor =
      !params.resetCursor &&
      conn.backfillCursor &&
      conn.backfillCursor.connectionId === conn.id &&
      conn.backfillCursor.grantVersion === expectedGrantVersion &&
      (conn.backfillCursor.previousWatermarkExternalTxId ?? null) ===
        (previousWatermarkExternalTxId ?? null)
        ? conn.backfillCursor
        : null;

    const activeCursor = params.cursor ?? savedCursor;
    const startPage = params.startPage ?? activeCursor?.nextPage ?? 0;

    let pagesFetched = 0;
    let fetchedCount = 0;
    let processedCount = 0;
    let duplicateCount = 0;
    let invalidCount = 0;
    let skippedCount = 0;
    let reachedPreviousWatermark = false;
    let hitMaxPagesWithFullPage = false;
    let candidateNewestValidExternalTxId: string | null =
      activeCursor?.pendingNewestValidExternalTxId ?? null;
    let lastSeenValidExternalTxId: string | null = activeCursor?.beforeExternalTxId ?? null;

    for (let offsetPage = 0; offsetPage < maxPages; offsetPage++) {
      const page = startPage + offsetPage;
      const items = await params.fetchPage(page, pageSize, {
        beforeExternalTxId: lastSeenValidExternalTxId
      });
      pagesFetched += 1;
      if (!Array.isArray(items) || items.length === 0) {
        break;
      }

      let hitWatermark = false;
      const parsedPageItems: ValidatedSePayWebhookPayload[] = [];
      for (const raw of items) {
        const extId = String(raw.id ?? "").trim();
        if (previousWatermarkExternalTxId && extId && extId === previousWatermarkExternalTxId) {
          hitWatermark = true;
          reachedPreviousWatermark = true;
          break;
        }

        const rawIdNum = Number(raw.id);
        if (!Number.isSafeInteger(rawIdNum) || rawIdNum <= 0) {
          invalidCount += 1;
          continue;
        }

        const rawAmountIn =
          raw.amount_in !== undefined && raw.amount_in !== null && raw.amount_in !== ""
            ? Number(raw.amount_in)
            : 0;
        const rawAmountOut =
          raw.amount_out !== undefined && raw.amount_out !== null && raw.amount_out !== ""
            ? Number(raw.amount_out)
            : 0;

        if (!Number.isFinite(rawAmountIn) || !Number.isFinite(rawAmountOut)) {
          invalidCount += 1;
          continue;
        }
        if ((rawAmountIn > 0 && rawAmountOut > 0) || (rawAmountIn <= 0 && rawAmountOut <= 0)) {
          invalidCount += 1;
          continue;
        }

        const transferType = rawAmountIn > 0 ? "in" : "out";
        const transferAmount = rawAmountIn > 0 ? rawAmountIn : rawAmountOut;
        const rawAcc =
          raw.accumulated !== undefined && raw.accumulated !== null && raw.accumulated !== ""
            ? Number(raw.accumulated)
            : 0;

        const normalizedPayload = Buffer.from(
          JSON.stringify({
            id: rawIdNum,
            gateway: String(raw.bank_brand_name ?? params.bankName),
            transactionDate: String(raw.transaction_date ?? ""),
            accountNumber: params.accountNumber,
            subAccount: String(raw.sub_account ?? params.subAccount ?? ""),
            code: raw.code ?? null,
            content: String(raw.transaction_content ?? ""),
            transferType,
            description: String(raw.transaction_content ?? ""),
            transferAmount,
            accumulated: Number.isFinite(rawAcc) ? rawAcc : 0,
            referenceCode: String(raw.reference_number ?? "")
          }),
          "utf8"
        );

        const validated = parseAndValidateSePayPayload(normalizedPayload);
        if (!validated.valid || !validated.payload) {
          // BANK-03: Never promote an invalid/malformed row into newestValidExternalTxId!
          invalidCount += 1;
          continue;
        }

        fetchedCount += 1;
        const validIdStr = String(validated.payload.id);
        if (candidateNewestValidExternalTxId === null) {
          candidateNewestValidExternalTxId = validIdStr;
        }
        lastSeenValidExternalTxId = validIdStr;
        parsedPageItems.push(validated.payload);
      }

      // M9: Sort each page chronologically (oldest -> newest) so observed balance advances monotonically
      // and older historical items never regress wallet.balanceMinor.
      parsedPageItems.sort((a, b) => a.occurredAtMs - b.occurredAtMs || a.id - b.id);

      for (const validatedPayload of parsedPageItems) {
        const providerEventKey = `sepay_${conn.id}_${validatedPayload.id}`;
        await this.store.createDurableInboxIfAbsent({
          providerEventKey,
          provider: "sepay",
          externalTransactionId: String(validatedPayload.id),
          connectionId: conn.id,
          ownerId: conn.ownerId,
          walletId: conn.linkedWalletId,
          grantVersion: expectedGrantVersion,
          state: "PENDING_PROCESSING",
          status: "pending_processing",
          payload: minimizeInboxPayload(validatedPayload, { stripText: false }),
          attemptCount: 0,
          leaseOwner: null,
          leaseExpiresAtMs: null,
          nextRetryAtMs: null,
          receivedAtMs: nowMs,
          updatedAtMs: nowMs
        });

        const out = await this.processInboxEvent(providerEventKey, nowMs);
        if (out.state === "DUPLICATE") {
          duplicateCount += 1;
        } else if (out.state === "PROCESSED" || out.state === "NEEDS_REVIEW") {
          processedCount += 1;
          if (out.notificationId) {
            await this.dispatchNotificationOutbox(out.notificationId, nowMs);
          }
        } else {
          skippedCount += 1;
        }
      }

      if (hitWatermark || items.length < pageSize) {
        break;
      }

      if (offsetPage === maxPages - 1 && items.length >= pageSize) {
        hitMaxPagesWithFullPage = true;
      }
    }

    const incomplete = !reachedPreviousWatermark && hitMaxPagesWithFullPage;
    const resumableCursor: BackfillCursorRecord | null = incomplete
      ? {
          connectionId: conn.id,
          grantVersion: expectedGrantVersion,
          nextPage: startPage + pagesFetched,
          beforeExternalTxId: lastSeenValidExternalTxId,
          pendingNewestValidExternalTxId: candidateNewestValidExternalTxId,
          previousWatermarkExternalTxId: previousWatermarkExternalTxId ?? null,
          updatedAtMs: nowMs
        }
      : null;

    // BANK-03: CAS verification on `(connectionId, grantVersion)` before advancing watermark or persisting cursor.
    // Never advances `lastSyncedExternalTxId` when `incomplete === true`, when `newestValidExternalTxId == null`,
    // or when connection was revoked / re-linked mid-backfill!
    const casRes = await this.store.commitReconciliationStateCas({
      ownerId: params.ownerId,
      connectionId: conn.id,
      expectedGrantVersion,
      incomplete,
      newestValidExternalTxId: candidateNewestValidExternalTxId,
      resumableCursor,
      nowMs
    });

    const watermarkAdvanced =
      casRes.committed && !incomplete && candidateNewestValidExternalTxId !== null;

    return {
      pagesFetched,
      fetchedCount,
      processedCount,
      duplicateCount,
      invalidCount,
      skippedCount,
      reachedPreviousWatermark,
      incomplete,
      watermarkAdvanced,
      ...(casRes.committed ? {} : { watermarkAbortedReason: casRes.reason ?? "CONNECTION_REVOKED_OR_GRANT_CHANGED" }),
      newestValidExternalTxId: candidateNewestValidExternalTxId,
      newestExternalTxId:
        watermarkAdvanced && candidateNewestValidExternalTxId ? candidateNewestValidExternalTxId : undefined,
      resumableCursor
    };
  }

  /**
   * H2: Atomically revokes bank connection consent, updates user mirror & releases claims.
   */
  async revokeConnection(
    ownerId: string,
    connectionId: string,
    nowMs: number = Date.now()
  ): Promise<void> {
    await this.store.disconnectConnection(ownerId, connectionId, nowMs);
  }

  /**
   * Multi-User Bank Linking with Strict SePay Identity Proof, Wallet Ownership Check &
   * Transactional Claim Ownership (Section 7, T23, Finding 3).
   * Typing an account number alone NEVER creates a `connected` SePay connection!
   */
  async verifyAndConnectBankAccount(params: {
    authenticatedUserId: string;
    bankCode: string;
    accountNumber: string;
    subAccount?: string;
    linkedWalletId: string;
    sepayAccounts?: readonly SePayBankAccountApiItem[];
    providerAccountProof?: {
      verifiedByProviderApi: boolean;
      providerConnectionId?: string;
    };
    nowMs?: number;
  }): Promise<{ ok: boolean; errorCode?: string; connection?: ServerBankConnectionRecord }> {
    const nowMs = params.nowMs ?? Date.now();
    const uid = params.authenticatedUserId.trim();
    const linkedWalletId = params.linkedWalletId.trim();
    const cleanAcc = params.accountNumber.replace(/[^A-Za-z0-9]/g, "").trim();
    if (!uid || !linkedWalletId) {
      return { ok: false, errorCode: "WALLET_NOT_FOUND_OR_FORBIDDEN" };
    }
    if (cleanAcc.length < 6) {
      return { ok: false, errorCode: "INVALID_ACCOUNT_NUMBER" };
    }

    let cap: BankIntegrationCapability;
    let verifiedSubAcc: string;
    let providerConnectionId: string;
    let providerAccountId: string | undefined;

    if (params.sepayAccounts !== undefined) {
      const matched = matchVerifiedSePayAccount({
        sepayAccounts: params.sepayAccounts,
        requestedBankCode: params.bankCode,
        requestedAccountNumber: cleanAcc,
        requestedSubAccount: params.subAccount
      });
      if (!matched.ok) {
        return { ok: false, errorCode: matched.errorCode };
      }
      cap = matched.capability;
      verifiedSubAcc = matched.subAccount;
      providerConnectionId = matched.providerConnectionId;
      providerAccountId = matched.providerAccountId;
    } else {
      // T23: Manual account input without provider proof MUST NOT be marked connected!
      if (!params.providerAccountProof?.verifiedByProviderApi) {
        return { ok: false, errorCode: "OWNERSHIP_PROOF_REQUIRED" };
      }
      const resolved = resolveBankCapability(params.bankCode);
      if (!resolved || !resolved.supportsWebhookCredit) {
        return { ok: false, errorCode: "UNSUPPORTED_PROVIDER_BANK" };
      }
      cap = resolved;
      verifiedSubAcc = (params.subAccount ?? "").trim();
      providerConnectionId =
        params.providerAccountProof.providerConnectionId?.trim() ||
        `sepay_conn_${sha256Hex(`${cap.bankCode}:${cleanAcc}:${verifiedSubAcc}`).slice(0, 14)}`;
      if (providerConnectionId.startsWith("sepay_ba_")) {
        const extractedId = providerConnectionId.slice("sepay_ba_".length).trim();
        if (extractedId) providerAccountId = extractedId;
      }
    }

    // Legacy non-claim conflict pre-check (in case connections predate server_bank_account_claims)
    const existingLegacyConn = await this.store.findAnyVerifiedConnectionByAccount(
      cap.bankCode,
      cleanAcc,
      verifiedSubAcc
    );
    if (
      existingLegacyConn &&
      existingLegacyConn.ownerId !== uid &&
      isConnectionActiveAndGranted(existingLegacyConn)
    ) {
      return { ok: false, errorCode: "ACCOUNT_ALREADY_LINKED_OTHER_USER" };
    }

    const acctClaimId = buildNormalizedAccountClaimId(cap.bankCode, cleanAcc, verifiedSubAcc);
    const idClaimId = providerAccountId
      ? buildProviderAccountIdClaimId(providerAccountId)
      : null;

    const connId = `conn_${cap.bankCode.toLowerCase()}_${sha256Hex(`${uid}:${cleanAcc}:${verifiedSubAcc}`).slice(0, 14)}`;

    return this.store.runAtomic(async (tx) => {
      // 1. All reads MUST occur before any writes (Cloud Firestore transaction constraint)
      const deletionFrozen = await tx.isUserDeletionFrozen(uid);
      const targetWallet = await tx.getWallet(uid, linkedWalletId);
      const acctClaim = await tx.getBankAccountClaim(acctClaimId);
      const idClaim = idClaimId ? await tx.getBankAccountClaim(idClaimId) : null;
      const existingConn = await tx.getConnectionById(connId);

      if (deletionFrozen) {
        return { ok: false, errorCode: "ACCOUNT_DELETION_FROZEN" };
      }

      if (!targetWallet || targetWallet.ownerId !== uid) {
        return { ok: false, errorCode: "WALLET_NOT_FOUND_OR_FORBIDDEN" };
      }
      if (targetWallet.archived === true || targetWallet.isArchived === true) {
        return { ok: false, errorCode: "WALLET_ARCHIVED_OR_FORBIDDEN" };
      }

      if (
        acctClaim &&
        acctClaim.status === "connected" &&
        acctClaim.ownerId !== uid
      ) {
        return { ok: false, errorCode: "ACCOUNT_ALREADY_LINKED_OTHER_USER" };
      }
      if (
        idClaim &&
        idClaim.status === "connected" &&
        idClaim.ownerId !== uid
      ) {
        return { ok: false, errorCode: "ACCOUNT_ALREADY_LINKED_OTHER_USER" };
      }

      const prevGrantVersion =
        existingConn && typeof existingConn.grantVersion === "number" && existingConn.grantVersion >= 1
          ? existingConn.grantVersion
          : 0;
      const nextGrantVersion = existingConn ? Math.max(1, prevGrantVersion) + 1 : 1;

      const record: ServerBankConnectionRecord = {
        id: connId,
        ownerId: uid,
        provider: "sepay",
        providerConnectionId,
        bankCode: cap.bankCode,
        bankName: cap.bankName,
        accountNumber: cleanAcc,
        accountMasked: maskAccountNumber(cleanAcc),
        subAccount: verifiedSubAcc,
        linkedWalletId,
        consentStatus: "granted",
        consentEnabled: true,
        status: "connected",
        grantVersion: nextGrantVersion,
        capabilities: cap,
        lastSyncedAtMs: nowMs,
        revokedAtMs: null,
        createdAtMs: existingConn?.createdAtMs ?? nowMs,
        updatedAtMs: nowMs
      };

      // 2. Write ownership claims + connection atomically inside the SAME transaction
      await tx.upsertBankAccountClaim({
        claimId: acctClaimId,
        ownerId: uid,
        connectionId: connId,
        provider: "sepay",
        providerConnectionId,
        ...(providerAccountId ? { providerAccountId } : {}),
        bankCode: cap.bankCode,
        accountNumber: cleanAcc,
        subAccount: verifiedSubAcc,
        status: "connected",
        updatedAtMs: nowMs
      });

      if (idClaimId) {
        await tx.upsertBankAccountClaim({
          claimId: idClaimId,
          ownerId: uid,
          connectionId: connId,
          provider: "sepay",
          providerConnectionId,
          ...(providerAccountId ? { providerAccountId } : {}),
          bankCode: cap.bankCode,
          accountNumber: cleanAcc,
          subAccount: verifiedSubAcc,
          status: "connected",
          updatedAtMs: nowMs
        });
      }

      await tx.saveVerifiedConnectionTx(record);
      return { ok: true, connection: record };
    });
  }
}
