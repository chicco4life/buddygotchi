import type { Metadata } from "next";
import Link from "next/link";
import { copy } from "@/lib/copy";

/*
  Where Stripe sends the customer after a completed $5 deposit (the Payment
  Link's "After payment" redirect → https://adoptaboop.com/held). Stripe appends
  ?session_id=… which we don't need — this page is a warm, on-brand confirmation,
  not a receipt. The authoritative record of the payment comes from the webhook
  (/api/stripe/webhook), not this redirect.
*/
export const metadata: Metadata = {
  title: "Your number is held — Boop",
  robots: { index: false, follow: false },
};

function HeldMark() {
  return (
    <svg viewBox="0 0 120 120" className="h-28 w-28" role="img" aria-label="A held adoption number">
      <defs>
        <radialGradient id="held-glow" cx="50%" cy="50%" r="55%">
          <stop offset="0%" stopColor="#e8a33d" stopOpacity="0.45" />
          <stop offset="100%" stopColor="#e8a33d" stopOpacity="0" />
        </radialGradient>
      </defs>
      <circle cx="60" cy="60" r="52" fill="url(#held-glow)" className="buddy-breathe" />
      <circle cx="60" cy="60" r="34" fill="none" stroke="#e8a33d" strokeWidth="2.5" />
      {/* a soft check, drawn in the site's charcoal */}
      <path
        d="M46 61 l10 10 l20 -22"
        fill="none"
        stroke="#2b2724"
        strokeWidth="4"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}

export default function HeldPage() {
  return (
    <main className="flex min-h-[100svh] flex-col items-center justify-center px-6 py-20 text-center">
      <HeldMark />
      <h1 className="mt-8 text-[clamp(2rem,5vw,3.25rem)] font-semibold tracking-[-0.02em]">
        {copy.held.heading}
      </h1>
      <p className="mt-3 max-w-md text-lg text-charcoal-soft">{copy.held.body}</p>
      <p className="mt-4 max-w-md text-sm text-charcoal-soft">{copy.held.reassurance}</p>

      <Link
        href="/"
        className="mt-14 text-sm text-charcoal-soft underline-offset-4 hover:text-charcoal hover:underline"
      >
        {copy.held.backHome}
      </Link>
    </main>
  );
}
