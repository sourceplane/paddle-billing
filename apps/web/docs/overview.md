# web

Paddle's Next.js starter kit — Supabase Auth, a localized pricing page, Paddle Checkout, subscription and payment pages and the webhook that syncs customers and subscriptions (Next.js on Cloudflare Workers + Static Assets via @opennextjs/cloudflare, per environment)

A Cloudflare Worker with Static Assets (server rendering plus static files), deployed per environment by its CI lane.

|              |                                                                                                                    |
| ------------ | ------------------------------------------------------------------------------------------------------------------ |
| Type         | `cloudflare-workers-assets-turbo`                                                                                  |
| Source       | `apps/web`                                                                                                         |
| Package      | `@app/web`                                                                                                         |
| Environments | `dev`: `verify` · `stage`: `verify`, `deploy` on a push to `main` · `prod`: `verify`, `deploy` on a push to `main` |

## Depends on

- **supabase** — Provisions Supabase projects for stage and prod, points their Auth at the app (its guest sign-in included), and wires the database credentials and the app's URL and keys into orun secrets
- **db-migrate** — Applies database migrations to stage and prod Supabase instances

## Depended on by

- (none)
