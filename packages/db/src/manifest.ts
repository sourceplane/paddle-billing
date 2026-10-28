import type { MigrationManifest } from "./types.js";

// Every migration the runner applies, in order, with the sha256 of its file.
// `pnpm --filter @saas/db run manifest:check` verifies the checksums;
// `manifest:fix` rewrites them after a migration file changes (only ever
// before that migration has been applied anywhere — an applied migration's
// checksum is immutable).
export const manifest: MigrationManifest = {
  version: 1,
  migrations: [
    {
      id: "000_control_baseline",
      context: "control",
      path: "000_control/up.sql",
      checksum:
        "2a5d7f30684c99e3ff441ca8a2c38038dedd1bab4db4a40e92cd36bb22be297f",
      description:
        "Baseline control migration — creates the migration tracking schema",
    },
    {
      id: "010_paddle_initialize",
      context: "app",
      path: "010_paddle_initialize/up.sql",
      checksum:
        "21405a999514b53917cfdcd5aa83042fc4c8df972411fd9d50572780fab851e0",
      description:
        "The template's schema (supabase/migrations/20240907140223_initialize.sql, verbatim): customers (Paddle customer id to email) and subscriptions, with read policies for signed-in users",
    },
    {
      id: "020_restrict_read_policies",
      context: "app",
      path: "020_restrict_read_policies/up.sql",
      checksum:
        "167e5d966971bf50b1ccedae427c1056de7f30c34af64a136b23fe09524e7a95",
      description:
        "The template's second migration (supabase/migrations/20260721000000_restrict_read_policies.sql, verbatim): row-level security on, and each signed-in user reads only their own customer row and its subscriptions",
    },
    {
      id: "030_row_level_security",
      context: "app",
      path: "030_row_level_security/up.sql",
      checksum:
        "af9768a0949f7167ee43f039f05b2145ba8da7d9df27bc50aad9eacd0b6af565",
      description:
        "Row-level security on every table in public, upstream's policies kept (010 and 020 wrote them): re-enabled by name, then checked — the migration stops if any table in public is left without it",
    },
  ],
};
