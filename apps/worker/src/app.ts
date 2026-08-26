import { createRoute, OpenAPIHono } from "@hono/zod-openapi";
import { bodyLimit } from "hono/body-limit";
import type { AppHonoEnv } from "./auth/middleware";
import { validateEnvironment } from "./env";
import { AppError } from "./errors";
import { registerAccountRoutes } from "./routes/account";
import { registerAgentRoutes } from "./routes/agent";
import { registerAuthRoutes } from "./routes/auth";
import { registerConversationRoutes } from "./routes/conversations";
import { registerFriendshipRoutes } from "./routes/friendships";
import { registerLetterRoutes } from "./routes/letters";
import { registerPetCareRoutes } from "./routes/pet-care";
import { commonErrors, dataSchema, z } from "./routes/schemas";
import { registerSyncRoutes } from "./routes/sync";
import { registerVisitRoutes } from "./routes/visits";

export function createApp(): OpenAPIHono<AppHonoEnv> {
  const app = new OpenAPIHono<AppHonoEnv>({
    defaultHook: (result, c) => {
      if (result.success) return;
      return c.json({
        error: {
          code: "invalid_request",
          message: result.error.issues.map((issue) => `${issue.path.join(".")}: ${issue.message}`).join("; ")
        }
      }, 400);
    }
  });

  app.use("*", async (c, next) => {
    validateEnvironment(c.env);
    return next();
  });
  app.use("*", bodyLimit({
    maxSize: 64 * 1024,
    onError: (c) => c.json({ error: { code: "payload_too_large", message: "Request payload is too large" } }, 413)
  }));

  const health = (path: "/health" | "/v1/health") => createRoute({
    method: "get", path,
    responses: {
      200: {
        content: { "application/json": { schema: dataSchema(z.object({
          status: z.literal("healthy"),
          apiVersion: z.string(),
          storage: z.literal("d1"),
          realtime: z.literal("account-durable-object")
        })) } },
        description: "Worker health"
      },
      ...commonErrors
    }
  });
  for (const path of ["/health", "/v1/health"] as const) {
    app.openapi(health(path), (c) => c.json({ data: {
      status: "healthy" as const,
      apiVersion: "1.0.0",
      storage: "d1" as const,
      realtime: "account-durable-object" as const
    } }, 200));
  }

  registerAuthRoutes(app);
  registerAccountRoutes(app);
  registerFriendshipRoutes(app);
  registerSyncRoutes(app);
  registerVisitRoutes(app);
  registerConversationRoutes(app);
  registerLetterRoutes(app);
  registerPetCareRoutes(app);
  registerAgentRoutes(app);

  app.notFound((c) => c.json({ error: { code: "not_found", message: "Resource was not found" } }, 404));
  app.onError((error, c) => {
    if (error instanceof AppError) {
      return c.json({ error: { code: error.code, message: error.message } }, error.status as 400);
    }
    return c.json({ error: { code: "internal_error", message: "An unexpected error occurred" } }, 500);
  });
  return app;
}

export const app = createApp();

export function openAPIDocument() {
  return app.getOpenAPIDocument({
    openapi: "3.1.0",
    info: {
      version: "1.0.0",
      title: "Mino Worker API",
      description: "Account-scoped social, Visit, durable event, and model proxy API"
    },
    servers: [{ url: "https://api.mino.example" }]
  });
}
