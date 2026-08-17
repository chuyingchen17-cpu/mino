import { describe, expect, it } from "vitest";
import { loadConfig } from "../src/config.js";

describe("configuration safety", () => {
  it("refuses development bootstrap in production", () => {
    expect(() => loadConfig({ NODE_ENV: "production", DEV_BOOTSTRAP_ENABLED: "true" })).toThrow(
      "DEV_BOOTSTRAP_ENABLED must be false in production"
    );
  });

  it("requires complete OpenAI-compatible provider settings", () => {
    expect(() => loadConfig({ NODE_ENV: "test", MODEL_PROVIDER: "openai-compatible" })).toThrow(
      "OpenAI-compatible model configuration is incomplete"
    );
  });

  it("requires an explicit letter encryption key in production", () => {
    expect(() => loadConfig({
      NODE_ENV: "production",
      DEV_BOOTSTRAP_ENABLED: "false",
      MODEL_PROVIDER: "mock"
    })).toThrow("LETTER_ENCRYPTION_KEY is required in production");
  });
});
