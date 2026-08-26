import { z } from "@hono/zod-openapi";
import type { Context } from "hono";
import type { AppHonoEnv } from "../auth/middleware";
import type { MutationResult } from "../domain/models";
import { badRequest } from "../errors";
import { notifyAccounts } from "../realtime/notifier";

export { z };

export const uuidSchema = z.uuid();
export const identifierSchema = z.string().min(1).max(128);
export const idempotencyHeadersSchema = z.object({
  "idempotency-key": uuidSchema.openapi({ description: "Stable UUID reused for safe retries" })
});

export const errorSchema = z.object({
  error: z.object({ code: z.string(), message: z.string() })
});

export const dataSchema = <T extends z.ZodType>(schema: T) => z.object({ data: schema });

export const commonErrors = {
  400: { content: { "application/json": { schema: errorSchema } }, description: "Invalid request" },
  401: { content: { "application/json": { schema: errorSchema } }, description: "Authentication required" },
  403: { content: { "application/json": { schema: errorSchema } }, description: "Forbidden" },
  404: { content: { "application/json": { schema: errorSchema } }, description: "Not found" },
  409: { content: { "application/json": { schema: errorSchema } }, description: "State or idempotency conflict" }
} as const;

export function idempotencyKey(headers: { "idempotency-key": string }): string {
  const key = headers["idempotency-key"];
  if (!key) throw badRequest("idempotency_key_required", "Idempotency-Key is required");
  return key;
}

export function completeMutation<T>(c: Context<AppHonoEnv>, result: MutationResult<T>): Response {
  if (result.notifyAccountIDs.length > 0) {
    c.executionCtx.waitUntil(notifyAccounts(c.env, result.notifyAccountIDs));
  }
  return c.json({ data: result.data }, result.status as 200 | 201);
}

export const actorTypeSchema = z.enum(["human", "pet_agent"]);

export const appearanceSchema = z.object({
  rigID: identifierSchema,
  body: identifierSchema,
  bodyColor: identifierSchema.optional(),
  pattern: identifierSchema.optional(),
  eyes: identifierSchema.optional(),
  mouth: identifierSchema.optional(),
  hair: identifierSchema.optional(),
  clothes: identifierSchema.optional(),
  hat: identifierSchema.optional(),
  glasses: identifierSchema.optional(),
  accessory: identifierSchema.optional()
}).strict();

export const deviceMetadataSchema = z.object({
  id: uuidSchema.optional(),
  displayName: z.string().trim().min(1).max(80),
  platform: z.literal("macos"),
  appVersion: z.string().trim().min(1).max(40)
}).strict();
