import { describe, expect, it } from "vitest";
import type { Kysely } from "kysely";
import { PostgresMinoStore } from "../src/database/postgres-store.js";
import type { Database } from "../src/database/schema.js";
import { devProfiles, isDevBootstrapToken } from "../src/dev-fixtures.js";
import { LetterCipher } from "../src/security/letter-cipher.js";

describe("development bootstrap credentials", () => {
  it("are deterministic across server restarts and clearly development-only", () => {
    const first = devProfiles();
    const afterRestart = devProfiles();

    expect(afterRestart.alice.token).toBe(first.alice.token);
    expect(afterRestart.bob.token).toBe(first.bob.token);
    expect(afterRestart.charlie.token).toBe(first.charlie.token);
    expect(first.alice.token).toBe("mino-local-development-alice-v1");
    expect(first.bob.token).toBe("mino-local-development-bob-v1");
    expect(first.charlie.token).toBe("mino-local-development-charlie-v1");
    expect(first.alice).not.toHaveProperty("coupleID");
    expect(first.alice).not.toHaveProperty("partnerPetID");
    expect(isDevBootstrapToken(first.alice.token)).toBe(true);
    expect(isDevBootstrapToken("a-production-session-token")).toBe(false);
  });

  it("rejects the known credentials before touching a production database", async () => {
    const unavailableDatabase = {} as Kysely<Database>;
    const store = new PostgresMinoStore(
      unavailableDatabase,
      LetterCipher.development("postgres://unused"),
      false
    );

    await expect(store.authenticate(devProfiles().alice.token)).resolves.toBeNull();
  });
});
