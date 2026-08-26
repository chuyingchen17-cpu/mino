import { env } from "cloudflare:workers";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { issueSession } from "../src/storage/accounts-repository";
import { bootstrapAll, jsonData, key, request, resetDatabase, type DevProfile } from "./helpers";

let alice: DevProfile;
let bob: DevProfile;

beforeEach(async () => {
  vi.restoreAllMocks();
  await resetDatabase();
  ({ alice, bob } = await bootstrapAll());
});

describe("sessions and devices", () => {
  it("rotates refresh tokens and rejects expired sessions and revoked devices", async () => {
    const attempts = await Promise.all([
      request("/v1/auth/refresh", { body: { refreshToken: alice.refreshToken } }),
      request("/v1/auth/refresh", { body: { refreshToken: alice.refreshToken } })
    ]);
    expect(attempts.map((response) => response.status).sort()).toEqual([200, 404]);
    const rotated = attempts.find((response) => response.status === 200)!;
    const tokens = await jsonData<{ accessToken: string; refreshToken: string }>(rotated);
    expect(tokens.refreshToken).not.toBe(alice.refreshToken);
    expect((await request("/v1/me", { token: alice.token })).status).toBe(401);
    expect((await request("/v1/me", { token: tokens.accessToken })).status).toBe(200);

    await env.DB.prepare("UPDATE devices SET revoked_at_ms = ? WHERE id = ?")
      .bind(Date.now(), alice.deviceID).run();
    expect((await request("/v1/me", { token: tokens.accessToken })).status).toBe(401);

    await env.DB.prepare("UPDATE devices SET revoked_at_ms = NULL WHERE id = ?")
      .bind(alice.deviceID).run();
    await env.DB.prepare("UPDATE sessions SET access_expires_at_ms = 0 WHERE access_token_hash IN (SELECT access_token_hash FROM sessions WHERE account_id = ?)")
      .bind(alice.accountID).run();
    expect((await request("/v1/me", { token: tokens.accessToken })).status).toBe(401);
  });

  it("cannot bind a session to another account's device identity", async () => {
    await expect(issueSession(env.DB, env.SESSION_TOKEN_PEPPER, alice.accountID, {
      deviceID: bob.deviceID,
      displayName: "forged",
      platform: "macos",
      appVersion: "test"
    })).rejects.toMatchObject({ code: "not_found" });
    const forged = await env.DB.prepare("SELECT id FROM sessions WHERE account_id = ? AND device_id = ?")
      .bind(alice.accountID, bob.deviceID).first();
    expect(forged).toBeNull();
  });
});

describe("GitHub Device Flow", () => {
  it("verifies the provider user, issues Mino tokens, and consumes the device code", async () => {
    vi.spyOn(globalThis, "fetch").mockImplementation(async (input) => {
      const url = String(input);
      if (url.includes("/login/device/code")) {
        return Response.json({
          device_code: "github-device-code-12345678901234567890",
          user_code: "ABCD-EFGH",
          verification_uri: "https://github.com/login/device",
          expires_in: 900,
          interval: 5
        });
      }
      if (url.includes("/login/oauth/access_token")) {
        return Response.json({ access_token: "github-user-token-secret", token_type: "bearer", scope: "" });
      }
      if (url === "https://api.github.com/user") {
        return Response.json({ id: 12345678, login: "octo-mino" });
      }
      return new Response(null, { status: 404 });
    });

    const started = await request("/v1/auth/github/device/start", { method: "POST" });
    expect(started.status).toBe(200);
    const authorization = await jsonData<{ deviceCode: string; userCode: string }>(started);
    expect(authorization.userCode).toBe("ABCD-EFGH");
    const storedFlow = await env.DB.prepare("SELECT device_code_hash FROM oauth_device_flows").first<{ device_code_hash: string }>();
    expect(storedFlow?.device_code_hash).not.toContain(authorization.deviceCode);

    await env.DB.prepare("UPDATE oauth_device_flows SET next_poll_at_ms = 0").run();
    const completed = await request("/v1/auth/github/device/complete", {
      body: {
        deviceCode: authorization.deviceCode,
        device: { displayName: "Mino Test Mac", platform: "macos", appVersion: "1.0" }
      }
    });
    expect(completed.status).toBe(200);
    const result = await jsonData<{
      status: "authenticated";
      session: { accountID: string; accessToken: string; refreshToken: string };
    }>(completed);
    expect(result.status).toBe("authenticated");
    expect((await request("/v1/me", { token: result.session.accessToken })).status).toBe(200);
    const account = await env.DB.prepare("SELECT provider_subject, display_name FROM accounts WHERE id = ?")
      .bind(result.session.accountID).first<{ provider_subject: string; display_name: string }>();
    expect(account).toEqual({ provider_subject: "github:12345678", display_name: "octo-mino" });
    expect((await request("/v1/auth/github/device/complete", {
      body: {
        deviceCode: authorization.deviceCode,
        device: { displayName: "Mino Test Mac", platform: "macos", appVersion: "1.0" }
      }
    })).status).toBe(400);
  });
});

describe("boundary validation", () => {
  it("rejects unknown appearance fields, forged Agent letter context, and oversized payloads", async () => {
    const appearance = await request("/v1/me/pet", {
      method: "PATCH",
      token: alice.token,
      key: key(),
      body: {
        appearanceSchemaVersion: 1,
        appearanceCatalogVersion: 1,
        appearance: { rigID: "mino-default", body: "default", fileURL: "https://evil.invalid/pet" }
      }
    });
    expect(appearance.status).toBe(400);

    const model = await request("/v1/agent/decision", {
      token: alice.token,
      body: {
        inferenceID: key(),
        petID: alice.petID,
        trigger: { type: "sealed_human_letter_available", summary: "the secret plaintext" },
        state: { friendPetIDs: [alice.friends[0]!.petID] },
        memories: [],
        availableActions: ["idle"]
      }
    });
    expect(model.status).toBe(400);
    expect(await model.json()).toMatchObject({ error: { code: "letter_content_forbidden" } });

    const oversized = await request("/v1/friendships", {
      token: alice.token,
      key: key(),
      body: { addresseeAccountID: "x".repeat(70_000) }
    });
    expect(oversized.status).toBe(413);
  });
});
