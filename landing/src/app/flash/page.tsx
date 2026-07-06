import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { copy } from "@/lib/copy";
import { FlashButton } from "@/components/FlashButton";

export const metadata: Metadata = {
  title: "Flash — Boop",
  robots: { index: false, follow: false },
};

export default function FlashPage() {
  // Hidden until hardware ships: the page 404s unless the flag is set at
  // build time, and /firmware/ artifacts are only published at release
  // (research/TODOs.md).
  if (process.env.NEXT_PUBLIC_SHOW_FLASH !== "true") {
    notFound();
  }
  const flash = copy.flash;
  return (
    <main className="mx-auto max-w-2xl px-6 py-24 md:py-32">
      <h1 className="text-3xl font-semibold tracking-[-0.02em]">{flash.heading}</h1>
      <div className="mt-8 flex flex-col gap-5 text-lg leading-relaxed text-charcoal-soft">
        <p>{flash.intro}</p>
        <p>{flash.warning}</p>
      </div>
      <div className="mt-10 rounded-lg border border-charcoal/15 bg-cream-deep p-6">
        <FlashButton />
      </div>
      <p className="mt-8 text-lg leading-relaxed text-charcoal-soft">{flash.after}</p>
      <p className="mt-4 text-lg leading-relaxed text-charcoal-soft">
        <Link href="/help" className="underline underline-offset-4 hover:text-charcoal">
          {flash.helpLink}
        </Link>
      </p>
      <Link
        href="/"
        className="mt-14 inline-block text-sm text-charcoal-soft underline-offset-4 hover:text-charcoal hover:underline"
      >
        {flash.backHome}
      </Link>
    </main>
  );
}
