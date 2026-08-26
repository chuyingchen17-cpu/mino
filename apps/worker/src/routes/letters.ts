import { createRoute, type OpenAPIHono } from "@hono/zod-openapi";
import { requireAuthContext, type AppHonoEnv } from "../auth/middleware";
import { createLetter, getLetter } from "../application/letters";
import {
  commonErrors,
  completeMutation,
  dataSchema,
  idempotencyHeadersSchema,
  idempotencyKey,
  uuidSchema,
  z
} from "./schemas";

const createRouteDefinition = createRoute({
  method: "post", path: "/v1/visits/{visitID}/letters",
  request: {
    headers: idempotencyHeadersSchema,
    params: z.object({ visitID: uuidSchema }),
    body: { content: { "application/json": { schema: z.object({ body: z.string().trim().min(1).max(2_000) }).strict() } } }
  },
  responses: { 201: { content: { "application/json": { schema: dataSchema(z.unknown()) } }, description: "Encrypted letter attached" }, ...commonErrors }
});
const getRoute = createRoute({
  method: "get", path: "/v1/letters/{letterID}",
  request: { params: z.object({ letterID: uuidSchema }) },
  responses: { 200: { content: { "application/json": { schema: dataSchema(z.unknown()) } }, description: "Authorized letter plaintext" }, ...commonErrors }
});

export function registerLetterRoutes(app: OpenAPIHono<AppHonoEnv>): void {
  app.openapi(createRouteDefinition, async (c) => {
    const context = await requireAuthContext(c);
    const result = await createLetter(
      c.env.DB, context, c.req.valid("param").visitID, c.req.valid("json").body,
      idempotencyKey(c.req.valid("header")), c.env.LETTER_ENCRYPTION_KEY_V1
    );
    return completeMutation(c, result) as never;
  });
  app.openapi(getRoute, async (c) => {
    const context = await requireAuthContext(c);
    return c.json({ data: await getLetter(
      c.env.DB, context, c.req.valid("param").letterID, c.env.LETTER_ENCRYPTION_KEY_V1
    ) }, 200);
  });
}
