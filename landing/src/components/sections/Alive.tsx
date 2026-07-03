import { copy } from "@/lib/copy";
import { Section } from "@/components/Section";
import { Reveal } from "@/components/Reveal";
import { MediaVideo } from "@/components/Media";

/* S3 — It's alive. Three short loops, lazy-loaded. Carries the kindchenschema. */
export function Alive() {
  const files = ["alive-wobble.mp4", "alive-sleep.mp4", "alive-celebrate.mp4"];
  const glows = ["warm", "night", "green"] as const;
  return (
    <Section id="S3" label="It's alive">
      <Reveal>
        <div className="grid gap-10 md:grid-cols-3">
          {copy.alive.loops.map((loop, i) => (
            <figure key={i} className="flex flex-col gap-4">
              <MediaVideo
                src={`/media/${files[i]}`}
                alt={loop.note}
                note={loop.note}
                ratio={4 / 5}
                glow={glows[i]}
                lazy
              />
              <figcaption className="text-charcoal-soft italic">{loop.caption}</figcaption>
            </figure>
          ))}
        </div>
      </Reveal>
    </Section>
  );
}
