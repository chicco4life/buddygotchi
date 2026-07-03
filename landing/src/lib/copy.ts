/*
  All user-facing copy lives here, centralized because it is A/B-tweaked during
  the demand test. Final-draft quality from MARKETING.md §2.2.

  Brand law (SPEC.md §10, enforced by tests/copy-rules.test.mjs):
    - No banned hype words (revolutionary, supercharge, AI-powered, etc.)
    - No exclamation marks, anywhere.
    - Sentence case; ALL CAPS only in tiny labels.
    - Stay in-universe: adopt, litter, get in line, hatches.
*/
export const copy = {
  meta: {
    title: "Buddygotchi — a desk companion for AI agents",
    description:
      "A little creature that watches your AI coding agents — glows when one needs you, celebrates when work lands, and lets you approve with a pet. Founding Litter of 100.",
  },

  hero: {
    headline: "Approve with a pet.",
    subhead:
      "A little creature that watches your AI agents — and only bothers you when it matters.",
    ctaLabel: "Adopt one",
    footnote: "Founding Litter · 100 numbered buddies · no subscription, ever",
    mediaNote: "Blob idling on a desk, glow shifts amber, a hand reaches in and pets it",
  },

  moment: {
    stills: [
      { caption: "It asks.", screen: "▸ claude wants to run npm test", note: "Amber glow, blob looks up" },
      { caption: "You pet.", note: "Hand mid-pet, blob squinting" },
      { caption: "Everyone gets back to work.", note: "Wide shot, human back at work, blob content" },
    ],
    line:
      "Permission prompts, completions, and failures — surfaced as a feeling in the corner of your eye, not another notification.",
  },

  alive: {
    loops: [
      { caption: "Boop it. It forgives you.", note: "Finger boops it, two or three damped rocks, giggle face" },
      { caption: "It sleeps when your agents do.", note: "Dark desk, sleeping face, finger boop, one eye opens" },
      { caption: "It's genuinely proud of your build passing.", note: "Green ripple, confetti face" },
    ],
  },

  light: {
    states: [
      { label: "Working", desc: "warm breathing" },
      { label: "Needs you", desc: "amber" },
      { label: "Done", desc: "green ripple" },
      { label: "Stuck", desc: "dim red heartbeat" },
      { label: "Asleep", desc: "dark" },
    ],
    caption:
      "You'll learn its moods in a day. Amber means come here. Everything else means you're free.",
  },

  rational: {
    agents: ["Claude Code", "Codex", "Cursor", "VS Code"],
    agentsCaption: "Speaks fluent agent. One-click setup from the Mac app.",
    trust: [
      {
        title: "Local-first",
        body: "everything runs on your Mac; the buddy talks to it over Bluetooth. No cloud, no account.",
      },
      {
        title: "No subscription",
        body: "buy it once. When agents change, it learns new tricks in free updates.",
      },
      {
        title: "USB-C powered",
        body: "lives on your desk, plugged in, always on.",
      },
    ],
  },

  craft: {
    note: "Exploded view: shell, screen, silicone crown, steel disc, base ring, floating apart",
    lines: [
      "A frosted shell that glows from within.",
      "A steel heart, so it always rights itself — 162 grams of calm.",
      "A silicone crown that clicks like a marshmallow.",
      "Two buttons. That's all it needs.",
    ],
  },

  adoption: {
    note: "The open adoption box: blob nested in the insert, care card, braided cream cable coiled",
    lines: [
      "Every buddy ships in an adoption box with a numbered ID, a care card, and a cable that deserves the name.",
      "Founding Litter: 100 buddies. When they're gone, batch two begins.",
    ],
    // {n} is filled from real data only; the whole line is hidden until then.
    counterTemplate: "Buddy #{n} of 100 was adopted yesterday",
  },

  faq: [
    { q: "Does it need a subscription?", a: "No. Never." },
    {
      q: "What does it actually do?",
      a: "Shows what your agents are doing, glows when one needs you, lets you approve or deny with a press, celebrates when work lands.",
    },
    {
      q: "What if I auto-approve everything?",
      a: "Then it's the thing that tells you when to come back. That's most of the point.",
    },
    {
      q: "What about my code and data?",
      a: "The buddy sees state, not source. Everything stays on your machine.",
    },
    { q: "Mac only?", a: "For now. The buddy doesn't judge." },
  ],

  footer: {
    ctaLabel: "Get in line",
    placeholder: "you@where-you-code.com",
    signoff: "Made by people who also forgot a task finished 40 minutes ago.",
    privacy: "privacy",
    contact: "contact",
    contactEmail: "hello@buddygotchi.com",
    wordmark: "Buddygotchi",
  },

  modal: {
    heading: "The Founding Litter of 100 is being hand-assembled now.",
    body: "Leave your email to claim a place in line — first come, first adopted.",
    ctaLabel: "Get in line",
    small: "No spam. One email when your number comes up.",
    error: "Something hiccuped. Try once more?",
    close: "Close",
    placeholder: "you@where-you-code.com",
  },

  welcome: {
    heading: "You're in line.",
    // {n} filled with the returned position.
    sublineTemplate: "Buddy #{n} will be yours when the Founding Litter hatches.",
    sublineGeneric: "Watch your inbox — your number is on its way.",
    share: "Want to skip ahead? Every friend who joins moves you up 10 places.",
    copyLabel: "Copy link",
    copiedLabel: "Copied",
    backHome: "back to the litter",
  },

  privacy: {
    heading: "The short, honest version.",
    paragraphs: [
      "We store your email address and the campaign link you arrived from. That's it.",
      "We use it to email you about the Founding Litter — when your adoption number comes up, and little else.",
      "Nothing is sold, rented, or handed to advertisers. You can unsubscribe from any email, and we'll delete your address if you ask.",
      "The buddy itself is local-first: it runs on your Mac and talks to the hardware over Bluetooth. This website is the only place we collect anything, and this is all of it.",
    ],
    backHome: "back to the litter",
  },
} as const;

export type Copy = typeof copy;
