import { NextResponse } from "next/server";
import { verifyStripeSignature } from "@/lib/stripe-webhook";
import { isBackendReady, markDepositPaid } from "@/lib/waitlist";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

/*
  Stripe webhook: the server-to-server source of truth for "did this signup pay
  the $5 deposit." Fires independently of the browser redirect (/held), so a
  deposit is still recorded even if the customer closes the tab.

  We only care about `checkout.session.completed`; the session's
  `client_reference_id` is the referral code we appended to the Payment Link URL
  (see WelcomeDeposit.tsx), which maps to the signup row.

  Config: set STRIPE_WEBHOOK_SECRET (the endpoint's signing secret, `whsec_…`).
  Unset → we can't verify anything, so we no-op with 200 (fail-safe; nothing is
  trusted or written).
*/
export async function POST(req: Request) {
  const secret = process.env.STRIPE_WEBHOOK_SECRET;
  if (!secret) {
    return NextResponse.json({ skipped: "STRIPE_WEBHOOK_SECRET not set" });
  }

  const rawBody = await req.text();
  const signature = req.headers.get("stripe-signature");

  if (!verifyStripeSignature(rawBody, signature, secret)) {
    return NextResponse.json({ error: "invalid signature" }, { status: 400 });
  }

  let event: { type?: string; data?: { object?: { client_reference_id?: string | null } } };
  try {
    event = JSON.parse(rawBody);
  } catch {
    return NextResponse.json({ error: "bad payload" }, { status: 400 });
  }

  if (event.type !== "checkout.session.completed") {
    // Verified, but not an event we act on. Acknowledge so Stripe stops resending.
    return NextResponse.json({ received: true });
  }

  const code = event.data?.object?.client_reference_id;
  if (!code) {
    // Deposit with no referral code attached — nothing to reconcile automatically.
    console.warn("stripe webhook: checkout.session.completed with no client_reference_id");
    return NextResponse.json({ received: true });
  }

  if (!isBackendReady()) {
    // Verified event we can't persist (misconfigured env). Don't make Stripe
    // retry forever for a config problem.
    console.error("stripe webhook: backend not configured; deposit not recorded", code);
    return NextResponse.json({ received: true });
  }

  try {
    await markDepositPaid(code);
  } catch (err) {
    // Transient DB failure — return 500 so Stripe retries with backoff.
    console.error("stripe webhook: failed to record deposit", err);
    return NextResponse.json({ error: "server error" }, { status: 500 });
  }

  return NextResponse.json({ received: true });
}
