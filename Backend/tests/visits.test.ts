import { env } from "cloudflare:workers";
import { beforeEach, describe, expect, it } from "vitest";
import { bootstrapAll, jsonData, key, request, resetDatabase, type DevProfile } from "./helpers";

let alice: DevProfile;
let bob: DevProfile;
let charlie: DevProfile;

beforeEach(async () => {
  await resetDatabase();
  ({ alice, bob, charlie } = await bootstrapAll());
});

async function createAliceVisit() {
  return request("/v1/visits", {
    token: alice.token,
    key: key(),
    body: {
      friendshipID: alice.friends[0]!.friendshipID,
      visitorPetID: alice.petID,
      hostAccountID: bob.accountID,
      reason: "想去看看团子"
    }
  });
}

describe("Visit aggregate", () => {
  it("supports visitor-owner requests and host invitations with derived responders", async () => {
    const ownerRequest = await createAliceVisit();
    expect(ownerRequest.status).toBe(201);
    expect(await jsonData(ownerRequest)).toMatchObject({
      visitorOwnerAccountID: alice.accountID,
      hostAccountID: bob.accountID,
      requestedByAccountID: alice.accountID,
      responderAccountID: bob.accountID,
      status: "pending"
    });

    const hostInvitation = await request("/v1/visits", {
      token: alice.token,
      key: key(),
      body: {
        friendshipID: alice.friends[0]!.friendshipID,
        visitorPetID: bob.petID,
        hostAccountID: alice.accountID
      }
    });
    expect(hostInvitation.status).toBe(201);
    expect(await jsonData(hostInvitation)).toMatchObject({
      visitorOwnerAccountID: bob.accountID,
      requestedByAccountID: alice.accountID,
      responderAccountID: bob.accountID
    });
  });

  it("converges decline, requester cancellation, and expiry to explicit close reasons", async () => {
    const declined = await jsonData<{ id: string }>(await createAliceVisit());
    expect(await jsonData(await request(`/v1/visits/${declined.id}/respond`, {
      token: bob.token, key: key(), body: { response: "decline", actorType: "human" }
    }))).toMatchObject({ status: "closed", closeReason: "declined" });

    const cancelled = await jsonData<{ id: string }>(await createAliceVisit());
    expect(await jsonData(await request(`/v1/visits/${cancelled.id}/end`, {
      token: alice.token, key: key(), body: { actorType: "human" }
    }))).toMatchObject({ status: "closed", closeReason: "cancelled" });

    const expired = await jsonData<{ id: string }>(await createAliceVisit());
    await env.DB.prepare("UPDATE visits SET expires_at_ms = 0 WHERE id = ?").bind(expired.id).run();
    const expirationResponse = await request(`/v1/visits/${expired.id}/respond`, {
      token: bob.token, key: key(), body: { response: "accept", actorType: "human" }
    });
    expect(expirationResponse.status).toBe(200);
    expect(await jsonData(expirationResponse)).toMatchObject({ status: "closed", closeReason: "expired" });
  });

  it("rejects non-friends, forged resources, and the wrong responder without enumeration", async () => {
    const nonFriend = await request("/v1/visits", {
      token: charlie.token,
      key: key(),
      body: {
        friendshipID: alice.friends[0]!.friendshipID,
        visitorPetID: charlie.petID,
        hostAccountID: alice.accountID
      }
    });
    expect(nonFriend.status).toBe(404);

    const created = await createAliceVisit();
    const visit = await jsonData<{ id: string }>(created);
    const wrongResponder = await request(`/v1/visits/${visit.id}/respond`, {
      token: alice.token,
      key: key(),
      body: { response: "accept", actorType: "human" }
    });
    expect(wrongResponder.status).toBe(404);
  });

  it("replays the same idempotency key and rejects a changed payload", async () => {
    const idempotencyKey = key();
    const body = {
      friendshipID: alice.friends[0]!.friendshipID,
      visitorPetID: alice.petID,
      hostAccountID: bob.accountID,
      reason: "same"
    };
    const first = await request("/v1/visits", { token: alice.token, key: idempotencyKey, body });
    const replay = await request("/v1/visits", { token: alice.token, key: idempotencyKey, body });
    expect(replay.status).toBe(201);
    expect((await jsonData<{ id: string }>(replay)).id).toBe((await jsonData<{ id: string }>(first)).id);
    const changed = await request("/v1/visits", {
      token: alice.token,
      key: idempotencyKey,
      body: { ...body, reason: "changed" }
    });
    expect(changed.status).toBe(409);
    expect(await changed.json()).toMatchObject({ error: { code: "idempotency_key_reused" } });
  });

  it("uses the active-host unique constraint to resolve concurrent accepts", async () => {
    const secondFriendshipID = crypto.randomUUID();
    const now = Date.now();
    await env.DB.prepare(`
      INSERT INTO friendships(
        id, requester_account_id, addressee_account_id, pair_key, status,
        version, last_transition_id, created_at_ms, responded_at_ms, closed_at_ms
      ) VALUES (?, ?, ?, ?, 'accepted', 1, ?, ?, ?, NULL)
    `).bind(secondFriendshipID, charlie.accountID, bob.accountID,
      [charlie.accountID, bob.accountID].sort().join(":"), crypto.randomUUID(), now, now).run();

    const first = await jsonData<{ id: string }>(await createAliceVisit());
    const secondResponse = await request("/v1/visits", {
      token: charlie.token,
      key: key(),
      body: {
        friendshipID: secondFriendshipID,
        visitorPetID: charlie.petID,
        hostAccountID: bob.accountID
      }
    });
    const second = await jsonData<{ id: string }>(secondResponse);
    const results = await Promise.all([
      request(`/v1/visits/${first.id}/respond`, {
        token: bob.token, key: key(), body: { response: "accept", actorType: "human" }
      }),
      request(`/v1/visits/${second.id}/respond`, {
        token: bob.token, key: key(), body: { response: "accept", actorType: "human" }
      })
    ]);
    expect(results.map((response) => response.status).sort()).toEqual([200, 409]);
    const conflict = results.find((response) => response.status === 409)!;
    expect(await conflict.json()).toMatchObject({ error: { code: "host_busy" } });
    const active = await env.DB.prepare("SELECT COUNT(*) AS count FROM visits WHERE host_account_id = ? AND status = 'active'")
      .bind(bob.accountID).first<{ count: number }>();
    expect(active?.count).toBe(1);
  });

  it("converges concurrent and repeated end commands without duplicate close events", async () => {
    const created = await jsonData<{ id: string }>(await createAliceVisit());
    expect((await request(`/v1/visits/${created.id}/respond`, {
      token: bob.token, key: key(), body: { response: "accept", actorType: "human" }
    })).status).toBe(200);
    const ended = await Promise.all([
      request(`/v1/visits/${created.id}/end`, {
        token: alice.token, key: key(), body: { actorType: "human" }
      }),
      request(`/v1/visits/${created.id}/end`, {
        token: bob.token, key: key(), body: { actorType: "human" }
      })
    ]);
    expect(ended.map((response) => response.status)).toEqual([200, 200]);
    expect(await jsonData(ended[0]!)).toMatchObject({ status: "closed" });
    const count = await env.DB.prepare(`
      SELECT COUNT(*) AS count FROM account_events
      WHERE aggregate_id = ? AND type = 'visit.closed'
    `).bind(created.id).first<{ count: number }>();
    expect(count?.count).toBe(2);
  });
});
