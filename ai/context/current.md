# paddle-billing — where this repository stands

The entry page for anyone (or any agent) picking this repository up. It is
this repository's own state and does not ship to a product built from it;
the two pages that do are [operations.md](operations.md) and
[deployment.md](deployment.md).

## What it is

Paddle's Next.js starter kit (Vercel's Paddle Billing Subscription Starter)
— a pricing page localized by Paddle.js, an inline Paddle Checkout, Supabase
Auth with a guest login, a dashboard of subscriptions and payments, and the
webhook that syncs customers and subscriptions into Postgres behind
row-level security — on Cloudflare Workers + Static Assets (through
`@opennextjs/cloudflare`), with its Supabase project from Terraform and its
schema applied by db-migrate. It is packaged as an Orun baseline:
`orun new --blueprint repo-blueprint.yaml` builds a new product in its own
repository and takes it to live on stage and prod in one landing
(`01-product`: the Supabase project, then the migrations, then the app),
then records what went live (`02-docs`). Paddle is the owner's to connect
afterwards; the app deploys and serves without it.

## Release

| | |
|---|---|
| Latest tag | `baseline-v1` (PB2 — the baseline) |
| Proven live | No. Everything short of the platform is proven offline in Baseline CI: the e2e tier migrates a local Postgres under the real Supabase Auth and Data API with the product's own runner, builds in orun's staged job tree, signs a user up, out and in and a guest in with Paddle not connected, and verifies and syncs signed webhook deliveries. No bootstrap from a tag has run against a workspace, and no Paddle account has been connected (PB-A, PB-B) |

## Where to read

| Question | Page |
|---|---|
| What shipped, and every departure from upstream | `specs/epics/paddle-billing/IMPLEMENTATION-STATUS.md` |
| Why it is built this way | [decisions.md](decisions.md), then `specs/epics/paddle-billing/design.md` |
| What could still go wrong | [open-risks.md](open-risks.md), then `specs/epics/paddle-billing/risks-and-open-questions.md` |
| How to instantiate it | `BOOTSTRAP.md`, `docs/phases/` |
| What each component is | `<component>/docs/` beside each `component.yaml` — `apps/web`, `packages/db`, `infra/db-migrate`, `infra/terraform/supabase`, `tests/{web,db}` (generated; `python3 tooling/catalog/gen-component-docs.py`) |

## Next

1. Bootstrap one product from `baseline-v1` against a workspace with
   Cloudflare and Supabase connected, and record its timings (closes PB-A).
2. Connect a Paddle sandbox to it: prices, a checkout, the webhook's sync
   and the dashboard's reads (closes PB-B).
