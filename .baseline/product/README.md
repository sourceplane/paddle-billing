# paddle-billing

Paddle's [Next.js starter kit](https://github.com/PaddleHQ/paddle-nextjs-starter-kit)
— a three-tier pricing page localized by Paddle.js, an inline Paddle
Checkout, Supabase Auth (email and password, a guest login and GitHub) with
cookie sessions through `@supabase/ssr`, a dashboard of the customer's
subscriptions and payments read from Paddle's API, and the webhook that keeps
Paddle's customers and subscriptions in Postgres — on **Cloudflare Workers +
Static Assets** through [`@opennextjs/cloudflare`](https://opennext.js.org/cloudflare),
with a **Supabase** project per environment. Terraform provisions the project
and Orun's `db-migrate` applies the schema, row-level security on every table
included, all on every merge to `main`.

## Live deployment

<!-- 02-docs:begin -->
Not recorded yet. The bootstrap's last phase writes the live URLs, the
workspace, whether Paddle is connected and the secrets the product uses into
[ai/context/deployment.md](ai/context/deployment.md); how the product deploys
and how to operate it is in
[ai/context/operations.md](ai/context/operations.md).
<!-- 02-docs:end -->

## What is here

| Surface | Where |
|---|---|
| The product's name and origin | `apps/web/src/utils/site.ts` |
| The logo and icons (the template's AeroEdit marks — replace them with yours) | `apps/web/public/logo.svg`, `apps/web/public/assets/icons/logo` |
| Pricing (`/`), checkout (`/checkout/[priceId]`, `/checkout/success`), log-in and sign-up, the dashboard (`/dashboard`: subscriptions, payments), the auth code exchange, the Paddle webhook (`/api/webhook`), `/api/health` | `apps/web/src/app` |
| The plans and their Paddle price ids | `apps/web/src/constants/pricing-tier.ts` |
| Paddle: whether it is connected, the API client, the webhook's verifier and its sync | `apps/web/src/utils/paddle` |
| Supabase clients (browser, server, service role, the session-refreshing proxy) | `apps/web/src/utils/supabase`, `apps/web/src/proxy.ts` |
| Workers build and deploy contract | `apps/web/next.config.mjs`, `open-next.config.ts`, `wrangler.template.jsonc` → `wrangler.jsonc`, `component.yaml` |
| The deploy-time wiring: the wrangler render and the Worker-secret push | `tooling/wire` |
| The schema as migrations, and their runner | `packages/db` (`@saas/db`) |
| The Supabase project and the migration step | `infra/terraform/supabase`, `infra/db-migrate` |
| Local development with the Supabase CLI | `apps/web/supabase` |
| Tests | `tests/web`, `tests/db` (vitest) |

## Getting started

```bash
pnpm install
pnpm run wire:fixture   # re-render apps/web/wrangler.jsonc from its template (it is committed)
pnpm typecheck
pnpm lint
pnpm test               # tests/db runs every migration in PGlite and checks row-level security
pnpm build              # next build + opennextjs-cloudflare build → apps/web/.open-next
```

The build needs no Supabase project and no Paddle account: it inlines the
placeholder project from the committed `wrangler.jsonc`, and without a
client-side token it builds the site with Paddle not connected.

## Running it locally

1. **A Supabase project.** Either the Supabase CLI's local stack
   (`npx supabase start` in `apps/web`, which applies
   `apps/web/supabase/migrations`; turn `enable_anonymous_sign_ins` on in
   `apps/web/supabase/config.toml` for the guest login), or a hosted project
   you apply `packages/db/src/migrations` to.
2. **Environment.** Copy `apps/web/.env.local.example` to
   `apps/web/.env.local`: the project URL, anon and service-role keys, and —
   optionally — Paddle's. `next dev` reads it:

   ```bash
   pnpm --filter @app/web dev          # http://localhost:3000
   ```

3. **Or the built Worker** under `wrangler dev`, which reads the Supabase URL
   and anon key from `wrangler.jsonc` (point them at your project in
   `wiring.fixture.json` and re-render, or override them in `.dev.vars`) and
   its secrets from `apps/web/.dev.vars` (copy `.dev.vars.example`); Paddle's
   public token and environment are read by the build, so export them before
   `pnpm build`:

   ```bash
   pnpm build
   pnpm --filter @app/web preview      # http://localhost:8787
   ```

4. **Paddle.** With a [sandbox account](https://sandbox-login.paddle.com/signup),
   create three products with a monthly and a yearly price each and put their
   price ids in `apps/web/src/constants/pricing-tier.ts`; test a checkout with
   card `4242 4242 4242 4242`, any future date, security code `100`. Without
   Paddle's keys everything else runs, and the pricing page says Paddle is not
   connected.

## How it deploys

Merges to `main` converge through [Orun](https://github.com/sourceplane/orun):
`.github/workflows/ci.yml` plans the changed components and runs each lane
against the workspace in `intent.yaml`. Per environment the order is
enforced — **the Supabase project, then the migrations, then the Worker** —
because each reads what the one before it published: the project's
credentials, then `WIRING_SUPABASE` (the project URL and anon key the build
inlines, and the service-role key the deploy hands the Worker as a secret).
`stage` deploys first and `prod` once stage has converged on the same
commit; `dev` only verifies. Every deploy is smoke-tested over HTTP,
`/api/health` included, which answers only when the Worker reaches its
migrated project with a valid service-role key.

The pipeline holds one credential, GitHub's own `GITHUB_TOKEN`. The
Cloudflare token and account id and the Supabase access token and org id are
brokered per run from the workspace's connections; the Supabase project's
credentials and keys are published by the Terraform apply as orun secrets.
Nothing provider-shaped is stored in the repository or in GitHub, and neither
the service-role key nor a Paddle server-side key is ever in a wrangler file
or a bundle.

Both tables in `public` have row-level security, with the template's
policies: a signed-in visitor reads their own Paddle customer row (matched by
their email) and that customer's subscriptions, never anyone else's, and only
the webhook's sync (the service role) writes. Migration
`030_row_level_security` stops a deploy that would leave a table without it.

**Deploy by hand.** Orunbase's **Deploy** button on a component, or **Run
workflow** on the CI workflow in GitHub's Actions tab (on `main`), runs
`ci.yml` for the environment and components you pick, and each one deploys
exactly as a merge would deploy it. Leave the component blank to redeploy
every component in that environment, with nothing changed: after setting a
Paddle key, say. A component with nothing to run in that environment (a test
suite in `prod`) is left out with a notice.

## Connecting Paddle

Paddle is a third party no platform brokers, so the product deploys without
it: sign-up, sign-in, the guest login and the dashboard work; the pricing
page shows the plans and says **"Paddle is not connected."** in place of
prices, checkout and the dashboard's subscription and payment views say the
same, and the webhook answers 503. To turn billing on, per environment
(sandbox first):

1. In Paddle (**Developer tools → Authentication**), create an API key and a
   client-side token. In **Developer tools → Notifications**, add a
   destination at
   `https://paddle-billing-web-prod.your-workers-subdomain.workers.dev/api/webhook`
   (and `-stage` for stage) for `customer.created`, `customer.updated`,
   `subscription.created` and `subscription.updated`, and copy its secret
   key. In **Checkout → Website approval** and **Checkout settings**, approve
   the same origin and make it the default payment link.
2. Store the four values as the product's secrets for the environment —
   upstream's names; `orun secrets set` prompts for each value:

   ```bash
   orun secrets set PADDLE_API_KEY                     --env prod
   orun secrets set PADDLE_NOTIFICATION_WEBHOOK_SECRET --env prod
   orun secrets set NEXT_PUBLIC_PADDLE_CLIENT_TOKEN    --env prod   # public by design: the build inlines it
   orun secrets set NEXT_PUBLIC_PADDLE_ENV             --env prod   # sandbox or production (sandbox if unset)
   ```

3. Put your price ids in `apps/web/src/constants/pricing-tier.ts` (the
   template's are its own sandbox's) and merge — or redeploy `web` (Deploy
   by hand, above): the deploy pushes the two server-side keys to the Worker
   as Worker secrets and the build inlines the public two.

A key removed from the product's secrets stays on the Worker until you
delete it there (`wrangler secret delete <NAME> --name paddle-billing-web-<env>`).

## GitHub sign-in

The log-in page's **Log in with GitHub** goes through Supabase Auth's GitHub
provider, which is the project's to enable: create a GitHub OAuth App whose
callback is `https://<project-ref>.supabase.co/auth/v1/callback`, then turn
the provider on with its id and secret (Supabase dashboard → Authentication
→ Sign In / Providers → GitHub). Visitors return to the Worker's
`/auth/callback`, which the project already allows.

## Supabase Auth email

The Supabase project's Auth sends visitors back to the Worker (its Site URL
and redirect allow-list are set by `infra/terraform/supabase`), new sign-ups
are signed straight in, because a project without SMTP of its own emails
only its organization's members, and anonymous sign-ins are on for the
log-in page's **Log in as Guest**. Before real users arrive, give the project
an SMTP server (Supabase dashboard → Authentication → Emails → SMTP
Settings), then set `authEmailConfirmation: "true"` in
`infra/terraform/supabase/component.yaml` and merge: sign-up then confirms
the address first. To drop the guest login, remove its button
(`apps/web/src/components/authentication/login-form.tsx`) and set
`authAnonymousSignIns: "false"` in the same change; to keep it, protect it
with a CAPTCHA (Supabase recommends one on a project with anonymous sign-ins
on).

## Custom domain

The app answers on workers.dev from its first deploy. To serve it on your
own domain, attach the domain to the Worker in Cloudflare (Workers & Pages →
`paddle-billing-web-prod` → Settings → Domains & Routes), set
`NEXT_PUBLIC_SITE_URL` in `apps/web/wrangler.template.jsonc` and the Auth
origin (`app_origin`) in `infra/terraform/supabase/terraform/main.tf` to it,
run `pnpm run wire:fixture`, merge, and point Paddle's notification
destination and website approval at the new origin. In the same change,
replace the reserved placeholder `paddle-billing.example.com` the product was
born with in `intent.yaml`'s `BASE_DOMAIN` (one line per environment) — the
one place the repository names the domain itself.

## CI

| Workflow | What it runs |
|---|---|
| `ci.yml` | the Orun pipeline, and the only workflow: `orun plan --changed`, then one job per lane. A pull request runs the verify lanes — the app built and dry-deployed for each environment, the Terraform root checked and planned, the migrations planned and their checksums verified — with nothing applied or deployed. It does not typecheck, lint or run the tests: those are the `pnpm` scripts above (Getting started), run them before you push. A merge applies, migrates and deploys stage → prod |

## Credits

The app is Paddle's [Next.js starter kit](https://github.com/PaddleHQ/paddle-nextjs-starter-kit)
(Apache-2.0 — `apps/web/LICENSE`).
