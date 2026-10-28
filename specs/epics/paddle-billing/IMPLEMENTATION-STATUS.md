# paddle-billing — implementation status

| Milestone | State | Landed |
|---|---|---|
| PB0 — the spec | ✅ | PB-1 |
| PB1 — the billing starter on Workers and Supabase | ✅ | PB-2 |
| PB2 — a baseline | ✅ | PB-3, tagged `baseline-v1` |

## Departures from the upstream template

Everything not listed here is the template as it is at `da90482`.

| # | What | Why |
|---|---|---|
| 1 | The app lives in `apps/web` of a pnpm workspace (`src/` kept); `supabase/` moved beside it; `.env.local.example` kept, `.dev.vars.example` added; upstream's `test` script (lint + prettier check) replaced by the workspace's typecheck, lint and test | The reference's shape |
| 2 | Next.js 15.5.18 → 16.3.8 (React 19.1.5 kept); `middleware.ts` → `proxy.ts` (same matcher, `export function proxy`) | The Cloudflare adapter refuses 15.5; Next.js 16 renamed the file |
| 3 | `eslint.config.mjs` in eslint-config-next 16's flat form (upstream used FlatCompat), with `react-hooks/set-state-in-effect` and `react-hooks/use-memo` off | Next.js 16 removed `next lint`; the React Compiler's rules postdate the template's hooks |
| 4 | Paddle read per call (`src/utils/paddle/config.ts`); `get-paddle-instance.ts` throws without `PADDLE_API_KEY` instead of building a client with an undefined key; `subscriptions/actions.ts` builds its client per call | On Workers the environment is the request's |
| 5 | Paddle not connected: the notice (`src/components/shared/paddle-not-connected`) on pricing, checkout and the dashboard; the dashboard's reads and the cancel action answer it without a call; `price-amount.tsx` shows `—` for a price Paddle did not return | A product deploys before its owner has a Paddle account |
| 6 | `NEXT_PUBLIC_PADDLE_ENV` defaults to `sandbox` (upstream required it set) | Upstream's README recommends the sandbox; a token alone now initializes Paddle.js |
| 7 | The webhook: 503 until its secret is set; 400 (upstream: 500) for a signature that does not verify; verified with no API key | design §5 |
| 8 | `src/utils/site.ts` (`SITE_NAME` = AeroEdit, and `siteUrl()`) for the title, the description, the logos' alternative text and the dashboard's copy; the GitHub sign-in returns to `siteUrl()` + `/auth/callback` (upstream: its demo's) | One rename seam; each product returns to itself |
| 9 | `next.config.mjs`: `images.unoptimized` (upstream allow-listed its demo's host), `output: 'standalone'`, the trace root at the workspace root, `env` from the wrangler render; `open-next.config.ts` and `wrangler.template.jsonc` added | OpenNext's build |
| 10 | `src/app/api/health/route.ts` added | The deploy's smoke and the record's probe |
| 11 | `@vercel/git-hooks` and `lint-staged` dropped | Vercel's pre-commit hooks; nothing runs them here |

## Departures from the reference

| # | What | Why |
|---|---|---|
| 1 | Paddle's keys are the product's optional Orun secrets (`optionalSecretEnv`); the server-side two pushed as Worker secrets by `secrets.mjs --optional-env` (new), the public two inlined | design §3 |
| 2 | Three migrations, upstream's two byte for byte; `030` is the RLS check | Upstream ships two |
| 3 | The supabase root also turns anonymous sign-ins on (`authAnonymousSignIns`) | The guest login |
| 4 | The smoke reads the pricing page's checkout links; the record probes the webhook too | The pages this template has |
| 5 | The rename engine masks upstream's demo host, `paddle-billing.vercel.app` | It spells this baseline's slug |

## Verified

- `pnpm typecheck`, `lint`, `test` (tests/web 31, tests/db 13) and `build`
  green; the Worker is 2.6 MiB gzipped (Workers Free).
- Every contract tier, the leak gate and the placement tier pass locally on
  orun v2.89.0. The e2e tier needs a PostgreSQL server (initdb, pg_ctl,
  psql) and Linux builds of Supabase Auth and PostgREST, which this build's
  machine did not have: it ran on Baseline CI, where every pull request ran
  it before it merged. Its route and webhook checks also ran here against a
  local stand-in for Supabase's API.
