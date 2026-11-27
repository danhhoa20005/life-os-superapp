import * as assert from "node:assert/strict";
import { describe, it } from "node:test";
import * as admin from "firebase-admin";
import { Timestamp } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";
import {
  AccountDeletionAuthClient,
  assertRecentAuthTime,
  handleDeleteUserAccountDataCallable,
  recoverStaleAccountDeletionJobs,
  runAccountDeletion
} from "../accountDeletion";
import { deleteServerOnlyUserAccountData } from "../index";
import {
  assertAllowedKeys,
  assertBoundedString,
  assertOptionalBoolean,
  assertPerUidRateLimit,
  enforceAppCheckFlag,
  fetchWithTimeout
} from "../requestGuards";

function cloneValue<T>(val: T): T {
  if (val === null || val === undefined) return val;
  if (val instanceof Timestamp) {
    return Timestamp.fromMillis(val.toMillis()) as unknown as T;
  }
  if (Array.isArray(val)) {
    return val.map((item) => cloneValue(item)) as unknown as T;
  }
  if (typeof val === "object") {
    const out: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(val as Record<string, unknown>)) {
      out[k] = cloneValue(v);
    }
    return out as T;
  }
  return val;
}

function isSentinelOp(val: unknown, methodName: string): boolean {
  if (!val || typeof val !== "object") return false;
  const ctorName = (val as { constructor?: { name?: string } }).constructor?.name ?? "";
  if (ctorName.toLowerCase().includes(methodName.toLowerCase())) return true;
  const internalName = (val as { methodName?: string }).methodName ?? "";
  return internalName.toLowerCase().includes(methodName.toLowerCase());
}

function applyFieldPathUpdate(
  target: Record<string, unknown>,
  patch: Record<string, unknown>
): Record<string, unknown> {
  const next = cloneValue(target);
  for (const [rawKey, rawVal] of Object.entries(patch)) {
    const parts = rawKey.split(".");
    let cursor: Record<string, unknown> = next;
    for (let i = 0; i < parts.length - 1; i++) {
      const part = parts[i];
      if (!cursor[part] || typeof cursor[part] !== "object" || Array.isArray(cursor[part])) {
        cursor[part] = {};
      }
      cursor = cursor[part] as Record<string, unknown>;
    }
    const leaf = parts[parts.length - 1];
    if (isSentinelOp(rawVal, "delete")) {
      delete cursor[leaf];
    } else if (isSentinelOp(rawVal, "arrayRemove")) {
      const elements = ((rawVal as { elements?: unknown[] }).elements ?? []) as unknown[];
      const existing = Array.isArray(cursor[leaf]) ? (cursor[leaf] as unknown[]) : [];
      cursor[leaf] = existing.filter((item) => !elements.includes(item));
    } else {
      cursor[leaf] = cloneValue(rawVal);
    }
  }
  return next;
}

function deepMerge(
  base: Record<string, unknown>,
  incoming: Record<string, unknown>
): Record<string, unknown> {
  const out = cloneValue(base);
  for (const [k, v] of Object.entries(incoming)) {
    if (
      v !== null &&
      typeof v === "object" &&
      !Array.isArray(v) &&
      !(v instanceof Timestamp) &&
      out[k] !== null &&
      typeof out[k] === "object" &&
      !Array.isArray(out[k]) &&
      !(out[k] instanceof Timestamp)
    ) {
      out[k] = deepMerge(out[k] as Record<string, unknown>, v as Record<string, unknown>);
    } else {
      out[k] = cloneValue(v);
    }
  }
  return out;
}

interface QueryFilter {
  readonly field: string;
  readonly op: string;
  readonly value: unknown;
}

/**
 * Lightweight deterministic in-memory Firestore mock supporting subcollections,
 * recursiveDelete, listCollections, queries, batches, and serialized transactions.
 */
class InMemoryFirestore {
  public readonly docs = new Map<string, Record<string, unknown>>();
  private txChain: Promise<unknown> = Promise.resolve();

  public collection(colPath: string): InMemoryCollectionRef {
    return new InMemoryCollectionRef(this, colPath);
  }

  public doc(docPath: string): InMemoryDocRef {
    return new InMemoryDocRef(this, docPath);
  }

  public batch(): InMemoryWriteBatch {
    return new InMemoryWriteBatch(this);
  }

  public async recursiveDelete(docRef: { path: string }): Promise<void> {
    const prefix = `${docRef.path}/`;
    this.docs.delete(docRef.path);
    for (const key of Array.from(this.docs.keys())) {
      if (key.startsWith(prefix)) {
        this.docs.delete(key);
      }
    }
  }

  public async runTransaction<T>(fn: (tx: InMemoryTransaction) => Promise<T>): Promise<T> {
    const run = this.txChain.then(async () => {
      const tx = new InMemoryTransaction(this);
      const res = await fn(tx);
      tx.commit();
      return res;
    });
    this.txChain = run.catch(() => undefined);
    return run;
  }

  public queryDocs(
    colPath: string,
    filters: readonly QueryFilter[],
    limitCount?: number
  ): Array<{ id: string; path: string; data: Record<string, unknown> }> {
    const prefix = `${colPath}/`;
    const matched: Array<{ id: string; path: string; data: Record<string, unknown> }> = [];
    for (const [path, data] of this.docs.entries()) {
      if (!path.startsWith(prefix)) continue;
      const rest = path.slice(prefix.length);
      if (rest.includes("/")) continue; // Direct children only
      const ok = filters.every((f) => {
        const val = data[f.field];
        if (f.op === "==") return val === f.value;
        if (f.op === "<=") return typeof val === "number" && typeof f.value === "number" && val <= f.value;
        if (f.op === "array-contains") return Array.isArray(val) && val.includes(f.value);
        return false;
      });
      if (ok) {
        matched.push({ id: rest, path, data: cloneValue(data) });
      }
    }
    return limitCount !== undefined ? matched.slice(0, limitCount) : matched;
  }

  public asFirestore(): admin.firestore.Firestore {
    return this as unknown as admin.firestore.Firestore;
  }
}

class InMemoryDocSnapshot {
  constructor(
    public readonly id: string,
    public readonly ref: InMemoryDocRef,
    private readonly rawData: Record<string, unknown> | undefined
  ) {}

  get exists(): boolean {
    return this.rawData !== undefined;
  }

  data(): Record<string, unknown> | undefined {
    return this.rawData ? cloneValue(this.rawData) : undefined;
  }
}

class InMemoryQuerySnapshot {
  constructor(public readonly docs: InMemoryDocSnapshot[]) {}
  get empty(): boolean {
    return this.docs.length === 0;
  }
  get size(): number {
    return this.docs.length;
  }
}

class InMemoryDocRef {
  constructor(
    private readonly db: InMemoryFirestore,
    public readonly path: string
  ) {}

  get id(): string {
    const parts = this.path.split("/");
    return parts[parts.length - 1];
  }

  collection(subCol: string): InMemoryCollectionRef {
    return new InMemoryCollectionRef(this.db, `${this.path}/${subCol}`);
  }

  async listCollections(): Promise<InMemoryCollectionRef[]> {
    const prefix = `${this.path}/`;
    const subColNames = new Set<string>();
    for (const key of this.db.docs.keys()) {
      if (!key.startsWith(prefix)) continue;
      const rest = key.slice(prefix.length);
      const firstSlash = rest.indexOf("/");
      if (firstSlash > 0) {
        subColNames.add(rest.slice(0, firstSlash));
      }
    }
    return Array.from(subColNames).map((name) => this.collection(name));
  }

  async get(): Promise<InMemoryDocSnapshot> {
    return new InMemoryDocSnapshot(this.id, this, this.db.docs.get(this.path));
  }

  async set(data: Record<string, unknown>, opts?: { merge?: boolean }): Promise<void> {
    const existing = this.db.docs.get(this.path);
    if (opts?.merge && existing) {
      this.db.docs.set(this.path, deepMerge(existing, data));
    } else {
      this.db.docs.set(this.path, cloneValue(data));
    }
  }

  async update(patch: Record<string, unknown>): Promise<void> {
    const existing = this.db.docs.get(this.path);
    if (!existing) {
      throw new Error(`NOT_FOUND: ${this.path}`);
    }
    this.db.docs.set(this.path, applyFieldPathUpdate(existing, patch));
  }

  async delete(): Promise<void> {
    this.db.docs.delete(this.path);
  }
}

class InMemoryQuery {
  constructor(
    protected readonly db: InMemoryFirestore,
    protected readonly colPath: string,
    protected readonly filters: readonly QueryFilter[] = [],
    protected readonly limitCount?: number
  ) {}

  where(field: string, op: string, value: unknown): InMemoryQuery {
    return new InMemoryQuery(this.db, this.colPath, [...this.filters, { field, op, value }], this.limitCount);
  }

  limit(n: number): InMemoryQuery {
    return new InMemoryQuery(this.db, this.colPath, this.filters, n);
  }

  async get(): Promise<InMemoryQuerySnapshot> {
    const rows = this.db.queryDocs(this.colPath, this.filters, this.limitCount);
    return new InMemoryQuerySnapshot(
      rows.map((r) => new InMemoryDocSnapshot(r.id, new InMemoryDocRef(this.db, r.path), r.data))
    );
  }
}

class InMemoryCollectionRef extends InMemoryQuery {
  constructor(db: InMemoryFirestore, colPath: string) {
    super(db, colPath);
  }

  doc(docId: string): InMemoryDocRef {
    return new InMemoryDocRef(this.db, `${this.colPath}/${docId}`);
  }
}

class InMemoryWriteBatch {
  private readonly ops: Array<() => void> = [];
  constructor(private readonly db: InMemoryFirestore) {}

  set(ref: InMemoryDocRef, data: Record<string, unknown>, opts?: { merge?: boolean }): void {
    this.ops.push(() => {
      const existing = this.db.docs.get(ref.path);
      if (opts?.merge && existing) {
        this.db.docs.set(ref.path, deepMerge(existing, data));
      } else {
        this.db.docs.set(ref.path, cloneValue(data));
      }
    });
  }

  update(ref: InMemoryDocRef, patch: Record<string, unknown>): void {
    this.ops.push(() => {
      const existing = this.db.docs.get(ref.path);
      if (!existing) throw new Error(`NOT_FOUND: ${ref.path}`);
      this.db.docs.set(ref.path, applyFieldPathUpdate(existing, patch));
    });
  }

  delete(ref: InMemoryDocRef): void {
    this.ops.push(() => {
      this.db.docs.delete(ref.path);
    });
  }

  async commit(): Promise<void> {
    for (const op of this.ops) op();
  }
}

class InMemoryTransaction {
  private readonly ops: Array<() => void> = [];
  constructor(private readonly db: InMemoryFirestore) {}

  async get(target: InMemoryDocRef | InMemoryQuery): Promise<unknown> {
    return target.get();
  }

  set(ref: InMemoryDocRef, data: Record<string, unknown>, opts?: { merge?: boolean }): void {
    this.ops.push(() => {
      const existing = this.db.docs.get(ref.path);
      if (opts?.merge && existing) {
        this.db.docs.set(ref.path, deepMerge(existing, data));
      } else {
        this.db.docs.set(ref.path, cloneValue(data));
      }
    });
  }

  update(ref: InMemoryDocRef, patch: Record<string, unknown>): void {
    this.ops.push(() => {
      const existing = this.db.docs.get(ref.path);
      if (!existing) throw new Error(`NOT_FOUND: ${ref.path}`);
      this.db.docs.set(ref.path, applyFieldPathUpdate(existing, patch));
    });
  }

  delete(ref: InMemoryDocRef): void {
    this.ops.push(() => {
      this.db.docs.delete(ref.path);
    });
  }

  commit(): void {
    for (const op of this.ops) op();
  }
}

class FakeAuthClient implements AccountDeletionAuthClient {
  public readonly revokedUids: string[] = [];
  public readonly deletedUids: string[] = [];
  public readonly callLog: string[] = [];
  public failDeleteWith: Error | null = null;
  public failRevokeWith: Error | null = null;

  async revokeRefreshTokens(uid: string): Promise<void> {
    this.callLog.push(`revoke:${uid}`);
    if (this.failRevokeWith) throw this.failRevokeWith;
    this.revokedUids.push(uid);
  }

  async deleteUser(uid: string): Promise<void> {
    this.callLog.push(`delete:${uid}`);
    if (this.failDeleteWith) throw this.failDeleteWith;
    this.deletedUids.push(uid);
  }
}

describe("DEL-02 / DEL-03 / DEL-04 / SEC-04 — Account Deletion Lifecycle & Request Security", () => {
  it("DEL-02: Rejects stale auth_time (> 5 min), succeeds with fresh auth_time, revokes+deletes Auth, and NEVER reports completed if Auth delete fails", async () => {
    const db = new InMemoryFirestore();
    const fs = db.asFirestore();
    const uid = "u_del02_1";
    const nowMs = Date.parse("2026-11-27T10:00:00Z");
    const nowSec = Math.floor(nowMs / 1000);

    await fs.collection("users").doc(uid).set({ id: uid, email: "del02@lifeos.vn" });
    await fs.collection("users").doc(uid).collection("wallets").doc("w1").set({ id: "w1", balanceMinor: 1000 });
    await fs.collection("server_bank_connections").doc("conn_1").set({ id: "conn_1", ownerId: uid });

    const auth = new FakeAuthClient();

    // 1. Stale auth_time (301s ago > 300s) -> REQUIRES_RECENT_LOGIN (`failed-precondition`)
    await assert.rejects(
      () =>
        handleDeleteUserAccountDataCallable({
          db: fs,
          authClient: auth,
          auth: { uid, token: { auth_time: nowSec - 301 } },
          data: { userId: uid },
          nowMs
        }),
      (err: unknown) =>
        err instanceof HttpsError &&
        err.code === "failed-precondition" &&
        err.message.includes("REQUIRES_RECENT_LOGIN")
    );
    assert.equal(auth.callLog.length, 0);
    assert.equal((await fs.collection("users").doc(uid).get()).exists, true);

    // 2. Missing/invalid auth_time -> REQUIRES_RECENT_LOGIN
    assert.throws(
      () => assertRecentAuthTime(undefined, nowSec),
      (err: unknown) => err instanceof HttpsError && err.code === "failed-precondition"
    );

    // 3. Cross-user deletion -> permission-denied
    await assert.rejects(
      () =>
        handleDeleteUserAccountDataCallable({
          db: fs,
          authClient: auth,
          auth: { uid, token: { auth_time: nowSec - 30 } },
          data: { userId: "other_uid" },
          nowMs: nowMs + 1000
        }),
      (err: unknown) => err instanceof HttpsError && err.code === "permission-denied"
    );

    // 4. Auth deletion failure -> MUST NOT return completed / verifiedClean: true!
    auth.failDeleteWith = Object.assign(new Error("Auth backend unavailable"), {
      code: "auth/internal-error"
    });
    await assert.rejects(
      () =>
        handleDeleteUserAccountDataCallable({
          db: fs,
          authClient: auth,
          auth: { uid, token: { auth_time: nowSec - 30 } },
          data: { userId: uid },
          nowMs: nowMs + 2000
        }),
      (err: unknown) => err instanceof HttpsError
    );

    const failedJob = (await fs.collection("account_deletion_jobs").doc(uid).get()).data()!;
    assert.equal(failedJob.status, "failed");
    assert.equal(failedJob.verifiedClean, false);
    assert.equal(failedJob.authDeleted, false);
    assert.equal(failedJob.leaseExpiresAtMs, 0);

    // 5. Retry with auth/user-not-found (idempotent Auth delete) -> completes cleanly!
    auth.failDeleteWith = Object.assign(new Error("User already deleted"), {
      code: "auth/user-not-found"
    });
    const okRes = await handleDeleteUserAccountDataCallable({
      db: fs,
      authClient: auth,
      auth: { uid, token: { auth_time: nowSec - 10 } },
      data: { userId: uid },
      nowMs: nowMs + 3000
    });
    assert.equal(okRes.ok, true);
    assert.equal(okRes.status, "completed");
    assert.equal(okRes.verifiedClean, true);
    assert.equal(okRes.authDeleted, true);
    assert.ok(okRes.jobId.startsWith(`del_${uid}_`));
    assert.equal((await fs.collection("users").doc(uid).get()).exists, false);
    assert.equal((await fs.collection("server_bank_connections").doc("conn_1").get()).exists, false);

    // 6. Fresh auth flow at exact 300s boundary verifies revokeRefreshTokens + deleteUser both invoked
    const uid2 = "u_del02_2";
    const auth2 = new FakeAuthClient();
    await fs.collection("users").doc(uid2).set({ id: uid2 });
    const nowMs2 = nowMs + 4000;
    const nowSec2 = Math.floor(nowMs2 / 1000);
    const res2 = await handleDeleteUserAccountDataCallable({
      db: fs,
      authClient: auth2,
      auth: { uid: uid2, token: { auth_time: nowSec2 - 300 } },
      data: {},
      nowMs: nowMs2
    });
    assert.equal(res2.status, "completed");
    assert.equal(res2.authDeleted, true);
    assert.deepEqual(auth2.callLog, [`revoke:${uid2}`, `delete:${uid2}`]);
  });

  it("DEL-03: Solo family concurrent member join race aborts inside transaction BEFORE deleting anything", async () => {
    const db = new InMemoryFirestore();
    const fs = db.asFirestore();
    const uid = "u_solo_race";
    const joinerUid = "u_racer";
    const famId = "fam_solo_race";
    const nowMs = Date.parse("2026-11-27T10:10:00Z");

    await fs.collection("users").doc(uid).set({ id: uid, fullName: "Owner" });
    await fs.collection("users").doc(uid).collection("wallets").doc("w1").set({ id: "w1", balanceMinor: 500000 });
    await fs.collection("server_bank_connections").doc("conn_race").set({ id: "conn_race", ownerId: uid });
    await fs.collection("families").doc(famId).set({
      id: famId,
      createdBy: uid,
      memberIds: [uid],
      memberRoles: { [uid]: "owner" },
      memberNames: { [uid]: "Owner" }
    });
    await fs.collection("families").doc(famId).collection("availability").doc("av_1").set({ ownerId: uid });
    await fs.collection("family_invites").doc("FAM-RACE1").set({ inviteCode: "FAM-RACE1", familyId: famId });

    // Simulate a concurrent member joining `fam_solo_race` right after pre-check, BEFORE Step 1 transaction!
    await assert.rejects(
      () =>
        runAccountDeletion(fs, uid, {
          nowMs,
          requireAuthDeletion: true,
          authClient: new FakeAuthClient(),
          beforeStepHook: async (step) => {
            if (step === "before_families") {
              await fs.collection("families").doc(famId).set({
                id: famId,
                createdBy: uid,
                memberIds: [uid, joinerUid],
                memberRoles: { [uid]: "owner", [joinerUid]: "member" },
                memberNames: { [uid]: "Owner", [joinerUid]: "Joiner" }
              });
            }
          }
        }),
      (err: unknown) =>
        err instanceof HttpsError &&
        err.code === "failed-precondition" &&
        err.message.includes("FAMILY_OWNER_TRANSFER_REQUIRED")
    );

    // Verify NOTHING was deleted (family, invites, availability, wallet, user doc) & tombstone was rolled back!
    const famAfter = await fs.collection("families").doc(famId).get();
    assert.equal(famAfter.exists, true);
    assert.deepEqual(famAfter.data()?.memberIds, [uid, joinerUid]);
    assert.equal((await fs.collection("family_invites").doc("FAM-RACE1").get()).exists, true);
    assert.equal((await fs.collection("families").doc(famId).collection("availability").doc("av_1").get()).exists, true);
    assert.equal((await fs.collection("users").doc(uid).get()).exists, true);
    assert.equal((await fs.collection("users").doc(uid).collection("wallets").doc("w1").get()).exists, true);
    assert.equal((await fs.collection("server_bank_connections").doc("conn_race").get()).exists, true);
    assert.equal((await fs.collection("account_deletion_tombstones").doc(uid).get()).exists, false);
  });

  it("DEL-03: Multi-member owner blocked upfront; solo family + invites deleted atomically when uncontested", async () => {
    const db = new InMemoryFirestore();
    const fs = db.asFirestore();
    const uid = "u_solo_clean";
    const famSolo = "fam_solo_ok";
    const famMulti = "fam_multi_ok";
    const nowMs = Date.parse("2026-11-27T10:15:00Z");

    await fs.collection("users").doc(uid).set({ id: uid });
    await fs.collection("families").doc(famMulti).set({
      id: famMulti,
      createdBy: uid,
      memberIds: [uid, "u_other"],
      memberRoles: { [uid]: "owner", u_other: "member" }
    });

    // Multi-member owner blocked upfront (no tombstone created!)
    await assert.rejects(
      () => runAccountDeletion(fs, uid, { nowMs }),
      (err: unknown) =>
        err instanceof HttpsError &&
        err.code === "failed-precondition" &&
        err.message.includes("FAMILY_OWNER_TRANSFER_REQUIRED")
    );
    assert.equal((await fs.collection("account_deletion_tombstones").doc(uid).get()).exists, false);

    // Transfer ownership to u_other, plus own a solo family with invite & nested availability
    await fs.collection("families").doc(famMulti).update({
      memberRoles: { [uid]: "member", u_other: "owner" }
    });
    await fs.collection("families").doc(famSolo).set({
      id: famSolo,
      createdBy: uid,
      memberIds: [uid],
      memberRoles: { [uid]: "owner" }
    });
    await fs.collection("families").doc(famSolo).collection("availability").doc("av_s").set({ ownerId: uid });
    await fs.collection("family_invites").doc("FAM-SOLO1").set({ inviteCode: "FAM-SOLO1", familyId: famSolo });

    const res = await runAccountDeletion(fs, uid, {
      nowMs: nowMs + 1000,
      requireAuthDeletion: true,
      authClient: new FakeAuthClient()
    });
    assert.equal(res.status, "completed");
    assert.equal(res.authDeleted, true);
    assert.equal((await fs.collection("families").doc(famSolo).get()).exists, false);
    assert.equal((await fs.collection("family_invites").doc("FAM-SOLO1").get()).exists, false);
    assert.equal((await fs.collection("families").doc(famSolo).collection("availability").doc("av_s").get()).exists, false);
    assert.deepEqual((await fs.collection("families").doc(famMulti).get()).data()?.memberIds, ["u_other"]);
  });

  it("DEL-04: Rejects concurrent active lease, writes tombstone before wiping, resumes expired lease, and sweeper recovers & purges TTL", async () => {
    const db = new InMemoryFirestore();
    const fs = db.asFirestore();
    const uid = "u_lease";
    const nowMs = Date.parse("2026-11-27T10:20:00Z");

    await fs.collection("users").doc(uid).set({ id: uid });
    await fs.collection("users").doc(uid).collection("personal_funds").doc("pf1").collection("fund_audits").doc("fa1").set({
      deltaMinor: 100
    });

    // 1. Seed an active unexpired lease held by another worker
    await fs.collection("account_deletion_jobs").doc(uid).set({
      uid,
      jobId: `del_${uid}_1`,
      status: "in_progress",
      leaseOwner: "worker_1",
      leaseExpiresAtMs: nowMs + 120_000,
      requireAuthDeletion: true,
      steps: { families: "pending", serverCollections: "pending", userSubtree: "pending", verification: "pending", authDeletion: "pending" }
    });

    await assert.rejects(
      () =>
        runAccountDeletion(fs, uid, {
          nowMs,
          leaseOwner: "worker_2",
          requireAuthDeletion: true,
          authClient: new FakeAuthClient()
        }),
      (err: unknown) =>
        err instanceof HttpsError &&
        err.code === "aborted" &&
        err.message.includes("DELETION_IN_PROGRESS")
    );

    // 2. After lease expires, sweeper resumes job cleanly, writes tombstone before wiping, and deletes Auth!
    const auth = new FakeAuthClient();
    const staleNowMs = nowMs + 180_000;
    const sweep1 = await recoverStaleAccountDeletionJobs({
      db: fs,
      authClient: auth,
      nowMs: staleNowMs
    });
    assert.equal(sweep1.checkedJobs, 1);
    assert.equal(sweep1.resumedJobs, 1);
    assert.equal(sweep1.failedResumes, 0);
    assert.deepEqual(auth.deletedUids, [uid]);

    const jobSnap = await fs.collection("account_deletion_jobs").doc(uid).get();
    const tombSnap = await fs.collection("account_deletion_tombstones").doc(uid).get();
    assert.equal(jobSnap.data()?.status, "completed");
    assert.equal(jobSnap.data()?.authDeleted, true);
    assert.equal(tombSnap.data()?.status, "deleted");
    assert.equal((await fs.collection("users").doc(uid).collection("personal_funds").doc("pf1").collection("fund_audits").doc("fa1").get()).exists, false);

    // 3. Verify tombstone status='deleting' is written BEFORE any data deletion runs
    const uidT = "u_tomb_order";
    await fs.collection("users").doc(uidT).set({ id: uidT });
    let tombStatusBeforeStep: unknown = null;
    await runAccountDeletion(fs, uidT, {
      nowMs: staleNowMs,
      requireAuthDeletion: false,
      beforeStepHook: async (step) => {
        if (step === "before_families") {
          tombStatusBeforeStep = (await fs.collection("account_deletion_tombstones").doc(uidT).get()).data()?.status;
        }
      }
    });
    assert.equal(tombStatusBeforeStep, "deleting");
    assert.equal((await fs.collection("account_deletion_tombstones").doc(uidT).get()).data()?.status, "deleted");

    // 4. Before TTL expiry, sweeper does NOT purge jobs/tombstones; past TTL expiry, sweeper purges both!
    const beforeTtlSweep = await recoverStaleAccountDeletionJobs({
      db: fs,
      authClient: auth,
      nowMs: staleNowMs + 1000
    });
    assert.equal(beforeTtlSweep.purgedExpiredJobs, 0);
    assert.equal(beforeTtlSweep.purgedExpiredTombstones, 0);

    const afterTtlMs = staleNowMs + 31 * 24 * 60 * 60 * 1000;
    const afterTtlSweep = await recoverStaleAccountDeletionJobs({
      db: fs,
      authClient: auth,
      nowMs: afterTtlMs
    });
    assert.equal(afterTtlSweep.purgedExpiredJobs, 2);
    assert.equal(afterTtlSweep.purgedExpiredTombstones, 2);
    assert.equal((await fs.collection("account_deletion_jobs").doc(uid).get()).exists, false);
    assert.equal((await fs.collection("account_deletion_tombstones").doc(uid).get()).exists, false);
  });

  it("SEC-04: Enforces App Check flag, strict key allowlist, bounded strings, transactional rate limiter & fetch timeout", async () => {
    const prevEnv = process.env.LIFEOS_ENFORCE_APP_CHECK;
    try {
      delete process.env.LIFEOS_ENFORCE_APP_CHECK;
      assert.equal(enforceAppCheckFlag(), false);
      process.env.LIFEOS_ENFORCE_APP_CHECK = "true";
      assert.equal(enforceAppCheckFlag(), true);
    } finally {
      if (prevEnv === undefined) {
        delete process.env.LIFEOS_ENFORCE_APP_CHECK;
      } else {
        process.env.LIFEOS_ENFORCE_APP_CHECK = prevEnv;
      }
    }

    // assertAllowedKeys
    assert.deepEqual(assertAllowedKeys(undefined, ["userId"]), {});
    assert.deepEqual(assertAllowedKeys({ userId: "u1" }, ["userId"]), { userId: "u1" });
    assert.throws(
      () => assertAllowedKeys(["bad"], ["userId"]),
      (err: unknown) => err instanceof HttpsError && err.code === "invalid-argument"
    );
    assert.throws(
      () => assertAllowedKeys({ userId: "u1", injectedAdmin: true }, ["userId"]),
      (err: unknown) => err instanceof HttpsError && err.code === "invalid-argument"
    );

    // assertBoundedString
    assert.equal(assertBoundedString("  VCB  ", "bankCode", { required: true, minLength: 2, maxLength: 10 }), "VCB");
    assert.throws(
      () => assertBoundedString("   ", "bankCode", { required: true }),
      (err: unknown) => err instanceof HttpsError && err.code === "invalid-argument"
    );
    assert.throws(
      () => assertBoundedString("A".repeat(33), "bankCode", { maxLength: 32 }),
      (err: unknown) => err instanceof HttpsError && err.code === "invalid-argument"
    );
    assert.throws(
      () => assertBoundedString("short", "sepayApiToken", { required: true, minLength: 16 }),
      (err: unknown) => err instanceof HttpsError && err.code === "invalid-argument"
    );
    assert.throws(
      () => assertBoundedString(12345, "bankCode", { required: true }),
      (err: unknown) => err instanceof HttpsError && err.code === "invalid-argument"
    );

    // assertOptionalBoolean
    assert.equal(assertOptionalBoolean(undefined, "ignoreWatermark", false), false);
    assert.equal(assertOptionalBoolean(true, "ignoreWatermark", false), true);
    assert.throws(
      () => assertOptionalBoolean("true", "ignoreWatermark", false),
      (err: unknown) => err instanceof HttpsError && err.code === "invalid-argument"
    );

    // assertPerUidRateLimit
    const db = new InMemoryFirestore();
    const fs = db.asFirestore();
    const t0 = Date.parse("2026-11-27T11:00:00Z");
    await assertPerUidRateLimit(fs, "u_rl_1", "verifyAndLinkBankConnection", 3, 60_000, t0);
    await assertPerUidRateLimit(fs, "u_rl_1", "verifyAndLinkBankConnection", 3, 60_000, t0 + 100);
    await assertPerUidRateLimit(fs, "u_rl_1", "verifyAndLinkBankConnection", 3, 60_000, t0 + 200);
    await assert.rejects(
      () => assertPerUidRateLimit(fs, "u_rl_1", "verifyAndLinkBankConnection", 3, 60_000, t0 + 300),
      (err: unknown) => err instanceof HttpsError && err.code === "resource-exhausted"
    );
    // Different endpoint or different UID unaffected
    await assertPerUidRateLimit(fs, "u_rl_1", "disconnectBankConnection", 3, 60_000, t0 + 300);
    await assertPerUidRateLimit(fs, "u_rl_2", "verifyAndLinkBankConnection", 3, 60_000, t0 + 300);
    // After window expires, resets cleanly
    await assertPerUidRateLimit(fs, "u_rl_1", "verifyAndLinkBankConnection", 3, 60_000, t0 + 60_001);

    // fetchWithTimeout rejects aborted fetch cleanly (without external network call)
    const preAborted = new AbortController();
    preAborted.abort(new Error("timeout"));
    await assert.rejects(
      () => fetchWithTimeout("http://127.0.0.1:1/unreachable", { signal: preAborted.signal }, 50)
    );
  });

  it("DEL-03 backward compatibility: deleteServerOnlyUserAccountData & trigger mode enforce family preconditions and delete orphaned subcollections", async () => {
    const db = new InMemoryFirestore();
    const fs = db.asFirestore();
    const uid = "u_trig_1";
    const nowMs = Date.parse("2026-11-27T11:30:00Z");

    // Seed orphaned nested subcollections (user root doc already absent as in onDocumentDeleted)
    await fs.collection("users").doc(uid).collection("wallets").doc("w_orphan").set({ id: "w_orphan" });
    await fs.collection("users").doc(uid).collection("vehicles").doc("v1").collection("fuel_logs").doc("fl1").set({ costMinor: 50000 });
    await fs.collection("server_bank_connections").doc("conn_trig").set({ id: "conn_trig", ownerId: uid });
    await fs.collection("families").doc("fam_trig_multi").set({
      id: "fam_trig_multi",
      createdBy: uid,
      memberIds: [uid, "u_co"],
      memberRoles: { [uid]: "owner", u_co: "member" }
    });

    // Without skipping family precondition, trigger mode rejects multi-member owner cleanly
    await assert.rejects(
      () => deleteServerOnlyUserAccountData(fs, uid, { isTrigger: true, nowMs }),
      (err: unknown) => err instanceof HttpsError && err.code === "failed-precondition"
    );

    // After ownership transferred, trigger mode deletes orphaned subcollections & server collections cleanly
    await fs.collection("families").doc("fam_trig_multi").update({
      memberRoles: { [uid]: "member", u_co: "owner" }
    });
    const res = await deleteServerOnlyUserAccountData(fs, uid, { isTrigger: true, nowMs: nowMs + 1000 });
    assert.equal(res.ok, true);
    assert.equal(res.verifiedClean, true);
    assert.equal((await fs.collection("users").doc(uid).collection("wallets").doc("w_orphan").get()).exists, false);
    assert.equal((await fs.collection("users").doc(uid).collection("vehicles").doc("v1").collection("fuel_logs").doc("fl1").get()).exists, false);
    assert.equal((await fs.collection("server_bank_connections").doc("conn_trig").get()).exists, false);
    assert.deepEqual((await fs.collection("families").doc("fam_trig_multi").get()).data()?.memberIds, ["u_co"]);
  });
});
