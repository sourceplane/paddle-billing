import { beforeAll, describe, expect, it } from "vitest";
import { PGlite } from "@electric-sql/pglite";
import { readFileSync } from "node:fs";
import * as path from "node:path";
import { manifest } from "@saas/db/manifest";

// Supabase's Data API (PostgREST) serves the `public` schema to anyone holding
// the project's anon key — and this app ships that key to every browser. So
// every table in `public` must have row-level security, and the policies must
// let the app's own flows through and nobody else's: a signed-in visitor
// reads their own Paddle customer row (matched by their email) and its
// subscriptions, never another's; the anon key reads nothing; the webhook's
// sync (the service role) writes everything. These run every migration
// db-migrate applies, in the manifest's order, on a real Postgres in process
// (PGlite: Postgres compiled to WASM), over the slice of Supabase's `auth`
// schema the policies read, and read the catalog — and the rows — they leave.
const migrationsDir = path.resolve(__dirname, "../../../packages/db/src/migrations");
const sqlOf = (rel: string) => readFileSync(path.join(migrationsDir, rel), "utf8");

// What a Supabase project has before the first migration: `auth.jwt()` and
// `auth.uid()` read from the request's JWT claims as PostgREST sets them, and
// the Data API's roles with the grants Supabase gives them on `public` — so
// a refusal below is row-level security's, not a missing grant's.
// `service_role` bypasses RLS, as it does on Supabase.
const SUPABASE = `
  create schema auth;
  create function auth.jwt() returns jsonb language sql stable as $$
    select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb
  $$;
  create function auth.uid() returns uuid language sql stable as $$
    select (auth.jwt() ->> 'sub')::uuid
  $$;
  create role anon nologin;
  create role authenticated nologin;
  create role service_role nologin bypassrls;
  grant usage on schema public, auth to anon, authenticated, service_role;
  grant execute on all functions in schema auth to anon, authenticated, service_role;
  alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
`;

async function migrated(upTo?: string): Promise<PGlite> {
  const db = new PGlite();
  await db.exec(SUPABASE);
  for (const entry of manifest.migrations) {
    if (upTo && entry.id >= upTo) break;
    await db.exec(sqlOf(entry.path));
  }
  return db;
}

type Rel = { relname: string; relrowsecurity: boolean; relforcerowsecurity: boolean };
const PUBLIC_TABLES = `
  select c.relname, c.relrowsecurity, c.relforcerowsecurity
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind in ('r', 'p')
   order by c.relname`;

const ALICE = { sub: "00000000-0000-4000-8000-00000000a11c", email: "alice@example.invalid" };
const BOB = { sub: "00000000-0000-4000-8000-000000000b0b", email: "bob@example.invalid" };

async function as<T>(db: PGlite, role: string, who: { sub: string; email: string } | null, run: () => Promise<T>): Promise<T> {
  await db.exec(`set role ${role}`);
  await db.query("select set_config('request.jwt.claims', $1, false)", [who ? JSON.stringify({ ...who, role }) : ""]);
  try {
    return await run();
  } finally {
    await db.exec("reset role");
    await db.query("select set_config('request.jwt.claims', '', false)");
  }
}
const count = async (db: PGlite, table: string) =>
  (await db.query<{ n: number }>(`select count(*)::int as n from ${table}`)).rows[0]!.n;
const ids = async (db: PGlite, sql: string) => (await db.query<{ id: string }>(sql)).rows.map((r) => r.id);

describe("row-level security on public (after every migration)", () => {
  let db: PGlite;
  beforeAll(async () => {
    db = await migrated();
    // Paddle's webhook syncs two customers and a subscription each — written
    // as the tables' owner, as the migrations and the service role would.
    await db.exec(`
      insert into customers (customer_id, email) values
        ('ctm_alice', '${ALICE.email}'), ('ctm_bob', '${BOB.email}');
      insert into subscriptions (subscription_id, subscription_status, price_id, product_id, customer_id) values
        ('sub_alice', 'active', 'pri_1', 'pro_1', 'ctm_alice'), ('sub_bob', 'active', 'pri_1', 'pro_1', 'ctm_bob');`);
  }, 60_000);

  it("leaves no table in public without row-level security", async () => {
    const { rows } = await db.query<Rel>(PUBLIC_TABLES);
    // Not vacuous: the template's two tables are there.
    expect(rows.map((r) => r.relname)).toEqual(["customers", "subscriptions"]);
    expect(rows.filter((r) => !r.relrowsecurity).map((r) => r.relname)).toEqual([]);
    expect(rows.filter((r) => r.relforcerowsecurity).map((r) => r.relname)).toEqual([]);
  });

  it("keeps upstream's own-row read policies — and not the permissive ones 020 replaced", async () => {
    const { rows } = await db.query<{ tablename: string; policyname: string; cmd: string; roles: string }>(
      "select tablename, policyname, cmd, roles::text from pg_policies where schemaname = 'public' order by tablename",
    );
    expect(rows).toEqual([
      { tablename: "customers", policyname: "Enable users to read their own customer record", cmd: "SELECT", roles: "{authenticated}" },
      { tablename: "subscriptions", policyname: "Enable users to read their own subscriptions", cmd: "SELECT", roles: "{authenticated}" },
    ]);
  });

  it("gives the anon key nothing to read and nothing to write", async () => {
    await as(db, "anon", null, async () => {
      expect(await count(db, "customers")).toBe(0);
      expect(await count(db, "subscriptions")).toBe(0);
      await expect(db.exec("insert into customers (customer_id, email) values ('ctm_x', 'x@example.invalid')")).rejects.toThrow(
        /row-level security/,
      );
    });
  });

  it("gives a signed-in user their own customer row and its subscriptions, never another's", async () => {
    await as(db, "authenticated", ALICE, async () => {
      expect(await ids(db, "select customer_id as id from customers")).toEqual(["ctm_alice"]);
      expect(await ids(db, "select subscription_id as id from subscriptions")).toEqual(["sub_alice"]);
      // The dashboard's own query (utils/paddle/get-customer-id.ts): by email.
      expect(await ids(db, `select customer_id as id from customers where email = '${BOB.email}'`)).toEqual([]);
      // Read-only: the webhook's sync is the one writer.
      await expect(
        db.exec(`insert into customers (customer_id, email) values ('ctm_mallory', '${ALICE.email}')`),
      ).rejects.toThrow(/row-level security/);
      await db.exec(`update subscriptions set subscription_status = 'canceled'`);
    });
    // The update matched no row it may see for writing: nothing changed.
    expect(await ids(db, "select subscription_id as id from subscriptions where subscription_status = 'active' order by 1")).toEqual([
      "sub_alice",
      "sub_bob",
    ]);
    await as(db, "authenticated", BOB, async () => {
      expect(await ids(db, "select subscription_id as id from subscriptions")).toEqual(["sub_bob"]);
    });
  });

  it("lets the service role — the webhook's sync — read and write everything", async () => {
    await as(db, "service_role", null, async () => {
      expect(await count(db, "customers")).toBe(2);
      expect(await count(db, "subscriptions")).toBe(2);
      await db.exec(`insert into customers (customer_id, email) values ('ctm_carol', 'carol@example.invalid')
                     on conflict (customer_id) do update set email = excluded.email`);
    });
    expect(await count(db, "customers")).toBe(3);
  });
});

describe("migration 030's check", () => {
  it("refuses a table in public without row-level security, naming it", async () => {
    const db = await migrated("030");
    await db.exec("create table public.notes (id serial primary key, body text)");
    await expect(db.exec(sqlOf("030_row_level_security/up.sql"))).rejects.toThrow(/without row-level security.*notes/);
  }, 60_000);

  it("passes on upstream's schema, and again on a second run", async () => {
    const db = await migrated("030");
    await db.exec(sqlOf("030_row_level_security/up.sql"));
    await db.exec(sqlOf("030_row_level_security/up.sql"));
    const { rows } = await db.query<Rel>(PUBLIC_TABLES);
    expect(rows.every((r) => r.relrowsecurity)).toBe(true);
  }, 60_000);

  it("is what closes upstream's first migration: 010 alone leaves both tables without row-level security", async () => {
    const db = await migrated("020");
    const { rows } = await db.query<Rel>(PUBLIC_TABLES);
    expect(rows.filter((r) => !r.relrowsecurity).map((r) => r.relname)).toEqual(["customers", "subscriptions"]);
    await db.exec(sqlOf("030_row_level_security/up.sql"));
    expect((await db.query<Rel>(PUBLIC_TABLES)).rows.every((r) => r.relrowsecurity)).toBe(true);
  }, 60_000);
});
