-- Row-level security on every table in `public`, checked.
--
-- Supabase's Data API (PostgREST) serves `public` to anyone holding the
-- project's anon key, which is public by design: this app ships it to every
-- browser. So no table here may be without row-level security. The app reads
-- through that API with the visitor's session (`authenticated`) — its
-- dashboard looks up the visitor's own Paddle customer by email — and the
-- Paddle webhook's sync writes with the service-role key, which bypasses
-- RLS. Upstream's policies (010, tightened by 020) are:
--
--   customers      own row: select        (auth.jwt() ->> 'email' = email)
--   subscriptions  own rows: select       (customer_id of the visitor's own customer row)
--
-- 020 enabled RLS on both; this states the rule as its own migration (each
-- ENABLE is a no-op on an enabled table) and then CHECKS it: if any table in
-- `public` is still without row-level security, it stops here, before the
-- app that would serve it deploys. tests/db runs the same check after every
-- migration, and the e2e asks the real Data API.
--
-- Idempotent: the Supabase Management API adapter sends each statement in
-- autocommit mode, so a re-run after a partial failure must succeed.

ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscriptions ENABLE ROW LEVEL SECURITY;

DO $$
DECLARE
  open_tables text;
BEGIN
  SELECT string_agg(c.relname, ', ' ORDER BY c.relname) INTO open_tables
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p') AND NOT c.relrowsecurity;
  IF open_tables IS NOT NULL THEN
    RAISE EXCEPTION 'tables in public without row-level security, which the Data API would serve to the anon key: %', open_tables;
  END IF;
END
$$;
