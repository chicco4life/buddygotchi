import type { Metadata } from "next";
import Link from "next/link";
import { copy } from "@/lib/copy";
import { WelcomeShare } from "@/components/WelcomeShare";
import { WelcomeSurvey } from "@/components/WelcomeSurvey";

/*
  The post-signup page — the funnel's "end" (peak–end rule). This is a marketing
  asset, not a receipt. See SPEC.md §6.3.
*/
export const metadata: Metadata = {
  title: "You're in line — Boop",
  robots: { index: false, follow: false },
};

function HatchingEgg() {
  return (
    <svg viewBox="0 0 120 140" className="h-32 w-32" role="img" aria-label="A hatching egg">
      <defs>
        <radialGradient id="egg-glow" cx="50%" cy="45%" r="55%">
          <stop offset="0%" stopColor="#e8a33d" stopOpacity="0.5" />
          <stop offset="100%" stopColor="#e8a33d" stopOpacity="0" />
        </radialGradient>
      </defs>
      <ellipse cx="60" cy="80" rx="55" ry="20" fill="url(#egg-glow)" className="buddy-breathe" />
      {/* bottom half of the shell */}
      <path d="M18 78 a42 52 0 0 0 84 0 Z" fill="#f4ead6" />
      {/* top half, lifted and rocking (egg-peek) */}
      <g style={{ transformOrigin: "60px 78px", animation: "egg-peek 3.2s var(--ease-buddy) infinite" }}>
        <path d="M18 74 a42 52 0 0 1 84 0 l-10 4 -12 -5 -12 5 -13 -5 -12 5 Z" fill="#f8f3ea" />
      </g>
      {/* a peeking eye in the crack */}
      <circle cx="60" cy="72" r="4" fill="#2b2724" />
    </svg>
  );
}

export default async function WelcomePage({
  searchParams,
}: {
  searchParams: Promise<{ pos?: string; code?: string }>;
}) {
  const params = await searchParams;
  const pos = Number(params.pos);
  const hasPos = Number.isInteger(pos) && pos > 0;
  const code = typeof params.code === "string" ? params.code : "";

  const subline = hasPos
    ? copy.welcome.sublineTemplate.replace("{n}", String(pos))
    : copy.welcome.sublineGeneric;

  return (
    <main className="flex min-h-[100svh] flex-col items-center justify-center px-6 py-20 text-center">
      <HatchingEgg />
      <h1 className="mt-8 text-[clamp(2rem,5vw,3.25rem)] font-semibold tracking-[-0.02em]">
        {copy.welcome.heading}
      </h1>
      <p className="mt-3 max-w-md text-lg text-charcoal-soft">{subline}</p>

      {code && (
        <>
          <WelcomeShare code={code} />
          <WelcomeSurvey code={code} />
        </>
      )}

      <Link
        href="/"
        className="mt-14 text-sm text-charcoal-soft underline-offset-4 hover:text-charcoal hover:underline"
      >
        {copy.welcome.backHome}
      </Link>
    </main>
  );
}
