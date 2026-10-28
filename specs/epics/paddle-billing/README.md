# paddle-billing — Paddle's Next.js starter kit on Cloudflare

**The template's subscription site as it is — the localized pricing page,
the inline Paddle Checkout, Supabase Auth with a guest login, the dashboard
of subscriptions and payments, the webhook that keeps customers and
subscriptions in Postgres — on one Cloudflare Worker, its Supabase project
per environment migrated before the Worker deploys, Paddle the owner's to
connect; and the baseline that makes a copy of it somebody else's product in
one landing.**

| | |
|---|---|
| Status | In progress — PB0 on main |
| Upstream | [PaddleHQ/paddle-nextjs-starter-kit](https://github.com/PaddleHQ/paddle-nextjs-starter-kit) (Apache-2.0), Vercel's [Paddle Billing Subscription Starter](https://vercel.com/templates/next.js/paddle-billing-subscription-starter), at `da90482` |
| Reference | [subscription-payments](https://github.com/sourceplane/subscription-payments) — Supabase Auth and its Data API, one wiring document, the Supabase root, db-migrate through the Management API, row-level security checked, a billing provider connected after the build |
| Key | `PB` |

## Read in this order

1. [design.md](design.md) — the template, how each Vercel piece maps to
   Cloudflare and Supabase, Paddle's keys, and the alternatives rejected.
2. [implementation-plan.md](implementation-plan.md) — the milestones.
3. [risks-and-open-questions.md](risks-and-open-questions.md) — what is not
   proven, and what was accepted.
4. [IMPLEMENTATION-STATUS.md](IMPLEMENTATION-STATUS.md) — what shipped, and
   every departure from the upstream template.

## Milestones

| Milestone | What it lands | Task |
|---|---|---|
| PB0 — the spec | the repository, its intent, CI, tooling and spec index; this doc set | PB-1 |
| PB1 — the billing starter on Workers and Supabase | the template in `apps/web`, its schema as migrations, the Supabase root, Paddle as optional secrets, the tests | PB-2 |
| PB2 — a baseline | the console card, the build document, the context pack and the baseline's tests | PB-3 |
