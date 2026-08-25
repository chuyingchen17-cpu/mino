import { createRoute, type OpenAPIHono } from "@hono/zod-openapi";
import { requireAuthContext, type AppHonoEnv } from "../auth/middleware";
import {
  createConversation,
  endConversation,
  listActiveConversations,
  listConversationMessages,
  sendConversationMessage
} from "../application/conversations";
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
  method: "get", path: "/v1/conversations",
  responses: { 200: { content: { "application/json": { schema: dataSchema(z.array(z.unknown())) } }, description: "Active conversations" }, ...commonErrors }
});
const createConversationRoute = createRoute({
  method: "post", path: "/v1/conversations",
  request: {
    headers: idempotencyHeadersSchema,
    body: { content: { "application/json": { schema: z.object({
      friendshipID: uuidSchema,
      recipientPetID: identifierSchema,
      openingMessage: z.string().trim().min(1).max(500),
      actorType: z.literal("pet_agent")
    }).strict() } } }
  },
  responses: { 201: { content: { "application/json": { schema: dataSchema(z.unknown()) } }, description: "Conversation started" }, ...commonErrors }
});
const messagesRoute = createRoute({
  method: "get", path: "/v1/conversations/{conversationID}/messages",
  request: { params: z.object({ conversationID: uuidSchema }) },
  responses: { 200: { content: { "application/json": { schema: dataSchema(z.array(z.unknown())) } }, description: "Conversation messages" }, ...commonErrors }
});
const sendMessageRoute = createRoute({
  method: "post", path: "/v1/conversations/{conversationID}/messages",
  request: {
    headers: idempotencyHeadersSchema,
    params: z.object({ conversationID: uuidSchema }),
    body: { content: { "application/json": { schema: z.object({
      actorType: z.enum(["human", "pet_agent"]),
      text: z.string().trim().min(1).max(500)
    }).strict() } } }
  },
  responses: { 201: { content: { "application/json": { schema: dataSchema(z.unknown()) } }, description: "Conversation message sent" }, ...commonErrors }
});
const endRoute = createRoute({
  method: "post", path: "/v1/conversations/{conversationID}/end",
  request: {
    headers: idempotencyHeadersSchema,
    params: z.object({ conversationID: uuidSchema }),
    body: { content: { "application/json": { schema: z.object({
      summary: z.string().trim().min(1).max(500),
      actorType: z.literal("pet_agent")
    }).strict() } } }
  },
  responses: { 200: { content: { "application/json": { schema: dataSchema(z.unknown()) } }, description: "Conversation ended" }, ...commonErrors }
});

export function registerConversationRoutes(app: OpenAPIHono<AppHonoEnv>): void {
  app.openapi(listRoute, async (c) => {
    const context = await requireAuthContext(c);
    return c.json({ data: await listActiveConversations(c.env.DB, context) }, 200);
  });
  app.openapi(createConversationRoute, async (c) => {
    const context = await requireAuthContext(c);
    const result = await createConversation(c.env.DB, context, c.req.valid("json"), idempotencyKey(c.req.valid("header")));
    return completeMutation(c, result) as never;
  });
  app.openapi(messagesRoute, async (c) => {
    const context = await requireAuthContext(c);
    return c.json({ data: await listConversationMessages(
      c.env.DB, context, c.req.valid("param").conversationID
    ) }, 200);
  });
  app.openapi(sendMessageRoute, async (c) => {
    const context = await requireAuthContext(c);
    const result = await sendConversationMessage(
      c.env.DB, context, c.req.valid("param").conversationID,
      c.req.valid("json"), idempotencyKey(c.req.valid("header"))
    );
    return completeMutation(c, result) as never;
  });
  app.openapi(endRoute, async (c) => {
    const context = await requireAuthContext(c);
    const result = await endConversation(
      c.env.DB, context, c.req.valid("param").conversationID,
      c.req.valid("json"), idempotencyKey(c.req.valid("header"))
    );
    return completeMutation(c, result) as never;
  });
}
