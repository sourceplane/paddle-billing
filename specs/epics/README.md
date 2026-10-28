# Epics

Orun-style work programs. Each epic is a folder carrying `epic.yaml` (the
declaration the platform reads: slug, key prefix, milestones with exit
criteria and task keys) beside its doc set. The pull request that adds the
folder is the adoption; the merge creates the epic in the workspace.

| Epic | Cluster | Status | What it is |
|------|---------|--------|------------|
| [`paddle-billing/`](./paddle-billing/) | **PB** | ✅ Shipped (`baseline-v1`); not yet live | Paddle's Next.js starter kit — localized pricing, Paddle Checkout, Supabase Auth with a guest login, a billing dashboard and the webhook — on Cloudflare Workers with a Supabase project per environment, and an Orun baseline that instantiates it in one landing (PB2) |

As-built ≠ intent: what shipped lives in each epic's `IMPLEMENTATION-STATUS.md`.
