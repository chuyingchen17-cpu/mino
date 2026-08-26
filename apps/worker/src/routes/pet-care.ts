import { createRoute, type OpenAPIHono } from "@hono/zod-openapi";
import { requireAuthContext, type AppHonoEnv } from "../auth/middleware";
import { getOwnPetCare, interactWithPet } from "../application/pet-care";
import {
  commonErrors,
  completeMutation,
  dataSchema,
  idempotencyHeadersSchema,
  idempotencyKey,
  identifierSchema,
  uuidSchema,
  z
} from "./schemas";

const careBandSchema = z.enum(["low", "steady", "high"]);
const careStateSchema = z.object({
  fullness: z.number().int().min(0).max(100),
  energy: z.number().int().min(0).max(100),
  mood: z.number().int().min(0).max(100),
  bond: z.number().int().min(0).max(100),
  version: z.number().int().positive(),
  evaluatedAt: z.number().int().nonnegative()
});
const publicCareSchema = z.object({
  fullness: careBandSchema,
  energy: careBandSchema,
  mood: careBandSchema
});
const familiaritySchema = z.object({
  petID: identifierSchema,
  friendshipID: uuidSchema,
  score: z.number().int().min(0).max(100),
  tier: z.enum(["first_meeting", "recognized", "familiar", "close"]),
  version: z.number().int().positive(),
  updatedAt: z.number().int().nonnegative()
});
const interactionKindSchema = z.enum(["pet", "feed", "play", "walk", "rest", "cuddle", "flower"]);
const interactionReceiptSchema = z.object({
  id: uuidSchema,
  targetPetID: identifierSchema,
  actorAccountID: uuidSchema,
  friendshipID: uuidSchema.nullable(),
  visitID: uuidSchema.nullable(),
  kind: interactionKindSchema,
  outcome: z.enum(["applied", "cosmetic_only", "too_full", "too_tired", "resting_cooldown"]),
  effect: z.object({
    fullness: z.number().int(),
    energy: z.number().int(),
    mood: z.number().int(),
    bond: z.number().int(),
    familiarity: z.number().int()
  }),
  careState: careStateSchema.nullable(),
  publicCare: publicCareSchema,
  familiarity: familiaritySchema.nullable(),
  occurredAt: z.number().int().nonnegative()
});

const stateRoute = createRoute({
  method: "get",
  path: "/v1/me/pet-state",
  responses: {
    200: { content: { "application/json": { schema: dataSchema(careStateSchema) } }, description: "Exact care state for the current account pet" },
    ...commonErrors
  }
});

const interactionRoute = createRoute({
  method: "post",
  path: "/v1/pets/{petID}/interactions",
  request: {
    headers: idempotencyHeadersSchema,
    params: z.object({ petID: identifierSchema }),
    body: { content: { "application/json": { schema: z.object({
      kind: interactionKindSchema,
      visitID: uuidSchema.optional(),
      occurredAt: z.number().int().nonnegative()
    }).strict() } } }
  },
  responses: {
    201: { content: { "application/json": { schema: dataSchema(interactionReceiptSchema) } }, description: "Immediate care interaction receipt" },
    ...commonErrors
  }
});

export function registerPetCareRoutes(app: OpenAPIHono<AppHonoEnv>): void {
  app.openapi(stateRoute, async (c) => {
    const context = await requireAuthContext(c);
    return c.json({ data: await getOwnPetCare(c.env.DB, context) }, 200);
  });
  app.openapi(interactionRoute, async (c) => {
    const context = await requireAuthContext(c);
    const body = c.req.valid("json");
    const result = await interactWithPet(
      c.env.DB,
      context,
      c.req.valid("param").petID,
      { kind: body.kind, occurredAt: body.occurredAt, ...(body.visitID ? { visitID: body.visitID } : {}) },
      idempotencyKey(c.req.valid("header"))
    );
    return completeMutation(c, result) as never;
  });
}
