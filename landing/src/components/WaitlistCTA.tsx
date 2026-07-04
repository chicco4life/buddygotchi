"use client";

import { useEffect, useRef, useState } from "react";
import { track } from "@vercel/analytics";
import { DEFAULT_PRICE, getPriceCohort } from "@/lib/attribution";
import type { SignupSource } from "@/lib/submit";
import { copy } from "@/lib/copy";
import { ctaClass } from "@/lib/ui";
import { EmailForm } from "@/components/EmailForm";

/*
  The amber CTA + honest waitlist modal (§6.1), shared by the hero and the
  adoption section — each instance carries its own <dialog> and source tag so
  the demand test can tell where the click came from. The native <dialog> gives
  us focus-trap, Esc-to-close, and focus return for free.
*/
export function WaitlistCTA({ source }: { source: Extract<SignupSource, "hero" | "adoption"> }) {
  const [price, setPrice] = useState(DEFAULT_PRICE);
  const dialogRef = useRef<HTMLDialogElement>(null);
  const headingId = `waitlist-heading-${source}`;

  // Price hydrates from the cookie/param after mount so the page stays static.
  useEffect(() => {
    setPrice(getPriceCohort());
  }, []);

  function open() {
    track("cta_click", { source });
    track("modal_open", { source });
    dialogRef.current?.showModal();
  }

  function onDialogClick(e: React.MouseEvent<HTMLDialogElement>) {
    // Click on the backdrop (the dialog element itself) closes it.
    if (e.target === dialogRef.current) dialogRef.current?.close();
  }

  return (
    <>
      <button type="button" onClick={open} className={ctaClass} data-testid={`${source}-cta`}>
        {copy.hero.ctaLabel} — ${price}
      </button>

      <dialog
        ref={dialogRef}
        onClick={onDialogClick}
        aria-labelledby={headingId}
        className="m-auto w-[min(30rem,92vw)] rounded-lg bg-cream p-8 text-charcoal sm:p-10"
      >
        <div className="flex flex-col gap-5">
          <h2 id={headingId} className="text-2xl font-semibold leading-snug">
            {copy.modal.heading}
          </h2>
          <p className="text-charcoal-soft">{copy.modal.body}</p>
          <EmailForm
            source={source}
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
