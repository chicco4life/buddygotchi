import { copy } from "@/lib/copy";
import { Section } from "@/components/Section";
import { Reveal } from "@/components/Reveal";
import { BuddyBlob, type Expression } from "@/components/BuddyBlob";

/*
  S2 — The moment (the alibi, shown not told). Three beats, drawn rather than
  photographed (SPEC.md Amendment A): asks → pet → back to work. The terminal
  chip under beat one is the whole rational story in one line.
*/
const BEAT_VISUALS: {
  expression: Expression;
  glow: "amber" | "warm" | "green";
  glowAnim?: "pulse";
  petting?: boolean;
}[] = [
  { expression: "alert", glow: "amber", glowAnim: "pulse" },
  { expression: "squint", glow: "warm", petting: true },
  { expression: "content", glow: "green" },
];

export function Moment() {
  return (
    <Section id="S2" label="The moment it needs you">
      <Reveal>
        <div className="grid gap-14 md:grid-cols-3">
          {copy.moment.beats.map((beat, i) => (
            <figure key={beat.caption} className="flex flex-col items-center gap-2 text-center">
              <BuddyBlob {...BEAT_VISUALS[i]} label={beat.aria} className="h-40 w-40" />
              {/* fixed-height chip row keeps the three captions on one line */}
              <div className="flex h-8 items-center">
                {"screen" in beat && (
                  <code className="rounded-lg bg-night px-3 py-1.5 font-mono text-xs text-night-text/90">
                    {beat.screen}
                  </code>
                )}
              </div>
              <figcaption className="mt-2 text-lg font-semibold">{beat.caption}</figcaption>
            </figure>
          ))}
        </div>
        <p className="mx-auto mt-14 max-w-2xl text-center text-charcoal-soft">
          {copy.moment.line}
        </p>
      </Reveal>
    </Section>
  );
}
