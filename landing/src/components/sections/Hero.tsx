import { copy } from "@/lib/copy";
import { tinyLabel } from "@/lib/ui";
import { MediaVideo } from "@/components/Media";
import { HeroCTA } from "@/components/HeroCTA";

/* S1 — Hero (100vh). Full-bleed muted loop, text over the lower third. */
export function Hero() {
  return (
    <section
      data-section="S1"
      aria-label="Buddygotchi — approve with a pet"
      className="relative flex min-h-[100svh] flex-col justify-end overflow-hidden"
    >
      <div className="absolute inset-0">
        <MediaVideo
          src="/media/hero-loop.mp4"
          alt="A small glowing creature sits on a desk; its glow turns amber, a hand reaches in and pets it, and a green ripple runs through it."
          note={copy.hero.mediaNote}
          glow="amber"
          fill
          priority
        />
      </div>

      {/* cream scrim so the copy stays legible over warm footage */}
      <div className="pointer-events-none absolute inset-x-0 bottom-0 h-2/3 bg-gradient-to-t from-cream via-cream/85 to-transparent" />

      <div className="relative mx-auto w-full max-w-[1100px] px-6 pb-16 md:pb-24">
        <h1 className="max-w-3xl text-[clamp(2.75rem,7vw,5.5rem)] font-semibold leading-[1.05] tracking-[-0.02em]">
          {copy.hero.headline}
        </h1>
        <p className="mt-5 max-w-xl text-lg text-charcoal-soft md:text-xl">
          {copy.hero.subhead}
        </p>
        <div className="mt-8">
          <HeroCTA />
        </div>
        <p className={`mt-5 ${tinyLabel}`}>{copy.hero.footnote}</p>
      </div>
    </section>
  );
}
