import "dotenv/config";
import { z } from "zod";

const environmentSchema = z.object({
  NODE_ENV: z.enum(["development", "test", "production"]).default("development"),
  HOST: z.string().default("127.0.0.1"),
  PORT: z.coerce.number().int().min(1).max(65_535).default(8080),
  DATABASE_URL: z.string().min(1).default("postgres://mino:mino_dev_only@127.0.0.1:5432/mino"),
  DEV_BOOTSTRAP_ENABLED: z.enum(["true", "false"]).default("false"),
  MODEL_PROVIDER: z.enum(["mock", "openai-compatible"]).default("mock"),
  MODEL_BASE_URL: z.string().url().optional(),
  MODEL_API_KEY: z.string().min(1).optional(),
  MODEL_NAME: z.string().min(1).optional(),
  LETTER_ENCRYPTION_KEY: z.string().min(1).optional()
});

export interface AppConfig {
  nodeEnv: "development" | "test" | "production";
  host: string;
  port: number;
  databaseURL: string;
  devBootstrapEnabled: boolean;
  model: {
    provider: "mock" | "openai-compatible";
    baseURL?: string;
    apiKey?: string;
    name?: string;
  };
  letterEncryptionKey?: string;
}

export function loadConfig(environment: NodeJS.ProcessEnv = process.env): AppConfig {
  const parsed = environmentSchema.parse(environment);
  const devBootstrapEnabled = parsed.DEV_BOOTSTRAP_ENABLED === "true";

  if (parsed.NODE_ENV === "production" && devBootstrapEnabled) {
    throw new Error("DEV_BOOTSTRAP_ENABLED must be false in production");
  }

  if (parsed.MODEL_PROVIDER === "openai-compatible") {
    if (!parsed.MODEL_BASE_URL || !parsed.MODEL_API_KEY || !parsed.MODEL_NAME) {
      throw new Error("OpenAI-compatible model configuration is incomplete");
    }
  }

  if (parsed.NODE_ENV === "production" && !parsed.LETTER_ENCRYPTION_KEY) {
    throw new Error("LETTER_ENCRYPTION_KEY is required in production");
  }

  return {
    nodeEnv: parsed.NODE_ENV,
    host: parsed.HOST,
    port: parsed.PORT,
    databaseURL: parsed.DATABASE_URL,
    devBootstrapEnabled,
    model: {
      provider: parsed.MODEL_PROVIDER,
      ...(parsed.MODEL_BASE_URL ? { baseURL: parsed.MODEL_BASE_URL } : {}),
      ...(parsed.MODEL_API_KEY ? { apiKey: parsed.MODEL_API_KEY } : {}),
      ...(parsed.MODEL_NAME ? { name: parsed.MODEL_NAME } : {})
    },
    ...(parsed.LETTER_ENCRYPTION_KEY ? { letterEncryptionKey: parsed.LETTER_ENCRYPTION_KEY } : {})
  };
}
