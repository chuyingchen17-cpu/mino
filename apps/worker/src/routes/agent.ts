import { createRoute, type OpenAPIHono } from "@hono/zod-openapi";
import { requireAuthContext, type AppHonoEnv } from "../auth/middleware";
import { decideModelAction } from "../application/model-decisions";
import { badRequest } from "../errors";
import { listFriendships } from "../storage/friendships-repository";
import { commonErrors, dataSchema, identifierSchema, uuidSchema, z } from "./schemas";

const triggerTypeSchema = z.enum([
  "owner_message", "owner_interaction", "remote_human_message", "pet_message",
  "conversation_ended", "visit_invitation", "visit_interaction", "visit_started",
  "visit_ended", "sealed_human_letter_available", "periodic_wake"
]);
const requestSchema = z.object({
  inferenceID: uuidSchema,
  petID: identifierSchema,
  trigger: z.object({ type: triggerTypeSchema, summary: z.string().max(1_000) }).strict(),
  state: z.object({
    location: z.enum(["home", "visiting"]).optional(),
    visitID: identifierSchema.optional(),
    emotion: z.enum(["content", "happy", "shy"]).optional(),
    autonomousSocialEnabled: z.boolean().optional(),
    ownerAccountID: identifierSchema.optional(),
    friendshipID: identifierSchema.optional(),
    friendPetIDs: z.array(identifierSchema).max(100).optional(),
    targetPetID: identifierSchema.optional(),
    invitationID: identifierSchema.optional(),
    senderPetID: identifierSchema.optional(),
    currentEventVisitID: identifierSchema.optional(),
    ownerPresence: z.enum(["unknown", "present", "away"]).optional(),
    ownerActivity: z.enum(["idle", "listening_to_music"]).optional(),
    companionPresent: z.boolean().optional(),
    careFullness: z.enum(["low", "steady", "high"]).optional(),
    careEnergy: z.enum(["low", "steady", "high"]).optional(),
    careMood: z.enum(["low", "steady", "high"]).optional()
  }).strict(),
  memories: z.array(z.object({
    summary: z.string().max(1_000),
    kind: z.enum(["owner", "friend_pet", "visit", "interaction", "general"]).optional()
  }).strict()).max(20),
  availableActions: z.array(z.enum([
    "idle", "speak_to_owner", "send_pet_message", "propose_visit", "respond_to_visit",
    "react_to_interaction", "request_return"
  ])).max(7)
}).strict();

const route = createRoute({
  method: "post", path: "/v1/agent/decision",
  request: { body: { content: { "application/json": { schema: requestSchema } } } },
  responses: { 200: { content: { "application/json": { schema: dataSchema(z.unknown()) } }, description: "Validated model decision" }, ...commonErrors }
});

export function registerAgentRoutes(app: OpenAPIHono<AppHonoEnv>): void {
  app.openapi(route, async (c) => {
    const context = await requireAuthContext(c);
    const body = c.req.valid("json");
    if (body.trigger.type === "sealed_human_letter_available" &&
      body.trigger.summary !== "sealed_human_letter_available") {
      throw badRequest("letter_content_forbidden", "Letter contents cannot enter Agent context");
    }
    const friendships = await listFriendships(c.env.DB, context, "accepted");
    const allowedPetIDs = new Set(friendships.map((friendship) => friendship.friend.pet.petID));
    if (body.state.friendPetIDs?.some((petID) => !allowedPetIDs.has(petID)) ||
      [body.state.targetPetID, body.state.senderPetID].some(
        (petID) => petID !== undefined && !allowedPetIDs.has(petID)
      )) {
      throw badRequest("invalid_agent_context", "Agent targets must be accepted friends");
    }
    return c.json({ data: await decideModelAction(c.env.DB, c.env, context, body) }, 200);
  });
}
