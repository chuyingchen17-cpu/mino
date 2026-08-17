import websocket from "@fastify/websocket";
import Fastify, { type FastifyInstance, type FastifyReply, type FastifyRequest } from "fastify";
import { z, ZodError } from "zod";
import type { AppConfig } from "./config.js";
import type { AuthContext, MutationResult, PetDecisionRequest, Visit } from "./domain.js";
import { AppError, badRequest, conflict, unauthorized } from "./errors.js";
import { EventHub } from "./events/hub.js";
import { ModelDecisionService } from "./model/service.js";
import type { MinoStore } from "./store.js";

export interface AppDependencies {
  config: AppConfig;
  store: MinoStore;
  modelService: ModelDecisionService;
  eventHub?: EventHub;
}

const idempotencyKeySchema = z.string().uuid();
const identifierSchema = z.string().min(1).max(128);
const textSchema = z.string().trim().min(1).max(500);

const agentTriggerTypeSchema = z.enum([
  "owner_message", "owner_interaction", "remote_human_message", "pet_message",
  "conversation_ended", "visit_invitation", "visit_interaction", "visit_started",
  "visit_ended", "sealed_human_letter_available", "periodic_wake"
]);

const agentStateSchema = z.object({
  location: z.enum(["home", "visiting"]).optional(),
  visitID: identifierSchema.optional(),
  emotion: z.enum(["content", "happy", "shy"]).optional(),
  autonomousSocialEnabled: z.boolean().optional(),
  ownerAccountID: identifierSchema.optional(),
  friendshipID: identifierSchema.optional(),
  friendPetIDs: z.array(identifierSchema).max(100).refine(
    (petIDs) => new Set(petIDs).size === petIDs.length,
    "Friend pet IDs must be unique"
  ).optional(),
  targetPetID: identifierSchema.optional(),
  invitationID: identifierSchema.optional(),
  senderPetID: identifierSchema.optional(),
  currentEventVisitID: identifierSchema.optional()
}).strict();

const agentDecisionRequestSchema = z.object({
  inferenceID: identifierSchema,
  petID: identifierSchema,
  trigger: z.object({ type: agentTriggerTypeSchema, summary: z.string().max(1000) }).strict(),
  state: agentStateSchema,
  memories: z.array(z.object({
    summary: z.string().max(1000),
    kind: z.enum(["owner", "friend_pet", "visit", "interaction", "general"]).optional()
  }).strict()).max(20),
  availableActions: z.array(z.enum([
    "idle", "speak_to_owner", "send_pet_message", "propose_visit", "respond_to_visit",
    "react_to_interaction", "request_return"
  ])).max(7)
}).strict();

function bearerToken(request: FastifyRequest): string | null {
  const authorization = request.headers.authorization;
  if (!authorization?.startsWith("Bearer ")) return null;
  const token = authorization.slice(7).trim();
  return token.length > 0 ? token : null;
}

async function requireAuth(store: MinoStore, request: FastifyRequest, allowQueryToken: boolean): Promise<AuthContext> {
  let token = bearerToken(request);
  if (!token && allowQueryToken) {
    const query = request.query as { token?: unknown };
    if (typeof query.token === "string") token = query.token;
  }
  if (!token) throw unauthorized();
  const context = await store.authenticate(token);
  if (!context) throw unauthorized();
  return context;
}

async function requireFriendshipID(store: MinoStore, context: AuthContext, request: FastifyRequest): Promise<string> {
  const parameters = request.params as { friendshipID?: unknown };
  if (typeof parameters.friendshipID === "string" && parameters.friendshipID.length > 0) return parameters.friendshipID;
  const query = request.query as { friendshipID?: unknown };
  if (typeof query.friendshipID === "string" && query.friendshipID.length > 0) return query.friendshipID;
  return store.resolveSingleAcceptedFriendship(context);
}

function parse<T>(schema: z.ZodType<T>, input: unknown): T {
  const result = schema.safeParse(input);
  if (!result.success) {
    throw badRequest("invalid_request", result.error.issues.map((issue) => `${issue.path.join(".")}: ${issue.message}`).join("; "));
  }
  return result.data;
}

function containsLetterBodyField(value: unknown): boolean {
  if (Array.isArray(value)) return value.some(containsLetterBodyField);
  if (typeof value !== "object" || value === null) return false;
  return Object.entries(value as Record<string, unknown>).some(([key, child]) => {
    const normalized = key.toLowerCase().replace(/[^a-z]/g, "");
    const letterBearingKey = normalized.includes("letter") &&
      !normalized.endsWith("id") &&
      !normalized.endsWith("status");
    return letterBearingKey ||
      containsLetterBodyField(child);
  });
}

function containsForbiddenLetterContext(value: unknown): boolean {
  if (typeof value !== "object" || value === null || Array.isArray(value)) return false;
  const request = value as Record<string, unknown>;
  if (containsLetterBodyField(request.state)) return true;

  const trigger = request.trigger;
  if (typeof trigger === "object" && trigger !== null && !Array.isArray(trigger)) {
    const fields = trigger as Record<string, unknown>;
    if (typeof fields.type === "string" && /letter/i.test(fields.type)) {
      return fields.type !== "sealed_human_letter_available" ||
        fields.summary !== "sealed_human_letter_available";
    }
  }

  return Array.isArray(request.memories) && request.memories.some((memory) => {
    if (typeof memory !== "object" || memory === null || Array.isArray(memory)) return false;
    const kind = (memory as Record<string, unknown>).kind;
    return typeof kind === "string" && /letter/i.test(kind);
  });
}

function publish<T>(hub: EventHub, result: MutationResult<T>): T {
  hub.publish(result.events);
  return result.data;
}

function invitationEnvelope(visit: Visit): Record<string, unknown> {
  const responderAccountID = visit.requestedByAccountID === visit.visitorOwnerAccountID
    ? visit.hostAccountID
    : visit.visitorOwnerAccountID;
  return {
    id: visit.id,
    friendshipID: visit.friendshipID,
    inviterAccountID: visit.requestedByAccountID,
    invitedAccountID: responderAccountID,
    requestedPetID: visit.visitorPetID,
    hostAccountID: visit.hostAccountID,
    status: visit.status === "cancelled" ? "declined" : visit.status === "active" ? "accepted" : visit.status,
    createdAt: visit.createdAt,
    respondedAt: visit.startedAt ?? visit.endedAt
  };
}

function legacyVisit(visit: Visit): Record<string, unknown> {
  return {
    id: visit.id,
    friendshipID: visit.friendshipID,
    petID: visit.visitorPetID,
    ownerAccountID: visit.visitorOwnerAccountID,
    hostAccountID: visit.hostAccountID,
    phase: visit.status === "active" ? "visiting" : visit.status === "ended" ? "completed" : "cancelled",
    outboundCargo: [],
    returnCargo: [],
    revision: 1,
    departedAt: visit.startedAt ?? visit.createdAt,
    arrivedAt: visit.startedAt,
    returnStartedAt: visit.endedAt,
    completedAt: visit.endedAt
  };
}

function registerRoutes(app: FastifyInstance, dependencies: AppDependencies, prefix: "" | "/v1"): void {
  const { config, store, modelService } = dependencies;
  const hub = dependencies.eventHub ?? new EventHub();
  const route = (path: string): string => `${prefix}${path}`;

  app.get(route("/health"), async () => ({ data: { status: "healthy", apiVersion: "0.1.0" } }));

  app.post(route("/dev/bootstrap"), async (request) => {
    if (!config.devBootstrapEnabled || config.nodeEnv === "production") {
      throw new AppError(404, "not_found", "Development bootstrap is disabled");
    }
    const body = parse(z.object({ profile: z.enum(["alice", "bob", "charlie"]) }).strict(), request.body);
    const profiles = await store.bootstrapDevProfiles();
    return { data: profiles[body.profile] };
  });

  app.get(route("/me"), async (request) => {
    const context = await requireAuth(store, request, false);
    return { data: context };
  });

  app.get(route("/friendships"), async (request) => {
    const context = await requireAuth(store, request, false);
    const query = parse(z.object({
      status: z.enum(["pending", "accepted", "rejected"]).optional()
    }).strict(), request.query);
    return { data: await store.listFriendships(context, query.status) };
  });

  app.post(route("/friendships"), async (request) => {
    const context = await requireAuth(store, request, false);
    const body = parse(z.object({
      addresseeAccountID: identifierSchema,
      idempotencyKey: idempotencyKeySchema
    }).strict(), request.body);
    return { data: await store.requestFriendship(context, body) };
  });

  app.post(route("/friendships/:friendshipID/respond"), async (request) => {
    const context = await requireAuth(store, request, false);
    const parameters = parse(z.object({ friendshipID: identifierSchema }), request.params);
    const body = parse(z.object({
      response: z.enum(["accept", "reject"]),
      idempotencyKey: idempotencyKeySchema
    }).strict(), request.body);
    return { data: await store.respondFriendship(context, parameters.friendshipID, body) };
  });

  app.get(route("/events"), async (request) => {
    const context = await requireAuth(store, request, false);
    const query = parse(z.object({
      friendshipID: identifierSchema.optional(),
      after: z.string().uuid().optional(),
      limit: z.coerce.number().int().min(1).max(200).default(100)
    }).strict(), request.query);
    const friendshipID = query.friendshipID ?? await store.resolveSingleAcceptedFriendship(context);
    return { data: await store.getEvents(context, friendshipID, query.after, query.limit ?? 100) };
  });

  app.get(route("/timeline"), async (request) => {
    const context = await requireAuth(store, request, false);
    const query = parse(z.object({
      friendshipID: identifierSchema.optional(),
      after: z.string().uuid().optional(),
      limit: z.coerce.number().int().min(1).max(200).default(100)
    }).strict(), request.query);
    const friendshipID = query.friendshipID ?? await store.resolveSingleAcceptedFriendship(context);
    return { data: await store.getEvents(context, friendshipID, query.after, query.limit ?? 100, true) };
  });

  const legacyTimelineHandler = async (request: FastifyRequest) => {
    const context = await requireAuth(store, request, false);
    const query = parse(z.object({
      friendshipID: identifierSchema.optional(),
      after: z.string().uuid().optional()
    }).strict(), request.query);
    const friendshipID = query.friendshipID ?? await store.resolveSingleAcceptedFriendship(context);
    const page = await store.getEvents(context, friendshipID, query.after, 100, true);
    return {
      data: {
        events: page.events.map((event) => ({
          id: event.id,
          kind: event.type,
          occurredAt: event.occurredAt,
          petID: event.payload.visitorPetID ?? event.payload.petID ?? null,
          visitID: event.payload.visitID ?? null,
          invitationID: event.payload.visitID ?? null,
          actorAccountID: event.actorType === "human" ? event.actorID : null,
          interactionKind: event.payload.kind ?? null,
          cargoItems: [],
          postcard: null,
          summary: event.payload.summary ?? null
        })),
        nextCursor: page.nextCursor
      }
    };
  };
  app.get(route("/friendship-events"), legacyTimelineHandler);

  app.get(route("/pet-presence"), async (request) => {
    const context = await requireAuth(store, request, false);
    const friendshipID = await requireFriendshipID(store, context, request);
    const presence = await store.getPresence(context, friendshipID);
    return {
      data: {
        ...presence,
        activeVisits: presence.activeVisits.map(legacyVisit)
      }
    };
  });

  app.post(route("/agent/decision"), async (request) => {
    const context = await requireAuth(store, request, false);
    if (containsForbiddenLetterContext(request.body)) {
      throw badRequest("letter_content_forbidden", "Human letter content cannot be sent to the pet model");
    }
    const body = parse(agentDecisionRequestSchema, request.body) as PetDecisionRequest;
    if (body.petID !== context.petID || (body.state.ownerAccountID && body.state.ownerAccountID !== context.accountID)) {
      throw badRequest("invalid_agent_context", "Agent state does not match the authenticated pet context");
    }
    if (
      body.state.friendshipID ||
      body.state.targetPetID ||
      body.state.senderPetID ||
      body.state.friendPetIDs !== undefined
    ) {
      const friendships = await store.listFriendships(context, "accepted");
      const acceptedFriendPetIDs = new Set(friendships.map((friendship) => friendship.friend.petID));
      if (body.state.friendPetIDs?.some((petID) => !acceptedFriendPetIDs.has(petID))) {
        throw badRequest("invalid_agent_context", "Agent friend whitelist contains a pet outside accepted friendships");
      }
      if (
        body.state.friendPetIDs !== undefined &&
        [body.state.targetPetID, body.state.senderPetID].some(
          (petID) => petID !== undefined && !body.state.friendPetIDs!.includes(petID)
        )
      ) {
        throw badRequest("invalid_agent_context", "Agent event target is outside the supplied friend whitelist");
      }
      const eventContext = friendships.find((friendship) =>
        (!body.state.friendshipID || friendship.id === body.state.friendshipID) &&
        (!body.state.targetPetID || friendship.friend.petID === body.state.targetPetID) &&
        (!body.state.senderPetID || friendship.friend.petID === body.state.senderPetID)
      );
      if (
        (body.state.friendshipID || body.state.targetPetID || body.state.senderPetID) &&
        !eventContext
      ) {
        throw badRequest("invalid_agent_context", "Agent target is not an accepted friend");
      }
    }
    return { data: await modelService.decide(context, body) };
  });

  app.post(route("/interactions"), async (request) => {
    const context = await requireAuth(store, request, false);
    const friendshipID = await requireFriendshipID(store, context, request);
    const body = parse(z.object({
      idempotencyKey: idempotencyKeySchema,
      kind: z.enum(["kiss", "flower_gift", "walk"]),
      senderPetID: identifierSchema,
      recipientPetID: identifierSchema,
      clientCreatedAt: z.string().datetime().optional()
    }).strict(), request.body);
    const result = await store.recordLegacyInteraction(context, friendshipID, body);
    const data = publish(hub, result);
    return { data: { interactionID: data.interactionID, acceptedAt: data.acceptedAt } };
  });

  app.get(route("/conversations"), async (request) => {
    const context = await requireAuth(store, request, false);
    const query = parse(z.object({
      friendshipID: identifierSchema.optional(),
      status: z.literal("active").default("active")
    }).strict(), request.query);
    const friendshipID = query.friendshipID ?? await store.resolveSingleAcceptedFriendship(context);
    return { data: await store.listConversations(context, friendshipID, query.status ?? "active") };
  });

  app.post(route("/conversations"), async (request) => {
    const context = await requireAuth(store, request, false);
    const friendshipID = await requireFriendshipID(store, context, request);
    const body = parse(z.object({
      recipientPetID: identifierSchema,
      openingMessage: textSchema,
      idempotencyKey: idempotencyKeySchema
    }).strict(), request.body);
    return { data: publish(hub, await store.createConversation(context, friendshipID, body)) };
  });

  app.get(route("/conversations/:conversationID/messages"), async (request) => {
    const context = await requireAuth(store, request, false);
    const friendshipID = await requireFriendshipID(store, context, request);
    const parameters = parse(z.object({ conversationID: identifierSchema }), request.params);
    return { data: await store.getConversationMessages(context, friendshipID, parameters.conversationID) };
  });

  app.post(route("/conversations/:conversationID/messages"), async (request) => {
    const context = await requireAuth(store, request, false);
    const friendshipID = await requireFriendshipID(store, context, request);
    const parameters = parse(z.object({ conversationID: identifierSchema }), request.params);
    const body = parse(z.object({
      actorType: z.enum(["human", "pet"]),
      text: textSchema,
      idempotencyKey: idempotencyKeySchema
    }).strict(), request.body);
    return { data: publish(hub, await store.addConversationMessage(context, friendshipID, parameters.conversationID, body)) };
  });

  app.post(route("/conversations/:conversationID/end"), async (request) => {
    const context = await requireAuth(store, request, false);
    const friendshipID = await requireFriendshipID(store, context, request);
    const parameters = parse(z.object({ conversationID: identifierSchema }), request.params);
    const body = parse(z.object({
      summary: z.string().trim().min(1).max(500),
      idempotencyKey: idempotencyKeySchema
    }).strict(), request.body);
    return { data: publish(hub, await store.endConversation(context, friendshipID, parameters.conversationID, body)) };
  });

  app.get(route("/visit-invitations"), async (request) => {
    const context = await requireAuth(store, request, false);
    const query = parse(z.object({
      friendshipID: identifierSchema.optional(),
      status: z.enum(["pending", "active", "ended", "cancelled"]).optional()
    }).strict(), request.query);
    const friendshipID = query.friendshipID ?? await store.resolveSingleAcceptedFriendship(context);
    return { data: await store.listVisitInvitations(context, friendshipID, query.status) };
  });

  app.post(route("/visit-invitations"), async (request) => {
    const context = await requireAuth(store, request, false);
    const friendshipID = await requireFriendshipID(store, context, request);
    const body = parse(z.object({
      visitorPetID: identifierSchema,
      hostAccountID: identifierSchema,
      reason: z.string().trim().min(1).max(240).optional(),
      idempotencyKey: idempotencyKeySchema
    }).strict(), request.body);
    return { data: publish(hub, await store.createVisitInvitation(context, friendshipID, {
      visitorPetID: body.visitorPetID,
      hostAccountID: body.hostAccountID,
      idempotencyKey: body.idempotencyKey,
      ...(body.reason ? { reason: body.reason } : {})
    })) };
  });

  app.post(route("/visit-invitations/:visitID/respond"), async (request) => {
    const context = await requireAuth(store, request, false);
    const friendshipID = await requireFriendshipID(store, context, request);
    const parameters = parse(z.object({ visitID: identifierSchema }), request.params);
    const body = parse(z.object({
      response: z.enum(["accept", "decline"]),
      idempotencyKey: idempotencyKeySchema
    }).strict(), request.body);
    return { data: publish(hub, await store.respondVisitInvitation(context, friendshipID, parameters.visitID, body)) };
  });

  app.post(route("/visits/:visitID/interactions"), async (request) => {
    const context = await requireAuth(store, request, false);
    const friendshipID = await requireFriendshipID(store, context, request);
    const parameters = parse(z.object({ visitID: identifierSchema }), request.params);
    const body = parse(z.object({
      kind: z.enum(["feed", "play", "message"]),
      text: z.string().trim().min(1).max(500).optional(),
      idempotencyKey: idempotencyKeySchema
    }).strict().superRefine((value, refinement) => {
      if (value.kind === "message" && !value.text) {
        refinement.addIssue({ code: z.ZodIssueCode.custom, path: ["text"], message: "A message interaction requires text" });
      }
    }), request.body);
    return { data: publish(hub, await store.addVisitInteraction(context, friendshipID, parameters.visitID, {
      kind: body.kind,
      idempotencyKey: body.idempotencyKey,
      ...(body.text ? { text: body.text } : {})
    })) };
  });

  app.post(route("/visits/:visitID/reactions"), async (request) => {
    const context = await requireAuth(store, request, false);
    const friendshipID = await requireFriendshipID(store, context, request);
    const parameters = parse(z.object({ visitID: identifierSchema }), request.params);
    const body = parse(z.object({
      reaction: z.string().trim().min(1).max(80),
      text: z.string().trim().min(1).max(500).optional(),
      idempotencyKey: idempotencyKeySchema
    }).strict(), request.body);
    return { data: publish(hub, await store.addVisitReaction(context, friendshipID, parameters.visitID, {
      reaction: body.reaction,
      idempotencyKey: body.idempotencyKey,
      ...(body.text ? { text: body.text } : {})
    })) };
  });

  app.post(route("/visits/:visitID/letter"), async (request) => {
    const context = await requireAuth(store, request, false);
    const friendshipID = await requireFriendshipID(store, context, request);
    const parameters = parse(z.object({ visitID: identifierSchema }), request.params);
    const body = parse(z.object({ body: z.string().trim().min(1).max(2_000), idempotencyKey: idempotencyKeySchema }).strict(), request.body);
    return { data: publish(hub, await store.createVisitLetter(context, friendshipID, parameters.visitID, body)) };
  });

  app.get(route("/letters/:letterID"), async (request) => {
    const context = await requireAuth(store, request, false);
    const friendshipID = await requireFriendshipID(store, context, request);
    const parameters = parse(z.object({ letterID: identifierSchema }), request.params);
    return { data: await store.getLetter(context, friendshipID, parameters.letterID) };
  });

  app.post(route("/visits/:visitID/end"), async (request) => {
    const context = await requireAuth(store, request, false);
    const friendshipID = await requireFriendshipID(store, context, request);
    const parameters = parse(z.object({ visitID: identifierSchema }), request.params);
    const body = parse(z.object({ idempotencyKey: idempotencyKeySchema }).strict(), request.body);
    return { data: publish(hub, await store.endVisit(context, friendshipID, parameters.visitID, body)) };
  });

  // Compatibility aliases for the initial macOS contract.
  app.get(route("/pet-visit-invitations"), async (request) => {
    const context = await requireAuth(store, request, false);
    const query = parse(z.object({
      friendshipID: identifierSchema.optional(),
      status: z.enum(["pending", "accepted", "declined", "cancelled", "expired"]).optional()
    }).strict(), request.query);
    const friendshipID = query.friendshipID ?? await store.resolveSingleAcceptedFriendship(context);
    const status = query.status === "accepted" ? "active" : query.status === "declined" ? "cancelled" : query.status;
    const visits = await store.listVisitInvitations(context, friendshipID, status);
    return { data: visits.map(invitationEnvelope) };
  });

  app.post(route("/pet-visit-invitations"), async (request) => {
    const context = await requireAuth(store, request, false);
    const friendshipID = await requireFriendshipID(store, context, request);
    const body = parse(z.object({
      idempotencyKey: idempotencyKeySchema,
      requestedPetID: identifierSchema,
      clientCreatedAt: z.string().datetime().optional()
    }).strict(), request.body);
    const visit = publish(hub, await store.createVisitInvitation(context, friendshipID, {
      visitorPetID: body.requestedPetID,
      hostAccountID: context.accountID,
      idempotencyKey: body.idempotencyKey
    }));
    return { data: invitationEnvelope(visit) };
  });

  app.post(route("/pet-visit-invitations/:invitationID/response"), async (request) => {
    const context = await requireAuth(store, request, false);
    const friendshipID = await requireFriendshipID(store, context, request);
    const parameters = parse(z.object({ invitationID: identifierSchema }), request.params);
    const body = parse(z.object({
      idempotencyKey: idempotencyKeySchema,
      invitationID: identifierSchema.optional(),
      response: z.enum(["accept", "decline"]),
      expectedPresenceRevision: z.number().int().min(0).optional(),
      clientCreatedAt: z.string().datetime().optional()
    }).strict(), request.body);
    const visit = publish(hub, await store.respondVisitInvitation(context, friendshipID, parameters.invitationID, body));
    const presence = await store.getPresence(context, friendshipID);
    return {
      data: {
        invitation: invitationEnvelope(visit),
        visit: body.response === "accept" ? legacyVisit(visit) : null,
        presence: body.response === "accept" ? presence.pets.find((pet) => pet.petID === visit.visitorPetID) ?? null : null,
        acceptedAt: new Date().toISOString()
      }
    };
  });

  app.post(route("/pet-visits"), async (request) => {
    await requireAuth(store, request, false);
    throw conflict(
      "visit_invitation_required",
      "Direct visits are deprecated; create an invitation and let the other account respond"
    );
  });

  app.post(route("/pet-visits/:visitID/return"), async (request) => {
    const context = await requireAuth(store, request, false);
    const friendshipID = await requireFriendshipID(store, context, request);
    const parameters = parse(z.object({ visitID: identifierSchema }), request.params);
    const body = parse(z.object({
      idempotencyKey: idempotencyKeySchema,
      visitID: identifierSchema.optional(),
      returnCargo: z.array(z.unknown()).default([]),
      expectedVisitRevision: z.number().int().min(0).optional(),
      clientCreatedAt: z.string().datetime().optional()
    }).strict(), request.body);
    const ended = publish(hub, await store.endVisit(context, friendshipID, parameters.visitID, body));
    const presence = await store.getPresence(context, friendshipID);
    return {
      data: {
        visit: legacyVisit(ended.visit),
        presence: presence.pets.find((pet) => pet.petID === ended.visit.visitorPetID),
        acceptedAt: new Date().toISOString()
      }
    };
  });

  app.get(route("/ws"), { websocket: true }, async (socket, request) => {
    let removeSubscription: (() => void) | undefined;
    try {
      const context = await requireAuth(store, request, config.devBootstrapEnabled && config.nodeEnv !== "production");
      const query = parse(z.object({
        friendshipID: identifierSchema.optional(),
        after: z.string().uuid().optional(),
        token: z.string().min(1).optional()
      }).strict(), request.query);
      const friendshipID = query.friendshipID ?? await store.resolveSingleAcceptedFriendship(context);
      // Subscribe in a paused state before reading PostgreSQL. Events committed
      // during the catch-up window are buffered and flushed in socket order.
      const subscription = hub.add(friendshipID, socket, true);
      removeSubscription = subscription.remove;
      socket.on("close", subscription.remove);
      socket.on("error", subscription.remove);

      const presence = await store.getPresence(context, friendshipID);
      socket.send(JSON.stringify({ type: "ready", cursor: presence.serverCursor }));

      let cursor = query.after;
      const replayedEventIDs = new Set<string>();
      while (socket.readyState === socket.OPEN) {
        const page = await store.getEvents(context, friendshipID, cursor, 100);
        for (const event of page.events) {
          replayedEventIDs.add(event.id);
          socket.send(JSON.stringify({ type: "friendship_event", data: event }));
        }
        if (page.events.length === 0) break;
        const nextCursor = page.nextCursor ?? page.events.at(-1)?.id;
        if (!nextCursor || nextCursor === cursor) break;
        cursor = nextCursor;
      }
      subscription.activate(replayedEventIDs);
    } catch (error) {
      removeSubscription?.();
      const code = error instanceof AppError ? error.code : "unauthorized";
      socket.close(1008, code);
    }
  });
}

export async function buildApp(dependencies: AppDependencies): Promise<FastifyInstance> {
  const app = Fastify({
    logger: dependencies.config.nodeEnv !== "test",
    trustProxy: false,
    bodyLimit: 64 * 1024
  });
  await app.register(websocket, { options: { maxPayload: 64 * 1024 } });

  app.setErrorHandler((error: Error, _request: FastifyRequest, reply: FastifyReply) => {
    if (error instanceof AppError) {
      void reply.status(error.statusCode).send({ error: { code: error.code, message: error.message } });
      return;
    }
    if (error instanceof ZodError) {
      void reply.status(400).send({ error: { code: "invalid_request", message: error.message } });
      return;
    }
    app.log.error(error);
    void reply.status(500).send({ error: { code: "internal_error", message: "An unexpected error occurred" } });
  });

  const hub = dependencies.eventHub ?? new EventHub();
  registerRoutes(app, { ...dependencies, eventHub: hub }, "");
  registerRoutes(app, { ...dependencies, eventHub: hub }, "/v1");
  app.addHook("onClose", async () => dependencies.store.close());
  await app.ready();
  return app;
}
