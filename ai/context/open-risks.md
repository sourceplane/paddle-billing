# paddle-billing — open risks

What is not yet proven or not yet decided. The full write-up of every risk,
including the accepted ones, is
`specs/epics/paddle-billing/risks-and-open-questions.md`; this page lists
only what is still live, so it should be short.

| ID | Risk | State | What closes it |
|---|---|---|---|
| PB-A | No bootstrap has run from a tag: the supabase root's apply with the brokered token, db-migrate against a real project, the Worker-secret push and the card's sixteen minutes are unproven | OPEN | One bootstrap from `baseline-v1` against a workspace |
| PB-B | No Paddle account has been connected: Paddle.js's prices and checkout from the Worker's origin, the SDK's API calls from the Worker, and real deliveries to the webhook are proven only by the SDK's own code and signatures computed in the tests | OPEN | A Paddle sandbox connected to a live product |

Accepted, and worth knowing before you change them: PB-C (Next.js 16's
`proxy.ts` runs on the Node.js runtime, which the Cloudflare adapter calls
experimental), PB-D (the SDK compares signatures with `===`, not in constant
time), PB-E (anonymous sign-ins on by default, for the guest login), PB-F
(two Supabase projects per product), PB-G (the e2e downloads real Supabase
binaries and needs PostgreSQL, so it runs on Baseline CI).
