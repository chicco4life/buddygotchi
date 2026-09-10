import { Hero } from "@/components/sections/Hero";
import { Moment } from "@/components/sections/Moment";
import { Alive } from "@/components/sections/Alive";
import { LightLanguage } from "@/components/sections/LightLanguage";
import { RationalFloor } from "@/components/sections/RationalFloor";
import { Adoption } from "@/components/sections/Adoption";
import { Faq } from "@/components/sections/Faq";
import { Footer } from "@/components/sections/Footer";

/*
  One page, no nav, no header — nothing to do but scroll and one thing to click.
  Sections S1–S8 in order (SPEC.md §5).
*/
export default function Page() {
  return (
    <main>
      <Hero />
      <Moment />
      <Alive />
      <LightLanguage />
      <RationalFloor />
      <Adoption />
      <Faq />
      <Footer />
    </main>
  );
}
