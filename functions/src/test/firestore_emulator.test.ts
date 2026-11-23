import * as assert from "node:assert/strict";
import * as net from "node:net";
import { describe, it } from "node:test";
import * as admin from "firebase-admin";
import { FcmMulticastResult, FcmPushSender, RealtimeBankingCoordinator } from "../bankingEngine";
import { FirestoreAdminBankingStore } from "../firestoreStore";
import { computeHmacSha256Hex } from "../security";

function isPortOpen(host: string, port: number): Promise<boolean> {
  return new Promise((resolve) => {
    const socket = new net.Socket();
    socket.setTimeout(800);
    socket.once("connect", () => {
      socket.destroy();
      resolve(true);
    });
    socket.once("timeout", () => {
      socket.destroy();
      resolve(false);
    });
    socket.once("error", () => {
      socket.destroy();
      resolve(false);
    });
    socket.connect(port, host);
  });
}

class EmulatorMockFcm implements FcmPushSender {
  public sentCount = 0;
  async sendToUserDevices(params: {
    tokens: readonly string[];
    notificationId: string;
    title: string;
    body: string;
    lockscreenPrivate: boolean;
    soundEnabled: boolean;
    data: Record<string, string>;
  }): Promise<FcmMulticastResult> {
    this.sentCount += params.tokens.length;
    return { successCount: params.tokens.length, failureCount: 0, invalidTokens: [] };
  }
}

describe("Live Cloud Firestore Emulator Integration — FirestoreAdminBankingStore", () => {
  it("Executes atomic SePay Webhook -> Durable Inbox -> Canonical Ledger -> Outbox on real Firestore Emulator", async (t) => {
    const reachable = await isPortOpen("127.0.0.1", 8188);
    if (!reachable) {
      t.skip("Firestore Emulator on 127.0.0.1:8188 is not running");
      return;
    }

    process.env.FIRESTORE_EMULATOR_HOST = "127.0.0.1:8188";
    const app = admin.initializeApp({ projectId: "demo-life-os" }, `emu_bank_test_${Date.now()}`);
    try {
      const db = app.firestore();
      const store = new FirestoreAdminBankingStore(db);
      const fcm = new EmulatorMockFcm();
      const secret = "emulator_hmac_secret_2026_lifeos_verified";
      const coordinator = new RealtimeBankingCoordinator(store, fcm, () => secret);
      const uid = `u_emu_${Date.now()}`;
      const testAccNum = `09${Date.now().toString().slice(-8)}`;
      const expectedMasked = `•••• ${testAccNum.slice(-4)}`;
      const nowMs = Date.now();

      await db.collection("users").doc(uid).collection("wallets").doc("w_emu_mb").set({
        id: "w_emu_mb",
        ownerId: uid,
        name: "MB Bank Lương",
        type: "bank",
        balanceMinor: 2000000,
        isEstimatedBalance: true
      });
      await db.collection("users").doc(uid).collection("devices").doc("dev_android_1").set({
        deviceId: "dev_android_1",
        ownerId: uid,
        fcmToken: "emu_token_12345",
        platform: "android",
        pushEnabled: true
      });

      const linkRes = await coordinator.verifyAndConnectBankAccount({
        authenticatedUserId: uid,
        bankCode: "MB",
        accountNumber: testAccNum,
        linkedWalletId: "w_emu_mb",
        providerAccountProof: { verifiedByProviderApi: true, providerConnectionId: "sp_emu_mb" },
        nowMs
      });
      assert.equal(linkRes.ok, true);

      // Verify sanitized user bank_connection doc does NOT expose raw accountNumber!
      const userConnSnap = await db
        .collection("users")
        .doc(uid)
        .collection("bank_connections")
        .doc(linkRes.connection!.id)
        .get();
      assert.equal(userConnSnap.exists, true);
      assert.equal(userConnSnap.data()?.accountMasked, expectedMasked);
      assert.equal("accountNumber" in (userConnSnap.data() ?? {}), false);

      const rawBody = Buffer.from(
        JSON.stringify({
          id: 880011,
          gateway: "MBBank",
          transactionDate: "2026-11-23 10:15:00",
          accountNumber: testAccNum,
          subAccount: "",
          code: null,
          content: "TRAN VAN B chuyen tien",
          transferType: "in",
          description: "TRAN VAN B chuyen tien",
          transferAmount: 750000,
          accumulated: 2750000,
          referenceCode: "FT_EMU_880011"
        }),
        "utf8"
      );
      const tsSec = Math.floor(nowMs / 1000);
      const sig = computeHmacSha256Hex(secret, `${tsSec}.${rawBody.toString("utf8")}`);

      const httpRes = await coordinator.handleSePayWebhookHttp({
        method: "POST",
        rawBody,
        nowMs,
        headers: {
          "x-sepay-signature": `sha256=${sig}`,
          "x-sepay-timestamp": String(tsSec)
        }
      });
      assert.equal(httpRes.statusCode, 200);

      // Fire 2 concurrent workers against the real Firestore Emulator to test ACID transaction isolation!
      const [w1, w2] = await Promise.all([
        coordinator.processInboxEvent(httpRes.providerEventKey!, nowMs),
        coordinator.processInboxEvent(httpRes.providerEventKey!, nowMs)
      ]);
      const states = [w1.state, w2.state].sort();
      assert.deepEqual(states, ["DUPLICATE", "PROCESSED"]);

      const notifId = w1.notificationId ?? w2.notificationId;
      assert.ok(notifId);
      const outRes = await coordinator.dispatchNotificationOutbox(notifId!, nowMs);
      assert.equal(outRes?.state, "DELIVERED");
      assert.equal(fcm.sentCount, 1);

      const walletSnap = await db.collection("users").doc(uid).collection("wallets").doc("w_emu_mb").get();
      assert.equal(walletSnap.data()?.balanceMinor, 2750000);
      assert.equal(walletSnap.data()?.isEstimatedBalance, false);

      const notifSnap = await db.collection("users").doc(uid).collection("financial_notifications").doc(notifId!).get();
      assert.equal(notifSnap.exists, true);
      assert.equal(notifSnap.data()?.amountMinor, 750000);
    } finally {
      await app.delete();
    }
  });
});
