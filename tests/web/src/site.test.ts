import { readFileSync } from "node:fs";
import * as path from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// The product's name and origin. The name is ONE literal line, so a product
// is renamed by changing it (and was named by it when it was born); the
// origin is what each deploy's build inlines, and the GitHub sign-in returns
// there (upstream hard-coded its demo's).

const signInWithOAuth = vi.fn(async () => ({ data: { url: "https://ref.supabase.co/auth/v1/authorize?provider=github" } }));
vi.mock("@/utils/supabase/server", () => ({ createClient: async () => ({ auth: { signInWithOAuth } }) }));
vi.mock("next/cache", () => ({ revalidatePath: vi.fn() }));

describe("the product's name and origin", () => {
  const env = { ...process.env };
  beforeEach(() => {
    vi.resetModules();
    signInWithOAuth.mockClear();
  });
  afterEach(() => {
    process.env = { ...env };
  });

  it("names the product on one literal line, and exports it as written", async () => {
    const site = readFileSync(path.resolve(__dirname, "../../../apps/web/src/utils/site.ts"), "utf8");
    // Not spelled here: the line is the product's, whatever its name.
    const lines = site.match(/^export const SITE_NAME = (".+")$/gm) ?? [];
    expect(lines).toHaveLength(1);
    const { SITE_NAME } = await import("@/utils/site");
    expect(JSON.stringify(SITE_NAME)).toBe(lines[0]!.slice("export const SITE_NAME = ".length));
  });

  it("reads its origin from NEXT_PUBLIC_SITE_URL, without a trailing slash, and localhost in `next dev`", async () => {
    const { siteUrl } = await import("@/utils/site");
    delete process.env.NEXT_PUBLIC_SITE_URL;
    expect(siteUrl()).toBe("http://localhost:3000");
    process.env.NEXT_PUBLIC_SITE_URL = "https://acme-web-stage.acme.workers.dev/";
    expect(siteUrl()).toBe("https://acme-web-stage.acme.workers.dev");
  });

  it("sends the GitHub sign-in back to this site's own /auth/callback", async () => {
    process.env.NEXT_PUBLIC_SITE_URL = "https://acme-web-prod.acme.workers.dev";
    const { signInWithGithub } = await import("@/app/login/actions");
    // Next's redirect() throws; its digest carries where to.
    await expect(signInWithGithub()).rejects.toMatchObject({
      digest: expect.stringContaining("https://ref.supabase.co/auth/v1/authorize?provider=github"),
    });
    expect(signInWithOAuth).toHaveBeenCalledWith({
      provider: "github",
      options: { redirectTo: "https://acme-web-prod.acme.workers.dev/auth/callback" },
    });
  });
});
