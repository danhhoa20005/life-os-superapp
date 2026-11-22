import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, it, before, after, beforeEach } from 'node:test';
import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, updateDoc, deleteDoc, Timestamp } from 'firebase/firestore';

const rulesPath = resolve(import.meta.dirname, '..', '..', 'firestore.rules');

describe('Life OS Cloud Firestore Security Rules (@firebase/rules-unit-testing)', () => {
  let testEnv;

  before(async () => {
    testEnv = await initializeTestEnvironment({
      projectId: 'demo-life-os',
      firestore: {
        rules: readFileSync(rulesPath, 'utf8'),
        host: '127.0.0.1',
        port: 8188,
      },
    });
  });

  beforeEach(async () => {
    await testEnv.clearFirestore();
  });

  after(async () => {
    await testEnv?.cleanup();
  });

  it('denies all unauthenticated reads and writes', async () => {
    const unauthedDb = testEnv.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(unauthedDb, 'users/u1')));
    await assertFails(getDoc(doc(unauthedDb, 'families/f1')));
  });

  it('prevents family owner from reading member private_events or personal wallets', async () => {
    const memberDb = testEnv.authenticatedContext('member_a').firestore();
    const ownerDb = testEnv.authenticatedContext('owner_b').firestore();

    await assertSucceeds(
      setDoc(doc(memberDb, 'users/member_a/private_events/ev1'), {
        id: 'ev1',
        ownerId: 'member_a',
        title: 'Lịch riêng tư',
      }),
    );

    await assertSucceeds(
      setDoc(doc(ownerDb, 'families/fam_1'), {
        id: 'fam_1',
        name: 'Gia đình B',
        createdBy: 'owner_b',
        memberIds: ['owner_b', 'member_a'],
        memberRoles: { owner_b: 'owner', member_a: 'member' },
      }),
    );

    await assertFails(getDoc(doc(ownerDb, 'users/member_a/private_events/ev1')));
    await assertFails(getDoc(doc(ownerDb, 'users/member_a/wallets/w1')));
  });

  it('enforces immutable transactions (no delete) and blocks role self-escalation on join', async () => {
    const userDb = testEnv.authenticatedContext('u1').firestore();
    await assertSucceeds(
      setDoc(doc(userDb, 'users/u1/transactions/tx1'), {
        id: 'tx1',
        ownerId: 'u1',
        amountMinor: 85000,
        currencyCode: 'VND',
      }),
    );
    await assertFails(deleteDoc(doc(userDb, 'users/u1/transactions/tx1')));

    await assertSucceeds(
      setDoc(doc(userDb, 'families/fam_1'), {
        id: 'fam_1',
        name: 'Gia đình 1',
        createdBy: 'u1',
        memberIds: ['u1'],
        memberRoles: { u1: 'owner' },
      }),
    );
    await assertSucceeds(
      setDoc(doc(userDb, 'family_invites/FAM-CODE1'), {
        inviteCode: 'FAM-CODE1',
        familyId: 'fam_1',
        createdBy: 'u1',
        expiresAt: Timestamp.fromDate(new Date(Date.now() + 86400000)),
      }),
    );

    const attackerDb = testEnv.authenticatedContext('u2').firestore();
    await assertFails(
      updateDoc(doc(attackerDb, 'families/fam_1'), {
        memberIds: ['u1', 'u2'],
        memberRoles: { u1: 'owner', u2: 'owner' },
        lastJoinedInviteCode: 'FAM-CODE1',
      }),
    );
  });
});
