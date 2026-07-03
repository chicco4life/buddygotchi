import Link from "next/link";
import { copy } from "@/lib/copy";
import { Section } from "@/components/Section";
import { Reveal } from "@/components/Reveal";
import { FooterSignup } from "@/components/FooterSignup";

/* S9 — Footer. Inline email capture, tiny links, sign-off, wordmark. */
export function Footer() {
  return (
    <Section id="S9" label="Get in line" className="pb-24">
      <Reveal>
        <div className="flex flex-col items-center gap-8 text-center">
          <FooterSignup />

          <nav className="flex items-center gap-6 text-sm text-charcoal-soft">
            <Link href="/privacy" className="hover:text-charcoal">
              {copy.footer.privacy}
            </Link>
            <a href={`mailto:${copy.footer.contactEmail}`} className="hover:text-charcoal">
              {copy.footer.contact}
            </a>
          </nav>

          <p className="max-w-md text-sm text-charcoal-soft">{copy.footer.signoff}</p>

          <p className="text-xs font-semibold uppercase tracking-[0.08em] text-charcoal-soft/70">
            {copy.footer.wordmark} · © {new Date().getFullYear()}
          </p>
        </div>
      </Reveal>
    </Section>
  );
}
