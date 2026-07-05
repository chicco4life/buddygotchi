// GENERATED — edit emails/*.md then `npm run emails:build`

export const EMAIL_TEMPLATES = {
  "waitlist-confirmation": {
    "id": "waitlist-confirmation",
    "subject": "You're in line — buddy #{{position}}",
    "from": "The Litter <hello@adoptaboop.com>",
    "replyTo": "hello@adoptaboop.com",
    "trigger": "first successful waitlist signup (landing/src/app/api/waitlist/route.ts)",
    "placeholders": [
      "position",
      "price",
      "referralUrl"
    ],
    "body": "hello —\n\nyou're in line. buddy #{{position}} of the Founding Litter — 100 numbered buddies, hand-assembled — will be yours when it hatches. we won't promise a date we might miss: when your number comes up you'll get exactly one email, and until then this is the last thing we send. the price is ${{price}}, once. no subscription, ever. if you change your mind at any point, reply to this and we'll take you off the list and delete your address, no questions.\n\nwant to skip ahead? every friend who joins moves you up 10 places:\n{{referralUrl}}\n\n— The Litter\nadoptaboop.com\n"
  },
};

export const WAITLIST_CONFIRMATION_TEMPLATE = EMAIL_TEMPLATES["waitlist-confirmation"];
