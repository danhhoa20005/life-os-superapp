import { describe, it } from 'node:test';
import assert from 'node:assert/strict';

const PROJECT_ID = 'demo-life-os';
const EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8188';
const BASE_URL = `http://${EMULATOR_HOST}/v1/projects/${PROJECT_ID}/databases/(default)/documents`;

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

function toFirestoreFields(obj) {
  const fields = {};
  for (const [k, v] of Object.entries(obj)) {
    if (typeof v === 'string') fields[k] = { stringValue: v };
    else if (typeof v === 'number') fields[k] = { integerValue: String(v) };
    else if (typeof v === 'boolean') fields[k] = { booleanValue: v };
    else if (Array.isArray(v)) {
      fields[k] = { arrayValue: { values: v.map((item) => ({ stringValue: String(item) })) } };
    } else if (v && typeof v === 'object') {
      fields[k] = { mapValue: { fields: toFirestoreFields(v) } };
    }
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

describe('Real Firebase Firestore Emulator — Full firestore.rules Verification', () => {
  it('1. Denies unauthenticated access across personal and family collections', async () => {
    assert.equal(await firestoreRequest('GET', 'users/user_a'), 403);
    assert.equal(await firestoreRequest('GET', 'families/fam_1'), 403);
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

  it('3. Blocks unauthorized role self-escalation on family join & revokes access on leave', async () => {
    assert.equal(
      await firestoreRequest('PATCH', 'families/fam_1', {
        uid: 'owner_1',
        data: {
          id: 'fam_1',
          name: 'Tổ ấm 1',
          createdBy: 'owner_1',
          memberIds: ['owner_1'],
          memberRoles: { owner_1: 'owner' },
        },
      }),
      200,
    );
    assert.equal(
      await firestoreRequest('PATCH', 'family_invites/FAM-JOIN99', {
        uid: 'owner_1',
        data: {
          inviteCode: 'FAM-JOIN99',
          familyId: 'fam_1',
          createdBy: 'owner_1',
        },
      }),
      200,
    );
    assert.equal(
      await firestoreRequest('PATCH', 'families/fam_1/funds/fund_1', {
        uid: 'owner_1',
        data: { id: 'fund_1', familyId: 'fam_1', name: 'Quỹ Tết', balanceMinor: 500000 },
      }),
      200,
    );

    // Attacker tries to join as 'owner' using valid invite code -> DENIED (403)!
    assert.equal(
      await firestoreRequest('PATCH', 'families/fam_1', {
        uid: 'user_2',
        data: {
          id: 'fam_1',
          name: 'Tổ ấm 1',
          createdBy: 'owner_1',
          memberIds: ['owner_1', 'user_2'],
          memberRoles: { owner_1: 'owner', user_2: 'owner' },
          lastJoinedInviteCode: 'FAM-JOIN99',
        },
      }),
      403,
    );

    // Legitimate join as 'member' -> SUCCEEDS (200)!
    assert.equal(
      await firestoreRequest('PATCH', 'families/fam_1', {
        uid: 'user_2',
        data: {
          id: 'fam_1',
          name: 'Tổ ấm 1',
          createdBy: 'owner_1',
          memberIds: ['owner_1', 'user_2'],
          memberRoles: { owner_1: 'owner', user_2: 'member' },
          lastJoinedInviteCode: 'FAM-JOIN99',
        },
      }),
      200,
    );

    // user_2 can now read shared fund and create positive-int split_bills & settlements
    assert.equal(
      await firestoreRequest('GET', 'families/fam_1/funds/fund_1', { uid: 'user_2' }),
      200,
    );
    assert.equal(
      await firestoreRequest('PATCH', 'families/fam_1/split_bills/bill_1', {
        uid: 'user_2',
        data: {
          id: 'bill_1',
          familyId: 'fam_1',
          title: 'Ăn tối & Nước giặt',
          paidByUserId: 'user_2',
          totalAmountMinor: 240000,
        },
      }),
      200,
    );
    assert.equal(
      await firestoreRequest('PATCH', 'families/fam_1/settlements/st_1', {
        uid: 'owner_1',
        data: {
          id: 'st_1',
          familyId: 'fam_1',
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
      await firestoreRequest('DELETE', 'families/fam_1/settlements/st_1', { uid: 'owner_1' }),
      403,
    );
    // Non-member outsider_9 is strictly denied reading split_bills (403!)
    assert.equal(
      await firestoreRequest('GET', 'families/fam_1/split_bills/bill_1', { uid: 'outsider_9' }),
      403,
    );

    // user_2 leaves family -> immediately denied reading shared fund (403)!
    assert.equal(
      await firestoreRequest('PATCH', 'families/fam_1', {
        uid: 'user_2',
        data: {
          id: 'fam_1',
          name: 'Tổ ấm 1',
          createdBy: 'owner_1',
          memberIds: ['owner_1'],
          memberRoles: { owner_1: 'owner' },
        },
      }),
      200,
    );
    assert.equal(
      await firestoreRequest('GET', 'families/fam_1/funds/fund_1', { uid: 'user_2' }),
      403,
    );
  });
});
