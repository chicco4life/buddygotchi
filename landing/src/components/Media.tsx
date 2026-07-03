"use client";

import { useEffect, useRef, useState } from "react";

/*
  Media slot with an art-directed placeholder underneath. The real file (dropped
  into public/media/ later, same filename) loads on top and covers the
  placeholder; if it 404s, the placeholder stays. So real assets swap in with
  zero code changes. See SPEC.md §8.1.

  Plain <img>/<video> (not next/image) is used deliberately: the placeholder era
  needs graceful 404 fallback, and the placeholders themselves are inline SVG —
  no bytes to optimize. Swap to next/image once real stills exist if desired.
*/
type BaseProps = {
  src: string;
  alt: string;
  note: string;
  ratio?: number; // width / height
  className?: string;
  screen?: string; // optional terminal line drawn into the placeholder
  glow?: "warm" | "amber" | "green" | "night";
  fill?: boolean; // fill the parent (hero) instead of using an aspect ratio
};

export function MediaImage(props: BaseProps) {
  const [failed, setFailed] = useState(false);
  const { src, alt } = props;
  return (
    <MediaFrame {...props}>
      {!failed && (
        <img
          src={src}
          alt={alt}
          loading="lazy"
          decoding="async"
          onError={() => setFailed(true)}
          className="absolute inset-0 h-full w-full object-cover"
        />
      )}
    </MediaFrame>
  );
}

export function MediaVideo(props: BaseProps & { lazy?: boolean; priority?: boolean }) {
  const { src, alt, lazy = false } = props;
  const [failed, setFailed] = useState(false);
  const [active, setActive] = useState(!lazy);
  const holder = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!lazy || active) return;
    const el = holder.current;
    if (!el) return;
    const io = new IntersectionObserver(
      (entries) => {
        if (entries.some((e) => e.isIntersecting)) {
          setActive(true);
          io.disconnect();
        }
      },
      { rootMargin: "200px" },
    );
    io.observe(el);
    return () => io.disconnect();
  }, [lazy, active]);

  return (
    <div ref={holder}>
      <MediaFrame {...props}>
        {active && !failed && (
          <video
            src={src}
            autoPlay
            muted
            loop
            playsInline
            preload={lazy ? "none" : "metadata"}
            aria-label={alt}
            onError={() => setFailed(true)}
            className="absolute inset-0 h-full w-full object-cover"
          />
        )}
      </MediaFrame>
    </div>
  );
}

function MediaFrame({
  ratio = 16 / 9,
  className = "",
  note,
  screen,
  glow = "warm",
  fill = false,
  children,
}: BaseProps & { children?: React.ReactNode }) {
  return (
    <div
      className={`relative overflow-hidden ${fill ? "h-full w-full" : "rounded-2xl"} ${className}`}
      style={fill ? undefined : { aspectRatio: String(ratio) }}
      role="img"
      aria-label={note}
    >
      <BlobPlaceholder glow={glow} note={note} screen={screen} />
      {children}
    </div>
  );
}

const GLOWS: Record<string, { bg: string; halo: string; face: string }> = {
  warm: { bg: "#efe7d8", halo: "#f4d9a6", face: "#2b2724" },
  amber: { bg: "#efe7d8", halo: "#e8a33d", face: "#2b2724" },
  green: { bg: "#eef0e6", halo: "#7fa96b", face: "#2b2724" },
  night: { bg: "#211c18", halo: "#e8a33d", face: "#efe7d8" },
};

/*
  The placeholder itself: a warm field, a soft halo, and a squashed-sphere blob
  with a screen-face slightly above the midline and two blush dots — matching
  PRODUCT.md §9.1. Reads as "tasteful pre-launch," not "broken image."
*/
function BlobPlaceholder({
  glow,
  note,
  screen,
}: {
  glow: "warm" | "amber" | "green" | "night";
  note: string;
  screen?: string;
}) {
  const c = GLOWS[glow];
  const dark = glow === "night";
  return (
    <svg
      viewBox="0 0 400 300"
      preserveAspectRatio="xMidYMid slice"
      className="absolute inset-0 h-full w-full"
      aria-hidden="true"
    >
      <defs>
        <radialGradient id={`bg-${glow}`} cx="50%" cy="42%" r="75%">
          <stop offset="0%" stopColor={c.halo} stopOpacity={dark ? 0.55 : 0.9} />
          <stop offset="55%" stopColor={c.bg} />
          <stop offset="100%" stopColor={c.bg} />
        </radialGradient>
        <radialGradient id={`halo-${glow}`} cx="50%" cy="50%" r="50%">
          <stop offset="0%" stopColor={c.halo} stopOpacity="0.85" />
          <stop offset="100%" stopColor={c.halo} stopOpacity="0" />
        </radialGradient>
      </defs>

      <rect width="400" height="300" fill={`url(#bg-${glow})`} />
      <ellipse cx="200" cy="205" rx="150" ry="34" fill={`url(#halo-${glow})`} className="buddy-breathe" />

      {/* squashed-sphere body, wider than tall */}
      <ellipse cx="200" cy="150" rx="92" ry="80" fill={dark ? "#3a322b" : "#f8f3ea"} opacity="0.96" />
      {/* screen face, slightly above midline */}
      <rect x="163" y="112" width="74" height="46" rx="12" fill={c.face} opacity="0.92" />
      {/* eyes */}
      <circle cx="185" cy="135" r="6.5" fill={dark ? "#e8a33d" : "#f7f2e9"} />
      <circle cx="215" cy="135" r="6.5" fill={dark ? "#e8a33d" : "#f7f2e9"} />
      {/* blush */}
      <circle cx="150" cy="150" r="8" fill="#e79aa0" opacity="0.5" />
      <circle cx="250" cy="150" r="8" fill="#e79aa0" opacity="0.5" />

      {screen && (
        <text
          x="200"
          y="240"
          textAnchor="middle"
          fontFamily="ui-monospace, monospace"
          fontSize="11"
          fill={dark ? "#efe7d8" : "#6e675d"}
        >
          {screen}
        </text>
      )}

      <text
        x="16"
        y="286"
        fontFamily="ui-sans-serif, system-ui, sans-serif"
        fontSize="9"
        letterSpacing="0.5"
        fill={dark ? "#8f857a" : "#a99f8f"}
      >
        placeholder · {note}
      </text>
    </svg>
  );
}
