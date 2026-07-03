/*
  One button style, used exactly twice (hero CTA + footer submit) so the eye
  always knows the one thing to click. See SPEC.md §4.5.
*/
export const ctaClass =
  "inline-flex items-center justify-center rounded-full bg-amber px-8 py-4 " +
  "font-semibold text-charcoal shadow-[0_8px_24px_rgb(232_163_61/0.35)] " +
  "transition-colors duration-150 ease-buddy hover:bg-amber-deep " +
  "focus-visible:outline-amber disabled:opacity-60 disabled:cursor-not-allowed";

// The only permitted ALL CAPS — tiny labels.
export const tinyLabel =
  "text-xs font-semibold uppercase tracking-[0.08em] text-charcoal-soft";
