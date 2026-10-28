# paddle-billing — operating contract (for humans and agents)

This is the standing guide to how this product is deployed and operated.
Instance facts (live URLs, workspace, whether Paddle is connected, the
secrets it uses) live in [deployment.md](deployment.md), rendered from
probed reality by the bootstrap's `02-docs` phase; this file is the contract
that stays true between deployments. It is written to give an agent with
repository read access enough context to reason about and operate the product
without any other source.

## What this system is

Paddle's Next.js starter kit — a three-tier pricing page localized by
Paddle.js, an inline Paddle Checkout, Supabase Auth (email and password, a
guest login through anonymous sign-ins, GitHub) with cookie sessions through
`@supabase/ssr`, a dashboard of the customer's subscriptions and payments
read from Paddle's API, and the webhook that keeps Paddle's customers and
subscriptions in Postgres — on Cloudflare Workers, with a Supabase project
per environment, expressed as an Orun component-native desired-state repo.
Six components:

- **`infra/terraform/supabase`** (`supabase`) — one Supabase project per
  environment, its Auth pointed at the app (Site URL, redirect allow-list,
  sign-up confirmation, anonymous sign-ins). Its apply publishes
  `SUPABASE_PROJECT_REF`, `SUPABASE_DB_PASSWORD`, `SUPABASE_DB_URL` and
  `WIRING_SUPABASE` (the project URL, the anon key and the service-role key,
  one document) onto the environment's secret rung.
- **`infra/db-migrate`** (`db-migrate`) — applies `packages/db`'s migrations
  to the environment's database through Supabase's Management API. Each
  migration is recorded with its checksum in `_migrations.applied`; only the
  missing ones apply.
- **`packages/db`** (`db`) — the migrations and their runner.
- **`apps/web`** (`web`) — the app: Next.js built by `@opennextjs/cloudflare`
  into one Worker plus Static Assets. It reaches Supabase through
  supabase-js — Auth and the Data API — with the anon key and the visitor's
  session, and with the service-role key for the Paddle webhook's sync
  (`src/utils/supabase/server-internal.ts`). It reaches Paddle's API with
  `PADDLE_API_KEY` for the dashboard's subscriptions, payments and the cancel
  action (`src/utils/paddle`), and the browser reaches Paddle.js with the
  client-side token for prices and checkout.
- **`tests/web`**, **`tests/db`** — vitest suites, verified on the `dev` rung.

Environments: **`stage`** and **`prod`** are deployed; **`dev` is
verify-only by design** — lanes build and test, nothing deploys.

## Identity and tenancy

Every remote operation runs against ONE Orun workspace, declared in
`intent.yaml` under `execution.state.workspace` — committed, enforced, and
what CI uses. Do not remove it; headless credentials depend on it. If it
reads `ws_SET_ME`, the bootstrap had no workspace to write: set the real one
before anything else.

## How deployment works

1. Merge (or push) to `main`.
2. CI (`.github/workflows/ci.yml`) runs `orun plan --changed` — only
   components whose files changed are planned — then runs each planned lane
   with `orun run --remote-state`, authenticated by GitHub OIDC (the
   exchange resolves this repository's linked workspace server-side).
3. Per environment, in this order — each edge `mode: enforced` on a push to
   main, advisory on a pull request (which deploys nothing):
   **`supabase` → `db-migrate` → `web`.** A job resolves its secrets when it
   starts, so each one reads what the apply before it published. The app's
   deploy re-renders `apps/web/wrangler.jsonc` from `WIRING_SUPABASE` before
   it builds (the URL, the anon key and the Worker's origin are inlined into
   the build, and so are Paddle's public token and environment when the
   owner has stored them), pushes the document's service-role key — and
   Paddle's two server-side keys, the ones that exist — to the Worker as
   Worker secrets (`tooling/wire/secrets.mjs`, `wrangler secret bulk`, the
   values over stdin), deploys `paddle-billing-web-<env>`, and smoke-tests
   it: the pricing page and its checkout links, and `/api/health`, which
   answers 200 only when the project is reachable with those keys, the
   schema is migrated, and the service-role secret is the project's own.
4. `prod` deploys after `stage` has converged on the same commit
   (`environments.prod.promotion` in intent.yaml).
5. **The convergence run is the deployment.** A green run means every
   planned lane applied. Failed lanes are retried with
   `gh run rerun --failed`, which resumes the same execution.

Caveats that matter:

- A push that touches no component files plans zero lanes — that run is
  green and deployed nothing. Never treat "latest run green" as "product
  converged"; probe the URLs instead.
- `apps/web/wrangler.jsonc` is committed as the render of
  `wrangler.template.jsonc` from `wiring.fixture.json` (a placeholder project
  URL and key): edit the template and run `pnpm run wire:fixture`. The deploy
  lanes render the real one in their own job tree; never commit a real key.
  The service-role key and Paddle's server-side keys are never in a wrangler
  file: they are Worker secrets.
- Both tables in `public` have row-level security. Supabase's Data API
  serves `public` to the anon key, which every browser has, so the policies
  ARE the access control: a signed-in visitor reads their own `customers`
  row (matched by the email in their session) and that customer's
  `subscriptions`; nobody but the service role (the webhook's sync) writes.
  Migration `030_row_level_security` fails the deploy if any table in
  `public` is without RLS; give every new table RLS and the policies the app
  needs in its own migration, and never `FORCE` it.
- A migration is immutable once applied: its checksum is in
  `packages/db/src/manifest.ts` and in the database's ledger. Change the
  schema with a NEW migration in `packages/db/src/migrations` (and the same
  SQL in `apps/web/supabase/migrations` for the Supabase CLI's local stack).
- The webhook writes a subscription only for a customer it has already
  synced (a foreign key); Paddle sends `customer.created` first and retries
  what fails, so an out-of-order delivery lands on its retry.

## Secrets model

- **Brokered provider secrets**, minted per run from the workspace's
  connections — no long-lived values at rest, nothing to rotate by hand:
  `CLOUDFLARE_API_TOKEN` (the Worker's deploy and its secrets),
  `CLOUDFLARE_ACCOUNT_ID`, `SUPABASE_ACCESS_TOKEN` (project create, its Auth
  settings, migrations) and `SUPABASE_ORG_ID`.
- **Published by the apply** onto the stage and prod rungs:
  `SUPABASE_PROJECT_REF`, `SUPABASE_DB_PASSWORD`, `SUPABASE_DB_URL`,
  `WIRING_SUPABASE`.
- **The service-role key** bypasses row-level security. It travels only in
  `WIRING_SUPABASE` and reaches the Worker as the Worker secret
  `SUPABASE_SERVICE_ROLE_KEY`, set by every deploy; it is never a wrangler
  var and never in a client bundle (only server code — the webhook's sync
  and `/api/health` — reads it).
- **The owner's, optional**, because no platform brokers Paddle: the
  product's secrets `PADDLE_API_KEY` and `PADDLE_NOTIFICATION_WEBHOOK_SECRET`
  (server-side: every deploy pushes the ones that exist to the Worker as
  Worker secrets) and `NEXT_PUBLIC_PADDLE_CLIENT_TOKEN` and
  `NEXT_PUBLIC_PADDLE_ENV` (public by design: the build inlines them). The
  web lane references all four best-effort, so a missing one is skipped,
  not a failure. Until they exist the pricing page shows the plans with a
  "Paddle is not connected." notice in place of prices, checkout and the
  dashboard's subscription and payment views say the same (without calling
  Paddle), and the webhook answers 503.
- Inspect by NAME only: `orun secrets list --org <ws> --project` and
  `--env stage|prod`. No tooling in this repository prints a secret value,
  and no document in `ai/context/` may contain one.

## Connecting Paddle

Per environment (`stage`, `prod`), in the Paddle account you want to sell
from (sandbox first):

1. **Developer tools → Authentication**: create an API key and a client-side
   token. **Developer tools → Notifications**: add a destination at
   `https://paddle-billing-web-<env>.your-workers-subdomain.workers.dev/api/webhook`
   for `customer.created`, `customer.updated`, `subscription.created` and
   `subscription.updated`; copy its secret key. **Checkout → Website
   approval** and **Checkout settings**: approve that origin and make it the
   default payment link.
2. Store the product's four secrets for the environment (each prompts for
   its value):

   ```bash
   orun secrets set PADDLE_API_KEY                     --env <env>
   orun secrets set PADDLE_NOTIFICATION_WEBHOOK_SECRET --env <env>
   orun secrets set NEXT_PUBLIC_PADDLE_CLIENT_TOKEN    --env <env>
   orun secrets set NEXT_PUBLIC_PADDLE_ENV             --env <env>   # sandbox or production
   ```

3. Put the account's price ids in `apps/web/src/constants/pricing-tier.ts`
   and merge, or redeploy `web` by hand: the deploy pushes the server-side
   keys and the build inlines the public pair.

The webhook verifies each delivery's `Paddle-Signature` (HMAC-SHA256 over
`ts:body`, no older than five seconds — the Paddle SDK's own check): 400 for
one that does not verify, 500 when a verified one cannot be written (Paddle
retries it), 200 once synced. Re-running the bootstrap's `02-docs` phase
records the change in [deployment.md](deployment.md). A secret removed from
the product stays on the Worker until `wrangler secret delete <NAME> --name
paddle-billing-web-<env>`.

## Supabase Auth

The supabase root manages four Auth settings and leaves every other one to
the project: the Site URL and the one allowed redirect origin (the
environment's Worker), whether sign-up needs a confirmed email — off
(`authEmailConfirmation: "false"` in `infra/terraform/supabase/component.yaml`),
because a project without SMTP of its own emails only its organization's
members — and anonymous sign-ins — on (`authAnonymousSignIns: "true"`), for
the log-in page's **Log in as Guest**. Before real users arrive:

1. Give the project an SMTP server (Supabase dashboard → Authentication →
   Emails → SMTP Settings), then set `authEmailConfirmation: "true"` and
   merge: new sign-ups then confirm their address first.
2. Decide on the guest login: remove its button and set
   `authAnonymousSignIns: "false"`, or keep it behind a CAPTCHA.
3. GitHub sign-in is the project's GitHub provider: an OAuth App whose
   callback is the project's `/auth/v1/callback`, enabled in the dashboard
   (Authentication → Sign In / Providers). Visitors return to the Worker's
   `/auth/callback`, which the allow-list already names.
4. A custom domain: also change the Site URL and allow-list (the root's
   `app_origin`) and `NEXT_PUBLIC_SITE_URL` in `apps/web/wrangler.template.jsonc`.

## Verifying the system

```bash
# the app and its Supabase path on each environment (also recorded, probed, in deployment.md)
curl -s -o /dev/null -w '%{http_code}\n' https://paddle-billing-web-stage.your-workers-subdomain.workers.dev/
curl -s https://paddle-billing-web-prod.your-workers-subdomain.workers.dev/api/health
# the webhook: 503 until its secret is set, 400 for an unsigned delivery after
curl -s -o /dev/null -w '%{http_code}\n' -X POST -d '{}' https://paddle-billing-web-prod.your-workers-subdomain.workers.dev/api/webhook

# workspace readiness (integrations + repository link)
orun integrations list --org <ws> --json && orun cloud check --org <ws>
```

## Common operations

| task | how |
|---|---|
| deploy a change | merge to `main`; watch the run; failed lanes → `gh run rerun --failed` |
| deploy by hand | Orunbase's Deploy button, or `gh workflow run ci.yml --ref main -f environment=<env> [-f component=<a,b>]` — the named components (blank: every one) run in that environment as a merge runs them; started off `main` it is refused |
| change the schema | a new `packages/db/src/migrations/<nnn>_<name>/up.sql` and its manifest entry (`pnpm --filter @saas/db run manifest:fix` for its checksum) — with RLS and the policies the app needs on any new table — then merge: db-migrate applies it before the app deploys. `pnpm test` fails on a table in `public` without row-level security; regenerate `apps/web/src/lib/database.types.ts` with the Supabase CLI |
| change the plans | `apps/web/src/constants/pricing-tier.ts` (names, features and Paddle price ids), merge |
| redeploy without a change | edit the last line of the component's `component.yaml` (`# orun: redeploy <reason> <stamp>`) and merge — it is a deploy trigger, nothing reads it |
| connect Paddle | above |
| turn on email confirmation, drop the guest login, enable GitHub | above, "Supabase Auth" |
| rotate the service-role key | rotate it in the Supabase dashboard (API keys), then re-run the supabase apply (a merge touching `infra/terraform/supabase`): it republishes `WIRING_SUPABASE`, and the next web deploy pushes the new key |
| rotate a Paddle key | create the new one in Paddle, `orun secrets set` it for the environment, redeploy `web` |
| serve a custom domain | attach it to the Worker in Cloudflare; change `NEXT_PUBLIC_SITE_URL` in `apps/web/wrangler.template.jsonc` and the Auth origin in the supabase root; point Paddle's notification destination and website approval at it; replace the placeholder `paddle-billing.example.com` in `intent.yaml`'s `BASE_DOMAIN` with it |
| headless credentials | `ORUN_TOKEN` (workspace-scoped) + `GITHUB_TOKEN` |

The deployment record is the bootstrap's `02-docs` phase. Re-running it (the
Orun console's Retry on that phase, or `orun new … --phase 02-docs`)
re-probes the URLs and re-renders [deployment.md](deployment.md); it is
idempotent.

## Evolution

Structural changes (a second Worker, a queue, another data store) follow the
same contract that deployed the product: add a component under `apps/`,
`infra/` or `packages/` with a `component.yaml` — declaring `dependsOn` on
any infrastructure whose published secrets it reads, enforced on main — land
it as a pull request, and the convergence run applies it.
