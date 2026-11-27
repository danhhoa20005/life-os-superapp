import { BankIntegrationCapability } from "./capabilities";
import { containsOtpOrSecret, sha256Hex } from "./security";

export type BalanceType = "observedBankBalance" | "estimatedWalletBalance" | "unknownBalance";

export type InboxProcessingState =
  | "RECEIVED"
  | "VALIDATED"
  | "PENDING_PROCESSING"
  | "PROCESSED"
  | "DUPLICATE"
  | "NEEDS_REVIEW"
  | "FAILED_RETRYABLE"
  | "FAILED_PERMANENT"
  | "skipped_revoked_or_reassigned";

export type VerificationStatus =
  | "PROVISIONAL"
  | "VERIFIED"
  | "USER_CONFIRMED"
  | "REJECTED"
  | "NEEDS_REVIEW";

export interface ServerBankConnectionRecord {
  readonly id: string;
  readonly ownerId: string;
  readonly provider: "sepay" | "android_only";
  readonly providerConnectionId: string;
  readonly bankCode: string;
  readonly bankName: string;
  readonly accountNumber: string; // Stored ONLY in server_bank_connections
  readonly accountMasked: string;
  readonly subAccount: string;
  readonly linkedWalletId: string;
  readonly consentStatus: "granted" | "revoked";
  readonly consentEnabled?: boolean;
  readonly status: "pending_verification" | "connected" | "active" | "disconnected" | "revoked" | "error";
  readonly grantVersion: number;
  readonly webhookSecretHash?: string;
  readonly encryptedApiToken?: string;
  readonly capabilities: BankIntegrationCapability;
  readonly lastSyncedAtMs: number | null;
  readonly revokedAtMs?: number | null;
  readonly createdAtMs: number;
  readonly updatedAtMs: number;
}

export type ServerBankConnection = ServerBankConnectionRecord;

export interface InboxEventRecord {
  readonly providerEventKey: string;
  readonly provider: "sepay";
  readonly externalTransactionId: string;
  readonly connectionId: string | null;
  readonly ownerId: string | null;
  readonly walletId?: string | null;
  readonly grantVersion?: number | null;
  readonly state: InboxProcessingState;
  readonly status?: string;
  readonly payload: ValidatedSePayWebhookPayload;
  readonly linkedTransactionId?: string;
  readonly balanceObservationSkippedStale?: boolean;
  readonly errorReason?: string;
  readonly reason?: string;
  readonly receivedAtMs: number;
  readonly updatedAtMs: number;
}

export type SepayWebhookInboxEvent = InboxEventRecord;

export interface NotificationOutboxRecord {
  readonly id: string;
  readonly ownerId: string;
  readonly transactionId: string;
  readonly walletId: string;
  readonly connectionId: string;
  readonly grantVersion?: number;
  readonly direction: "credit" | "debit";
  readonly amountMinor: number;
  readonly bankCode: string;
  readonly bankName: string;
  readonly accountMasked: string;
  readonly content: string;
  readonly occurredAtMs: number;
  readonly verificationStatus: VerificationStatus;
  readonly state:
    | "PENDING_DELIVERY"
    | "DISPATCHING"
    | "DELIVERED"
    | "SUPPRESSED_BY_PREFS"
    | "NO_ACTIVE_DEVICES"
    | "FAILED_RETRYABLE"
    | "FAILED_PERMANENT"
    | "skipped_revoked_or_reassigned";
  readonly attemptCount: number;
  readonly lastError?: string;
  readonly nextRetryAtMs?: number;
  readonly createdAtMs: number;
  readonly updatedAtMs: number;
}

export type NotificationOutboxEvent = NotificationOutboxRecord;

export interface ValidatedSePayWebhookPayload {
  readonly id: number;
  readonly gateway: string;
  readonly transactionDate: string;
  readonly occurredAtMs: number;
  readonly accountNumber: string;
  readonly subAccount: string;
  readonly code: string | null;
  readonly content: string;
  readonly transferType: "in" | "out";
  readonly direction: "credit" | "debit";
  readonly description: string;
  readonly transferAmount: number; // Exact positive integer VND
  readonly accumulatedMinor: number | null; // Strictly > 0 when observed; null if 0 or absent (T15)
  readonly balanceType: BalanceType;
  readonly referenceCode: string;
}

export interface SchemaValidationOutcome {
  readonly valid: boolean;
  readonly payload?: ValidatedSePayWebhookPayload;
  readonly errorCode?: string;
  readonly message?: string;
}

function parseVietnamTimestampMs(raw: string): number | null {
  const trimmed = raw.trim();
  if (!trimmed) return null;
  // SePay format: "YYYY-MM-DD HH:mm:ss" in Asia/Ho_Chi_Minh (+07:00) or ISO-8601
  const vnMatch = /^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2}):(\d{2})$/.exec(trimmed);
  if (vnMatch) {
    const iso = `${vnMatch[1]}-${vnMatch[2]}-${vnMatch[3]}T${vnMatch[4]}:${vnMatch[5]}:${vnMatch[6]}+07:00`;
    const ms = Date.parse(iso);
    return Number.isFinite(ms) ? ms : null;
  }
  const ms = Date.parse(trimmed);
  return Number.isFinite(ms) ? ms : null;
}

/**
 * Strictly validates incoming SePay JSON body:
 * - Rejects non-integer / float / zero / negative transferAmount (strict integer VND).
 * - Strips/ignores any untrusted external `userId` field (Section 6 rule #7).
 * - Blocks OTP/SmartOTP/PIN/CVV content (T19).
 * - Never treats `accumulated = 0` as a real zero bank balance (T15).
 */
export function parseAndValidateSePayPayload(rawBody: Buffer): SchemaValidationOutcome {
  let obj: unknown;
  try {
    obj = JSON.parse(rawBody.toString("utf8"));
  } catch {
    return { valid: false, errorCode: "INVALID_JSON", message: "Request body is not valid JSON." };
  }

  if (typeof obj !== "object" || obj === null || Array.isArray(obj)) {
    return { valid: false, errorCode: "INVALID_OBJECT", message: "Payload must be a JSON object." };
  }

  const rec = obj as Record<string, unknown>;

  if (typeof rec.id !== "number" || !Number.isSafeInteger(rec.id) || rec.id <= 0) {
    return { valid: false, errorCode: "INVALID_ID", message: "Field 'id' must be a positive integer." };
  }

  if (typeof rec.gateway !== "string" || rec.gateway.trim().length === 0 || rec.gateway.length > 80) {
    return { valid: false, errorCode: "INVALID_GATEWAY", message: "Field 'gateway' is required." };
  }

  if (typeof rec.accountNumber !== "string" || rec.accountNumber.replace(/[^A-Za-z0-9]/g, "").length < 4) {
    return { valid: false, errorCode: "INVALID_ACCOUNT", message: "Field 'accountNumber' is invalid." };
  }

  if (rec.transferType !== "in" && rec.transferType !== "out") {
    return {
      valid: false,
      errorCode: "INVALID_TRANSFER_TYPE",
      message: "Field 'transferType' must be 'in' or 'out'."
    };
  }

  if (
    typeof rec.transferAmount !== "number" ||
    !Number.isSafeInteger(rec.transferAmount) ||
    rec.transferAmount <= 0
  ) {
    return {
      valid: false,
      errorCode: "INVALID_AMOUNT",
      message: "Field 'transferAmount' must be a positive safe integer VND."
    };
  }

  if (typeof rec.transactionDate !== "string") {
    return { valid: false, errorCode: "INVALID_DATE", message: "Field 'transactionDate' is required." };
  }
  const occurredAtMs = parseVietnamTimestampMs(rec.transactionDate);
  if (occurredAtMs === null) {
    return { valid: false, errorCode: "INVALID_DATE", message: "Unparseable 'transactionDate'." };
  }

  const content = typeof rec.content === "string" ? rec.content.trim().slice(0, 500) : "";
  const description = typeof rec.description === "string" ? rec.description.trim().slice(0, 500) : "";
  if (containsOtpOrSecret(`${content} ${description}`)) {
    return {
      valid: false,
      errorCode: "BLOCKED_OTP_SECRET",
      message: "Payload rejected because it contains OTP/PIN/security code markers."
    };
  }

  // T15: Do NOT treat accumulated <= 0 as a real zero bank balance!
  let accumulatedMinor: number | null = null;
  let balanceType: BalanceType = "unknownBalance";
  if (typeof rec.accumulated === "number" && Number.isSafeInteger(rec.accumulated) && rec.accumulated > 0) {
    accumulatedMinor = rec.accumulated;
    balanceType = "observedBankBalance";
  }

  const subAccount = typeof rec.subAccount === "string" ? rec.subAccount.trim().slice(0, 64) : "";
  const code = typeof rec.code === "string" && rec.code.trim().length > 0 ? rec.code.trim().slice(0, 64) : null;
  const referenceCode = typeof rec.referenceCode === "string" ? rec.referenceCode.trim().slice(0, 80) : "";
  const cleanAcc = rec.accountNumber.replace(/[^A-Za-z0-9]/g, "").trim();

  return {
    valid: true,
    payload: {
      id: rec.id,
      gateway: rec.gateway.trim(),
      transactionDate: rec.transactionDate.trim(),
      occurredAtMs,
      accountNumber: cleanAcc,
      subAccount,
      code,
      content,
      transferType: rec.transferType,
      direction: rec.transferType === "in" ? "credit" : "debit",
      description,
      transferAmount: rec.transferAmount,
      accumulatedMinor,
      balanceType,
      referenceCode
    }
  };
}

/**
 * Explainable deterministic Vietnamese category classifier (matches Dart BankNotificationParser).
 * Never falsely labeled as AI.
 */
export function classifyVietnameseTransaction(
  text: string,
  direction: "credit" | "debit",
  customRules?: ReadonlyMap<string, string>
): { categoryName: string; isVehicleMaintenanceHint: boolean; isRecurringCandidate: boolean } {
  const upper = text.toUpperCase();
  if (customRules) {
    for (const [keyword, cat] of customRules.entries()) {
      if (keyword.trim() && upper.includes(keyword.trim().toUpperCase())) {
        return {
          categoryName: cat,
          isVehicleMaintenanceHint: false,
          isRecurringCandidate: false
        };
      }
    }
  }

  const isVehicleMaint = /\b(thay\s*nh[oớ]t|thay\s*d[aầ]u|b[aả]o\s*d[uư][oỡ]ng\s*xe|head\s*honda|yamaha\s*town|s[uử]a\s*xe|l[oố]p\s*xe|[aắ]c\s*quy|gara)\b/i.test(
    text
  );

  if (direction === "credit") {
    if (/\b(l[uư][oơ]ng|salary|th[uư][oở]ng)\b/i.test(text)) {
      return { categoryName: "Lương & Thu nhập", isVehicleMaintenanceHint: false, isRecurringCandidate: false };
    }
    return { categoryName: "Thu nhập khác", isVehicleMaintenanceHint: false, isRecurringCandidate: false };
  }

  if (/\b(evn|ti[eề]n\s*[đd]i[eệ]n|ti[eề]n\s*n[uư][oớ]c|sawaco|viettel|vnpt|fpt|internet|wifi)\b/i.test(text)) {
    return { categoryName: "Hóa đơn", isVehicleMaintenanceHint: false, isRecurringCandidate: true };
  }
  if (/\b(thu[eê]\s*nh[aà]|ti[eề]n\s*tr[oọ]|ph[ií]\s*chung\s*c[uư]|netflix|spotify|icloud|youtube)\b/i.test(text)) {
    return { categoryName: "Nhà cửa & Thuê nhà", isVehicleMaintenanceHint: false, isRecurringCandidate: true };
  }
  if (isVehicleMaint || /\b([đd][oổ]\s*x[aă]ng|x[aă]ng|petrolimex|pvoil)\b/i.test(text)) {
    return { categoryName: "Xe cộ", isVehicleMaintenanceHint: isVehicleMaint, isRecurringCandidate: false };
  }
  if (/\b(grab|xanh\s*sm|be\s*group|epass|vetc|g[uử]i\s*xe)\b/i.test(text)) {
    return { categoryName: "Di chuyển", isVehicleMaintenanceHint: false, isRecurringCandidate: false };
  }
  if (/\b(shopee|lazada|tiki|tiktok\s*shop|co\.?opmart|winmart|bach\s*hoa\s*xanh|mua\s*s[aắ]m)\b/i.test(text)) {
    return { categoryName: "Mua sắm", isVehicleMaintenanceHint: false, isRecurringCandidate: false };
  }
  if (/\b(c[oơ]m|ph[oở]|b[uú]n|cafe|coffee|highlands|phuc\s*long|kfc|pizza|[aă]n|u[oố]ng)\b/i.test(text)) {
    return { categoryName: "Ăn uống", isVehicleMaintenanceHint: false, isRecurringCandidate: false };
  }
  return { categoryName: "Chi tiêu khác", isVehicleMaintenanceHint: isVehicleMaint, isRecurringCandidate: false };
}

export function computeCrossSourceFingerprint(params: {
  ownerId: string;
  direction: "credit" | "debit";
  amountMinor: number;
  occurredAtMs: number;
  referenceCode?: string;
}): string {
  const bucket15m = Math.floor(params.occurredAtMs / (15 * 60 * 1000));
  const ref = params.referenceCode && params.referenceCode.trim().length > 0
    ? params.referenceCode.trim().toUpperCase()
    : `BUCKET_${bucket15m}`;
  return sha256Hex(`${params.ownerId}|${params.direction}|${params.amountMinor}|${ref}`).slice(0, 32);
}

export function computeSoftWindowFingerprint(params: {
  ownerId: string;
  direction: "credit" | "debit";
  amountMinor: number;
  occurredAtMs: number;
}): string {
  const bucket15m = Math.floor(params.occurredAtMs / (15 * 60 * 1000));
  return sha256Hex(`${params.ownerId}|${params.direction}|${params.amountMinor}|SOFT_${bucket15m}`).slice(0, 32);
}

export function computeOverlappingSoftWindowFingerprints(params: {
  ownerId: string;
  direction: "credit" | "debit";
  amountMinor: number;
  occurredAtMs: number;
}): string[] {
  const w = 15 * 60 * 1000;
  const set = new Set<string>([
    computeSoftWindowFingerprint({ ...params, occurredAtMs: params.occurredAtMs - w }),
    computeSoftWindowFingerprint(params),
    computeSoftWindowFingerprint({ ...params, occurredAtMs: params.occurredAtMs + w })
  ]);
  return Array.from(set);
}

export function formatVndCompactNotification(amountMinor: number): string {
  const formatted = Math.abs(Math.trunc(amountMinor))
    .toString()
    .replace(/\B(?=(\d{3})+(?!\d))/g, ".");
  return `${formatted}đ`;
}

export function extractAccountTail(raw?: string | null): string | null {
  if (!raw) return null;
  const cleaned = raw.replace(/[^A-Za-z0-9]/g, "").trim();
  if (cleaned.length < 4) return null;
  return cleaned.slice(-4).toUpperCase();
}

export function isConnectionActiveAndGranted(
  conn: ServerBankConnectionRecord | null | undefined
): conn is ServerBankConnectionRecord {
  if (!conn) return false;
  const activeStatus = conn.status === "connected" || conn.status === "active";
  return activeStatus && conn.consentStatus === "granted" && conn.consentEnabled !== false;
}

export interface MonotonicBalanceDecision {
  readonly shouldUpdateObservedBalance: boolean;
  readonly balanceObservationSkippedStale: boolean;
}

export function evaluateMonotonicObservedBalance(params: {
  observedBalanceMinor: number | null;
  eventOccurredAtEpochMs: number;
  existingLastObservedAtEpochMs?: number | null;
}): MonotonicBalanceDecision {
  if (params.observedBalanceMinor === null || params.observedBalanceMinor <= 0) {
    return {
      shouldUpdateObservedBalance: false,
      balanceObservationSkippedStale: false
    };
  }
  if (
    params.existingLastObservedAtEpochMs == null ||
    params.eventOccurredAtEpochMs >= params.existingLastObservedAtEpochMs
  ) {
    return {
      shouldUpdateObservedBalance: true,
      balanceObservationSkippedStale: false
    };
  }
  return {
    shouldUpdateObservedBalance: false,
    balanceObservationSkippedStale: true
  };
}
