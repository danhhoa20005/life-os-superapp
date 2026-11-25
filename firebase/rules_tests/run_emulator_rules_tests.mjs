import { describe, it } from 'node:test';
import assert from 'node:assert/strict';

const PROJECT_ID = 'demo-life-os';
const EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8188';
const BASE_URL = `http://${EMULATOR_HOST}/v1/projects/${PROJECT_ID}/databases/(default)/documents`;
const COMMIT_URL = `${BASE_URL}:commit`;

function makeEmulatorJwt(uid) {
  const header = Buffer.from(JSON.stringify({ alg: 'none', typ: 'JWT' })).toString('base64url');
  const payload = Buffer.from(
    JSON.stringify({
      iss: `https://securetoken.google.com/${PROJECT_ID}`,
      aud: PROJECT_ID,
      user_id: uid,
      sub: uid,
      iat: Math.floor(Date.now() / 1000) - 60,
      exp: Math.floor(Date.now() / 1000) + 3600,
    }),
  ).toString('base64url');
  return `${header}.${payload}.`;
}

function toFirestoreValue(v) {
  if (v === null || v === undefined) return { nullValue: null };
  if (v instanceof Date) return { timestampValue: v.toISOString() };
  if (typeof v === 'string') return { stringValue: v };
  if (typeof v === 'number') return { integerValue: String(v) };
  if (typeof v === 'boolean') return { booleanValue: v };
  if (Array.isArray(v)) {
    return { arrayValue: { values: v.map((item) => toFirestoreValue(item)) } };
  }
  if (typeof v === 'object') {
    return { mapValue: { fields: toFirestoreFields(v) } };
  }
  return { stringValue: String(v) };
}

function toFirestoreFields(obj) {
  const fields = {};
  for (const [k, v] of Object.entries(obj)) {
    fields[k] = toFirestoreValue(v);
  }
  return fields;
}

async function firestoreRequest(method, docPath, { uid = null, data = null } = {}) {
  const headers = { 'Content-Type': 'application/json' };
  if (uid) headers.Authorization = `Bearer ${makeEmulatorJwt(uid)}`;
  const url = `${BASE_URL}/${docPath}`;
  const res = await fetch(url, {
    method,
    headers,
    body: data ? JSON.stringify({ fields: toFirestoreFields(data) }) : undefined,
  });
  return res.status;
}

async function firestoreCommitBatch(uid, writes) {
  const headers = { 'Content-Type': 'application/json' };
  if (uid) headers.Authorization = `Bearer ${makeEmulatorJwt(uid)}`;
  const formattedWrites = writes.map((w) => {
    const docName = `projects/${PROJECT_ID}/databases/(default)/documents/${w.path}`;
    const writeObj = {
      update: {
        name: docName,
        fields: toFirestoreFields(w.data),
      },
    };
    if (Array.isArray(w.updateMask) && w.updateMask.length > 0) {
      writeObj.updateMask = { fieldPaths: w.updateMask };
    }
    if (w.exists !== undefined) {
      writeObj.currentDocument = { exists: w.exists };
    }
    return writeObj;
  });
  const res = await fetch(COMMIT_URL, {
    method: 'POST',
    headers,
    body: JSON.stringify({ writes: formattedWrites }),
  });
  return res.status;
}

describe('Real Firebase Firestore Emulator — Full firestore.rules Verification', () => {
  it('1. Denies unauthenticated access across personal and family collections', async () => {
    assert.equal(await firestoreRequest('GET', 'users/user_a'), 403);
    assert.equal(await firestoreRequest('GET', 'families/fam_1'), 403);
    assert.equal(await firestoreRequest('GET', 'family_invites'), 403);
  });

  it('2. Allows owner access, blocks cross-user & family-owner snooping on private_events/wallets, and blocks tx delete', async () => {
    assert.equal(
      await firestoreRequest('PATCH', 'users/member_a', {
        uid: 'member_a',
        data: { id: 'member_a', email: 'a@lifeos.vn', fullName: 'Minh' },
      }),
      200,
    );
    assert.equal(
      await firestoreRequest('PATCH', 'users/member_a/private_events/ev_1', {
        uid: 'member_a',
        data: { id: 'ev_1', ownerId: 'member_a', title: 'Khám riêng tư' },
      }),
      200,
    );
    assert.equal(
      await firestoreRequest('PATCH', 'users/member_a/transactions/tx_1', {
        uid: 'member_a',
        data: { id: 'tx_1', ownerId: 'member_a', amountMinor: 85000, currencyCode: 'VND' },
      }),
      200,
    );

    // Invalid amountMinor = 0 must be rejected (403)
    assert.equal(
      await firestoreRequest('PATCH', 'users/member_a/transactions/tx_zero', {
        uid: 'member_a',
        data: { id: 'tx_zero', ownerId: 'member_a', amountMinor: 0, currencyCode: 'VND' },
      }),
      403,
    );

    // Hard delete on transaction must be rejected (403)
    assert.equal(
      await firestoreRequest('DELETE', 'users/member_a/transactions/tx_1', { uid: 'member_a' }),
      403,
    );

    // Family owner creates shared household with member_a
    assert.equal(
      await firestoreRequest('PATCH', 'families/fam_shared', {
        uid: 'owner_b',
        data: {
          id: 'fam_shared',
          name: 'Gia đình B',
          createdBy: 'owner_b',
          memberIds: ['owner_b', 'member_a'],
          memberRoles: { owner_b: 'owner', member_a: 'member' },
        },
      }),
      200,
    );

    // Family owner_b STILL cannot read member_a's private_events!
    assert.equal(
      await firestoreRequest('GET', 'users/member_a/private_events/ev_1', { uid: 'owner_b' }),
      403,
    );
  });

  it('3. Enforces FIX-002/003 atomic non-member join, zero PII on family_invites, maxUses/expiry/revocation, RBAC & leave', async () => {
    const suffix = Date.now();
    const famId = `fam_${suffix}`;
    const futureDate = new Date(Date.now() + 24 * 3600 * 1000);

    assert.equal(
      await firestoreRequest('PATCH', `families/${famId}`, {
        uid: 'owner_1',
        data: {
          id: famId,
          name: 'Tổ ấm 1',
          createdBy: 'owner_1',
          memberIds: ['owner_1'],
          memberRoles: { owner_1: 'owner' },
          memberNames: { owner_1: 'Chủ nhóm' },
        },
      }),
      200,
    );

    // FIX-003: Listing family_invites directory is forbidden even when signed in (403)!
    assert.equal(await firestoreRequest('GET', 'family_invites', { uid: 'user_2' }), 403);

    // FIX-003: Creating an invite that leaks raw `inviteeContact` on public `family_invites` -> DENIED (403)!
    const piiCode = `FAM-PII-${suffix}`;
    assert.equal(
      await firestoreRequest('PATCH', `family_invites/${piiCode}`, {
        uid: 'owner_1',
        data: {
          inviteCode: piiCode,
          familyId: famId,
          createdBy: 'owner_1',
          inviteeContact: 'secret@lifeos.vn',
          maxUses: 1,
          usedCount: 0,
          status: 'active',
          expiresAt: futureDate,
        },
      }),
      403,
    );

    // Valid one-time invite creation (hashed recipient only, no raw contact PII!) -> 200
    const invCode = `FAM-JOIN-${suffix}`;
    assert.equal(
      await firestoreRequest('PATCH', `family_invites/${invCode}`, {
        uid: 'owner_1',
        data: {
          inviteCode: invCode,
          familyId: famId,
          createdBy: 'owner_1',
          intendedRecipientHash: 'a'.repeat(64),
          maxUses: 1,
          usedCount: 0,
          revoked: false,
          status: 'active',
          expiresAt: futureDate,
        },
      }),
      200,
    );

    assert.equal(
      await firestoreRequest('PATCH', `families/${famId}/funds/fund_1`, {
        uid: 'owner_1',
        data: { id: 'fund_1', familyId: famId, name: 'Quỹ Tết', balanceMinor: 500000 },
      }),
      200,
    );

    // FIX-002: Non-member user_2 CANNOT read families/{famId} before joining (403)
    assert.equal(await firestoreRequest('GET', `families/${famId}`, { uid: 'user_2' }), 403);
    // FIX-002: Non-member user_2 CAN preview public family_invites/{invCode} (200)
    assert.equal(await firestoreRequest('GET', `family_invites/${invCode}`, { uid: 'user_2' }), 200);

    // Bypass attempt 1: Standalone family update WITHOUT consuming invite in same batch -> DENIED (403)!
    assert.equal(
      await firestoreRequest('PATCH', `families/${famId}`, {
        uid: 'user_2',
        data: {
          id: famId,
          name: 'Tổ ấm 1',
          createdBy: 'owner_1',
          memberIds: ['owner_1', 'user_2'],
          memberRoles: { owner_1: 'owner', user_2: 'member' },
          memberNames: { owner_1: 'Chủ nhóm', user_2: 'Lan' },
          lastJoinedInviteCode: invCode,
        },
      }),
      403,
    );

    // Bypass attempt 2: Atomic batch trying to self-escalate role to 'owner' -> DENIED (403)!
    assert.equal(
      await firestoreCommitBatch('user_2', [
        {
          path: `family_invites/${invCode}`,
          exists: true,
          updateMask: ['usedCount', 'consumedBy', 'consumedAt', 'status', 'updatedAt'],
          data: {
            usedCount: 1,
            consumedBy: 'user_2',
            consumedAt: new Date(),
            status: 'consumed',
            updatedAt: new Date(),
          },
        },
        {
          path: `families/${famId}`,
          exists: true,
          updateMask: ['memberIds', 'memberRoles', 'memberNames', 'lastJoinedInviteCode', 'updatedAt'],
          data: {
            memberIds: ['owner_1', 'user_2'],
            memberRoles: { owner_1: 'owner', user_2: 'owner' },
            memberNames: { owner_1: 'Chủ nhóm', user_2: 'Lan' },
            lastJoinedInviteCode: invCode,
            updatedAt: new Date(),
          },
        },
      ]),
      403,
    );

    // Legitimate atomic batch join as 'member' -> SUCCEEDS (200)!
    assert.equal(
      await firestoreCommitBatch('user_2', [
        {
          path: `family_invites/${invCode}`,
          exists: true,
          updateMask: ['usedCount', 'consumedBy', 'consumedAt', 'status', 'updatedAt'],
          data: {
            usedCount: 1,
            consumedBy: 'user_2',
            consumedAt: new Date(),
            status: 'consumed',
            updatedAt: new Date(),
          },
        },
        {
          path: `families/${famId}`,
          exists: true,
          updateMask: ['memberIds', 'memberRoles', 'memberNames', 'lastJoinedInviteCode', 'updatedAt'],
          data: {
            memberIds: ['owner_1', 'user_2'],
            memberRoles: { owner_1: 'owner', user_2: 'member' },
            memberNames: { owner_1: 'Chủ nhóm', user_2: 'Lan' },
            lastJoinedInviteCode: invCode,
            updatedAt: new Date(),
          },
        },
      ]),
      200,
    );

    // Replay attempt on already-consumed one-time code (usedCount == maxUses == 1) -> DENIED (403)!
    assert.equal(
      await firestoreCommitBatch('user_replay', [
        {
          path: `family_invites/${invCode}`,
          exists: true,
          updateMask: ['usedCount', 'consumedBy', 'consumedAt', 'status', 'updatedAt'],
          data: {
            usedCount: 2,
            consumedBy: 'user_replay',
            consumedAt: new Date(),
            status: 'consumed',
            updatedAt: new Date(),
          },
        },
        {
          path: `families/${famId}`,
          exists: true,
          updateMask: ['memberIds', 'memberRoles', 'memberNames', 'lastJoinedInviteCode', 'updatedAt'],
          data: {
            memberIds: ['owner_1', 'user_2', 'user_replay'],
            memberRoles: { owner_1: 'owner', user_2: 'member', user_replay: 'member' },
            memberNames: { owner_1: 'Chủ nhóm', user_2: 'Lan', user_replay: 'Kẻ giả mạo' },
            lastJoinedInviteCode: invCode,
            updatedAt: new Date(),
          },
        },
      ]),
      403,
    );

    // user_2 can now read shared fund and create positive-int split_bills & settlements
    assert.equal(
      await firestoreRequest('GET', `families/${famId}/funds/fund_1`, { uid: 'user_2' }),
      200,
    );
    assert.equal(
      await firestoreRequest('PATCH', `families/${famId}/split_bills/bill_1`, {
        uid: 'user_2',
        data: {
          id: 'bill_1',
          familyId: famId,
          title: 'Ăn tối & Nước giặt',
          paidByUserId: 'user_2',
          totalAmountMinor: 240000,
        },
      }),
      200,
    );
    assert.equal(
      await firestoreRequest('PATCH', `families/${famId}/settlements/st_1`, {
        uid: 'owner_1',
        data: {
          id: 'st_1',
          familyId: famId,
          fromUserId: 'owner_1',
          toUserId: 'user_2',
          amountMinor: 120000,
          paymentCode: 'SEVQR LIFEOS SPLIT01',
        },
      }),
      200,
    );
    // Settlement records are immutable (DELETE must be rejected with 403!)
    assert.equal(
      await firestoreRequest('DELETE', `families/${famId}/settlements/st_1`, { uid: 'owner_1' }),
      403,
    );
    // Non-member outsider_9 is strictly denied reading split_bills (403!)
    assert.equal(
      await firestoreRequest('GET', `families/${famId}/split_bills/bill_1`, { uid: 'outsider_9' }),
      403,
    );

    // Reusable group invite (`maxUses: 2`): user_3 and user_4 join, user_5 is blocked!
    const invCodeGroup = `FAM-GRP-${suffix}`;
    assert.equal(
      await firestoreRequest('PATCH', `family_invites/${invCodeGroup}`, {
        uid: 'owner_1',
        data: {
          inviteCode: invCodeGroup,
          familyId: famId,
          createdBy: 'owner_1',
          maxUses: 2,
          usedCount: 0,
          revoked: false,
          status: 'active',
          expiresAt: futureDate,
        },
      }),
      200,
    );

    // Expired invite creation is rejected (403); revoked invite cannot be consumed (403)
    const invCodeExpired = `FAM-EXP-${suffix}`;
    assert.equal(
      await firestoreRequest('PATCH', `family_invites/${invCodeExpired}`, {
        uid: 'owner_1',
        data: {
          inviteCode: invCodeExpired,
          familyId: famId,
          createdBy: 'owner_1',
          maxUses: 1,
          usedCount: 0,
          revoked: false,
          status: 'active',
          expiresAt: new Date(Date.now() - 60 * 1000),
        },
      }),
      403,
    );
    const invCodeRevoked = `FAM-REV-${suffix}`;
    assert.equal(
      await firestoreRequest('PATCH', `family_invites/${invCodeRevoked}`, {
        uid: 'owner_1',
        data: {
          inviteCode: invCodeRevoked,
          familyId: famId,
          createdBy: 'owner_1',
          maxUses: 1,
          usedCount: 0,
          revoked: false,
          status: 'active',
          expiresAt: futureDate,
        },
      }),
      200,
    );
    assert.equal(
      await firestoreRequest('PATCH', `family_invites/${invCodeRevoked}`, {
        uid: 'owner_1',
        data: {
          inviteCode: invCodeRevoked,
          familyId: famId,
          createdBy: 'owner_1',
          maxUses: 1,
          usedCount: 0,
          revoked: true,
          status: 'revoked',
          expiresAt: futureDate,
        },
      }),
      200,
    );
    assert.equal(
      await firestoreCommitBatch('user_3', [
        {
          path: `family_invites/${invCodeRevoked}`,
          exists: true,
          updateMask: ['usedCount', 'consumedBy', 'consumedAt', 'status', 'updatedAt'],
          data: {
            usedCount: 1,
            consumedBy: 'user_3',
            consumedAt: new Date(),
            status: 'consumed',
            updatedAt: new Date(),
          },
        },
        {
          path: `families/${famId}`,
          exists: true,
          updateMask: ['memberIds', 'memberRoles', 'memberNames', 'lastJoinedInviteCode', 'updatedAt'],
          data: {
            memberIds: ['owner_1', 'user_2', 'user_3'],
            memberRoles: { owner_1: 'owner', user_2: 'member', user_3: 'member' },
            memberNames: { owner_1: 'Chủ nhóm', user_2: 'Lan', user_3: 'Hùng' },
            lastJoinedInviteCode: invCodeRevoked,
            updatedAt: new Date(),
          },
        },
      ]),
      403,
    );

    // Existing plain member (user_2) AND manager (owner_1) cannot burn or tamper usedCount on an active invite -> DENIED (403)!
    assert.equal(
      await firestoreCommitBatch('user_2', [
        {
          path: `family_invites/${invCodeGroup}`,
          exists: true,
          updateMask: ['usedCount', 'consumedBy', 'consumedAt', 'status', 'updatedAt'],
          data: {
            usedCount: 1,
            consumedBy: 'user_2',
            consumedAt: new Date(),
            status: 'active',
            updatedAt: new Date(),
          },
        },
      ]),
      403,
    );
    assert.equal(
      await firestoreCommitBatch('owner_1', [
        {
          path: `family_invites/${invCodeGroup}`,
          exists: true,
          updateMask: ['usedCount', 'consumedBy', 'consumedAt', 'status', 'updatedAt'],
          data: {
            usedCount: 1,
            consumedBy: 'owner_1',
            consumedAt: new Date(),
            status: 'active',
            updatedAt: new Date(),
          },
        },
      ]),
      403,
    );

    // SEC-03: Join with valid invite code BUT tampering family name -> DENIED (403)!
    assert.equal(
      await firestoreCommitBatch('user_3', [
        {
          path: `family_invites/${invCodeGroup}`,
          exists: true,
          updateMask: ['usedCount', 'consumedBy', 'consumedAt', 'status', 'updatedAt'],
          data: {
            usedCount: 1,
            consumedBy: 'user_3',
            consumedAt: new Date(),
            status: 'active',
            updatedAt: new Date(),
          },
        },
        {
          path: `families/${famId}`,
          exists: true,
          updateMask: ['name', 'memberIds', 'memberRoles', 'memberNames', 'lastJoinedInviteCode', 'updatedAt'],
          data: {
            name: 'TÊN BỊ GIẢ MẠO',
            memberIds: ['owner_1', 'user_2', 'user_3'],
            memberRoles: { owner_1: 'owner', user_2: 'member', user_3: 'member' },
            memberNames: { owner_1: 'Chủ nhóm', user_2: 'Lan', user_3: 'Hùng' },
            lastJoinedInviteCode: invCodeGroup,
            updatedAt: new Date(),
          },
        },
      ]),
      403,
    );

    // Clean atomic join for user_3 (slot 1 of 2, status stays 'active') -> 200
    assert.equal(
      await firestoreCommitBatch('user_3', [
        {
          path: `family_invites/${invCodeGroup}`,
          exists: true,
          updateMask: ['usedCount', 'consumedBy', 'consumedAt', 'status', 'updatedAt'],
          data: {
            usedCount: 1,
            consumedBy: 'user_3',
            consumedAt: new Date(),
            status: 'active',
            updatedAt: new Date(),
          },
        },
        {
          path: `families/${famId}`,
          exists: true,
          updateMask: ['memberIds', 'memberRoles', 'memberNames', 'lastJoinedInviteCode', 'updatedAt'],
          data: {
            memberIds: ['owner_1', 'user_2', 'user_3'],
            memberRoles: { owner_1: 'owner', user_2: 'member', user_3: 'member' },
            memberNames: { owner_1: 'Chủ nhóm', user_2: 'Lan', user_3: 'Hùng' },
            lastJoinedInviteCode: invCodeGroup,
            updatedAt: new Date(),
          },
        },
      ]),
      200,
    );

    // Clean atomic join for user_4 (slot 2 of 2, status becomes 'consumed') -> 200
    assert.equal(
      await firestoreCommitBatch('user_4', [
        {
          path: `family_invites/${invCodeGroup}`,
          exists: true,
          updateMask: ['usedCount', 'consumedBy', 'consumedAt', 'status', 'updatedAt'],
          data: {
            usedCount: 2,
            consumedBy: 'user_4',
            consumedAt: new Date(),
            status: 'consumed',
            updatedAt: new Date(),
          },
        },
        {
          path: `families/${famId}`,
          exists: true,
          updateMask: ['memberIds', 'memberRoles', 'memberNames', 'lastJoinedInviteCode', 'updatedAt'],
          data: {
            memberIds: ['owner_1', 'user_2', 'user_3', 'user_4'],
            memberRoles: { owner_1: 'owner', user_2: 'member', user_3: 'member', user_4: 'member' },
            memberNames: { owner_1: 'Chủ nhóm', user_2: 'Lan', user_3: 'Hùng', user_4: 'Mai' },
            lastJoinedInviteCode: invCodeGroup,
            updatedAt: new Date(),
          },
        },
      ]),
      200,
    );

    // user_5 tries exceeding maxUses (3 > 2) -> DENIED (403)!
    assert.equal(
      await firestoreCommitBatch('user_5', [
        {
          path: `family_invites/${invCodeGroup}`,
          exists: true,
          updateMask: ['usedCount', 'consumedBy', 'consumedAt', 'status', 'updatedAt'],
          data: {
            usedCount: 3,
            consumedBy: 'user_5',
            consumedAt: new Date(),
            status: 'consumed',
            updatedAt: new Date(),
          },
        },
        {
          path: `families/${famId}`,
          exists: true,
          updateMask: ['memberIds', 'memberRoles', 'memberNames', 'lastJoinedInviteCode', 'updatedAt'],
          data: {
            memberIds: ['owner_1', 'user_2', 'user_3', 'user_4', 'user_5'],
            memberRoles: { owner_1: 'owner', user_2: 'member', user_3: 'member', user_4: 'member', user_5: 'member' },
            memberNames: { owner_1: 'Chủ nhóm', user_2: 'Lan', user_3: 'Hùng', user_4: 'Mai', user_5: 'Nam' },
            lastJoinedInviteCode: invCodeGroup,
            updatedAt: new Date(),
          },
        },
      ]),
      403,
    );

    // SEC-04: user_3 tries to forge settlement between owner_1 and user_2 -> DENIED (403)!
    assert.equal(
      await firestoreRequest('PATCH', `families/${famId}/settlements/st_forged`, {
        uid: 'user_3',
        data: {
          id: 'st_forged',
          familyId: famId,
          fromUserId: 'owner_1',
          toUserId: 'user_2',
          amountMinor: 120000,
          paymentCode: 'FORGED',
        },
      }),
      403,
    );

    // Two-step settlement_requests: debtor user_2 creates 'pending', 3rd-party user_3 cannot confirm, creditor owner_1 confirms!
    assert.equal(
      await firestoreRequest('PATCH', `families/${famId}/settlement_requests/req_1`, {
        uid: 'user_2',
        data: {
          id: 'req_1',
          familyId: famId,
          fromUserId: 'user_2',
          toUserId: 'owner_1',
          amountMinor: 50000,
          paymentCode: 'LIFEOS SPLIT01',
          status: 'pending',
        },
      }),
      200,
    );
    assert.equal(
      await firestoreRequest('PATCH', `families/${famId}/settlement_requests/req_1`, {
        uid: 'user_3',
        data: {
          id: 'req_1',
          familyId: famId,
          fromUserId: 'user_2',
          toUserId: 'owner_1',
          amountMinor: 50000,
          paymentCode: 'LIFEOS SPLIT01',
          status: 'confirmed',
          confirmedBy: 'user_3',
          confirmedAt: new Date(),
        },
      }),
      403,
    );
    assert.equal(
      await firestoreCommitBatch('owner_1', [
        {
          path: `families/${famId}/settlement_requests/req_1`,
          exists: true,
          updateMask: ['status', 'confirmedBy', 'confirmedAt'],
          data: {
            status: 'confirmed',
            confirmedBy: 'owner_1',
            confirmedAt: new Date(),
          },
        },
        {
          path: `families/${famId}/settlements/stl_req_1`,
          exists: false,
          data: {
            id: 'stl_req_1',
            familyId: famId,
            fromUserId: 'user_2',
            toUserId: 'owner_1',
            amountMinor: 50000,
            paymentCode: 'LIFEOS SPLIT01',
            settlementRequestId: 'req_1',
          },
        },
      ]),
      200,
    );

    // SEC-02: Owner promotes user_3 to 'admin', then user_3 tries to self-escalate to 'owner' or demote owner_1 -> DENIED (403)!
    assert.equal(
      await firestoreRequest('PATCH', `families/${famId}`, {
        uid: 'owner_1',
        data: {
          id: famId,
          name: 'Tổ ấm 1',
          createdBy: 'owner_1',
          memberIds: ['owner_1', 'user_2', 'user_3', 'user_4'],
          memberRoles: { owner_1: 'owner', user_2: 'member', user_3: 'admin', user_4: 'member' },
          memberNames: { owner_1: 'Chủ nhóm', user_2: 'Lan', user_3: 'Hùng', user_4: 'Mai' },
        },
      }),
      200,
    );
    assert.equal(
      await firestoreRequest('PATCH', `families/${famId}`, {
        uid: 'user_3',
        data: {
          id: famId,
          name: 'Tổ ấm 1',
          createdBy: 'owner_1',
          memberIds: ['owner_1', 'user_2', 'user_3', 'user_4'],
          memberRoles: { owner_1: 'member', user_2: 'member', user_3: 'owner', user_4: 'member' },
          memberNames: { owner_1: 'Chủ nhóm', user_2: 'Lan', user_3: 'Hùng', user_4: 'Mai' },
        },
      }),
      403,
    );

    // SEC-01: user_2 leaves family AND tries to tamper user_3's role -> DENIED (403)!
    assert.equal(
      await firestoreRequest('PATCH', `families/${famId}`, {
        uid: 'user_2',
        data: {
          id: famId,
          name: 'Tổ ấm 1',
          createdBy: 'owner_1',
          memberIds: ['owner_1', 'user_3', 'user_4'],
          memberRoles: { owner_1: 'owner', user_3: 'member', user_4: 'member' },
          memberNames: { owner_1: 'Chủ nhóm', user_3: 'Hùng', user_4: 'Mai' },
        },
      }),
      403,
    );

    // Legitimate user_2 voluntary leave -> immediately denied reading shared fund (403)!
    assert.equal(
      await firestoreRequest('PATCH', `families/${famId}`, {
        uid: 'user_2',
        data: {
          id: famId,
          name: 'Tổ ấm 1',
          createdBy: 'owner_1',
          memberIds: ['owner_1', 'user_3', 'user_4'],
          memberRoles: { owner_1: 'owner', user_3: 'admin', user_4: 'member' },
          memberNames: { owner_1: 'Chủ nhóm', user_3: 'Hùng', user_4: 'Mai' },
        },
      }),
      200,
    );
    assert.equal(
      await firestoreRequest('GET', `families/${famId}/funds/fund_1`, { uid: 'user_2' }),
      403,
    );
  });

  it('4. T20 & T23 — Isolates devices, bank_connections, financial_notifications & blocks client access to server-only collections', async () => {
    // Owner A registers own FCM device & privacy settings -> 200
    assert.equal(
      await firestoreRequest('PATCH', 'users/bank_user_a/devices/dev_pixel9', {
        uid: 'bank_user_a',
        data: {
          deviceId: 'dev_pixel9',
          ownerId: 'bank_user_a',
          fcmToken: 'tok_a_123',
          pushEnabled: true,
        },
      }),
      200,
    );
    assert.equal(
      await firestoreRequest('PATCH', 'users/bank_user_a/notification_preferences/settings', {
        uid: 'bank_user_a',
        data: {
          ownerId: 'bank_user_a',
          hideAmountOnLockscreen: true,
        },
      }),
      200,
    );

    // Client CANNOT forge a verified `sepay` + `connected` bank_connection directly -> 403!
    assert.equal(
      await firestoreRequest('PATCH', 'users/bank_user_a/bank_connections/forged_conn', {
        uid: 'bank_user_a',
        data: {
          ownerId: 'bank_user_a',
          provider: 'sepay',
          status: 'connected',
          bankCode: 'VCB',
        },
      }),
      403,
    );

    // User B CANNOT read or write User A's devices, preferences, bank_connections, or financial_notifications -> 403!
    assert.equal(
      await firestoreRequest('GET', 'users/bank_user_a/devices/dev_pixel9', { uid: 'bank_user_b' }),
      403,
    );
    assert.equal(
      await firestoreRequest('PATCH', 'users/bank_user_a/devices/dev_hijack', {
        uid: 'bank_user_b',
        data: { deviceId: 'dev_hijack', ownerId: 'bank_user_a', fcmToken: 'evil' },
      }),
      403,
    );
    assert.equal(
      await firestoreRequest('GET', 'users/bank_user_a/notification_preferences/settings', {
        uid: 'bank_user_b',
      }),
      403,
    );
    assert.equal(
      await firestoreRequest('GET', 'users/bank_user_a/financial_notifications/n1', {
        uid: 'bank_user_b',
      }),
      403,
    );

    // Server-only collections are strictly inaccessible to ALL client users -> 403!
    assert.equal(
      await firestoreRequest('GET', 'server_bank_connections/conn_1', { uid: 'bank_user_a' }),
      403,
    );
    assert.equal(
      await firestoreRequest('PATCH', 'sepay_webhook_inbox/ev_1', {
        uid: 'bank_user_a',
        data: { state: 'PROCESSED' },
      }),
      403,
    );
    assert.equal(
      await firestoreRequest('GET', 'notification_outbox/out_1', { uid: 'bank_user_a' }),
      403,
    );
    assert.equal(
      await firestoreRequest('GET', 'bank_reconciliation_jobs/job_1', { uid: 'bank_user_a' }),
      403,
    );
    assert.equal(
      await firestoreRequest('GET', 'family_invite_rate_limits/bank_user_a', { uid: 'bank_user_a' }),
      403,
    );
  });

  it('5. Section 40 & FIX-007 — Requires ledger_audit on wallet balance mutations & locks verified transaction core fields', async () => {
    const uid = `ledger_u_${Date.now()}`;
    assert.equal(
      await firestoreRequest('PATCH', `users/${uid}/wallets/w_main`, {
        uid,
        data: {
          id: 'w_main',
          ownerId: uid,
          name: 'VCB Chính',
          balanceMinor: 1000000,
        },
      }),
      200,
    );

    // Changing balanceMinor WITHOUT lastAuditId -> DENIED (403)!
    assert.equal(
      await firestoreRequest('PATCH', `users/${uid}/wallets/w_main`, {
        uid,
        data: {
          id: 'w_main',
          ownerId: uid,
          name: 'VCB Chính',
          balanceMinor: 9999999,
          updatedAt: new Date(),
        },
      }),
      403,
    );

    // Changing balanceMinor WITH non-existent lastAuditId -> DENIED (403)!
    assert.equal(
      await firestoreRequest('PATCH', `users/${uid}/wallets/w_main`, {
        uid,
        data: {
          id: 'w_main',
          ownerId: uid,
          name: 'VCB Chính',
          balanceMinor: 9999999,
          lastAuditId: 'aud_ghost',
          updatedAt: new Date(),
        },
      }),
      403,
    );

    // Changing balanceMinor WITH atomic ledger_audit in same batch -> SUCCEEDS (200)!
    assert.equal(
      await firestoreCommitBatch(uid, [
        {
          path: `users/${uid}/ledger_audits/aud_1`,
          exists: false,
          data: {
            id: 'aud_1',
            ownerId: uid,
            walletId: 'w_main',
            previousBalanceMinor: 1000000,
            deltaMinor: 500000,
            newBalanceMinor: 1500000,
            createdAt: new Date(),
          },
        },
        {
          path: `users/${uid}/wallets/w_main`,
          exists: true,
          updateMask: ['balanceMinor', 'lastAuditId', 'updatedAt'],
          data: {
            balanceMinor: 1500000,
            lastAuditId: 'aud_1',
            updatedAt: new Date(),
          },
        },
      ]),
      200,
    );

    // Updating wallet metadata WITHOUT changing balanceMinor -> SUCCEEDS (200)!
    assert.equal(
      await firestoreRequest('PATCH', `users/${uid}/wallets/w_main`, {
        uid,
        data: {
          id: 'w_main',
          ownerId: uid,
          name: 'VCB Lương 2026',
          balanceMinor: 1500000,
          lastAuditId: 'aud_1',
          updatedAt: new Date(),
        },
      }),
      200,
    );

    // Verified bank transaction: core financial & provenance fields are strictly immutable!
    const verifiedTx = {
      id: 'tx_ver_1',
      ownerId: uid,
      walletId: 'w_main',
      categoryName: 'Lương & Thu nhập',
      kind: 'income',
      direction: 'credit',
      amountMinor: 500000,
      currencyCode: 'VND',
      verification: 'verified',
      verificationStatus: 'VERIFIED',
      sourceKind: 'bankApi',
      externalTransactionId: 'sepay_9988',
      referenceCode: 'FT20269988',
      observedBalanceMinor: 1500000,
      note: 'Nhận chuyển khoản',
    };
    assert.equal(
      await firestoreRequest('PATCH', `users/${uid}/transactions/tx_ver_1`, {
        uid,
        data: verifiedTx,
      }),
      200,
    );

    // Tampering amountMinor, walletId, kind, verification, externalTransactionId, referenceCode, or observedBalanceMinor -> ALL DENIED (403)!
    for (const [field, badVal] of [
      ['amountMinor', 9000000],
      ['walletId', 'w_other'],
      ['kind', 'expense'],
      ['verification', 'userConfirmed'],
      ['externalTransactionId', 'forged_ext'],
      ['referenceCode', 'FORGED_REF'],
      ['observedBalanceMinor', 9999999],
    ]) {
      assert.equal(
        await firestoreRequest('PATCH', `users/${uid}/transactions/tx_ver_1`, {
          uid,
          data: { ...verifiedTx, [field]: badVal },
        }),
        403,
        `Expected 403 when mutating verified field '${field}'`,
      );
    }

    // Mutating categoryName & note metadata on verified transaction -> SUCCEEDS (200)!
    assert.equal(
      await firestoreRequest('PATCH', `users/${uid}/transactions/tx_ver_1`, {
        uid,
        data: {
          ...verifiedTx,
          categoryName: 'Thưởng dự án',
          note: 'Đã phân loại lại',
          updatedAt: new Date(),
        },
      }),
      200,
    );

    // Attaching reversal link (`reversedById` + `verificationStatus: 'REVERSED'`) -> SUCCEEDS (200)!
    assert.equal(
      await firestoreRequest('PATCH', `users/${uid}/transactions/tx_ver_1`, {
        uid,
        data: {
          ...verifiedTx,
          categoryName: 'Thưởng dự án',
          note: 'Đã phân loại lại',
          reversedById: 'rev_tx_ver_1',
          verificationStatus: 'REVERSED',
          updatedAt: new Date(),
        },
      }),
      200,
    );
  });
});
