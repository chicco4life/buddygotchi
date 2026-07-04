"use client";

import { useEffect, useRef, useState, type ReactNode } from "react";

/*
  The page's two media slots (hero + adoption box — SPEC.md Amendments A/B). An
  art-directed placeholder renders underneath; the real file (dropped into
  public/media/ later, same filename) loads on top and covers it. If the file
  404s, the placeholder stays — so generated mock images swap in with zero code
  changes.

  Plain <img> (not next/image) is deliberate: the placeholder era needs graceful
  404 fallback. Swap to next/image once real files exist if desired.
*/
type MediaProps = {
  src: string;
  alt: string;
  ratio?: number; // width / height
  className?: string;
  glow?: "warm" | "amber" | "green" | "night";
  fill?: boolean; // fill the parent (hero) instead of using an aspect ratio
  priority?: boolean; // eager-load (hero)
  placeholder?: ReactNode; // custom drawn stand-in; defaults to the desk scene
};

export function MediaImage({
  src,
  alt,
  ratio = 16 / 9,
  className = "",
  glow = "warm",
  fill = false,
  priority = false,
  placeholder,
}: MediaProps) {
  const [failed, setFailed] = useState(false);
  const imgRef = useRef<HTMLImageElement>(null);

  // The error event can fire before hydration attaches onError (SSR'd <img>),
  // leaving a broken-image icon over the placeholder — recheck after mount.
  useEffect(() => {
    const img = imgRef.current;
    if (img?.complete && img.naturalWidth === 0) setFailed(true);
  }, []);

  return (
    <div
      className={`relative overflow-hidden ${fill ? "h-full w-full" : "rounded-2xl"} ${className}`}
      style={fill ? undefined : { aspectRatio: String(ratio) }}
      role="img"
      aria-label={alt}
    >
      {placeholder ?? <DeskScenePlaceholder glow={glow} />}
      {!failed && (
        // eslint-disable-next-line @next/next/no-img-element
        <img
          ref={imgRef}
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

const GLOWS: Record<string, { bg: string; desk: string; halo: string; face: string }> = {
  warm: { bg: "#efe7d8", desk: "#e6d9c1", halo: "#f4d9a6", face: "#2b2724" },
  amber: { bg: "#efe7d8", desk: "#e6d9c1", halo: "#e8a33d", face: "#2b2724" },
  green: { bg: "#eef0e6", desk: "#e2e0d0", halo: "#7fa96b", face: "#2b2724" },
  night: { bg: "#211c18", desk: "#191410", halo: "#e8a33d", face: "#efe7d8" },
};

/*
  The default drawn stand-in: a desk-scale scene, not a portrait. The blob sits
  small on a desk plane with a contact shadow and a breathing halo, so the
  placeholder already says "a physical object on your desk" — the one thing the
  page most needs a visitor to believe. Proportions per PRODUCT.md §9.1.
*/
function DeskScenePlaceholder({ glow }: { glow: keyof typeof GLOWS }) {
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
        <radialGradient id={`bg-${glow}`} cx="50%" cy="55%" r="70%">
          <stop offset="0%" stopColor={c.halo} stopOpacity={dark ? 0.5 : 0.55} />
          <stop offset="60%" stopColor={c.bg} />
          <stop offset="100%" stopColor={c.bg} />
        </radialGradient>
        <radialGradient id={`halo-${glow}`} cx="50%" cy="50%" r="50%">
          <stop offset="0%" stopColor={c.halo} stopOpacity="0.75" />
          <stop offset="100%" stopColor={c.halo} stopOpacity="0" />
        </radialGradient>
      </defs>

      {/* warm wall + desk plane: the scene reads as a desk, not a void. The
          composition sits in the upper half — in the hero, the lower third is
          under the copy scrim. */}
      <rect width="400" height="300" fill={`url(#bg-${glow})`} />
      <rect y="150" width="400" height="150" fill={c.desk} />

      {/* desk halo — the glow the product actually throws */}
      <ellipse cx="200" cy="150" rx="95" ry="19" fill={`url(#halo-${glow})`} className="buddy-breathe" style={{ transformOrigin: "200px 150px" }} />
      {/* contact shadow */}
      <ellipse cx="200" cy="151" rx="35" ry="5.5" fill={c.face} opacity={dark ? 0.35 : 0.12} />

      {/* the buddy at desk scale: squashed sphere, wider than tall. Kept small
          in the scene so portrait (mobile) slice-crops still show desk context. */}
      <ellipse cx="200" cy="116" rx="40" ry="34" fill={dark ? "#3a322b" : "#f8f3ea"} opacity="0.97" />
      {/* screen face, slightly above midline */}
      <rect x="181" y="94" width="38" height="24" rx="8" fill={c.face} opacity="0.92" />
      {/* eyes */}
      <circle cx="192" cy="106" r="3.6" fill={dark ? "#e8a33d" : "#f7f2e9"} />
      <circle cx="208" cy="106" r="3.6" fill={dark ? "#e8a33d" : "#f7f2e9"} />
      {/* blush */}
      <circle cx="171" cy="114" r="4.5" fill="#e79aa0" opacity="0.5" />
      <circle cx="229" cy="114" r="4.5" fill="#e79aa0" opacity="0.5" />
    </svg>
  );
}
