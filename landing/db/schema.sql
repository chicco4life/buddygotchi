-- Boop waitlist. One table. Applied via `npm run db:push`.
create table if not exists signups (
  id             bigint generated always as identity primary key,
  email          text not null unique,
  source         text not null,              -- 'hero' | 'footer'
  price_cohort   integer,                    -- 99 | 129 | null (default $119 shown)
  utm_source     text,
  utm_medium     text,
  utm_campaign   text,
  utm_content    text,
  utm_term       text,
  referrer       text,                       -- document.referrer at landing
  ref_code_used  text,                       -- ?ref= code they arrived with
  referral_code  text not null unique,       -- their own share code
  referral_count integer not null default 0,
  created_at     timestamptz not null default now()
);

create index if not exists signups_created_at_idx on signups (created_at);
create index if not exists signups_referral_code_idx on signups (referral_code);
