import type { ReactNode } from "react";

/*
  Standard section shell: the data-section hook for scroll-depth tracking, the
  1100px column, and the minimum-120px vertical breathing. Separation by space
  alone — no cards, borders, or alternating backgrounds (SPEC.md §4.3).
*/
export function Section({
  id,
  label,
  children,
  className = "",
  inner = "",
}: {
  id: string;
  label: string;
  children: ReactNode;
  className?: string;
  inner?: string;
}) {
  return (
    <section
      data-section={id}
      aria-label={label}
      className={`px-6 py-20 md:py-28 ${className}`}
    >
      <div className={`mx-auto max-w-[1100px] ${inner}`}>{children}</div>
    </section>
  );
}
