import { createRoute, type OpenAPIHono } from "@hono/zod-openapi";
import { requireAuthContext, type AppHonoEnv } from "../auth/middleware";
import {
  closeFriendship,
  createFriendship,
  respondFriendship
} from "../application/friendships";
import { listFriendships } from "../storage/friendships-repository";
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

const listRoute = createRoute({
  method: "get", path: "/v1/friendships",
  request: { query: z.object({ status: z.enum(["pending", "accepted", "rejected", "closed"]).optional() }) },
  responses: { 200: { content: { "application/json": { schema: dataSchema(z.array(z.unknown())) } }, description: "Friendships" }, ...commonErrors }
});
const createFriendshipRoute = createRoute({
  method: "post", path: "/v1/friendships",
  request: {
    headers: idempotencyHeadersSchema,
    body: { content: { "application/json": { schema: z.object({ addresseeAccountID: identifierSchema }).strict() } } }
  },
  responses: { 201: { content: { "application/json": { schema: dataSchema(z.unknown()) } }, description: "Friendship requested" }, ...commonErrors }
});
const respondRoute = createRoute({
  method: "post", path: "/v1/friendships/{friendshipID}/respond",
  request: {
    headers: idempotencyHeadersSchema,
    params: z.object({ friendshipID: uuidSchema }),
    body: { content: { "application/json": { schema: z.object({ response: z.enum(["accept", "reject"]) }).strict() } } }
  },
  responses: { 200: { content: { "application/json": { schema: dataSchema(z.unknown()) } }, description: "Friendship resolved" }, ...commonErrors }
});
const closeRoute = createRoute({
  method: "post", path: "/v1/friendships/{friendshipID}/close",
  request: { headers: idempotencyHeadersSchema, params: z.object({ friendshipID: uuidSchema }) },
  responses: { 200: { content: { "application/json": { schema: dataSchema(z.unknown()) } }, description: "Friendship closed" }, ...commonErrors }
});

export function registerFriendshipRoutes(app: OpenAPIHono<AppHonoEnv>): void {
  app.openapi(listRoute, async (c) => {
    const context = await requireAuthContext(c);
    return c.json({ data: await listFriendships(c.env.DB, context, c.req.valid("query").status) }, 200);
  });
  app.openapi(createFriendshipRoute, async (c) => {
    const context = await requireAuthContext(c);
    const result = await createFriendship(c.env.DB, context, c.req.valid("json"), idempotencyKey(c.req.valid("header")));
    return completeMutation(c, result) as never;
  });
  app.openapi(respondRoute, async (c) => {
    const context = await requireAuthContext(c);
    const result = await respondFriendship(
      c.env.DB, context, c.req.valid("param").friendshipID,
      c.req.valid("json"), idempotencyKey(c.req.valid("header"))
    );
    return completeMutation(c, result) as never;
  });
  app.openapi(closeRoute, async (c) => {
    const context = await requireAuthContext(c);
    const result = await closeFriendship(
      c.env.DB, context, c.req.valid("param").friendshipID,
      idempotencyKey(c.req.valid("header"))
    );
    return completeMutation(c, result) as never;
  });
}
