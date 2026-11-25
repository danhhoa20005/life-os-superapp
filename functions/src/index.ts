import * as admin from "firebase-admin";
import { FunctionsErrorCode, HttpsError, onCall, onRequest } from "firebase-functions/v2/https";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { defineSecret } from "firebase-functions/params";
import { BANK_CAPABILITY_CATALOG } from "./capabilities";
import { RealtimeBankingCoordinator } from "./bankingEngine";
import {
  CollaborationSpaceType,
  FamilyInviteCoordinator,
  FamilyInviteError,
  FirestoreAdminFamilyInviteStore,
  InviteKind
} from "./familyInvites";
import { FirebaseAdminFcmSender, FirestoreAdminBankingStore } from "./firestoreStore";
import { sha256Hex } from "./security";

if (admin.apps.length === 0) {
  admin.initializeApp();
}

const SEPAY_WEBHOOK_SECRET = defineSecret("SEPAY_WEBHOOK_SECRET");

function createProductionCoordinator(secretValue?: string): RealtimeBankingCoordinator {
  const db = admin.firestore();
  const store = new FirestoreAdminBankingStore(db);
  const fcm = new FirebaseAdminFcmSender(admin.messaging());
  return new RealtimeBankingCoordinator(store, fcm, () => secretValue || process.env.SEPAY_WEBHOOK_SECRET);
}

/**
 * 1. HTTPS Endpoint: `POST /webhooks/sepay` (Cloud Functions Gen 2)
 *    - Enforces HTTP POST, <= 64KB rawBody, constant-time HMAC-SHA256 (`X-SePay-Signature`)
 *      and ±300s anti-replay window (`X-SePay-Timestamp`).
 *    - Persists event into `sepay_webhook_inbox` BEFORE returning HTTP 200 `{"success": true}`.
 */
export const sepayWebhook = onRequest(
  {
    region: "asia-southeast1",
    secrets: [SEPAY_WEBHOOK_SECRET],
    maxInstances: 20,
    cors: false
  },
  async (req, res) => {
    const normalizedPath = (req.path || "/").replace(/\/+$/, "") || "/";
    if (normalizedPath !== "/" && normalizedPath !== "/webhooks/sepay") {
      res.status(404).json({ success: false, error: "NOT_FOUND" });
      return;
    }

    const coordinator = createProductionCoordinator(SEPAY_WEBHOOK_SECRET.value());
    const headers: Record<string, string | undefined> = {};
    for (const [k, v] of Object.entries(req.headers)) {
      headers[k.toLowerCase()] = Array.isArray(v) ? v[0] : v;
    }

    const rawBuf = Buffer.isBuffer(req.rawBody)
      ? req.rawBody
      : Buffer.from(typeof req.body === "string" ? req.body : JSON.stringify(req.body ?? {}), "utf8");

    const outcome = await coordinator.handleSePayWebhookHttp({
      method: req.method,
      rawBody: rawBuf,
      headers
    });

    res.status(outcome.statusCode).json(outcome.body);
  }
);

/**
 * 2. Async Queue Worker: Processes `sepay_webhook_inbox/{providerEventKey}` into Canonical Ledger
 *    and enqueues `notification_outbox/{notificationId}`.
 */
export const processSePayInboxWorker = onDocumentCreated(
  {
    document: "sepay_webhook_inbox/{providerEventKey}",
    region: "asia-southeast1"
  },
  async (event) => {
    const providerEventKey = event.params.providerEventKey;
    const coordinator = createProductionCoordinator();
    await coordinator.processInboxEvent(providerEventKey);
  }
);

/**
 * 3. Async Outbox Worker: Dispatches FCM Push Notification with privacy redaction & retry state.
 */
export const dispatchNotificationOutboxWorker = onDocumentCreated(
  {
    document: "notification_outbox/{notificationId}",
    region: "asia-southeast1"
  },
  async (event) => {
    const notificationId = event.params.notificationId;
    const coordinator = createProductionCoordinator();
    await coordinator.dispatchNotificationOutbox(notificationId);
  }
);

/**
 * 3b. F12 / BG-02 Scheduled Outbox Recovery Worker:
 *     Every 5 minutes, sweeps `FAILED_RETRYABLE` outbox items whose exponential backoff
 *     (`nextRetryAtMs`) has elapsed, retrying up to 5 total attempts before `FAILED_PERMANENT` dead-letter.
 */
export const retryFailedNotificationOutboxWorker = onSchedule(
  {
    schedule: "every 5 minutes",
    region: "asia-southeast1",
    maxInstances: 1
  },
  async () => {
    const coordinator = createProductionCoordinator();
    await coordinator.retryDueNotificationOutboxBatch(Date.now(), 50);
  }
);

/**
 * 4. Authenticated Callable: Verifies user bank ownership via user's SePay API credential on server
 *    (never storing raw token in user-readable Firestore!) and binds BankConnection -> Wallet.
 */
export const verifyAndLinkBankConnection = onCall(
  { region: "asia-southeast1" },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "Vui lòng đăng nhập để liên kết ngân hàng.");
    }

    const data = (request.data ?? {}) as Record<string, unknown>;
    const bankCode = String(data.bankCode ?? "").trim();
    const accountNumber = String(data.accountNumber ?? "").replace(/[^A-Za-z0-9]/g, "").trim();
    const subAccount = String(data.subAccount ?? "").trim();
    const linkedWalletId = String(data.linkedWalletId ?? "").trim();
    const userSePayApiToken = String(data.sepayApiToken ?? "").trim();

    if (!bankCode || accountNumber.length < 6 || !linkedWalletId) {
      throw new HttpsError("invalid-argument", "Thiếu thông tin ngân hàng, số tài khoản hoặc ví liên kết.");
    }

    if (userSePayApiToken.length < 16) {
      throw new HttpsError(
        "failed-precondition",
        "Cần xác minh quyền sở hữu tài khoản qua SePay API Token hợp lệ của bạn (không tự đánh dấu Đã kết nối khi chỉ nhập số tài khoản)."
      );
    }

    let verifiedAccountFound = false;
    let providerConnectionId = "";
    try {
      const resp = await fetch("https://my.sepay.vn/userapi/bankaccounts/list", {
        method: "GET",
        headers: {
          Authorization: `Bearer ${userSePayApiToken}`,
          Accept: "application/json"
        }
      });
      if (!resp.ok) {
        throw new HttpsError("permission-denied", "SePay từ chối xác thực API Token. Vui lòng kiểm tra lại.");
      }
      const bodyJson = (await resp.json()) as {
        bankaccounts?: Array<{ id?: string | number; account_number?: string; bank_short_name?: string }>;
      };
      const list = Array.isArray(bodyJson.bankaccounts) ? bodyJson.bankaccounts : [];
      const matched = list.find((acc) => {
        const cleanRemote = String(acc.account_number ?? "").replace(/[^A-Za-z0-9]/g, "").trim();
        return cleanRemote === accountNumber;
      });
      if (matched) {
        verifiedAccountFound = true;
        providerConnectionId = `sepay_ba_${matched.id ?? sha256Hex(accountNumber).slice(0, 10)}`;
      }
    } catch (err) {
      if (err instanceof HttpsError) throw err;
      throw new HttpsError("unavailable", "Không thể kết nối tới máy chủ xác minh SePay lúc này.");
    }

    const coordinator = createProductionCoordinator();
    const res = await coordinator.verifyAndConnectBankAccount({
      authenticatedUserId: uid,
      bankCode,
      accountNumber,
      subAccount,
      linkedWalletId,
      providerAccountProof: {
        verifiedByProviderApi: verifiedAccountFound,
        providerConnectionId
      }
    });

    if (!res.ok || !res.connection) {
      throw new HttpsError(
        "permission-denied",
        res.errorCode === "ACCOUNT_ALREADY_LINKED_OTHER_USER"
          ? "Tài khoản ngân hàng này đã được liên kết với một người dùng khác."
          : "Tài khoản ngân hàng không thuộc danh sách đã xác minh trên SePay của bạn."
      );
    }

    return {
      ok: true,
      connectionId: res.connection.id,
      accountMasked: res.connection.accountMasked,
      capabilities: res.connection.capabilities
    };
  }
);

/**
 * 5. Authenticated Callable: Revoke consent & disconnect bank connection.
 */
export const disconnectBankConnection = onCall(
  { region: "asia-southeast1" },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "Vui lòng đăng nhập.");
    }
    const connectionId = String((request.data ?? {}).connectionId ?? "").trim();
    if (!connectionId) {
      throw new HttpsError("invalid-argument", "Thiếu connectionId.");
    }
    const store = new FirestoreAdminBankingStore(admin.firestore());
    await store.disconnectConnection(uid, connectionId, Date.now());
    return { ok: true };
  }
);

/**
 * 6. Authenticated Callable: Migrate legacy `users/{uid}/consents/sepay_api` cleanly
 *    without exposing or logging plaintext tokens (Section 14 & Phase 4 Migration).
 */
export const migrateLegacySePayToken = onCall(
  { region: "asia-southeast1" },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "Vui lòng đăng nhập.");
    }
    const db = admin.firestore();
    const store = new FirestoreAdminBankingStore(db);
    const legacy = await store.readAndDeleteLegacySePayConsent(uid);
    if (!legacy || !legacy.apiToken) {
      return { migrated: false };
    }
    await db.collection("bank_reconciliation_jobs").doc(`mig_${uid}`).set({
      id: `mig_${uid}`,
      ownerId: uid,
      type: "legacy_token_purged_and_vaulted",
      tokenFingerprint: sha256Hex(legacy.apiToken).slice(0, 16),
      migratedAt: admin.firestore.Timestamp.now()
    });
    return { migrated: true };
  }
);

/**
 * 7. Source B — Paginated Server-Side SePay REST API Reconciliation (`reconcileBankConnectionViaApi` — F13 / FIN-05).
 *    Paginates across up to 10 pages × 100 items (1,000 transactions per backfill), supports optional
 *    `transactionDateMin` / `transactionDateMax` & connection watermark (`lastReconciledExternalTxId`),
 *    and routes every item through the idempotent Canonical Ledger pipeline!
 */
export const reconcileBankConnectionViaApi = onCall(
  { region: "asia-southeast1" },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "Vui lòng đăng nhập.");
    }
    const data = (request.data ?? {}) as Record<string, unknown>;
    const connectionId = String(data.connectionId ?? "").trim();
    const sepayApiToken = String(data.sepayApiToken ?? "").trim();
    const dateMin = String(data.transactionDateMin ?? "").trim();
    const dateMax = String(data.transactionDateMax ?? "").trim();
    const ignoreWatermark = Boolean(data.ignoreWatermark);

    if (!connectionId || sepayApiToken.length < 16) {
      throw new HttpsError("invalid-argument", "Thiếu connectionId hoặc token đối soát.");
    }

    const db = admin.firestore();
    const connRef = db.collection("server_bank_connections").doc(connectionId);
    const connSnap = await connRef.get();
    if (!connSnap.exists || connSnap.data()?.ownerId !== uid) {
      throw new HttpsError("permission-denied", "Không tìm thấy kết nối ngân hàng hợp lệ.");
    }
    const conn = connSnap.data()!;
    if (conn.status !== "connected" || conn.consentStatus !== "granted") {
      throw new HttpsError(
        "failed-precondition",
        "Kết nối ngân hàng đã ngắt hoặc chưa được cấp quyền đồng bộ."
      );
    }
    const accountNumber = String(conn.accountNumber ?? "");
    const watermarkTxId = ignoreWatermark ? undefined : (conn.lastReconciledExternalTxId as string | undefined);

    const coordinator = createProductionCoordinator();
    const summary = await coordinator.reconcilePaginatedSePayPages({
      ownerId: uid,
      connectionId,
      accountNumber,
      subAccount: String(conn.subAccount ?? ""),
      bankName: String(conn.bankName ?? conn.bankCode ?? "Bank"),
      pageSize: 100,
      maxPages: 10,
      stopAtExternalTxId: watermarkTxId,
      fetchPage: async (pageIndex, pageLimit) => {
        const offset = pageIndex * pageLimit;
        const params = new URLSearchParams({
          account_number: accountNumber,
          limit: String(pageLimit),
          offset: String(offset)
        });
        if (dateMin) params.set("transaction_date_min", dateMin);
        if (dateMax) params.set("transaction_date_max", dateMax);

        const resp = await fetch(`https://my.sepay.vn/userapi/transactions/list?${params.toString()}`, {
          method: "GET",
          headers: {
            Authorization: `Bearer ${sepayApiToken}`,
            Accept: "application/json"
          }
        });
        if (!resp.ok) {
          throw new HttpsError("unavailable", `Không thể tải trang ${pageIndex + 1} danh sách đối soát từ SePay API.`);
        }
        const json = (await resp.json()) as { transactions?: Array<Record<string, unknown>> };
        return Array.isArray(json.transactions) ? json.transactions : [];
      }
    });

    if (summary.newestExternalTxId) {
      await connRef.set(
        {
          lastReconciledExternalTxId: summary.newestExternalTxId,
          lastReconciledAt: admin.firestore.Timestamp.now()
        },
        { merge: true }
      );
    }

    const jobId = `rec_${connectionId}_${Date.now()}`;
    await db.collection("bank_reconciliation_jobs").doc(jobId).set({
      id: jobId,
      ownerId: uid,
      connectionId,
      pagesFetched: summary.pagesFetched,
      fetchedCount: summary.fetchedCount,
      processedCount: summary.processedCount,
      duplicateCount: summary.duplicateCount,
      completedAt: admin.firestore.Timestamp.now()
    });

    return {
      ok: true,
      pagesFetched: summary.pagesFetched,
      fetchedCount: summary.fetchedCount,
      processedCount: summary.processedCount,
      duplicateCount: summary.duplicateCount
    };
  }
);

function mapFamilyInviteErrorToHttps(err: unknown): HttpsError {
  if (err instanceof HttpsError) return err;
  if (err instanceof FamilyInviteError) {
    const codeMap: Record<FamilyInviteError["code"], FunctionsErrorCode> = {
      UNAUTHENTICATED: "unauthenticated",
      INVALID_ARGUMENT: "invalid-argument",
      PERMISSION_DENIED: "permission-denied",
      NOT_FOUND: "not-found",
      FAILED_PRECONDITION: "failed-precondition",
      RESOURCE_EXHAUSTED: "resource-exhausted"
    };
    return new HttpsError(codeMap[err.code] ?? "internal", err.message);
  }
  return new HttpsError("internal", "Không thể xử lý yêu cầu lời mời nhóm lúc này.");
}

function createFamilyInviteCoordinator(): FamilyInviteCoordinator {
  const store = new FirestoreAdminFamilyInviteStore(admin.firestore());
  return new FamilyInviteCoordinator(store);
}

/**
 * 8. Family Invite Callables (FIX-002 & FIX-003):
 *    - `createFamilyInvite`: Server-authoritative 3-mode invite creation (`oneTime`, `targeted`, `reusableGroup`)
 *      with SHA-256 `intendedRecipientHash` and ZERO plaintext contact PII on `family_invites/{code}`.
 *    - `previewFamilyInvite`: Safe minimal metadata preview without exposing `families/{id}`, rate-limited by UID.
 *    - `joinFamilyByInvite`: Atomic `runTransaction` consuming 1 slot and assigning `'member'` role safely.
 *    - `revokeFamilyInvite`: Manager-only atomic revocation across `family_invites` and `families.pendingInvites`.
 */
export const createFamilyInvite = onCall(
  { region: "asia-southeast1" },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "Vui lòng đăng nhập để tạo mã mời.");
    }
    const data = (request.data ?? {}) as Record<string, unknown>;
    const rawKind = typeof data.inviteKind === "string" ? data.inviteKind : undefined;
    const inviteKind: InviteKind | undefined =
      rawKind === "oneTime" || rawKind === "targeted" || rawKind === "reusableGroup"
        ? rawKind
        : undefined;
    try {
      return await createFamilyInviteCoordinator().createFamilyInvite({
        actorUserId: uid,
        familyId: String(data.familyId ?? ""),
        invitedByName: typeof data.invitedByName === "string" ? data.invitedByName : undefined,
        inviteKind,
        maxUses: typeof data.maxUses === "number" ? data.maxUses : undefined,
        ttlDays: typeof data.ttlDays === "number" ? data.ttlDays : undefined,
        inviteeName: typeof data.inviteeName === "string" ? data.inviteeName : undefined,
        inviteeContact: typeof data.inviteeContact === "string" ? data.inviteeContact : undefined
      });
    } catch (err) {
      throw mapFamilyInviteErrorToHttps(err);
    }
  }
);

export const previewFamilyInvite = onCall(
  { region: "asia-southeast1" },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "Vui lòng đăng nhập để kiểm tra mã mời.");
    }
    const data = (request.data ?? {}) as Record<string, unknown>;
    try {
      const res = await createFamilyInviteCoordinator().previewFamilyInvite({
        actorUserId: uid,
        inviteCode: String(data.inviteCode ?? "")
      });
      return res as {
        ok: true;
        inviteCode: string;
        familyId: string;
        familyName: string;
        spaceType: CollaborationSpaceType;
        inviteKind: InviteKind;
        isTargeted: boolean;
        invitedByName: string;
        inviteeName?: string;
        maxUses: number;
        usedCount: number;
        expiresAtMs: number;
        status: string;
      };
    } catch (err) {
      throw mapFamilyInviteErrorToHttps(err);
    }
  }
);

export const joinFamilyByInvite = onCall(
  { region: "asia-southeast1" },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "Vui lòng đăng nhập để tham gia nhóm.");
    }
    const data = (request.data ?? {}) as Record<string, unknown>;
    const token = (request.auth?.token ?? {}) as Record<string, unknown>;
    const authEmailVerified = token.email_verified === true;
    const authEmail =
      authEmailVerified && typeof token.email === "string" ? token.email : undefined;
    const authPhoneNumber = typeof token.phone_number === "string" ? token.phone_number : undefined;
    try {
      return await createFamilyInviteCoordinator().joinFamilyByInvite({
        actorUserId: uid,
        userName: String(data.userName ?? "Thành viên"),
        inviteCode: String(data.inviteCode ?? ""),
        authEmail,
        authEmailVerified,
        authPhoneNumber
      });
    } catch (err) {
      throw mapFamilyInviteErrorToHttps(err);
    }
  }
);

export const revokeFamilyInvite = onCall(
  { region: "asia-southeast1" },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "Vui lòng đăng nhập để thu hồi mã mời.");
    }
    const data = (request.data ?? {}) as Record<string, unknown>;
    try {
      return await createFamilyInviteCoordinator().revokeFamilyInvite({
        actorUserId: uid,
        familyId: String(data.familyId ?? ""),
        inviteCode: String(data.inviteCode ?? "")
      });
    } catch (err) {
      throw mapFamilyInviteErrorToHttps(err);
    }
  }
);

async function deleteQueryInBatches(
  db: admin.firestore.Firestore,
  queryFactory: () => admin.firestore.Query
): Promise<number> {
  let deleted = 0;
  while (true) {
    const snap = await queryFactory().limit(400).get();
    if (snap.empty) break;
    const batch = db.batch();
    for (const doc of snap.docs) {
      batch.delete(doc.ref);
    }
    await batch.commit();
    deleted += snap.size;
    if (snap.size < 400) break;
  }
  return deleted;
}

export async function deleteServerOnlyUserAccountData(
  db: admin.firestore.Firestore,
  uid: string
): Promise<{ ok: true; deletedCount: number }> {
  const cleanUid = uid.trim();
  if (!cleanUid) {
    throw new HttpsError("invalid-argument", "Thiếu mã người dùng cần xóa dữ liệu.");
  }
  let deletedCount = 0;
  const ownerScopedCollections = [
    "server_bank_connections",
    "sepay_webhook_inbox",
    "notification_outbox",
    "bank_reconciliation_jobs",
    "family_invite_rate_limits"
  ];
  for (const colName of ownerScopedCollections) {
    deletedCount += await deleteQueryInBatches(db, () =>
      db.collection(colName).where("ownerId", "==", cleanUid)
    );
  }
  const directRateLimitRef = db.collection("family_invite_rate_limits").doc(cleanUid);
  const directRateLimitSnap = await directRateLimitRef.get();
  if (directRateLimitSnap.exists) {
    await directRateLimitRef.delete();
    deletedCount += 1;
  }
  return { ok: true, deletedCount };
}

export const deleteUserAccountData = onCall(
  { region: "asia-southeast1" },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "Vui lòng đăng nhập để xóa dữ liệu tài khoản.");
    }
    return deleteServerOnlyUserAccountData(admin.firestore(), uid);
  }
);

export { BANK_CAPABILITY_CATALOG };
export * from "./bankingEngine";
export * from "./capabilities";
export * from "./familyInvites";
export * from "./schema";
export * from "./security";
export * from "./memoryStore";
export * from "./firestoreStore";
