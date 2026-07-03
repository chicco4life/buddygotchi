"use client";

import { useEffect } from "react";
import { track } from "@vercel/analytics";

/*
  Fires a `scroll_depth` event once per section (S1…S9) so the demand test can
  see where interest dies. Observes any element with data-section. See SPEC §7.3.
*/
export function ScrollDepth() {
  useEffect(() => {
    const seen = new Set<string>();
    const io = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (!entry.isIntersecting) continue;
          const id = (entry.target as HTMLElement).dataset.section;
          if (id && !seen.has(id)) {
            seen.add(id);
            track("scroll_depth", { section: id });
          }
        }
      },
      { threshold: 0.5 },
    );
    document.querySelectorAll("[data-section]").forEach((el) => io.observe(el));
    return () => io.disconnect();
  }, []);
  return null;
}
