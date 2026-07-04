import { copy } from "@/lib/copy";
import { Section } from "@/components/Section";
import { Reveal } from "@/components/Reveal";
import { MediaImage } from "@/components/Media";
import { WaitlistCTA } from "@/components/WaitlistCTA";

/*
  S6 — The adoption. The scarcity + story section (MARKETING.md §2.2 S7, sans
  care card): the box, the numbered ID, the Founding Litter. Drawn until the
  real box exists — drop public/media/box.jpg to swap in the photograph. Also
  carries the page's mid-scroll CTA: this is where the scarcity is stated, so
  it's where the button belongs. The adoption counter stays out until real
  (brand law: nothing fabricated).
*/
function AdoptionBox() {
  return (
    <svg
      viewBox="0 0 400 300"
      preserveAspectRatio="xMidYMid slice"
      className="absolute inset-0 h-full w-full"
      aria-hidden="true"
    >
      <defs>
        <radialGradient id="adoption-halo" cx="50%" cy="46%" r="60%">
          <stop offset="0%" stopColor="#f4d9a6" stopOpacity="0.65" />
          <stop offset="100%" stopColor="#f4d9a6" stopOpacity="0" />
        </radialGradient>
      </defs>

      <rect width="400" height="300" fill="#efe7d8" />
      <ellipse cx="200" cy="160" rx="180" ry="110" fill="url(#adoption-halo)" />
      {/* desk plane */}
      <rect y="218" width="400" height="82" fill="#e6d9c1" />

      {/* open lid, leaning behind the box */}
      <path d="M128 128 L272 128 L288 74 L112 74 Z" fill="#e0d2b8" />
      <path d="M128 128 L272 128 L268 118 L132 118 Z" fill="#d4c5a8" />

      {/* the buddy, nested and peeking over the rim */}
      <ellipse cx="200" cy="140" rx="52" ry="44" fill="#f8f3ea" />
      <rect x="175" y="116" width="50" height="32" rx="9" fill="#2b2724" />
      <path d="M186 133 q7 -8 14 0" stroke="#f7f2e9" strokeWidth="2.6" fill="none" strokeLinecap="round" />
      <path d="M209 133 q7 -8 14 0" stroke="#f7f2e9" strokeWidth="2.6" fill="none" strokeLinecap="round" />
      <circle cx="160" cy="144" r="6" fill="#e79aa0" opacity="0.5" />
      <circle cx="240" cy="144" r="6" fill="#e79aa0" opacity="0.5" />

      {/* box body in front of the buddy */}
      <rect x="122" y="158" width="156" height="72" rx="7" fill="#e8dcc6" />
      <rect x="122" y="158" width="156" height="10" rx="5" fill="#dccdaf" />

      {/* numbered adoption tag on the box front */}
      <rect x="178" y="180" width="44" height="26" rx="5" fill="#f7f2e9" stroke="#2b2724" strokeOpacity="0.12" />
      <text
        x="200"
        y="197"
        textAnchor="middle"
        fontFamily="ui-sans-serif, system-ui, sans-serif"
        fontSize="11"
        fontWeight="600"
        letterSpacing="0.5"
        fill="#6e675d"
      >
        Nº 001
      </text>

      {/* coiled cream cable beside the box */}
      <g stroke="#f3ead9" strokeWidth="7" fill="none" strokeLinecap="round">
        <circle cx="326" cy="228" r="20" />
        <circle cx="326" cy="228" r="11" />
        <path d="M344 218 q14 -8 20 -22" />
      </g>
      <g stroke="#2b2724" strokeOpacity="0.08" strokeWidth="9" fill="none" strokeLinecap="round">
        <circle cx="326" cy="228" r="20" />
      </g>
    </svg>
  );
}

export function Adoption() {
  return (
    <Section id="S6" label="The adoption">
      <Reveal>
        <div className="grid items-center gap-12 md:grid-cols-2">
          <MediaImage
            src="/media/box.jpg"
            alt="An open adoption box: the buddy nested inside with a numbered tag, a coiled cream cable beside it."
            ratio={4 / 3}
            placeholder={<AdoptionBox />}
          />
          <div className="flex flex-col gap-6">
            <p className="text-xl italic leading-snug text-charcoal">{copy.adoption.lines[0]}</p>
            <p className="text-xl italic leading-snug text-charcoal">{copy.adoption.lines[1]}</p>
            <div className="mt-2">
              <WaitlistCTA source="adoption" />
            </div>
          </div>
        </div>
      </Reveal>
    </Section>
  );
}
