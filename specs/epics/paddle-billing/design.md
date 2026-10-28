# paddle-billing — design

## 1. The template

Paddle's Next.js starter kit ([PaddleHQ/paddle-nextjs-starter-kit](https://github.com/PaddleHQ/paddle-nextjs-starter-kit),
Vercel's Paddle Billing Subscription Starter) is a Next.js 15 App Router app
for a demo product called AeroEdit. Its home page is a three-tier pricing
page (Starter, Pro, Advanced, monthly or yearly) whose prices Paddle.js
localizes for the visitor's country; each plan's **Get started** opens an
inline Paddle Checkout (`/checkout/<priceId>`). Supabase Auth signs visitors
up and in with email and password, as an anonymous guest ("Log in as Guest",
which then gives the guest an email address) or with GitHub, through
`@supabase/ssr` cookies the middleware refreshes. The dashboard lists the
signed-in customer's subscriptions — each with its next and past payments
and a cancel action — and their payments, read from Paddle's API for the
Paddle customer whose email is the visitor's. The webhook
(`/api/webhook`) verifies each delivery's `Paddle-Signature` with the Paddle
SDK and writes customers and subscriptions into two Supabase tables. On
Vercel, the Supabase integration creates the project and its env vars, the
owner runs the two migrations in `supabase/migrations`, sets four Paddle env
vars, and replaces the price ids in `src/constants/pricing-tier.ts`.

The reference is [subscription-payments](https://github.com/sourceplane/subscription-payments),
the same shape for Stripe: Supabase Auth and its Data API reached through
supabase-js over HTTPS (so no Hyperdrive), one wiring document per
environment, the Supabase Terraform root, db-migrate through the Management
API, row-level security checked by a migration, and a billing provider the
owner connects after the build.

## 2. How it maps to Cloudflare and Supabase

| Vercel | Here | Why |
|---|---|---|
| Next.js 15.5 hosting | One Worker (`.open-next/worker.js`) + Static Assets, built by `@opennextjs/cloudflare` on Next.js 16.3.8 | The adapter (1.20.11, the newest on npm) refuses Next.js 15.5 as past the support window it builds for; 16.3.8 is the reference's pin |
| `middleware.ts` (the edge runtime) | `src/proxy.ts`, Next.js 16's name for it, on the Node.js runtime | Next.js 16 renamed the file and runs it on Node.js |
| The Supabase integration's env vars | `WIRING_SUPABASE` per environment, from the supabase root's apply: the URL and anon key as wrangler vars the build inlines, the service-role key a Worker secret every deploy pushes | The reference's shape: the service-role key bypasses RLS and never enters a file or a bundle |
| The integration's project, its Site URL set by hand, anonymous sign-ins turned on by hand | `infra/terraform/supabase`: one project per environment; `supabase_settings` sets the Site URL and redirect allow-list to the Worker, autoconfirm, and anonymous sign-ins on | A product comes up with its Auth already pointed at itself, the guest login working |
| `supabase/migrations`, run by the owner | `packages/db`: `010` and `020` are upstream's two files byte for byte, `030` re-enables RLS by name and refuses any table in `public` without it; applied by `infra/db-migrate` before the Worker deploys | One schema, in order, recorded in a ledger |
| Four Paddle env vars | The product's own optional Orun secrets, under upstream's names (§3) | Secrets are Orun's; Paddle is the owner's to connect |
| The GitHub sign-in's return address, hard-coded to the demo | `siteUrl()` (`NEXT_PUBLIC_SITE_URL`, the environment's origin, inlined) + `/auth/callback` | Each product returns to itself |
| Vercel's image optimizer | `images.unoptimized` | No optimizer on Workers |
| "Deploy with Vercel" | `orun new --blueprint repo-blueprint.yaml` | One landing to live |

## 3. Paddle's keys

Upstream reads four env vars: `PADDLE_API_KEY` and
`PADDLE_NOTIFICATION_WEBHOOK_SECRET` on the server, and
`NEXT_PUBLIC_PADDLE_CLIENT_TOKEN` and `NEXT_PUBLIC_PADDLE_ENV` in the
browser. Here they keep those names and are the product's own Orun secrets
per environment, declared by `apps/web/component.yaml` as
`optionalSecretEnv` — best-effort references: one nobody has stored is
skipped when the job resolves its secrets. What happens to each in the web
lane:

- the **server-side two** are pushed to the Worker as Worker secrets after
  the build, by the same tool that pushes the service-role key
  (`tooling/wire/secrets.mjs --optional-env`, `wrangler secret bulk`, the
  values over stdin; skipped when unset; nothing pushed from a verify lane).
  The build never reads them (turbo's strict env mode passes it only what
  `apps/web/turbo.json` declares), so they are in no bundle — the e2e builds
  with sentinels for both and looks for them in everything the build wrote;
- the **public two** are declared to turbo's build task, and `next build`
  inlines them into the browser bundle, as upstream does.

The code reads them per call (`src/utils/paddle/config.ts`): on Workers the
environment is the request's, and upstream's module-level client
(`subscriptions/actions.ts`) became one built per call.

## 4. Paddle not connected

A fresh product has no Paddle account, and must still come up — the
reference's rule. So:

| Surface | With no Paddle key |
|---|---|
| Pricing (`/`) | The three plans, their features and checkout links, with **"Paddle is not connected."** — "Connect Paddle to show prices and take payments." — in place of prices (`data-paddle="not-connected"`); upstream's price skeleton would never stop loading |
| Checkout (`/checkout/<priceId>`) | The page, with the notice where Paddle's frame would be |
| The dashboard's subscriptions card and page, a subscription, the payments | The notice, decided before any network call (`isPaddleConnected()`); the reads and the cancel action answer `{ error: "Paddle is not connected." }` |
| The webhook | 503 `{"error":"Paddle is not connected."}` until its secret is set, which Paddle retries |
| Sign-up, log-in, the guest login, GitHub (once enabled), the dashboard | As upstream |

## 5. The webhook

Upstream's route verifies with the Paddle SDK's `webhooks.unmarshal`:
HMAC-SHA256 over `ts:body` with the destination's secret, compared with the
header's `h1`, refused when the timestamp is more than five seconds old. The
SDK ships a Node.js build (`node:crypto`) and an edge one (WebCrypto); the
Node.js build is what Next.js's server bundle resolves, and Workers runs it
under `nodejs_compat`. Both verified real signatures in this tree's tests
and under `wrangler dev`, so the template's verifier stays. Two changes: the
verifier no longer needs `PADDLE_API_KEY` (it never calls Paddle), and a
delivery whose signature does not verify answers 400 instead of upstream's
500 — a forged delivery is not an error of ours for Paddle to retry. A
verified one the database refuses (a subscription for a customer not yet
synced) is still a 500, so Paddle retries it after the customer lands.

## 6. The schema

Upstream's first migration creates `customers` (Paddle customer id → email)
and `subscriptions` with read policies for any signed-in user, and RLS off;
its second turns RLS on and narrows both policies to the visitor's own rows
(by the email in their JWT). Both are applied as they are — `010` and `020`,
byte for byte, which `tests/db` checks against `apps/web/supabase/migrations`
— and `030` re-enables RLS by name and raises if any table in `public` is
still without it. The webhook writes through the service role, which
bypasses RLS; the dashboard reads through the visitor's session, which RLS
confines to their own customer row.

## 7. The guest login

The log-in page's primary button is "Log in as Guest": Supabase's anonymous
sign-in, then an email (`aeroedit+<time>@paddle.com`, upstream's) set on the
anonymous user so Paddle's checkout has one. Supabase projects refuse
anonymous sign-ins by default, so the root turns them on
(`authAnonymousSignIns`, default `"true"`); the product's README says how to
turn them off with the button, or put a CAPTCHA in front of them.

## Alternatives rejected

- **Keeping Next.js 15.5 with `--dangerouslyUseUnsupportedNextVersion`.**
  The adapter refuses 15.5 for a reason (no security fixes); the flag is the
  workaround the brief rules out.
- **Paddle's keys as Worker secrets the owner sets with `wrangler secret
  put`** (the reference's Stripe keys). A product's secrets are Orun's; and
  the server-side keys still never reach a bundle, because the deploy pushes
  them as Worker secrets.
- **Paddle's keys inlined at build** (admin-dashboard's GitHub keys). A
  server-side key would sit in the Worker's script, readable by anyone who
  can read the account's scripts.
- **A WebCrypto verifier of our own.** The SDK's verifier already runs on
  Workers; replacing the template's code would buy only a constant-time
  comparison (risk PB-D).
- **The price ids as secrets.** They are not secret and they are the plans'
  configuration, in the file the template's README tells its owner to edit.
