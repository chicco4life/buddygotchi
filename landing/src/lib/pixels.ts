/*
  Ad-pixel conversion events for the demand test. Each fires only if the pixel
  actually loaded (its env ID was set — see components/Pixels.tsx). Safe no-op
  otherwise. See SPEC.md §7.3.
*/
declare global {
  interface Window {
    rdt?: (...args: unknown[]) => void;
    twq?: (...args: unknown[]) => void;
    fbq?: (...args: unknown[]) => void;
  }
}

export function fireLead(source: "hero" | "adoption" | "footer"): void {
  if (typeof window === "undefined") return;
  try {
    window.rdt?.("track", "SignUp");
    window.twq?.("event", "signup", { source });
    window.fbq?.("track", "Lead", { source });
  } catch {
    // never let analytics break the signup flow
  }
}

export {};
