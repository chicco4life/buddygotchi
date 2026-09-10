import { copy } from "@/lib/copy";
import { Reveal } from "@/components/Reveal";

/*
  S4 — The light language. The page's one dark passage. Built, not photographed:
  it's a diagram, and the one place CSS/SVG art is on-brand. Five faceless shell
  silhouettes with their glows — the faces live in S2/S3; here only the light
  speaks, which is the whole point of the section. "Needs you" is deliberately
  the brightest thing on the band: amber must be unmistakable at a glance.
*/
type Variant = {
  glow: string;
  anim: string;
  innerOpacity: number; // glow core intensity
  outerOpacity: number; // halo reach
  shell: string;
  shellLit: number; // how much the shell itself lights up
};

const VARIANTS: Record<string, Variant> = {
  Working: { glow: "#f4d9a6", anim: "buddy-breathe", innerOpacity: 0.9, outerOpacity: 0.5, shell: "#4a4034", shellLit: 0.35 },
  "Needs you": { glow: "#e8a33d", anim: "buddy-amber", innerOpacity: 1, outerOpacity: 0.7, shell: "#524230", shellLit: 0.55 },
  Done: { glow: "#8fbe78", anim: "buddy-breathe", innerOpacity: 0.9, outerOpacity: 0.5, shell: "#3e4636", shellLit: 0.35 },
  Stuck: { glow: "#c8564b", anim: "buddy-heartbeat", innerOpacity: 0.85, outerOpacity: 0.45, shell: "#443029", shellLit: 0.3 },
  Asleep: { glow: "#3a322b", anim: "", innerOpacity: 0, outerOpacity: 0, shell: "#2f2822", shellLit: 0 },
};

function LightBlob({ label, desc }: { label: string; desc: string }) {
  const v = VARIANTS[label];
  const gid = `glow-${label.replace(/\s/g, "")}`;
  const emphasized = label === "Needs you";
  // Emphasis is drawn as bigger shapes inside a uniform box — a taller box
  // would lift this blob's center above its bottom-aligned neighbors.
  const s = emphasized ? 1.13 : 1;
  return (
    <div className="flex flex-col items-center gap-4 text-center">
      <svg
        viewBox="0 0 140 140"
        className="h-28 w-28"
        role="img"
        aria-label={`${label}: ${desc}`}
      >
        {v.innerOpacity > 0 && (
          <defs>
            <radialGradient id={gid} cx="50%" cy="50%" r="50%">
              <stop offset="0%" stopColor={v.glow} stopOpacity={v.innerOpacity} />
              <stop offset="45%" stopColor={v.glow} stopOpacity={v.outerOpacity} />
              <stop offset="100%" stopColor={v.glow} stopOpacity="0" />
            </radialGradient>
          </defs>
        )}
        {v.innerOpacity > 0 && (
          <circle
            cx="70"
            cy="72"
            r="66"
            fill={`url(#${gid})`}
            className={v.anim}
            style={{ transformOrigin: "70px 72px" }}
          />
        )}
        {/* the shell silhouette, lit from within */}
        <ellipse cx="70" cy="72" rx={38 * s} ry={33 * s} fill={v.shell} />
        {v.shellLit > 0 && (
          <ellipse cx="70" cy={72 - 8 * s} rx={26 * s} ry={18 * s} fill={v.glow} opacity={v.shellLit} />
        )}
        {/* asleep: the faintest outline so the dark shape still reads as the buddy */}
        {label === "Asleep" && (
          <ellipse cx="70" cy="72" rx="38" ry="33" fill="none" stroke="#efe7d8" strokeOpacity="0.15" />
        )}
      </svg>
      <span
        className={`text-xs font-semibold uppercase tracking-[0.08em] ${
          emphasized ? "text-amber" : "text-night-text/70"
        }`}
      >
        {label}
      </span>
    </div>
  );
}

export function LightLanguage() {
  return (
    <section
      data-section="S4"
      aria-label="The light language"
      className="bg-night px-6 py-24 text-night-text md:py-32"
    >
      <div className="mx-auto max-w-[1100px]">
        <Reveal>
          <div className="flex flex-wrap items-end justify-center gap-x-10 gap-y-12 lg:gap-x-14">
            {copy.light.states.map((s) => (
              <LightBlob key={s.label} label={s.label} desc={s.desc} />
            ))}
          </div>
          <p className="mx-auto mt-14 max-w-2xl text-center text-night-text/80">
            {copy.light.caption}
          </p>
        </Reveal>
      </div>
    </section>
  );
}
