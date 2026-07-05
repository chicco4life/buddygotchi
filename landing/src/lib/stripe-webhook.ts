import { createHmac, timingSafeEqual } from "node:crypto";

/*
  Stripe webhook signature verification, done by hand so we take on no SDK
  dependency (same posture as the Resend integration — see src/lib/email.ts).

  Stripe signs each webhook with the endpoint's signing secret and sends a
  `Stripe-Signature` header shaped like:

    t=1719000000,v1=hexmac,v1=anotherhexmac

  The signed payload is `${t}.${rawBody}`, HMAC-SHA256'd with the secret. We
  recompute it and constant-time-compare against every provided v1 signature,
  and reject timestamps outside a tolerance window to blunt replay.

  This function is intentionally pure (takes `nowMs` for deterministic tests).
*/

const DEFAULT_TOLERANCE_SECONDS = 300;

type ParsedHeader = { timestamp: number; signatures: string[] };

function parseSignatureHeader(header: string): ParsedHeader | null {
  let timestamp = NaN;
  const signatures: string[] = [];
  for (const part of header.split(",")) {
    const eq = part.indexOf("=");
    if (eq === -1) continue;
    const key = part.slice(0, eq).trim();
    const value = part.slice(eq + 1).trim();
    if (key === "t") timestamp = Number(value);
    else if (key === "v1") signatures.push(value);
  }
  if (!Number.isFinite(timestamp) || signatures.length === 0) return null;
  return { timestamp, signatures };
}

function safeEqualHex(a: string, b: string): boolean {
  // Hex only, equal length, then constant-time compare.
  if (!/^[0-9a-f]+$/i.test(a) || !/^[0-9a-f]+$/i.test(b)) return false;
  if (a.length !== b.length) return false;
  return timingSafeEqual(Buffer.from(a, "hex"), Buffer.from(b, "hex"));
}

export function verifyStripeSignature(
  rawBody: string,
  header: string | null,
  secret: string | undefined,
  nowMs: number = Date.now(),
  toleranceSeconds: number = DEFAULT_TOLERANCE_SECONDS,
): boolean {
  if (!secret || !header) return false;

  const parsed = parseSignatureHeader(header);
  if (!parsed) return false;

  const ageSeconds = Math.abs(nowMs / 1000 - parsed.timestamp);
  if (ageSeconds > toleranceSeconds) return false;

  const expected = createHmac("sha256", secret)
    .update(`${parsed.timestamp}.${rawBody}`, "utf8")
    .digest("hex");

  return parsed.signatures.some((sig) => safeEqualHex(sig, expected));
}
