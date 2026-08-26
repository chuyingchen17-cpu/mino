import type { AuthContext, Device, PublicPetSnapshot } from "../domain/models";
import { notFound } from "../errors";
import { hashToken, randomToken } from "../security/tokens";

interface AuthRow {
  session_id: string;
  account_id: string;
  device_id: string;
  pet_id: string;
  primary_agent_device_id: string | null;
}

interface PetRow {
  id: string;
  display_name: string;
  appearance_schema_version: number;
  appearance_catalog_version: number;
  appearance_json: string;
  appearance_version: number;
}

interface DeviceRow {
  id: string;
  account_id: string;
  display_name: string;
  platform: "macos";
  app_version: string;
  created_at_ms: number;
  revoked_at_ms: number | null;
}

export interface SessionTokens {
  accessToken: string;
  refreshToken: string;
  accessExpiresAt: number;
  refreshExpiresAt: number;
  device: Device;
  accountID: string;
  pet: PublicPetSnapshot;
  isPrimaryAgentDevice: boolean;
}

export function publicPetFromRow(row: PetRow): PublicPetSnapshot {
  return {
    petID: row.id,
    displayName: row.display_name,
    appearanceSchemaVersion: row.appearance_schema_version,
    appearanceCatalogVersion: row.appearance_catalog_version,
    appearanceVersion: row.appearance_version,
    appearance: JSON.parse(row.appearance_json) as Record<string, string>
  };
}

function deviceFromRow(row: DeviceRow): Device {
  return {
    id: row.id,
    accountID: row.account_id,
    displayName: row.display_name,
    platform: row.platform,
    appVersion: row.app_version,
    createdAt: row.created_at_ms,
    revokedAt: row.revoked_at_ms
  };
}

export async function authenticateAccessToken(
  db: D1Database,
  token: string,
  pepper: string,
  now = Date.now()
): Promise<AuthContext | null> {
  const accessHash = await hashToken(token, pepper);
  const row = await db.prepare(`
    SELECT sessions.id AS session_id, sessions.account_id, sessions.device_id,
           pets.id AS pet_id, accounts.primary_agent_device_id
    FROM sessions
    JOIN accounts ON accounts.id = sessions.account_id
    JOIN devices ON devices.id = sessions.device_id AND devices.account_id = sessions.account_id
    JOIN pets ON pets.owner_account_id = sessions.account_id
    WHERE sessions.access_token_hash = ?
      AND sessions.access_expires_at_ms > ?
      AND sessions.revoked_at_ms IS NULL
      AND devices.revoked_at_ms IS NULL
  `).bind(accessHash, now).first<AuthRow>();
  if (!row) return null;
  return {
    accountID: row.account_id,
    deviceID: row.device_id,
    petID: row.pet_id,
    isPrimaryAgentDevice: row.primary_agent_device_id === row.device_id,
    sessionID: row.session_id
  };
}

export async function issueSession(
  db: D1Database,
  pepper: string,
  accountID: string,
  metadata: { deviceID?: string; displayName: string; platform: "macos"; appVersion: string },
  now = Date.now(),
  suppliedTokens?: { accessToken: string; refreshToken: string }
): Promise<SessionTokens> {
  const deviceID = metadata.deviceID ?? crypto.randomUUID();
  if (metadata.deviceID) {
    const existingDevice = await db.prepare("SELECT account_id, revoked_at_ms FROM devices WHERE id = ?")
      .bind(deviceID).first<{ account_id: string; revoked_at_ms: number | null }>();
    if (existingDevice &&
      (existingDevice.account_id !== accountID || existingDevice.revoked_at_ms !== null)) {
      throw notFound("device");
    }
  }
  const accessToken = suppliedTokens?.accessToken ?? randomToken();
  const refreshToken = suppliedTokens?.refreshToken ?? randomToken();
  const accessExpiresAt = now + 15 * 60 * 1_000;
  const refreshExpiresAt = now + 30 * 24 * 60 * 60 * 1_000;
  const sessionID = crypto.randomUUID();
  const [accessHash, refreshHash] = await Promise.all([
    hashToken(accessToken, pepper),
    hashToken(refreshToken, pepper)
  ]);
  await db.batch([
    db.prepare(`
      INSERT INTO devices(id, account_id, display_name, platform, app_version, created_at_ms, revoked_at_ms)
      VALUES (?, ?, ?, ?, ?, ?, NULL)
      ON CONFLICT(id) DO UPDATE SET
        display_name = excluded.display_name,
        app_version = excluded.app_version
      WHERE devices.account_id = excluded.account_id AND devices.revoked_at_ms IS NULL
    `).bind(deviceID, accountID, metadata.displayName, metadata.platform, metadata.appVersion, now),
    db.prepare(`
      INSERT INTO sessions(
        id, account_id, device_id, access_token_hash, refresh_token_hash,
        access_expires_at_ms, refresh_expires_at_ms, revoked_at_ms, created_at_ms
      ) VALUES (?, ?, ?, ?, ?, ?, ?, NULL, ?)
    `).bind(sessionID, accountID, deviceID, accessHash, refreshHash, accessExpiresAt, refreshExpiresAt, now),
    db.prepare(`
      UPDATE accounts SET primary_agent_device_id = ?, updated_at_ms = ?
      WHERE id = ? AND primary_agent_device_id IS NULL
    `).bind(deviceID, now, accountID)
  ]);
  const [device, pet, account] = await Promise.all([
    db.prepare("SELECT * FROM devices WHERE id = ? AND account_id = ? AND revoked_at_ms IS NULL")
      .bind(deviceID, accountID).first<DeviceRow>(),
    db.prepare("SELECT * FROM pets WHERE owner_account_id = ?").bind(accountID).first<PetRow>(),
    db.prepare("SELECT primary_agent_device_id FROM accounts WHERE id = ?").bind(accountID)
      .first<{ primary_agent_device_id: string | null }>()
  ]);
  if (!device || !pet || !account) throw notFound("account");
  return {
    accessToken,
    refreshToken,
    accessExpiresAt,
    refreshExpiresAt,
    device: deviceFromRow(device),
    accountID,
    pet: publicPetFromRow(pet),
    isPrimaryAgentDevice: account.primary_agent_device_id === deviceID
  };
}

export async function rotateRefreshToken(
  db: D1Database,
  pepper: string,
  refreshToken: string,
  now = Date.now()
): Promise<SessionTokens> {
  const refreshHash = await hashToken(refreshToken, pepper);
  const current = await db.prepare(`
    SELECT sessions.id, sessions.account_id, sessions.device_id,
           devices.display_name, devices.platform, devices.app_version
    FROM sessions
    JOIN devices ON devices.id = sessions.device_id
    WHERE sessions.refresh_token_hash = ?
      AND sessions.refresh_expires_at_ms > ?
      AND sessions.revoked_at_ms IS NULL
      AND devices.revoked_at_ms IS NULL
  `).bind(refreshHash, now).first<{
    id: string; account_id: string; device_id: string; display_name: string;
    platform: "macos"; app_version: string;
  }>();
  if (!current) throw notFound("session");
  const accessToken = randomToken();
  const nextRefreshToken = randomToken();
  const [accessHash, nextRefreshHash] = await Promise.all([
    hashToken(accessToken, pepper),
    hashToken(nextRefreshToken, pepper)
  ]);
  const sessionID = crypto.randomUUID();
  const accessExpiresAt = now + 15 * 60 * 1_000;
  const refreshExpiresAt = now + 30 * 24 * 60 * 60 * 1_000;

  // The replacement is inserted only while the presented session remains live,
  // then the old row is revoked in the same D1 transaction. Concurrent uses of
  // one refresh token therefore produce at most one durable replacement.
  await db.batch([
    db.prepare(`
      INSERT INTO sessions(
        id, account_id, device_id, access_token_hash, refresh_token_hash,
        access_expires_at_ms, refresh_expires_at_ms, revoked_at_ms, created_at_ms
      )
      SELECT ?, account_id, device_id, ?, ?, ?, ?, NULL, ?
      FROM sessions
      WHERE id = ? AND revoked_at_ms IS NULL AND refresh_expires_at_ms > ?
    `).bind(
      sessionID, accessHash, nextRefreshHash, accessExpiresAt, refreshExpiresAt,
      now, current.id, now
    ),
    db.prepare(`
      UPDATE sessions SET revoked_at_ms = ?
      WHERE id = ? AND revoked_at_ms IS NULL
        AND EXISTS (SELECT 1 FROM sessions WHERE id = ?)
    `).bind(now, current.id, sessionID)
  ]);

  const [inserted, device, pet, account] = await Promise.all([
    db.prepare("SELECT id FROM sessions WHERE id = ?").bind(sessionID).first(),
    db.prepare("SELECT * FROM devices WHERE id = ? AND account_id = ?")
      .bind(current.device_id, current.account_id).first<DeviceRow>(),
    db.prepare("SELECT * FROM pets WHERE owner_account_id = ?")
      .bind(current.account_id).first<PetRow>(),
    db.prepare("SELECT primary_agent_device_id FROM accounts WHERE id = ?")
      .bind(current.account_id).first<{ primary_agent_device_id: string | null }>()
  ]);
  if (!inserted) throw notFound("session");
  if (!device || !pet || !account) throw notFound("account");
  return {
    accessToken,
    refreshToken: nextRefreshToken,
    accessExpiresAt,
    refreshExpiresAt,
    device: deviceFromRow(device),
    accountID: current.account_id,
    pet: publicPetFromRow(pet),
    isPrimaryAgentDevice: account.primary_agent_device_id === current.device_id
  };
}

export async function revokeSession(db: D1Database, sessionID: string, now = Date.now()): Promise<void> {
  await db.prepare("UPDATE sessions SET revoked_at_ms = ? WHERE id = ? AND revoked_at_ms IS NULL")
    .bind(now, sessionID).run();
}

export async function currentAccount(db: D1Database, context: AuthContext) {
  const account = await db.prepare(`
    SELECT id, display_name, primary_agent_device_id, created_at_ms, updated_at_ms
    FROM accounts WHERE id = ?
  `).bind(context.accountID).first<{
    id: string; display_name: string; primary_agent_device_id: string | null;
    created_at_ms: number; updated_at_ms: number;
  }>();
  const pet = await db.prepare("SELECT * FROM pets WHERE owner_account_id = ?")
    .bind(context.accountID).first<PetRow>();
  if (!account || !pet) throw notFound("account");
  return {
    account: {
      id: account.id,
      displayName: account.display_name,
      primaryAgentDeviceID: account.primary_agent_device_id,
      createdAt: account.created_at_ms,
      updatedAt: account.updated_at_ms
    },
    pet: publicPetFromRow(pet)
  };
}

export async function updateProfile(
  db: D1Database,
  context: AuthContext,
  input: { accountName: string; petName: string },
  now = Date.now()
) {
  await db.batch([
    db.prepare("UPDATE accounts SET display_name = ?, updated_at_ms = ? WHERE id = ?")
      .bind(input.accountName, now, context.accountID),
    db.prepare("UPDATE pets SET display_name = ?, updated_at_ms = ? WHERE id = ? AND owner_account_id = ?")
      .bind(input.petName, now, context.petID, context.accountID)
  ]);
  return currentAccount(db, context);
}

export async function claimPrimaryAgentDevice(
  db: D1Database,
  context: AuthContext,
  deviceID: string,
  now = Date.now()
): Promise<{ previousDeviceID: string | null; currentDeviceID: string }> {
  const device = await db.prepare(`
    SELECT id FROM devices WHERE id = ? AND account_id = ? AND revoked_at_ms IS NULL
  `).bind(deviceID, context.accountID).first();
  if (!device) throw notFound("device");
  const account = await db.prepare("SELECT primary_agent_device_id FROM accounts WHERE id = ?")
    .bind(context.accountID).first<{ primary_agent_device_id: string | null }>();
  if (!account) throw notFound("account");
  await db.prepare("UPDATE accounts SET primary_agent_device_id = ?, updated_at_ms = ? WHERE id = ?")
    .bind(deviceID, now, context.accountID).run();
  return { previousDeviceID: account.primary_agent_device_id, currentDeviceID: deviceID };
}
