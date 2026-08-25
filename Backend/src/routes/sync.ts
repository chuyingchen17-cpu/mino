import { createRoute, type OpenAPIHono } from "@hono/zod-openapi";
import { requireAuthContext, type AppHonoEnv } from "../auth/middleware";
import { syncBootstrap } from "../application/sync";
import { badRequest } from "../errors";
import { fetchAccountEvents } from "../storage/events-repository";
import { commonErrors, dataSchema, z } from "./schemas";

const bootstrapRoute = createRoute({
  method: "get", path: "/v1/sync/bootstrap",
  responses: { 200: { content: { "application/json": { schema: dataSchema(z.unknown()) } }, description: "Atomic account state snapshot" }, ...commonErrors }
});
const eventsRoute = createRoute({
  method: "get", path: "/v1/events",
  request: { query: z.object({
    after: z.coerce.number().int().min(0).default(0),
    limit: z.coerce.number().int().min(1).max(100).default(100),
    timelineVisible: z.enum(["true", "false"]).optional()
  }) },
  responses: { 200: { content: { "application/json": { schema: dataSchema(z.unknown()) } }, description: "Account event page" }, ...commonErrors }
});
const realtimeRoute = createRoute({
  method: "get", path: "/v1/realtime",
  responses: {
    101: { description: "Account realtime signal WebSocket" },
    426: { description: "WebSocket upgrade required" },
    ...commonErrors
  }
});

export function registerSyncRoutes(app: OpenAPIHono<AppHonoEnv>): void {
  app.openapi(bootstrapRoute, async (c) => {
    const context = await requireAuthContext(c);
    return c.json({ data: await syncBootstrap(c.env.DB, context) }, 200);
  });
  app.openapi(eventsRoute, async (c) => {
    const context = await requireAuthContext(c);
    const query = c.req.valid("query");
    return c.json({ data: await fetchAccountEvents(
      c.env.DB, context.accountID, query.after, query.limit, query.timelineVisible === "true"
    ) }, 200);
  });
  app.openapi(realtimeRoute, async (c) => {
    const context = await requireAuthContext(c);
    if (c.req.header("upgrade")?.toLowerCase() !== "websocket") {
      throw badRequest("websocket_upgrade_required", "Realtime requires a WebSocket upgrade");
    }
    const headers = new Headers(c.req.raw.headers);
    headers.delete("x-mino-device-id");
    headers.delete("x-mino-account-id");
    headers.set("x-mino-device-id", context.deviceID);
    const id = c.env.ACCOUNT_REALTIME.idFromName(context.accountID);
    return c.env.ACCOUNT_REALTIME.get(id).fetch(new Request(c.req.url, { method: "GET", headers })) as never;
  });
}
