import { copy } from "@/lib/copy";
import { Section } from "@/components/Section";
import { Reveal } from "@/components/Reveal";

/*
  S8 — FAQ. Plain stacked text, no accordion (collapsing five lines is
  disfluency for no gain). Ships FAQPage JSON-LD — the only structured content
  on the page, free SEO. See SPEC.md §5 (S8).
*/
export function Faq() {
  const jsonLd = {
    "@context": "https://schema.org",
    "@type": "FAQPage",
    mainEntity: copy.faq.map((item) => ({
      "@type": "Question",
      name: item.q,
      acceptedAnswer: { "@type": "Answer", text: item.a },
    })),
  };

  return (
    <Section id="S8" label="Questions">
      <Reveal>
        <dl className="mx-auto flex max-w-2xl flex-col gap-8">
          {copy.faq.map((item) => (
            <div key={item.q}>
              <dt className="font-semibold">{item.q}</dt>
              <dd className="mt-1 text-charcoal-soft">{item.a}</dd>
            </div>
          ))}
        </dl>
      </Reveal>
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd) }}
      />
    </Section>
  );
}
