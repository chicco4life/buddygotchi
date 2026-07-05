import { test } from "node:test";
import assert from "node:assert/strict";
import { createHmac } from "node:crypto";

const { verifyStripeSignature } = await import("../src/lib/stripe-webhook.ts");

const SECRET = "whsec_test_secret";
const BODY = JSON.stringify({ type: "checkout.session.completed", data: { object: { client_reference_id: "ABC123" } } });

function signedHeader(body, secret, timestamp) {
  const v1 = createHmac("sha256", secret).update(`${timestamp}.${body}`, "utf8").digest("hex");
  return { header: `t=${timestamp},v1=${v1}`, nowMs: timestamp * 1000 };
}

test("accepts a valid, fresh signature", () => {
  const t = 1_800_000_000;
  const { header, nowMs } = signedHeader(BODY, SECRET, t);
  assert.equal(verifyStripeSignature(BODY, header, SECRET, nowMs), true);
});

test("rejects a tampered body", () => {
  const t = 1_800_000_000;
  const { header, nowMs } = signedHeader(BODY, SECRET, t);
  assert.equal(verifyStripeSignature(BODY + " ", header, SECRET, nowMs), false);
});

test("rejects the wrong secret", () => {
  const t = 1_800_000_000;
  const { header, nowMs } = signedHeader(BODY, SECRET, t);
  assert.equal(verifyStripeSignature(BODY, header, "whsec_wrong", nowMs), false);
});

test("rejects a stale timestamp (replay)", () => {
  const t = 1_800_000_000;
  const { header } = signedHeader(BODY, SECRET, t);
  // 10 minutes later, outside the 5-minute tolerance.
  assert.equal(verifyStripeSignature(BODY, header, SECRET, (t + 600) * 1000), false);
});

test("accepts when one of several v1 signatures matches", () => {
  const t = 1_800_000_000;
  const v1 = createHmac("sha256", SECRET).update(`${t}.${BODY}`, "utf8").digest("hex");
  const header = `t=${t},v1=deadbeef,v1=${v1}`;
  assert.equal(verifyStripeSignature(BODY, header, SECRET, t * 1000), true);
});

test("rejects missing secret, header, or malformed header", () => {
  const t = 1_800_000_000;
  const { header, nowMs } = signedHeader(BODY, SECRET, t);
  assert.equal(verifyStripeSignature(BODY, header, undefined, nowMs), false);
  assert.equal(verifyStripeSignature(BODY, null, SECRET, nowMs), false);
  assert.equal(verifyStripeSignature(BODY, "garbage", SECRET, nowMs), false);
  assert.equal(verifyStripeSignature(BODY, `t=${t}`, SECRET, nowMs), false);
});
