import { developmentBootstrapEnabled, type MinoEnv } from "../env";
import { notFound } from "../errors";
import { hashToken } from "../security/tokens";

const friendshipID = "00000000-0000-4000-8000-000000000001";

const profiles = {
  alice: {
    profile: "alice",
    token: "mino-local-development-alice-v1",
    refreshToken: "mino-local-development-alice-refresh-v1",
    accountID: "00000000-0000-4000-8000-00000000000a",
    deviceID: "00000000-0000-4000-8000-0000000000da",
    sessionID: "00000000-0000-4000-8000-0000000001da",
    petID: "00000000-0000-4000-8000-0000000000a1",
    accountName: "Alice",
    petName: "奶糖",
    appearanceCatalogVersion: 2,
    appearance: { rigID: "maltese-pair-v1", body: "maltese-white" }
  },
  bob: {
    profile: "bob",
    token: "mino-local-development-bob-v1",
    refreshToken: "mino-local-development-bob-refresh-v1",
    accountID: "00000000-0000-4000-8000-00000000000b",
    deviceID: "00000000-0000-4000-8000-0000000000db",
    sessionID: "00000000-0000-4000-8000-0000000001db",
    petID: "00000000-0000-4000-8000-0000000000b1",
    accountName: "Bob",
    petName: "团子",
    appearanceCatalogVersion: 2,
    appearance: { rigID: "maltese-pair-v1", body: "retriever-yellow" }
  },
  charlie: {
    profile: "charlie",
    token: "mino-local-development-charlie-v1",
    refreshToken: "mino-local-development-charlie-refresh-v1",
    accountID: "00000000-0000-4000-8000-00000000000c",
    deviceID: "00000000-0000-4000-8000-0000000000dc",
    sessionID: "00000000-0000-4000-8000-0000000001dc",
    petID: "00000000-0000-4000-8000-0000000000c1",
    accountName: "Charlie",
    petName: "星星",
    appearanceCatalogVersion: 1,
    appearance: { rigID: "mino-default", body: "default" }
  }
} as const;

export type DevProfileName = keyof typeof profiles;

export async function bootstrapDevelopmentProfile(env: MinoEnv, profileName: DevProfileName, now = Date.now()) {
  if (!developmentBootstrapEnabled(env)) throw notFound("route");
  for (const profile of Object.values(profiles)) {
    const [accessHash, refreshHash] = await Promise.all([
      hashToken(profile.token, env.SESSION_TOKEN_PEPPER),
      hashToken(profile.refreshToken, env.SESSION_TOKEN_PEPPER)
    ]);
    await env.DB.batch([
      env.DB.prepare(`
        INSERT INTO accounts(id, provider_subject, display_name, primary_agent_device_id, created_at_ms, updated_at_ms)
        VALUES (?, NULL, ?, NULL, ?, ?)
        ON CONFLICT(id) DO UPDATE SET updated_at_ms = excluded.updated_at_ms
      `).bind(profile.accountID, profile.accountName, now, now),
      env.DB.prepare(`
        INSERT INTO pets(
          id, owner_account_id, display_name, appearance_schema_version,
          appearance_catalog_version, appearance_json, appearance_version,
          created_at_ms, updated_at_ms
        ) VALUES (?, ?, ?, 1, ?, ?, 1, ?, ?)
        ON CONFLICT(id) DO UPDATE SET owner_account_id = excluded.owner_account_id
      `).bind(
        profile.petID,
        profile.accountID,
        profile.petName,
        profile.appearanceCatalogVersion,
        JSON.stringify(profile.appearance),
        now,
        now
      ),
      env.DB.prepare(`
        INSERT INTO devices(id, account_id, display_name, platform, app_version, created_at_ms, revoked_at_ms)
        VALUES (?, ?, ?, 'macos', 'development', ?, NULL)
        ON CONFLICT(id) DO UPDATE SET revoked_at_ms = NULL
      `).bind(profile.deviceID, profile.accountID, `${profile.accountName} Development Mac`, now),
      env.DB.prepare(`
        INSERT INTO sessions(
          id, account_id, device_id, access_token_hash, refresh_token_hash,
          access_expires_at_ms, refresh_expires_at_ms, revoked_at_ms, created_at_ms
        ) VALUES (?, ?, ?, ?, ?, ?, ?, NULL, ?)
        ON CONFLICT(id) DO UPDATE SET
          access_token_hash = excluded.access_token_hash,
          refresh_token_hash = excluded.refresh_token_hash,
          access_expires_at_ms = excluded.access_expires_at_ms,
          refresh_expires_at_ms = excluded.refresh_expires_at_ms,
          revoked_at_ms = NULL
      `).bind(profile.sessionID, profile.accountID, profile.deviceID, accessHash, refreshHash,
        now + 365 * 24 * 60 * 60 * 1_000, now + 365 * 24 * 60 * 60 * 1_000, now),
      env.DB.prepare(`
        UPDATE accounts SET primary_agent_device_id = ?, updated_at_ms = ? WHERE id = ?
      `).bind(profile.deviceID, now, profile.accountID)
    ]);
  }
  await env.DB.prepare(`
    INSERT INTO friendships(
      id, requester_account_id, addressee_account_id, pair_key, status,
      version, last_transition_id, created_at_ms, responded_at_ms, closed_at_ms
    ) VALUES (?, ?, ?, ?, 'accepted', 1, ?, ?, ?, NULL)
    ON CONFLICT(id) DO UPDATE SET status = 'accepted', closed_at_ms = NULL
  `).bind(
    friendshipID, profiles.alice.accountID, profiles.bob.accountID,
    [profiles.alice.accountID, profiles.bob.accountID].sort().join(":"),
    friendshipID, now, now
  ).run();
  const profile = profiles[profileName];
  const friends = profileName === "charlie" ? [] : [{
    friendshipID,
    accountID: profileName === "alice" ? profiles.bob.accountID : profiles.alice.accountID,
    petID: profileName === "alice" ? profiles.bob.petID : profiles.alice.petID,
    accountName: profileName === "alice" ? profiles.bob.accountName : profiles.alice.accountName,
    petName: profileName === "alice" ? profiles.bob.petName : profiles.alice.petName
  }];
  return { ...profile, friends };
}
