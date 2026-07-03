import { copy } from "@/lib/copy";
import { Section } from "@/components/Section";
import { Reveal } from "@/components/Reveal";
import { MediaImage } from "@/components/Media";

/* S6 — The craft. Exploded-view render (the one acceptable render) + sparse copy. */
export function Craft() {
  return (
    <Section id="S6" label="The craft">
      <Reveal>
        <div className="grid items-center gap-12 md:grid-cols-2">
          <MediaImage
            src="/media/exploded.jpg"
            alt="An exploded view of the blob: frosted shell, screen, silicone crown, steel disc, and base ring floating apart."
            note={copy.craft.note}
            ratio={4 / 5}
            glow="warm"
          />
          <div className="flex flex-col gap-6">
            {copy.craft.lines.map((line, i) => (
              <p key={i} className="text-xl italic leading-snug text-charcoal">
                {line}
              </p>
            ))}
          </div>
        </div>
      </Reveal>
    </Section>
  );
}
