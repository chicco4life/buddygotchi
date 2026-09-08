import { NextResponse } from "next/server";
import { z } from "zod";
import { isBackendReady, saveExpectation } from "@/lib/waitlist";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const Body = z.object({
  code: z.string().trim().min(1).max(32),
  answer: z.string().trim().min(1).max(64),
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
    return NextResponse.json({ error: "bad request" }, { status: 400 });
  }

  try {
    await saveExpectation(parsed.data);
    return NextResponse.json({ ok: true });
  } catch (err) {
    console.error("waitlist expectation failed", err);
    return NextResponse.json({ error: "server error" }, { status: 500 });
  }
}
