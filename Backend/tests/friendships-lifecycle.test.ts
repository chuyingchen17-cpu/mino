import { env } from "cloudflare:workers";
import { beforeEach, describe, expect, it } from "vitest";
import { issueSession } from "../src/storage/accounts-repository";
import { bootstrapAll, jsonData, key, request, resetDatabase, type DevProfile } from "./helpers";

let alice: DevProfile;
let bob: DevProfile;
let charlie: DevProfile;

beforeEach(async () => {
  await resetDatabase();
  ({ alice, bob, charlie } = await bootstrapAll());
});

async function requestAndAcceptFriendship(requester: DevProfile, addressee: DevProfile) {
  const created = await request("/v1/friendships", {
    token: requester.token,
    key: key(),
    body: { addresseeAccountID: addressee.accountID }
  });
  const friendship = await jsonData<{ id: string }>(created);
  const accepted = await request(`/v1/friendships/${friendship.id}/respond`, {
    token: addressee.token,
    key: key(),
    body: { response: "accept" }
  });
  expect(accepted.status).toBe(200);
  return friendship.id;
}

describe("friendship lifecycle", () => {
  it("blocks pending friendships, then accepts and closes every open Visit atomically", async () => {
    const pending = await request("/v1/friendships", {
      token: charlie.token,
      key: key(),
      body: { addresseeAccountID: alice.accountID }
    });
    const friendship = await jsonData<{ id: string }>(pending);
    const blocked = await request("/v1/visits", {
      token: charlie.token,
      key: key(),
      body: {
        friendshipID: friendship.id,
        visitorPetID: charlie.petID,
        hostAccountID: alice.accountID
      }
    });
    expect(blocked.status).toBe(404);

    expect((await request(`/v1/friendships/${friendship.id}/respond`, {
      token: alice.token,
      key: key(),
      body: { response: "accept" }
    })).status).toBe(200);
    const created = await request("/v1/visits", {
      token: charlie.token,
      key: key(),
      body: {
        friendshipID: friendship.id,
        visitorPetID: charlie.petID,
        hostAccountID: alice.accountID
      }
    });
    const visit = await jsonData<{ id: string }>(created);
    expect((await request(`/v1/visits/${visit.id}/respond`, {
      token: alice.token,
      key: key(),
      body: { response: "accept", actorType: "human" }
    })).status).toBe(200);
    const letter = await jsonData<{ id: string }>(await request(`/v1/visits/${visit.id}/letters`, {
      token: alice.token,
      key: key(),
      body: { body: "友情关闭也必须可靠交付" }
    }));

    const closed = await request(`/v1/friendships/${friendship.id}/close`, {
      method: "POST",
      token: charlie.token,
      key: key()
    });
    expect(closed.status).toBe(200);
    const persisted = await env.DB.prepare("SELECT status, close_reason FROM visits WHERE id = ?")
      .bind(visit.id).first<{ status: string; close_reason: string }>();
    expect(persisted).toEqual({ status: "closed", close_reason: "friendship_closed" });
    expect(await jsonData(await request(`/v1/letters/${letter.id}`, { token: charlie.token })))
      .toMatchObject({ status: "delivered", body: "友情关闭也必须可靠交付" });
    const deliveryCount = await env.DB.prepare(`
      SELECT COUNT(*) AS count FROM account_events
      WHERE type = 'letter.delivered' AND aggregate_id = ?
    `).bind(letter.id).first<{ count: number }>();
    expect(deliveryCount?.count).toBe(1);
    expect((await request(`/v1/visits/${visit.id}/actions`, {
      token: alice.token,
      key: key(),
      body: { kind: "feed", actorType: "human", payload: {} }
    })).status).not.toBe(201);
  });

  it("allows multiple pending destinations but only one active Visit per visitor", async () => {
    const aliceCharlie = await requestAndAcceptFriendship(alice, charlie);
    const bobPending = await request("/v1/visits", {
      token: alice.token,
      key: key(),
      body: {
        friendshipID: alice.friends[0]!.friendshipID,
        visitorPetID: alice.petID,
        hostAccountID: bob.accountID
      }
    });
    const charliePending = await request("/v1/visits", {
      token: alice.token,
      key: key(),
      body: {
        friendshipID: aliceCharlie,
        visitorPetID: alice.petID,
        hostAccountID: charlie.accountID
      }
    });
    const bobVisit = await jsonData<{ id: string }>(bobPending);
    const charlieVisit = await jsonData<{ id: string }>(charliePending);
    expect((await request(`/v1/visits/${bobVisit.id}/respond`, {
      token: bob.token, key: key(), body: { response: "accept", actorType: "human" }
    })).status).toBe(200);
    const conflict = await request(`/v1/visits/${charlieVisit.id}/respond`, {
      token: charlie.token, key: key(), body: { response: "accept", actorType: "human" }
    });
    expect(conflict.status).toBe(409);
    expect(await conflict.json()).toMatchObject({ error: { code: "visitor_busy" } });
  });

  it("allows the primary Agent responder and rejects a secondary device", async () => {
    const secondary = await issueSession(env.DB, env.SESSION_TOKEN_PEPPER, bob.accountID, {
      displayName: "Bob secondary",
      platform: "macos",
      appVersion: "test"
    });
    const first = await jsonData<{ id: string }>(await request("/v1/visits", {
      token: alice.token,
      key: key(),
      body: {
        friendshipID: alice.friends[0]!.friendshipID,
        visitorPetID: alice.petID,
        hostAccountID: bob.accountID
      }
    }));
    const rejected = await request(`/v1/visits/${first.id}/respond`, {
      token: secondary.accessToken,
      key: key(),
      body: { response: "accept", actorType: "pet_agent" }
    });
    expect(rejected.status).toBe(409);
    expect(await rejected.json()).toMatchObject({ error: { code: "not_primary_agent_device" } });

    const accepted = await request(`/v1/visits/${first.id}/respond`, {
      token: bob.token,
      key: key(),
      body: { response: "accept", actorType: "pet_agent" }
    });
    expect(accepted.status).toBe(200);
  });

  it("atomically switches the primary Agent and emits one account event", async () => {
    const secondary = await issueSession(env.DB, env.SESSION_TOKEN_PEPPER, alice.accountID, {
      displayName: "Alice secondary",
      platform: "macos",
      appVersion: "test"
    });
    const claimed = await request(`/v1/devices/${secondary.device.id}/claim-agent`, {
      method: "POST",
      token: secondary.accessToken,
      key: key()
    });
    expect(claimed.status).toBe(200);
    expect(await jsonData(claimed)).toMatchObject({
      previousDeviceID: alice.deviceID,
      currentDeviceID: secondary.device.id
    });
    const newDeviceBootstrap = await jsonData<{ isPrimaryAgentDevice: boolean }>(
      await request("/v1/sync/bootstrap", { token: secondary.accessToken })
    );
    const oldDeviceBootstrap = await jsonData<{ isPrimaryAgentDevice: boolean }>(
      await request("/v1/sync/bootstrap", { token: alice.token })
    );
    expect(newDeviceBootstrap.isPrimaryAgentDevice).toBe(true);
    expect(oldDeviceBootstrap.isPrimaryAgentDevice).toBe(false);
    const event = await env.DB.prepare(`
      SELECT COUNT(*) AS count FROM account_events
      WHERE recipient_account_id = ? AND type = 'agent.primary.changed'
    `).bind(alice.accountID).first<{ count: number }>();
    expect(event?.count).toBe(1);
  });
});
