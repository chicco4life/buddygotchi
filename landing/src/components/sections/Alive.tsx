import { copy } from "@/lib/copy";
import { Section } from "@/components/Section";
import { Reveal } from "@/components/Reveal";
import { BuddyBlob } from "@/components/BuddyBlob";

/*
  S3 — It's alive. The three retellable delights, drawn and animated in CSS
  (SPEC.md Amendment A): the damped wobble, the sleep peek, the celebration.
  Real close-shot loops replace these when the product exists.
*/
export function Alive() {
  const v = copy.alive.vignettes;
  return (
    <Section id="S3" label="It's alive">
      <Reveal>
        <div className="grid gap-14 md:grid-cols-3">
          <figure className="flex flex-col items-center gap-4 text-center">
            <BuddyBlob
              expression="squint"
              glow="warm"
              wobble
              label={v[0].aria}
              className="h-48 w-48"
            />
            <figcaption className="italic text-charcoal-soft">{v[0].caption}</figcaption>
          </figure>

          <figure className="flex flex-col items-center gap-4 text-center">
            <BuddyBlob
              expression="sleep"
              glow="warm"
              glowAnim="none"
              peek
              zzz
              label={v[1].aria}
              className="h-48 w-48"
            />
            <figcaption className="italic text-charcoal-soft">{v[1].caption}</figcaption>
          </figure>

          <figure className="flex flex-col items-center gap-4 text-center">
            <BuddyBlob
              expression="celebrate"
              glow="green"
              confetti
              label={v[2].aria}
              className="h-48 w-48"
            />
            <figcaption className="italic text-charcoal-soft">{v[2].caption}</figcaption>
          </figure>
        </div>
      </Reveal>
    </Section>
  );
}
