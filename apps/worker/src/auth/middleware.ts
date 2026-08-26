import type { Context } from "hono";
import type { AuthContext } from "../domain/models";
import { unauthorized } from "../errors";
import { validateEnvironment } from "../env";
import { authenticateAccessToken } from "../storage/accounts-repository";

export type AppHonoEnv = {
  Bindings: Env;
  Variables: { auth: AuthContext };
};

export async function requireAuthContext(c: Context<AppHonoEnv>): Promise<AuthContext> {
  const authorization = c.req.header("authorization");
  if (!authorization?.startsWith("Bearer ")) throw unauthorized();
  const token = authorization.slice(7).trim();
  if (!token) throw unauthorized();
  const env = validateEnvironment(c.env);
  const context = await authenticateAccessToken(env.DB, token, env.SESSION_TOKEN_PEPPER);
  if (!context) throw unauthorized();
  c.set("auth", context);
  return context;
}
