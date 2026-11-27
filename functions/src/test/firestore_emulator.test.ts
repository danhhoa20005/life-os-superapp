import * as assert from "node:assert/strict";
import * as net from "node:net";
import { describe, it } from "node:test";
import * as admin from "firebase-admin";
import { FcmMulticastResult, FcmPushSender, RealtimeBankingCoordinator } from "../bankingEngine";
import { FirestoreAdminBankingStore } from "../firestoreStore";
import { deleteServerOnlyUserAccountData } from "../index";
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

function resolveEmulatorEndpoint(): { host: string; port: number; raw: string } {
  const raw = process.env.FIRESTORE_EMULATOR_HOST || "127.0.0.1:8188";
  const [host, portStr] = raw.split(":");
  const port = Number.parseInt(portStr || "8188", 10) || 8188;
  return { host: host || "127.0.0.1", port, raw: `${host || "127.0.0.1"}:${port}` };
}

describe("Live Cloud Firestore Emulator Integration — FirestoreAdminBankingStore", () => {
  it("Executes atomic SePay Webhook -> Durable Inbox -> Canonical Ledger -> Outbox on real Firestore Emulator", async (t) => {
    const emu = resolveEmulatorEndpoint();
    const reachable = await isPortOpen(emu.host, emu.port);
    if (!reachable) {
      t.skip(`Firestore Emulator on ${emu.raw} is not running`);
      return;
    }

    process.env.FIRESTORE_EMULATOR_HOST = emu.raw;
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
        sepayAccounts: [
          {
            id: "emu_mb_101",
            account_number: testAccNum,
            bank_short_name: "MBBank",
            active: "1"
          }
        ],
        nowMs
      });
      assert.equal(linkRes.ok, true);
      assert.equal(linkRes.connection?.providerConnectionId, "sepay_ba_emu_mb_101");

      // Concurrent cross-user attempt for the same SePay account MUST fail in real Firestore transaction!
      const raceLoser = await coordinator.verifyAndConnectBankAccount({
        authenticatedUserId: `${uid}_attacker`,
        bankCode: "MB",
        accountNumber: testAccNum,
        linkedWalletId: "w_emu_mb",
        sepayAccounts: [
          {
            id: "emu_mb_101",
            account_number: testAccNum,
            bank_short_name: "MBBank",
            active: "1"
          }
        ],
        nowMs
      });
      // Since attacker has no wallet w_emu_mb, test also with attacker wallet seeded:
      assert.equal(raceLoser.ok, false);

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
      assert.ok(walletSnap.data()?.lastAuditId);

      // Strict subAccount isolation check (AUD-012)
      const unmatched = await store.findActiveConnectionForAccount({
        bankCode: "MB",
        gateway: "MBBank",
        accountNumber: testAccNum,
        subAccount: "SUB_OTHER"
      });
      assert.equal(unmatched, null);
      const matched = await store.findActiveConnectionForAccount({
        bankCode: "MB",
        gateway: "MBBank",
        accountNumber: testAccNum,
        subAccount: ""
      });
      assert.ok(matched);

      const notifSnap = await db.collection("users").doc(uid).collection("financial_notifications").doc(notifId!).get();
      assert.equal(notifSnap.exists, true);
      assert.equal(notifSnap.data()?.amountMinor, 750000);

      // Verify deleteServerOnlyUserAccountData (AUD-007) deletes server-only docs for uid without touching other users
      await db.collection("bank_reconciliation_jobs").doc(`job_${uid}`).set({ ownerId: uid, status: "done" });
      await db.collection("family_invite_rate_limits").doc(uid).set({ failedCount: 3, windowStartMs: nowMs });
      await db.collection("server_bank_connections").doc("conn_other_user").set({
        id: "conn_other_user",
        ownerId: "u_other_preserve",
        status: "connected"
      });
      const delRes = await deleteServerOnlyUserAccountData(db, uid);
      assert.equal(delRes.ok, true);
      assert.ok(delRes.deletedCount >= 5);
      assert.equal((await db.collection("server_bank_connections").doc(linkRes.connection!.id).get()).exists, false);
      assert.equal((await db.collection("sepay_webhook_inbox").doc(httpRes.providerEventKey!).get()).exists, false);
      assert.equal((await db.collection("notification_outbox").doc(notifId!).get()).exists, false);
      assert.equal((await db.collection("bank_reconciliation_jobs").doc(`job_${uid}`).get()).exists, false);
      assert.equal((await db.collection("family_invite_rate_limits").doc(uid).get()).exists, false);
      assert.equal((await db.collection("server_bank_connections").doc("conn_other_user").get()).exists, true);
      const claimsAfterDelete = await db.collection("server_bank_account_claims").where("ownerId", "==", uid).get();
      assert.equal(claimsAfterDelete.empty, true);
    } finally {
      await app.delete();
    }
  });

  it("Finding 3 — Real Firestore transaction allows strictly one winner in concurrent bank account link race", async (t) => {
    const emu = resolveEmulatorEndpoint();
    const reachable = await isPortOpen(emu.host, emu.port);
    if (!reachable) {
      t.skip(`Firestore Emulator on ${emu.raw} is not running`);
      return;
    }

    process.env.FIRESTORE_EMULATOR_HOST = emu.raw;
    const app = admin.initializeApp({ projectId: "demo-life-os" }, `emu_f3_race_${Date.now()}`);
    try {
      const db = app.firestore();
      const store = new FirestoreAdminBankingStore(db);
      const coordinator = new RealtimeBankingCoordinator(store, new EmulatorMockFcm(), () => "secret");
      const nowMs = Date.now();
      const uA = `u_a_${nowMs}`;
      const uB = `u_b_${nowMs}`;
      const sharedAcc = `088${nowMs.toString().slice(-7)}`;
      const sepayList = [
        {
          id: `sp_${nowMs}`,
          account_number: sharedAcc,
          bank_short_name: "VCB",
          sub_account: "VA01",
          active: true
        },
        {
          id: `sp_other_${nowMs}`,
          account_number: sharedAcc,
          bank_short_name: "MB",
          sub_account: "VA01",
          active: true
        }
      ];

      await Promise.all([
        db.collection("users").doc(uA).collection("wallets").doc("w_a").set({
          id: "w_a",
          ownerId: uA,
          name: "VCB A",
          type: "bank",
          balanceMinor: 0,
          isEstimatedBalance: true
        }),
        db.collection("users").doc(uB).collection("wallets").doc("w_b").set({
          id: "w_b",
          ownerId: uB,
          name: "VCB B",
          type: "bank",
          balanceMinor: 0,
          isEstimatedBalance: true
        })
      ]);

      const [resA, resB] = await Promise.all([
        coordinator.verifyAndConnectBankAccount({
          authenticatedUserId: uA,
          bankCode: "VCB",
          accountNumber: sharedAcc,
          subAccount: "VA01",
          linkedWalletId: "w_a",
          sepayAccounts: sepayList,
          nowMs
        }),
        coordinator.verifyAndConnectBankAccount({
          authenticatedUserId: uB,
          bankCode: "VCB",
          accountNumber: sharedAcc,
          subAccount: "VA01",
          linkedWalletId: "w_b",
          sepayAccounts: sepayList,
          nowMs
        })
      ]);

      const winners = [resA, resB].filter((r) => r.ok);
      const losers = [resA, resB].filter((r) => !r.ok);
      assert.equal(winners.length, 1);
      assert.equal(losers.length, 1);
      assert.equal(losers[0].errorCode, "ACCOUNT_ALREADY_LINKED_OTHER_USER");
      assert.equal(winners[0].connection?.bankCode, "VCB");
    } finally {
      await app.delete();
    }
  });

  it("H2 & H3 — Real Firestore atomic revocation increments grantVersion, updates user mirror & blocks stale inbox/outbox cross-user leak", async (t) => {
    const emu = resolveEmulatorEndpoint();
    const reachable = await isPortOpen(emu.host, emu.port);
    if (!reachable) {
      t.skip(`Firestore Emulator on ${emu.raw} is not running`);
      return;
    }

    process.env.FIRESTORE_EMULATOR_HOST = emu.raw;
    const app = admin.initializeApp({ projectId: "demo-life-os" }, `emu_h2_h3_${Date.now()}`);
    try {
      const db = app.firestore();
      const store = new FirestoreAdminBankingStore(db);
      const fcm = new EmulatorMockFcm();
      const secret = "emulator_hmac_secret_2026_h2_h3_verified";
      const coordinator = new RealtimeBankingCoordinator(store, fcm, () => secret);
      const nowMs = Date.now();
      const uA = `u_h2_a_${nowMs}`;
      const uB = `u_h2_b_${nowMs}`;
      const accNum = `077${nowMs.toString().slice(-7)}`;

      await Promise.all([
        db.collection("users").doc(uA).collection("wallets").doc("w_a").set({
          id: "w_a",
          ownerId: uA,
          name: "VCB A",
          type: "bank",
          balanceMinor: 1000000,
          isEstimatedBalance: true
        }),
        db.collection("users").doc(uB).collection("wallets").doc("w_b").set({
          id: "w_b",
          ownerId: uB,
          name: "VCB B",
          type: "bank",
          balanceMinor: 5000000,
          isEstimatedBalance: true
        })
      ]);

      const linkA = await coordinator.verifyAndConnectBankAccount({
        authenticatedUserId: uA,
        bankCode: "VCB",
        accountNumber: accNum,
        linkedWalletId: "w_a",
        sepayAccounts: [{ id: `ba_${nowMs}`, account_number: accNum, bank_short_name: "VCB", active: "1" }],
        nowMs
      });
      assert.equal(linkA.ok, true);
      assert.equal(linkA.connection?.grantVersion, 1);

      const rawBody = Buffer.from(
        JSON.stringify({
          id: 999123,
          gateway: "Vietcombank",
          transactionDate: "2026-11-23 11:00:00",
          accountNumber: accNum,
          subAccount: "",
          content: "Pending webhook before revoke",
          transferType: "in",
          transferAmount: 400000,
          accumulated: 1400000,
          referenceCode: "FT_EMU_H3"
        }),
        "utf8"
      );
      const tsSec = Math.floor(nowMs / 1000);
      const sig = computeHmacSha256Hex(secret, `${tsSec}.${rawBody.toString("utf8")}`);
      const httpRes = await coordinator.handleSePayWebhookHttp({
        method: "POST",
        rawBody,
        nowMs,
        headers: { "x-sepay-signature": `sha256=${sig}`, "x-sepay-timestamp": String(tsSec) }
      });
      assert.equal(httpRes.statusCode, 200);

      // Revoke User A connection atomically and link account to User B BEFORE processing inbox
      await coordinator.revokeConnection(uA, linkA.connection!.id, nowMs + 1000);
      const serverConnSnap = await db.collection("server_bank_connections").doc(linkA.connection!.id).get();
      assert.equal(serverConnSnap.data()?.status, "revoked");
      assert.equal(serverConnSnap.data()?.consentStatus, "revoked");
      assert.equal(serverConnSnap.data()?.consentEnabled, false);
      assert.equal(serverConnSnap.data()?.grantVersion, 2);

      const userMirrorSnap = await db.collection("users").doc(uA).collection("bank_connections").doc(linkA.connection!.id).get();
      assert.equal(userMirrorSnap.data()?.status, "disconnected");
      assert.equal(userMirrorSnap.data()?.consentStatus, "revoked");
      assert.ok(userMirrorSnap.data()?.revokedAt);

      const linkB = await coordinator.verifyAndConnectBankAccount({
        authenticatedUserId: uB,
        bankCode: "VCB",
        accountNumber: accNum,
        linkedWalletId: "w_b",
        sepayAccounts: [{ id: `ba_${nowMs}`, account_number: accNum, bank_short_name: "VCB", active: "1" }],
        nowMs: nowMs + 2000
      });
      assert.equal(linkB.ok, true);

      // Process User A's pending inbox event -> MUST skip without writing to User B!
      const procRes = await coordinator.processInboxEvent(httpRes.providerEventKey!, nowMs + 3000);
      assert.equal(procRes.state, "skipped_revoked_or_reassigned");
      const inboxSnap = await db.collection("sepay_webhook_inbox").doc(httpRes.providerEventKey!).get();
      assert.equal(inboxSnap.data()?.status, "skipped_revoked_or_reassigned");
      assert.equal((await db.collection("users").doc(uB).collection("wallets").doc("w_b").get()).data()?.balanceMinor, 5000000);
      assert.equal((await db.collection("users").doc(uB).collection("transactions").get()).empty, true);
    } finally {
      await app.delete();
    }
  });

  it("H5 — Authoritative resumable deleteServerOnlyUserAccountData enforces multi-member family owner guard, deletes nested subcollections recursively & completes job", async (t) => {
    const emu = resolveEmulatorEndpoint();
    const reachable = await isPortOpen(emu.host, emu.port);
    if (!reachable) {
      t.skip(`Firestore Emulator on ${emu.raw} is not running`);
      return;
    }

    process.env.FIRESTORE_EMULATOR_HOST = emu.raw;
    const app = admin.initializeApp({ projectId: "demo-life-os" }, `emu_h5_del_${Date.now()}`);
    try {
      const db = app.firestore();
      const nowMs = Date.now();
      const uid = `u_h5_${nowMs}`;
      const memberUid = `u_h5_member_${nowMs}`;
      const otherOwnerUid = `u_h5_other_owner_${nowMs}`;

      // Seed nested personal subcollections including daily_preferences, legacy medical paths, personal_funds/*/fund_audits, vehicles/*/fuel_logs
      await db.collection("users").doc(uid).set({ id: uid, email: "h5@lifeos.vn", deletionInProgress: true });
      await db.collection("users").doc(uid).collection("daily_preferences").doc("hydration_reminder").set({ targetWaterMl: 2000 });
      await db.collection("users").doc(uid).collection("medications").doc("m1").set({ name: "Legacy Med" });
      await db.collection("users").doc(uid).collection("health_logs").doc("h1").set({ value: 120 });
      await db.collection("users").doc(uid).collection("medical_profiles").doc("mp1").set({ bloodType: "O" });
      await db.collection("users").doc(uid).collection("personal_funds").doc("pf1").set({ id: "pf1", balanceMinor: 500000 });
      await db.collection("users").doc(uid).collection("personal_funds").doc("pf1").collection("fund_audits").doc("fa1").set({ id: "fa1", deltaMinor: 500000 });
      await db.collection("users").doc(uid).collection("vehicles").doc("v1").set({ id: "v1", name: "Xe máy" });
      await db.collection("users").doc(uid).collection("vehicles").doc("v1").collection("fuel_logs").doc("fl1").set({ id: "fl1", costMinor: 70000 });

      // Seed server-only collections
      await db.collection("server_bank_connections").doc(`conn_${uid}`).set({ id: `conn_${uid}`, ownerId: uid, status: "connected" });
      await db.collection("family_invite_rate_limits").doc(uid).set({ failedCount: 2, windowStartMs: nowMs });

      // 1. Multi-member family owned by uid MUST block deletion with failed-precondition!
      const famOwnedMulti = `fam_owned_multi_${nowMs}`;
      await db.collection("families").doc(famOwnedMulti).set({
        id: famOwnedMulti,
        createdBy: uid,
        memberIds: [uid, memberUid],
        memberRoles: { [uid]: "owner", [memberUid]: "member" },
        memberNames: { [uid]: "Owner", [memberUid]: "Member" }
      });

      await assert.rejects(
        () => deleteServerOnlyUserAccountData(db, uid),
        (err: unknown) => (err as { code?: string })?.code === "failed-precondition"
      );

      // Update that family so uid transferred ownership (uid is now plain member), plus add solo family & availability slots
      await db.collection("families").doc(famOwnedMulti).update({
        memberRoles: { [uid]: "member", [memberUid]: "owner" }
      });
      await db.collection("families").doc(famOwnedMulti).collection("availability").doc(`av_${uid}`).set({ ownerId: uid });

      const famSolo = `fam_solo_${nowMs}`;
      await db.collection("families").doc(famSolo).set({
        id: famSolo,
        createdBy: uid,
        memberIds: [uid],
        memberRoles: { [uid]: "owner" }
      });
      await db.collection("families").doc(famSolo).collection("availability").doc(`av_solo_${uid}`).set({ ownerId: uid });
      await db.collection("family_invites").doc(`FAM-SOLO-${nowMs}`).set({
        inviteCode: `FAM-SOLO-${nowMs}`,
        familyId: famSolo,
        createdBy: uid
      });

      // Seed an unrelated user's data to confirm zero collateral damage
      await db.collection("users").doc(otherOwnerUid).set({ id: otherOwnerUid });

      // 2. Simulate interrupted job resuming mid-flow (`status: 'in_progress'`)
      await db.collection("account_deletion_jobs").doc(uid).set({
        uid,
        status: "in_progress",
        steps: {
          families: "pending",
          serverCollections: "pending",
          userSubtree: "pending",
          verification: "pending"
        }
      });

      const res = await deleteServerOnlyUserAccountData(db, uid);
      assert.equal(res.ok, true);
      assert.equal(res.verifiedClean, true);
      assert.ok(res.deletedCount >= 4);

      // Verify user root + ALL nested subcollections deleted
      assert.equal((await db.collection("users").doc(uid).get()).exists, false);
      assert.equal((await db.collection("users").doc(uid).listCollections()).length, 0);
      assert.equal((await db.collection("users").doc(uid).collection("personal_funds").doc("pf1").collection("fund_audits").doc("fa1").get()).exists, false);
      assert.equal((await db.collection("users").doc(uid).collection("daily_preferences").doc("hydration_reminder").get()).exists, false);
      assert.equal((await db.collection("users").doc(uid).collection("medications").doc("m1").get()).exists, false);

      // Verify solo family & its invite deleted; multi-member family preserved with uid cleanly removed!
      assert.equal((await db.collection("families").doc(famSolo).get()).exists, false);
      assert.equal((await db.collection("family_invites").doc(`FAM-SOLO-${nowMs}`).get()).exists, false);
      const multiFamSnap = await db.collection("families").doc(famOwnedMulti).get();
      assert.equal(multiFamSnap.exists, true);
      assert.deepEqual(multiFamSnap.data()?.memberIds, [memberUid]);
      assert.equal((await db.collection("families").doc(famOwnedMulti).collection("availability").doc(`av_${uid}`).get()).exists, false);

      // Verify job marker marked completed & unrelated user untouched
      const jobSnap = await db.collection("account_deletion_jobs").doc(uid).get();
      assert.equal(jobSnap.data()?.status, "completed");
      assert.equal(jobSnap.data()?.verifiedClean, true);
      assert.equal((await db.collection("users").doc(otherOwnerUid).get()).exists, true);

      // Verify idempotent re-run succeeds cleanly
      const rerun = await deleteServerOnlyUserAccountData(db, uid);
      assert.equal(rerun.ok, true);
      assert.equal(rerun.verifiedClean, true);
    } finally {
      await app.delete();
    }
  });
});
