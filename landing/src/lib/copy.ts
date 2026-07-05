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
    title: "Boop — a desk companion for AI agents",
    description:
      "Boop is a desk companion for AI agents that watches your AI coding agents — glows when one needs you, celebrates when work lands, and lets you approve with a pet. Founding Litter of 100.",
  },

  hero: {
    headline: "Approve with a pet.",
    subhead:
      "A little creature that watches your AI agents — and only bothers you when it matters.",
    ctaLabel: "Adopt one",
    footnote: "Founding Litter · 100 numbered buddies · no subscription, ever",
  },

  moment: {
    beats: [
      {
        caption: "It asks.",
        screen: "▸ claude wants to run npm test",
        aria: "The buddy glows amber and looks up, asking",
      },
      {
        caption: "You pet.",
        aria: "A hand pets the buddy; it squints, happy",
      },
      {
        caption: "Everyone gets back to work.",
        aria: "The buddy settles back to a contented idle",
      },
    ],
    line:
      "Permission prompts, completions, and failures — surfaced as a feeling in the corner of your eye, not another notification.",
  },

  alive: {
    vignettes: [
      {
        caption: "Boop it. It forgives you.",
        aria: "Booped, the buddy rocks twice and settles, giggling",
      },
      {
        caption: "It sleeps when your agents do.",
        aria: "The buddy sleeps; one eye peeks open, then closes again",
      },
      {
        caption: "It's genuinely proud of your build passing.",
        aria: "Confetti and a green glow — the buddy celebrates",
      },
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

  adoption: {
    boxAria:
      "An open adoption box, drawn: the buddy nested inside, a numbered tag on the lid, a coiled cream cable beside it",
    lines: [
      "Every buddy ships in an adoption box with a numbered ID and a cable that deserves the name.",
      "Founding Litter: 100 buddies. When they're gone, batch two begins.",
    ],
  },

  faq: [
    { q: "Does it need a subscription?", a: "No. Never." },
    {
      q: "What does it actually do?",
      a: "It's a desk companion for AI agents: it shows what yours are doing, glows when one needs you, lets you approve or deny with a press, celebrates when work lands.",
    },
    {
      q: "When do they hatch?",
      a: "When they're ready. The Founding Litter is still being hand-assembled, and we won't promise a date we might miss. You'll get exactly one email when your number comes up.",
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
    // Rendered only when url is non-empty — set it once the build-in-public
    // account exists (research/TODOs.md).
    followBuild: { label: "follow the build", url: "" },
    signoff: "Made by people who also forgot a task finished 40 minutes ago.",
    privacy: "privacy",
    contact: "contact",
    contactEmail: "hello@adoptaboop.com",
    wordmark: "Boop",
    copyright: "© 2026 Boop Computer",
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
    survey: {
      label: "one question, optional",
      question: "What would you honestly expect a buddy like this to cost?",
      placeholder: "your honest number",
      submitLabel: "Send",
      thanks: "Noted. The litter thanks you.",
    },
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
