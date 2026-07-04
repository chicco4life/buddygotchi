"use client";

import { track } from "@vercel/analytics";
import { copy } from "@/lib/copy";
import { ctaClass } from "@/lib/ui";

function withClientReference(url: string, code: string): string {
  const separator = url.includes("?") ? "&" : "?";
  return `${url}${separator}client_reference_id=${encodeURIComponent(code)}`;
}

export function WelcomeDeposit({ code, depositUrl }: { code: string; depositUrl: string }) {
  if (!depositUrl) return null;

  return (
    <section className="mt-8 flex w-full max-w-md flex-col items-center gap-3 text-center">
      <h2 className="text-xl font-semibold">{copy.welcome.deposit.heading}</h2>
      <p className="text-sm leading-6 text-charcoal-soft">{copy.welcome.deposit.body}</p>
      <a
        href={withClientReference(depositUrl, code)}
        target="_blank"
        rel="noopener"
        className={`${ctaClass} mt-1`}
        onClick={() => track("deposit_click", { code })}
      >
        {copy.welcome.deposit.ctaLabel}
      </a>
      <p className="text-xs text-charcoal-soft">{copy.welcome.deposit.small}</p>
    </section>
  );
}
