"use client";

import { useState, type FormEvent } from "react";
import { track } from "@vercel/analytics";
import { copy } from "@/lib/copy";
import { tinyLabel } from "@/lib/ui";

export function WelcomeSurvey({ code }: { code: string }) {
  const [answer, setAnswer] = useState("");
  const [pending, setPending] = useState(false);
  const [done, setDone] = useState(false);
  const [error, setError] = useState(false);

  async function onSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setPending(true);
    setError(false);

    try {
      const res = await fetch("/api/waitlist/expectation", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ code, answer }),
      });

      if (!res.ok) throw new Error("request failed");

      track("price_expectation", {});
      setDone(true);
    } catch {
      setError(true);
    } finally {
      setPending(false);
    }
  }

  return (
    <section className="mt-10 flex w-full max-w-md flex-col items-center text-center">
      <p className={tinyLabel}>{copy.welcome.survey.label}</p>
      <p className="mt-3 text-sm leading-6 text-charcoal-soft">{copy.welcome.survey.question}</p>

      {done ? (
        <p className="mt-4 text-sm text-charcoal-soft">{copy.welcome.survey.thanks}</p>
      ) : (
        <form onSubmit={onSubmit} className="mt-4 flex w-full flex-col gap-3">
          <div className="flex w-full flex-col gap-3 sm:flex-row">
            <input
              value={answer}
              onChange={(event) => setAnswer(event.currentTarget.value)}
              maxLength={64}
              aria-label={copy.welcome.survey.question}
              placeholder={copy.welcome.survey.placeholder}
              className="w-full flex-1 rounded-full border border-charcoal/15 bg-cream-deep px-5 py-3 text-sm text-charcoal placeholder:text-charcoal-soft/70"
            />
            <button
              type="submit"
              disabled={pending}
              className="inline-flex items-center justify-center rounded-full border border-charcoal/15 bg-cream-deep px-5 py-3 text-sm font-semibold text-charcoal transition-colors duration-150 ease-buddy hover:border-charcoal/25 hover:bg-cream focus-visible:outline-amber disabled:cursor-not-allowed disabled:opacity-60"
            >
              {copy.welcome.survey.submitLabel}
            </button>
          </div>
          {error && (
            <p role="alert" className="text-sm text-charcoal-soft">
              {copy.modal.error}
            </p>
          )}
        </form>
      )}
    </section>
  );
}
