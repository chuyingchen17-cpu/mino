import { beforeEach, describe, expect, it } from "vitest";
import { decisionMatchesContext } from "../src/application/model-decisions";
import { bootstrapAll, jsonData, key, request, resetDatabase, type DevProfile } from "./helpers";

let alice: DevProfile;
let bob: DevProfile;

beforeEach(async () => {
  await resetDatabase();
  ({ alice, bob } = await bootstrapAll());
});

describe("conversation continuity", () => {
  it("preserves pet turn order, human interjections, replay, and restart listing", async () => {
    const idempotencyKey = key();
    const body = {
      friendshipID: alice.friends[0]!.friendshipID,
      recipientPetID: bob.petID,
      openingMessage: "今天好吗？",
      actorType: "pet_agent"
    };
    const created = await request("/v1/conversations", {
      token: alice.token, key: idempotencyKey, body
    });
    expect(created.status).toBe(201);
    const initial = await jsonData<{ conversation: { id: string } }>(created);
    const replay = await request("/v1/conversations", {
      token: alice.token, key: idempotencyKey, body
    });
    expect((await jsonData<{ conversation: { id: string } }>(replay)).conversation.id)
      .toBe(initial.conversation.id);

    const human = await request(`/v1/conversations/${initial.conversation.id}/messages`, {
      token: alice.token,
      key: key(),
      body: { actorType: "human", text: "主人路过打个招呼" }
    });
    expect(human.status).toBe(201);
    const bobTurn = await request(`/v1/conversations/${initial.conversation.id}/messages`, {
      token: bob.token,
      key: key(),
      body: { actorType: "pet_agent", text: "我很好呀" }
    });
    expect(bobTurn.status).toBe(201);
    const wrongTurn = await request(`/v1/conversations/${initial.conversation.id}/messages`, {
      token: bob.token,
      key: key(),
      body: { actorType: "pet_agent", text: "再说一次" }
    });
    expect(wrongTurn.status).toBe(409);
    expect(await wrongTurn.json()).toMatchObject({ error: { code: "not_your_turn" } });

    const restored = await jsonData<Array<{ id: string }>>(await request("/v1/conversations", {
      token: alice.token
    }));
    expect(restored.map((conversation) => conversation.id)).toContain(initial.conversation.id);
    const messages = await jsonData<unknown[]>(await request(
      `/v1/conversations/${initial.conversation.id}/messages`, { token: bob.token }
    ));
    expect(messages).toHaveLength(3);
  });
});

describe("model inference receipts", () => {
  it("rejects provider-selected resources outside the verified request context", () => {
    const requestContext = {
      inferenceID: key(),
      petID: alice.petID,
      trigger: { type: "periodic_wake", summary: "wake" },
      state: { friendPetIDs: [bob.petID], invitationID: "visit-allowed", visitID: "visit-allowed" },
      memories: [],
      availableActions: ["send_pet_message", "respond_to_visit", "request_return"]
    };
    expect(decisionMatchesContext(
      { kind: "send_pet_message", recipientPetID: bob.petID, text: "hello" },
      requestContext
    )).toBe(true);
    expect(decisionMatchesContext(
      { kind: "send_pet_message", recipientPetID: "forged-pet", text: "hello" },
      requestContext
    )).toBe(false);
    expect(decisionMatchesContext(
      { kind: "respond_to_visit", invitationID: "forged-visit", response: "accept" },
      requestContext
    )).toBe(false);
  });

  it("replays one validated inference and rejects changed context under the same ID", async () => {
    const inferenceID = key();
    const body = {
      inferenceID,
      petID: alice.petID,
      trigger: { type: "periodic_wake", summary: "quiet wake" },
      state: { friendPetIDs: [bob.petID] },
      memories: [],
      availableActions: ["idle"]
    };
    const first = await request("/v1/agent/decision", { token: alice.token, body });
    expect(first.status).toBe(200);
    expect(await jsonData(first)).toMatchObject({ inferenceID, replayed: false, decision: { kind: "idle" } });
    const replay = await request("/v1/agent/decision", { token: alice.token, body });
    expect(await jsonData(replay)).toMatchObject({ inferenceID, replayed: true, decision: { kind: "idle" } });
    const changed = await request("/v1/agent/decision", {
      token: alice.token,
      body: { ...body, trigger: { ...body.trigger, summary: "changed" } }
    });
    expect(changed.status).toBe(409);
    expect(await changed.json()).toMatchObject({ error: { code: "inference_id_reused" } });
  });
});
