import type { Metadata } from "next";
import Link from "next/link";
import { copy } from "@/lib/copy";

export const metadata: Metadata = {
  title: "Privacy — Buddygotchi",
  robots: { index: true, follow: true },
};

export default function PrivacyPage() {
  return (
    <main className="mx-auto max-w-2xl px-6 py-24 md:py-32">
      <h1 className="text-3xl font-semibold tracking-[-0.02em]">{copy.privacy.heading}</h1>
      <div className="mt-8 flex flex-col gap-5 text-lg leading-relaxed text-charcoal-soft">
        {copy.privacy.paragraphs.map((p, i) => (
          <p key={i}>{p}</p>
        ))}
      </div>
      <Link
        href="/"
        className="mt-14 inline-block text-sm text-charcoal-soft underline-offset-4 hover:text-charcoal hover:underline"
      >
        {copy.privacy.backHome}
      </Link>
    </main>
  );
}
