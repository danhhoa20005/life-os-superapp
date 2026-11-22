import { describe, it } from 'node:test';
import assert from 'node:assert/strict';

const PROJECT_ID = 'demo-life-os';
const AUTH_HOST = process.env.FIREBASE_AUTH_EMULATOR_HOST || '127.0.0.1:9199';
const FIRESTORE_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8188';

const AUTH_BASE = `http://${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts`;
const TOKEN_BASE = `http://${AUTH_HOST}/securetoken.googleapis.com/v1/token?key=demo-api-key`;
const FS_DOCS_BASE = `http://${FIRESTORE_HOST}/v1/projects/${PROJECT_ID}/databases/(default)/documents`;

async function authSignUp(email, password, displayName) {
  const res = await fetch(`${AUTH_BASE}:signUp?key=demo-api-key`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password, displayName, returnSecureToken: true }),
  });
  const body = await res.json();
  assert.equal(res.status, 200, `Auth signUp failed: ${JSON.stringify(body)}`);
  return body;
}

async function authSignIn(email, password) {
  const res = await fetch(`${AUTH_BASE}:signInWithPassword?key=demo-api-key`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password, returnSecureToken: true }),
  });
  const body = await res.json();
  assert.equal(res.status, 200, `Auth signIn failed: ${JSON.stringify(body)}`);
  return body;
}

async function authRefreshSession(refreshToken) {
  const res = await fetch(TOKEN_BASE, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `grant_type=refresh_token&refresh_token=${encodeURIComponent(refreshToken)}`,
  });
  const body = await res.json();
  assert.equal(res.status, 200, `Token refresh failed: ${JSON.stringify(body)}`);
  return body;
}

function toFirestoreValue(v) {
  if (v === null || v === undefined) return { nullValue: null };
  if (typeof v === 'string') {
    if (/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/.test(v)) {
      return { timestampValue: v };
    }
    return { stringValue: v };
  }
  if (typeof v === 'number') {
    return Number.isInteger(v) ? { integerValue: String(v) } : { doubleValue: v };
  }
  if (typeof v === 'boolean') return { booleanValue: v };
  if (Array.isArray(v)) {
    return { arrayValue: { values: v.map(toFirestoreValue) } };
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

async function fsDoc(method, docPath, { idToken = null, data = null, query = '' } = {}) {
  const headers = { 'Content-Type': 'application/json' };
  if (idToken) headers.Authorization = `Bearer ${idToken}`;
  const url = `${FS_DOCS_BASE}/${docPath}${query}`;
  const res = await fetch(url, {
    method,
    headers,
    body: data ? JSON.stringify({ fields: toFirestoreFields(data) }) : undefined,
  });
  const text = await res.text();
  let json = null;
  try {
    json = text ? JSON.parse(text) : null;
  } catch {
    json = { raw: text };
  }
  return { status: res.status, body: json };
}

async function fsRunQuery(parentDocPath, structuredQuery, idToken) {
  const headers = {
    'Content-Type': 'application/json',
    Authorization: `Bearer ${idToken}`,
  };
  const url = `${FS_DOCS_BASE}/${parentDocPath}:runQuery`;
  const res = await fetch(url, {
    method: 'POST',
    headers,
    body: JSON.stringify({ structuredQuery }),
  });
  const json = await res.json();
  return { status: res.status, body: json };
}

describe('PHẦN 12 — Full 15-Scenario Live Firebase Auth + Cloud Firestore Emulator Suite', () => {
  let userA;
  let userB;
  let outsiderC;

  it('Scenarios 1, 2 & 3: Account Sign-Up, Password Sign-In, Session Refresh & User Profile Creation', async () => {
    const signUpA = await authSignUp('minh.e2e@lifeos.vn', 'StrongPass123!', 'Nguyễn Minh');
    userA = await authSignIn('minh.e2e@lifeos.vn', 'StrongPass123!');
    assert.equal(userA.localId, signUpA.localId);

    const refreshedA = await authRefreshSession(userA.refreshToken);
    assert.equal(refreshedA.user_id, userA.localId);

    userB = await authSignUp('lan.e2e@lifeos.vn', 'StrongPass123!', 'Trần Lan');
    outsiderC = await authSignUp('outsider.e2e@lifeos.vn', 'StrongPass123!', 'Người Lạ');

    const profA = await fsDoc('PATCH', `users/${userA.localId}`, {
      idToken: userA.idToken,
      data: {
        id: userA.localId,
        email: 'minh.e2e@lifeos.vn',
        fullName: 'Nguyễn Minh',
        timezone: 'Asia/Ho_Chi_Minh',
        onboardingCompleted: true,
      },
    });
    assert.equal(profA.status, 200);

    const leakAttempt = await fsDoc('PATCH', `users/${userB.localId}`, {
      idToken: userB.idToken,
      data: {
        id: userB.localId,
        email: 'lan.e2e@lifeos.vn',
        password: 'LeakedPlaintextPassword',
      },
    });
    assert.equal(leakAttempt.status, 403);

    const profB = await fsDoc('PATCH', `users/${userB.localId}`, {
      idToken: userB.idToken,
      data: {
        id: userB.localId,
        email: 'lan.e2e@lifeos.vn',
        fullName: 'Trần Lan',
        onboardingCompleted: true,
      },
    });
    assert.equal(profB.status, 200);
  });

  it('Scenarios 4, 5, 6, 7, 13 & 14: Document CRUD, Positive VND Validation, Duplicate Prevention & Immutable Ledger', async () => {
    assert.equal(
      (
        await fsDoc('PATCH', `users/${userA.localId}/wallets/w_vcb`, {
          idToken: userA.idToken,
          data: {
            id: 'w_vcb',
            ownerId: userA.localId,
            name: 'Vietcombank',
            type: 'bank',
            balanceMinor: 15000000,
          },
        })
      ).status,
      200,
    );

    assert.equal(
      (
        await fsDoc('PATCH', `users/${userA.localId}/transactions/op_tx_001`, {
          idToken: userA.idToken,
          query: '?currentDocument.exists=false',
          data: {
            id: 'op_tx_001',
            ownerId: userA.localId,
            walletId: 'w_vcb',
            categoryName: 'Ăn uống',
            kind: 'expense',
            direction: 'debit',
            amountMinor: 85000,
            currencyCode: 'VND',
            monthKey: '2026-11',
            verification: 'userConfirmed',
            occurredAt: '2026-11-22T10:15:00Z',
          },
        })
      ).status,
      200,
    );

    // 14. Prevent duplicate transaction with same operationId via precondition `currentDocument.exists=false` -> 409!
    assert.equal(
      (
        await fsDoc('PATCH', `users/${userA.localId}/transactions/op_tx_001`, {
          idToken: userA.idToken,
          query: '?currentDocument.exists=false',
          data: {
            id: 'op_tx_001',
            ownerId: userA.localId,
            walletId: 'w_vcb',
            amountMinor: 85000,
            currencyCode: 'VND',
          },
        })
      ).status,
      409,
    );

    // 13. Block invalid data: amountMinor <= 0 or forged ownerId -> 403!
    assert.equal(
      (
        await fsDoc('PATCH', `users/${userA.localId}/transactions/tx_invalid_amt`, {
          idToken: userA.idToken,
          data: {
            id: 'tx_invalid_amt',
            ownerId: userA.localId,
            amountMinor: -50000,
            currencyCode: 'VND',
          },
        })
      ).status,
      403,
    );
    assert.equal(
      (
        await fsDoc('PATCH', `users/${userA.localId}/transactions/tx_forged_owner`, {
          idToken: userA.idToken,
          data: {
            id: 'tx_forged_owner',
            ownerId: userB.localId,
            amountMinor: 50000,
            currencyCode: 'VND',
          },
        })
      ).status,
      403,
    );

    // 5. Read Document
    const readTx = await fsDoc('GET', `users/${userA.localId}/transactions/op_tx_001`, {
      idToken: userA.idToken,
    });
    assert.equal(readTx.status, 200);
    assert.equal(readTx.body.fields.amountMinor.integerValue, '85000');

    // 6 & 7. Create, Update & Delete Private Calendar Event (allowed), while Transaction Delete is FORBIDDEN (403)
    assert.equal(
      (
        await fsDoc('PATCH', `users/${userA.localId}/private_events/ev_priv_1`, {
          idToken: userA.idToken,
          data: {
            id: 'ev_priv_1',
            ownerId: userA.localId,
            title: 'Khám sức khỏe định kỳ',
            startsAt: '2026-11-23T08:00:00Z',
          },
        })
      ).status,
      200,
    );
    assert.equal(
      (
        await fsDoc('PATCH', `users/${userA.localId}/private_events/ev_priv_1`, {
          idToken: userA.idToken,
          data: {
            id: 'ev_priv_1',
            ownerId: userA.localId,
            title: 'Khám sức khỏe định kỳ (Đã dời lịch)',
            startsAt: '2026-11-23T09:30:00Z',
          },
        })
      ).status,
      200,
    );
    assert.equal(
      (
        await fsDoc('DELETE', `users/${userA.localId}/transactions/op_tx_001`, {
          idToken: userA.idToken,
        })
      ).status,
      403,
    );
  });

  it('Scenarios 8, 9, 10, 11, 12 & 15: Cross-User Isolation, Family RBAC, Anti-Escalation, Multi-Session Sync & Indexed Queries', async () => {
    // 9 & 10. User B CANNOT read or modify User A's private transactions or wallets!
    assert.equal(
      (
        await fsDoc('GET', `users/${userA.localId}/transactions/op_tx_001`, {
          idToken: userB.idToken,
        })
      ).status,
      403,
    );
    assert.equal(
      (
        await fsDoc('PATCH', `users/${userA.localId}/wallets/w_vcb`, {
          idToken: userB.idToken,
          data: { id: 'w_vcb', ownerId: userA.localId, balanceMinor: 999999999 },
        })
      ).status,
      403,
    );

    // 11 & 12. Family creation, Invite code, Role Self-Escalation block, Shared Bill & Fund RBAC
    assert.equal(
      (
        await fsDoc('PATCH', 'families/fam_live_1', {
          idToken: userA.idToken,
          data: {
            id: 'fam_live_1',
            name: 'Tổ ấm Minh & Lan',
            spaceType: 'family',
            createdBy: userA.localId,
            memberIds: [userA.localId],
            memberRoles: { [userA.localId]: 'owner' },
          },
        })
      ).status,
      200,
    );
    assert.equal(
      (
        await fsDoc('PATCH', 'family_invites/FAM-LIVE01', {
          idToken: userA.idToken,
          data: {
            inviteCode: 'FAM-LIVE01',
            familyId: 'fam_live_1',
            createdBy: userA.localId,
          },
        })
      ).status,
      200,
    );

    assert.equal((await fsDoc('GET', 'family_invites', { idToken: userB.idToken })).status, 403);

    // 12. User B tries to self-escalate to 'admin' on join -> DENIED (403)!
    assert.equal(
      (
        await fsDoc('PATCH', 'families/fam_live_1', {
          idToken: userB.idToken,
          data: {
            id: 'fam_live_1',
            name: 'Tổ ấm Minh & Lan',
            spaceType: 'family',
            createdBy: userA.localId,
            memberIds: [userA.localId, userB.localId],
            memberRoles: { [userA.localId]: 'owner', [userB.localId]: 'admin' },
            lastJoinedInviteCode: 'FAM-LIVE01',
          },
        })
      ).status,
      403,
    );

    // Valid join as 'member' -> SUCCEEDS (200)!
    assert.equal(
      (
        await fsDoc('PATCH', 'families/fam_live_1', {
          idToken: userB.idToken,
          data: {
            id: 'fam_live_1',
            name: 'Tổ ấm Minh & Lan',
            spaceType: 'family',
            createdBy: userA.localId,
            memberIds: [userA.localId, userB.localId],
            memberRoles: { [userA.localId]: 'owner', [userB.localId]: 'member' },
            lastJoinedInviteCode: 'FAM-LIVE01',
          },
        })
      ).status,
      200,
    );

    // Family member STILL CANNOT read private_events!
    assert.equal(
      (
        await fsDoc('GET', `users/${userA.localId}/private_events/ev_priv_1`, {
          idToken: userB.idToken,
        })
      ).status,
      403,
    );

    // Both User A & User B sync shared split_bills in real time; Outsider C gets 403!
    assert.equal(
      (
        await fsDoc('PATCH', 'families/fam_live_1/split_bills/sb_01', {
          idToken: userB.idToken,
          data: {
            id: 'sb_01',
            familyId: 'fam_live_1',
            title: 'Ăn tối & Nước giặt sinh hoạt',
            topic: 'housework',
            paidByUserId: userB.localId,
            totalAmountMinor: 300000,
          },
        })
      ).status,
      200,
    );

    const secondDeviceUserA = await authSignIn('minh.e2e@lifeos.vn', 'StrongPass123!');
    const syncedBill = await fsDoc('GET', 'families/fam_live_1/split_bills/sb_01', {
      idToken: secondDeviceUserA.idToken,
    });
    assert.equal(syncedBill.status, 200);
    assert.equal(syncedBill.body.fields.totalAmountMinor.integerValue, '300000');

    assert.equal(
      (
        await fsDoc('GET', 'families/fam_live_1/split_bills/sb_01', {
          idToken: outsiderC.idToken,
        })
      ).status,
      403,
    );

    // 15. Composite-indexed structured query (`monthKey == '2026-11' ORDER BY occurredAt DESC`)
    const indexedQuery = await fsRunQuery(
      `users/${userA.localId}`,
      {
        from: [{ collectionId: 'transactions' }],
        where: {
          fieldFilter: {
            field: { fieldPath: 'monthKey' },
            op: 'EQUAL',
            value: { stringValue: '2026-11' },
          },
        },
        orderBy: [{ field: { fieldPath: 'occurredAt' }, direction: 'DESCENDING' }],
        limit: 20,
      },
      secondDeviceUserA.idToken,
    );
    assert.equal(indexedQuery.status, 200);
    assert.equal(indexedQuery.body[0].document.fields.amountMinor.integerValue, '85000');

    // Clean up private event (Scenario 7 Delete allowed on private_events)
    assert.equal(
      (
        await fsDoc('DELETE', `users/${userA.localId}/private_events/ev_priv_1`, {
          idToken: userA.idToken,
        })
      ).status,
      200,
    );
  });
});
