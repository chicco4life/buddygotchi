import { copy } from "@/lib/copy";

/*
  The live counter. Ships built but hidden — this brand cannot afford a small
  lie (SPEC.md §5 S7). It renders ONLY when the operator turns it on AND supplies
  a real number:
    NEXT_PUBLIC_SHOW_COUNTER=true
    NEXT_PUBLIC_ADOPTED_COUNT=38   (the real count; nothing is invented here)
  Absent either, the section simply omits the line.
*/
export function AdoptionCounter() {
  if (process.env.NEXT_PUBLIC_SHOW_COUNTER !== "true") return null;

  const n = Number(process.env.NEXT_PUBLIC_ADOPTED_COUNT);
  if (!Number.isInteger(n) || n <= 0) return null;

  return (
    <p className="mt-6 text-sm font-semibold uppercase tracking-[0.08em] text-charcoal-soft">
      {copy.adoption.counterTemplate.replace("{n}", String(n))}
    </p>
  );
}
