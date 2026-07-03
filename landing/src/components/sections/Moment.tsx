import { copy } from "@/lib/copy";
import { Section } from "@/components/Section";
import { Reveal } from "@/components/Reveal";
import { MediaImage } from "@/components/Media";

/* S2 — The moment (the alibi, shown not told). Three stills, minimal captions. */
export function Moment() {
  return (
    <Section id="S2" label="The moment it needs you">
      <Reveal>
        <div className="grid gap-10 md:grid-cols-3">
          {copy.moment.stills.map((still, i) => (
            <figure key={i} className="flex flex-col gap-4">
              <MediaImage
                src={`/media/moment-${["asks", "pet", "work"][i]}.jpg`}
                alt={still.note}
                note={still.note}
                ratio={4 / 3}
                glow={i === 0 ? "amber" : "warm"}
                screen={still.screen}
              />
              <figcaption className="text-lg font-semibold">{still.caption}</figcaption>
            </figure>
          ))}
        </div>
        <p className="mx-auto mt-12 max-w-2xl text-center text-charcoal-soft">
          {copy.moment.line}
        </p>
      </Reveal>
    </Section>
  );
}
