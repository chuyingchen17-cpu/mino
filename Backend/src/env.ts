import { z } from "zod";
import { AppError } from "./errors";

const environmentSchema = z.object({
  ENVIRONMENT: z.enum(["local", "development", "test", "staging", "production"]),
  DEV_BOOTSTRAP_ENABLED: z.enum(["true", "false"]),
  GITHUB_CLIENT_ID: z.string().min(1),
  SESSION_TOKEN_PEPPER: z.string().min(16),
  LETTER_ENCRYPTION_KEY_V1: z.string().min(16),
  MODEL_PROVIDER_API_KEY: z.string().min(1).optional(),
  MODEL_PROVIDER_BASE_URL: z.url().optional(),
  MODEL_NAME: z.string().min(1).optional()
});

export type MinoEnv = z.infer<typeof environmentSchema> & Pick<Env, "DB" | "ACCOUNT_REALTIME">;

export function validateEnvironment(env: Env): MinoEnv {
  const parsed = environmentSchema.safeParse(env);
  if (!parsed.success) {
    throw new AppError(500, "invalid_environment", "Worker environment is incomplete");
  }
  if (parsed.data.ENVIRONMENT === "production" && parsed.data.DEV_BOOTSTRAP_ENABLED === "true") {
    throw new AppError(500, "unsafe_production_configuration", "Development bootstrap cannot be enabled in production");
  }
  return env as unknown as MinoEnv;
}

export function developmentBootstrapEnabled(env: MinoEnv): boolean {
  return env.DEV_BOOTSTRAP_ENABLED === "true" &&
    ["local", "development", "test"].includes(env.ENVIRONMENT);
}
