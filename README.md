# paddle-billing

Paddle's [Next.js starter kit](https://github.com/PaddleHQ/paddle-nextjs-starter-kit)
(Vercel's [Paddle Billing Subscription Starter](https://vercel.com/templates/next.js/paddle-billing-subscription-starter))
— a three-tier pricing page localized by Paddle.js, an inline Paddle
Checkout, Supabase Auth with cookie sessions through `@supabase/ssr`, a
dashboard of the customer's subscriptions and payments read from Paddle's
API, and the webhook that keeps Paddle's customers and subscriptions in
Postgres — running on **Cloudflare Workers + Static Assets** through
[`@opennextjs/cloudflare`](https://opennext.js.org/cloudflare), with a
**Supabase** project per environment provisioned by Terraform and its schema
applied by the `db-migrate` runner through
[Orun](https://github.com/sourceplane/orun), the way
[subscription-payments](https://github.com/sourceplane/subscription-payments)
does it for Stripe, deployed by
[Orun](https://github.com/sourceplane/orun) to stage and prod on every merge.
Packaging it as an Orun baseline is the next milestone (PB2).

The template's code is the code, moved to Next.js 16 with only the changes
Next.js 16 and Workers force. What a fresh, unattended deployment forces on
top: the app reads its Supabase project from ONE wiring document per
environment (`WIRING_SUPABASE`: the URL and anon key the build inlines, and
the service-role key the deploy pushes to the Worker as a secret — never a
var or a bundle); Paddle's keys are the owner's own optional secrets, so the
app deploys, signs users up, in and in as guests and renders the dashboard
with no Paddle account, while pricing shows the plans with a notice instead
of prices, checkout and the dashboard's Paddle views say Paddle is not
connected, and the webhook answers 503; and both tables in `public` keep
upstream's row-level security, checked by a migration of its own. See
[`specs/epics/paddle-billing`](specs/epics/paddle-billing/README.md) for the
design, the milestones and the as-built status, including every departure.

## What is here (the product)

| Surface | Where |
|---|---|
| The product's name and origin | `apps/web/src/utils/site.ts` |
| Pricing (`/`), checkout (`/checkout/[priceId]`, `/checkout/success`), log-in and sign-up, the dashboard (`/dashboard`: subscriptions, payments), the auth code exchange, the Paddle webhook (`/api/webhook`), `/api/health` | `apps/web/src/app` |
| The plans and their Paddle price ids | `apps/web/src/constants/pricing-tier.ts` |
| Paddle (whether it is connected, the API client, the webhook's verifier and its sync), Supabase clients (browser, server, service role, the proxy) | `apps/web/src/utils`, `apps/web/src/proxy.ts` |
| The schema, for local Supabase-CLI development | `apps/web/supabase` |
| The same schema as the migrations CI applies, and row-level security checked | `packages/db/src/migrations` (`010_paddle_initialize`, `020_restrict_read_policies`, `030_row_level_security`), `infra/db-migrate` |
| Workers build and deploy contract | `apps/web/next.config.mjs`, `open-next.config.ts`, `wrangler.template.jsonc` → `wrangler.jsonc` (committed), `component.yaml` |
| The deploy-time wiring: the wrangler render and the Worker-secret push | `tooling/wire` |
| The Supabase project (stage, prod) and its Auth settings | `infra/terraform/supabase` |
| Tests | `tests/web`, `tests/db` (vitest; `tests/db` runs every migration in PGlite and checks row-level security) |

## Getting started

```bash
pnpm install
pnpm run wire:fixture   # re-render apps/web/wrangler.jsonc from its template (committed; this changes nothing)
pnpm typecheck
pnpm lint
pnpm test
pnpm build              # packages/db → dist; next build + opennextjs-cloudflare build → apps/web/.open-next
```

The build needs no Supabase project and no Paddle account. Running it
locally — the Supabase CLI's stack or a hosted project, `.env.local`,
`next dev` or `wrangler dev`, a Paddle sandbox — is in the product's README
(`.baseline/product/README.md`), which is what a product built from here
carries.

## How it maps to Vercel

| Vercel | Here |
|---|---|
| Next.js hosting, `middleware.ts` on the edge | One Cloudflare Worker (`.open-next/worker.js`) + Static Assets, on Next.js 16.3.8 (the template's 15.5 is past the support window the Cloudflare adapter builds); the middleware is `proxy.ts` (Next.js 16's name) and runs in the Worker |
| Project env vars set by the Supabase integration | `WIRING_SUPABASE` per environment: the URL and anon key as wrangler vars the build inlines, the service-role key a Worker secret every deploy pushes |
| The integration confirming the template's `supabase/migrations` | `infra/db-migrate` applies `packages/db/src/migrations` (upstream's two migrations, byte for byte, then a row-level security check) through Supabase's Management API per environment, after the project exists, before the Worker deploys |
| Paddle keys in the project's env vars | The product's own optional Orun secrets, under upstream's names: the server-side two pushed to the Worker as Worker secrets by every deploy, the public two inlined by the build; until they are set, prices, checkout and the dashboard's Paddle views say Paddle is not connected and the webhook answers 503 |
| The Supabase project's Site URL, set by hand (and anonymous sign-ins turned on for the guest login) | `infra/terraform/supabase` sets the Site URL and the redirect allow-list to the Worker, and turns anonymous sign-ins on |
| A Supabase project created by the integration | `infra/terraform/supabase` (one project per environment), credentials and keys as orun secrets |
| Vercel's image optimizer | Images served as they are (`images.unoptimized`): Workers has no Next.js image optimizer |
| "Deploy with Vercel" (clone the template) | `orun new --blueprint repo-blueprint.yaml` — a new repository, branded, provisioned, deployed |

## CI

| Workflow | What it runs | Ships to a product |
|---|---|---|
| `ci.yml` | the Orun pipeline, and the only workflow a product carries: `orun plan --changed`, then one job per lane. A pull request runs the verify lanes (the app built and dry-deployed per environment, the Terraform root checked and planned, the migrations planned; the packages and the two test suites only installed and their structure checked), except the bootstrap's own landings (`orun/BASE-*`), where `plan` alone runs and nothing waits for it — the landing was checked in the build box; a merge applies, migrates and deploys stage → prod. Typecheck, lint and the tests run in `baseline.yml`'s e2e tier on the landing before every tag, and in a product as the `pnpm` scripts its developers run before they push. It plans nothing while `intent.yaml` names the placeholder workspace `ws_CHANGE_ME`, as this repository does. A manual run (Orunbase's Deploy button, or Run workflow on `main`) plans the environment and components it names under the push-to-main trigger, so they deploy as a merge deploys them | yes |
