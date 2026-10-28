# paddle-billing — implementation plan

Three milestones, each one reviewed pull request (PB0 is the repository's
first commit and its spec), each green before it merges.

## PB0 — the spec (PB-1)

The repository is born: `intent.yaml` with the placeholder workspace
`ws_CHANGE_ME`, `ci.yml` (byte for byte turso-starter's, with the comment
lines subscription-payments' own copy changes), the shared TypeScript and
ESLint configuration, the wiring renderer and migration helpers, the spec
index, this doc set and the task contracts.

## PB1 — the billing starter on Workers and Supabase (PB-2)

- The template in `apps/web/src` on Next.js 16.3.8: `middleware.ts` as
  `proxy.ts`, `images.unoptimized`, ESLint in eslint-config-next 16's flat
  form, the Supabase clients over the wrangler vars the build inlines.
- Paddle per call (`src/utils/paddle/config.ts`, `get-paddle-instance.ts`):
  the API client only with `PADDLE_API_KEY`, Paddle.js only with the
  client-side token; the not-connected notice on pricing, checkout and the
  dashboard; the webhook's 503, its 400 for a signature that does not verify.
- `src/utils/site.ts` (the name seam and the origin), the GitHub sign-in's
  return address from it, `src/app/api/health/route.ts`.
- `wrangler.template.jsonc` + `wiring.fixture.json`, `component.yaml` (the
  four Paddle values as optional secrets, the server-side two pushed by
  `tooling/wire/secrets.mjs --optional-env`, the smoke).
- `packages/db`: `010_paddle_initialize`, `020_restrict_read_policies`
  (upstream's), `030_row_level_security`; the Supabase root (anonymous
  sign-ins on); `infra/db-migrate`.
- `tests/web` (the name and origin, the health check, Paddle not connected,
  the webhook's verification with real signatures, its sync, the wrangler
  config and the Worker secrets) and `tests/db` (the manifest, upstream's
  migrations byte for byte, row-level security, on PGlite).

## PB2 — a baseline (PB-3)

subscription-payments' machinery on this tree: `blueprint.yaml`,
`repo-blueprint.yaml` (four brokered keys), `.baseline/` (identity — the name
seam is upstream's AeroEdit — the product's README with "Connecting Paddle",
task contracts), the rename engine (upstream's demo host, which spells this
slug, masked), the bootstrap helpers, the record renderer (probing `/`,
`/api/health` and the webhook), `docs/phases/`, the context pack, and
`testing/` — the leak and placement gates (Paddle's refs optional in the
product's own plan), and the e2e tier that migrates the stage database
through a stand-in Supabase Management API under the real Supabase Auth and
Data API, then serves the built Worker over it: every route with Paddle not
connected, a sign-up, sign-out, sign-in and a guest, then signed webhook
deliveries synced and forged ones refused, and the Data API's roles held to
the policies.
