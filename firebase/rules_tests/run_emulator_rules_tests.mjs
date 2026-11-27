import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';

const PROJECT_ID = 'demo-life-os';
const EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8188';
const BASE_URL = `http://${EMULATOR_HOST}/v1/projects/${PROJECT_ID}/databases/(default)/documents`;
const COMMIT_URL = `${BASE_URL}:commit`;

function sha256Hex(input) {
  return crypto.createHash('sha256').update(input, 'utf8').digest('hex');
}

function makeEmulatorJwt(authSpec) {
  const uid = typeof authSpec === 'string' ? authSpec : authSpec.uid;
  const claims = typeof authSpec === 'object' && authSpec !== null ? authSpec.claims ?? {} : {};
  const header = Buffer.from(JSON.stringify({ alg: 'none', typ: 'JWT' })).toString('base64url');
  const payload = Buffer.from(
    JSON.stringify({
      iss: `https://securetoken.google.com/${PROJECT_ID}`,
      aud: PROJECT_ID,
      user_id: uid,
      sub: uid,
      ...claims,
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
  if (typeof v === 'number') {
    return Number.isInteger(v) ? { integerValue: String(v) } : { doubleValue: v };
  }
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

async function firestoreAdminRequest(method, docPath, { data = null } = {}) {
  const headers = {
    'Content-Type': 'application/json',
    Authorization: 'Bearer owner',
  };
  const url = `${BASE_URL}/${docPath}`;
  const res = await fetch(url, {
    method,
    headers,
    body: data ? JSON.stringify({ fields: toFirestoreFields(data) }) : undefined,
  });
  return res.status;
}

async function firestoreCommitBatch(uid, writes) {
  const res = await firestoreCommitBatchResponse(uid, writes);
  return res.status;
}

async function firestoreCommitBatchResponse(uid, writes, transaction = null) {
  const headers = { 'Content-Type': 'application/json' };
  if (uid) headers.Authorization = `Bearer ${makeEmulatorJwt(uid)}`;
  const formattedWrites = writes.map((w) => {
    const docName = `projects/${PROJECT_ID}/databases/(default)/documents/${w.path}`;
    if (w.delete === true) {
      const delObj = { delete: docName };
      if (w.exists !== undefined) {
        delObj.currentDocument = { exists: w.exists };
      } else if (w.updateTime) {
        delObj.currentDocument = { updateTime: w.updateTime };
      }
      return delObj;
    }
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
    } else if (w.updateTime) {
      writeObj.currentDocument = { updateTime: w.updateTime };
    }
    return writeObj;
  });
  const payload = { writes: formattedWrites };
  if (transaction) payload.transaction = transaction;
  const res = await fetch(COMMIT_URL, {
    method: 'POST',
    headers,
    body: JSON.stringify(payload),
  });
  return res;
}

async function firestoreGetDoc(uid, docPath, transaction = null) {
  const headers = {};
  if (uid) headers.Authorization = `Bearer ${makeEmulatorJwt(uid)}`;
  const qs = transaction ? `?transaction=${encodeURIComponent(transaction)}` : '';
  const res = await fetch(`${BASE_URL}/${docPath}${qs}`, { method: 'GET', headers });
  const body = res.ok ? await res.json() : null;
  return { status: res.status, doc: body };
}

async function firestoreBeginTransaction(uid) {
  const headers = { 'Content-Type': 'application/json' };
  if (uid) headers.Authorization = `Bearer ${makeEmulatorJwt(uid)}`;
  const res = await fetch(`${BASE_URL}:beginTransaction`, {
    method: 'POST',
    headers,
    body: JSON.stringify({ options: { readWrite: {} } }),
  });
  if (!res.ok) throw new Error(`beginTransaction failed: ${res.status}`);
  const json = await res.json();
  return json.transaction;
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

    // Family owner creates shared household and invites member_a cleanly
    assert.equal(
      await firestoreRequest('PATCH', 'families/fam_shared', {
        uid: 'owner_b',
        data: {
          id: 'fam_shared',
          name: 'Gia đình B',
          createdBy: 'owner_b',
          memberIds: ['owner_b'],
          memberRoles: { owner_b: 'owner' },
        },
      }),
      200,
    );
    const privInv = `FAM-PRIV-${Date.now()}`;
    assert.equal(
      await firestoreRequest('PATCH', `family_invites/${privInv}`, {
        uid: 'owner_b',
        data: {
          inviteCode: privInv,
          familyId: 'fam_shared',
          createdBy: 'owner_b',
          maxUses: 1,
          usedCount: 0,
          revoked: false,
          status: 'active',
          expiresAt: new Date(Date.now() + 3600000),
        },
      }),
      200,
    );
    assert.equal(
      await firestoreCommitBatch('member_a', [
        {
          path: `family_invites/${privInv}`,
          exists: true,
          updateMask: ['usedCount', 'consumedBy', 'consumedAt', 'status', 'updatedAt'],
          data: {
            usedCount: 1,
            consumedBy: 'member_a',
            consumedAt: new Date(),
            status: 'consumed',
            updatedAt: new Date(),
          },
        },
        {
          path: 'families/fam_shared',
          exists: true,
          updateMask: ['memberIds', 'memberRoles', 'lastJoinedInviteCode', 'updatedAt'],
          data: {
            memberIds: ['owner_b', 'member_a'],
            memberRoles: { owner_b: 'owner', member_a: 'member' },
            lastJoinedInviteCode: privInv,
            updatedAt: new Date(),
          },
        },
      ]),
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

    // Valid open one-time invite creation (no raw contact PII!) -> 200
    const invCode = `FAM-JOIN-${suffix}`;
    assert.equal(
      await firestoreRequest('PATCH', `family_invites/${invCode}`, {
        uid: 'owner_1',
        data: {
          inviteCode: invCode,
          familyId: famId,
          createdBy: 'owner_1',
          inviteKind: 'oneTime',
          isTargeted: false,
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
        data: {
          id: 'fund_1',
          ownerId: 'owner_1',
          familyId: famId,
          name: 'Quỹ Tết',
          balanceMinor: 0,
          targetAmountMinor: 1000000,
          createdAt: new Date(),
        },
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
          sharesByUserId: { owner_1: 120000, user_2: 120000 },
          status: 'open',
        },
      }),
      200,
    );
    // AUD-002: Unilateral debtor settlement creation MUST fail (403); creditor confirmation succeeds (200)!
    assert.equal(
      await firestoreRequest('PATCH', `families/${famId}/settlements/st_forged_debtor`, {
        uid: 'owner_1',
        data: {
          id: 'st_forged_debtor',
          familyId: famId,
          fromUserId: 'owner_1',
          toUserId: 'user_2',
          amountMinor: 120000,
          paymentCode: 'SEVQR LIFEOS SPLIT01',
        },
      }),
      403,
    );
    assert.equal(
      await firestoreRequest('PATCH', `families/${famId}/settlements/st_1`, {
        uid: 'user_2',
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
          updateMask: ['status', 'confirmedBy', 'confirmedAt', 'settlementId'],
          data: {
            status: 'confirmed',
            confirmedBy: 'owner_1',
            confirmedAt: new Date(),
            settlementId: 'stl_req_req_1',
          },
        },
        {
          path: `families/${famId}/settlements/stl_req_req_1`,
          exists: false,
          data: {
            id: 'stl_req_req_1',
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
      await firestoreCommitBatch('owner_1', [
        {
          path: `families/${famId}`,
          exists: true,
          updateMask: ['memberRoles', 'updatedAt'],
          data: {
            memberRoles: { owner_1: 'owner', user_2: 'member', user_3: 'admin', user_4: 'member' },
            updatedAt: new Date(),
          },
        },
      ]),
      200,
    );
    assert.equal(
      await firestoreCommitBatch('user_3', [
        {
          path: `families/${famId}`,
          exists: true,
          updateMask: ['memberRoles', 'updatedAt'],
          data: {
            memberRoles: { owner_1: 'member', user_2: 'member', user_3: 'owner', user_4: 'member' },
            updatedAt: new Date(),
          },
        },
      ]),
      403,
    );

    // SEC-01: user_2 leaves family AND tries to tamper user_3's role -> DENIED (403)!
    assert.equal(
      await firestoreCommitBatch('user_2', [
        {
          path: `families/${famId}`,
          exists: true,
          updateMask: ['memberIds', 'memberRoles', 'memberNames', 'updatedAt'],
          data: {
            memberIds: ['owner_1', 'user_3', 'user_4'],
            memberRoles: { owner_1: 'owner', user_3: 'member', user_4: 'member' },
            memberNames: { owner_1: 'Chủ nhóm', user_3: 'Hùng', user_4: 'Mai' },
            updatedAt: new Date(),
          },
        },
      ]),
      403,
    );

    // Legitimate user_2 voluntary leave -> immediately denied reading shared fund (403)!
    assert.equal(
      await firestoreCommitBatch('user_2', [
        {
          path: `families/${famId}`,
          exists: true,
          updateMask: ['memberIds', 'memberRoles', 'memberNames', 'updatedAt'],
          data: {
            memberIds: ['owner_1', 'user_3', 'user_4'],
            memberRoles: { owner_1: 'owner', user_3: 'admin', user_4: 'member' },
            memberNames: { owner_1: 'Chủ nhóm', user_3: 'Hùng', user_4: 'Mai' },
            updatedAt: new Date(),
          },
        },
      ]),
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

    // Verified bank transaction: client CANNOT create bankApi/bankWebhook directly (M7),
    // must be created by Admin SDK (Cloud Functions backend), and its core fields are strictly immutable!
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
      403,
    );
    assert.equal(
      await firestoreAdminRequest('PATCH', `users/${uid}/transactions/tx_ver_1`, {
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

  async function seedFamilyWithRoles(prefix) {
    const suffix = `${prefix}_${Date.now()}_${Math.floor(Math.random() * 10000)}`;
    const famId = `fam_${suffix}`;
    const ownerId = `owner_${suffix}`;
    const adminId = `admin_${suffix}`;
    const memberId = `member_${suffix}`;
    const outsiderId = `outsider_${suffix}`;
    const futureDate = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000);

    assert.equal(
      await firestoreRequest('PATCH', `families/${famId}`, {
        uid: ownerId,
        data: {
          id: famId,
          name: 'Gia đình Kiểm thử P0',
          spaceType: 'family',
          createdBy: ownerId,
          memberIds: [ownerId],
          memberRoles: { [ownerId]: 'owner' },
          memberNames: { [ownerId]: 'Trưởng nhóm' },
        },
      }),
      200,
    );

    const invCode = `FAM-${suffix.toUpperCase().replace(/[^A-Z0-9]/g, '').slice(0, 12)}`;
    assert.equal(
      await firestoreRequest('PATCH', `family_invites/${invCode}`, {
        uid: ownerId,
        data: {
          inviteCode: invCode,
          familyId: famId,
          createdBy: ownerId,
          maxUses: 5,
          usedCount: 0,
          revoked: false,
          status: 'active',
          expiresAt: futureDate,
        },
      }),
      200,
    );

    assert.equal(
      await firestoreCommitBatch(adminId, [
        {
          path: `family_invites/${invCode}`,
          exists: true,
          updateMask: ['usedCount', 'consumedBy', 'consumedAt', 'status', 'updatedAt'],
          data: {
            usedCount: 1,
            consumedBy: adminId,
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
            memberIds: [ownerId, adminId],
            memberRoles: { [ownerId]: 'owner', [adminId]: 'member' },
            memberNames: { [ownerId]: 'Trưởng nhóm', [adminId]: 'Quản trị B' },
            lastJoinedInviteCode: invCode,
            updatedAt: new Date(),
          },
        },
      ]),
      200,
    );

    assert.equal(
      await firestoreCommitBatch(memberId, [
        {
          path: `family_invites/${invCode}`,
          exists: true,
          updateMask: ['usedCount', 'consumedBy', 'consumedAt', 'status', 'updatedAt'],
          data: {
            usedCount: 2,
            consumedBy: memberId,
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
            memberIds: [ownerId, adminId, memberId],
            memberRoles: { [ownerId]: 'owner', [adminId]: 'member', [memberId]: 'member' },
            memberNames: { [ownerId]: 'Trưởng nhóm', [adminId]: 'Quản trị B', [memberId]: 'Thành viên C' },
            lastJoinedInviteCode: invCode,
            updatedAt: new Date(),
          },
        },
      ]),
      200,
    );

    // Promote adminId to 'admin'
    assert.equal(
      await firestoreCommitBatch(ownerId, [
        {
          path: `families/${famId}`,
          exists: true,
          updateMask: ['memberRoles', 'updatedAt'],
          data: {
            memberRoles: { [ownerId]: 'owner', [adminId]: 'admin', [memberId]: 'member' },
            updatedAt: new Date(),
          },
        },
      ]),
      200,
    );

    return { famId, ownerId, adminId, memberId, outsiderId, invCode };
  }

  it('6. P0 Attack 1 (AUD-001) — Blocks non-zero fund creation, phantom fund balance tampering, and requires atomic fund_audits + contributions', async () => {
    const { famId, ownerId, memberId } = await seedFamilyWithRoles('p0_fund');

    // Attack 1a: Create fund with forged initial balance > 0 -> 403
    assert.equal(
      await firestoreRequest('PATCH', `families/${famId}/funds/fund_bad`, {
        uid: ownerId,
        data: {
          id: 'fund_bad',
          ownerId,
          familyId: famId,
          name: 'Quỹ Ma',
          balanceMinor: 5000000,
          targetAmountMinor: 10000000,
        },
      }),
      403,
    );

    // Create valid zero-balance fund -> 200
    const createdAt = new Date();
    assert.equal(
      await firestoreRequest('PATCH', `families/${famId}/funds/fund_good`, {
        uid: ownerId,
        data: {
          id: 'fund_good',
          ownerId,
          familyId: famId,
          name: 'Quỹ Sinh hoạt',
          balanceMinor: 0,
          targetAmountMinor: 5000000,
          createdAt,
        },
      }),
      200,
    );

    // Attack 1b: Direct PATCH increasing balanceMinor without contribution/fund_audits -> 403
    assert.equal(
      await firestoreCommitBatch(memberId, [
        {
          path: `families/${famId}/funds/fund_good`,
          exists: true,
          updateMask: ['balanceMinor', 'updatedAt'],
          data: { balanceMinor: 9999999, updatedAt: new Date() },
        },
      ]),
      403,
    );

    // Attack 1c: Contribution + fund update with mismatched fund_audit delta -> 403
    assert.equal(
      await firestoreCommitBatch(memberId, [
        {
          path: `families/${famId}/funds/fund_good/contributions/c_bad`,
          exists: false,
          data: { id: 'c_bad', fundId: 'fund_good', contributorId: memberId, amountMinor: 200000 },
        },
        {
          path: `families/${famId}/funds/fund_good/fund_audits/fa_bad`,
          exists: false,
          data: {
            id: 'fa_bad',
            fundId: 'fund_good',
            actorId: memberId,
            previousBalanceMinor: 0,
            deltaMinor: 900000,
            newBalanceMinor: 900000,
          },
        },
        {
          path: `families/${famId}/funds/fund_good`,
          exists: true,
          updateMask: ['balanceMinor', 'lastAuditId', 'lastEventType', 'lastEventId'],
          data: {
            balanceMinor: 900000,
            lastAuditId: 'fa_bad',
            lastEventType: 'contribution',
            lastEventId: 'c_bad',
          },
        },
      ]),
      403,
    );

    // Legitimate atomic contribution batch -> 200
    assert.equal(
      await firestoreCommitBatch(memberId, [
        {
          path: `families/${famId}/funds/fund_good/contributions/c_1`,
          exists: false,
          data: { id: 'c_1', fundId: 'fund_good', contributorId: memberId, amountMinor: 500000 },
        },
        {
          path: `families/${famId}/funds/fund_good/fund_audits/fa_1`,
          exists: false,
          data: {
            id: 'fa_1',
            fundId: 'fund_good',
            actorId: memberId,
            previousBalanceMinor: 0,
            deltaMinor: 500000,
            newBalanceMinor: 500000,
          },
        },
        {
          path: `families/${famId}/funds/fund_good`,
          exists: true,
          updateMask: ['balanceMinor', 'lastAuditId', 'lastEventType', 'lastEventId', 'updatedAt'],
          data: {
            balanceMinor: 500000,
            lastAuditId: 'fa_1',
            lastEventType: 'contribution',
            lastEventId: 'c_1',
            updatedAt: new Date(),
          },
        },
      ]),
      200,
    );
  });

  it('7. P0 Attack 2 (AUD-001) — Enforces 9-state expense FSM, separation-of-duties (self-approval blocked), and immutable ledger deletes', async () => {
    const { famId, ownerId, adminId, memberId } = await seedFamilyWithRoles('p0_exp');
    const createdAt = new Date();
    assert.equal(
      await firestoreRequest('PATCH', `families/${famId}/funds/f_exp`, {
        uid: ownerId,
        data: {
          id: 'f_exp',
          ownerId,
          familyId: famId,
          name: 'Quỹ Chi Tiêu',
          balanceMinor: 0,
          targetAmountMinor: 2000000,
          createdAt,
        },
      }),
      200,
    );
    assert.equal(
      await firestoreCommitBatch(ownerId, [
        {
          path: `families/${famId}/funds/f_exp/contributions/c_seed`,
          exists: false,
          data: { id: 'c_seed', fundId: 'f_exp', contributorId: ownerId, amountMinor: 1000000 },
        },
        {
          path: `families/${famId}/funds/f_exp/fund_audits/fa_seed`,
          exists: false,
          data: {
            id: 'fa_seed',
            fundId: 'f_exp',
            actorId: ownerId,
            previousBalanceMinor: 0,
            deltaMinor: 1000000,
            newBalanceMinor: 1000000,
          },
        },
        {
          path: `families/${famId}/funds/f_exp`,
          exists: true,
          updateMask: ['balanceMinor', 'lastAuditId', 'lastEventType', 'lastEventId'],
          data: {
            balanceMinor: 1000000,
            lastAuditId: 'fa_seed',
            lastEventType: 'contribution',
            lastEventId: 'c_seed',
          },
        },
      ]),
      200,
    );

    // Owner creates a draft expense -> 200
    assert.equal(
      await firestoreRequest('PATCH', `families/${famId}/funds/f_exp/expenses/exp_1`, {
        uid: ownerId,
        data: {
          id: 'exp_1',
          fundId: 'f_exp',
          requesterId: ownerId,
          title: 'Mua đồ dùng nháp',
          amountMinor: 200000,
          status: 'draft',
          createdAt,
        },
      }),
      200,
    );
    // Edit draft title/amount and submit -> 200
    assert.equal(
      await firestoreCommitBatch(ownerId, [
        {
          path: `families/${famId}/funds/f_exp/expenses/exp_1`,
          exists: true,
          updateMask: ['title', 'amountMinor', 'status', 'updatedAt'],
          data: {
            title: 'Mua thực phẩm tuần',
            amountMinor: 300000,
            status: 'pending_approval',
            updatedAt: new Date(),
          },
        },
      ]),
      200,
    );

    // Attack 2a: Self-approval by requester (even though owner!) in multi-member family -> 403
    assert.equal(
      await firestoreCommitBatch(ownerId, [
        {
          path: `families/${famId}/funds/f_exp/expenses/exp_1`,
          exists: true,
          updateMask: ['status', 'decidedBy', 'updatedAt'],
          data: { status: 'approved', decidedBy: ownerId, updatedAt: new Date() },
        },
      ]),
      403,
    );

    // Attack 2b: Plain member trying to approve -> 403
    assert.equal(
      await firestoreCommitBatch(memberId, [
        {
          path: `families/${famId}/funds/f_exp/expenses/exp_1`,
          exists: true,
          updateMask: ['status', 'decidedBy', 'updatedAt'],
          data: { status: 'approved', decidedBy: memberId, updatedAt: new Date() },
        },
      ]),
      403,
    );

    // Attack 2c: Tampering amountMinor once past draft -> 403
    assert.equal(
      await firestoreCommitBatch(adminId, [
        {
          path: `families/${famId}/funds/f_exp/expenses/exp_1`,
          exists: true,
          updateMask: ['status', 'decidedBy', 'amountMinor', 'updatedAt'],
          data: { status: 'approved', decidedBy: adminId, amountMinor: 900000, updatedAt: new Date() },
        },
      ]),
      403,
    );

    // Manager B (adminId != ownerId) approves -> 200
    assert.equal(
      await firestoreCommitBatch(adminId, [
        {
          path: `families/${famId}/funds/f_exp/expenses/exp_1`,
          exists: true,
          updateMask: ['status', 'decidedBy', 'updatedAt'],
          data: { status: 'approved', decidedBy: adminId, updatedAt: new Date() },
        },
      ]),
      200,
    );

    // Execute approved -> executed atomically with fund debit & fund_audits -> 200
    assert.equal(
      await firestoreCommitBatch(adminId, [
        {
          path: `families/${famId}/funds/f_exp/fund_audits/fa_exec_1`,
          exists: false,
          data: {
            id: 'fa_exec_1',
            fundId: 'f_exp',
            actorId: adminId,
            previousBalanceMinor: 1000000,
            deltaMinor: -300000,
            newBalanceMinor: 700000,
          },
        },
        {
          path: `families/${famId}/funds/f_exp/expenses/exp_1`,
          exists: true,
          updateMask: ['status', 'executedBy', 'updatedAt'],
          data: { status: 'executed', executedBy: adminId, updatedAt: new Date() },
        },
        {
          path: `families/${famId}/funds/f_exp`,
          exists: true,
          updateMask: ['balanceMinor', 'lastAuditId', 'lastEventType', 'lastEventId'],
          data: {
            balanceMinor: 700000,
            lastAuditId: 'fa_exec_1',
            lastEventType: 'expense_executed',
            lastEventId: 'exp_1',
          },
        },
      ]),
      200,
    );

    // Regular member disputes executed expense -> 200
    assert.equal(
      await firestoreCommitBatch(memberId, [
        {
          path: `families/${famId}/funds/f_exp/expenses/exp_1`,
          exists: true,
          updateMask: ['status', 'disputedBy', 'disputeReason', 'updatedAt'],
          data: {
            status: 'disputed',
            disputedBy: memberId,
            disputeReason: 'Hóa đơn thiếu mục',
            updatedAt: new Date(),
          },
        },
      ]),
      200,
    );

    // Manager reverses disputed -> reversed atomically restoring balance -> 200
    assert.equal(
      await firestoreCommitBatch(adminId, [
        {
          path: `families/${famId}/funds/f_exp/fund_audits/fa_rev_1`,
          exists: false,
          data: {
            id: 'fa_rev_1',
            fundId: 'f_exp',
            actorId: adminId,
            previousBalanceMinor: 700000,
            deltaMinor: 300000,
            newBalanceMinor: 1000000,
          },
        },
        {
          path: `families/${famId}/funds/f_exp/expenses/exp_1`,
          exists: true,
          updateMask: ['status', 'updatedAt'],
          data: { status: 'reversed', updatedAt: new Date() },
        },
        {
          path: `families/${famId}/funds/f_exp`,
          exists: true,
          updateMask: ['balanceMinor', 'lastAuditId', 'lastEventType', 'lastEventId'],
          data: {
            balanceMinor: 1000000,
            lastAuditId: 'fa_rev_1',
            lastEventType: 'expense_reversed',
            lastEventId: 'exp_1',
          },
        },
      ]),
      200,
    );

    // Delete on expenses/contributions/fund_audits strictly denied -> 403
    assert.equal(await firestoreRequest('DELETE', `families/${famId}/funds/f_exp/expenses/exp_1`, { uid: ownerId }), 403);
    assert.equal(await firestoreRequest('DELETE', `families/${famId}/funds/f_exp/contributions/c_seed`, { uid: ownerId }), 403);
    assert.equal(await firestoreRequest('DELETE', `families/${famId}/funds/f_exp/fund_audits/fa_seed`, { uid: ownerId }), 403);
  });

  it('8. P0 Attack 3 (AUD-002) — Blocks unilateral debtor settlements, bank_transfer forgery, non-creditor reversals & duplicate reversal replay', async () => {
    const { famId, ownerId, memberId } = await seedFamilyWithRoles('p0_stl');

    // Attack 3a: Unilateral bank_transfer forgery -> 403
    assert.equal(
      await firestoreRequest('PATCH', `families/${famId}/settlements/st_bank_forge`, {
        uid: memberId,
        data: {
          id: 'st_bank_forge',
          familyId: famId,
          fromUserId: 'bank_transfer',
          toUserId: memberId,
          amountMinor: 500000,
          paymentCode: 'FAKE_BANK',
        },
      }),
      403,
    );

    // Attack 3b: Debtor creates direct settlement without creditor consent -> 403
    assert.equal(
      await firestoreRequest('PATCH', `families/${famId}/settlements/st_debtor_self`, {
        uid: memberId,
        data: {
          id: 'st_debtor_self',
          familyId: famId,
          fromUserId: memberId,
          toUserId: ownerId,
          amountMinor: 200000,
          paymentCode: 'PAY_FAKE',
        },
      }),
      403,
    );

    // Creditor creates direct settlement -> 200
    assert.equal(
      await firestoreRequest('PATCH', `families/${famId}/settlements/st_valid`, {
        uid: ownerId,
        data: {
          id: 'st_valid',
          familyId: famId,
          fromUserId: memberId,
          toUserId: ownerId,
          amountMinor: 200000,
          paymentCode: 'CASH_OK',
        },
      }),
      200,
    );

    // Attack 3c: Plain debtor tries to reverse settlement -> 403
    assert.equal(
      await firestoreRequest('PATCH', `families/${famId}/settlements/rev_st_valid`, {
        uid: memberId,
        data: {
          id: 'rev_st_valid',
          familyId: famId,
          fromUserId: ownerId,
          toUserId: memberId,
          amountMinor: 200000,
          paymentCode: 'REV_CASH_OK',
          reversalOfId: 'st_valid',
        },
      }),
      403,
    );

    // Creditor creates deterministic single reversal -> 200
    assert.equal(
      await firestoreRequest('PATCH', `families/${famId}/settlements/rev_st_valid`, {
        uid: ownerId,
        data: {
          id: 'rev_st_valid',
          familyId: famId,
          fromUserId: ownerId,
          toUserId: memberId,
          amountMinor: 200000,
          paymentCode: 'REV_CASH_OK',
          reversalOfId: 'st_valid',
        },
      }),
      200,
    );

    // Attack 3d: Reversing a reversal (double reversal chain) -> 403
    assert.equal(
      await firestoreRequest('PATCH', `families/${famId}/settlements/rev_rev_st_valid`, {
        uid: ownerId,
        data: {
          id: 'rev_rev_st_valid',
          familyId: famId,
          fromUserId: memberId,
          toUserId: ownerId,
          amountMinor: 200000,
          paymentCode: 'REV_2',
          reversalOfId: 'rev_st_valid',
        },
      }),
      403,
    );
  });

  it('9. P0 Attack 4 (AUD-003) — Enforces member shares on split_bills & blocks deleting settled or locked bills', async () => {
    const { famId, ownerId, memberId, outsiderId } = await seedFamilyWithRoles('p0_bill');

    // Attack 4a: Non-member participant in sharesByUserId -> 403
    assert.equal(
      await firestoreRequest('PATCH', `families/${famId}/split_bills/bill_bad_member`, {
        uid: ownerId,
        data: {
          id: 'bill_bad_member',
          familyId: famId,
          title: 'Tiền rác',
          paidByUserId: ownerId,
          totalAmountMinor: 100000,
          sharesByUserId: { [ownerId]: 50000, [outsiderId]: 50000 },
          status: 'open',
        },
      }),
      403,
    );

    // Attack 4b: Create already settled bill -> 403
    assert.equal(
      await firestoreRequest('PATCH', `families/${famId}/split_bills/bill_settled_create`, {
        uid: ownerId,
        data: {
          id: 'bill_settled_create',
          familyId: famId,
          title: 'Hóa đơn đóng sẵn',
          paidByUserId: ownerId,
          totalAmountMinor: 100000,
          sharesByUserId: { [ownerId]: 50000, [memberId]: 50000 },
          status: 'settled',
        },
      }),
      403,
    );

    // Valid open bill -> update to settled -> DELETE must be DENIED (403) even for owner!
    assert.equal(
      await firestoreRequest('PATCH', `families/${famId}/split_bills/bill_lock`, {
        uid: ownerId,
        data: {
          id: 'bill_lock',
          familyId: famId,
          title: 'Tiền điện',
          paidByUserId: ownerId,
          totalAmountMinor: 300000,
          sharesByUserId: { [ownerId]: 150000, [memberId]: 150000 },
          status: 'open',
        },
      }),
      200,
    );
    assert.equal(
      await firestoreCommitBatch(ownerId, [
        {
          path: `families/${famId}/split_bills/bill_lock`,
          exists: true,
          updateMask: ['status'],
          data: { status: 'settled' },
        },
      ]),
      200,
    );
    assert.equal(
      await firestoreRequest('DELETE', `families/${famId}/split_bills/bill_lock`, { uid: ownerId }),
      403,
    );
  });

  it('10. P0 Attack 5 & 6 (AUD-004, AUD-005) — Blocks availability/doc hijacks, pre-seeded ghosts, and banned member rejoin', async () => {
    const { famId, ownerId, adminId, memberId, invCode } = await seedFamilyWithRoles('p0_rbac');

    // Attack 5a: memberId creates availability, adminId CANNOT hijack/update it -> 403
    assert.equal(
      await firestoreRequest('PATCH', `families/${famId}/availability/slot_c`, {
        uid: memberId,
        data: { id: 'slot_c', ownerId: memberId, label: 'Rảnh tối' },
      }),
      200,
    );
    assert.equal(
      await firestoreCommitBatch(adminId, [
        {
          path: `families/${famId}/availability/slot_c`,
          exists: true,
          updateMask: ['label'],
          data: { label: 'Bị sửa trộm' },
        },
      ]),
      403,
    );

    // Attack 5b: memberId uploads doc, another non-manager member CANNOT overwrite or forge uploadedBy
    assert.equal(
      await firestoreRequest('PATCH', `families/${famId}/documents/doc_1`, {
        uid: adminId,
        data: { id: 'doc_1', familyId: famId, uploadedBy: adminId, title: 'Giấy tờ xe' },
      }),
      200,
    );
    assert.equal(
      await firestoreCommitBatch(memberId, [
        {
          path: `families/${famId}/documents/doc_1`,
          exists: true,
          updateMask: ['title'],
          data: { title: 'Sửa trái phép' },
        },
      ]),
      403,
    );

    // Attack 6a: Pre-seeded ghost members on create -> 403
    assert.equal(
      await firestoreRequest('PATCH', `families/fam_ghost_${Date.now()}`, {
        uid: ownerId,
        data: {
          id: 'fam_ghost',
          name: 'Nhóm Ma',
          createdBy: ownerId,
          memberIds: [ownerId, 'ghost_uid'],
          memberRoles: { [ownerId]: 'owner', ghost_uid: 'admin' },
        },
      }),
      403,
    );

    // Attack 6b: Owner removes & bans memberId -> memberId CANNOT rejoin even with active invCode -> 403
    assert.equal(
      await firestoreCommitBatch(ownerId, [
        {
          path: `families/${famId}`,
          exists: true,
          updateMask: ['memberIds', 'memberRoles', 'memberNames', 'bannedUserIds', 'lastRemovedMemberId'],
          data: {
            memberIds: [ownerId, adminId],
            memberRoles: { [ownerId]: 'owner', [adminId]: 'admin' },
            memberNames: { [ownerId]: 'Trưởng nhóm', [adminId]: 'Quản trị B' },
            bannedUserIds: [memberId],
            lastRemovedMemberId: memberId,
          },
        },
      ]),
      200,
    );
    assert.equal(
      await firestoreCommitBatch(memberId, [
        {
          path: `family_invites/${invCode}`,
          exists: true,
          updateMask: ['usedCount', 'consumedBy', 'consumedAt', 'status', 'updatedAt'],
          data: {
            usedCount: 3,
            consumedBy: memberId,
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
            memberIds: [ownerId, adminId, memberId],
            memberRoles: { [ownerId]: 'owner', [adminId]: 'admin', [memberId]: 'member' },
            memberNames: { [ownerId]: 'Trưởng nhóm', [adminId]: 'Quản trị B', [memberId]: 'Quay lại' },
            lastJoinedInviteCode: invCode,
            updatedAt: new Date(),
          },
        },
      ]),
      403,
    );
  });

  it('11. P0 Attack 7 & 8 (AUD-010, AUD-021) — Blocks wallet audit replay/math skew, extended verified tx lock, and monotonic deletion lock', async () => {
    const uid = `u_p0_ledger_${Date.now()}`;
    assert.equal(
      await firestoreRequest('PATCH', `users/${uid}`, {
        uid,
        data: { id: uid, fullName: 'Minh', deletionInProgress: false },
      }),
      200,
    );
    assert.equal(
      await firestoreRequest('PATCH', `users/${uid}/wallets/w_1`, {
        uid,
        data: { id: 'w_1', ownerId: uid, name: 'Ví Chính', balanceMinor: 1000000 },
      }),
      200,
    );

    // Valid audit_1 -> 200
    assert.equal(
      await firestoreCommitBatch(uid, [
        {
          path: `users/${uid}/ledger_audits/aud_1`,
          exists: false,
          data: {
            id: 'aud_1',
            ownerId: uid,
            walletId: 'w_1',
            previousBalanceMinor: 1000000,
            deltaMinor: -200000,
            newBalanceMinor: 800000,
          },
        },
        {
          path: `users/${uid}/wallets/w_1`,
          exists: true,
          updateMask: ['balanceMinor', 'lastAuditId', 'updatedAt'],
          data: { balanceMinor: 800000, lastAuditId: 'aud_1', updatedAt: new Date() },
        },
      ]),
      200,
    );

    // Attack 7a: Wallet update reusing existing lastAuditId (`aud_1`) -> 403
    assert.equal(
      await firestoreCommitBatch(uid, [
        {
          path: `users/${uid}/wallets/w_1`,
          exists: true,
          updateMask: ['balanceMinor', 'lastAuditId', 'updatedAt'],
          data: { balanceMinor: 9999999, lastAuditId: 'aud_1', updatedAt: new Date() },
        },
      ]),
      403,
    );

    // Attack 7b: Wallet update with inconsistent audit math -> 403
    assert.equal(
      await firestoreCommitBatch(uid, [
        {
          path: `users/${uid}/ledger_audits/aud_bad_math`,
          exists: false,
          data: {
            id: 'aud_bad_math',
            ownerId: uid,
            walletId: 'w_1',
            previousBalanceMinor: 800000,
            deltaMinor: 100000,
            newBalanceMinor: 5000000,
          },
        },
        {
          path: `users/${uid}/wallets/w_1`,
          exists: true,
          updateMask: ['balanceMinor', 'lastAuditId', 'updatedAt'],
          data: { balanceMinor: 5000000, lastAuditId: 'aud_bad_math', updatedAt: new Date() },
        },
      ]),
      403,
    );

    // Attack 7c: Verified tx extended immutable fields (occurredAt, balanceAfterMinor, monthKey)
    const txTime = new Date();
    const verTx = {
      id: 'tx_ext_lock',
      ownerId: uid,
      walletId: 'w_1',
      kind: 'expense',
      amountMinor: 200000,
      currencyCode: 'VND',
      verificationStatus: 'VERIFIED',
      monthKey: '2026-11',
      occurredAt: txTime,
      balanceAfterMinor: 800000,
      isRefund: false,
    };
    assert.equal(
      await firestoreRequest('PATCH', `users/${uid}/transactions/tx_ext_lock`, { uid, data: verTx }),
      200,
    );
    assert.equal(
      await firestoreCommitBatch(uid, [
        {
          path: `users/${uid}/transactions/tx_ext_lock`,
          exists: true,
          updateMask: ['monthKey'],
          data: { monthKey: '2026-01' },
        },
      ]),
      403,
    );
    assert.equal(
      await firestoreCommitBatch(uid, [
        {
          path: `users/${uid}/transactions/tx_ext_lock`,
          exists: true,
          updateMask: ['balanceAfterMinor'],
          data: { balanceAfterMinor: 9999999 },
        },
      ]),
      403,
    );

    // Attack 8 (AUD-021): Start deletion -> deletes audit -> cannot roll back deletionInProgress to false!
    assert.equal(
      await firestoreCommitBatch(uid, [
        {
          path: `users/${uid}`,
          exists: true,
          updateMask: ['deletionInProgress'],
          data: { deletionInProgress: true },
        },
      ]),
      200,
    );
    assert.equal(await firestoreRequest('DELETE', `users/${uid}/ledger_audits/aud_1`, { uid }), 200);
    assert.equal(
      await firestoreCommitBatch(uid, [
        {
          path: `users/${uid}`,
          exists: true,
          updateMask: ['deletionInProgress'],
          data: { deletionInProgress: false },
        },
      ]),
      403,
    );
  });

  it('12. P0 Attack 9, 10 & 11 (AUD-011, Cross-Collection & Concurrency) — Blocks ownerId mutation, assignee task escalation, verifies cross-wallet fund debit and concurrent optimistic lock', async () => {
    const { famId, ownerId, adminId, memberId } = await seedFamilyWithRoles('p0_conc');

    // Attack 9: Tasks assignee-only restricted fields & recurring task spawn
    assert.equal(
      await firestoreRequest('PATCH', `families/${famId}/tasks/task_1`, {
        uid: ownerId,
        data: {
          id: 'task_1',
          familyId: famId,
          createdBy: ownerId,
          assigneeId: memberId,
          title: 'Đóng tiền nước',
          status: 'accepted',
        },
      }),
      200,
    );
    // Assignee cannot tamper task title -> 403
    assert.equal(
      await firestoreCommitBatch(memberId, [
        {
          path: `families/${famId}/tasks/task_1`,
          exists: true,
          updateMask: ['status', 'title'],
          data: { status: 'done', title: 'Sửa tiêu đề' },
        },
      ]),
      403,
    );
    // Assignee completes task & spawns recurring occurrence with createdBy == memberId -> 200
    assert.equal(
      await firestoreCommitBatch(memberId, [
        {
          path: `families/${famId}/tasks/task_1`,
          exists: true,
          updateMask: ['status', 'updatedAt'],
          data: { status: 'done', updatedAt: new Date() },
        },
        {
          path: `families/${famId}/tasks/task_2`,
          exists: false,
          data: {
            id: 'task_2',
            familyId: famId,
            createdBy: memberId,
            originalCreatorId: ownerId,
            assigneeId: memberId,
            title: 'Đóng tiền nước',
            status: 'accepted',
          },
        },
      ]),
      200,
    );

    // Owner cannot mutate ownerId on shared_events/vehicles/bills -> 403; vehicle owner can delete maintenances -> 200
    assert.equal(
      await firestoreRequest('PATCH', `families/${famId}/shared_events/ev_1`, {
        uid: memberId,
        data: { id: 'ev_1', ownerId: memberId, title: 'Họp nhà' },
      }),
      200,
    );
    assert.equal(
      await firestoreCommitBatch(memberId, [
        {
          path: `families/${famId}/shared_events/ev_1`,
          exists: true,
          updateMask: ['ownerId'],
          data: { ownerId: adminId },
        },
      ]),
      403,
    );
    assert.equal(
      await firestoreRequest('PATCH', `families/${famId}/vehicles/veh_1`, {
        uid: memberId,
        data: { id: 'veh_1', ownerId: memberId, name: 'SH Mode' },
      }),
      200,
    );
    assert.equal(
      await firestoreCommitBatch(memberId, [
        {
          path: `families/${famId}/vehicles/veh_1`,
          exists: true,
          updateMask: ['ownerId'],
          data: { ownerId: adminId },
        },
      ]),
      403,
    );
    assert.equal(
      await firestoreRequest('PATCH', `families/${famId}/vehicles/veh_1/maintenances/m_1`, {
        uid: ownerId,
        data: { id: 'm_1', serviceTitle: 'Thay nhớt', costMinor: 150000 },
      }),
      200,
    );
    assert.equal(
      await firestoreRequest('DELETE', `families/${famId}/vehicles/veh_1/maintenances/m_1`, { uid: memberId }),
      200,
    );
    assert.equal(
      await firestoreRequest('PATCH', `families/${famId}/bills/bill_r1`, {
        uid: memberId,
        data: { id: 'bill_r1', ownerId: memberId, title: 'Internet' },
      }),
      200,
    );
    assert.equal(
      await firestoreCommitBatch(memberId, [
        {
          path: `families/${famId}/bills/bill_r1`,
          exists: true,
          updateMask: ['ownerId'],
          data: { ownerId: adminId },
        },
      ]),
      403,
    );

    // Attack 10: Atomic wallet -> family fund contribution in a single batch!
    assert.equal(
      await firestoreRequest('PATCH', `users/${memberId}/wallets/w_src`, {
        uid: memberId,
        data: { id: 'w_src', ownerId: memberId, name: 'Ví C', balanceMinor: 1000000 },
      }),
      200,
    );
    assert.equal(
      await firestoreRequest('PATCH', `families/${famId}/funds/f_shared`, {
        uid: ownerId,
        data: {
          id: 'f_shared',
          ownerId,
          familyId: famId,
          name: 'Quỹ Chung',
          balanceMinor: 0,
          targetAmountMinor: 5000000,
          createdAt: new Date(),
        },
      }),
      200,
    );
    assert.equal(
      await firestoreCommitBatch(memberId, [
        {
          path: `users/${memberId}/wallets/w_src`,
          exists: true,
          updateMask: ['balanceMinor', 'lastAuditId', 'updatedAt'],
          data: { balanceMinor: 750000, lastAuditId: 'aud_wf_1', updatedAt: new Date() },
        },
        {
          path: `users/${memberId}/ledger_audits/aud_wf_1`,
          exists: false,
          data: {
            id: 'aud_wf_1',
            ownerId: memberId,
            walletId: 'w_src',
            previousBalanceMinor: 1000000,
            deltaMinor: -250000,
            newBalanceMinor: 750000,
          },
        },
        {
          path: `users/${memberId}/transactions/tx_wf_1`,
          exists: false,
          data: {
            id: 'tx_wf_1',
            ownerId: memberId,
            walletId: 'w_src',
            amountMinor: 250000,
            currencyCode: 'VND',
            kind: 'expense',
          },
        },
        {
          path: `families/${famId}/funds/f_shared/contributions/c_wf_1`,
          exists: false,
          data: { id: 'c_wf_1', fundId: 'f_shared', contributorId: memberId, amountMinor: 250000 },
        },
        {
          path: `families/${famId}/funds/f_shared/fund_audits/fa_wf_1`,
          exists: false,
          data: {
            id: 'fa_wf_1',
            fundId: 'f_shared',
            actorId: memberId,
            previousBalanceMinor: 0,
            deltaMinor: 250000,
            newBalanceMinor: 250000,
          },
        },
        {
          path: `families/${famId}/funds/f_shared`,
          exists: true,
          updateMask: ['balanceMinor', 'lastAuditId', 'lastEventType', 'lastEventId'],
          data: {
            balanceMinor: 250000,
            lastAuditId: 'fa_wf_1',
            lastEventType: 'contribution',
            lastEventId: 'c_wf_1',
          },
        },
      ]),
      200,
    );

    // Attack 11: Concurrent optimistic transactions racing on same approved expense -> AT MOST ONE wins (no lost update / double debit)!
    assert.equal(
      await firestoreRequest('PATCH', `families/${famId}/funds/f_shared/expenses/exp_race`, {
        uid: memberId,
        data: {
          id: 'exp_race',
          fundId: 'f_shared',
          requesterId: memberId,
          title: 'Chi đua tranh',
          amountMinor: 200000,
          status: 'approved',
        },
      }),
      403, // Also confirms cannot create already-approved expense!
    );
    assert.equal(
      await firestoreRequest('PATCH', `families/${famId}/funds/f_shared/expenses/exp_race`, {
        uid: memberId,
        data: {
          id: 'exp_race',
          fundId: 'f_shared',
          requesterId: memberId,
          title: 'Chi đua tranh',
          amountMinor: 200000,
          status: 'pending_approval',
        },
      }),
      200,
    );
    assert.equal(
      await firestoreCommitBatch(adminId, [
        {
          path: `families/${famId}/funds/f_shared/expenses/exp_race`,
          exists: true,
          updateMask: ['status', 'decidedBy'],
          data: { status: 'approved', decidedBy: adminId },
        },
      ]),
      200,
    );

    const fundSnap = await firestoreGetDoc(ownerId, `families/${famId}/funds/f_shared`);
    assert.equal(fundSnap.status, 200);
    const snapUpdateTime = fundSnap.doc.updateTime;

    const raceWrites = (execUid, suffix) => [
      {
        path: `families/${famId}/funds/f_shared/fund_audits/fa_race_${suffix}`,
        exists: false,
        data: {
          id: `fa_race_${suffix}`,
          fundId: 'f_shared',
          actorId: execUid,
          previousBalanceMinor: 250000,
          deltaMinor: -200000,
          newBalanceMinor: 50000,
        },
      },
      {
        path: `families/${famId}/funds/f_shared/expenses/exp_race`,
        exists: true,
        updateMask: ['status', 'executedBy'],
        data: { status: 'executed', executedBy: execUid },
      },
      {
        path: `families/${famId}/funds/f_shared`,
        updateTime: snapUpdateTime,
        updateMask: ['balanceMinor', 'lastAuditId', 'lastEventType', 'lastEventId'],
        data: {
          balanceMinor: 50000,
          lastAuditId: `fa_race_${suffix}`,
          lastEventType: 'expense_executed',
          lastEventId: 'exp_race',
        },
      },
    ];

    const [r1, r2] = await Promise.all([
      firestoreCommitBatchResponse(ownerId, raceWrites(ownerId, 'a')),
      firestoreCommitBatchResponse(adminId, raceWrites(adminId, 'b')),
    ]);
    const okCount = [r1.status, r2.status].filter((s) => s === 200).length;
    assert.equal(okCount, 1, `Expected strictly 1 winner in concurrent debit race, got statuses [${r1.status}, ${r2.status}]`);
    const finalFund = await firestoreGetDoc(ownerId, `families/${famId}/funds/f_shared`);
    assert.equal(Number(finalFund.doc.fields.balanceMinor.integerValue), 50000);
  });

  it('13. Finding 2 — Enforces targeted invite recipient binding (inviteeUid, verified inviteeEmail, intendedRecipientHash) & atomic member/useCount updates', async () => {
    const suffix = `f2_${Date.now()}`;
    const famId = `fam_${suffix}`;
    const ownerId = `owner_${suffix}`;
    const futureDate = new Date(Date.now() + 24 * 3600 * 1000);

    assert.equal(
      await firestoreRequest('PATCH', `families/${famId}`, {
        uid: ownerId,
        data: {
          id: famId,
          name: 'Nhóm Đích Danh',
          createdBy: ownerId,
          memberIds: [ownerId],
          memberRoles: { [ownerId]: 'owner' },
          memberNames: { [ownerId]: 'Minh' },
        },
      }),
      200,
    );

    // 13a. Targeted invite using intendedRecipientHash (zero raw PII) for email lan@lifeos.vn
    const hashCode = `FAM-HASH-${suffix}`;
    const lanHash = sha256Hex('lan@lifeos.vn');
    assert.equal(
      await firestoreRequest('PATCH', `family_invites/${hashCode}`, {
        uid: ownerId,
        data: {
          inviteCode: hashCode,
          familyId: famId,
          createdBy: ownerId,
          inviteKind: 'targeted',
          isTargeted: true,
          intendedRecipientHash: lanHash,
          maxUses: 1,
          usedCount: 0,
          revoked: false,
          status: 'active',
          expiresAt: futureDate,
        },
      }),
      200,
    );

    // Helper for join batch (preserves prior memberNames so unchangedMapExceptSelfJoin holds)
    const knownMemberNames = { [ownerId]: 'Minh' };
    const joinWrites = (joinUid, joinName, code, prevMembers, nextUsed, nextStatus) => [
      {
        path: `family_invites/${code}`,
        exists: true,
        updateMask: ['usedCount', 'consumedBy', 'consumedAt', 'status', 'updatedAt'],
        data: {
          usedCount: nextUsed,
          consumedBy: joinUid,
          consumedAt: new Date(),
          status: nextStatus,
          updatedAt: new Date(),
        },
      },
      {
        path: `families/${famId}`,
        exists: true,
        updateMask: ['memberIds', 'memberRoles', 'memberNames', 'lastJoinedInviteCode', 'updatedAt'],
        data: {
          memberIds: [...prevMembers, joinUid],
          memberRoles: Object.fromEntries([
            ...prevMembers.map((id) => [id, id === ownerId ? 'owner' : 'member']),
            [joinUid, 'member'],
          ]),
          memberNames: Object.fromEntries([
            ...prevMembers.map((id) => [id, knownMemberNames[id] ?? id]),
            [joinUid, joinName],
          ]),
          lastJoinedInviteCode: code,
          updatedAt: new Date(),
        },
      },
    ];

    // Unverified email with matching address MUST BE DENIED (403)
    assert.equal(
      await firestoreCommitBatch(
        { uid: `u_unver_${suffix}`, claims: { email: 'lan@lifeos.vn', email_verified: false } },
        joinWrites(`u_unver_${suffix}`, 'Lan Unverified', hashCode, [ownerId], 1, 'consumed'),
      ),
      403,
    );

    // Different user with verified wrong email MUST BE DENIED (403)
    assert.equal(
      await firestoreCommitBatch(
        { uid: `u_other_${suffix}`, claims: { email: 'intruder@lifeos.vn', email_verified: true } },
        joinWrites(`u_other_${suffix}`, 'Intruder', hashCode, [ownerId], 1, 'consumed'),
      ),
      403,
    );

    // Non-atomic: incrementing invite usedCount WITHOUT updating family memberIds MUST BE DENIED (403)
    const lanUid = `u_lan_${suffix}`;
    assert.equal(
      await firestoreCommitBatch(
        { uid: lanUid, claims: { email: 'Lan@LifeOS.vn', email_verified: true } },
        [joinWrites(lanUid, 'Lan', hashCode, [ownerId], 1, 'consumed')[0]],
      ),
      403,
    );

    // Non-atomic: updating family memberIds WITHOUT incrementing invite usedCount MUST BE DENIED (403)
    assert.equal(
      await firestoreCommitBatch(
        { uid: lanUid, claims: { email: 'Lan@LifeOS.vn', email_verified: true } },
        [joinWrites(lanUid, 'Lan', hashCode, [ownerId], 1, 'consumed')[1]],
      ),
      403,
    );

    // Verified matching email (case-insensitive) in atomic batch SUCCEEDS (200)
    assert.equal(
      await firestoreCommitBatch(
        { uid: lanUid, claims: { email: 'Lan@LifeOS.vn', email_verified: true } },
        joinWrites(lanUid, 'Lan', hashCode, [ownerId], 1, 'consumed'),
      ),
      200,
    );
    knownMemberNames[lanUid] = 'Lan';

    // 13b. Targeted invite with inviteeUid: only matching UID joins; matching email with different UID is denied
    const uidCode = `FAM-UID-${suffix}`;
    const targetUid = `u_uidtarget_${suffix}`;
    assert.equal(
      await firestoreRequest('PATCH', `family_invites/${uidCode}`, {
        uid: ownerId,
        data: {
          inviteCode: uidCode,
          familyId: famId,
          createdBy: ownerId,
          inviteKind: 'targeted',
          isTargeted: true,
          inviteeUid: targetUid,
          inviteeEmail: 'bob@lifeos.vn',
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
      await firestoreCommitBatch(
        { uid: `u_wrong_uid_${suffix}`, claims: { email: 'bob@lifeos.vn', email_verified: true } },
        joinWrites(`u_wrong_uid_${suffix}`, 'Wrong UID', uidCode, [ownerId, lanUid], 1, 'consumed'),
      ),
      403,
    );
    assert.equal(
      await firestoreCommitBatch(
        { uid: targetUid, claims: {} },
        joinWrites(targetUid, 'Bob', uidCode, [ownerId, lanUid], 1, 'consumed'),
      ),
      200,
    );
    knownMemberNames[targetUid] = 'Bob';

    // 13c. Targeted invite with inviteeEmail (no inviteeUid): requires email_verified == true and lowercased match
    const emailCode = `FAM-MAIL-${suffix}`;
    const mailUid = `u_mail_${suffix}`;
    assert.equal(
      await firestoreRequest('PATCH', `family_invites/${emailCode}`, {
        uid: ownerId,
        data: {
          inviteCode: emailCode,
          familyId: famId,
          createdBy: ownerId,
          inviteKind: 'targeted',
          isTargeted: true,
          inviteeEmail: 'Mai.Nguyen@LifeOS.vn',
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
      await firestoreCommitBatch(
        { uid: mailUid, claims: { email: 'mai.nguyen@lifeos.vn', email_verified: false } },
        joinWrites(mailUid, 'Mai', emailCode, [ownerId, lanUid, targetUid], 1, 'consumed'),
      ),
      403,
    );
    assert.equal(
      await firestoreCommitBatch(
        { uid: mailUid, claims: { email: 'mai.nguyen@lifeos.vn', email_verified: true } },
        joinWrites(mailUid, 'Mai', emailCode, [ownerId, lanUid, targetUid], 1, 'consumed'),
      ),
      200,
    );
    knownMemberNames[mailUid] = 'Mai';

    // 13d. Open invite still works without email verification
    const openCode = `FAM-OPEN-${suffix}`;
    const openUid = `u_open_${suffix}`;
    assert.equal(
      await firestoreRequest('PATCH', `family_invites/${openCode}`, {
        uid: ownerId,
        data: {
          inviteCode: openCode,
          familyId: famId,
          createdBy: ownerId,
          inviteKind: 'oneTime',
          isTargeted: false,
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
      await firestoreCommitBatch(
        openUid,
        joinWrites(openUid, 'Open Joiner', openCode, [ownerId, lanUid, targetUid, mailUid], 1, 'consumed'),
      ),
      200,
    );
  });

  it('14. Finding 7 — Enforces split_bills shares integer >= 0, sum == totalAmountMinor & max 20 participants on create AND update', async () => {
    const { famId, ownerId, adminId, memberId } = await seedFamilyWithRoles('f7_split');

    // Valid 100,000 VND split among 3 to the last dong (33,334 + 33,333 + 33,333 = 100,000) -> 200
    assert.equal(
      await firestoreRequest('PATCH', `families/${famId}/split_bills/bill_100k`, {
        uid: ownerId,
        data: {
          id: 'bill_100k',
          familyId: famId,
          title: 'Cà phê 3 người',
          paidByUserId: ownerId,
          totalAmountMinor: 100000,
          sharesByUserId: { [ownerId]: 33334, [adminId]: 33333, [memberId]: 33333 },
          status: 'open',
        },
      }),
      200,
    );

    // Mismatched sum on create (33,333 * 3 = 99,999 != 100,000) -> DENIED (403)
    assert.equal(
      await firestoreRequest('PATCH', `families/${famId}/split_bills/bill_bad_sum`, {
        uid: ownerId,
        data: {
          id: 'bill_bad_sum',
          familyId: famId,
          title: 'Lệch 1 đồng',
          paidByUserId: ownerId,
          totalAmountMinor: 100000,
          sharesByUserId: { [ownerId]: 33333, [adminId]: 33333, [memberId]: 33333 },
          status: 'open',
        },
      }),
      403,
    );

    // Negative share on create -> DENIED (403)
    assert.equal(
      await firestoreRequest('PATCH', `families/${famId}/split_bills/bill_neg`, {
        uid: ownerId,
        data: {
          id: 'bill_neg',
          familyId: famId,
          title: 'Phần âm',
          paidByUserId: ownerId,
          totalAmountMinor: 100000,
          sharesByUserId: { [ownerId]: 120000, [memberId]: -20000 },
          status: 'open',
        },
      }),
      403,
    );

    // Non-integer float share on create -> DENIED (403)
    assert.equal(
      await firestoreRequest('PATCH', `families/${famId}/split_bills/bill_float`, {
        uid: ownerId,
        data: {
          id: 'bill_float',
          familyId: famId,
          title: 'Phần số lẻ thập phân',
          paidByUserId: ownerId,
          totalAmountMinor: 100000,
          sharesByUserId: { [ownerId]: 50000.5, [memberId]: 49999.5 },
          status: 'open',
        },
      }),
      403,
    );

    // Mismatched sum on update (changing totalAmountMinor without adjusting shares) -> DENIED (403)
    assert.equal(
      await firestoreCommitBatch(ownerId, [
        {
          path: `families/${famId}/split_bills/bill_100k`,
          exists: true,
          updateMask: ['totalAmountMinor'],
          data: { totalAmountMinor: 150000 },
        },
      ]),
      403,
    );

    // Valid update adjusting both totalAmountMinor and sharesByUserId so sum matches -> 200
    assert.equal(
      await firestoreCommitBatch(ownerId, [
        {
          path: `families/${famId}/split_bills/bill_100k`,
          exists: true,
          updateMask: ['totalAmountMinor', 'sharesByUserId'],
          data: {
            totalAmountMinor: 150000,
            sharesByUserId: { [ownerId]: 50000, [adminId]: 50000, [memberId]: 50000 },
          },
        },
      ]),
      200,
    );

    // Exceeding max 20 participants -> DENIED (403)
    const fam21Id = `fam_21_${Date.now()}`;
    const m21 = Array.from({ length: 21 }, (_, i) => `m21_${i}`);
    assert.equal(
      await firestoreRequest('PATCH', `families/${fam21Id}`, {
        uid: m21[0],
        data: {
          id: fam21Id,
          name: 'Nhóm 21 người',
          createdBy: m21[0],
          memberIds: [m21[0]],
          memberRoles: { [m21[0]]: 'owner' },
        },
      }),
      200,
    );
    const inv21 = `FAM-21-${Date.now()}`;
    assert.equal(
      await firestoreRequest('PATCH', `family_invites/${inv21}`, {
        uid: m21[0],
        data: {
          inviteCode: inv21,
          familyId: fam21Id,
          createdBy: m21[0],
          maxUses: 25,
          usedCount: 0,
          revoked: false,
          status: 'active',
          expiresAt: new Date(Date.now() + 86400000),
        },
      }),
      200,
    );
    const curMembers = [m21[0]];
    const curRoles = { [m21[0]]: 'owner' };
    for (let i = 1; i < 21; i++) {
      curMembers.push(m21[i]);
      curRoles[m21[i]] = 'member';
      assert.equal(
        await firestoreCommitBatch(m21[i], [
          {
            path: `family_invites/${inv21}`,
            exists: true,
            updateMask: ['usedCount', 'consumedBy', 'consumedAt', 'status', 'updatedAt'],
            data: {
              usedCount: i,
              consumedBy: m21[i],
              consumedAt: new Date(),
              status: 'active',
              updatedAt: new Date(),
            },
          },
          {
            path: `families/${fam21Id}`,
            exists: true,
            updateMask: ['memberIds', 'memberRoles', 'lastJoinedInviteCode', 'updatedAt'],
            data: {
              memberIds: [...curMembers],
              memberRoles: { ...curRoles },
              lastJoinedInviteCode: inv21,
              updatedAt: new Date(),
            },
          },
        ]),
        200,
      );
    }
    const shares21 = Object.fromEntries(m21.map((id) => [id, 10000]));
    assert.equal(
      await firestoreRequest('PATCH', `families/${fam21Id}/split_bills/bill_21`, {
        uid: m21[0],
        data: {
          id: 'bill_21',
          familyId: fam21Id,
          title: 'Quá 20 người',
          paidByUserId: m21[0],
          totalAmountMinor: 210000,
          sharesByUserId: shares21,
          status: 'open',
        },
      }),
      403,
    );
    // 20 participants exact sum -> 200
    const shares20 = Object.fromEntries(m21.slice(0, 20).map((id) => [id, 10000]));
    assert.equal(
      await firestoreRequest('PATCH', `families/${fam21Id}/split_bills/bill_20`, {
        uid: m21[0],
        data: {
          id: 'bill_20',
          familyId: fam21Id,
          title: 'Đúng 20 người',
          paidByUserId: m21[0],
          totalAmountMinor: 200000,
          sharesByUserId: shares20,
          status: 'open',
        },
      }),
      200,
    );
  });

  it('15. M7 — Blocks client-forged verifiedByBank / bankWebhook / bankApi on create & escalation on update while permitting metadata edits', async () => {
    const uid = `m7_user_${Date.now()}`;
    const otherUid = `m7_other_${Date.now()}`;

    // Client create with verification: 'verifiedByBank' -> DENIED (403)
    assert.equal(
      await firestoreRequest('PATCH', `users/${uid}/transactions/tx_forged_vbb`, {
        uid,
        data: {
          id: 'tx_forged_vbb',
          ownerId: uid,
          walletId: 'w_1',
          kind: 'income',
          direction: 'credit',
          amountMinor: 1000000,
          currencyCode: 'VND',
          verification: 'verifiedByBank',
          sourceKind: 'manual',
        },
      }),
      403,
    );

    // Client create with sourceKind: 'bankWebhook' or 'bankApi' -> DENIED (403)
    for (const sk of ['bankWebhook', 'bankApi']) {
      assert.equal(
        await firestoreRequest('PATCH', `users/${uid}/transactions/tx_forged_${sk}`, {
          uid,
          data: {
            id: `tx_forged_${sk}`,
            ownerId: uid,
            walletId: 'w_1',
            kind: 'income',
            direction: 'credit',
            amountMinor: 500000,
            currencyCode: 'VND',
            verification: 'provisional',
            sourceKind: sk,
          },
        }),
        403,
        `Expected 403 when creating client tx with sourceKind='${sk}'`,
      );
    }

    // Valid client manual transaction -> 200
    const manualTx = {
      id: 'tx_manual_m7',
      ownerId: uid,
      walletId: 'w_1',
      kind: 'expense',
      direction: 'debit',
      amountMinor: 150000,
      currencyCode: 'VND',
      currency: 'VND',
      verification: 'userConfirmed',
      verificationStatus: 'USER_CONFIRMED',
      sourceKind: 'manual',
      categoryName: 'Ăn uống',
      note: 'Cơm trưa',
    };
    assert.equal(
      await firestoreRequest('PATCH', `users/${uid}/transactions/tx_manual_m7`, {
        uid,
        data: manualTx,
      }),
      200,
    );

    // Client update escalating manual tx to verification='verifiedByBank' -> DENIED (403)
    assert.equal(
      await firestoreRequest('PATCH', `users/${uid}/transactions/tx_manual_m7`, {
        uid,
        data: { ...manualTx, verification: 'verifiedByBank' },
      }),
      403,
    );

    // Client update escalating sourceKind to 'bankWebhook' or 'bankApi' -> DENIED (403)
    assert.equal(
      await firestoreRequest('PATCH', `users/${uid}/transactions/tx_manual_m7`, {
        uid,
        data: { ...manualTx, sourceKind: 'bankWebhook' },
      }),
      403,
    );

    // Admin SDK seeds a genuine `verifiedByBank` + `bankWebhook` transaction -> 200
    const adminBankTx = {
      id: 'tx_admin_vbb',
      ownerId: uid,
      walletId: 'w_bank_1',
      kind: 'income',
      direction: 'credit',
      amountMinor: 2500000,
      currencyCode: 'VND',
      currency: 'VND',
      verification: 'verifiedByBank',
      verificationStatus: 'VERIFIED',
      sourceKind: 'bankWebhook',
      categoryId: 'cat_inc',
      categoryName: 'Thu nhập khác',
      merchant: 'VCB Chuyển khoản',
      note: 'Từ Admin SDK',
    };
    assert.equal(
      await firestoreAdminRequest('PATCH', `users/${uid}/transactions/tx_admin_vbb`, {
        data: adminBankTx,
      }),
      200,
    );

    // Client CANNOT mutate protected core fields on verifiedByBank tx -> 403
    for (const [field, badVal] of [
      ['verification', 'userConfirmed'],
      ['sourceKind', 'manual'],
      ['amountMinor', 9999999],
      ['direction', 'debit'],
      ['walletId', 'w_other'],
      ['currency', 'USD'],
      ['currencyCode', 'USD'],
    ]) {
      assert.equal(
        await firestoreRequest('PATCH', `users/${uid}/transactions/tx_admin_vbb`, {
          uid,
          data: { ...adminBankTx, [field]: badVal },
        }),
        403,
        `Expected 403 when mutating '${field}' on verifiedByBank tx`,
      );
    }

    // Owner CAN update user-editable metadata (`categoryId`, `categoryName`, `merchant`, `note`, `updatedAt`) -> 200
    assert.equal(
      await firestoreRequest('PATCH', `users/${uid}/transactions/tx_admin_vbb`, {
        uid,
        data: {
          ...adminBankTx,
          categoryId: 'cat_salary',
          categoryName: 'Lương & Thu nhập',
          merchant: 'Công ty ABC',
          note: 'Lương tháng 11',
          updatedAt: new Date(),
        },
      }),
      200,
    );

    // Other user still denied -> 403
    assert.equal(
      await firestoreRequest('GET', `users/${uid}/transactions/tx_admin_vbb`, { uid: otherUid }),
      403,
    );
  });

  it('16. H5 — Allows owner read/delete of daily_preferences, legacy medical cleanup paths & personal_funds/*/fund_audits while blocking other users and legacy writes', async () => {
    const uid = `h5_owner_${Date.now()}`;
    const otherUid = `h5_other_${Date.now()}`;

    // 16a. daily_preferences: owner can create/read/update/delete; other user denied
    assert.equal(
      await firestoreRequest('PATCH', `users/${uid}/daily_preferences/hydration_reminder`, {
        uid,
        data: { ownerId: uid, reminderEnabled: true, targetWaterMl: 2200 },
      }),
      200,
    );
    assert.equal(
      await firestoreRequest('GET', `users/${uid}/daily_preferences/hydration_reminder`, { uid }),
      200,
    );
    assert.equal(
      await firestoreRequest('GET', `users/${uid}/daily_preferences/hydration_reminder`, { uid: otherUid }),
      403,
    );
    assert.equal(
      await firestoreRequest('DELETE', `users/${uid}/daily_preferences/hydration_reminder`, { uid: otherUid }),
      403,
    );
    assert.equal(
      await firestoreRequest('DELETE', `users/${uid}/daily_preferences/hydration_reminder`, { uid }),
      200,
    );

    // 16b. Legacy medical cleanup paths (`medications`, `health_logs`, `medical_profiles`):
    //      Client create/update blocked (403); Admin seeds legacy docs -> owner can read & delete (200); other user denied (403)
    for (const col of ['medications', 'health_logs', 'medical_profiles']) {
      assert.equal(
        await firestoreRequest('PATCH', `users/${uid}/${col}/legacy_doc_1`, {
          uid,
          data: { id: 'legacy_doc_1', ownerId: uid, note: 'legacy' },
        }),
        403,
        `Expected client write to legacy path '${col}' to be denied (403)`,
      );

      assert.equal(
        await firestoreAdminRequest('PATCH', `users/${uid}/${col}/legacy_doc_1`, {
          data: { id: 'legacy_doc_1', ownerId: uid, note: 'legacy_seeded' },
        }),
        200,
      );

      assert.equal(
        await firestoreRequest('GET', `users/${uid}/${col}/legacy_doc_1`, { uid }),
        200,
      );
      assert.equal(
        await firestoreRequest('GET', `users/${uid}/${col}/legacy_doc_1`, { uid: otherUid }),
        403,
      );
      assert.equal(
        await firestoreRequest('DELETE', `users/${uid}/${col}/legacy_doc_1`, { uid: otherUid }),
        403,
      );
      assert.equal(
        await firestoreRequest('DELETE', `users/${uid}/${col}/legacy_doc_1`, { uid }),
        200,
      );
    }

    // 16c. personal_funds/{fundId}/fund_audits/{auditId}: owner can create/read/delete; updates blocked; other user denied
    assert.equal(
      await firestoreRequest('PATCH', `users/${uid}/personal_funds/pf_1`, {
        uid,
        data: { id: 'pf_1', ownerId: uid, name: 'Quỹ dự phòng', balanceMinor: 1000000 },
      }),
      200,
    );
    assert.equal(
      await firestoreRequest('PATCH', `users/${uid}/personal_funds/pf_1/fund_audits/fa_1`, {
        uid,
        data: { id: 'fa_1', ownerId: uid, deltaMinor: 1000000, newBalanceMinor: 1000000 },
      }),
      200,
    );
    assert.equal(
      await firestoreRequest('GET', `users/${uid}/personal_funds/pf_1/fund_audits/fa_1`, { uid }),
      200,
    );
    assert.equal(
      await firestoreRequest('GET', `users/${uid}/personal_funds/pf_1/fund_audits/fa_1`, { uid: otherUid }),
      403,
    );
    // Audit update is immutable (403)
    assert.equal(
      await firestoreCommitBatch(uid, [
        {
          path: `users/${uid}/personal_funds/pf_1/fund_audits/fa_1`,
          exists: true,
          updateMask: ['deltaMinor'],
          data: { deltaMinor: 999 },
        },
      ]),
      403,
    );
    assert.equal(
      await firestoreRequest('DELETE', `users/${uid}/personal_funds/pf_1/fund_audits/fa_1`, { uid: otherUid }),
      403,
    );
    assert.equal(
      await firestoreRequest('DELETE', `users/${uid}/personal_funds/pf_1/fund_audits/fa_1`, { uid }),
      200,
    );

    // 16d. Server-only account_deletion_jobs is locked from all client access -> 403
    assert.equal(
      await firestoreRequest('GET', `account_deletion_jobs/${uid}`, { uid }),
      403,
    );
    assert.equal(
      await firestoreRequest('PATCH', `account_deletion_jobs/${uid}`, {
        uid,
        data: { status: 'completed' },
      }),
      403,
    );
  });
});
