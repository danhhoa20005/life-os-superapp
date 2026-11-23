import * as crypto from "node:crypto";

export const MAX_WEBHOOK_BODY_BYTES = 64 * 1024; // 64 KB hard limit
export const MAX_TIMESTAMP_SKEW_SECONDS = 300; // ±300s anti-replay window

const OTP_PATTERNS: readonly RegExp[] = [
  /\b(otp|smart\s*otp|digital\s*otp|s-otp|m-otp)\b/i,
  /\bm[aã]\s*(x[aá]c\s*th[uự]c|x[aá]c\s*nh[aậ]n|b[aả]o\s*m[aậ]t|k[ií]ch\s*ho[aạ]t)\b/i,
  /\b(verification|security|auth|activation|one[- ]time)\s*(code|pin|password)\b/i,
  /\b(cvv|cvc|m[aã]\s*pin|m[aậ]t\s*kh[aẩ]u)\b/i
];

export function containsOtpOrSecret(text: string): boolean {
  if (!text) return false;
  return OTP_PATTERNS.some((re) => re.test(text));
}

export function maskAccountNumber(accountNumber: string): string {
  const clean = accountNumber.replace(/[^A-Za-z0-9]/g, "").trim();
  if (clean.length <= 4) return "••••";
  return `•••• ${clean.slice(-4)}`;
}

export function computeHmacSha256Hex(secret: string, signedPayload: string): string {
  return crypto.createHmac("sha256", Buffer.from(secret, "utf8")).update(signedPayload, "utf8").digest("hex");
}

export interface SignatureVerificationResult {
  readonly ok: boolean;
  readonly statusCode: number;
  readonly errorCode?: "MISSING_SECRET" | "MISSING_HEADERS" | "INVALID_TIMESTAMP" | "REPLAY_EXPIRED" | "INVALID_SIGNATURE";
  readonly message?: string;
}

/**
 * Verifies SePay Webhook HMAC-SHA256 signature & anti-replay timestamp in constant time:
 *   X-SePay-Signature: sha256=<hex>
 *   X-SePay-Timestamp: <unix_seconds>
 *   signedPayload = timestamp + "." + rawBody
 *   signature = HMAC_SHA256(secret, signedPayload)
 */
export function verifySePayWebhookSignature(params: {
  rawBody: Buffer;
  signatureHeader: string | undefined;
  timestampHeader: string | undefined;
  secret: string | undefined;
  nowEpochSeconds?: number;
  maxSkewSeconds?: number;
}): SignatureVerificationResult {
  const {
    rawBody,
    signatureHeader,
    timestampHeader,
    secret,
    nowEpochSeconds = Math.floor(Date.now() / 1000),
    maxSkewSeconds = MAX_TIMESTAMP_SKEW_SECONDS
  } = params;

  if (!secret || secret.trim().length < 16) {
    return {
      ok: false,
      statusCode: 500,
      errorCode: "MISSING_SECRET",
      message: "Webhook secret is not configured on backend."
    };
  }

  if (!signatureHeader || !timestampHeader) {
    return {
      ok: false,
      statusCode: 401,
      errorCode: "MISSING_HEADERS",
      message: "Missing X-SePay-Signature or X-SePay-Timestamp header."
    };
  }

  const tsTrimmed = timestampHeader.trim();
  if (!/^\d{9,12}$/.test(tsTrimmed)) {
    return {
      ok: false,
      statusCode: 401,
      errorCode: "INVALID_TIMESTAMP",
      message: "Malformed X-SePay-Timestamp header."
    };
  }

  const tsSeconds = Number.parseInt(tsTrimmed, 10);
  if (!Number.isSafeInteger(tsSeconds) || Math.abs(nowEpochSeconds - tsSeconds) > maxSkewSeconds) {
    return {
      ok: false,
      statusCode: 401,
      errorCode: "REPLAY_EXPIRED",
      message: "Webhook timestamp outside allowed ±300s replay window."
    };
  }

  const sigTrimmed = signatureHeader.trim();
  const hexPart = sigTrimmed.toLowerCase().startsWith("sha256=")
    ? sigTrimmed.slice(7).trim()
    : sigTrimmed;

  if (!/^[0-9a-fA-F]{64}$/.test(hexPart)) {
    return {
      ok: false,
      statusCode: 401,
      errorCode: "INVALID_SIGNATURE",
      message: "Malformed HMAC-SHA256 digest."
    };
  }

  const rawUtf8 = rawBody.toString("utf8");
  const signedPayload = `${tsTrimmed}.${rawUtf8}`;
  const expectedHex = computeHmacSha256Hex(secret, signedPayload);

  const providedBuf = Buffer.from(hexPart.toLowerCase(), "hex");
  const expectedBuf = Buffer.from(expectedHex.toLowerCase(), "hex");

  if (providedBuf.length !== expectedBuf.length || !crypto.timingSafeEqual(providedBuf, expectedBuf)) {
    return {
      ok: false,
      statusCode: 401,
      errorCode: "INVALID_SIGNATURE",
      message: "HMAC-SHA256 signature verification failed."
    };
  }

  return { ok: true, statusCode: 200 };
}

export function sha256Hex(input: string): string {
  return crypto.createHash("sha256").update(input, "utf8").digest("hex");
}
