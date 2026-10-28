import { createHmac } from "node:crypto";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// app/api/webhook/route.ts once the notification destination's secret is set
// (paddle-not-connected.test.ts covers the 503 before that). The signature is
// checked by the template's own verifier, the Paddle SDK's
// `webhooks.unmarshal` — HMAC-SHA256 over `ts:body`, no older than five
// seconds — with REAL signatures computed here; only the database write
// (ProcessWebhook, which uses the service-role client) is mocked.

const processEvent = vi.fn();
vi.mock("@/utils/paddle/process-webhook", () => ({
  ProcessWebhook: class {
    processEvent = processEvent;
  },
}));

const SECRET = "pdl_ntfset_test_not_a_real_secret";
const BODY = JSON.stringify({
  event_id: "evt_01",
  event_type: "customer.created",
  occurred_at: "2026-10-28T00:00:00.000Z",
  notification_id: "ntf_01",
  data: { id: "ctm_01", email: "sam@example.invalid", status: "active", custom_data: null, locale: "en",
          name: null, marketing_consent: false, created_at: "2026-10-28T00:00:00.000Z",
          updated_at: "2026-10-28T00:00:00.000Z", import_meta: null },
});
const sign = (body: string, ts: number, secret = SECRET) =>
  `ts=${ts};h1=${createHmac("sha256", secret).update(`${ts}:${body}`).digest("hex")}`;
const now = () => Math.floor(Date.now() / 1000);

async function post(body: string, signature?: string) {
  const { POST } = await import("@/app/api/webhook/route");
  const headers: Record<string, string> = { "content-type": "application/json" };
  if (signature !== undefined) headers["paddle-signature"] = signature;
  const res = await POST(new Request("https://app.example.com/api/webhook", { method: "POST", body, headers }) as never);
  return { status: res.status, body: await res.json() };
}

describe("POST /api/webhook (app/api/webhook/route.ts)", () => {
  const env = { ...process.env };
  beforeEach(() => {
    vi.resetModules();
    processEvent.mockReset();
    vi.spyOn(console, "log").mockImplementation(() => {});
    process.env.PADDLE_NOTIFICATION_WEBHOOK_SECRET = SECRET;
    // The webhook needs no API key: it never calls Paddle.
    delete process.env.PADDLE_API_KEY;
  });
  afterEach(() => {
    process.env = { ...env };
    vi.restoreAllMocks();
  });

  it("answers 400 without a Paddle-Signature header, or without a body", async () => {
    expect(await post(BODY)).toEqual({ status: 400, body: { error: "Missing signature from header" } });
    expect(await post("", sign("", now()))).toEqual({ status: 400, body: { error: "Missing signature from header" } });
    expect(processEvent).not.toHaveBeenCalled();
  });

  it("verifies a delivery Paddle signed, hands the event on, and acknowledges it", async () => {
    expect(await post(BODY, sign(BODY, now()))).toEqual({ status: 200, body: { status: 200, eventName: "customer.created" } });
    expect(processEvent).toHaveBeenCalledTimes(1);
    const event = processEvent.mock.calls[0]![0];
    expect(event.eventType).toBe("customer.created");
    expect(event.data).toMatchObject({ id: "ctm_01", email: "sam@example.invalid" });
  });

  it("refuses with 400 — never processing it — a signature that does not verify", async () => {
    const forged = [
      sign(BODY, now(), "another-secret"), // signed with a key that is not this destination's
      sign(BODY.replace("sam@", "mallory@"), now()), // a body that is not the one signed
      sign(BODY, now() - 60), // a replay: older than the five seconds the SDK allows
      `ts=${now()};h1=${"0".repeat(64)}`,
      "nonsense", // no ts or h1 at all
    ];
    for (const signature of forged) {
      expect(await post(BODY, signature)).toEqual({ status: 400, body: { error: "Invalid signature" } });
    }
    expect(processEvent).not.toHaveBeenCalled();
  });

  it("answers 500 when the verified event cannot be written, so Paddle retries it", async () => {
    processEvent.mockRejectedValue(new Error("insert or update on table subscriptions violates foreign key constraint"));
    expect(await post(BODY, sign(BODY, now()))).toEqual({ status: 500, body: { error: "Internal server error" } });
  });
});
