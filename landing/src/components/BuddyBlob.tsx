/*
  The shared illustrated buddy. Until real photography exists (SPEC.md
  Amendment A), the page's visual identity is this one drawn creature — same
  proportions as the physical product (PRODUCT.md §9.1): squashed sphere, wider
  than tall, screen-face slightly above the midline, blush dots. All motion is
  damped and slow (SPEC.md §4.4). Server component — zero client JS.
*/
type Glow = "warm" | "amber" | "green" | "red" | "none";
type GlowAnim = "breathe" | "pulse" | "heartbeat" | "none";

export type Expression = "content" | "alert" | "squint" | "sleep" | "celebrate";

const GLOW_COLORS: Record<Exclude<Glow, "none">, string> = {
  warm: "#f4d9a6",
  amber: "#e8a33d",
  green: "#7fa96b",
  red: "#c8564b",
};

const GLOW_ANIM_CLASS: Record<GlowAnim, string> = {
  breathe: "buddy-breathe",
  pulse: "buddy-amber",
  heartbeat: "buddy-heartbeat",
  none: "",
};

const SCREEN = "#2b2724";
const EYE = "#f7f2e9";
const BODY = "#f8f3ea";

function Eyes({ expression, peek }: { expression: Expression; peek: boolean }) {
  switch (expression) {
    case "alert":
      // round eyes, looking up expectantly
      return (
        <>
          <circle cx="86" cy="99" r="5.5" fill="#e8a33d" />
          <circle cx="114" cy="99" r="5.5" fill="#e8a33d" />
        </>
      );
    case "squint":
      // happy squint — closed, curved up
      return (
        <>
          <path d="M78 105 q8 -9 16 0" stroke={EYE} strokeWidth="3" fill="none" strokeLinecap="round" />
          <path d="M106 105 q8 -9 16 0" stroke={EYE} strokeWidth="3" fill="none" strokeLinecap="round" />
        </>
      );
    case "sleep":
      return (
        <>
          <path d="M78 103 q8 6 16 0" stroke={EYE} strokeWidth="3" fill="none" strokeLinecap="round" />
          {/* right eye: closed arc that fades out while an open eye peeks in */}
          <path
            d="M106 103 q8 6 16 0"
            stroke={EYE}
            strokeWidth="3"
            fill="none"
            strokeLinecap="round"
            className={peek ? "buddy-peek-out" : undefined}
          />
          {peek && <circle cx="114" cy="102" r="5" fill={EYE} opacity="0" className="buddy-peek-in" />}
        </>
      );
    case "celebrate":
      return (
        <>
          <circle cx="86" cy="100" r="5.5" fill={EYE} />
          <circle cx="114" cy="100" r="5.5" fill={EYE} />
          <path d="M88 111 q12 8 24 0" stroke={EYE} strokeWidth="3" fill="none" strokeLinecap="round" />
        </>
      );
    default:
      // content
      return (
        <>
          <circle cx="86" cy="102" r="5" fill={EYE} />
          <circle cx="114" cy="102" r="5" fill={EYE} />
        </>
      );
  }
}

export function BuddyBlob({
  expression = "content",
  glow = "warm",
  glowAnim = "breathe",
  wobble = false,
  peek = false,
  confetti = false,
  petting = false,
  zzz = false,
  label,
  className = "",
}: {
  expression?: Expression;
  glow?: Glow;
  glowAnim?: GlowAnim;
  wobble?: boolean;
  peek?: boolean;
  confetti?: boolean;
  petting?: boolean;
  zzz?: boolean;
  label?: string;
  className?: string;
}) {
  const glowColor = glow === "none" ? null : GLOW_COLORS[glow];
  const gid = `bb-glow-${glow}`;

  return (
    <svg
      viewBox="0 0 200 190"
      className={className}
      role={label ? "img" : undefined}
      aria-label={label}
      aria-hidden={label ? undefined : true}
    >
      {glowColor && (
        <defs>
          <radialGradient id={gid} cx="50%" cy="50%" r="50%">
            <stop offset="0%" stopColor={glowColor} stopOpacity="0.8" />
            <stop offset="100%" stopColor={glowColor} stopOpacity="0" />
          </radialGradient>
        </defs>
      )}

      {glowColor && (
        <ellipse
          cx="100"
          cy="112"
          rx="88"
          ry="74"
          fill={`url(#${gid})`}
          className={GLOW_ANIM_CLASS[glowAnim]}
          style={{ transformOrigin: "100px 112px" }}
        />
      )}

      {/* body group — wobble rocks around the base contact point */}
      <g className={wobble ? "buddy-wobble" : undefined} style={wobble ? { transformOrigin: "100px 164px" } : undefined}>
        <ellipse cx="100" cy="112" rx="62" ry="52" fill={BODY} />
        <rect x="70" y="84" width="60" height="38" rx="10" fill={SCREEN} />
        <Eyes expression={expression} peek={peek} />
        <circle cx="52" cy="118" r="7" fill="#e79aa0" opacity="0.5" />
        <circle cx="148" cy="118" r="7" fill="#e79aa0" opacity="0.5" />
      </g>

      {petting && (
        <g stroke="#6e675d" strokeWidth="3" strokeLinecap="round" fill="none" opacity="0.55" className="buddy-breathe" style={{ transformOrigin: "100px 48px" }}>
          <path d="M76 42 q24 -14 48 0" />
          <path d="M84 54 q16 -9 32 0" />
        </g>
      )}

      {confetti && (
        <g>
          {[
            { x: 58, y: 40, r: 3.5, c: "#e8a33d", d: "0s" },
            { x: 98, y: 26, r: 3, c: "#7fa96b", d: "0.5s" },
            { x: 140, y: 38, r: 3.5, c: "#e79aa0", d: "1s" },
            { x: 76, y: 54, r: 2.5, c: "#7fa96b", d: "1.5s" },
            { x: 124, y: 50, r: 2.5, c: "#e8a33d", d: "2s" },
            { x: 160, y: 58, r: 3, c: "#e79aa0", d: "2.5s" },
          ].map((dot, i) => (
            <circle
              key={i}
              cx={dot.x}
              cy={dot.y}
              r={dot.r}
              fill={dot.c}
              className="buddy-twinkle"
              style={{ animationDelay: dot.d, transformOrigin: `${dot.x}px ${dot.y}px` }}
            />
          ))}
        </g>
      )}

      {zzz && (
        <g fill="#6e675d" fontFamily="inherit" fontStyle="italic" fontWeight="600">
          <text x="146" y="62" fontSize="16" className="buddy-twinkle" style={{ transformOrigin: "146px 62px" }}>
            z
          </text>
          <text x="160" y="44" fontSize="12" className="buddy-twinkle" style={{ animationDelay: "1.1s", transformOrigin: "160px 44px" }}>
            z
          </text>
        </g>
      )}
    </svg>
  );
}
