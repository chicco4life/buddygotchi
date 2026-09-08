import { copy } from "@/lib/copy";
import { tinyLabel } from "@/lib/ui";
import { MediaImage } from "@/components/Media";
import { WaitlistCTA } from "@/components/WaitlistCTA";

/*
  S1 — Hero (100vh). One of the page's two media slots (SPEC.md Amendment A):
  a generated mock shot at public/media/hero.jpg. Until it exists, the
  art-directed placeholder (breathing amber glow) carries the scene. Real film
  replaces this when the product exists.
*/
export function Hero() {
  return (
    <section
      data-section="S1"
      aria-label="Boop — approve with a pet"
      className="relative flex min-h-[100svh] flex-col justify-end overflow-hidden"
    >
      <div className="absolute inset-0">
        <MediaImage
          src="/media/hero.jpg"
          alt="A small glowing creature sits on a desk in warm light; its glow has turned amber and a hand reaches in to pet it."
          glow="amber"
          fill
          priority
        />
      </div>

      {/* cream scrim so the copy stays legible over warm imagery */}
      <div className="pointer-events-none absolute inset-x-0 bottom-0 h-2/3 bg-gradient-to-t from-cream via-cream/85 to-transparent" />

      <div className="relative mx-auto w-full max-w-[1100px] px-6 pb-16 md:pb-24">
        <h1 className="max-w-3xl text-[clamp(2.75rem,7vw,5.5rem)] font-semibold leading-[1.05] tracking-[-0.02em]">
          {copy.hero.headline}
        </h1>
        <p className="mt-5 max-w-xl text-lg text-charcoal-soft md:text-xl">
          {copy.hero.subhead}
        </p>
        <div className="mt-8">
          <WaitlistCTA source="hero" />
        </div>
        <p className={`mt-5 ${tinyLabel}`}>{copy.hero.footnote}</p>
      </div>
    </section>
  );
}
