"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";
import { track } from "@vercel/analytics";
import { submitEmail } from "@/lib/submit";
import { getPriceCohort } from "@/lib/attribution";
import { copy } from "@/lib/copy";
import { ctaClass } from "@/lib/ui";

/*
  Shared email capture, used by both the hero modal and the footer. On success,
  navigates to /welcome with the returned position + referral code.
*/
export function EmailForm({
  source,
  buttonLabel,
  placeholder,
  autoFocus = false,
  layout = "stacked",
}: {
  source: "hero" | "footer";
  buttonLabel: string;
  placeholder: string;
  autoFocus?: boolean;
  layout?: "stacked" | "inline";
}) {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [state, setState] = useState<"idle" | "loading" | "error">("idle");

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (state === "loading") return;
    setState("loading");
    try {
      const { position, referralCode } = await submitEmail(email.trim(), source);
      track("signup", { source, cohort: getPriceCohort() });
      router.push(`/welcome?pos=${position}&code=${encodeURIComponent(referralCode)}`);
    } catch {
      setState("error");
    }
  }

  const wrap =
    layout === "inline"
      ? "flex flex-col gap-3 sm:flex-row"
      : "flex flex-col gap-3";

  return (
    <form onSubmit={onSubmit} className={wrap} noValidate>
      <label className="sr-only" htmlFor={`email-${source}`}>
        Email address
      </label>
      <input
        id={`email-${source}`}
        type="email"
        name="email"
        inputMode="email"
        autoComplete="email"
        required
        autoFocus={autoFocus}
        placeholder={placeholder}
        value={email}
        onChange={(e) => {
          setEmail(e.target.value);
          if (state === "error") setState("idle");
        }}
        className="w-full flex-1 rounded-full border border-charcoal/15 bg-cream-deep px-6 py-4 text-charcoal placeholder:text-charcoal-soft/70 focus-visible:border-amber"
      />
      <button type="submit" className={ctaClass} disabled={state === "loading"}>
        {state === "loading" ? "…" : buttonLabel}
      </button>
      {state === "error" && (
        <p role="alert" className="text-sm text-charcoal-soft sm:basis-full">
          {copy.modal.error}
        </p>
      )}
    </form>
  );
}
