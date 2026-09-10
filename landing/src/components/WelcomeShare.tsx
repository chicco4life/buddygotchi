"use client";

import { useEffect, useState } from "react";
import { track } from "@vercel/analytics";
import { copy } from "@/lib/copy";
import { ctaClass } from "@/lib/ui";

/*
  The share hook on /welcome: a read-only referral link + copy button. The
  single cheapest viral loop there is (SPEC.md §6.3). Origin is resolved client
  side so the link is correct on any deploy or preview URL.
*/
export function WelcomeShare({ code }: { code: string }) {
  const [link, setLink] = useState("");
  const [copied, setCopied] = useState(false);

  useEffect(() => {
    setLink(`${window.location.origin}/?ref=${encodeURIComponent(code)}`);
  }, [code]);

  async function onCopy() {
    try {
      await navigator.clipboard.writeText(link);
      track("copy_referral", {});
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      // clipboard blocked — leave the link visible for manual copy
    }
  }

  return (
    <div className="mt-10 flex w-full max-w-md flex-col gap-4">
      <p className="text-charcoal-soft">{copy.welcome.share}</p>
      <div className="flex flex-col gap-3 sm:flex-row">
        <input
          readOnly
          value={link}
          aria-label="Your referral link"
          onFocus={(e) => e.currentTarget.select()}
          className="w-full flex-1 rounded-full border border-charcoal/15 bg-cream-deep px-6 py-4 text-charcoal"
        />
        <button type="button" onClick={onCopy} className={ctaClass}>
          {copied ? copy.welcome.copiedLabel : copy.welcome.copyLabel}
        </button>
      </div>
    </div>
  );
}
