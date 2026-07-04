import { fireLead } from "@/lib/pixels";

export type SignupResult = { position: number; referralCode: string };

/** Where on the page a signup came from — stored on the row for the demand test. */
export type SignupSource = "hero" | "adoption" | "footer";

/** POST an email to the waitlist. Throws on failure with an in-register message. */
export async function submitEmail(
  email: string,
  source: SignupSource,
): Promise<SignupResult> {
  const res = await fetch("/api/waitlist", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ email, source }),
  });

  if (!res.ok) {
    throw new Error("waitlist request failed");
  }

  const data = (await res.json()) as SignupResult;
  fireLead(source);
  return data;
}
