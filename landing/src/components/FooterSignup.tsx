"use client";

import { EmailForm } from "@/components/EmailForm";
import { copy } from "@/lib/copy";

export function FooterSignup() {
  return (
    <div className="w-full max-w-md">
      <EmailForm
        source="footer"
        buttonLabel={copy.footer.ctaLabel}
        placeholder={copy.footer.placeholder}
        layout="inline"
      />
    </div>
  );
}
