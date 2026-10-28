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
does it for Stripe, and packaged as an **Orun baseline**: one command takes
a new product from nothing to live on stage and prod, in its own repository,
under its own name — in ONE landing.

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
upstream's row-level security, checked by a migration of its own. What the
baseline adds is everything needed to make a copy of it somebody else's,
built the way [cirrus-baseline](https://github.com/sourceplane/cirrus-baseline)
is. See
[`specs/epics/paddle-billing`](specs/epics/paddle-billing/README.md) for the
design, the milestones and the as-built status, including every departure.

## Instantiating a product

```bash
git clone --depth 1 --branch <baseline-tag> https://github.com/sourceplane/paddle-billing
cd paddle-billing
orun new --blueprint repo-blueprint.yaml --out ~/products/acme-pay --run-hooks --resume \
  --set reponame=acme-pay --set productname="Acme Cloud" \
  --set githuborg=acme-inc --set subdomain=<workers-dev-subdomain>
```

Or, once the platform's registry lists it, from the Orun console (Baselines →
`paddle-billing` → Build). Two phases: **`01-product`** creates the
repository, mints the four brokered credentials (Cloudflare and Supabase)
and lands the whole product as one pull request, whose convergence on
`main` provisions and deploys it per environment in a fixed order —

```
supabase ──▶ db-migrate ──▶ web
```

— each edge `mode: enforced` on a push to main and advisory on a pull
request; then **`02-docs`** records the live deployment from probed facts.
The Supabase organization needs room for **two** projects (stage and prod;
its free plan allows exactly two active ones).
**[BOOTSTRAP.md](BOOTSTRAP.md)** is the operator guide;
[docs/phases/](docs/phases/README.md) has a page per phase.

The new repository receives the **product only** — the app, the Terraform
root, the migrations, the tests, its CI, its tooling, a README of its own
and its operating contract — renamed throughout to the product's name,
repository, Worker and Supabase project. None of this repository's machinery
ships. **Paddle is the owner's to connect afterwards** (the product's README,
"Connecting Paddle"): no platform brokers it, so the card asks for no Paddle
key. Neither is GitHub sign-in, nor Supabase Auth's email: the project signs
new users straight in until its owner gives it SMTP (the product's README,
"Supabase Auth email").

| What makes it a baseline | Where |
|---|---|
| The console card (inputs, secrets, programme) | `blueprint.yaml` |
| The build document (modules, phases, hooks) | `repo-blueprint.yaml` |
| This tree's identity, the product's README and the bootstrap's task contracts | `.baseline/` |
| The rename engine (product-name seam: `apps/web/src/utils/site.ts`) | `tooling/rebrand/rebrand.mjs` |
| The bootstrap's helpers (deferrals, redeploy marker, work-tree strip) | `tooling/bootstrap/` |
| The deployment-record renderer | `hooks/render-deployment-docs.sh` |
| The product's context pack | `ai/context/` |
| The baseline's tests: contract, leak, offline bootstrap and plans, end to end | `testing/`, `.github/workflows/baseline.yml` |
| Cutting a `baseline-vN` tag | `.github/workflows/tag.yml` |

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
| `baseline.yml` | the baseline's own tiers: contract tests; the blueprint read by the pinned orun, the leak gate, the offline bootstrap and the product's own plans; the product built, migrated into a local Supabase (its real Auth and Data API), dry-deployed, served, signed up, out and in on and logged in as a guest, and its webhook verified and synced | no |
| `tag.yml` | cuts a `baseline-vN` tag (manual) | no |
