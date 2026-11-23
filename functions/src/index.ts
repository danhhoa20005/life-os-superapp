import * as admin from "firebase-admin";
import { HttpsError, onCall, onRequest } from "firebase-functions/v2/https";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { defineSecret } from "firebase-functions/params";
import { BANK_CAPABILITY_CATALOG } from "./capabilities";
import { RealtimeBankingCoordinator } from "./bankingEngine";
import { FirebaseAdminFcmSender, FirestoreAdminBankingStore } from "./firestoreStore";
import { parseAndValidateSePayPayload } from "./schema";
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
    // Accept `/webhooks/sepay` (when routed via Firebase Hosting rewrite) or `/` (direct Function URL)
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

    // Verify ownership directly against SePay User API from trusted backend (Source B)
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
 * 7. Source B — Controlled Server-Side SePay REST API Reconciliation (`reconcileBankConnectionViaApi`).
 *    Fetches missed historical transactions on backend and routes each item through the exact same
 *    idempotent Canonical Ledger pipeline (T21 — zero duplicates with Webhook!).
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
    if (!connectionId || sepayApiToken.length < 16) {
      throw new HttpsError("invalid-argument", "Thiếu connectionId hoặc token đối soát.");
    }

    const db = admin.firestore();
    const connSnap = await db.collection("server_bank_connections").doc(connectionId).get();
    if (!connSnap.exists || connSnap.data()?.ownerId !== uid) {
      throw new HttpsError("permission-denied", "Không tìm thấy kết nối ngân hàng hợp lệ.");
    }
    const conn = connSnap.data()!;
    const accountNumber = String(conn.accountNumber ?? "");

    const resp = await fetch(
      `https://my.sepay.vn/userapi/transactions/list?account_number=${encodeURIComponent(accountNumber)}&limit=20`,
      {
        method: "GET",
        headers: {
          Authorization: `Bearer ${sepayApiToken}`,
          Accept: "application/json"
        }
      }
    );
    if (!resp.ok) {
      throw new HttpsError("unavailable", "Không thể tải danh sách đối soát từ SePay API.");
    }

    const json = (await resp.json()) as { transactions?: Array<Record<string, unknown>> };
    const items = Array.isArray(json.transactions) ? json.transactions : [];
    const store = new FirestoreAdminBankingStore(db);
    const coordinator = createProductionCoordinator();

    let processed = 0;
    let duplicates = 0;

    for (const raw of items) {
      const amountIn = Number(raw.amount_in ?? 0);
      const amountOut = Number(raw.amount_out ?? 0);
      const transferType = amountIn > 0 ? "in" : "out";
      const transferAmount = Math.round(amountIn > 0 ? amountIn : amountOut);
      if (transferAmount <= 0) continue;

      const normalizedPayload = Buffer.from(
        JSON.stringify({
          id: Number(raw.id),
          gateway: String(raw.bank_brand_name ?? conn.bankName),
          transactionDate: String(raw.transaction_date ?? ""),
          accountNumber,
          subAccount: String(raw.sub_account ?? conn.subAccount ?? ""),
          code: raw.code ?? null,
          content: String(raw.transaction_content ?? ""),
          transferType,
          description: String(raw.transaction_content ?? ""),
          transferAmount,
          accumulated: Number(raw.accumulated ?? 0),
          referenceCode: String(raw.reference_number ?? "")
        }),
        "utf8"
      );

      const validated = parseAndValidateSePayPayload(normalizedPayload);
      if (!validated.valid || !validated.payload) continue;

      const providerEventKey = `sepay_${connectionId}_${validated.payload.id}`;
      await store.createDurableInboxIfAbsent({
        providerEventKey,
        provider: "sepay",
        externalTransactionId: String(validated.payload.id),
        connectionId,
        ownerId: uid,
        state: "PENDING_PROCESSING",
        payload: validated.payload,
        receivedAtMs: Date.now(),
        updatedAtMs: Date.now()
      });

      const out = await coordinator.processInboxEvent(providerEventKey);
      if (out.state === "DUPLICATE") {
        duplicates += 1;
      } else if (out.state === "PROCESSED" || out.state === "NEEDS_REVIEW") {
        processed += 1;
        if (out.notificationId) {
          await coordinator.dispatchNotificationOutbox(out.notificationId);
        }
      }
    }

    const jobId = `rec_${connectionId}_${Date.now()}`;
    await db.collection("bank_reconciliation_jobs").doc(jobId).set({
      id: jobId,
      ownerId: uid,
      connectionId,
      fetchedCount: items.length,
      processedCount: processed,
      duplicateCount: duplicates,
      completedAt: admin.firestore.Timestamp.now()
    });

    return { ok: true, fetchedCount: items.length, processedCount: processed, duplicateCount: duplicates };
  }
);

export { BANK_CAPABILITY_CATALOG };
export * from "./bankingEngine";
export * from "./capabilities";
export * from "./schema";
export * from "./security";
export * from "./memoryStore";
export * from "./firestoreStore";
