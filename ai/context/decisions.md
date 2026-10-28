# paddle-billing — decisions

The choices that shape this repository, one line each, with where the full
reasoning lives.

| # | Decision | Why | Source |
|---|---|---|---|
| 1 | subscription-payments' machinery (Supabase through its API, one wiring document, db-migrate through the Management API, the supabase root), the template's code in `apps/web/src` | The same shape as the Stripe starter: Supabase Auth and Postgres per environment, a billing provider the owner connects | design.md §1 |
| 2 | Next.js 15.5 → 16.3.8; `middleware.ts` → `proxy.ts` (Node.js runtime) | The Cloudflare adapter (1.20.11) refuses Next.js 15.5 as past its support window; 16.3.8 is the newest it builds, and Next.js 16 renamed the middleware | design.md §2, risk PB-C |
| 3 | Paddle's four values are the product's own optional Orun secrets under upstream's names: the server-side two pushed to the Worker as Worker secrets by every deploy (`secrets.mjs --optional-env`), the public two inlined by the build | Secrets are Orun's, never committed or hand-set on the Worker; a server-side key never enters a bundle; the client-side token is public by design | design.md §3 |
| 4 | Paddle is optional: with no key the app builds, deploys and serves — the plans without prices and a notice, checkout and the dashboard's Paddle views saying Paddle is not connected without calling it, the webhook 503 | The platform brokers no Paddle connection, so a fresh product must come up without one | design.md §4 |
| 5 | The webhook verifies with the Paddle SDK's own `webhooks.unmarshal` (HMAC-SHA256 over `ts:body`, five-second window), which runs on Workers; a signature that does not verify answers 400 (upstream: 500) | The template's code works on Workers as it is; a forged delivery is the sender's fault, not a retryable error | design.md §5, risk PB-D |
| 6 | The schema is upstream's two migrations byte for byte (`010`, `020`), then `030` re-enables and checks row-level security on every table in `public` | Upstream's first migration creates both tables without RLS; the second fixes it; the check keeps it fixed | design.md §6 |
| 7 | The supabase root turns anonymous sign-ins on (`authAnonymousSignIns`) | The template's log-in page offers "Log in as Guest" | design.md §7, risk PB-E |
| 8 | No Hyperdrive | The app speaks PostgREST over HTTPS, never a Postgres socket | design.md §1 |
| 9 | Images unoptimized; the logo and icons kept as the template ships them | Workers has no Next.js image optimizer; the marks are images, the name is text (`SITE_NAME`) | IMPLEMENTATION-STATUS |
| 10 | One landing (`01-product`) then the record (`02-docs`); supabase → db-migrate → web enforced on main, advisory on a pull request; stack-tectonic 0.19.0 | subscription-payments' build, proven | `repo-blueprint.yaml`, `intent.yaml` |
| 11 | `subdomain` is read from the Cloudflare connection, never asked; the console asks for no domain | It belongs to the account and has one right answer; a domain is an owner's step after the build | `blueprint.yaml`, `repo-blueprint.yaml` |
