import { copy } from "@/lib/copy";
import { Section } from "@/components/Section";
import { Reveal } from "@/components/Reveal";

/*
  S6 — The craft. The exploded view, drawn (SPEC.md Amendment A): the five
  physical parts floating apart with hairline labels, in the same built visual
  language as the light strip. A real render replaces this when one exists.
*/
function ExplodedDiagram() {
  const [crown, shell, screen, heart, ring] = copy.craft.parts;
  const labelProps = {
    fontSize: 12,
    fill: "#6e675d",
    fontFamily: "inherit",
  } as const;
  const hairline = { stroke: "#2b2724", strokeOpacity: 0.2, strokeWidth: 1 } as const;

  return (
    <svg
      viewBox="0 0 340 430"
      className="mx-auto w-full max-w-sm"
      role="img"
      aria-label={copy.craft.diagramAria}
    >
      {/* silicone crown */}
      <path d="M78 64 a32 26 0 0 1 64 0 z" fill="#f0dfd2" stroke="#2b2724" strokeOpacity="0.1" />
      <line x1="150" y1="52" x2="196" y2="52" {...hairline} />
      <text x="202" y="56" {...labelProps}>{crown}</text>

      {/* frosted shell, glowing from within */}
      <ellipse cx="110" cy="150" rx="72" ry="58" fill="#f8f3ea" opacity="0.8" stroke="#2b2724" strokeOpacity="0.15" strokeWidth="1.5" />
      <ellipse cx="110" cy="150" rx="40" ry="30" fill="#f4d9a6" opacity="0.4" />
      <line x1="188" y1="150" x2="196" y2="150" {...hairline} />
      <text x="202" y="154" {...labelProps}>{shell}</text>

      {/* screen — the face */}
      <rect x="80" y="238" width="60" height="40" rx="9" fill="#2b2724" />
      <circle cx="95" cy="258" r="5" fill="#e8a33d" />
      <circle cx="125" cy="258" r="5" fill="#e8a33d" />
      <line x1="146" y1="258" x2="196" y2="258" {...hairline} />
      <text x="202" y="262" {...labelProps}>{screen}</text>

      {/* steel heart */}
      <circle cx="110" cy="330" r="22" fill="#b8b2a9" />
      <path d="M96 320 a22 22 0 0 1 20 -8" stroke="#e5e0d8" strokeWidth="3" fill="none" strokeLinecap="round" />
      <line x1="138" y1="330" x2="196" y2="330" {...hairline} />
      <text x="202" y="334" {...labelProps}>{heart}</text>

      {/* base ring */}
      <ellipse cx="110" cy="392" rx="52" ry="12" fill="#ded4c2" stroke="#2b2724" strokeOpacity="0.1" />
      <line x1="168" y1="392" x2="196" y2="392" {...hairline} />
      <text x="202" y="396" {...labelProps}>{ring}</text>
    </svg>
  );
}

export function Craft() {
  return (
    <Section id="S6" label="The craft">
      <Reveal>
        <div className="grid items-center gap-12 md:grid-cols-2">
          <ExplodedDiagram />
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
