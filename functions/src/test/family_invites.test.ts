import * as assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  FamilyInviteCoordinator,
  FamilyInviteError,
  hashRecipientContact,
  InMemoryFamilyInviteStore,
  normalizeRecipientContact,
  sanitizePublicInviteeName
} from "../familyInvites";

describe("Family Invites Cloud Functions — FIX-002 & FIX-003 (3 Modes, Race Condition, Rate Limit & PII Zeroing)", () => {
  function seedStore(nowMs: number) {
    const store = new InMemoryFamilyInviteStore();
    store.families.set("fam_1", {
      id: "fam_1",
      name: "Tổ ấm Minh & Lan",
      spaceType: "family",
      createdBy: "owner_1",
      memberIds: ["owner_1"],
      memberRoles: { owner_1: "owner" },
      memberNames: { owner_1: "Minh" },
      pendingInvites: {}
    });
    return { store, coordinator: new FamilyInviteCoordinator(store, () => nowMs) };
  }

  it("1. Creates targeted invite WITHOUT leaking raw contact PII on public family_invites and normalizes VN phones/emails", async () => {
    const nowMs = Date.parse("2026-11-25T10:00:00Z");
    const { store, coordinator } = seedStore(nowMs);

    assert.equal(normalizeRecipientContact("  Lan@LifeOS.vn "), "lan@lifeos.vn");
    assert.equal(normalizeRecipientContact("+84 909 123 456"), "0909123456");
    assert.equal(normalizeRecipientContact("0909-123.456"), "0909123456");
    assert.equal(
      hashRecipientContact("+84 909 123 456"),
      hashRecipientContact("0909 123 456")
    );
    assert.equal(sanitizePublicInviteeName("lan@lifeos.vn"), undefined);
    assert.equal(sanitizePublicInviteeName("0909 123 456"), undefined);
    assert.equal(sanitizePublicInviteeName("Trần Lan"), "Trần Lan");

    const created = await coordinator.createFamilyInvite({
      actorUserId: "owner_1",
      familyId: "fam_1",
      inviteKind: "targeted",
      inviteeName: "Trần Lan",
      inviteeContact: "+84 909 123 456"
    });

    assert.equal(created.inviteKind, "targeted");
    assert.equal(created.maxUses, 1);

    const publicDoc = store.invites.get(created.inviteCode)!;
    assert.equal("inviteeContact" in publicDoc, false);
    assert.equal(publicDoc.intendedRecipientHash, hashRecipientContact("0909123456"));
    assert.equal(publicDoc.status, "active");

    // Internal family.pendingInvites NEVER exposes raw contact PII — stores masked contact only
    const internalPending = store.families.get("fam_1")!.pendingInvites[created.inviteCode]!;
    assert.equal("inviteeContact" in internalPending, false);
    assert.equal(internalPending.inviteeContactMasked, "*******3456");

    // Preview returns minimal safe payload without intendedRecipientHash or family memberIds
    const preview = await coordinator.previewFamilyInvite({
      actorUserId: "uid_lan",
      inviteCode: `Mời bạn tham gia: ${created.inviteCode.toLowerCase()}`
    });
    assert.equal(preview.familyName, "Tổ ấm Minh & Lan");
    assert.equal(preview.isTargeted, true);
    assert.equal(preview.maxUses, 1);
    assert.equal(preview.usedCount, 0);
    assert.equal("intendedRecipientHash" in preview, false);

    // Wrong recipient rejected (PERMISSION_DENIED)
    await assert.rejects(
      () =>
        coordinator.joinFamilyByInvite({
          actorUserId: "uid_intruder",
          userName: "Kẻ lạ",
          inviteCode: created.inviteCode,
          authEmail: "intruder@lifeos.vn",
          authEmailVerified: true,
          authPhoneNumber: "0911111111"
        }),
      (err: unknown) => err instanceof FamilyInviteError && err.code === "PERMISSION_DENIED"
    );

    // Email-targeted invite MUST reject unverified email claims (`authEmailVerified !== true`)
    const emailInv = await coordinator.createFamilyInvite({
      actorUserId: "owner_1",
      familyId: "fam_1",
      inviteKind: "targeted",
      inviteeName: "Linh Email",
      inviteeContact: "linh@lifeos.vn"
    });
    const emailPending = store.families.get("fam_1")!.pendingInvites[emailInv.inviteCode]!;
    assert.equal("inviteeContact" in emailPending, false);
    assert.equal(emailPending.inviteeContactMasked, "li***@lifeos.vn");

    await assert.rejects(
      () =>
        coordinator.joinFamilyByInvite({
          actorUserId: "uid_unverified",
          userName: "Linh Fake",
          inviteCode: emailInv.inviteCode,
          authEmail: "linh@lifeos.vn",
          authEmailVerified: false
        }),
      (err: unknown) => err instanceof FamilyInviteError && err.code === "PERMISSION_DENIED"
    );
    await coordinator.joinFamilyByInvite({
      actorUserId: "uid_linh",
      userName: "Linh",
      inviteCode: emailInv.inviteCode,
      authEmail: "linh@lifeos.vn",
      authEmailVerified: true
    });
    assert.equal(store.families.get("fam_1")!.memberRoles.uid_linh, "member");

    // Banned user cannot redeem invite
    const openInv = await coordinator.createFamilyInvite({
      actorUserId: "owner_1",
      familyId: "fam_1",
      inviteKind: "reusableGroup",
      maxUses: 5
    });
    const famBeforeBan = store.families.get("fam_1")!;
    store.families.set("fam_1", {
      ...famBeforeBan,
      bannedUserIds: ["uid_banned"]
    });
    await assert.rejects(
      () =>
        coordinator.joinFamilyByInvite({
          actorUserId: "uid_banned",
          userName: "Banned",
          inviteCode: openInv.inviteCode
        }),
      (err: unknown) => err instanceof FamilyInviteError && err.code === "PERMISSION_DENIED"
    );

    // Right recipient with local phone format matches normalized hash & joins as 'member'
    const joined = await coordinator.joinFamilyByInvite({
      actorUserId: "uid_lan",
      userName: "Trần Lan",
      inviteCode: created.inviteCode,
      authPhoneNumber: "0909 123 456"
    });
    assert.equal(joined.role, "member");
    assert.equal(joined.remainingUses, 0);
    assert.equal(store.invites.get(created.inviteCode)!.status, "consumed");
    assert.equal(store.families.get("fam_1")!.memberRoles.uid_lan, "member");
  });

  it("2. Prevents concurrent race condition when 2 users join the same oneTime (maxUses=1) invite simultaneously", async () => {
    const nowMs = Date.parse("2026-11-25T10:00:00Z");
    const { store, coordinator } = seedStore(nowMs);

    const created = await coordinator.createFamilyInvite({
      actorUserId: "owner_1",
      familyId: "fam_1",
      inviteKind: "oneTime"
    });

    const results = await Promise.allSettled([
      coordinator.joinFamilyByInvite({
        actorUserId: "user_a",
        userName: "User A",
        inviteCode: created.inviteCode
      }),
      coordinator.joinFamilyByInvite({
        actorUserId: "user_b",
        userName: "User B",
        inviteCode: created.inviteCode
      })
    ]);

    const fulfilled = results.filter((r) => r.status === "fulfilled");
    const rejected = results.filter((r) => r.status === "rejected");
    assert.equal(fulfilled.length, 1);
    assert.equal(rejected.length, 1);
    assert.equal(store.invites.get(created.inviteCode)!.usedCount, 1);
    assert.equal(store.invites.get(created.inviteCode)!.status, "consumed");
    assert.equal(store.families.get("fam_1")!.memberIds.length, 2);
  });

  it("3. Supports reusableGroup invites up to maxUses, blocks expired/revoked codes, and enforces UID rate-limit", async () => {
    let clockMs = Date.parse("2026-11-25T10:00:00Z");
    const store = new InMemoryFamilyInviteStore();
    store.families.set("fam_1", {
      id: "fam_1",
      name: "Nhà Trọ A1",
      spaceType: "roommates",
      createdBy: "owner_1",
      memberIds: ["owner_1"],
      memberRoles: { owner_1: "owner" },
      memberNames: { owner_1: "Minh" },
      pendingInvites: {}
    });
    const coordinator = new FamilyInviteCoordinator(store, () => clockMs);

    // Non-manager cannot create invite
    await assert.rejects(
      () =>
        coordinator.createFamilyInvite({
          actorUserId: "outsider",
          familyId: "fam_1",
          inviteKind: "oneTime"
        }),
      (err: unknown) => err instanceof FamilyInviteError && err.code === "PERMISSION_DENIED"
    );

    const groupInv = await coordinator.createFamilyInvite({
      actorUserId: "owner_1",
      familyId: "fam_1",
      inviteKind: "reusableGroup",
      maxUses: 3,
      ttlDays: 2
    });
    assert.equal(groupInv.maxUses, 3);

    await coordinator.joinFamilyByInvite({
      actorUserId: "u_1",
      userName: "Bạn 1",
      inviteCode: groupInv.inviteCode
    });
    await coordinator.joinFamilyByInvite({
      actorUserId: "u_2",
      userName: "Bạn 2",
      inviteCode: groupInv.inviteCode
    });
    // Existing member idempotent re-join does NOT waste 3rd slot!
    const idem = await coordinator.joinFamilyByInvite({
      actorUserId: "u_2",
      userName: "Bạn 2",
      inviteCode: groupInv.inviteCode
    });
    assert.equal(idem.alreadyMember, true);
    assert.equal(store.invites.get(groupInv.inviteCode)!.usedCount, 2);

    await coordinator.joinFamilyByInvite({
      actorUserId: "u_3",
      userName: "Bạn 3",
      inviteCode: groupInv.inviteCode
    });
    assert.equal(store.invites.get(groupInv.inviteCode)!.status, "consumed");

    // 4th user is rejected
    await assert.rejects(
      () =>
        coordinator.joinFamilyByInvite({
          actorUserId: "u_4",
          userName: "Bạn 4",
          inviteCode: groupInv.inviteCode
        }),
      (err: unknown) => err instanceof FamilyInviteError && err.code === "FAILED_PRECONDITION"
    );

    // Revoke test
    const revInv = await coordinator.createFamilyInvite({
      actorUserId: "owner_1",
      familyId: "fam_1",
      inviteKind: "oneTime"
    });
    await coordinator.revokeFamilyInvite({
      actorUserId: "owner_1",
      familyId: "fam_1",
      inviteCode: revInv.inviteCode
    });
    assert.equal(store.invites.get(revInv.inviteCode)!.status, "revoked");
    await assert.rejects(
      () => coordinator.previewFamilyInvite({ actorUserId: "u_5", inviteCode: revInv.inviteCode }),
      (err: unknown) => err instanceof FamilyInviteError && err.code === "FAILED_PRECONDITION"
    );

    // Expiry test (advance server clock past ttlDays=1)
    const expInv = await coordinator.createFamilyInvite({
      actorUserId: "owner_1",
      familyId: "fam_1",
      inviteKind: "oneTime",
      ttlDays: 1
    });
    clockMs += 25 * 60 * 60 * 1000;
    await assert.rejects(
      () =>
        coordinator.joinFamilyByInvite({
          actorUserId: "u_late",
          userName: "Đến muộn",
          inviteCode: expInv.inviteCode
        }),
      (err: unknown) => err instanceof FamilyInviteError && err.code === "FAILED_PRECONDITION"
    );

    // Brute-force rate limit test (> 10 failed attempts within 60s -> RESOURCE_EXHAUSTED)
    for (let i = 0; i < 10; i++) {
      await assert.rejects(
        () => coordinator.previewFamilyInvite({ actorUserId: "brute_uid", inviteCode: `FAM-FAKE0${i}` }),
        (err: unknown) => err instanceof FamilyInviteError && err.code === "NOT_FOUND"
      );
    }
    await assert.rejects(
      () => coordinator.previewFamilyInvite({ actorUserId: "brute_uid", inviteCode: "FAM-FAKE99" }),
      (err: unknown) => err instanceof FamilyInviteError && err.code === "RESOURCE_EXHAUSTED"
    );
  });

  it("4. Finding 2 — Enforces inviteeUid, verified inviteeEmail, unverified email denial message & open invites", async () => {
    const nowMs = Date.parse("2026-11-25T10:00:00Z");
    const { store, coordinator } = seedStore(nowMs);

    // 4a. inviteeUid targeted invite: only matching UID joins; matching email with wrong UID denied
    const uidInv = await coordinator.createFamilyInvite({
      actorUserId: "owner_1",
      familyId: "fam_1",
      inviteKind: "targeted",
      inviteeName: "Bob",
      inviteeUid: "u_bob_target"
    });
    await assert.rejects(
      () =>
        coordinator.joinFamilyByInvite({
          actorUserId: "u_other",
          userName: "Fake Bob",
          inviteCode: uidInv.inviteCode,
          authEmail: "bob@lifeos.vn",
          authEmailVerified: true
        }),
      (err: unknown) => err instanceof FamilyInviteError && err.code === "PERMISSION_DENIED"
    );
    const bobJoin = await coordinator.joinFamilyByInvite({
      actorUserId: "u_bob_target",
      userName: "Bob",
      inviteCode: uidInv.inviteCode
    });
    assert.equal(bobJoin.ok, true);

    // 4b. Unverified matching email on intendedRecipientHash invite yields explicit Vietnamese verification prompt
    const hashInv = await coordinator.createFamilyInvite({
      actorUserId: "owner_1",
      familyId: "fam_1",
      inviteKind: "targeted",
      inviteeName: "Chi",
      inviteeContact: "Chi@LifeOS.vn"
    });
    await assert.rejects(
      () =>
        coordinator.joinFamilyByInvite({
          actorUserId: "u_chi",
          userName: "Chi",
          inviteCode: hashInv.inviteCode,
          authEmail: "chi@lifeos.vn",
          authEmailVerified: false
        }),
      (err: unknown) =>
        err instanceof FamilyInviteError &&
        err.code === "PERMISSION_DENIED" &&
        err.message.includes("Cần xác minh email trước khi tham gia nhóm")
    );
    const chiJoin = await coordinator.joinFamilyByInvite({
      actorUserId: "u_chi",
      userName: "Chi",
      inviteCode: hashInv.inviteCode,
      authEmail: "chi@lifeos.vn",
      authEmailVerified: true
    });
    assert.equal(chiJoin.ok, true);

    // 4c. Legacy/direct targeted invite with inviteeEmail requires verified matching email
    store.invites.set("FAM-MAILRAW1", {
      inviteId: "FAM-MAILRAW1",
      inviteCode: "FAM-MAILRAW1",
      familyId: "fam_1",
      familyName: "Tổ ấm Minh & Lan",
      spaceType: "family",
      inviteKind: "targeted",
      isTargeted: true,
      createdBy: "owner_1",
      invitedByUserId: "owner_1",
      invitedByName: "Minh",
      inviteeEmail: "Mai@LifeOS.vn",
      maxUses: 1,
      usedCount: 0,
      consumedBy: null,
      consumedAtMs: null,
      revoked: false,
      revokedBy: null,
      revokedAtMs: null,
      status: "active",
      expiresAtMs: nowMs + 86400_000,
      createdAtMs: nowMs,
      updatedAtMs: nowMs
    });
    await assert.rejects(
      () =>
        coordinator.joinFamilyByInvite({
          actorUserId: "u_mai",
          userName: "Mai",
          inviteCode: "FAM-MAILRAW1",
          authEmail: "mai@lifeos.vn",
          authEmailVerified: false
        }),
      (err: unknown) =>
        err instanceof FamilyInviteError &&
        err.code === "PERMISSION_DENIED" &&
        err.message.includes("Cần xác minh email trước khi tham gia nhóm")
    );
    const maiJoin = await coordinator.joinFamilyByInvite({
      actorUserId: "u_mai",
      userName: "Mai",
      inviteCode: "FAM-MAILRAW1",
      authEmail: "mai@lifeos.vn",
      authEmailVerified: true
    });
    assert.equal(maiJoin.ok, true);

    // 4d. Open invite works without verified email
    const openInv = await coordinator.createFamilyInvite({
      actorUserId: "owner_1",
      familyId: "fam_1",
      inviteKind: "oneTime"
    });
    const openJoin = await coordinator.joinFamilyByInvite({
      actorUserId: "u_open",
      userName: "Khách",
      inviteCode: openInv.inviteCode
    });
    assert.equal(openJoin.ok, true);
  });
});
