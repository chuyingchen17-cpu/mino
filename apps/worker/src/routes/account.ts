import { createRoute, type OpenAPIHono } from "@hono/zod-openapi";
import { requireAuthContext, type AppHonoEnv } from "../auth/middleware";
import { claimAgentDevice } from "../application/devices";
import {
  PET_APPEARANCE_CATALOG_VERSION,
  PET_APPEARANCE_SCHEMA_VERSION,
  PET_CHARACTER_BODIES,
  PET_CHARACTER_RIG_ID,
  updatePetAppearance
} from "../application/pets";
import { currentAccount, updateProfile } from "../storage/accounts-repository";
import {
  commonErrors,
  completeMutation,
  dataSchema,
  idempotencyHeadersSchema,
  idempotencyKey,
  uuidSchema,
  z
} from "./schemas";

const meRoute = createRoute({
  method: "get", path: "/v1/me",
  responses: { 200: { content: { "application/json": { schema: dataSchema(z.unknown()) } }, description: "Current account" }, ...commonErrors }
});
const profileRoute = createRoute({
  method: "get", path: "/v1/me/profile",
  responses: { 200: { content: { "application/json": { schema: dataSchema(z.unknown()) } }, description: "Current profile" }, ...commonErrors }
});
const updateProfileRoute = createRoute({
  method: "patch", path: "/v1/me/profile",
  request: { body: { content: { "application/json": { schema: z.object({
    accountName: z.string().trim().min(1).max(40),
    petName: z.string().trim().min(1).max(24)
  }).strict() } } } },
  responses: { 200: { content: { "application/json": { schema: dataSchema(z.unknown()) } }, description: "Updated profile" }, ...commonErrors }
});
const updatePetRoute = createRoute({
  method: "patch", path: "/v1/me/pet",
  request: {
    headers: idempotencyHeadersSchema,
    body: { content: { "application/json": { schema: z.object({
      appearanceSchemaVersion: z.literal(PET_APPEARANCE_SCHEMA_VERSION),
      appearanceCatalogVersion: z.literal(PET_APPEARANCE_CATALOG_VERSION),
      appearance: z.object({
        rigID: z.literal(PET_CHARACTER_RIG_ID),
        body: z.enum(PET_CHARACTER_BODIES)
      }).strict()
    }).strict() } } }
  },
  responses: { 200: { content: { "application/json": { schema: dataSchema(z.unknown()) } }, description: "Selected the permanent pet character, or replayed the same selection" }, ...commonErrors }
});
const claimRoute = createRoute({
  method: "post", path: "/v1/devices/{deviceID}/claim-agent",
  request: { headers: idempotencyHeadersSchema, params: z.object({ deviceID: uuidSchema }) },
  responses: { 200: { content: { "application/json": { schema: dataSchema(z.unknown()) } }, description: "Primary Agent device claimed" }, ...commonErrors }
});

function profilePayload(value: Awaited<ReturnType<typeof currentAccount>>) {
  return {
    accountID: value.account.id,
    petID: value.pet.petID,
    accountName: value.account.displayName,
    petName: value.pet.displayName,
    createdAt: value.account.createdAt,
    account: value.account,
    pet: value.pet
  };
}

export function registerAccountRoutes(app: OpenAPIHono<AppHonoEnv>): void {
  app.openapi(meRoute, async (c) => {
    const context = await requireAuthContext(c);
    return c.json({ data: { ...context, ...(await currentAccount(c.env.DB, context)) } }, 200);
  });
  app.openapi(profileRoute, async (c) => {
    const context = await requireAuthContext(c);
    return c.json({ data: profilePayload(await currentAccount(c.env.DB, context)) }, 200);
  });
  app.openapi(updateProfileRoute, async (c) => {
    const context = await requireAuthContext(c);
    return c.json({ data: profilePayload(await updateProfile(c.env.DB, context, c.req.valid("json"))) }, 200);
  });
  app.openapi(updatePetRoute, async (c) => {
    const context = await requireAuthContext(c);
    const result = await updatePetAppearance(
      c.env.DB, context, c.req.valid("json"), idempotencyKey(c.req.valid("header"))
    );
    return completeMutation(c, result) as never;
  });
  app.openapi(claimRoute, async (c) => {
    const context = await requireAuthContext(c);
    const result = await claimAgentDevice(
      c.env.DB, context, c.req.valid("param").deviceID, idempotencyKey(c.req.valid("header"))
    );
    return completeMutation(c, result) as never;
  });
}
