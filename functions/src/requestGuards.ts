import * as admin from "firebase-admin";
import { HttpsError } from "firebase-functions/v2/https";

/**
 * Controls Firebase App Check enforcement on Gen 2 Callable functions via env flag.
 */
export function enforceAppCheckFlag(): boolean {
  return process.env.LIFEOS_ENFORCE_APP_CHECK === "true";
}

/**
 * Validates that callable payload is a plain object containing only allowlisted keys.
 */
export function assertAllowedKeys(
  rawData: unknown,
  allowedKeys: readonly string[]
): Record<string, unknown> {
  if (rawData === undefined || rawData === null) {
    return {};
  }
  if (typeof rawData !== "object" || Array.isArray(rawData)) {
    throw new HttpsError(
      "invalid-argument",
      "Dữ liệu đầu vào phải là một đối tượng JSON hợp lệ."
    );
  }
  const rec = rawData as Record<string, unknown>;
  const allowedSet = new Set(allowedKeys);
  for (const key of Object.keys(rec)) {
    if (!allowedSet.has(key)) {
      throw new HttpsError(
        "invalid-argument",
        `Tham số đầu vào không được phép: ${key}.`
      );
    }
  }
  return rec;
}

export interface BoundedStringOptions {
  readonly required?: boolean;
  readonly minLength?: number;
  readonly maxLength?: number;
  readonly pattern?: RegExp;
}

/**
 * Enforces string type, length bounds, optional requirement and regex pattern.
 */
export function assertBoundedString(
  value: unknown,
  fieldName: string,
  options: BoundedStringOptions = {}
): string {
  const { required = false, minLength = 0, maxLength = 256, pattern } = options;

  if (value === undefined || value === null) {
    if (required) {
      throw new HttpsError("invalid-argument", `Thiếu trường bắt buộc: ${fieldName}.`);
    }
    return "";
  }

  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", `Trường ${fieldName} phải là chuỗi ký tự.`);
  }

  if (value.length > maxLength) {
    throw new HttpsError(
      "invalid-argument",
      `Trường ${fieldName} vượt quá độ dài tối đa (${maxLength} ký tự).`
    );
  }

  const trimmed = value.trim();
  if (required && trimmed.length === 0) {
    throw new HttpsError("invalid-argument", `Thiếu trường bắt buộc: ${fieldName}.`);
  }

  if (trimmed.length > 0 && trimmed.length < minLength) {
    throw new HttpsError(
      "invalid-argument",
      `Trường ${fieldName} phải có ít nhất ${minLength} ký tự.`
    );
  }

  if (pattern && trimmed.length > 0 && !pattern.test(trimmed)) {
    throw new HttpsError("invalid-argument", `Trường ${fieldName} không đúng định dạng.`);
  }

  return trimmed;
}

/**
 * Validates an optional boolean field.
 */
export function assertOptionalBoolean(
  value: unknown,
  fieldName: string,
  defaultValue = false
): boolean {
  if (value === undefined || value === null) {
    return defaultValue;
  }
  if (typeof value !== "boolean") {
    throw new HttpsError("invalid-argument", `Trường ${fieldName} phải là boolean.`);
  }
  return value;
}

function sanitizeRateLimitKeyPart(raw: string): string {
  return raw.replace(/[^A-Za-z0-9_.-]/g, "_").slice(0, 120);
}

/**
 * Transactional per-UID fixed-window rate limiter backed by `api_rate_limits/{endpoint}_{uid}`.
 */
export async function assertPerUidRateLimit(
  db: admin.firestore.Firestore,
  uid: string,
  endpoint: string,
  maxRequests: number,
  windowMs: number,
  nowMs: number = Date.now()
): Promise<void> {
  const cleanUid = uid.trim();
  const cleanEndpoint = endpoint.trim();
  if (!cleanUid || !cleanEndpoint || maxRequests <= 0 || windowMs <= 0) {
    throw new HttpsError("invalid-argument", "Tham số giới hạn tần suất không hợp lệ.");
  }

  const docId = `${sanitizeRateLimitKeyPart(cleanEndpoint)}_${sanitizeRateLimitKeyPart(cleanUid)}`;
  const ref = db.collection("api_rate_limits").doc(docId);

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) {
      tx.set(ref, {
        uid: cleanUid,
        endpoint: cleanEndpoint,
        windowStartMs: nowMs,
        count: 1,
        updatedAtMs: nowMs,
        expiresAtMs: nowMs + windowMs
      });
      return;
    }

    const data = snap.data() ?? {};
    const windowStartMs = typeof data.windowStartMs === "number" ? data.windowStartMs : 0;
    const count = typeof data.count === "number" ? data.count : 0;

    if (nowMs - windowStartMs >= windowMs) {
      tx.set(
        ref,
        {
          uid: cleanUid,
          endpoint: cleanEndpoint,
          windowStartMs: nowMs,
          count: 1,
          updatedAtMs: nowMs,
          expiresAtMs: nowMs + windowMs
        },
        { merge: true }
      );
      return;
    }

    if (count >= maxRequests) {
      throw new HttpsError(
        "resource-exhausted",
        "Bạn gửi quá nhiều yêu cầu liên tiếp. Vui lòng thử lại sau ít phút."
      );
    }

    tx.set(
      ref,
      {
        uid: cleanUid,
        endpoint: cleanEndpoint,
        windowStartMs,
        count: count + 1,
        updatedAtMs: nowMs,
        expiresAtMs: windowStartMs + windowMs
      },
      { merge: true }
    );
  });
}

/**
 * Executes upstream HTTP calls with a strict timeout via `AbortSignal.timeout`.
 * Never logs Authorization headers, API tokens, or raw financial payloads.
 */
export async function fetchWithTimeout(
  url: string,
  init: RequestInit = {},
  timeoutMs = 10_000
): Promise<Response> {
  const timeoutSignal = AbortSignal.timeout(timeoutMs);
  const signal = init.signal ? AbortSignal.any([init.signal, timeoutSignal]) : timeoutSignal;
  return fetch(url, { ...init, signal });
}
