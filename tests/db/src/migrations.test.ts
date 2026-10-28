import { describe, expect, it } from "vitest";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import * as path from "node:path";
import { manifest } from "@saas/db/manifest";
import { buildPlan, runMigrations } from "@saas/db/runner";

const migrationsDir = path.resolve(__dirname, "../../../packages/db/src/migrations");

describe("the migration manifest (packages/db)", () => {
  it("starts with the control migration and names every file with its checksum", () => {
    expect(manifest.migrations[0]?.id).toBe("000_control_baseline");
    for (const entry of manifest.migrations) {
      const file = readFileSync(path.join(migrationsDir, entry.path));
      expect(createHash("sha256").update(file).digest("hex"), entry.id).toBe(entry.checksum);
    }
  });

  it("plans every migration as pending offline", async () => {
    const result = await runMigrations(manifest, { mode: "plan", migrationsDir, adapter: null });
    expect(result.failed).toBeNull();
    expect(result.applied).toEqual(manifest.migrations.map((m) => m.id));
  });

  it("re-enables row-level security, by name, on every table 010 creates", () => {
    const init = readFileSync(path.join(migrationsDir, "010_paddle_initialize/up.sql"), "utf8");
    const rls = readFileSync(path.join(migrationsDir, "030_row_level_security/up.sql"), "utf8");
    const created = [...init.matchAll(/^\s*public\.(\w+) \(/gim)].map((m) => m[1]);
    expect(created).toEqual(["customers", "subscriptions"]);
    for (const table of created) {
      expect(rls, table).toContain(`ALTER TABLE public.${table} ENABLE ROW LEVEL SECURITY;`);
    }
    expect(rls).toMatch(/RAISE EXCEPTION 'tables in public without row-level security/);
  });

  it("carries upstream's two migrations byte for byte, in upstream's order", () => {
    const upstream = path.resolve(__dirname, "../../../apps/web/supabase/migrations");
    expect(readFileSync(path.join(migrationsDir, "010_paddle_initialize/up.sql"), "utf8")).toBe(
      readFileSync(path.join(upstream, "20240907140223_initialize.sql"), "utf8"),
    );
    expect(readFileSync(path.join(migrationsDir, "020_restrict_read_policies/up.sql"), "utf8")).toBe(
      readFileSync(path.join(upstream, "20260721000000_restrict_read_policies.sql"), "utf8"),
    );
  });

  it("skips what the database already recorded", () => {
    const applied = new Map([[manifest.migrations[0]!.id, manifest.migrations[0]!.checksum]]);
    const plan = buildPlan(manifest, applied, migrationsDir);
    expect(plan.alreadyApplied).toEqual([manifest.migrations[0]!.id]);
    expect(plan.pending.map((m) => m.id)).toEqual(manifest.migrations.slice(1).map((m) => m.id));
    expect(plan.checksumMismatches).toEqual([]);
  });
});
