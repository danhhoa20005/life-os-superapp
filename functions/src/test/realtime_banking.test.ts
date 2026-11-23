import * as assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  FcmMulticastResult,
  FcmPushSender,
  RealtimeBankingCoordinator
} from "../bankingEngine";
import { resolveBankCapability } from "../capabilities";
import { SerializedMemoryBankingStore } from "../memoryStore";
import { computeSoftWindowFingerprint } from "../schema";
import { computeHmacSha256Hex } from "../security";

const TEST_SECRET = "lifeos_test_webhook_hmac_secret_2026_secure";

class RecordingFcmSender implements FcmPushSender {
  public calls: Array<{
    tokens: readonly string[];
    notificationId: string;
    title: string;
    body: string;
    data: Record<string, string>;
  }> = [];
  public shouldFail = false;
  public invalidTokensToReport: string[] = [];

  async sendToUserDevices(params: {
    tokens: readonly string[];
    notificationId: string;
    title: string;
    body: string;
    lockscreenPrivate: boolean;
    soundEnabled: boolean;
    data: Record<string, string>;
  }): Promise<FcmMulticastResult> {
    this.calls.push({
      tokens: params.tokens,
      notificationId: params.notificationId,
      title: params.title,
      body: params.body,
      data: params.data
    });
    if (this.shouldFail) {
      return {
        successCount: 0,
        failureCount: params.tokens.length,
        invalidTokens: this.invalidTokensToReport,
        retryableError: "messaging/internal-error"
      };
    }
    return {
      successCount: params.tokens.length - this.invalidTokensToReport.length,
      failureCount: this.invalidTokensToReport.length,
      invalidTokens: this.invalidTokensToReport
    };
  }
}

function buildSignedWebhookRequest(
  payloadObj: Record<string, unknown>,
  nowMs: number,
  secret: string = TEST_SECRET,
  overrideTimestampSec?: number
) {
  const rawBody = Buffer.from(JSON.stringify(payloadObj), "utf8");
  const tsSec = overrideTimestampSec ?? Math.floor(nowMs / 1000);
  const sigHex = computeHmacSha256Hex(secret, `${tsSec}.${rawBody.toString("utf8")}`);
  return {
    method: "POST",
    rawBody,
    nowMs,
    headers: {
      "x-sepay-signature": `sha256=${sigHex}`,
      "x-sepay-timestamp": String(tsSec)
    }
  };
}

describe("Life OS Real-Time Banking Backend — T01..T24 Verification Suite", () => {
  const baseNowMs = Date.parse("2026-11-23T09:30:10+07:00");

  async function createHarness() {
    const store = new SerializedMemoryBankingStore();
    const fcm = new RecordingFcmSender();
    const coordinator = new RealtimeBankingCoordinator(store, fcm, () => TEST_SECRET);

    await coordinator.verifyAndConnectBankAccount({
      authenticatedUserId: "user_minh",
      bankCode: "VCB",
      accountNumber: "1017588888",
      linkedWalletId: "wallet_vcb",
      providerAccountProof: { verifiedByProviderApi: true, providerConnectionId: "sp_vcb_1" },
      nowMs: baseNowMs
    });

    await coordinator.verifyAndConnectBankAccount({
      authenticatedUserId: "user_minh",
      bankCode: "TPB",
      accountNumber: "0123499999",
      subAccount: "TKP8899",
      linkedWalletId: "wallet_tpb",
      providerAccountProof: { verifiedByProviderApi: true, providerConnectionId: "sp_tpb_1" },
      nowMs: baseNowMs
    });

    store.wallets.set("user_minh::wallet_vcb", {
      id: "wallet_vcb",
      ownerId: "user_minh",
      name: "Vietcombank Chính",
      balanceMinor: 10000000,
      isEstimatedBalance: true,
      bankCode: "VCB",
      maskedAccount: "•••• 8888",
      updatedAtMs: baseNowMs
    });

    store.wallets.set("user_minh::wallet_tpb", {
      id: "wallet_tpb",
      ownerId: "user_minh",
      name: "TPBank Chi tiêu",
      balanceMinor: 5000000,
      isEstimatedBalance: true,
      bankCode: "TPB",
      maskedAccount: "•••• 9999",
      updatedAtMs: baseNowMs
    });

    store.userDevices.set("user_minh", [
      {
        deviceId: "pixel_9_pro",
        ownerId: "user_minh",
        fcmToken: "fcm_tok_pixel9_valid",
        platform: "android",
        pushEnabled: true,
        updatedAtMs: baseNowMs
      }
    ]);

    return { store, fcm, coordinator };
  }

  it("T01 & T12/T13 — Money-in webhook (500,000đ) creates 1 verified income transaction & dispatches FCM", async () => {
    const { store, fcm, coordinator } = await createHarness();
    const req = buildSignedWebhookRequest(
      {
        id: 92704,
        gateway: "Vietcombank",
        transactionDate: "2026-11-23 09:30:00",
        accountNumber: "1017588888",
        subAccount: "",
        code: null,
        content: "NGUYEN VAN A chuyen tien",
        transferType: "in",
        description: "NGUYEN VAN A chuyen tien",
        transferAmount: 500000,
        accumulated: 10500000,
        referenceCode: "FT24012345678"
      },
      baseNowMs
    );

    const httpRes = await coordinator.handleSePayWebhookHttp(req);
    assert.equal(httpRes.statusCode, 200);
    assert.deepEqual(httpRes.body, { success: true });
    assert.ok(httpRes.providerEventKey);

    const workerRes = await coordinator.processInboxEvent(httpRes.providerEventKey!, baseNowMs);
    assert.equal(workerRes.state, "PROCESSED");
    assert.ok(workerRes.notificationId);

    const outboxRes = await coordinator.dispatchNotificationOutbox(workerRes.notificationId!, baseNowMs);
    assert.equal(outboxRes?.state, "DELIVERED");
    assert.equal(fcm.calls.length, 1);
    assert.equal(fcm.calls[0].title, "💰 Life OS — Tiền vừa về!");
    // Default lockscreen privacy hides exact amount in pushBody!
    assert.equal(fcm.calls[0].body.includes("500.000đ"), false);
    assert.equal(fcm.calls[0].data.transactionId, workerRes.transactionId);

    const txs = Array.from(store.transactions.values());
    assert.equal(txs.length, 1);
    assert.equal(txs[0].direction, "credit");
    assert.equal(txs[0].kind, "income");
    assert.equal(txs[0].amountMinor, 500000);
    assert.equal(txs[0].verificationStatus, "VERIFIED");
    assert.equal(txs[0].balanceType, "observedBankBalance");
    assert.equal(store.wallets.get("user_minh::wallet_vcb")?.balanceMinor, 10500000);
  });

  it("T02 & T10 — Money-out webhook (200,000đ) on TPBank TKP routes to exact TPBank wallet without touching VCB", async () => {
    const { store, coordinator } = await createHarness();
    const req = buildSignedWebhookRequest(
      {
        id: 92705,
        gateway: "TPBank",
        transactionDate: "2026-11-23 09:31:00",
        accountNumber: "0123499999",
        subAccount: "TKP8899",
        code: null,
        content: "SHOPEE thanh toan don hang",
        transferType: "out",
        description: "SHOPEE thanh toan don hang",
        transferAmount: 200000,
        accumulated: 4800000,
        referenceCode: "FT998877"
      },
      baseNowMs
    );

    const httpRes = await coordinator.handleSePayWebhookHttp(req);
    assert.equal(httpRes.statusCode, 200);
    const workerRes = await coordinator.processInboxEvent(httpRes.providerEventKey!, baseNowMs);
    assert.equal(workerRes.state, "PROCESSED");

    const tx = store.transactions.get(`user_minh::${workerRes.transactionId}`);
    assert.ok(tx);
    assert.equal(tx.walletId, "wallet_tpb");
    assert.equal(tx.kind, "expense");
    assert.equal(tx.categoryName, "Mua sắm"); // Auto-categorized SHOPEE -> Mua sắm
    assert.equal(store.wallets.get("user_minh::wallet_tpb")?.balanceMinor, 4800000);
    assert.equal(store.wallets.get("user_minh::wallet_vcb")?.balanceMinor, 10000000);
  });

  it("T03, T04 & T18 — 10x webhook retries and concurrent Promise.all race condition produce EXACTLY 1 transaction, 1 balance update & 1 FCM push", async () => {
    const { store, fcm, coordinator } = await createHarness();
    const req = buildSignedWebhookRequest(
      {
        id: 93001,
        gateway: "Vietcombank",
        transactionDate: "2026-11-23 09:30:00",
        accountNumber: "1017588888",
        subAccount: "",
        code: null,
        content: "LUONG THANG 11",
        transferType: "in",
        description: "LUONG THANG 11",
        transferAmount: 15000000,
        accumulated: 0, // Force delta path so any double-add would be caught!
        referenceCode: "SAL202611"
      },
      baseNowMs
    );

    // Fire 10 webhook deliveries concurrently + process concurrently
    const responses = await Promise.all(
      Array.from({ length: 10 }, () => coordinator.handleSePayWebhookHttp(req))
    );
    for (const r of responses) {
      assert.equal(r.statusCode, 200);
    }

    const eventKey = responses[0].providerEventKey!;
    const workerResults = await Promise.all(
      Array.from({ length: 10 }, () => coordinator.processInboxEvent(eventKey, baseNowMs))
    );

    const processedCount = workerResults.filter((w) => w.state === "PROCESSED").length;
    const duplicateCount = workerResults.filter((w) => w.state === "DUPLICATE").length;
    assert.equal(processedCount, 1);
    assert.equal(duplicateCount, 9);

    // Dispatch outbox multiple times -> only 1 FCM multicast sent!
    const notifId = workerResults.find((w) => w.notificationId)?.notificationId!;
    await Promise.all([
      coordinator.dispatchNotificationOutbox(notifId, baseNowMs),
      coordinator.dispatchNotificationOutbox(notifId, baseNowMs)
    ]);
    // Sequential retry after DELIVERED is a no-op
    await coordinator.dispatchNotificationOutbox(notifId, baseNowMs);

    assert.equal(store.transactions.size, 1);
    // Initial 10,000,000 + 15,000,000 = 25,000,000 (strictly applied ONCE!)
    assert.equal(store.wallets.get("user_minh::wallet_vcb")?.balanceMinor, 25000000);
    assert.equal(fcm.calls.length, 1);
  });

  it("T05 & T24 — Cross-source reconciliation (provisional -> verified AND userConfirmed -> verified) NEVER double-counts wallet balance", async () => {
    const { store, coordinator } = await createHarness();
    const occMs = Date.parse("2026-11-23T09:30:00+07:00");
    const softFp = computeSoftWindowFingerprint({
      ownerId: "user_minh",
      direction: "credit",
      amountMinor: 450000,
      occurredAtMs: occMs
    });

    // Case A: Android created PROVISIONAL (`ledgerApplied: false`, wallet still 10,000,000)
    store.transactions.set("user_minh::prov_android_1", {
      id: "prov_android_1",
      ownerId: "user_minh",
      walletId: "wallet_vcb",
      sourceProvider: "android_device",
      sourceKind: "androidNotification",
      kind: "income",
      direction: "credit",
      amountMinor: 450000,
      currencyCode: "VND",
      merchant: "VCB: NGUYEN MINH",
      description: "VCB: NGUYEN MINH",
      categoryName: "Thu nhập khác",
      occurredAtMs: occMs - 20000,
      receivedAtMs: occMs - 19000,
      monthKey: "2026-11",
      verification: "provisional",
      verificationStatus: "PROVISIONAL",
      reconciliationStatus: "unreconciled_provisional",
      sourceEventKey: "android_ev_1",
      crossSourceFingerprint: "fp_1",
      softWindowFingerprint: softFp,
      balanceAfterMinor: null,
      balanceType: "unknownBalance",
      ledgerApplied: false,
      isVehicleMaintenanceHint: false,
      isRecurringCandidate: false,
      createdAtMs: occMs - 19000,
      updatedAtMs: occMs - 19000
    });

    const reqA = buildSignedWebhookRequest(
      {
        id: 94001,
        gateway: "Vietcombank",
        transactionDate: "2026-11-23 09:30:00",
        accountNumber: "1017588888",
        subAccount: "",
        code: null,
        content: "NGUYEN MINH chuyen khoan",
        transferType: "in",
        description: "NGUYEN MINH chuyen khoan",
        transferAmount: 450000,
        accumulated: 0,
        referenceCode: "FT450A"
      },
      baseNowMs
    );
    const httpA = await coordinator.handleSePayWebhookHttp(reqA);
    const workA = await coordinator.processInboxEvent(httpA.providerEventKey!, baseNowMs);
    assert.equal(workA.transactionId, "prov_android_1"); // Upgraded existing tx in-place!
    assert.equal(store.transactions.size, 1);
    assert.equal(store.transactions.get("user_minh::prov_android_1")?.verification, "verified");
    assert.equal(store.wallets.get("user_minh::wallet_vcb")?.balanceMinor, 10450000);

    // Case B: User ALREADY confirmed Android signal (`ledgerApplied: true`, wallet already +300k = 10,750,000)
    const occMsB = Date.parse("2026-11-23T09:32:00+07:00");
    const softFpB = computeSoftWindowFingerprint({
      ownerId: "user_minh",
      direction: "credit",
      amountMinor: 300000,
      occurredAtMs: occMsB
    });
    store.wallets.set("user_minh::wallet_vcb", {
      ...store.wallets.get("user_minh::wallet_vcb")!,
      balanceMinor: 10750000
    });
    store.transactions.set("user_minh::prov_android_2", {
      id: "prov_android_2",
      ownerId: "user_minh",
      walletId: "wallet_vcb",
      sourceProvider: "android_device",
      sourceKind: "androidNotification",
      kind: "income",
      direction: "credit",
      amountMinor: 300000,
      currencyCode: "VND",
      merchant: "VCB: LAN CHUYEN TIEN",
      description: "VCB: LAN CHUYEN TIEN",
      categoryName: "Thu nhập khác",
      occurredAtMs: occMsB,
      receivedAtMs: occMsB,
      monthKey: "2026-11",
      verification: "userConfirmed",
      verificationStatus: "USER_CONFIRMED",
      reconciliationStatus: "unreconciled_provisional",
      sourceEventKey: "android_ev_2",
      crossSourceFingerprint: "fp_2",
      softWindowFingerprint: softFpB,
      balanceAfterMinor: 10750000,
      balanceType: "estimatedWalletBalance",
      ledgerApplied: true, // ALREADY APPLIED!
      isVehicleMaintenanceHint: false,
      isRecurringCandidate: false,
      createdAtMs: occMsB,
      updatedAtMs: occMsB
    });

    const reqB = buildSignedWebhookRequest(
      {
        id: 94002,
        gateway: "Vietcombank",
        transactionDate: "2026-11-23 09:32:10",
        accountNumber: "1017588888",
        subAccount: "",
        code: null,
        content: "LAN CHUYEN TIEN",
        transferType: "in",
        description: "LAN CHUYEN TIEN",
        transferAmount: 300000,
        accumulated: 0,
        referenceCode: "FT300B"
      },
      baseNowMs + 120000
    );
    const httpB = await coordinator.handleSePayWebhookHttp(reqB);
    const workB = await coordinator.processInboxEvent(httpB.providerEventKey!, baseNowMs + 120000);
    assert.equal(workB.transactionId, "prov_android_2");
    // Balance MUST stay 10,750,000 — NOT 11,050,000!
    assert.equal(store.wallets.get("user_minh::wallet_vcb")?.balanceMinor, 10750000);
  });

  it("T06 — Two separate same-amount transfers within 2 minutes with distinct referenceCode are NOT merged", async () => {
    const { store, coordinator } = await createHarness();
    const req1 = buildSignedWebhookRequest(
      {
        id: 95001,
        gateway: "Vietcombank",
        transactionDate: "2026-11-23 09:30:00",
        accountNumber: "1017588888",
        subAccount: "",
        code: null,
        content: "Khach A chuyen 100k",
        transferType: "in",
        description: "Khach A",
        transferAmount: 100000,
        accumulated: 0,
        referenceCode: "FT_DISTINCT_01"
      },
      baseNowMs
    );
    const req2 = buildSignedWebhookRequest(
      {
        id: 95002,
        gateway: "Vietcombank",
        transactionDate: "2026-11-23 09:31:30",
        accountNumber: "1017588888",
        subAccount: "",
        code: null,
        content: "Khach B chuyen 100k",
        transferType: "in",
        description: "Khach B",
        transferAmount: 100000,
        accumulated: 0,
        referenceCode: "FT_DISTINCT_02"
      },
      baseNowMs + 90000
    );

    const h1 = await coordinator.handleSePayWebhookHttp(req1);
    const h2 = await coordinator.handleSePayWebhookHttp(req2);
    await coordinator.processInboxEvent(h1.providerEventKey!, baseNowMs);
    await coordinator.processInboxEvent(h2.providerEventKey!, baseNowMs + 90000);

    assert.equal(store.transactions.size, 2);
    assert.equal(store.wallets.get("user_minh::wallet_vcb")?.balanceMinor, 10200000);
  });

  it("T07, T08, T09 & T19 — Rejects invalid HMAC, expired replay timestamp, OTP payload, and ignores unlinked/injected userId", async () => {
    const { store, coordinator } = await createHarness();

    // T07: Tampered HMAC signature
    const badSigReq = buildSignedWebhookRequest(
      {
        id: 96001,
        gateway: "Vietcombank",
        transactionDate: "2026-11-23 09:30:00",
        accountNumber: "1017588888",
        transferType: "in",
        transferAmount: 500000
      },
      baseNowMs,
      "wrong_attacker_secret_key_00000000"
    );
    const r7 = await coordinator.handleSePayWebhookHttp(badSigReq);
    assert.equal(r7.statusCode, 401);

    // T08: Replay attack (timestamp 600s old > 300s limit)
    const replayReq = buildSignedWebhookRequest(
      {
        id: 96002,
        gateway: "Vietcombank",
        transactionDate: "2026-11-23 09:30:00",
        accountNumber: "1017588888",
        transferType: "in",
        transferAmount: 500000
      },
      baseNowMs,
      TEST_SECRET,
      Math.floor(baseNowMs / 1000) - 600
    );
    const r8 = await coordinator.handleSePayWebhookHttp(replayReq);
    assert.equal(r8.statusCode, 401);
    assert.equal(r8.body.error, "REPLAY_EXPIRED");

    // T19: OTP / security code in content is blocked at validation gate
    const otpReq = buildSignedWebhookRequest(
      {
        id: 96003,
        gateway: "Vietcombank",
        transactionDate: "2026-11-23 09:30:00",
        accountNumber: "1017588888",
        content: "Ma xac thuc Smart OTP cua quy khach la 482910",
        transferType: "in",
        transferAmount: 500000
      },
      baseNowMs
    );
    const r19 = await coordinator.handleSePayWebhookHttp(otpReq);
    assert.equal(r19.statusCode, 400);
    assert.equal(r19.body.error, "BLOCKED_OTP_SECRET");

    // T09: Unlinked bank account with attacker-injected `userId: "user_minh"` MUST NOT credit user_minh!
    const unlinkedReq = buildSignedWebhookRequest(
      {
        id: 96004,
        userId: "user_minh", // Untrusted external field!
        gateway: "Vietcombank",
        transactionDate: "2026-11-23 09:30:00",
        accountNumber: "9999999999", // Not linked!
        content: "Spoof attempt",
        transferType: "in",
        transferAmount: 9000000
      },
      baseNowMs
    );
    const r9 = await coordinator.handleSePayWebhookHttp(unlinkedReq);
    assert.equal(r9.statusCode, 200);
    const w9 = await coordinator.processInboxEvent(r9.providerEventKey!, baseNowMs);
    assert.equal(w9.state, "FAILED_PERMANENT");
    assert.equal(store.transactions.size, 0);
    assert.equal(store.wallets.get("user_minh::wallet_vcb")?.balanceMinor, 10000000);
  });

  it("T14, T15, T21, T22, T23 & Durable Failure — FCM error preserves ledger, accumulated=0 safe, capability & ownership enforced", async () => {
    const { store, fcm, coordinator } = await createHarness();

    // Durable failure returns HTTP 503 (NEVER 200) so SePay retries!
    store.simulateInboxWriteFailure = true;
    const reqFail = buildSignedWebhookRequest(
      {
        id: 97001,
        gateway: "Vietcombank",
        transactionDate: "2026-11-23 09:30:00",
        accountNumber: "1017588888",
        content: "Chuyen khoan",
        transferType: "in",
        transferAmount: 250000,
        accumulated: 0
      },
      baseNowMs
    );
    const r503 = await coordinator.handleSePayWebhookHttp(reqFail);
    assert.equal(r503.statusCode, 503);
    store.simulateInboxWriteFailure = false;

    // T14 & T15: FCM transport fails AND accumulated = 0 -> transaction saved, wallet becomes 10,250,000 (NOT 0!)
    fcm.shouldFail = true;
    fcm.invalidTokensToReport = ["fcm_tok_pixel9_valid"];
    const rOk = await coordinator.handleSePayWebhookHttp(reqFail);
    assert.equal(rOk.statusCode, 200);
    const wOk = await coordinator.processInboxEvent(rOk.providerEventKey!, baseNowMs);
    assert.equal(wOk.state, "PROCESSED");
    const outFail = await coordinator.dispatchNotificationOutbox(wOk.notificationId!, baseNowMs);
    assert.equal(outFail?.state, "FAILED_RETRYABLE");
    assert.equal(store.transactions.size, 1); // Transaction NOT rolled back!
    assert.equal(store.wallets.get("user_minh::wallet_vcb")?.balanceMinor, 10250000); // NOT 0!
    // Invalid token was automatically deactivated
    assert.equal(store.userDevices.get("user_minh")?.[0].pushEnabled, false);

    // T21: Reverse sync of same SePay ID 97001 is ignored as DUPLICATE
    const rDup = await coordinator.processInboxEvent(rOk.providerEventKey!, baseNowMs + 5000);
    assert.equal(rDup.state, "DUPLICATE");
    assert.equal(store.transactions.size, 1);

    // T22: Vietcombank money-out (`out`) via SePay webhook is rejected because VCB only supports webhook credit
    assert.equal(resolveBankCapability("Vietcombank")?.supportsWebhookDebit, false);
    const vcbOutReq = buildSignedWebhookRequest(
      {
        id: 97002,
        gateway: "Vietcombank",
        transactionDate: "2026-11-23 09:31:00",
        accountNumber: "1017588888",
        content: "Chuyen di",
        transferType: "out",
        transferAmount: 100000,
        accumulated: 10150000
      },
      baseNowMs
    );
    const hVcbOut = await coordinator.handleSePayWebhookHttp(vcbOutReq);
    const wVcbOut = await coordinator.processInboxEvent(hVcbOut.providerEventKey!, baseNowMs);
    assert.equal(wVcbOut.state, "FAILED_PERMANENT");

    // T23: Manual input without provider proof fails; cross-user claim of user_minh's VCB account fails!
    const unverifiedAttempt = await coordinator.verifyAndConnectBankAccount({
      authenticatedUserId: "user_attacker",
      bankCode: "VCB",
      accountNumber: "8888777766",
      linkedWalletId: "w_att",
      providerAccountProof: { verifiedByProviderApi: false }
    });
    assert.equal(unverifiedAttempt.ok, false);
    assert.equal(unverifiedAttempt.errorCode, "OWNERSHIP_PROOF_REQUIRED");

    const hijackAttempt = await coordinator.verifyAndConnectBankAccount({
      authenticatedUserId: "user_attacker",
      bankCode: "VCB",
      accountNumber: "1017588888", // Already verified by user_minh!
      linkedWalletId: "w_att",
      providerAccountProof: { verifiedByProviderApi: true }
    });
    assert.equal(hijackAttempt.ok, false);
    assert.equal(hijackAttempt.errorCode, "ACCOUNT_ALREADY_LINKED_OTHER_USER");
  });
});
