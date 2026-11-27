import * as crypto from "node:crypto";
import * as admin from "firebase-admin";
import { HttpsError } from "firebase-functions/v2/https";
import { assertAllowedKeys, assertBoundedString, assertPerUidRateLimit } from "./requestGuards";

export const RECENT_LOGIN_MAX_AGE_SECONDS = 300; // 5 minutes
export const DEFAULT_DELETION_LEASE_MS = 5 * 60 * 1000; // 5 minutes
export const DEFAULT_RETENTION_TTL_MS = 30 * 24 * 60 * 60 * 1000; // 30 days

export const OWNER_SCOPED_SERVER_COLLECTIONS = [
  "server_bank_connections",
  "server_bank_account_claims",
  "server_source_events",
  "sepay_webhook_inbox",
  "notification_outbox",
  "bank_reconciliation_jobs",
  "family_invite_rate_limits"
] as const;

export type AccountDeletionStatus = "in_progress" | "completed" | "failed";

export interface AccountDeletionSteps {
  families: string;
  serverCollections: string;
  userSubtree: string;
  verification: string;
  authDeletion: string;
}

export interface AccountDeletionAuthClient {
  revokeRefreshTokens(uid: string): Promise<void>;
  deleteUser(uid: string): Promise<void>;
}

export interface DeleteAccountOptions {
  readonly skipFamilyOwnerPrecondition?: boolean;
  readonly skipUserRecursiveDelete?: boolean;
  readonly isTrigger?: boolean;
  readonly requireAuthDeletion?: boolean;
  readonly authClient?: AccountDeletionAuthClient;
  readonly nowMs?: number;
  readonly leaseOwner?: string;
  readonly leaseDurationMs?: number;
  readonly retentionTtlMs?: number;
  readonly beforeStepHook?: (
    step: "before_families" | "before_server_collections" | "before_user_subtree" | "before_auth_delete"
  ) => Promise<void>;
}

export interface DeleteAccountResult {
  readonly ok: true;
  readonly status: "completed";
  readonly deletedCount: number;
  readonly verifiedClean: true;
  readonly authDeleted: boolean;
  readonly jobId: string;
}

export interface RecoverStaleDeletionsResult {
  readonly checkedJobs: number;
  readonly resumedJobs: number;
  readonly failedResumes: number;
  readonly purgedExpiredJobs: number;
  readonly purgedExpiredTombstones: number;
}

function isAuthUserNotFoundError(err: unknown): boolean {
  if (!err || typeof err !== "object") return false;
  const rec = err as { code?: unknown; errorInfo?: { code?: unknown } };
  return rec.code === "auth/user-not-found" || rec.errorInfo?.code === "auth/user-not-found";
}

function extractSafeErrorCode(err: unknown): string {
  if (err instanceof HttpsError) {
    if (err.message.startsWith("FAMILY_OWNER_TRANSFER_REQUIRED")) {
      return "FAMILY_OWNER_TRANSFER_REQUIRED";
    }
    if (err.message.startsWith("REQUIRES_RECENT_LOGIN")) {
      return "REQUIRES_RECENT_LOGIN";
    }
    return `https_${err.code}`;
  }
  if (err && typeof err === "object") {
    const rec = err as { code?: unknown; errorInfo?: { code?: unknown } };
    const code = rec.code ?? rec.errorInfo?.code;
    if (typeof code === "string" && code.trim().length > 0) {
      return code.trim().slice(0, 80);
    }
  }
  return "internal_error";
}

/**
 * Enforces recent Firebase Auth sign-in (`auth_time` within last 5 minutes).
 */
export function assertRecentAuthTime(
  authTimeSec: unknown,
  nowEpochSec: number = Math.floor(Date.now() / 1000)
): void {
  if (
    typeof authTimeSec !== "number" ||
    !Number.isFinite(authTimeSec) ||
    authTimeSec <= 0 ||
    nowEpochSec - authTimeSec > RECENT_LOGIN_MAX_AGE_SECONDS
  ) {
    throw new HttpsError(
      "failed-precondition",
      "REQUIRES_RECENT_LOGIN: Phiên đăng nhập quá 5 phút, vui lòng xác thực lại trước khi xóa tài khoản."
    );
  }
}

async function deleteQueryInBatches(
  db: admin.firestore.Firestore,
  queryFactory: () => admin.firestore.Query
): Promise<number> {
  let deleted = 0;
  while (true) {
    const snap = await queryFactory().limit(400).get();
    if (snap.empty) break;
    const batch = db.batch();
    for (const doc of snap.docs) {
      batch.delete(doc.ref);
    }
    await batch.commit();
    deleted += snap.size;
    if (snap.size < 400) break;
  }
  return deleted;
}

export async function purgeServerCollectionsForOwner(
  db: admin.firestore.Firestore,
  cleanUid: string
): Promise<number> {
  let deletedCount = 0;
  for (const colName of OWNER_SCOPED_SERVER_COLLECTIONS) {
    deletedCount += await deleteQueryInBatches(db, () =>
      db.collection(colName).where("ownerId", "==", cleanUid)
    );
  }
  deletedCount += await deleteQueryInBatches(db, () =>
    db.collection("api_rate_limits").where("uid", "==", cleanUid)
  );
  const directRateLimitRef = db.collection("family_invite_rate_limits").doc(cleanUid);
  const directRateLimitSnap = await directRateLimitRef.get();
  if (directRateLimitSnap.exists) {
    await directRateLimitRef.delete();
    deletedCount += 1;
  }
  return deletedCount;
}

export async function verifyOwnerAccountClean(
  db: admin.firestore.Firestore,
  cleanUid: string,
  checkUserSubtree: boolean
): Promise<boolean> {
  if (checkUserSubtree) {
    const userDocRef = db.collection("users").doc(cleanUid);
    const [userSnap, subCols] = await Promise.all([
      userDocRef.get(),
      userDocRef.listCollections()
    ]);
    if (userSnap.exists || subCols.length > 0) {
      return false;
    }
  }
  for (const colName of OWNER_SCOPED_SERVER_COLLECTIONS) {
    const snap = await db.collection(colName).where("ownerId", "==", cleanUid).limit(1).get();
    if (!snap.empty) {
      return false;
    }
  }
  const rateLimitSnap = await db.collection("api_rate_limits").where("uid", "==", cleanUid).limit(1).get();
  if (!rateLimitSnap.empty) {
    return false;
  }
  const directRateLimitSnap = await db.collection("family_invite_rate_limits").doc(cleanUid).get();
  if (directRateLimitSnap.exists) {
    return false;
  }
  return true;
}

function isFamilyOwnerOfDoc(data: Record<string, unknown>, uid: string): boolean {
  const memberRoles = (data.memberRoles ?? {}) as Record<string, unknown>;
  return (
    memberRoles[uid] === "owner" ||
    (memberRoles[uid] === undefined && String(data.createdBy ?? "") === uid)
  );
}

async function assertFamilyOwnerPrecondition(
  db: admin.firestore.Firestore,
  cleanUid: string
): Promise<void> {
  const famSnap = await db.collection("families").where("memberIds", "array-contains", cleanUid).get();
  for (const famDoc of famSnap.docs) {
    const d = famDoc.data() ?? {};
    const memberIds = Array.isArray(d.memberIds) ? d.memberIds.map(String) : [];
    if (isFamilyOwnerOfDoc(d, cleanUid) && memberIds.length > 1) {
      throw new HttpsError(
        "failed-precondition",
        "FAMILY_OWNER_TRANSFER_REQUIRED: Bạn đang là trưởng nhóm của một không gian chung có thành viên khác. Vui lòng chuyển quyền hoặc giải tán nhóm trước khi xóa tài khoản."
      );
    }
  }
}

/**
 * Authoritative, leased, resumable account deletion coordinator.
 */
export async function runAccountDeletion(
  db: admin.firestore.Firestore,
  uid: string,
  options: DeleteAccountOptions = {}
): Promise<DeleteAccountResult> {
  const cleanUid = uid.trim();
  if (!cleanUid) {
    throw new HttpsError("invalid-argument", "Thiếu mã người dùng cần xóa dữ liệu.");
  }

  const nowMs = options.nowMs ?? Date.now();
  const leaseDurationMs = options.leaseDurationMs ?? DEFAULT_DELETION_LEASE_MS;
  const retentionTtlMs = options.retentionTtlMs ?? DEFAULT_RETENTION_TTL_MS;
  const leaseOwner = options.leaseOwner ?? crypto.randomUUID();
  const requireAuthDeletion = options.requireAuthDeletion === true;

  // Check family ownership precondition BEFORE writing tombstone or starting destructive steps
  if (!options.skipFamilyOwnerPrecondition) {
    await assertFamilyOwnerPrecondition(db, cleanUid);
  }

  const jobRef = db.collection("account_deletion_jobs").doc(cleanUid);
  const tombstoneRef = db.collection("account_deletion_tombstones").doc(cleanUid);
  const nowTs = admin.firestore.Timestamp.fromMillis(nowMs);

  const leaseOutcome = await db.runTransaction(async (tx) => {
    const [jobSnap, tombstoneSnap] = await Promise.all([
      tx.get(jobRef),
      tx.get(tombstoneRef)
    ]);
    const jobData = jobSnap.exists ? (jobSnap.data() ?? {}) : {};
    const existingTombstoneData = tombstoneSnap.exists ? (tombstoneSnap.data() ?? {}) : {};

    if (jobSnap.exists && jobData.status === "completed" && jobData.verifiedClean === true) {
      if (!requireAuthDeletion || jobData.authDeleted === true) {
        return {
          alreadyCompleted: true as const,
          jobId: String(jobData.jobId ?? `del_${cleanUid}`),
          authDeleted: Boolean(jobData.authDeleted),
          steps: (jobData.steps ?? {}) as AccountDeletionSteps,
          tombstoneAlreadyDeleted: tombstoneSnap.exists && existingTombstoneData.status === "deleted"
        };
      }
    }

    if (jobSnap.exists && jobData.status === "in_progress") {
      const existingLeaseExpiresAtMs =
        typeof jobData.leaseExpiresAtMs === "number" ? jobData.leaseExpiresAtMs : 0;
      if (existingLeaseExpiresAtMs > nowMs && jobData.leaseOwner !== leaseOwner) {
        throw new HttpsError(
          "aborted",
          "DELETION_IN_PROGRESS: Yêu cầu xóa tài khoản đang được xử lý. Vui lòng đợi hoàn tất."
        );
      }
    }

    const existingSteps = (jobData.steps ?? {}) as Record<string, unknown>;
    const steps: AccountDeletionSteps = {
      families: existingSteps.families === "completed" ? "completed" : "pending",
      serverCollections: existingSteps.serverCollections === "completed" ? "completed" : "pending",
      userSubtree: options.skipUserRecursiveDelete
        ? existingSteps.userSubtree === "completed"
          ? "completed"
          : "skipped_trigger"
        : existingSteps.userSubtree === "completed"
          ? "completed"
          : "pending",
      verification: existingSteps.verification === "completed" ? "completed" : "pending",
      authDeletion: requireAuthDeletion
        ? existingSteps.authDeletion === "completed"
          ? "completed"
          : "pending"
        : existingSteps.authDeletion === "completed"
          ? "completed"
          : "skipped_server_only"
    };

    const jobId =
      typeof jobData.jobId === "string" && jobData.jobId.trim().length > 0
        ? jobData.jobId.trim()
        : `del_${cleanUid}_${nowMs}`;
    const startedAtMs =
      typeof jobData.startedAtMs === "number" ? jobData.startedAtMs : nowMs;

    tx.set(
      jobRef,
      {
        uid: cleanUid,
        jobId,
        status: "in_progress",
        leaseOwner,
        leaseExpiresAtMs: nowMs + leaseDurationMs,
        requireAuthDeletion: requireAuthDeletion || jobData.requireAuthDeletion === true,
        steps,
        ...(jobSnap.exists ? {} : { startedAt: nowTs, startedAtMs }),
        updatedAt: nowTs,
        updatedAtMs: nowMs,
        expiresAtMs: nowMs + retentionTtlMs
      },
      { merge: true }
    );

    tx.set(
      tombstoneRef,
      {
        uid: cleanUid,
        status: existingTombstoneData.status === "deleted" ? "deleted" : "deleting",
        jobId,
        startedAtMs:
          typeof existingTombstoneData.startedAtMs === "number"
            ? existingTombstoneData.startedAtMs
            : startedAtMs,
        updatedAtMs: nowMs,
        expiresAtMs: nowMs + retentionTtlMs
      },
      { merge: true }
    );

    return {
      alreadyCompleted: false as const,
      jobId,
      authDeleted: Boolean(jobData.authDeleted),
      steps,
      tombstoneAlreadyDeleted: existingTombstoneData.status === "deleted"
    };
  });

  if (leaseOutcome.alreadyCompleted) {
    const alreadyClean = await verifyOwnerAccountClean(
      db,
      cleanUid,
      !options.skipUserRecursiveDelete
    );
    if (alreadyClean) {
      if (!leaseOutcome.tombstoneAlreadyDeleted) {
        await tombstoneRef.set(
          {
            uid: cleanUid,
            status: "deleted",
            jobId: leaseOutcome.jobId,
            completedAtMs: nowMs,
            updatedAtMs: nowMs,
            expiresAtMs: nowMs + retentionTtlMs
          },
          { merge: true }
        );
      }
      return {
        ok: true,
        status: "completed",
        deletedCount: 0,
        verifiedClean: true,
        authDeleted: leaseOutcome.authDeleted,
        jobId: leaseOutcome.jobId
      };
    }
    // Re-acquire below if stragglers were discovered on an already-completed job.
    await jobRef.set(
      {
        status: "in_progress",
        leaseOwner,
        leaseExpiresAtMs: nowMs + leaseDurationMs,
        updatedAt: nowTs,
        updatedAtMs: nowMs
      },
      { merge: true }
    );
  }

  const { jobId, steps } = leaseOutcome;
  let deletedCount = 0;

  try {
    // Step 1: Atomic family membership removal & solo-family deletion inside transaction
    if (steps.families !== "completed") {
      await options.beforeStepHook?.("before_families");
      const famSnap = await db.collection("families").where("memberIds", "array-contains", cleanUid).get();
      for (const famDoc of famSnap.docs) {
        const txResult = await db.runTransaction(async (tx) => {
          const fresh = await tx.get(famDoc.ref);
          if (!fresh.exists) {
            return { action: "none" as const, deletedInvites: 0 };
          }
          const d = fresh.data() ?? {};
          const memberIds = Array.isArray(d.memberIds) ? d.memberIds.map(String) : [];
          if (!memberIds.includes(cleanUid)) {
            return { action: "none" as const, deletedInvites: 0 };
          }

          if (!options.skipFamilyOwnerPrecondition && isFamilyOwnerOfDoc(d, cleanUid) && memberIds.length > 1) {
            throw new HttpsError(
              "failed-precondition",
              "FAMILY_OWNER_TRANSFER_REQUIRED: Bạn đang là trưởng nhóm của một không gian chung có thành viên khác. Vui lòng chuyển quyền hoặc giải tán nhóm trước khi xóa tài khoản."
            );
          }

          const remaining = memberIds.filter((id) => id !== cleanUid);
          if (remaining.length === 0) {
            // Atomically read & delete pending family_invites and the family document itself inside ONE transaction
            // so no concurrent member can join while deleting a solo family!
            const invitesQuery = db.collection("family_invites").where("familyId", "==", famDoc.id).limit(400);
            const invitesSnap = await tx.get(invitesQuery);
            for (const invDoc of invitesSnap.docs) {
              tx.delete(invDoc.ref);
            }
            tx.delete(famDoc.ref);
            return { action: "deleted_solo" as const, deletedInvites: invitesSnap.size };
          }

          tx.update(famDoc.ref, {
            memberIds: admin.firestore.FieldValue.arrayRemove(cleanUid),
            [`memberRoles.${cleanUid}`]: admin.firestore.FieldValue.delete(),
            [`memberNames.${cleanUid}`]: admin.firestore.FieldValue.delete(),
            updatedAt: admin.firestore.Timestamp.now()
          });
          return { action: "removed_member" as const, deletedInvites: 0 };
        });

        if (txResult.action === "deleted_solo") {
          deletedCount += txResult.deletedInvites;
          deletedCount += await deleteQueryInBatches(db, () =>
            db.collection("family_invites").where("familyId", "==", famDoc.id)
          );
          await db.recursiveDelete(famDoc.ref);
          deletedCount += 1;
        } else if (txResult.action === "removed_member") {
          deletedCount += await deleteQueryInBatches(db, () =>
            famDoc.ref.collection("availability").where("ownerId", "==", cleanUid)
          );
          deletedCount += 1;
        }
      }

      steps.families = "completed";
      await jobRef.set(
        {
          steps: { families: "completed" },
          updatedAt: admin.firestore.Timestamp.now(),
          updatedAtMs: Date.now()
        },
        { merge: true }
      );
    }

    // Step 2: Purge ALL server-only collections
    if (steps.serverCollections !== "completed") {
      await options.beforeStepHook?.("before_server_collections");
      deletedCount += await purgeServerCollectionsForOwner(db, cleanUid);
      steps.serverCollections = "completed";
      await jobRef.set(
        {
          steps: { serverCollections: "completed" },
          updatedAt: admin.firestore.Timestamp.now(),
          updatedAtMs: Date.now()
        },
        { merge: true }
      );
    }

    // Step 3: Complete recursive deletion of `users/{uid}` and ALL nested subcollections
    if (!options.skipUserRecursiveDelete && steps.userSubtree !== "completed") {
      await options.beforeStepHook?.("before_user_subtree");
      const userDocRef = db.collection("users").doc(cleanUid);
      const [userSnap, subCols] = await Promise.all([
        userDocRef.get(),
        userDocRef.listCollections()
      ]);
      if (userSnap.exists || subCols.length > 0) {
        await db.recursiveDelete(userDocRef);
        deletedCount += userSnap.exists ? 1 : subCols.length;
      }
      steps.userSubtree = "completed";
      await jobRef.set(
        {
          steps: { userSubtree: "completed" },
          updatedAt: admin.firestore.Timestamp.now(),
          updatedAtMs: Date.now()
        },
        { merge: true }
      );
    }

    // Step 4: Verify clean Firestore state (and sweep stragglers if resumed after a prior partial state)
    let clean = await verifyOwnerAccountClean(db, cleanUid, !options.skipUserRecursiveDelete);
    if (!clean) {
      deletedCount += await purgeServerCollectionsForOwner(db, cleanUid);
      if (!options.skipUserRecursiveDelete) {
        const userDocRef = db.collection("users").doc(cleanUid);
        const [userSnap, subCols] = await Promise.all([
          userDocRef.get(),
          userDocRef.listCollections()
        ]);
        if (userSnap.exists || subCols.length > 0) {
          await db.recursiveDelete(userDocRef);
          deletedCount += 1;
        }
      }
      clean = await verifyOwnerAccountClean(db, cleanUid, !options.skipUserRecursiveDelete);
    }

    if (!clean) {
      throw new HttpsError("internal", "Không thể xác minh xóa sạch hoàn toàn dữ liệu tài khoản.");
    }
    steps.verification = "completed";

    // Step 5: Firebase Auth token revocation + account deletion (required for callable flow)
    let authDeleted = false;
    if (requireAuthDeletion) {
      await options.beforeStepHook?.("before_auth_delete");
      const authClient = options.authClient ?? admin.auth();
      try {
        await authClient.revokeRefreshTokens(cleanUid);
      } catch (authErr) {
        if (!isAuthUserNotFoundError(authErr)) {
          throw authErr;
        }
      }
      try {
        await authClient.deleteUser(cleanUid);
      } catch (authErr) {
        if (!isAuthUserNotFoundError(authErr)) {
          throw authErr;
        }
      }
      authDeleted = true;
      steps.authDeletion = "completed";
    }

    // Step 6: Mark job completed and freeze tombstone permanently until TTL expiry
    const completedMs = options.nowMs ?? Date.now();
    const completedTs = admin.firestore.Timestamp.fromMillis(completedMs);
    await Promise.all([
      jobRef.set(
        {
          uid: cleanUid,
          jobId,
          status: "completed",
          leaseOwner: null,
          leaseExpiresAtMs: 0,
          steps,
          verifiedClean: true,
          authDeleted,
          deletedCount,
          completedAt: completedTs,
          completedAtMs: completedMs,
          updatedAt: completedTs,
          updatedAtMs: completedMs,
          expiresAtMs: completedMs + retentionTtlMs
        },
        { merge: true }
      ),
      tombstoneRef.set(
        {
          uid: cleanUid,
          status: "deleted",
          jobId,
          completedAtMs: completedMs,
          updatedAtMs: completedMs,
          expiresAtMs: completedMs + retentionTtlMs
        },
        { merge: true }
      )
    ]);

    return {
      ok: true,
      status: "completed",
      deletedCount,
      verifiedClean: true,
      authDeleted,
      jobId
    };
  } catch (err) {
    const safeErrorCode = extractSafeErrorCode(err);
    const errMs = options.nowMs ?? Date.now();
    const nothingDeletedYet =
      steps.families !== "completed" &&
      steps.serverCollections !== "completed" &&
      steps.userSubtree !== "completed";

    if (safeErrorCode === "FAMILY_OWNER_TRANSFER_REQUIRED" && nothingDeletedYet && !leaseOutcome.tombstoneAlreadyDeleted) {
      // Unfreeze account cleanly when deletion aborted BEFORE any data was deleted!
      await Promise.allSettled([
        tombstoneRef.delete(),
        jobRef.set(
          {
            uid: cleanUid,
            jobId,
            status: "failed",
            leaseOwner: null,
            leaseExpiresAtMs: 0,
            steps,
            verifiedClean: false,
            authDeleted: false,
            lastError: safeErrorCode,
            updatedAt: admin.firestore.Timestamp.fromMillis(errMs),
            updatedAtMs: errMs,
            expiresAtMs: errMs + retentionTtlMs
          },
          { merge: true }
        )
      ]);
    } else {
      await jobRef
        .set(
          {
            uid: cleanUid,
            jobId,
            status: "failed",
            leaseOwner: null,
            leaseExpiresAtMs: 0,
            steps,
            verifiedClean: false,
            authDeleted: false,
            lastError: safeErrorCode,
            updatedAt: admin.firestore.Timestamp.fromMillis(errMs),
            updatedAtMs: errMs,
            expiresAtMs: errMs + retentionTtlMs
          },
          { merge: true }
        )
        .catch(() => undefined);
    }

    if (err instanceof HttpsError) {
      throw err;
    }
    throw new HttpsError(
      "internal",
      "Không thể hoàn tất quy trình xóa tài khoản trên máy chủ. Vui lòng thử lại."
    );
  }
}

export interface DeleteAccountCallableInput {
  readonly db: admin.firestore.Firestore;
  readonly authClient: AccountDeletionAuthClient;
  readonly auth: {
    readonly uid?: string;
    readonly token?: {
      readonly auth_time?: unknown;
      readonly [key: string]: unknown;
    };
  } | null | undefined;
  readonly data: unknown;
  readonly nowMs?: number;
}

/**
 * Full callable handler logic for `deleteUserAccountData` (testable with injected clocks & Auth client).
 */
export async function handleDeleteUserAccountDataCallable(
  params: DeleteAccountCallableInput
): Promise<DeleteAccountResult> {
  const uid = params.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Vui lòng đăng nhập để xóa dữ liệu tài khoản.");
  }

  const nowMs = params.nowMs ?? Date.now();
  await assertPerUidRateLimit(params.db, uid, "deleteUserAccountData", 5, 60_000, nowMs);

  const payload = assertAllowedKeys(params.data, ["userId"]);
  const requestedUid = assertBoundedString(payload.userId, "userId", { maxLength: 128 });
  if (requestedUid && requestedUid !== uid) {
    throw new HttpsError("permission-denied", "Không thể xóa dữ liệu của tài khoản khác.");
  }

  assertRecentAuthTime(params.auth?.token?.auth_time, Math.floor(nowMs / 1000));

  return runAccountDeletion(params.db, uid, {
    requireAuthDeletion: true,
    authClient: params.authClient,
    nowMs
  });
}

/**
 * Scheduled recovery & PII minimization sweeper:
 * 1. Resumes stalled `account_deletion_jobs` stuck in `in_progress` past `leaseExpiresAtMs`.
 * 2. Purges expired `completed` jobs and `deleted` tombstones past `expiresAtMs`.
 */
export async function recoverStaleAccountDeletionJobs(params: {
  readonly db: admin.firestore.Firestore;
  readonly authClient: AccountDeletionAuthClient;
  readonly nowMs?: number;
  readonly batchLimit?: number;
}): Promise<RecoverStaleDeletionsResult> {
  const { db, authClient, nowMs = Date.now(), batchLimit = 25 } = params;
  let checkedJobs = 0;
  let resumedJobs = 0;
  let failedResumes = 0;
  let purgedExpiredJobs = 0;
  let purgedExpiredTombstones = 0;

  const inProgressSnap = await db
    .collection("account_deletion_jobs")
    .where("status", "==", "in_progress")
    .limit(batchLimit)
    .get();

  for (const jobDoc of inProgressSnap.docs) {
    checkedJobs += 1;
    const d = jobDoc.data() ?? {};
    const leaseExpiresAtMs = typeof d.leaseExpiresAtMs === "number" ? d.leaseExpiresAtMs : 0;
    if (leaseExpiresAtMs > nowMs) {
      continue;
    }
    try {
      await runAccountDeletion(db, jobDoc.id, {
        requireAuthDeletion: d.requireAuthDeletion === true,
        authClient,
        nowMs
      });
      resumedJobs += 1;
    } catch {
      failedResumes += 1;
    }
  }

  // Also retry transient failures where Firestore verification passed but Auth deletion had failed
  const failedSnap = await db
    .collection("account_deletion_jobs")
    .where("status", "==", "failed")
    .limit(batchLimit)
    .get();

  for (const jobDoc of failedSnap.docs) {
    const d = jobDoc.data() ?? {};
    const lastError = typeof d.lastError === "string" ? d.lastError : "";
    const expiresAtMs = typeof d.expiresAtMs === "number" ? d.expiresAtMs : Number.MAX_SAFE_INTEGER;
    const steps = (d.steps ?? {}) as Record<string, unknown>;
    if (
      lastError !== "FAMILY_OWNER_TRANSFER_REQUIRED" &&
      d.requireAuthDeletion === true &&
      steps.verification === "completed" &&
      expiresAtMs > nowMs
    ) {
      checkedJobs += 1;
      try {
        await runAccountDeletion(db, jobDoc.id, {
          requireAuthDeletion: true,
          authClient,
          nowMs
        });
        resumedJobs += 1;
      } catch {
        failedResumes += 1;
      }
    }
  }

  // Purge expired completed jobs & deleted tombstones past `expiresAtMs`
  const expiredJobsSnap = await db
    .collection("account_deletion_jobs")
    .where("expiresAtMs", "<=", nowMs)
    .limit(batchLimit)
    .get();

  if (!expiredJobsSnap.empty) {
    const batch = db.batch();
    let count = 0;
    for (const doc of expiredJobsSnap.docs) {
      const d = doc.data() ?? {};
      if (d.status === "completed" || (d.status === "failed" && d.lastError === "FAMILY_OWNER_TRANSFER_REQUIRED")) {
        batch.delete(doc.ref);
        count += 1;
      }
    }
    if (count > 0) {
      await batch.commit();
      purgedExpiredJobs += count;
    }
  }

  const expiredTombstonesSnap = await db
    .collection("account_deletion_tombstones")
    .where("expiresAtMs", "<=", nowMs)
    .limit(batchLimit)
    .get();

  if (!expiredTombstonesSnap.empty) {
    const batch = db.batch();
    let count = 0;
    for (const doc of expiredTombstonesSnap.docs) {
      const d = doc.data() ?? {};
      if (d.status === "deleted") {
        batch.delete(doc.ref);
        count += 1;
      }
    }
    if (count > 0) {
      await batch.commit();
      purgedExpiredTombstones += count;
    }
  }

  return {
    checkedJobs,
    resumedJobs,
    failedResumes,
    purgedExpiredJobs,
    purgedExpiredTombstones
  };
}
