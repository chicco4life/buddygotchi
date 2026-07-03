import { copy } from "@/lib/copy";
import { Section } from "@/components/Section";
import { Reveal } from "@/components/Reveal";

/*
  S5 — The rational floor (compatibility + trust). Restrained, small type.
  Agent names are text wordmarks, not logo files (SPEC.md §8.3 — legally clean).
*/
export function RationalFloor() {
  return (
    <Section id="S5" label="Compatibility and trust">
      <Reveal>
        <div className="flex flex-col items-center gap-3 text-center">
          <div className="flex flex-wrap items-center justify-center gap-x-6 gap-y-2 text-lg font-semibold tracking-wide text-charcoal-soft">
            {copy.rational.agents.map((name, i) => (
              <span key={name} className="flex items-center gap-6">
                {i > 0 && <span aria-hidden="true" className="text-charcoal-soft/40">·</span>}
                {name}
              </span>
            ))}
          </div>
          <p className="text-charcoal-soft">{copy.rational.agentsCaption}</p>
        </div>

        <div className="mt-16 grid gap-10 md:grid-cols-3">
          {copy.rational.trust.map((t) => (
            <div key={t.title} className="text-center md:text-left">
              <h3 className="font-semibold">{t.title}</h3>
              <p className="mt-2 text-charcoal-soft">{t.body}</p>
            </div>
          ))}
        </div>
      </Reveal>
    </Section>
  );
}
