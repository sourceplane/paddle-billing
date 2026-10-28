# apps/web — the app

A subscription site from Paddle's
[Next.js starter kit](https://github.com/PaddleHQ/paddle-nextjs-starter-kit)
(Apache-2.0, see `LICENSE`; its demo is https://paddle-billing.vercel.app/),
running on Cloudflare Workers + Static Assets:

- A three-tier pricing page (`/`) localized for 200+ markets by Paddle.js,
  monthly or yearly — or, until Paddle is connected, the plans without
  prices and a notice saying so
- An inline Paddle Checkout (`/checkout/<priceId>`), by card, Apple Pay,
  Google Pay, PayPal and the rest, and its success page
- Sign-up and log-in with Supabase Auth — email and password, a guest login
  (Supabase's anonymous sign-ins) and GitHub — with cookie sessions through
  `@supabase/ssr` and a proxy that refreshes them
- The dashboard (`/dashboard`): the visitor's subscriptions, each with its
  next and past payments and a cancel action, and their payments — read from
  Paddle's API for the Paddle customer whose email is the visitor's
- The Paddle webhook (`/api/webhook`), which keeps the `customers` and
  `subscriptions` tables in sync — verifying each delivery's
  `Paddle-Signature` with the Paddle SDK — and answers 503 until its secret
  is set
- `/api/health`, which answers 200 only when the Supabase project is
  reachable with the keys the Worker was built with, migrated, and its
  service-role key valid

The product's name is `src/utils/site.ts`; its logo is `public/logo.svg` (the
template's AeroEdit wordmark) and the icons in `public/assets/icons/logo/`.
The plans and their Paddle price ids are `src/constants/pricing-tier.ts` (the
template's sandbox prices: replace them with yours). The Supabase URL, the anon
key and the site's origin come from `wrangler.jsonc`'s vars, which `next
build` inlines (`next.config.mjs`); the service-role key is a Worker secret,
read only by server code (`src/utils/supabase/server-internal.ts`). Paddle's
keys are read per request (`src/utils/paddle/config.ts`): no Paddle client
exists until `PADDLE_API_KEY` does, and Paddle.js only once
`NEXT_PUBLIC_PADDLE_CLIENT_TOKEN` was set for the build.

```bash
pnpm dev               # next dev on http://localhost:3000, with .env.local
pnpm build             # next build + opennextjs-cloudflare build → .open-next/
pnpm preview           # wrangler dev over the built Worker, with .dev.vars
npx supabase start     # the Supabase CLI's local stack (supabase/migrations, supabase/config.toml)
```

How it runs locally, how it deploys — per environment, after the Supabase
project and the migrations, on merge to `main` — how to connect Paddle and
GitHub sign-in, and how to configure Supabase Auth's email are the
repository's README and `component.yaml` beside this file.
