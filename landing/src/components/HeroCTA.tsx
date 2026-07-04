"use client";

import { useEffect, useRef, useState } from "react";
import { track } from "@vercel/analytics";
import { DEFAULT_PRICE, getPriceCohort } from "@/lib/attribution";
import { copy } from "@/lib/copy";
import { ctaClass } from "@/lib/ui";
import { EmailForm } from "@/components/EmailForm";

/*
  Hero CTA. Renders the amber button with the cohort-dependent price (§7.2) and
  the honest waitlist modal (§6.1) — the native <dialog> gives us focus-trap,
  Esc-to-close, and focus return for free.
*/
export function HeroCTA() {
  const [price, setPrice] = useState(DEFAULT_PRICE);
  const dialogRef = useRef<HTMLDialogElement>(null);

  // Price hydrates from the cookie/param after mount so the page stays static.
  useEffect(() => {
    setPrice(getPriceCohort());
  }, []);

  function open() {
    track("cta_click", { source: "hero" });
    track("modal_open", {});
    dialogRef.current?.showModal();
  }

  function onDialogClick(e: React.MouseEvent<HTMLDialogElement>) {
    // Click on the backdrop (the dialog element itself) closes it.
    if (e.target === dialogRef.current) dialogRef.current?.close();
  }

  return (
    <>
      <button type="button" onClick={open} className={ctaClass} data-testid="hero-cta">
        {copy.hero.ctaLabel} — ${price}
      </button>

      <dialog
        ref={dialogRef}
        onClick={onDialogClick}
        aria-labelledby="waitlist-heading"
        className="m-auto w-[min(30rem,92vw)] rounded-lg bg-cream p-8 text-charcoal sm:p-10"
      >
        <div className="flex flex-col gap-5">
          <h2 id="waitlist-heading" className="text-2xl font-semibold leading-snug">
            {copy.modal.heading}
          </h2>
          <p className="text-charcoal-soft">{copy.modal.body}</p>
          <EmailForm
            source="hero"
            buttonLabel={copy.modal.ctaLabel}
            placeholder={copy.modal.placeholder}
            autoFocus
          />
          <p className="text-sm text-charcoal-soft">{copy.modal.small}</p>
        </div>

        <form method="dialog" className="mt-6">
          <button
            type="submit"
            className="text-sm text-charcoal-soft underline-offset-4 hover:underline"
          >
            {copy.modal.close}
          </button>
        </form>
      </dialog>
    </>
  );
}
