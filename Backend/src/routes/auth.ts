import { createRoute, type OpenAPIHono } from "@hono/zod-openapi";
import {
  claimGitHubDevicePoll,
  consumeGitHubDeviceFlow,
  fetchGitHubIdentity,
  pollGitHubDeviceAuthorization,
  rememberGitHubDeviceFlow,
  rescheduleGitHubDevicePoll,
  startGitHubDeviceAuthorization
} from "../auth/github-auth";
import { requireAuthContext, type AppHonoEnv } from "../auth/middleware";
import { sessionForProviderIdentity } from "../auth/sessions";
import { bootstrapDevelopmentProfile } from "../application/dev-bootstrap";
import { validateEnvironment } from "../env";
import { badRequest } from "../errors";
import { revokeSession, rotateRefreshToken } from "../storage/accounts-repository";
import { commonErrors, dataSchema, deviceMetadataSchema, z } from "./schemas";

const sessionSchema = z.object({
  accessToken: z.string(),
  refreshToken: z.string(),
  accessExpiresAt: z.number(),
  refreshExpiresAt: z.number(),
  accountID: z.string(),
  device: z.unknown(),
  pet: z.unknown(),
  isPrimaryAgentDevice: z.boolean()
});

const githubDeviceStartRoute = createRoute({
  method: "post",
  path: "/v1/auth/github/device/start",
  responses: {
    200: { content: { "application/json": { schema: dataSchema(z.object({
      deviceCode: z.string(),
      userCode: z.string(),
      verificationURI: z.url(),
      expiresIn: z.number().int().positive(),
      interval: z.number().int().positive()
    })) } }, description: "GitHub device authorization" },
    ...commonErrors
  }
});

const githubDeviceCompleteRoute = createRoute({
  method: "post",
  path: "/v1/auth/github/device/complete",
  request: {
    body: { content: { "application/json": { schema: z.object({
      deviceCode: z.string().min(20).max(256),
      device: deviceMetadataSchema
    }).strict() } } }
  },
  responses: {
    200: { content: { "application/json": { schema: dataSchema(z.discriminatedUnion("status", [
      z.object({ status: z.literal("pending"), retryAfterSeconds: z.number().int().positive() }),
      z.object({ status: z.literal("authenticated"), session: sessionSchema })
    ])) } }, description: "Pending status or authenticated Mino session" },
    ...commonErrors
  }
});

const refreshRoute = createRoute({
  method: "post",
  path: "/v1/auth/refresh",
  request: { body: { content: { "application/json": { schema: z.object({ refreshToken: z.string().min(1).max(512) }).strict() } } } },
  responses: {
    200: { content: { "application/json": { schema: dataSchema(sessionSchema) } }, description: "Rotated session" },
    ...commonErrors
  }
});

const logoutRoute = createRoute({
  method: "post",
  path: "/v1/auth/logout",
  responses: {
    204: { description: "Session revoked" },
    ...commonErrors
  }
});

const devBootstrapRoute = createRoute({
  method: "post",
  path: "/v1/dev/bootstrap",
  request: { body: { content: { "application/json": { schema: z.object({ profile: z.enum(["alice", "bob", "charlie"]) }).strict() } } } },
  responses: {
    200: { content: { "application/json": { schema: dataSchema(z.unknown()) } }, description: "Local development identity" },
    ...commonErrors
  }
});

export function registerAuthRoutes(app: OpenAPIHono<AppHonoEnv>): void {
  app.openapi(githubDeviceStartRoute, async (c) => {
    const env = validateEnvironment(c.env);
    const authorization = await startGitHubDeviceAuthorization(env.GITHUB_CLIENT_ID);
    await rememberGitHubDeviceFlow(env.DB, env.SESSION_TOKEN_PEPPER, authorization);
    return c.json({ data: authorization }, 200);
  });
  app.openapi(githubDeviceCompleteRoute, async (c) => {
    const env = validateEnvironment(c.env);
    const body = c.req.valid("json");
    const claim = await claimGitHubDevicePoll(
      env.DB,
      env.SESSION_TOKEN_PEPPER,
      body.deviceCode
    );
    if (!claim.poll) {
      return c.json({ data: {
        status: "pending" as const,
        retryAfterSeconds: claim.retryAfterSeconds
      } }, 200);
    }
    const result = await pollGitHubDeviceAuthorization(
      env.GITHUB_CLIENT_ID,
      body.deviceCode,
      claim.retryAfterSeconds
    );
    if (result.status === "pending" || result.status === "slow_down") {
      await rescheduleGitHubDevicePoll(env.DB, claim.hash, result.retryAfterSeconds);
      return c.json({ data: {
        status: "pending" as const,
        retryAfterSeconds: result.retryAfterSeconds
      } }, 200);
    }
    if (result.status === "expired" || result.status === "denied") {
      await consumeGitHubDeviceFlow(env.DB, claim.hash);
      throw badRequest(
        result.status === "expired" ? "github_device_expired" : "github_access_denied",
        result.status === "expired" ? "GitHub device authorization expired" : "GitHub authorization was denied"
      );
    }
    const identity = await fetchGitHubIdentity(result.accessToken);
    const session = await sessionForProviderIdentity(
      env.DB,
      env.SESSION_TOKEN_PEPPER,
      "github",
      identity.subject,
      identity.login,
      {
        ...(body.device.id ? { id: body.device.id } : {}),
        displayName: body.device.displayName,
        platform: body.device.platform,
        appVersion: body.device.appVersion
      }
    );
    await consumeGitHubDeviceFlow(env.DB, claim.hash);
    return c.json({ data: { status: "authenticated" as const, session } }, 200);
  });
  app.openapi(refreshRoute, async (c) => {
    const env = validateEnvironment(c.env);
    const session = await rotateRefreshToken(env.DB, env.SESSION_TOKEN_PEPPER, c.req.valid("json").refreshToken);
    return c.json({ data: session }, 200);
  });
  app.openapi(logoutRoute, async (c) => {
    const context = await requireAuthContext(c);
    await revokeSession(c.env.DB, context.sessionID);
    return c.body(null, 204);
  });
  app.openapi(devBootstrapRoute, async (c) => {
    const data = await bootstrapDevelopmentProfile(validateEnvironment(c.env), c.req.valid("json").profile);
    return c.json({ data }, 200);
  });
}
