import { neon } from "@neondatabase/serverless";
import type { Attribution } from "@/lib/attribution";

/*
  Waitlist persistence with two backends:
    - Neon Postgres when DATABASE_URL is set (production).
    - An in-memory store when ALLOW_INMEM=1 and no DATABASE_URL (Playwright).
  Without either, the backend is "not ready" and the API returns 503, so the
  page still renders (fail-open, like everything else in this project).
  See SPEC.md §6.2 / §11.3.
*/

export type SubmitInput = {
  email: string;
  source: "hero" | "footer";
  attr: Attribution;
};

export type SubmitResult = { position: number; referralCode: string };

const CROCKFORD = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";

function generateReferralCode(): string {
  const bytes = new Uint8Array(8);
  crypto.getRandomValues(bytes);
  let out = "";
  for (const b of bytes) out += CROCKFORD[b % 32];
  return out;
}

function positionFrom(rank: number, referralCount: number): number {
  return Math.max(1, rank - 10 * referralCount);
}

function getSql() {
  const url = process.env.DATABASE_URL;
  return url ? neon(url) : null;
}

const allowInmem = () => process.env.ALLOW_INMEM === "1";

export function isBackendReady(): boolean {
  return Boolean(process.env.DATABASE_URL) || allowInmem();
}

/* ---------------- In-memory backend (tests only) ---------------- */

type MemRow = {
  email: string;
  referral_code: string;
  referral_count: number;
  ref_code_used?: string;
  created_at: number;
};

const g = globalThis as unknown as { __bgMem?: MemRow[] };
const mem: MemRow[] = (g.__bgMem ??= []);

function submitInMemory(input: SubmitInput): SubmitResult {
  const existing = mem.find((r) => r.email === input.email);
  if (existing) {
    const rank = mem.filter((r) => r.created_at <= existing.created_at).length;
    return {
      position: positionFrom(rank, existing.referral_count),
      referralCode: existing.referral_code,
    };
  }

  const row: MemRow = {
    email: input.email,
    referral_code: generateReferralCode(),
    referral_count: 0,
    ref_code_used: input.attr.ref_code_used,
    created_at: Date.now() + mem.length, // strictly increasing tiebreak
  };
  mem.push(row);

  if (input.attr.ref_code_used) {
    const referrer = mem.find((r) => r.referral_code === input.attr.ref_code_used);
    if (referrer) referrer.referral_count += 1;
  }

  const rank = mem.filter((r) => r.created_at <= row.created_at).length;
  return { position: rank, referralCode: row.referral_code };
}

/* ---------------- Postgres backend ---------------- */

async function submitInPostgres(
  sql: NonNullable<ReturnType<typeof getSql>>,
  input: SubmitInput,
): Promise<SubmitResult> {
  const { email, source, attr } = input;

  const existing = (await sql`
    select referral_code, referral_count, created_at
    from signups where email = ${email}
  `) as unknown as { referral_code: string; referral_count: number; created_at: string }[];

  if (existing.length) {
    const row = existing[0];
    const rank = (
      (await sql`select count(*)::int as r from signups where created_at <= ${row.created_at}`) as unknown as {
        r: number;
      }[]
    )[0].r;
    return {
      position: positionFrom(rank, row.referral_count),
      referralCode: row.referral_code,
    };
  }

  const code = generateReferralCode();
  const inserted = (await sql`
    insert into signups
      (email, source, price_cohort, utm_source, utm_medium, utm_campaign,
       utm_content, utm_term, referrer, ref_code_used, referral_code)
    values
      (${email}, ${source}, ${attr.priceCohort ?? null},
       ${attr.utm_source ?? null}, ${attr.utm_medium ?? null}, ${attr.utm_campaign ?? null},
       ${attr.utm_content ?? null}, ${attr.utm_term ?? null},
       ${attr.referrer ?? null}, ${attr.ref_code_used ?? null}, ${code})
    returning created_at
  `) as unknown as { created_at: string }[];

  if (attr.ref_code_used) {
    await sql`
      update signups set referral_count = referral_count + 1
      where referral_code = ${attr.ref_code_used}
    `;
  }

  const rank = (
    (await sql`select count(*)::int as r from signups where created_at <= ${inserted[0].created_at}`) as unknown as {
      r: number;
    }[]
  )[0].r;

  return { position: rank, referralCode: code };
}

export async function submitSignup(input: SubmitInput): Promise<SubmitResult> {
  const sql = getSql();
  if (sql) return submitInPostgres(sql, input);
  if (allowInmem()) return submitInMemory(input);
  throw new Error("waitlist backend not configured");
}
