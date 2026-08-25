import { env } from "cloudflare:workers";
import { beforeEach, describe, expect, it } from "vitest";
import {
  acceptVisit,
  bootstrapAll,
  jsonData,
  key,
  request,
  resetDatabase,
  type DevProfile
} from "./helpers";

let alice: DevProfile;
let bob: DevProfile;
let visitID: string;

beforeEach(async () => {
  await resetDatabase();
  ({ alice, bob } = await bootstrapAll());
  visitID = (await acceptVisit(alice, bob)).id;
});

describe("Visit actions and offline recovery", () => {
  it("keeps host actions unresolved until the visitor primary Agent replies", async () => {
    const hostActionResponse = await request(`/v1/visits/${visitID}/actions`, {
      token: bob.token,
      key: key(),
      body: { kind: "feed", actorType: "human", payload: { food: "cookie" } }
    });
    expect(hostActionResponse.status).toBe(201);
    const hostAction = await jsonData<{ id: string }>(hostActionResponse);

    const bootstrap = await jsonData<{ unresolvedVisitActions: Array<{ id: string }> }>(
      await request("/v1/sync/bootstrap", { token: alice.token })
    );
    expect(bootstrap.unresolvedVisitActions.map((action) => action.id)).toContain(hostAction.id);

    const replacementDeviceID = crypto.randomUUID();
    await env.DB.batch([
      env.DB.prepare(`
        INSERT INTO devices(id, account_id, display_name, platform, app_version, created_at_ms, revoked_at_ms)
        VALUES (?, ?, 'Replacement', 'macos', 'test', ?, NULL)
      `).bind(replacementDeviceID, alice.accountID, Date.now()),
      env.DB.prepare("UPDATE accounts SET primary_agent_device_id = ? WHERE id = ?")
        .bind(replacementDeviceID, alice.accountID)
    ]);
    const nonPrimary = await request(`/v1/visits/${visitID}/actions`, {
      token: alice.token,
      key: key(),
      body: {
        kind: "acknowledgement",
        actorType: "pet_agent",
        payload: {},
        replyToActionID: hostAction.id
      }
    });
    expect(nonPrimary.status).toBe(409);
    expect(await nonPrimary.json()).toMatchObject({ error: { code: "not_primary_agent_device" } });

    await env.DB.prepare("UPDATE accounts SET primary_agent_device_id = ? WHERE id = ?")
      .bind(alice.deviceID, alice.accountID).run();
    const reply = await request(`/v1/visits/${visitID}/actions`, {
      token: alice.token,
      key: key(),
      body: {
        kind: "acknowledgement",
        actorType: "pet_agent",
        payload: {},
        replyToActionID: hostAction.id
      }
    });
    expect(reply.status).toBe(201);

    const duplicateReply = await request(`/v1/visits/${visitID}/actions`, {
      token: alice.token,
      key: key(),
      body: {
        kind: "reaction",
        actorType: "pet_agent",
        payload: { reaction: "happy" },
        replyToActionID: hostAction.id
      }
    });
    expect(duplicateReply.status).toBe(409);
    const recovered = await jsonData<{ unresolvedVisitActions: unknown[] }>(
      await request("/v1/sync/bootstrap", { token: alice.token })
    );
    expect(recovered.unresolvedVisitActions).toHaveLength(0);
  });

  it("rejects arbitrary actions and actions after a Visit closes", async () => {
    const unknown = await request(`/v1/visits/${visitID}/actions`, {
      token: bob.token,
      key: key(),
      body: { kind: "plugin_custom", actorType: "human", payload: {} }
    });
    expect(unknown.status).toBe(400);
    await request(`/v1/visits/${visitID}/end`, {
      token: bob.token, key: key(), body: { actorType: "human" }
    });
    const closed = await request(`/v1/visits/${visitID}/actions`, {
      token: bob.token,
      key: key(),
      body: { kind: "pet", actorType: "human", payload: {} }
    });
    expect(closed.status).toBe(409);
    expect(await closed.json()).toMatchObject({ error: { code: "visit_not_active" } });
  });
});

describe("encrypted visit letters", () => {
  it("never stores plaintext and delivers exactly once when the Visit closes", async () => {
    const plaintext = "这是一封只给 Alice 看的秘密信。";
    const created = await request(`/v1/visits/${visitID}/letters`, {
      token: bob.token,
      key: key(),
      body: { body: plaintext }
    });
    expect(created.status).toBe(201);
    const letter = await jsonData<{ id: string }>(created);

    const stored = await env.DB.prepare("SELECT ciphertext FROM letters WHERE id = ?")
      .bind(letter.id).first<{ ciphertext: string }>();
    expect(stored?.ciphertext).not.toContain(plaintext);
    const eventPayloads = await env.DB.prepare("SELECT payload_json FROM account_events WHERE aggregate_id = ?")
      .bind(letter.id).all<{ payload_json: string }>();
    expect(JSON.stringify(eventPayloads.results)).not.toContain(plaintext);
    const receipts = await env.DB.prepare("SELECT response_json FROM idempotency_records WHERE operation LIKE 'createLetter:%'")
      .all<{ response_json: string }>();
    expect(JSON.stringify(receipts.results)).not.toContain(plaintext);

    expect((await request(`/v1/letters/${letter.id}`, { token: alice.token })).status).toBe(404);
    const authorCopy = await request(`/v1/letters/${letter.id}`, { token: bob.token });
    expect(await jsonData(authorCopy)).toMatchObject({ body: plaintext, status: "attached" });

    expect((await request(`/v1/visits/${visitID}/end`, {
      token: alice.token, key: key(), body: { actorType: "human" }
    })).status).toBe(200);
    const delivered = await request(`/v1/letters/${letter.id}`, { token: alice.token });
    expect(await jsonData(delivered)).toMatchObject({ body: plaintext, status: "delivered" });

    expect((await request(`/v1/visits/${visitID}/end`, {
      token: bob.token, key: key(), body: { actorType: "human" }
    })).status).toBe(200);
    const deliveryEvents = await env.DB.prepare(`
      SELECT COUNT(*) AS count FROM account_events
      WHERE type = 'letter.delivered' AND aggregate_id = ?
    `).bind(letter.id).first<{ count: number }>();
    expect(deliveryEvents?.count).toBe(1);
  });
});
