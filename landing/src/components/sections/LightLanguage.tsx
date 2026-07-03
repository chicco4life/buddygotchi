import { copy } from "@/lib/copy";
import { Reveal } from "@/components/Reveal";

/*
  S4 — The light language. The page's one dark passage. Built, not photographed:
  it's a diagram, and the one place CSS/SVG art is on-brand. Five blob
  silhouettes with their glows, all slow and soft. See SPEC.md §5 (S4).
*/
type Variant = {
  glow: string;
  anim: string;
  eye: string;
  body: string;
};

const VARIANTS: Record<string, Variant> = {
  Working: { glow: "#f4d9a6", anim: "buddy-breathe", eye: "#f7f2e9", body: "#3a322b" },
  "Needs you": { glow: "#e8a33d", anim: "buddy-amber", eye: "#f7f2e9", body: "#3a322b" },
  Done: { glow: "#7fa96b", anim: "buddy-breathe", eye: "#f7f2e9", body: "#3a322b" },
  Stuck: { glow: "#c8564b", anim: "buddy-heartbeat", eye: "#e0b3ae", body: "#332723" },
  Asleep: { glow: "#3a322b", anim: "", eye: "#5a5148", body: "#2b241f" },
};

function LightBlob({ label, desc }: { label: string; desc: string }) {
  const v = VARIANTS[label];
  const sleeping = label === "Asleep";
  return (
    <div className="flex flex-col items-center gap-4 text-center">
      <svg viewBox="0 0 120 120" className="h-24 w-24" role="img" aria-label={`${label}: ${desc}`}>
        <defs>
          <radialGradient id={`glow-${label.replace(/\s/g, "")}`} cx="50%" cy="50%" r="50%">
            <stop offset="0%" stopColor={v.glow} stopOpacity="0.9" />
            <stop offset="100%" stopColor={v.glow} stopOpacity="0" />
          </radialGradient>
        </defs>
        <circle
          cx="60"
          cy="62"
          r="52"
          fill={`url(#glow-${label.replace(/\s/g, "")})`}
          className={v.anim}
          style={{ transformOrigin: "60px 62px" }}
        />
        <ellipse cx="60" cy="60" rx="34" ry="30" fill={v.body} />
        {sleeping ? (
          <>
            <path d="M48 58 q6 5 12 0" stroke={v.eye} strokeWidth="2.5" fill="none" strokeLinecap="round" />
            <path d="M60 58 q6 5 12 0" stroke={v.eye} strokeWidth="2.5" fill="none" strokeLinecap="round" />
          </>
        ) : (
          <>
            <circle cx="52" cy="57" r="3.4" fill={v.eye} />
            <circle cx="68" cy="57" r="3.4" fill={v.eye} />
          </>
        )}
      </svg>
      <span className="text-xs font-semibold uppercase tracking-[0.08em] text-night-text/70">
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
          <div className="flex flex-wrap justify-center gap-x-10 gap-y-12 sm:gap-x-16">
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
