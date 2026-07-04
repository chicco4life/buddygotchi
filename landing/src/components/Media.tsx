"use client";

import { useState } from "react";

/*
  The page's two remaining media slots (hero + adoption box — SPEC.md
  Amendment A). An art-directed placeholder renders underneath; the real file
  (dropped into public/media/ later, same filename) loads on top and covers it.
  If the file 404s, the placeholder stays — so generated mock images swap in
  with zero code changes.

  Plain <img> (not next/image) is deliberate: the placeholder era needs graceful
  404 fallback. Swap to next/image once real files exist if desired.
*/
type MediaProps = {
  src: string;
  alt: string;
  note: string;
  ratio?: number; // width / height
  className?: string;
  glow?: "warm" | "amber" | "green" | "night";
  fill?: boolean; // fill the parent (hero) instead of using an aspect ratio
  priority?: boolean; // eager-load (hero)
};

export function MediaImage({
  src,
  alt,
  note,
  ratio = 16 / 9,
  className = "",
  glow = "warm",
  fill = false,
  priority = false,
}: MediaProps) {
  const [failed, setFailed] = useState(false);

  return (
    <div
      className={`relative overflow-hidden ${fill ? "h-full w-full" : "rounded-2xl"} ${className}`}
      style={fill ? undefined : { aspectRatio: String(ratio) }}
      role="img"
      aria-label={alt}
    >
      <BlobPlaceholder glow={glow} note={note} />
      {!failed && (
        // eslint-disable-next-line @next/next/no-img-element
        <img
          src={src}
          alt=""
          loading={priority ? "eager" : "lazy"}
          fetchPriority={priority ? "high" : undefined}
          decoding="async"
          onError={() => setFailed(true)}
          className="absolute inset-0 h-full w-full object-cover"
        />
      )}
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
  The placeholder: a warm field, a soft halo, and a squashed-sphere blob with a
  screen-face slightly above the midline and two blush dots — matching
  PRODUCT.md §9.1. Reads as "tasteful pre-launch," not "broken image."
*/
function BlobPlaceholder({ glow, note }: { glow: keyof typeof GLOWS; note: string }) {
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
