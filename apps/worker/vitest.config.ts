import { cloudflareTest, readD1Migrations } from "@cloudflare/vitest-plugin";
import { defineConfig } from "vitest/config";
import path from "node:path";

export default defineConfig(async () => {
  const migrations = await readD1Migrations(path.join(import.meta.dirname, "migrations"));
  return {
    plugins: [cloudflareTest({
      wrangler: { configPath: "./wrangler.jsonc" },
      miniflare: {
        bindings: {
          TEST_MIGRATIONS: migrations,
          ENVIRONMENT: "test",
          DEV_BOOTSTRAP_ENABLED: "true",
          GITHUB_CLIENT_ID: "test-github-client",
          SESSION_TOKEN_PEPPER: "test-session-pepper",
          LETTER_ENCRYPTION_KEY_V1: "dGVzdC1sZXR0ZXIta2V5LXdpdGgtMzItYnl0ZXM=",
          MODEL_PROVIDER_API_KEY: "test-model-key",
          MODEL_PROVIDER_BASE_URL: "https://model.example.invalid",
          MODEL_NAME: "test-model"
        }
      }
    })],
    test: {
      setupFiles: ["./tests/setup.ts"],
      sequence: { concurrent: false },
      include: ["tests/**/*.test.ts"]
    }
  };
});
