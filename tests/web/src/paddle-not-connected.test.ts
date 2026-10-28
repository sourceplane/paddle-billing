import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// Before the owner connects Paddle (README, "Connecting Paddle") the app has
// no Paddle key at all — and must still serve: no Paddle client is built,
// the dashboard's Paddle reads answer "Paddle is not connected." without a
// network call, and the webhook answers 503. The Supabase server client is
// mocked (a signed-in visitor with a Paddle customer row), so the only thing
// between these calls and Paddle's API is the connection check.

vi.mock("@/utils/supabase/server", () => ({
  createClient: async () => ({
    auth: {
      getUser: async () => ({ data: { user: { id: "u1", email: "sam@example.invalid" } } }),
      getSession: async () => ({ data: { session: { access_token: "t" } } }),
    },
    from: () => ({
      select: () => ({ eq: () => ({ single: async () => ({ data: { customer_id: "ctm_sam", email: "sam@example.invalid" } }) }) }),
    }),
  }),
  validateUserSession: async () => {},
}));
vi.mock("next/cache", () => ({ revalidatePath: vi.fn() }));

const NOT_CONNECTED = "Paddle is not connected.";
const PADDLE_ENV = ["PADDLE_API_KEY", "PADDLE_NOTIFICATION_WEBHOOK_SECRET", "NEXT_PUBLIC_PADDLE_CLIENT_TOKEN", "NEXT_PUBLIC_PADDLE_ENV"];

describe("the app with Paddle not connected", () => {
  const env = { ...process.env };
  const fetchMock = vi.fn(async () => {
    throw new Error("no network in this test");
  });
  beforeEach(() => {
    vi.resetModules();
    for (const k of PADDLE_ENV) delete process.env[k];
    fetchMock.mockClear();
    vi.stubGlobal("fetch", fetchMock);
  });
  afterEach(() => {
    process.env = { ...env };
    vi.unstubAllGlobals();
  });

  it("has no Paddle key, no client-side config, and the sandbox as its environment", async () => {
    const config = await import("@/utils/paddle/config");
    expect(config.PADDLE_NOT_CONNECTED).toBe(NOT_CONNECTED);
    expect(config.isPaddleConnected()).toBe(false);
    expect(config.paddleClientConfig()).toBeUndefined();
    expect(config.paddleEnvironment()).toBe("sandbox");
    // A blank line in .dev.vars is no key either.
    process.env.PADDLE_API_KEY = "  ";
    process.env.NEXT_PUBLIC_PADDLE_CLIENT_TOKEN = "";
    expect(config.isPaddleConnected()).toBe(false);
    expect(config.paddleClientConfig()).toBeUndefined();
  });

  it("builds no Paddle client without the API key", async () => {
    const { getPaddleInstance } = await import("@/utils/paddle/get-paddle-instance");
    expect(() => getPaddleInstance()).toThrow(/Paddle is not connected\. PADDLE_API_KEY is not set\./);
  });

  it("answers every dashboard read and the cancel action with the notice, calling nobody", async () => {
    const { getSubscriptions } = await import("@/utils/paddle/get-subscriptions");
    const { getSubscription } = await import("@/utils/paddle/get-subscription");
    const { getTransactions } = await import("@/utils/paddle/get-transactions");
    const { cancelSubscription } = await import("@/app/dashboard/subscriptions/actions");
    expect(await getSubscriptions()).toEqual({ error: NOT_CONNECTED, data: [], hasMore: false, totalRecords: 0 });
    expect(await getSubscription("sub_1")).toEqual({ error: NOT_CONNECTED });
    expect(await getTransactions("sub_1", "")).toEqual({ error: NOT_CONNECTED, data: [], hasMore: false, totalRecords: 0 });
    expect(await cancelSubscription("sub_1")).toEqual({ error: NOT_CONNECTED });
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("answers the webhook 503 'Paddle is not connected.' until its secret is set", async () => {
    const { POST } = await import("@/app/api/webhook/route");
    const res = await POST(
      new Request("https://app.example.com/api/webhook", {
        method: "POST",
        body: '{"event_type":"customer.created"}',
        headers: { "paddle-signature": "ts=1;h1=abc" },
      }) as never,
    );
    expect(res.status).toBe(503);
    expect(await res.json()).toEqual({ error: NOT_CONNECTED });
  });

  it("connects with the owner's keys: the API key for the server, the token and environment for the browser", async () => {
    process.env.PADDLE_API_KEY = "pdl_sdbx_apikey_not_a_real_key";
    process.env.NEXT_PUBLIC_PADDLE_CLIENT_TOKEN = "test_not_a_real_token";
    process.env.NEXT_PUBLIC_PADDLE_ENV = "production";
    const config = await import("@/utils/paddle/config");
    expect(config.isPaddleConnected()).toBe(true);
    expect(config.paddleClientConfig()).toEqual({ token: "test_not_a_real_token", environment: "production" });
    const { getPaddleInstance } = await import("@/utils/paddle/get-paddle-instance");
    expect(getPaddleInstance()).toBeDefined();
  });
});
