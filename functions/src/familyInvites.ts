import * as crypto from "node:crypto";
import * as admin from "firebase-admin";
import { Timestamp } from "firebase-admin/firestore";
import { sha256Hex } from "./security";

export type InviteKind = "oneTime" | "targeted" | "reusableGroup";
export type InviteStatus = "active" | "consumed" | "revoked" | "expired";
export type CollaborationSpaceType = "family" | "roommates" | "group";

const INVITE_CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
const DEFAULT_TTL_DAYS = 7;
const MAX_TTL_DAYS = 30;
const MAX_REUSABLE_USES = 100;
const RATE_LIMIT_WINDOW_MS = 60_000;
const RATE_LIMIT_MAX_ATTEMPTS = 10;

export type FamilyInviteErrorCode =
  | "UNAUTHENTICATED"
  | "INVALID_ARGUMENT"
  | "PERMISSION_DENIED"
  | "NOT_FOUND"
  | "FAILED_PRECONDITION"
  | "RESOURCE_EXHAUSTED";

export class FamilyInviteError extends Error {
  constructor(
    public readonly code: FamilyInviteErrorCode,
    message: string
  ) {
    super(message);
    this.name = "FamilyInviteError";
  }
}

export interface FamilyInviteRecord {
  readonly inviteId: string;
  readonly inviteCode: string;
  readonly familyId: string;
  readonly familyName: string;
  readonly spaceType: CollaborationSpaceType;
  readonly inviteKind: InviteKind;
  readonly isTargeted: boolean;
  readonly createdBy: string;
  readonly invitedByUserId: string;
  readonly invitedByName: string;
  readonly inviteeName?: string;
  readonly intendedRecipientHash?: string;
  readonly maxUses: number;
  readonly usedCount: number;
  readonly consumedBy?: string | null;
  readonly consumedAtMs?: number | null;
  readonly revoked: boolean;
  readonly revokedBy?: string | null;
  readonly revokedAtMs?: number | null;
  readonly status: InviteStatus;
  readonly expiresAtMs: number;
  readonly createdAtMs: number;
  readonly updatedAtMs: number;
}

export interface FamilySpaceRecord {
  readonly id: string;
  readonly name: string;
  readonly spaceType: CollaborationSpaceType;
  readonly createdBy: string;
  readonly memberIds: readonly string[];
  readonly bannedUserIds?: readonly string[];
  readonly memberRoles: Readonly<Record<string, string>>;
  readonly memberNames: Readonly<Record<string, string>>;
  readonly pendingInvites: Readonly<Record<string, Record<string, unknown>>>;
  readonly lastJoinedInviteCode?: string;
  readonly updatedAtMs?: number;
}

export interface InviteRateLimitRecord {
  readonly windowStartMs: number;
  readonly failedCount: number;
  readonly updatedAtMs: number;
}

export interface FamilyInviteTxContext {
  getFamily(familyId: string): Promise<FamilySpaceRecord | null>;
  updateFamilyJoin(
    familyId: string,
    update: {
      memberIdToAdd: string;
      memberName: string;
      inviteCode: string;
      deletePendingInvite: boolean;
      nowMs: number;
    }
  ): Promise<void>;
  setFamilyPendingInvite(
    familyId: string,
    inviteCode: string,
    internalPayload: Record<string, unknown>,
    nowMs: number
  ): Promise<void>;
  deleteFamilyPendingInvite(familyId: string, inviteCode: string, nowMs: number): Promise<void>;
  getInvite(inviteCode: string): Promise<FamilyInviteRecord | null>;
  setInvite(invite: FamilyInviteRecord): Promise<void>;
  updateInvite(inviteCode: string, patch: Partial<FamilyInviteRecord>): Promise<void>;
  updateUserActiveFamily(uid: string, familyId: string, nowMs: number): Promise<void>;
}

export interface FamilyInviteStore {
  runTransaction<T>(fn: (tx: FamilyInviteTxContext) => Promise<T>): Promise<T>;
  getInviteReadOnly(inviteCode: string): Promise<FamilyInviteRecord | null>;
  getRateLimit(uid: string): Promise<InviteRateLimitRecord | null>;
  setRateLimit(uid: string, record: InviteRateLimitRecord): Promise<void>;
}

export function extractInviteCode(rawInput: string): string {
  const upper = rawInput.trim().toUpperCase();
  const match = /FAM-[A-Z0-9]{4,12}/.exec(upper);
  if (match) {
    return match[0];
  }
  return upper.replace(/\s+/g, "");
}

export function normalizeRecipientContact(raw: string): string {
  const trimmed = raw.trim();
  if (!trimmed) return "";
  if (trimmed.includes("@")) {
    return trimmed.toLowerCase();
  }
  const compact = trimmed.replace(/[\s\-().]/g, "");
  if (/^\+84\d{8,11}$/.test(compact)) {
    return `0${compact.slice(3)}`;
  }
  if (/^84\d{8,11}$/.test(compact)) {
    return `0${compact.slice(2)}`;
  }
  return compact.toLowerCase();
}

export function hashRecipientContact(raw: string): string {
  const normalized = normalizeRecipientContact(raw);
  if (!normalized) return "";
  return sha256Hex(normalized);
}

export function sanitizePublicInviteeName(rawName?: string): string | undefined {
  if (!rawName) return undefined;
  const trimmed = rawName.trim();
  if (!trimmed) return undefined;
  if (trimmed.includes("@")) return undefined;
  const digits = (trimmed.match(/\d/g) ?? []).length;
  if (digits >= 6) return undefined;
  return trimmed;
}

export function maskContactForInternalDisplay(rawContact?: string): string | undefined {
  if (!rawContact) return undefined;
  const trimmed = rawContact.trim();
  if (!trimmed) return undefined;
  const atIdx = trimmed.indexOf("@");
  if (atIdx > 0) {
    const local = trimmed.slice(0, atIdx);
    const domain = trimmed.slice(atIdx);
    const keep = local.slice(0, Math.min(2, local.length));
    return `${keep}***${domain}`;
  }
  const digits = trimmed.replace(/\D/g, "");
  if (digits.length >= 6) {
    const last4 = digits.slice(-4);
    return `${"*".repeat(Math.max(4, digits.length - 4))}${last4}`;
  }
  return `${trimmed.slice(0, Math.min(2, trimmed.length))}***`;
}

function generateSecureInviteCode(): string {
  const bytes = crypto.randomBytes(6);
  let suffix = "";
  for (let i = 0; i < 6; i++) {
    suffix += INVITE_CODE_ALPHABET[bytes[i]! % INVITE_CODE_ALPHABET.length];
  }
  return `FAM-${suffix}`;
}

export class InMemoryFamilyInviteStore implements FamilyInviteStore {
  public readonly families = new Map<string, FamilySpaceRecord>();
  public readonly invites = new Map<string, FamilyInviteRecord>();
  public readonly users = new Map<string, Record<string, unknown>>();
  public readonly rateLimits = new Map<string, InviteRateLimitRecord>();
  private lock: Promise<void> = Promise.resolve();

  async runTransaction<T>(fn: (tx: FamilyInviteTxContext) => Promise<T>): Promise<T> {
    const prev = this.lock;
    let release!: () => void;
    this.lock = new Promise<void>((res) => {
      release = res;
    });
    await prev;
    try {
      const pendingOps: Array<() => void> = [];
      const ctx: FamilyInviteTxContext = {
        getFamily: async (familyId) => {
          const fam = this.families.get(familyId);
          return fam ? structuredClone(fam) : null;
        },
        updateFamilyJoin: async (familyId, update) => {
          pendingOps.push(() => {
            const fam = this.families.get(familyId);
            if (!fam) throw new FamilyInviteError("NOT_FOUND", "Không tìm thấy nhóm.");
            const nextMembers = fam.memberIds.includes(update.memberIdToAdd)
              ? [...fam.memberIds]
              : [...fam.memberIds, update.memberIdToAdd];
            const nextRoles = { ...fam.memberRoles, [update.memberIdToAdd]: "member" };
            const nextNames = { ...fam.memberNames, [update.memberIdToAdd]: update.memberName };
            const nextPending = { ...fam.pendingInvites };
            if (update.deletePendingInvite) {
              delete nextPending[update.inviteCode];
            }
            this.families.set(familyId, {
              ...fam,
              memberIds: nextMembers,
              memberRoles: nextRoles,
              memberNames: nextNames,
              pendingInvites: nextPending,
              lastJoinedInviteCode: update.inviteCode,
              updatedAtMs: update.nowMs
            });
          });
        },
        setFamilyPendingInvite: async (familyId, inviteCode, internalPayload, nowMs) => {
          pendingOps.push(() => {
            const fam = this.families.get(familyId);
            if (!fam) throw new FamilyInviteError("NOT_FOUND", "Không tìm thấy nhóm.");
            this.families.set(familyId, {
              ...fam,
              pendingInvites: { ...fam.pendingInvites, [inviteCode]: internalPayload },
              updatedAtMs: nowMs
            });
          });
        },
        deleteFamilyPendingInvite: async (familyId, inviteCode, nowMs) => {
          pendingOps.push(() => {
            const fam = this.families.get(familyId);
            if (!fam) return;
            const nextPending = { ...fam.pendingInvites };
            delete nextPending[inviteCode];
            this.families.set(familyId, {
              ...fam,
              pendingInvites: nextPending,
              updatedAtMs: nowMs
            });
          });
        },
        getInvite: async (inviteCode) => {
          const inv = this.invites.get(inviteCode);
          return inv ? structuredClone(inv) : null;
        },
        setInvite: async (invite) => {
          pendingOps.push(() => {
            this.invites.set(invite.inviteCode, structuredClone(invite));
          });
        },
        updateInvite: async (inviteCode, patch) => {
          pendingOps.push(() => {
            const existing = this.invites.get(inviteCode);
            if (!existing) throw new FamilyInviteError("NOT_FOUND", "Mã mời không tồn tại.");
            this.invites.set(inviteCode, { ...existing, ...patch });
          });
        },
        updateUserActiveFamily: async (uid, familyId, nowMs) => {
          pendingOps.push(() => {
            const existing = this.users.get(uid) ?? { id: uid };
            const prevIds = Array.isArray(existing.familyIds) ? (existing.familyIds as string[]) : [];
            const nextIds = prevIds.includes(familyId) ? prevIds : [...prevIds, familyId];
            this.users.set(uid, {
              ...existing,
              id: uid,
              familyId,
              activeFamilyId: familyId,
              familyIds: nextIds,
              updatedAtMs: nowMs
            });
          });
        }
      };

      const result = await fn(ctx);
      for (const op of pendingOps) {
        op();
      }
      return result;
    } finally {
      release();
    }
  }

  async getInviteReadOnly(inviteCode: string): Promise<FamilyInviteRecord | null> {
    const inv = this.invites.get(inviteCode);
    return inv ? structuredClone(inv) : null;
  }

  async getRateLimit(uid: string): Promise<InviteRateLimitRecord | null> {
    const rec = this.rateLimits.get(uid);
    return rec ? structuredClone(rec) : null;
  }

  async setRateLimit(uid: string, record: InviteRateLimitRecord): Promise<void> {
    this.rateLimits.set(uid, structuredClone(record));
  }
}

function tsToMs(val: unknown, fallback: number): number {
  if (val instanceof Timestamp) return val.toMillis();
  if (typeof val === "number" && Number.isFinite(val)) return val;
  return fallback;
}

function mapInviteDoc(code: string, d: Record<string, unknown>, nowMs: number): FamilyInviteRecord {
  const maxUses = typeof d.maxUses === "number" && d.maxUses >= 1 ? Math.floor(d.maxUses) : 1;
  const usedCount = typeof d.usedCount === "number" && d.usedCount >= 0 ? Math.floor(d.usedCount) : 0;
  const revoked = Boolean(d.revoked);
  const rawStatus = typeof d.status === "string" ? d.status : undefined;
  const status: InviteStatus =
    rawStatus === "revoked" || revoked
      ? "revoked"
      : rawStatus === "consumed" || usedCount >= maxUses
        ? "consumed"
        : rawStatus === "expired"
          ? "expired"
          : "active";
  const rawKind = typeof d.inviteKind === "string" ? d.inviteKind : undefined;
  const hasHash = typeof d.intendedRecipientHash === "string" && d.intendedRecipientHash.length > 0;
  const inviteKind: InviteKind =
    rawKind === "targeted" || rawKind === "reusableGroup" || rawKind === "oneTime"
      ? rawKind
      : hasHash
        ? "targeted"
        : maxUses > 1
          ? "reusableGroup"
          : "oneTime";
  const rawSpace = typeof d.spaceType === "string" ? d.spaceType : "family";
  const spaceType: CollaborationSpaceType =
    rawSpace === "roommates" || rawSpace === "group" ? rawSpace : "family";

  return {
    inviteId: String(d.inviteId ?? d.inviteCode ?? code),
    inviteCode: String(d.inviteCode ?? code),
    familyId: String(d.familyId ?? ""),
    familyName: String(d.familyName ?? "Không gian chung"),
    spaceType,
    inviteKind,
    isTargeted: Boolean(d.isTargeted ?? (inviteKind === "targeted" || hasHash)),
    createdBy: String(d.createdBy ?? d.invitedByUserId ?? ""),
    invitedByUserId: String(d.invitedByUserId ?? d.createdBy ?? ""),
    invitedByName: String(d.invitedByName ?? "Trưởng nhóm"),
    inviteeName: typeof d.inviteeName === "string" ? d.inviteeName : undefined,
    intendedRecipientHash: typeof d.intendedRecipientHash === "string" ? d.intendedRecipientHash : undefined,
    maxUses,
    usedCount,
    consumedBy: typeof d.consumedBy === "string" ? d.consumedBy : null,
    consumedAtMs: d.consumedAt != null ? tsToMs(d.consumedAt, nowMs) : null,
    revoked,
    revokedBy: typeof d.revokedBy === "string" ? d.revokedBy : null,
    revokedAtMs: d.revokedAt != null ? tsToMs(d.revokedAt, nowMs) : null,
    status,
    expiresAtMs: tsToMs(d.expiresAt, nowMs),
    createdAtMs: tsToMs(d.createdAt, nowMs),
    updatedAtMs: tsToMs(d.updatedAt, nowMs)
  };
}

export class FirestoreAdminFamilyInviteStore implements FamilyInviteStore {
  constructor(private readonly db: admin.firestore.Firestore) {}

  async runTransaction<T>(fn: (tx: FamilyInviteTxContext) => Promise<T>): Promise<T> {
    return this.db.runTransaction(async (tx) => {
      const ctx: FamilyInviteTxContext = {
        getFamily: async (familyId) => {
          const snap = await tx.get(this.db.collection("families").doc(familyId));
          if (!snap.exists) return null;
          const d = snap.data() ?? {};
          const rawSpace = typeof d.spaceType === "string" ? d.spaceType : "family";
          return {
            id: String(d.id ?? snap.id),
            name: String(d.name ?? "Gia đình"),
            spaceType: rawSpace === "roommates" || rawSpace === "group" ? rawSpace : "family",
            createdBy: String(d.createdBy ?? ""),
            memberIds: Array.isArray(d.memberIds) ? d.memberIds.map(String) : [],
            bannedUserIds: Array.isArray(d.bannedUserIds) ? d.bannedUserIds.map(String) : [],
            memberRoles: (d.memberRoles as Record<string, string>) ?? {},
            memberNames: (d.memberNames as Record<string, string>) ?? {},
            pendingInvites: (d.pendingInvites as Record<string, Record<string, unknown>>) ?? {},
            lastJoinedInviteCode: typeof d.lastJoinedInviteCode === "string" ? d.lastJoinedInviteCode : undefined
          };
        },
        updateFamilyJoin: async (familyId, update) => {
          const ref = this.db.collection("families").doc(familyId);
          const payload: Record<string, unknown> = {
            memberIds: admin.firestore.FieldValue.arrayUnion(update.memberIdToAdd),
            [`memberRoles.${update.memberIdToAdd}`]: "member",
            [`memberNames.${update.memberIdToAdd}`]: update.memberName,
            lastJoinedInviteCode: update.inviteCode,
            updatedAt: Timestamp.fromMillis(update.nowMs)
          };
          if (update.deletePendingInvite) {
            payload[`pendingInvites.${update.inviteCode}`] = admin.firestore.FieldValue.delete();
          }
          tx.update(ref, payload);
        },
        setFamilyPendingInvite: async (familyId, inviteCode, internalPayload, nowMs) => {
          const ref = this.db.collection("families").doc(familyId);
          tx.update(ref, {
            [`pendingInvites.${inviteCode}`]: internalPayload,
            updatedAt: Timestamp.fromMillis(nowMs)
          });
        },
        deleteFamilyPendingInvite: async (familyId, inviteCode, nowMs) => {
          const ref = this.db.collection("families").doc(familyId);
          tx.update(ref, {
            [`pendingInvites.${inviteCode}`]: admin.firestore.FieldValue.delete(),
            updatedAt: Timestamp.fromMillis(nowMs)
          });
        },
        getInvite: async (inviteCode) => {
          const snap = await tx.get(this.db.collection("family_invites").doc(inviteCode));
          if (!snap.exists) return null;
          return mapInviteDoc(inviteCode, snap.data() ?? {}, Date.now());
        },
        setInvite: async (invite) => {
          const ref = this.db.collection("family_invites").doc(invite.inviteCode);
          // STRICT FIX-003: NEVER write raw `inviteeContact`, `email`, or `phone` on public `family_invites`!
          const docData: Record<string, unknown> = {
            inviteId: invite.inviteId,
            inviteCode: invite.inviteCode,
            familyId: invite.familyId,
            familyName: invite.familyName,
            spaceType: invite.spaceType,
            inviteKind: invite.inviteKind,
            isTargeted: invite.isTargeted,
            createdBy: invite.createdBy,
            invitedByUserId: invite.invitedByUserId,
            invitedByName: invite.invitedByName,
            maxUses: invite.maxUses,
            usedCount: invite.usedCount,
            consumedBy: invite.consumedBy ?? null,
            consumedAt: invite.consumedAtMs != null ? Timestamp.fromMillis(invite.consumedAtMs) : null,
            revoked: invite.revoked,
            revokedAt: invite.revokedAtMs != null ? Timestamp.fromMillis(invite.revokedAtMs) : null,
            status: invite.status,
            expiresAt: Timestamp.fromMillis(invite.expiresAtMs),
            createdAt: Timestamp.fromMillis(invite.createdAtMs),
            updatedAt: Timestamp.fromMillis(invite.updatedAtMs)
          };
          if (invite.inviteeName) docData.inviteeName = invite.inviteeName;
          if (invite.intendedRecipientHash) docData.intendedRecipientHash = invite.intendedRecipientHash;
          tx.set(ref, docData);
        },
        updateInvite: async (inviteCode, patch) => {
          const ref = this.db.collection("family_invites").doc(inviteCode);
          const payload: Record<string, unknown> = {};
          if (patch.usedCount !== undefined) payload.usedCount = patch.usedCount;
          if (patch.consumedBy !== undefined) payload.consumedBy = patch.consumedBy;
          if (patch.consumedAtMs !== undefined) {
            payload.consumedAt = patch.consumedAtMs != null ? Timestamp.fromMillis(patch.consumedAtMs) : null;
          }
          if (patch.revoked !== undefined) payload.revoked = patch.revoked;
          if (patch.revokedBy !== undefined) payload.revokedBy = patch.revokedBy;
          if (patch.revokedAtMs !== undefined) {
            payload.revokedAt = patch.revokedAtMs != null ? Timestamp.fromMillis(patch.revokedAtMs) : null;
          }
          if (patch.status !== undefined) payload.status = patch.status;
          if (patch.updatedAtMs !== undefined) payload.updatedAt = Timestamp.fromMillis(patch.updatedAtMs);
          tx.update(ref, payload);
        },
        updateUserActiveFamily: async (uid, familyId, nowMs) => {
          const ref = this.db.collection("users").doc(uid);
          tx.set(
            ref,
            {
              id: uid,
              familyId,
              activeFamilyId: familyId,
              familyIds: admin.firestore.FieldValue.arrayUnion(familyId),
              updatedAt: Timestamp.fromMillis(nowMs)
            },
            { merge: true }
          );
        }
      };

      return fn(ctx);
    });
  }

  async getInviteReadOnly(inviteCode: string): Promise<FamilyInviteRecord | null> {
    const snap = await this.db.collection("family_invites").doc(inviteCode).get();
    if (!snap.exists) return null;
    return mapInviteDoc(inviteCode, snap.data() ?? {}, Date.now());
  }

  async getRateLimit(uid: string): Promise<InviteRateLimitRecord | null> {
    const snap = await this.db.collection("family_invite_rate_limits").doc(uid).get();
    if (!snap.exists) return null;
    const d = snap.data() ?? {};
    return {
      windowStartMs: Number(d.windowStartMs ?? 0),
      failedCount: Number(d.failedCount ?? 0),
      updatedAtMs: Number(d.updatedAtMs ?? 0)
    };
  }

  async setRateLimit(uid: string, record: InviteRateLimitRecord): Promise<void> {
    await this.db.collection("family_invite_rate_limits").doc(uid).set({
      windowStartMs: record.windowStartMs,
      failedCount: record.failedCount,
      updatedAtMs: record.updatedAtMs
    });
  }
}

export class FamilyInviteCoordinator {
  constructor(
    private readonly store: FamilyInviteStore,
    private readonly nowProvider: () => number = () => Date.now()
  ) {}

  private async ensureWithinRateLimit(uid: string, nowMs: number): Promise<void> {
    const current = await this.store.getRateLimit(uid);
    if (!current) return;
    if (nowMs - current.windowStartMs < RATE_LIMIT_WINDOW_MS && current.failedCount >= RATE_LIMIT_MAX_ATTEMPTS) {
      throw new FamilyInviteError(
        "RESOURCE_EXHAUSTED",
        "Bạn đã thử quá nhiều mã mời không hợp lệ. Vui lòng đợi 1 phút rồi thử lại."
      );
    }
  }

  private async recordFailedAttempt(uid: string, nowMs: number): Promise<void> {
    const current = await this.store.getRateLimit(uid);
    if (!current || nowMs - current.windowStartMs >= RATE_LIMIT_WINDOW_MS) {
      await this.store.setRateLimit(uid, {
        windowStartMs: nowMs,
        failedCount: 1,
        updatedAtMs: nowMs
      });
      return;
    }
    await this.store.setRateLimit(uid, {
      windowStartMs: current.windowStartMs,
      failedCount: current.failedCount + 1,
      updatedAtMs: nowMs
    });
  }

  async createFamilyInvite(params: {
    actorUserId: string;
    familyId: string;
    invitedByName?: string;
    inviteKind?: InviteKind;
    maxUses?: number;
    ttlDays?: number;
    inviteeName?: string;
    inviteeContact?: string;
  }): Promise<{
    ok: true;
    inviteCode: string;
    inviteKind: InviteKind;
    maxUses: number;
    expiresAtMs: number;
    intendedRecipientHash?: string;
  }> {
    const uid = params.actorUserId.trim();
    const familyId = params.familyId.trim();
    if (!uid) throw new FamilyInviteError("UNAUTHENTICATED", "Vui lòng đăng nhập.");
    if (!familyId) throw new FamilyInviteError("INVALID_ARGUMENT", "Thiếu mã nhóm.");

    const cleanInviteeName = params.inviteeName?.trim();
    const cleanContact = params.inviteeContact?.trim();
    const hasContact = Boolean(cleanContact && cleanContact.length > 0);
    const requestedMaxUses =
      typeof params.maxUses === "number" && Number.isFinite(params.maxUses) ? Math.floor(params.maxUses) : 1;

    const effectiveKind: InviteKind =
      params.inviteKind ?? (hasContact ? "targeted" : requestedMaxUses > 1 ? "reusableGroup" : "oneTime");

    let effectiveMaxUses = requestedMaxUses;
    if (effectiveKind === "oneTime" || effectiveKind === "targeted") {
      if (requestedMaxUses !== 1 && params.maxUses !== undefined) {
        throw new FamilyInviteError("INVALID_ARGUMENT", "Mã mời 1 lần hoặc đích danh chỉ cho phép maxUses = 1.");
      }
      effectiveMaxUses = 1;
    } else {
      if (effectiveMaxUses < 2 || effectiveMaxUses > MAX_REUSABLE_USES) {
        throw new FamilyInviteError(
          "INVALID_ARGUMENT",
          `Mã mời nhóm nhiều lượt phải có số lượt từ 2 đến ${MAX_REUSABLE_USES}.`
        );
      }
    }

    if (effectiveKind === "targeted" && !hasContact) {
      throw new FamilyInviteError("INVALID_ARGUMENT", "Mã mời đích danh bắt buộc nhập Email hoặc SĐT người nhận.");
    }

    const ttlDays = Math.min(
      MAX_TTL_DAYS,
      Math.max(1, typeof params.ttlDays === "number" && Number.isFinite(params.ttlDays) ? Math.floor(params.ttlDays) : DEFAULT_TTL_DAYS)
    );
    const nowMs = this.nowProvider();
    const expiresAtMs = nowMs + ttlDays * 24 * 60 * 60 * 1000;
    const recipientHash = hasContact ? hashRecipientContact(cleanContact!) : undefined;
    const publicInviteeName = sanitizePublicInviteeName(cleanInviteeName);

    return this.store.runTransaction(async (tx) => {
      const fam = await tx.getFamily(familyId);
      if (!fam) {
        throw new FamilyInviteError("NOT_FOUND", "Không tìm thấy không gian nhóm.");
      }
      const actorRole = fam.memberRoles[uid];
      if (!fam.memberIds.includes(uid) || (actorRole !== "owner" && actorRole !== "admin")) {
        throw new FamilyInviteError("PERMISSION_DENIED", "Chỉ trưởng nhóm hoặc quản trị viên mới được tạo mã mời.");
      }

      let code = generateSecureInviteCode();
      for (let i = 0; i < 5; i++) {
        const existing = await tx.getInvite(code);
        if (!existing) break;
        code = generateSecureInviteCode();
      }

      const inviterName =
        params.invitedByName?.trim() || fam.memberNames[uid] || "Trưởng nhóm";

      const publicRecord: FamilyInviteRecord = {
        inviteId: code,
        inviteCode: code,
        familyId: fam.id,
        familyName: fam.name,
        spaceType: fam.spaceType,
        inviteKind: effectiveKind,
        isTargeted: effectiveKind === "targeted",
        createdBy: uid,
        invitedByUserId: uid,
        invitedByName: inviterName,
        inviteeName: publicInviteeName,
        intendedRecipientHash: recipientHash,
        maxUses: effectiveMaxUses,
        usedCount: 0,
        consumedBy: null,
        consumedAtMs: null,
        revoked: false,
        revokedBy: null,
        revokedAtMs: null,
        status: "active",
        expiresAtMs,
        createdAtMs: nowMs,
        updatedAtMs: nowMs
      };

      const maskedContact = maskContactForInternalDisplay(cleanContact);
      const internalPendingPayload: Record<string, unknown> = {
        inviteId: code,
        inviteCode: code,
        familyId: fam.id,
        familyName: fam.name,
        spaceType: fam.spaceType,
        inviteKind: effectiveKind,
        isTargeted: effectiveKind === "targeted",
        createdBy: uid,
        invitedByUserId: uid,
        invitedByName: inviterName,
        ...(cleanInviteeName ? { inviteeName: cleanInviteeName } : {}),
        ...(maskedContact ? { inviteeContactMasked: maskedContact } : {}),
        ...(recipientHash ? { intendedRecipientHash: recipientHash } : {}),
        maxUses: effectiveMaxUses,
        usedCount: 0,
        revoked: false,
        status: "active",
        expiresAt: Timestamp.fromMillis(expiresAtMs),
        createdAt: Timestamp.fromMillis(nowMs)
      };

      await tx.setInvite(publicRecord);
      await tx.setFamilyPendingInvite(fam.id, code, internalPendingPayload, nowMs);

      return {
        ok: true,
        inviteCode: code,
        inviteKind: effectiveKind,
        maxUses: effectiveMaxUses,
        expiresAtMs,
        ...(recipientHash ? { intendedRecipientHash: recipientHash } : {})
      };
    });
  }

  async previewFamilyInvite(params: {
    actorUserId: string;
    inviteCode: string;
  }): Promise<{
    ok: true;
    inviteCode: string;
    familyId: string;
    familyName: string;
    spaceType: CollaborationSpaceType;
    inviteKind: InviteKind;
    isTargeted: boolean;
    invitedByName: string;
    inviteeName?: string;
    maxUses: number;
    usedCount: number;
    expiresAtMs: number;
    status: InviteStatus;
  }> {
    const uid = params.actorUserId.trim();
    if (!uid) throw new FamilyInviteError("UNAUTHENTICATED", "Vui lòng đăng nhập.");

    const nowMs = this.nowProvider();
    await this.ensureWithinRateLimit(uid, nowMs);

    const cleanCode = extractInviteCode(params.inviteCode);
    if (cleanCode.length < 4) {
      await this.recordFailedAttempt(uid, nowMs);
      throw new FamilyInviteError("INVALID_ARGUMENT", "Mã mời không đúng định dạng (ví dụ: FAM-8K2P9Q).");
    }

    const inv = await this.store.getInviteReadOnly(cleanCode);
    if (!inv) {
      await this.recordFailedAttempt(uid, nowMs);
      throw new FamilyInviteError("NOT_FOUND", "Không tìm thấy lời mời khớp với mã này.");
    }
    if (inv.revoked || inv.status === "revoked") {
      await this.recordFailedAttempt(uid, nowMs);
      throw new FamilyInviteError("FAILED_PRECONDITION", "Lời mời này đã bị quản trị viên thu hồi.");
    }
    if (inv.expiresAtMs <= nowMs || inv.status === "expired") {
      await this.recordFailedAttempt(uid, nowMs);
      throw new FamilyInviteError("FAILED_PRECONDITION", "Mã mời này đã hết hạn sử dụng.");
    }
    if (inv.usedCount >= inv.maxUses || inv.status === "consumed") {
      await this.recordFailedAttempt(uid, nowMs);
      throw new FamilyInviteError("FAILED_PRECONDITION", "Mã mời này đã hết lượt sử dụng.");
    }

    return {
      ok: true,
      inviteCode: inv.inviteCode,
      familyId: inv.familyId,
      familyName: inv.familyName,
      spaceType: inv.spaceType,
      inviteKind: inv.inviteKind,
      isTargeted: inv.isTargeted,
      invitedByName: inv.invitedByName,
      ...(inv.inviteeName ? { inviteeName: inv.inviteeName } : {}),
      maxUses: inv.maxUses,
      usedCount: inv.usedCount,
      expiresAtMs: inv.expiresAtMs,
      status: inv.status
    };
  }

  async joinFamilyByInvite(params: {
    actorUserId: string;
    userName: string;
    inviteCode: string;
    authEmail?: string;
    authEmailVerified?: boolean;
    authPhoneNumber?: string;
  }): Promise<{
    ok: true;
    alreadyMember: boolean;
    familyId: string;
    familyName: string;
    spaceType: CollaborationSpaceType;
    role: "member" | "admin" | "owner";
    inviteCode: string;
    remainingUses: number;
  }> {
    const uid = params.actorUserId.trim();
    if (!uid) throw new FamilyInviteError("UNAUTHENTICATED", "Vui lòng đăng nhập.");

    const nowMs = this.nowProvider();
    await this.ensureWithinRateLimit(uid, nowMs);

    const cleanCode = extractInviteCode(params.inviteCode);
    if (cleanCode.length < 4) {
      await this.recordFailedAttempt(uid, nowMs);
      throw new FamilyInviteError("INVALID_ARGUMENT", "Mã mời không hợp lệ.");
    }

    const cleanUserName = params.userName.trim() || "Thành viên";

    try {
      return await this.store.runTransaction(async (tx) => {
        const inv = await tx.getInvite(cleanCode);
        if (!inv) {
          throw new FamilyInviteError("NOT_FOUND", "Mã mời gia đình không tồn tại.");
        }
        if (inv.revoked || inv.status === "revoked") {
          throw new FamilyInviteError("FAILED_PRECONDITION", "Lời mời này đã bị thu hồi.");
        }
        if (inv.expiresAtMs <= nowMs || inv.status === "expired") {
          throw new FamilyInviteError("FAILED_PRECONDITION", "Mã mời đã hết hạn.");
        }
        if (inv.usedCount >= inv.maxUses || inv.status === "consumed") {
          throw new FamilyInviteError("FAILED_PRECONDITION", "Mã mời này đã được sử dụng hết lượt.");
        }

        if (inv.intendedRecipientHash) {
          const verifiedEmail = params.authEmailVerified === true ? params.authEmail : undefined;
          const candidates = [verifiedEmail, params.authPhoneNumber, uid]
            .filter((v): v is string => typeof v === "string" && v.trim().length > 0)
            .map(hashRecipientContact);
          if (!candidates.includes(inv.intendedRecipientHash)) {
            throw new FamilyInviteError(
              "PERMISSION_DENIED",
              "Mã mời đích danh này chỉ dành cho đúng tài khoản đã xác minh được mời."
            );
          }
        }

        const fam = await tx.getFamily(inv.familyId);
        if (!fam) {
          throw new FamilyInviteError("NOT_FOUND", "Không gian nhóm không còn tồn tại.");
        }
        if (fam.bannedUserIds?.includes(uid)) {
          throw new FamilyInviteError(
            "PERMISSION_DENIED",
            "Tài khoản này đã bị quản trị viên không gian nhóm hạn chế tham gia lại."
          );
        }

        if (fam.memberIds.includes(uid)) {
          const existingRole = fam.memberRoles[uid];
          const role = existingRole === "owner" || existingRole === "admin" ? existingRole : "member";
          return {
            ok: true,
            alreadyMember: true,
            familyId: fam.id,
            familyName: fam.name,
            spaceType: fam.spaceType,
            role,
            inviteCode: cleanCode,
            remainingUses: Math.max(0, inv.maxUses - inv.usedCount)
          };
        }

        const nextUsed = inv.usedCount + 1;
        const exhausted = nextUsed >= inv.maxUses;
        const nextStatus: InviteStatus = exhausted ? "consumed" : "active";

        await tx.updateInvite(cleanCode, {
          usedCount: nextUsed,
          consumedBy: uid,
          consumedAtMs: nowMs,
          status: nextStatus,
          updatedAtMs: nowMs
        });
        await tx.updateFamilyJoin(fam.id, {
          memberIdToAdd: uid,
          memberName: cleanUserName,
          inviteCode: cleanCode,
          deletePendingInvite: exhausted,
          nowMs
        });
        await tx.updateUserActiveFamily(uid, fam.id, nowMs);

        return {
          ok: true,
          alreadyMember: false,
          familyId: fam.id,
          familyName: fam.name,
          spaceType: fam.spaceType,
          role: "member",
          inviteCode: cleanCode,
          remainingUses: Math.max(0, inv.maxUses - nextUsed)
        };
      });
    } catch (err) {
      if (err instanceof FamilyInviteError) {
        await this.recordFailedAttempt(uid, nowMs);
      }
      throw err;
    }
  }

  async revokeFamilyInvite(params: {
    actorUserId: string;
    familyId: string;
    inviteCode: string;
  }): Promise<{ ok: true; inviteCode: string; status: "revoked" }> {
    const uid = params.actorUserId.trim();
    const familyId = params.familyId.trim();
    const cleanCode = extractInviteCode(params.inviteCode);
    if (!uid) throw new FamilyInviteError("UNAUTHENTICATED", "Vui lòng đăng nhập.");
    if (!familyId || cleanCode.length < 4) {
      throw new FamilyInviteError("INVALID_ARGUMENT", "Thiếu familyId hoặc inviteCode hợp lệ.");
    }

    const nowMs = this.nowProvider();
    return this.store.runTransaction(async (tx) => {
      const fam = await tx.getFamily(familyId);
      if (!fam) {
        throw new FamilyInviteError("NOT_FOUND", "Không tìm thấy nhóm.");
      }
      const actorRole = fam.memberRoles[uid];
      if (!fam.memberIds.includes(uid) || (actorRole !== "owner" && actorRole !== "admin")) {
        throw new FamilyInviteError("PERMISSION_DENIED", "Chỉ trưởng nhóm hoặc quản trị mới được thu hồi mã mời.");
      }

      const inv = await tx.getInvite(cleanCode);
      if (inv) {
        if (inv.familyId !== familyId) {
          throw new FamilyInviteError("PERMISSION_DENIED", "Mã mời không thuộc không gian nhóm này.");
        }
        await tx.updateInvite(cleanCode, {
          revoked: true,
          revokedBy: uid,
          revokedAtMs: nowMs,
          status: "revoked",
          updatedAtMs: nowMs
        });
      }
      await tx.deleteFamilyPendingInvite(familyId, cleanCode, nowMs);

      return { ok: true, inviteCode: cleanCode, status: "revoked" };
    });
  }
}
