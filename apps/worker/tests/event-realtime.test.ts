import { env } from "cloudflare:workers";
import { beforeEach, describe, expect, it } from "vitest";
import { accountEventStatement } from "../src/storage/events-repository";
import { bootstrapAll, jsonData, key, request, resetDatabase, type DevProfile } from "./helpers";

let alice: DevProfile;
let bob: DevProfile;

beforeEach(async () => {
  await resetDatabase();
  ({ alice, bob } = await bootstrapAll());
});

describe("account event synchronization", () => {
  it("writes an independent monotonically ordered event copy per recipient", async () => {
    const created = await request("/v1/visits", {
      token: alice.token,
      key: key(),
      body: {
        friendshipID: alice.friends[0]!.friendshipID,
        visitorPetID: alice.petID,
        hostAccountID: bob.accountID
      }
    });
    expect(created.status).toBe(201);
    const alicePage = await jsonData<{ events: Array<{ id: string; sequence: number; recipientAccountID: string }>; nextCursor: number }>(
      await request("/v1/events?after=0&limit=1", { token: alice.token })
    );
    const bobPage = await jsonData<typeof alicePage>(
      await request("/v1/events?after=0&limit=100", { token: bob.token })
    );
    expect(alicePage.events).toHaveLength(1);
    expect(bobPage.events).toHaveLength(1);
    expect(alicePage.events[0]!.recipientAccountID).toBe(alice.accountID);
    expect(bobPage.events[0]!.recipientAccountID).toBe(bob.accountID);
    expect(alicePage.events[0]!.id).not.toBe(bobPage.events[0]!.id);

    const after = await jsonData<{ events: unknown[]; nextCursor: number }>(
      await request(`/v1/events?after=${alicePage.nextCursor}&limit=100`, { token: alice.token })
    );
    expect(after.events).toHaveLength(0);
    expect(after.nextCursor).toBe(alicePage.nextCursor);
  });

  it("closes the bootstrap window by fetching events after the atomic cursor", async () => {
    const bootstrap = await jsonData<{ cursor: number }>(
      await request("/v1/sync/bootstrap", { token: alice.token })
    );
    await request("/v1/visits", {
      token: alice.token,
      key: key(),
      body: {
        friendshipID: alice.friends[0]!.friendshipID,
        visitorPetID: alice.petID,
        hostAccountID: bob.accountID
      }
    });
    const catchUp = await jsonData<{ events: Array<{ type: string }> }>(
      await request(`/v1/events?after=${bootstrap.cursor}`, { token: alice.token })
    );
    expect(catchUp.events.map((event) => event.type)).toContain("visit.requested");
  });

  it("paginates a large recipient stream without requiring contiguous global sequences", async () => {
    const now = Date.now();
    const statements = Array.from({ length: 105 }, (_, index) => accountEventStatement(env.DB, {
      recipientAccountID: alice.accountID,
      type: "test.page",
      aggregateType: "test",
      aggregateID: `page-${index}`,
      aggregateVersion: 1,
      payload: { index },
      timelineVisible: index % 2 === 0,
      occurredAt: now + index
    }));
    await env.DB.batch(statements.slice(0, 100));
    await env.DB.batch(statements.slice(100));

    const first = await jsonData<{ events: Array<{ sequence: number }>; nextCursor: number }>(
      await request("/v1/events?after=0&limit=100", { token: alice.token })
    );
    const second = await jsonData<typeof first>(
      await request(`/v1/events?after=${first.nextCursor}&limit=100`, { token: alice.token })
    );
    expect(first.events).toHaveLength(100);
    expect(second.events).toHaveLength(5);
    const sequences = [...first.events, ...second.events].map((event) => event.sequence);
    expect(sequences).toEqual([...sequences].sort((left, right) => left - right));
    expect(new Set(sequences).size).toBe(105);
  });
});

async function connect(stub: DurableObjectStub, deviceID: string): Promise<{ socket: WebSocket; messages: string[] }> {
  const response = await stub.fetch(new Request("https://hub.test/socket", {
    headers: { upgrade: "websocket", "x-mino-device-id": deviceID }
  }));
  expect(response.status).toBe(101);
  const socket = response.webSocket!;
  const messages: string[] = [];
  const ready = new Promise<void>((resolve) => {
    socket.addEventListener("message", (event) => {
      messages.push(String(event.data));
      if (String(event.data).includes("ready")) resolve();
    });
  });
  socket.accept();
  await ready;
  return { socket, messages };
}

describe("AccountRealtimeHub", () => {
  it("broadcasts duplicate-safe hints to all devices of one account and isolates accounts", async () => {
    const aliceStub = env.ACCOUNT_REALTIME.get(env.ACCOUNT_REALTIME.idFromName(alice.accountID));
    const bobStub = env.ACCOUNT_REALTIME.get(env.ACCOUNT_REALTIME.idFromName(bob.accountID));
    const first = await connect(aliceStub, alice.deviceID);
    const second = await connect(aliceStub, crypto.randomUUID());
    const isolated = await connect(bobStub, bob.deviceID);

    await aliceStub.notify();
    await aliceStub.notify();
    await new Promise((resolve) => setTimeout(resolve, 10));
    expect(first.messages.filter((message) => message.includes("events_available"))).toHaveLength(2);
    expect(second.messages.filter((message) => message.includes("events_available"))).toHaveLength(2);
    expect(isolated.messages.some((message) => message.includes("events_available"))).toBe(false);

    first.socket.close(1000, "done");
    second.socket.close(1000, "done");
    isolated.socket.close(1000, "done");
  });

  it("does not accept realtime identity from query parameters", async () => {
    const unauthenticated = await request(`/v1/realtime?accountID=${bob.accountID}`);
    expect(unauthenticated.status).toBe(401);
  });
});
