import { beforeEach, describe, expect, it } from "vitest";
import { env } from "cloudflare:workers";
import { acceptVisit, bootstrapAll, jsonData, key, request, resetDatabase } from "./helpers";

interface CareState {
  fullness: number;
  energy: number;
  mood: number;
  bond: number;
  version: number;
}

interface Receipt {
  id: string;
  outcome: string;
  careState: CareState | null;
  publicCare: { fullness: string; energy: string; mood: string };
  familiarity: { score: number; tier: string } | null;
  effect: { bond: number; familiarity: number };
}

describe("model-free pet care", () => {
  beforeEach(resetDatabase);

  it("returns exact owner state and applies idempotent optimistic interactions", async () => {
    const { alice } = await bootstrapAll();
    const initial = await request("/v1/me/pet-state", { token: alice.token });
    expect(initial.status).toBe(200);
    expect(await jsonData<CareState>(initial)).toMatchObject({
      fullness: 70, energy: 80, mood: 70, bond: 20, version: 1
    });

    const idempotencyKey = key();
    const body = { kind: "feed", occurredAt: Date.now() };
    const first = await request(`/v1/pets/${alice.petID}/interactions`, {
      token: alice.token, key: idempotencyKey, body
    });
    expect(first.status).toBe(201);
    const receipt = await jsonData<Receipt>(first);
    expect(receipt.outcome).toBe("applied");
    expect(receipt.careState).toMatchObject({ fullness: 90, mood: 73, bond: 21, version: 2 });

    const replay = await request(`/v1/pets/${alice.petID}/interactions`, {
      token: alice.token, key: idempotencyKey, body
    });
    expect(await jsonData<Receipt>(replay)).toEqual(receipt);
    const count = await env.DB.prepare("SELECT COUNT(*) AS count FROM pet_interactions").first<{ count: number }>();
    expect(count?.count).toBe(1);
  });

  it("lets the host care for an offline visitor without exposing exact state", async () => {
    const { alice, bob } = await bootstrapAll();
    const visit = await acceptVisit(alice, bob);
    const response = await request(`/v1/pets/${alice.petID}/interactions`, {
      token: bob.token,
      key: key(),
      body: { kind: "play", visitID: visit.id, occurredAt: Date.now() }
    });
    expect(response.status).toBe(201);
    const receipt = await jsonData<Receipt>(response);
    expect(receipt.careState).toBeNull();
    expect(receipt.publicCare).toBeTruthy();
    expect(receipt.familiarity).toMatchObject({ score: 2, tier: "first_meeting" });
    expect(receipt.effect).toMatchObject({ bond: 0, familiarity: 2 });

    const ownerBootstrap = await jsonData<{
      ownPetCare: CareState;
      petFamiliarities: Array<{ score: number }>;
      friendships: Array<{ friend: { pet: { publicCare: object } } }>;
    }>(await request("/v1/sync/bootstrap", { token: alice.token }));
    expect(ownerBootstrap.ownPetCare.version).toBe(2);
    expect(ownerBootstrap.petFamiliarities[0]?.score).toBe(2);
    expect(ownerBootstrap.friendships[0]?.friend.pet.publicCare).toBeTruthy();

    const ended = await request(`/v1/visits/${visit.id}/end`, {
      token: bob.token,
      key: key(),
      body: { actorType: "human" }
    });
    expect(ended.status).toBe(200);
    const timeline = await jsonData<{ events: Array<{
      type: string;
      aggregateID: string;
      payload: { interactionSummary?: { counts: Record<string, number>; familiarityGained: number } };
    }> }>(await request("/v1/events?after=0&limit=100&timelineVisible=true", { token: alice.token }));
    const closed = timeline.events.find((event) => event.type === "visit.closed" && event.aggregateID === visit.id);
    expect(closed?.payload.interactionSummary).toMatchObject({
      counts: { play: 1 }, familiarityGained: 2
    });
  });

  it("rejects non-host friend access and friend rest", async () => {
    const { alice, bob, charlie } = await bootstrapAll();
    const visit = await acceptVisit(alice, bob);
    const stranger = await request(`/v1/pets/${alice.petID}/interactions`, {
      token: charlie.token,
      key: key(),
      body: { kind: "pet", visitID: visit.id, occurredAt: Date.now() }
    });
    expect(stranger.status).toBe(404);
    const rest = await request(`/v1/pets/${alice.petID}/interactions`, {
      token: bob.token,
      key: key(),
      body: { kind: "rest", visitID: visit.id, occurredAt: Date.now() }
    });
    expect(rest.status).toBe(404);
  });

  it("makes rapid repeats cosmetic and caps daily relationship gains", async () => {
    const { alice } = await bootstrapAll();
    const now = Date.now();
    const first = await request(`/v1/pets/${alice.petID}/interactions`, {
      token: alice.token, key: key(), body: { kind: "pet", occurredAt: now }
    });
    expect((await jsonData<Receipt>(first)).outcome).toBe("applied");
    const repeated = await request(`/v1/pets/${alice.petID}/interactions`, {
      token: alice.token, key: key(), body: { kind: "pet", occurredAt: now + 1 }
    });
    expect((await jsonData<Receipt>(repeated)).outcome).toBe("cosmetic_only");

    for (let index = 0; index < 8; index += 1) {
      await env.DB.prepare("UPDATE pet_interactions SET created_at_ms = created_at_ms - 31000").run();
      await request(`/v1/pets/${alice.petID}/interactions`, {
        token: alice.token,
        key: key(),
        body: { kind: index % 2 === 0 ? "play" : "flower", occurredAt: now + 2 + index }
      });
    }
    const state = await jsonData<CareState>(await request("/v1/me/pet-state", { token: alice.token }));
    expect(state.bond).toBeLessThanOrEqual(28);
  });

  it("lazily settles care, enforces fatigue thresholds, and rate-limits rest", async () => {
    const { alice } = await bootstrapAll();
    await request("/v1/me/pet-state", { token: alice.token });
    const threeDaysAgo = Date.now() - 3 * 86_400_000;
    await env.DB.prepare(`
      UPDATE pet_care_states SET fullness = 70, energy = 10, mood = 90,
        evaluated_at_ms = ? WHERE pet_id = ?
    `).bind(threeDaysAgo, alice.petID).run();
    const raw = await env.DB.prepare("SELECT * FROM pet_care_states WHERE pet_id = ?")
      .bind(alice.petID).first<{ fullness: number; energy: number; mood: number; evaluated_at_ms: number }>();
    expect(raw).toMatchObject({ fullness: 70, energy: 10, mood: 90, evaluated_at_ms: threeDaysAgo });

    const settled = await jsonData<CareState>(
      await request("/v1/me/pet-state", { token: alice.token })
    );
    expect(settled).toMatchObject({ fullness: 35, energy: 70, mood: 60 });

    await env.DB.prepare("UPDATE pet_care_states SET energy = 10, evaluated_at_ms = ? WHERE pet_id = ?")
      .bind(Date.now(), alice.petID).run();
    const tiredWalk = await jsonData<Receipt>(await request(`/v1/pets/${alice.petID}/interactions`, {
      token: alice.token, key: key(), body: { kind: "walk", occurredAt: Date.now() }
    }));
    expect(tiredWalk.outcome).toBe("too_tired");
    expect(tiredWalk.effect).toMatchObject({ bond: 0, familiarity: 0 });

    const firstRest = await jsonData<Receipt>(await request(`/v1/pets/${alice.petID}/interactions`, {
      token: alice.token, key: key(), body: { kind: "rest", occurredAt: Date.now() }
    }));
    expect(firstRest.outcome).toBe("applied");
    const secondRest = await jsonData<Receipt>(await request(`/v1/pets/${alice.petID}/interactions`, {
      token: alice.token, key: key(), body: { kind: "rest", occurredAt: Date.now() + 1 }
    }));
    expect(secondRest.outcome).toBe("cosmetic_only");
  });

  it("serializes care updates from concurrent devices without losing a change", async () => {
    const { alice } = await bootstrapAll();
    const now = Date.now();
    const responses = await Promise.all([
      request(`/v1/pets/${alice.petID}/interactions`, {
        token: alice.token, key: key(), body: { kind: "feed", occurredAt: now }
      }),
      request(`/v1/pets/${alice.petID}/interactions`, {
        token: alice.token, key: key(), body: { kind: "play", occurredAt: now + 1 }
      })
    ]);
    expect(responses.every((response) => response.status === 201)).toBe(true);
    const state = await jsonData<CareState>(await request("/v1/me/pet-state", { token: alice.token }));
    expect(state).toMatchObject({ fullness: 90, energy: 68, version: 3 });
  });
});
