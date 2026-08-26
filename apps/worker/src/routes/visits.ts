import { createRoute, type OpenAPIHono } from "@hono/zod-openapi";
import { requireAuthContext, type AppHonoEnv } from "../auth/middleware";
import { createVisitAction } from "../application/visit-actions";
import { createVisit, endVisit, respondVisit } from "../application/visits";
import { listVisits } from "../storage/visits-repository";
import {
  actorTypeSchema,
  commonErrors,
  completeMutation,
  dataSchema,
  idempotencyHeadersSchema,
  idempotencyKey,
  identifierSchema,
  uuidSchema,
  z
} from "./schemas";

const listRoute = createRoute({
  method: "get", path: "/v1/visits",
  request: { query: z.object({ status: z.enum(["pending", "active", "closed"]).optional() }) },
  responses: { 200: { content: { "application/json": { schema: dataSchema(z.array(z.unknown())) } }, description: "Account visits" }, ...commonErrors }
});
const createVisitRoute = createRoute({
  method: "post", path: "/v1/visits",
  request: {
    headers: idempotencyHeadersSchema,
    body: { content: { "application/json": { schema: z.object({
      friendshipID: uuidSchema,
      visitorPetID: identifierSchema,
      hostAccountID: identifierSchema,
      reason: z.string().trim().min(1).max(240).optional()
    }).strict() } } }
  },
  responses: { 201: { content: { "application/json": { schema: dataSchema(z.unknown()) } }, description: "Pending Visit created" }, ...commonErrors }
});
const respondRoute = createRoute({
  method: "post", path: "/v1/visits/{visitID}/respond",
  request: {
    headers: idempotencyHeadersSchema,
    params: z.object({ visitID: uuidSchema }),
    body: { content: { "application/json": { schema: z.object({
      response: z.enum(["accept", "decline"]),
      actorType: actorTypeSchema
    }).strict() } } }
  },
  responses: { 200: { content: { "application/json": { schema: dataSchema(z.unknown()) } }, description: "Visit response" }, ...commonErrors }
});
const endRoute = createRoute({
  method: "post", path: "/v1/visits/{visitID}/end",
  request: {
    headers: idempotencyHeadersSchema,
    params: z.object({ visitID: uuidSchema }),
    body: { content: { "application/json": { schema: z.object({ actorType: actorTypeSchema }).strict() } } }
  },
  responses: { 200: { content: { "application/json": { schema: dataSchema(z.unknown()) } }, description: "Convergent Visit close" }, ...commonErrors }
});

const actionBase = {
  replyToActionID: uuidSchema.optional()
};
const actionBodySchema = z.discriminatedUnion("kind", [
  z.object({ kind: z.literal("feed"), actorType: z.literal("human"), payload: z.object({ food: identifierSchema.optional() }).strict(), ...actionBase }).strict(),
  z.object({ kind: z.literal("play"), actorType: z.literal("human"), payload: z.object({ toy: identifierSchema.optional() }).strict(), ...actionBase }).strict(),
  z.object({ kind: z.literal("pet"), actorType: z.literal("human"), payload: z.object({}).strict(), ...actionBase }).strict(),
  z.object({ kind: z.literal("hug"), actorType: z.literal("human"), payload: z.object({}).strict(), ...actionBase }).strict(),
  z.object({ kind: z.literal("kiss"), actorType: z.literal("human"), payload: z.object({}).strict(), ...actionBase }).strict(),
  z.object({ kind: z.literal("flower"), actorType: z.literal("human"), payload: z.object({ color: identifierSchema.optional() }).strict(), ...actionBase }).strict(),
  z.object({ kind: z.literal("walk"), actorType: z.literal("human"), payload: z.object({ destination: z.string().max(120).optional() }).strict(), ...actionBase }).strict(),
  z.object({ kind: z.literal("message"), actorType: z.literal("human"), payload: z.object({ text: z.string().trim().min(1).max(500) }).strict(), ...actionBase }).strict(),
  z.object({
    kind: z.literal("reaction"), actorType: z.literal("pet_agent"),
    payload: z.object({
      reaction: z.enum(["happy", "excited", "shy", "sleepy", "grateful", "playful", "resting"]),
      text: z.string().trim().min(1).max(500).optional()
    }).strict(),
    ...actionBase
  }).strict(),
  z.object({
    kind: z.literal("activity"), actorType: z.literal("pet_agent"),
    payload: z.object({ activity: z.enum(["eating", "playing", "walking", "resting"]) }).strict(),
    ...actionBase
  }).strict(),
  z.object({
    kind: z.literal("speech"), actorType: z.literal("pet_agent"),
    payload: z.object({ text: z.string().trim().min(1).max(500) }).strict(),
    ...actionBase
  }).strict(),
  z.object({
    kind: z.literal("acknowledgement"), actorType: z.literal("pet_agent"),
    payload: z.object({}).strict(),
    ...actionBase
  }).strict()
]);

const actionRoute = createRoute({
  method: "post", path: "/v1/visits/{visitID}/actions",
  request: {
    headers: idempotencyHeadersSchema,
    params: z.object({ visitID: uuidSchema }),
    body: { content: { "application/json": { schema: actionBodySchema } } }
  },
  responses: { 201: { content: { "application/json": { schema: dataSchema(z.unknown()) } }, description: "Visit action created" }, ...commonErrors }
});

export function registerVisitRoutes(app: OpenAPIHono<AppHonoEnv>): void {
  app.openapi(listRoute, async (c) => {
    const context = await requireAuthContext(c);
    return c.json({ data: await listVisits(c.env.DB, context, c.req.valid("query").status) }, 200);
  });
  app.openapi(createVisitRoute, async (c) => {
    const context = await requireAuthContext(c);
    const body = c.req.valid("json");
    const result = await createVisit(c.env.DB, context, {
      friendshipID: body.friendshipID,
      visitorPetID: body.visitorPetID,
      hostAccountID: body.hostAccountID,
      ...(body.reason ? { reason: body.reason } : {})
    }, idempotencyKey(c.req.valid("header")));
    return completeMutation(c, result) as never;
  });
  app.openapi(respondRoute, async (c) => {
    const context = await requireAuthContext(c);
    const result = await respondVisit(
      c.env.DB, context, c.req.valid("param").visitID,
      c.req.valid("json"), idempotencyKey(c.req.valid("header"))
    );
    return completeMutation(c, result) as never;
  });
  app.openapi(endRoute, async (c) => {
    const context = await requireAuthContext(c);
    const result = await endVisit(
      c.env.DB, context, c.req.valid("param").visitID,
      c.req.valid("json"), idempotencyKey(c.req.valid("header"))
    );
    return completeMutation(c, result) as never;
  });
  app.openapi(actionRoute, async (c) => {
    const context = await requireAuthContext(c);
    const body = c.req.valid("json");
    const result = await createVisitAction(
      c.env.DB, context, c.req.valid("param").visitID,
      { kind: body.kind, actorType: body.actorType, payload: body.payload,
        ...(body.replyToActionID ? { replyToActionID: body.replyToActionID } : {}) },
      idempotencyKey(c.req.valid("header"))
    );
    return completeMutation(c, result) as never;
  });
}
