import type { AccountRealtimeHub } from "./src/realtime/account-realtime-hub";

declare global {
  interface Env {
    DB: D1Database;
    ACCOUNT_REALTIME: DurableObjectNamespace<AccountRealtimeHub>;
    ENVIRONMENT: "local" | "development" | "test" | "staging" | "production";
    DEV_BOOTSTRAP_ENABLED: string;
    GITHUB_CLIENT_ID: string;
    SESSION_TOKEN_PEPPER: string;
    LETTER_ENCRYPTION_KEY_V1: string;
    MODEL_PROVIDER_API_KEY?: string;
    MODEL_PROVIDER_BASE_URL?: string;
    MODEL_NAME?: string;
    TEST_MIGRATIONS: D1Migration[];
  }
}

export {};
