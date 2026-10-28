import { beforeEach, describe, expect, it, vi } from "vitest";
import { EventName } from "@paddle/paddle-node-sdk";

// utils/paddle/process-webhook.ts, upstream's: which webhook events it syncs
// into Supabase and the rows it writes — through the service-role client
// (utils/supabase/server-internal.ts, mocked here), never a visitor's session.

const upserts: { table: string; row: Record<string, unknown> }[] = [];
let failWith: { message: string } | null = null;
vi.mock("@/utils/supabase/server-internal", () => ({
  createClient: async () => ({
    from: (table: string) => ({
      upsert: (row: Record<string, unknown>) => {
        upserts.push({ table, row });
        return { select: async () => ({ error: failWith }) };
      },
    }),
  }),
}));

const subscriptionEvent = (eventType: string) =>
  ({
    eventType,
    data: {
      id: "sub_01",
      status: "active",
      customerId: "ctm_01",
      scheduledChange: { effectiveAt: "2026-11-28T00:00:00Z" },
      items: [{ price: { id: "pri_01", productId: "pro_01" } }],
    },
  }) as never;

describe("ProcessWebhook (utils/paddle/process-webhook.ts)", () => {
  beforeEach(() => {
    upserts.length = 0;
    failWith = null;
  });

  it("syncs a subscription created or updated into subscriptions", async () => {
    const { ProcessWebhook } = await import("@/utils/paddle/process-webhook");
    await new ProcessWebhook().processEvent(subscriptionEvent(EventName.SubscriptionCreated));
    await new ProcessWebhook().processEvent(subscriptionEvent(EventName.SubscriptionUpdated));
    expect(upserts).toEqual(
      Array(2).fill({
        table: "subscriptions",
        row: {
          subscription_id: "sub_01",
          subscription_status: "active",
          price_id: "pri_01",
          product_id: "pro_01",
          scheduled_change: "2026-11-28T00:00:00Z",
          customer_id: "ctm_01",
        },
      }),
    );
  });

  it("syncs a customer created or updated into customers, by email", async () => {
    const { ProcessWebhook } = await import("@/utils/paddle/process-webhook");
    for (const eventType of [EventName.CustomerCreated, EventName.CustomerUpdated]) {
      await new ProcessWebhook().processEvent({ eventType, data: { id: "ctm_01", email: "sam@example.invalid" } } as never);
    }
    expect(upserts).toEqual(Array(2).fill({ table: "customers", row: { customer_id: "ctm_01", email: "sam@example.invalid" } }));
  });

  it("ignores every other event, and throws when a write fails", async () => {
    const { ProcessWebhook } = await import("@/utils/paddle/process-webhook");
    await new ProcessWebhook().processEvent({ eventType: EventName.TransactionCompleted, data: {} } as never);
    expect(upserts).toEqual([]);
    failWith = { message: "violates foreign key constraint" };
    await expect(new ProcessWebhook().processEvent(subscriptionEvent(EventName.SubscriptionCreated))).rejects.toEqual(failWith);
  });
});
