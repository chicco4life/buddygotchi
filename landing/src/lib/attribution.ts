/*
  First-touch attribution for the demand test. Reads UTM params, price cohort,
  referral code, and referrer on the first visit and stores them in a single
  first-party cookie. Later organic revisits do NOT overwrite paid attribution.
  The waitlist API reads this cookie server-side. See SPEC.md §7.2.
*/
export type Attribution = {
  priceCohort?: number;
  utm_source?: string;
  utm_medium?: string;
  utm_campaign?: string;
  utm_content?: string;
  utm_term?: string;
  referrer?: string;
  ref_code_used?: string;
  ts?: string;
};

export const ATTR_COOKIE = "bg_attr";
const UTM_KEYS = ["utm_source", "utm_medium", "utm_campaign", "utm_content", "utm_term"] as const;
const VALID_COHORTS = new Set([99, 129]);
export const DEFAULT_PRICE = 119;

function readCookie(name: string): string | null {
  if (typeof document === "undefined") return null;
  const match = document.cookie.match(new RegExp("(?:^|; )" + name + "=([^;]*)"));
  return match ? decodeURIComponent(match[1]) : null;
}

function writeCookie(name: string, value: string, days: number) {
  const expires = new Date(Date.now() + days * 864e5).toUTCString();
  document.cookie = `${name}=${encodeURIComponent(value)}; expires=${expires}; path=/; SameSite=Lax`;
}

function parseCohort(raw: string | null): number | undefined {
  if (!raw) return undefined;
  const n = Number(raw);
  return VALID_COHORTS.has(n) ? n : undefined;
}

/** Run once on first load. First-touch only. */
export function captureAttribution(): void {
  if (typeof document === "undefined") return;
  if (readCookie(ATTR_COOKIE)) return; // already captured — leave it alone

  const q = new URLSearchParams(window.location.search);
  const attr: Attribution = { ts: new Date().toISOString() };

  const cohort = parseCohort(q.get("p"));
  if (cohort) attr.priceCohort = cohort;

  for (const key of UTM_KEYS) {
    const v = q.get(key);
    if (v) attr[key] = v;
  }

  const ref = q.get("ref");
  if (ref) attr.ref_code_used = ref;
  if (document.referrer) attr.referrer = document.referrer;

  writeCookie(ATTR_COOKIE, JSON.stringify(attr), 30);
}

/**
  Price cohort for analytics only — never shown on the page. Reads the cookie,
  falls back to a live ?p= param, then $119.
*/
export function getPriceCohort(): number {
  const stored = parseCohort(
    (() => {
      const raw = readCookie(ATTR_COOKIE);
      if (!raw) return null;
      try {
        return String((JSON.parse(raw) as Attribution).priceCohort ?? "");
      } catch {
        return null;
      }
    })(),
  );
  if (stored) return stored;

  if (typeof window !== "undefined") {
    const live = parseCohort(new URLSearchParams(window.location.search).get("p"));
    if (live) return live;
  }
  return DEFAULT_PRICE;
}
