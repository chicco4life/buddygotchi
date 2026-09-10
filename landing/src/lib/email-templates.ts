// GENERATED — edit emails/*.md then `npm run emails:build`

export const EMAIL_TEMPLATES = {
  "waitlist-confirmation": {
    "id": "waitlist-confirmation",
    "subject": "You're in line: buddy #{{position}}",
    "from": "Boop Computer <hello@adoptaboop.com>",
    "replyTo": "hello@adoptaboop.com",
    "trigger": "first successful waitlist signup (landing/src/app/api/waitlist/route.ts)",
    "placeholders": [
      "position"
    ],
    "heading": "You're in line.",
    "subline": "Buddy #{{position}} of the Founding Litter will be yours when it hatches. 100 numbered buddies, hand-assembled.",
    "body": "We won't promise a date we might miss: when your number comes up, you'll get exactly one email, and until then this is the last thing we send.\n\nNo subscription, ever. If you change your mind, reply to this email and we'll take you off the list and delete your address, no questions asked.\n\nBoop Computer\nadoptaboop.com\n"
  },
};

export const WAITLIST_CONFIRMATION_TEMPLATE = EMAIL_TEMPLATES["waitlist-confirmation"];
