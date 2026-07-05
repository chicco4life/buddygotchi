import { after, NextResponse } from "next/server";
import { cookies } from "next/headers";
import { z } from "zod";
import { ATTR_COOKIE, DEFAULT_PRICE, type Attribution } from "@/lib/attribution";
import { sendWaitlistConfirmation } from "@/lib/email";
import { isBackendReady, submitSignup } from "@/lib/waitlist";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const Body = z.object({
  email: z.string().email().max(320),
  source: z.enum(["hero", "adoption", "footer"]),
});

// Naive per-IP limiter. Fine at demand-test traffic; resets on cold start and is
// per-instance only — not a real DoS control, just an abuse speed bump.
const hits = new Map<string, number[]>();
function rateLimited(ip: string): boolean {
  const now = Date.now();
  const recent = (hits.get(ip) ?? []).filter((t) => now - t < 60_000);
  recent.push(now);
  hits.set(ip, recent);
  return recent.length > 5;
}

export async function POST(req: Request) {
  if (!isBackendReady()) {
    return NextResponse.json({ error: "waitlist unavailable" }, { status: 503 });
  }

  const ip = req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() || "local";
  if (rateLimited(ip)) {
    return NextResponse.json({ error: "slow down" }, { status: 429 });
  }

  let json: unknown;
  try {
    json = await req.json();
  } catch {
    return NextResponse.json({ error: "bad request" }, { status: 400 });
  }

  const parsed = Body.safeParse(json);
  if (!parsed.success) {
    return NextResponse.json({ error: "invalid email" }, { status: 400 });
  }

  const email = parsed.data.email.trim().toLowerCase();

  let attr: Attribution = {};
  const raw = (await cookies()).get(ATTR_COOKIE)?.value;
  if (raw) {
    try {
      attr = JSON.parse(raw) as Attribution;
    } catch {
      // malformed cookie — proceed with no attribution
    }
  }

  try {
    const result = await submitSignup({ email, source: parsed.data.source, attr });
    if (result.created) {
      after(() =>
        sendWaitlistConfirmation({
          to: email,
          position: result.position,
          price: attr.priceCohort ?? DEFAULT_PRICE,
        }),
      );
    }
    return NextResponse.json(result);
  } catch (err) {
    console.error("waitlist submit failed", err);
    return NextResponse.json({ error: "server error" }, { status: 500 });
  }
}
