import { env } from "cloudflare:workers";
import { beforeEach, describe, expect, it } from "vitest";
import { issueSession } from "../src/storage/accounts-repository";
import {
  acceptVisit,
  bootstrapAll,
  jsonData,
  key,
  request,
  resetDatabase,
  type DevProfile
} from "./helpers";

type CharacterBody = "maltese-white" | "retriever-yellow";

interface PetSnapshot {
  petID: string;
  appearanceSchemaVersion: number;
  appearanceCatalogVersion: number;
  appearanceVersion: number;
  appearance: { rigID: string; body: CharacterBody };
}

let alice: DevProfile;
let bob: DevProfile;

beforeEach(async () => {
  await resetDatabase();
  ({ alice, bob } = await bootstrapAll());
  // Production-like dev fixtures keep Alice/Bob stable for visual E2E. These
  // focused tests explicitly put Alice back on the legacy upgrade boundary.
  await env.DB.prepare(`
    UPDATE pets SET appearance_schema_version = 1,
      appearance_catalog_version = 1,
      appearance_json = '{"rigID":"mino-default","body":"default"}',
      appearance_version = 1
    WHERE id = ?
  `).bind(alice.petID).run();
});

function selection(body: CharacterBody) {
  return {
    appearanceSchemaVersion: 1 as const,
    appearanceCatalogVersion: 2 as const,
    appearance: { rigID: "maltese-pair-v1" as const, body }
  };
}

function select(token: string, body: CharacterBody, idempotencyKey = key()) {
  return request("/v1/me/pet", {
    method: "PATCH",
    token,
    key: idempotencyKey,
    body: selection(body)
  });
}

describe("permanent pet character selection", () => {
  it("upgrades the legacy appearance and exposes catalog 2 through own and friend bootstrap", async () => {
    const response = await select(alice.token, "maltese-white");
    expect(response.status).toBe(200);
    expect(await jsonData<PetSnapshot>(response)).toMatchObject({
      petID: alice.petID,
      appearanceSchemaVersion: 1,
      appearanceCatalogVersion: 2,
      appearanceVersion: 2,
      appearance: { rigID: "maltese-pair-v1", body: "maltese-white" }
    });

    const own = await jsonData<{ pet: PetSnapshot }>(
      await request("/v1/sync/bootstrap", { token: alice.token })
    );
    const friend = await jsonData<{ friendships: Array<{ friend: { pet: PetSnapshot } }> }>(
      await request("/v1/sync/bootstrap", { token: bob.token })
    );
    expect(own.pet.appearance).toEqual({ rigID: "maltese-pair-v1", body: "maltese-white" });
    expect(friend.friendships[0]!.friend.pet.appearance).toEqual(own.pet.appearance);
  });

  it("treats the same choice as idempotent and locks a different choice", async () => {
    const idempotencyKey = key();
    const first = await select(alice.token, "maltese-white", idempotencyKey);
    const replay = await select(alice.token, "maltese-white", idempotencyKey);
    const sameChoice = await select(alice.token, "maltese-white");
    expect([first.status, replay.status, sameChoice.status]).toEqual([200, 200, 200]);
    expect((await jsonData<PetSnapshot>(replay)).appearanceVersion).toBe(2);
    expect((await jsonData<PetSnapshot>(sameChoice)).appearanceVersion).toBe(2);

    const changed = await select(alice.token, "retriever-yellow");
    expect(changed.status).toBe(409);
    expect(await changed.json()).toMatchObject({ error: { code: "appearance_locked" } });

    const eventCount = await env.DB.prepare(`
      SELECT COUNT(*) AS count FROM account_events
      WHERE recipient_account_id = ? AND type = 'pet.appearance.updated'
    `).bind(alice.accountID).first<{ count: number }>();
    expect(eventCount?.count).toBe(1);
  });

  it("allows an empty legacy appearance but rejects unsupported catalog entries at the route boundary", async () => {
    await env.DB.prepare(`
      UPDATE pets SET appearance_json = '{}', appearance_catalog_version = 1
      WHERE id = ?
    `).bind(alice.petID).run();
    expect((await select(alice.token, "retriever-yellow")).status).toBe(200);

    for (const body of [
      { ...selection("maltese-white"), appearanceCatalogVersion: 1 },
      { ...selection("maltese-white"), appearance: { rigID: "mino-default", body: "maltese-white" } },
      { ...selection("maltese-white"), appearance: { rigID: "maltese-pair-v1", body: "cat" } },
      { ...selection("maltese-white"), appearance: {
        rigID: "maltese-pair-v1", body: "maltese-white", accessory: "unapproved"
      } }
    ]) {
      const rejected = await request("/v1/me/pet", {
        method: "PATCH", token: bob.token, key: key(), body
      });
      expect(rejected.status).toBe(400);
      expect(await rejected.json()).toMatchObject({ error: { code: "invalid_request" } });
    }
  });

  it("converges competing device choices on the first successful selection", async () => {
    const secondDevice = await issueSession(
      env.DB,
      env.SESSION_TOKEN_PEPPER,
      alice.accountID,
      { displayName: "Alice Second Mac", platform: "macos", appVersion: "test" }
    );
    const attempts = await Promise.all([
      select(alice.token, "maltese-white"),
      select(secondDevice.accessToken, "retriever-yellow")
    ]);
    expect(attempts.map((response) => response.status).sort()).toEqual([200, 409]);
    const winner = await jsonData<PetSnapshot>(attempts.find((response) => response.status === 200)!);
    const loser = attempts.find((response) => response.status === 409)!;
    expect(await loser.json()).toMatchObject({ error: { code: "appearance_locked" } });

    const convergence = await select(secondDevice.accessToken, winner.appearance.body);
    expect(convergence.status).toBe(200);
    expect(await jsonData<PetSnapshot>(convergence)).toMatchObject({
      appearanceVersion: 2,
      appearance: winner.appearance
    });
    const stored = await env.DB.prepare(`
      SELECT appearance_catalog_version, appearance_json, appearance_version
      FROM pets WHERE id = ?
    `).bind(alice.petID).first<{
      appearance_catalog_version: number;
      appearance_json: string;
      appearance_version: number;
    }>();
    expect(stored).toMatchObject({ appearance_catalog_version: 2, appearance_version: 2 });
    expect(JSON.parse(stored!.appearance_json)).toEqual(winner.appearance);
  });

  it("publishes the selected appearance to both owners during an active visit", async () => {
    const visit = await acceptVisit(alice, bob);
    expect(visit.status).toBe("active");
    expect((await select(alice.token, "maltese-white")).status).toBe(200);

    const events = await env.DB.prepare(`
      SELECT recipient_account_id, friendship_id, payload_json
      FROM account_events
      WHERE aggregate_id = ? AND type = 'pet.appearance.updated'
      ORDER BY recipient_account_id
    `).bind(alice.petID).all<{
      recipient_account_id: string;
      friendship_id: string | null;
      payload_json: string;
    }>();
    expect(events.results.map((event) => event.recipient_account_id).sort())
      .toEqual([alice.accountID, bob.accountID].sort());
    expect(events.results.find((event) => event.recipient_account_id === alice.accountID)?.friendship_id)
      .toBeNull();
    expect(events.results.find((event) => event.recipient_account_id === bob.accountID)?.friendship_id)
      .toBe(alice.friends[0]!.friendshipID);
    expect(events.results.map((event) => JSON.parse(event.payload_json)))
      .toEqual(Array(2).fill({
        publicPetSnapshot: expect.objectContaining({
          petID: alice.petID,
          appearance: { rigID: "maltese-pair-v1", body: "maltese-white" }
        })
      }));
  });
});
