import { copy } from "@/lib/copy";
import { Section } from "@/components/Section";
import { Reveal } from "@/components/Reveal";
import { MediaImage } from "@/components/Media";
import { AdoptionCounter } from "@/components/AdoptionCounter";

/* S7 — The adoption. The open box; the founding-litter story; hidden counter. */
export function Adoption() {
  return (
    <Section id="S7" label="The adoption">
      <Reveal>
        <div className="grid items-center gap-12 md:grid-cols-2">
          <MediaImage
            src="/media/box.jpg"
            alt="An open adoption box: the blob nested in its insert, a care card, and a braided cream cable coiled beside it."
            note={copy.adoption.note}
            ratio={4 / 3}
            glow="warm"
          />
          <div>
            {copy.adoption.lines.map((line, i) => (
              <p
                key={i}
                className={i === 0 ? "text-xl leading-snug" : "mt-4 text-charcoal-soft"}
              >
                {line}
              </p>
            ))}
            <AdoptionCounter />
          </div>
        </div>
      </Reveal>
    </Section>
  );
}
