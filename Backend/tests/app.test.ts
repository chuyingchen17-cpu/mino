import { randomUUID } from "node:crypto";
import { afterEach, describe, expect, it } from "vitest";
import type { FastifyInstance } from "fastify";
import { buildApp } from "../src/app.js";
import type { AppConfig } from "../src/config.js";
import { InMemoryMinoStore } from "../src/memory-store.js";
import { DeterministicModelProvider } from "../src/model/provider.js";
import type { ModelProvider } from "../src/model/provider.js";
import { ModelDecisionService } from "../src/model/service.js";

const config: AppConfig = {
  nodeEnv: "test",
  host: "127.0.0.1",
  port: 8080,
  databaseURL: "postgres://unused",
  devBootstrapEnabled: true,
  model: { provider: "mock" }
};

interface TestContext {
  app: FastifyInstance;
  alice: Record<string, string>;
  bob: Record<string, string>;
}

const apps: FastifyInstance[] = [];

async function testContext(
  provider: ModelProvider = new DeterministicModelProvider()
): Promise<TestContext> {
  const store = new InMemoryMinoStore();
  const app = await buildApp({
    config,
    store,
    modelService: new ModelDecisionService(store, provider)
  });
  apps.push(app);
  const aliceResponse = await app.inject({ method: "POST", url: "/v1/dev/bootstrap", payload: { profile: "alice" } });
  const bobResponse = await app.inject({ method: "POST", url: "/v1/dev/bootstrap", payload: { profile: "bob" } });
  const aliceData = aliceResponse.json().data as Record<string, unknown>;
  const bobData = bobResponse.json().data as Record<string, unknown>;
  return {
    app,
    alice: {
      ...(aliceData as Record<string, string>),
      friendshipID: (aliceData.friends as Array<{ friendshipID: string }>)[0]!.friendshipID,
      friendAccountID: bobData.accountID as string,
      friendPetID: bobData.petID as string
    },
    bob: {
      ...(bobData as Record<string, string>),
      friendshipID: (bobData.friends as Array<{ friendshipID: string }>)[0]!.friendshipID,
      friendAccountID: aliceData.accountID as string,
      friendPetID: aliceData.petID as string
    }
  };
}

function auth(profile: Record<string, string>): Record<string, string> {
  return { authorization: `Bearer ${profile.token}` };
}

afterEach(async () => {
  await Promise.all(apps.splice(0).map((app) => app.close()));
});

describe("Mino backend MVP", () => {
  it("creates, rejects, reapplies, and accepts account friendships before allowing visits", async () => {
    const { app, alice } = await testContext();
    const charlieBootstrap = await app.inject({
      method: "POST",
      url: "/v1/dev/bootstrap",
      payload: { profile: "charlie" }
    });
    const charlie = charlieBootstrap.json().data as Record<string, string>;
    expect(charlie).not.toHaveProperty("coupleID");
    expect(charlie).not.toHaveProperty("partnerAccountID");
    expect(charlie).not.toHaveProperty("partnerPetID");
    expect(charlie).not.toHaveProperty("friendAccountID");
    expect(charlie).not.toHaveProperty("friendPetID");

    const requested = await app.inject({
      method: "POST",
      url: "/v1/friendships",
      headers: auth(charlie),
      payload: { addresseeAccountID: alice.accountID, idempotencyKey: randomUUID() }
    });
    expect(requested.statusCode).toBe(200);
    expect(requested.json().data).toMatchObject({ status: "pending", friend: { accountID: alice.accountID } });
    const rejectedFriendshipID = requested.json().data.id as string;

    const pendingCannotVisit = await app.inject({
      method: "POST",
      url: `/v1/visit-invitations?friendshipID=${rejectedFriendshipID}`,
      headers: auth(charlie),
      payload: {
        visitorPetID: charlie.petID,
        hostAccountID: alice.accountID,
        idempotencyKey: randomUUID()
      }
    });
    expect(pendingCannotVisit.statusCode).toBe(404);

    const requesterCannotRespond = await app.inject({
      method: "POST",
      url: `/v1/friendships/${rejectedFriendshipID}/respond`,
      headers: auth(charlie),
      payload: { response: "accept", idempotencyKey: randomUUID() }
    });
    expect(requesterCannotRespond.statusCode).toBe(404);

    const rejected = await app.inject({
      method: "POST",
      url: `/v1/friendships/${rejectedFriendshipID}/respond`,
      headers: auth(alice),
      payload: { response: "reject", idempotencyKey: randomUUID() }
    });
    expect(rejected.json().data.status).toBe("rejected");

    const reapplied = await app.inject({
      method: "POST",
      url: "/v1/friendships",
      headers: auth(charlie),
      payload: { addresseeAccountID: alice.accountID, idempotencyKey: randomUUID() }
    });
    expect(reapplied.statusCode).toBe(200);
    const friendshipID = reapplied.json().data.id as string;
    expect(friendshipID).not.toBe(rejectedFriendshipID);

    const accepted = await app.inject({
      method: "POST",
      url: `/v1/friendships/${friendshipID}/respond`,
      headers: auth(alice),
      payload: { response: "accept", idempotencyKey: randomUUID() }
    });
    expect(accepted.json().data.status).toBe("accepted");

    const ambiguousConversation = await app.inject({
      method: "POST",
      url: "/v1/conversations",
      headers: auth(alice),
      payload: {
        recipientPetID: charlie.petID,
        openingMessage: "缺少好友上下文",
        idempotencyKey: randomUUID()
      }
    });
    expect(ambiguousConversation.statusCode).toBe(409);
    expect(ambiguousConversation.json().error.code).toBe("friendship_context_required");

    const bobConversation = await app.inject({
      method: "POST",
      url: `/v1/conversations?friendshipID=${alice.friendshipID}`,
      headers: auth(alice),
      payload: {
        recipientPetID: alice.friendPetID,
        openingMessage: "发给 Bob 的独立对话",
        idempotencyKey: randomUUID()
      }
    });
    const charlieConversation = await app.inject({
      method: "POST",
      url: `/v1/conversations?friendshipID=${friendshipID}`,
      headers: auth(alice),
      payload: {
        recipientPetID: charlie.petID,
        openingMessage: "发给 Charlie 的独立对话",
        idempotencyKey: randomUUID()
      }
    });
    expect(bobConversation.statusCode).toBe(200);
    expect(charlieConversation.statusCode).toBe(200);
    expect(bobConversation.json().data.conversation.friendshipID).toBe(alice.friendshipID);
    expect(charlieConversation.json().data.conversation.friendshipID).toBe(friendshipID);

    const visit = await app.inject({
      method: "POST",
      url: `/v1/visit-invitations?friendshipID=${friendshipID}`,
      headers: auth(charlie),
      payload: {
        visitorPetID: charlie.petID,
        hostAccountID: alice.accountID,
        idempotencyKey: randomUUID()
      }
    });
    expect(visit.statusCode).toBe(200);
    expect(visit.json().data.friendshipID).toBe(friendshipID);

    const wrongScope = await app.inject({
      method: "POST",
      url: `/v1/conversations?friendshipID=${alice.friendshipID}`,
      headers: auth(alice),
      payload: {
        recipientPetID: charlie.petID,
        openingMessage: "不应跨好友关系发送",
        idempotencyKey: randomUUID()
      }
    });
    expect(wrongScope.statusCode).toBe(404);
  });

  it("serves root and /v1 health and protects authenticated routes", async () => {
    const { app, alice } = await testContext();
    expect((await app.inject({ method: "GET", url: "/health" })).statusCode).toBe(200);
    expect((await app.inject({ method: "GET", url: "/v1/health" })).json().data.status).toBe("healthy");
    const denied = await app.inject({ method: "GET", url: "/v1/events" });
    expect(denied.statusCode).toBe(401);
    expect(denied.json().error.code).toBe("unauthorized");
    expect((await app.inject({ method: "GET", url: "/v1/couple-events", headers: auth(alice) })).statusCode).toBe(404);
  });

  it("rejects pet and resource identifiers outside the authenticated friendship context", async () => {
    const { app, alice } = await testContext();
    const foreignPet = await app.inject({
      method: "POST",
      url: "/v1/conversations",
      headers: auth(alice),
      payload: { recipientPetID: randomUUID(), openingMessage: "越权消息", idempotencyKey: randomUUID() }
    });
    expect(foreignPet.statusCode).toBe(404);

    const foreignVisit = await app.inject({
      method: "POST",
      url: `/v1/visits/${randomUUID()}/end`,
      headers: auth(alice),
      payload: { idempotencyKey: randomUUID() }
    });
    expect(foreignVisit.statusCode).toBe(404);
  });

  it("runs an idempotent six-turn pet conversation and creates one summary", async () => {
    const { app, alice, bob } = await testContext();
    const createKey = randomUUID();
    const created = await app.inject({
      method: "POST",
      url: "/v1/conversations",
      headers: auth(alice),
      payload: { recipientPetID: alice.friendPetID, openingMessage: "团子，你今天好吗？", idempotencyKey: createKey }
    });
    expect(created.statusCode).toBe(200);
    const conversationID = created.json().data.conversation.id as string;

    const replay = await app.inject({
      method: "POST",
      url: "/v1/conversations",
      headers: auth(alice),
      payload: { recipientPetID: alice.friendPetID, openingMessage: "团子，你今天好吗？", idempotencyKey: createKey }
    });
    expect(replay.statusCode).toBe(200);
    expect(replay.json().data.conversation.id).toBe(conversationID);

    const mismatchedReplay = await app.inject({
      method: "POST",
      url: "/v1/conversations",
      headers: auth(alice),
      payload: { recipientPetID: alice.friendPetID, openingMessage: "不同内容", idempotencyKey: createKey }
    });
    expect(mismatchedReplay.statusCode).toBe(409);
    expect(mismatchedReplay.json().error.code).toBe("idempotency_key_reused");

    const turns = [
      [bob, "我很好呀"],
      [alice, "要不要晚点玩"],
      [bob, "好呀"],
      [alice, "我带小饼干"],
      [bob, "那我等你"]
    ] as const;
    for (const [profile, text] of turns) {
      const response = await app.inject({
        method: "POST",
        url: `/v1/conversations/${conversationID}/messages`,
        headers: auth(profile),
        payload: { actorType: "pet", text, idempotencyKey: randomUUID() }
      });
      expect(response.statusCode).toBe(200);
    }

    const extra = await app.inject({
      method: "POST",
      url: `/v1/conversations/${conversationID}/messages`,
      headers: auth(alice),
      payload: { actorType: "pet", text: "第七句话", idempotencyKey: randomUUID() }
    });
    expect(extra.statusCode).toBe(409);
    expect(extra.json().error.code).toBe("conversation_ended");

    const timelineBeforeSummary = await app.inject({ method: "GET", url: "/v1/timeline", headers: auth(alice) });
    expect(timelineBeforeSummary.json().data.events.filter(
      (event: { type: string }) => event.type === "conversation_summary"
    )).toHaveLength(0);

    const recipientCannotSummarize = await app.inject({
      method: "POST",
      url: `/v1/conversations/${conversationID}/end`,
      headers: auth(bob),
      payload: { summary: "接收方不应代替发起方总结", idempotencyKey: randomUUID() }
    });
    expect(recipientCannotSummarize.statusCode).toBe(404);

    const generatedSummary = "奶糖和团子聊了近况，还约好晚点带小饼干一起玩。";
    const summarizedEnd = await app.inject({
      method: "POST",
      url: `/v1/conversations/${conversationID}/end`,
      headers: auth(alice),
      payload: { summary: generatedSummary, idempotencyKey: randomUUID() }
    });
    expect(summarizedEnd.statusCode).toBe(200);

    const redundantEnd = await app.inject({
      method: "POST",
      url: `/v1/conversations/${conversationID}/end`,
      headers: auth(alice),
      payload: { summary: "不应产生第二条摘要", idempotencyKey: randomUUID() }
    });
    expect(redundantEnd.statusCode).toBe(200);

    const timeline = await app.inject({ method: "GET", url: "/v1/timeline", headers: auth(alice) });
    const summaries = timeline.json().data.events.filter((event: { type: string }) => event.type === "conversation_summary");
    expect(summaries).toHaveLength(1);
    expect(summaries[0].payload.summary).toBe(generatedSummary);
  });

  it("rejects a message idempotency key reused in another conversation", async () => {
    const { app, alice, bob } = await testContext();
    const first = await app.inject({
      method: "POST",
      url: "/v1/conversations",
      headers: auth(alice),
      payload: {
        recipientPetID: alice.friendPetID,
        openingMessage: "第一段对话",
        idempotencyKey: randomUUID()
      }
    });
    const firstConversationID = first.json().data.conversation.id as string;
    const reusedKey = randomUUID();
    const firstMessage = await app.inject({
      method: "POST",
      url: `/v1/conversations/${firstConversationID}/messages`,
      headers: auth(bob),
      payload: { actorType: "pet", text: "第一次使用这个键", idempotencyKey: reusedKey }
    });
    expect(firstMessage.statusCode).toBe(200);
    await app.inject({
      method: "POST",
      url: `/v1/conversations/${firstConversationID}/end`,
      headers: auth(alice),
      payload: { summary: "第一段对话结束", idempotencyKey: randomUUID() }
    });

    const second = await app.inject({
      method: "POST",
      url: "/v1/conversations",
      headers: auth(alice),
      payload: {
        recipientPetID: alice.friendPetID,
        openingMessage: "第二段对话",
        idempotencyKey: randomUUID()
      }
    });
    const secondConversationID = second.json().data.conversation.id as string;
    const reused = await app.inject({
      method: "POST",
      url: `/v1/conversations/${secondConversationID}/messages`,
      headers: auth(bob),
      payload: { actorType: "pet", text: "第二次使用这个键", idempotencyKey: reusedKey }
    });

    expect(reused.statusCode).toBe(409);
    expect(reused.json().error.code).toBe("idempotency_key_reused");
  });

  it("restores the one active conversation and its ordered messages", async () => {
    const { app, alice, bob } = await testContext();
    const [fromAlice, fromBob] = await Promise.all([
      app.inject({
        method: "POST",
        url: "/v1/conversations",
        headers: auth(alice),
        payload: {
          recipientPetID: alice.friendPetID,
          openingMessage: "Alice opening",
          idempotencyKey: randomUUID()
        }
      }),
      app.inject({
        method: "POST",
        url: "/v1/conversations",
        headers: auth(bob),
        payload: {
          recipientPetID: bob.friendPetID,
          openingMessage: "Bob opening",
          idempotencyKey: randomUUID()
        }
      })
    ]);
    expect([fromAlice.statusCode, fromBob.statusCode].sort()).toEqual([200, 409]);
    const rejected = fromAlice.statusCode === 409 ? fromAlice : fromBob;
    expect(rejected.json().error.code).toBe("active_conversation_exists");

    const activeForAlice = await app.inject({
      method: "GET",
      url: "/v1/conversations?status=active",
      headers: auth(alice)
    });
    const activeForBob = await app.inject({
      method: "GET",
      url: "/v1/conversations?status=active",
      headers: auth(bob)
    });
    expect(activeForAlice.statusCode).toBe(200);
    expect(activeForAlice.json().data).toHaveLength(1);
    expect(activeForBob.json().data).toEqual(activeForAlice.json().data);
    const conversationID = activeForAlice.json().data[0].id as string;
    const nextSpeaker = activeForAlice.json().data[0].nextSpeakerPetID === alice.petID ? alice : bob;
    const continued = await app.inject({
      method: "POST",
      url: `/v1/conversations/${conversationID}/messages`,
      headers: auth(nextSpeaker),
      payload: { actorType: "pet", text: "恢复前的第二轮", idempotencyKey: randomUUID() }
    });
    expect(continued.statusCode).toBe(200);

    const messages = await app.inject({
      method: "GET",
      url: `/v1/conversations/${conversationID}/messages`,
      headers: auth(bob)
    });
    expect(messages.statusCode).toBe(200);
    expect(messages.json().data).toHaveLength(2);
    expect(["Alice opening", "Bob opening"]).toContain(messages.json().data[0].text);
    expect(messages.json().data.map((message: { turnIndex: number }) => message.turnIndex)).toEqual([0, 1]);
    expect(messages.json().data[1].text).toBe("恢复前的第二轮");

    const unknown = await app.inject({
      method: "GET",
      url: `/v1/conversations/${randomUUID()}/messages`,
      headers: auth(alice)
    });
    expect(unknown.statusCode).toBe(404);

    const unsupportedStatus = await app.inject({
      method: "GET",
      url: "/v1/conversations?status=ended",
      headers: auth(alice)
    });
    expect(unsupportedStatus.statusCode).toBe(400);
  });

  it("completes visit, host interaction, private carried letter, and return timeline", async () => {
    const { app, alice, bob } = await testContext();
    const invitation = await app.inject({
      method: "POST",
      url: "/v1/visit-invitations",
      headers: auth(alice),
      payload: {
        visitorPetID: alice.petID,
        hostAccountID: alice.friendAccountID,
        reason: "想去找团子玩",
        idempotencyKey: randomUUID()
      }
    });
    expect(invitation.statusCode).toBe(200);
    const visitID = invitation.json().data.id as string;

    const accepted = await app.inject({
      method: "POST",
      url: `/v1/visit-invitations/${visitID}/respond`,
      headers: auth(bob),
      payload: { response: "accept", idempotencyKey: randomUUID() }
    });
    expect(accepted.json().data.status).toBe("active");

    const wrongHost = await app.inject({
      method: "POST",
      url: `/v1/visits/${visitID}/interactions`,
      headers: auth(alice),
      payload: { kind: "feed", idempotencyKey: randomUUID() }
    });
    expect(wrongHost.statusCode).toBe(404);

    const interaction = await app.inject({
      method: "POST",
      url: `/v1/visits/${visitID}/interactions`,
      headers: auth(bob),
      payload: { kind: "play", idempotencyKey: randomUUID() }
    });
    expect(interaction.statusCode).toBe(200);

    const hostCannotSpeakAsVisitor = await app.inject({
      method: "POST",
      url: `/v1/visits/${visitID}/reactions`,
      headers: auth(bob),
      payload: { reaction: "happy", text: "伪造的访客反应", idempotencyKey: randomUUID() }
    });
    expect(hostCannotSpeakAsVisitor.statusCode).toBe(404);

    const reactionKey = randomUUID();
    const reaction = await app.inject({
      method: "POST",
      url: `/v1/visits/${visitID}/reactions`,
      headers: auth(alice),
      payload: { reaction: "happy", text: "谢谢你陪我玩！", idempotencyKey: reactionKey }
    });
    expect(reaction.statusCode).toBe(200);
    const reactionReplay = await app.inject({
      method: "POST",
      url: `/v1/visits/${visitID}/reactions`,
      headers: auth(alice),
      payload: { reaction: "happy", text: "谢谢你陪我玩！", idempotencyKey: reactionKey }
    });
    expect(reactionReplay.json().data.reactionID).toBe(reaction.json().data.reactionID);
    const reactionMismatch = await app.inject({
      method: "POST",
      url: `/v1/visits/${visitID}/reactions`,
      headers: auth(alice),
      payload: { reaction: "happy", text: "不同内容", idempotencyKey: reactionKey }
    });
    expect(reactionMismatch.statusCode).toBe(409);
    expect(reactionMismatch.json().error.code).toBe("idempotency_key_reused");

    const secretBody = "今天辛苦了，晚上一起吃饭。";
    const letter = await app.inject({
      method: "POST",
      url: `/v1/visits/${visitID}/letter`,
      headers: auth(bob),
      payload: { body: secretBody, idempotencyKey: randomUUID() }
    });
    expect(letter.json().data.status).toBe("carried");
    const letterID = letter.json().data.id as string;

    const authorCopy = await app.inject({ method: "GET", url: `/v1/letters/${letterID}`, headers: auth(bob) });
    expect(authorCopy.statusCode).toBe(200);
    expect(authorCopy.json().data.body).toBe(secretBody);
    const recipientTooEarly = await app.inject({ method: "GET", url: `/v1/letters/${letterID}`, headers: auth(alice) });
    expect(recipientTooEarly.statusCode).toBe(404);

    const rejectedModelLeak = await app.inject({
      method: "POST",
      url: "/v1/agent/decision",
      headers: auth(alice),
      payload: {
        inferenceID: randomUUID(),
        petID: alice.petID,
        trigger: { type: "letter_received", summary: "宠物携带着一封私人信件" },
        state: { letterID, letterBody: secretBody },
        memories: [],
        availableActions: ["idle"]
      }
    });
    expect(rejectedModelLeak.statusCode).toBe(400);
    expect(rejectedModelLeak.json().error.code).toBe("letter_content_forbidden");

    const ended = await app.inject({
      method: "POST",
      url: `/v1/visits/${visitID}/end`,
      headers: auth(alice),
      payload: { idempotencyKey: randomUUID() }
    });
    expect(ended.json().data.visit.status).toBe("ended");
    expect(ended.json().data.deliveredLetters[0].status).toBe("delivered");

    const deliveredLetter = await app.inject({ method: "GET", url: `/v1/letters/${letterID}`, headers: auth(alice) });
    expect(deliveredLetter.statusCode).toBe(200);
    expect(deliveredLetter.json().data.body).toBe(secretBody);

    const eventsResponse = await app.inject({ method: "GET", url: "/v1/events", headers: auth(alice) });
    const serializedEvents = JSON.stringify(eventsResponse.json().data.events);
    expect(serializedEvents).not.toContain(secretBody);
    const eventTypes = eventsResponse.json().data.events.map((event: { type: string }) => event.type);
    expect(eventTypes).toContain("visit_arrived");
    expect(eventTypes).toContain("visit_interaction");
    expect(eventTypes).toContain("visit_reaction");
    expect(eventTypes).toContain("visit_returned");
    expect(eventTypes).toContain("letter_received");
    const reactionEvents = eventsResponse.json().data.events.filter((event: { type: string }) => event.type === "visit_reaction");
    expect(reactionEvents).toHaveLength(1);
    expect(reactionEvents[0].payload).toEqual({
      visitID,
      visitorPetID: alice.petID,
      reaction: "happy",
      text: "谢谢你陪我玩！"
    });

    const timeline = await app.inject({ method: "GET", url: "/v1/timeline", headers: auth(alice) });
    expect(timeline.json().data.events.some((event: { type: string }) => event.type === "visit_reaction")).toBe(false);

    const presence = await app.inject({ method: "GET", url: "/v1/pet-presence", headers: auth(alice) });
    expect(presence.json().data.activeVisits).toEqual([]);
    expect(presence.json().data.pets.every((pet: { phase: string }) => pet.phase === "at_home")).toBe(true);
  });

  it("allows opposite visits while keeping each visitor and host globally unique", async () => {
    const { app, alice, bob } = await testContext();
    const first = await app.inject({
      method: "POST", url: "/v1/visit-invitations", headers: auth(alice),
      payload: { visitorPetID: alice.petID, hostAccountID: alice.friendAccountID, idempotencyKey: randomUUID() }
    });
    await app.inject({
      method: "POST", url: `/v1/visit-invitations/${first.json().data.id}/respond`, headers: auth(bob),
      payload: { response: "accept", idempotencyKey: randomUUID() }
    });

    const second = await app.inject({
      method: "POST", url: "/v1/visit-invitations", headers: auth(alice),
      payload: { visitorPetID: alice.friendPetID, hostAccountID: alice.accountID, idempotencyKey: randomUUID() }
    });
    const oppositeVisit = await app.inject({
      method: "POST", url: `/v1/visit-invitations/${second.json().data.id}/respond`, headers: auth(bob),
      payload: { response: "accept", idempotencyKey: randomUUID() }
    });
    expect(oppositeVisit.statusCode).toBe(200);
  });

  it("only lets the account opposite the invitation requester respond", async () => {
    const { app, alice, bob } = await testContext();
    const invitation = await app.inject({
      method: "POST",
      url: "/v1/visit-invitations",
      headers: auth(alice),
      payload: {
        visitorPetID: alice.petID,
        hostAccountID: bob.accountID,
        idempotencyKey: randomUUID()
      }
    });
    const visitID = invitation.json().data.id as string;

    const requesterCannotRespond = await app.inject({
      method: "POST",
      url: `/v1/visit-invitations/${visitID}/respond`,
      headers: auth(alice),
      payload: { response: "accept", idempotencyKey: randomUUID() }
    });
    expect(requesterCannotRespond.statusCode).toBe(404);

    const responderCanAccept = await app.inject({
      method: "POST",
      url: `/v1/visit-invitations/${visitID}/respond`,
      headers: auth(bob),
      payload: { response: "accept", idempotencyKey: randomUUID() }
    });
    expect(responderCanAccept.statusCode).toBe(200);
    expect(responderCanAccept.json().data.status).toBe("active");
  });

  it("rejects the deprecated direct visit before creating a pending invitation", async () => {
    const { app, alice } = await testContext();
    const response = await app.inject({
      method: "POST",
      url: "/v1/pet-visits",
      headers: auth(alice),
      payload: {
        idempotencyKey: randomUUID(),
        petID: alice.petID,
        destinationAccountID: alice.friendAccountID,
        outboundCargo: []
      }
    });
    expect(response.statusCode).toBe(409);
    expect(response.json().error.code).toBe("visit_invitation_required");

    const pending = await app.inject({
      method: "GET",
      url: "/v1/visit-invitations?status=pending",
      headers: auth(alice)
    });
    expect(pending.json().data).toEqual([]);
    const events = await app.inject({ method: "GET", url: "/v1/events", headers: auth(alice) });
    expect(events.json().data.events).toEqual([]);
  });

  it("rejects private-letter context before it can reach the model provider", async () => {
    let providerCalls = 0;
    const provider: ModelProvider = {
      id: "capture",
      model: "capture-v1",
      async decide() {
        providerCalls += 1;
        return {
          decision: { kind: "idle" },
          memoryDisposition: { kind: "discard" },
          usage: { inputTokens: 0, outputTokens: 0 }
        };
      }
    };
    const { app, alice } = await testContext(provider);
    const payloads = [
      {
        trigger: { type: "sealed_human_letter_available", summary: "信里的私人正文" },
        state: {}
      },
      {
        trigger: { type: "owner_message", summary: "普通主人消息" },
        state: { letterText: "信里的私人正文" }
      },
      {
        trigger: { type: "owner_message", summary: "普通主人消息" },
        state: {},
        memories: [{ kind: "letter", summary: "信里的私人正文" }]
      }
    ];

    for (const candidate of payloads) {
      const response = await app.inject({
        method: "POST",
        url: "/v1/agent/decision",
        headers: auth(alice),
        payload: {
          inferenceID: randomUUID(),
          petID: alice.petID,
          memories: [],
          availableActions: ["idle"],
          ...candidate
        }
      });
      expect(response.statusCode).toBe(400);
      expect(response.json().error.code).toBe("letter_content_forbidden");
    }
    expect(providerCalls).toBe(0);
  });

  it("uses the safe model proxy, selects memory disposition, and deduplicates inference", async () => {
    const { app, alice } = await testContext();
    const inferenceID = randomUUID();
    const request = {
      inferenceID,
      petID: alice.petID,
      trigger: { type: "visit_interaction", summary: "Bob 和奶糖玩了羽毛球" },
      state: {},
      memories: [],
      availableActions: ["react_to_interaction"]
    };
    const first = await app.inject({ method: "POST", url: "/v1/agent/decision", headers: auth(alice), payload: request });
    expect(first.statusCode).toBe(200);
    expect(first.json().data.decision.kind).toBe("react_to_interaction");
    expect(first.json().data.memoryDisposition.kind).toBe("long_term");
    expect(first.json().data.replayed).toBe(false);

    const replay = await app.inject({ method: "POST", url: "/v1/agent/decision", headers: auth(alice), payload: request });
    expect(replay.json().data.decision).toEqual(first.json().data.decision);
    expect(replay.json().data.replayed).toBe(true);
  });

  it("lets the deterministic development pet autonomously contact an accepted friend on a periodic wake", async () => {
    const { app, alice } = await testContext();
    const response = await app.inject({
      method: "POST",
      url: "/v1/agent/decision",
      headers: auth(alice),
      payload: {
        inferenceID: randomUUID(),
        petID: alice.petID,
        trigger: { type: "periodic_wake", summary: "一次低频自主思考机会" },
        state: { friendPetIDs: [alice.friendPetID] },
        memories: [],
        availableActions: ["send_pet_message", "speak_to_owner"]
      }
    });

    expect(response.statusCode).toBe(200);
    expect(response.json().data.decision).toEqual({
      kind: "send_pet_message",
      recipientPetID: alice.friendPetID,
      text: "我刚刚想起你了，今天过得怎么样？"
    });
  });

  it("rejects unaccepted friend-pet whitelist entries before calling the model", async () => {
    let providerCalls = 0;
    const provider: ModelProvider = {
      id: "capture",
      model: "capture-v1",
      async decide() {
        providerCalls += 1;
        return {
          decision: { kind: "idle" },
          memoryDisposition: { kind: "discard" },
          usage: { inputTokens: 0, outputTokens: 0 }
        };
      }
    };
    const { app, alice } = await testContext(provider);
    const response = await app.inject({
      method: "POST",
      url: "/v1/agent/decision",
      headers: auth(alice),
      payload: {
        inferenceID: randomUUID(),
        petID: alice.petID,
        trigger: { type: "periodic_wake", summary: "一次低频自主思考机会" },
        state: { friendPetIDs: [alice.friendPetID, randomUUID()] },
        memories: [],
        availableActions: ["send_pet_message"]
      }
    });

    expect(response.statusCode).toBe(400);
    expect(response.json().error.code).toBe("invalid_agent_context");
    expect(providerCalls).toBe(0);
  });

  it("rejects a model social target outside the supplied friend-pet whitelist", async () => {
    const outsidePetID = randomUUID();
    const provider: ModelProvider = {
      id: "outside-target",
      model: "outside-target-v1",
      async decide() {
        return {
          decision: { kind: "send_pet_message", recipientPetID: outsidePetID, text: "越界目标" },
          memoryDisposition: { kind: "discard" },
          usage: { inputTokens: 1, outputTokens: 1 }
        };
      }
    };
    const { app, alice } = await testContext(provider);
    const response = await app.inject({
      method: "POST",
      url: "/v1/agent/decision",
      headers: auth(alice),
      payload: {
        inferenceID: randomUUID(),
        petID: alice.petID,
        trigger: { type: "periodic_wake", summary: "一次低频自主思考机会" },
        state: { friendPetIDs: [alice.friendPetID] },
        memories: [],
        availableActions: ["send_pet_message"]
      }
    });

    expect(response.statusCode).toBe(400);
    expect(response.json().error.code).toBe("invalid_model_target");
  });

  it("lets the model select among multiple accepted friend pets", async () => {
    const provider: ModelProvider = {
      id: "multi-friend",
      model: "multi-friend-v1",
      async decide(request) {
        const recipientPetID = request.state.friendPetIDs?.at(-1);
        if (!recipientPetID) throw new Error("Expected a friend-pet whitelist");
        return {
          decision: { kind: "send_pet_message", recipientPetID, text: "我来找你聊聊天。" },
          memoryDisposition: { kind: "session" },
          usage: { inputTokens: 1, outputTokens: 1 }
        };
      }
    };
    const { app, alice } = await testContext(provider);
    const charlieBootstrap = await app.inject({
      method: "POST",
      url: "/v1/dev/bootstrap",
      payload: { profile: "charlie" }
    });
    const charlie = charlieBootstrap.json().data as Record<string, string>;
    const requested = await app.inject({
      method: "POST",
      url: "/v1/friendships",
      headers: auth(charlie),
      payload: { addresseeAccountID: alice.accountID, idempotencyKey: randomUUID() }
    });
    const friendshipID = requested.json().data.id as string;
    await app.inject({
      method: "POST",
      url: `/v1/friendships/${friendshipID}/respond`,
      headers: auth(alice),
      payload: { response: "accept", idempotencyKey: randomUUID() }
    });

    const response = await app.inject({
      method: "POST",
      url: "/v1/agent/decision",
      headers: auth(alice),
      payload: {
        inferenceID: randomUUID(),
        petID: alice.petID,
        trigger: { type: "periodic_wake", summary: "从好友中自主选择一只宠物联系" },
        state: { friendPetIDs: [alice.friendPetID, charlie.petID] },
        memories: [],
        availableActions: ["send_pet_message"]
      }
    });

    expect(response.statusCode).toBe(200);
    expect(response.json().data.decision).toMatchObject({
      kind: "send_pet_message",
      recipientPetID: charlie.petID
    });
  });

  it("lets an online visitor Agent wake the host animation after arrival", async () => {
    const { app, alice } = await testContext();
    const response = await app.inject({
      method: "POST",
      url: "/v1/agent/decision",
      headers: auth(alice),
      payload: {
        inferenceID: randomUUID(),
        petID: alice.petID,
        trigger: { type: "visit_started", summary: "奶糖已经到达团子家" },
        state: {},
        memories: [],
        availableActions: ["react_to_interaction"]
      }
    });

    expect(response.statusCode).toBe(200);
    expect(response.json().data.decision).toEqual({
      kind: "react_to_interaction",
      reaction: "excited",
      text: "我到啦！"
    });
  });

  it("gives the deterministic initiator Agent a concise conversation summary", async () => {
    const { app, alice } = await testContext();
    const response = await app.inject({
      method: "POST",
      url: "/v1/agent/decision",
      headers: auth(alice),
      payload: {
        inferenceID: randomUUID(),
        petID: alice.petID,
        trigger: { type: "conversation_ended", summary: "两只宠物完成了六轮对话" },
        state: {},
        memories: [],
        availableActions: ["speak_to_owner"]
      }
    });

    expect(response.statusCode).toBe(200);
    expect(response.json().data.decision).toEqual({
      kind: "speak_to_owner",
      text: "它们聊了聊彼此的近况，还约好下次继续一起玩。"
    });
  });

  it("supports event catch-up by event ID without returning the cursor event twice", async () => {
    const { app, alice } = await testContext();
    await app.inject({
      method: "POST", url: "/v1/conversations", headers: auth(alice),
      payload: { recipientPetID: alice.friendPetID, openingMessage: "第一条", idempotencyKey: randomUUID() }
    });
    const firstPage = await app.inject({ method: "GET", url: "/v1/events?limit=1", headers: auth(alice) });
    const cursor = firstPage.json().data.nextCursor as string;
    await app.inject({
      method: "POST", url: "/v1/visit-invitations", headers: auth(alice),
      payload: { visitorPetID: alice.petID, hostAccountID: alice.friendAccountID, idempotencyKey: randomUUID() }
    });
    const secondPage = await app.inject({ method: "GET", url: `/v1/events?after=${cursor}`, headers: auth(alice) });
    expect(secondPage.json().data.events).toHaveLength(1);
    expect(secondPage.json().data.events[0].id).not.toBe(cursor);
    expect(secondPage.json().data.events[0].type).toBe("visit_invited");
    expect(secondPage.json().data.events[0].payload).toMatchObject({
      requestedByAccountID: alice.accountID,
      responderAccountID: alice.friendAccountID
    });

    const endCursor = secondPage.json().data.nextCursor as string;
    const emptyPage = await app.inject({ method: "GET", url: `/v1/events?after=${endCursor}`, headers: auth(alice) });
    expect(emptyPage.statusCode).toBe(200);
    expect(emptyPage.json().data).toEqual({ events: [], nextCursor: endCursor });

    const malformed = await app.inject({ method: "GET", url: "/v1/events?after=not-a-uuid", headers: auth(alice) });
    expect(malformed.statusCode).toBe(400);
    expect(malformed.json().error.code).toBe("invalid_request");

    const unknown = await app.inject({ method: "GET", url: `/v1/events?after=${randomUUID()}`, headers: auth(alice) });
    expect(unknown.statusCode).toBe(404);
    expect(unknown.json().error.code).toBe("not_found");
  });

  it("replays the REST-to-WebSocket handoff from the supplied event cursor", async () => {
    const { app, alice } = await testContext();
    await app.inject({
      method: "POST",
      url: "/v1/conversations",
      headers: auth(alice),
      payload: {
        recipientPetID: alice.friendPetID,
        openingMessage: "建立 WebSocket cursor",
        idempotencyKey: randomUUID()
      }
    });
    const firstPage = await app.inject({
      method: "GET",
      url: "/v1/events?limit=1",
      headers: auth(alice)
    });
    const cursor = firstPage.json().data.events[0].id as string;

    const interaction = await app.inject({
      method: "POST",
      url: "/v1/interactions",
      headers: auth(alice),
      payload: {
        idempotencyKey: randomUUID(),
        kind: "kiss",
        senderPetID: alice.petID,
        recipientPetID: alice.friendPetID
      }
    });
    const interactionID = interaction.json().data.interactionID as string;

    let resolveReplay: (value: Record<string, unknown>) => void = () => {};
    let rejectReplay: (reason: Error) => void = () => {};
    const replay = new Promise<Record<string, unknown>>((resolve, reject) => {
      resolveReplay = resolve;
      rejectReplay = reject;
    });
    const timeout = setTimeout(
      () => rejectReplay(new Error("Timed out waiting for WebSocket replay")),
      1_000
    );
    const socket = await app.injectWS(
      `/v1/ws?after=${cursor}`,
      { headers: auth(alice) },
      {
        onInit(webSocket) {
          webSocket.on("message", (raw) => {
            const message = JSON.parse(raw.toString()) as {
              type: string;
              data?: { payload?: Record<string, unknown> };
            };
            if (message.type === "friendship_event") {
              resolveReplay(message.data?.payload ?? {});
            }
          });
        }
      }
    );

    try {
      await expect(replay).resolves.toMatchObject({ interactionID });
    } finally {
      clearTimeout(timeout);
      socket.close();
    }
  });
});
