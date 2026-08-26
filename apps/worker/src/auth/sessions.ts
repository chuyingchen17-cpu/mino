import type { SessionTokens } from "../storage/accounts-repository";
import { issueSession } from "../storage/accounts-repository";

export async function sessionForProviderIdentity(
  db: D1Database,
  pepper: string,
  provider: "github" | "qq",
  providerSubject: string,
  suggestedDisplayName: string,
  device: { id?: string; displayName: string; platform: "macos"; appVersion: string },
  now = Date.now()
): Promise<SessionTokens> {
  const identityKey = `${provider}:${providerSubject}`;
  let account = await db.prepare("SELECT id FROM accounts WHERE provider_subject = ?")
    .bind(identityKey).first<{ id: string }>();
  if (!account) {
    const accountID = crypto.randomUUID();
    const petID = crypto.randomUUID();
    const displayName = suggestedDisplayName.trim().slice(0, 40) || "Mino User";
    await db.batch([
      db.prepare(`
        INSERT INTO accounts(id, provider_subject, display_name, primary_agent_device_id, created_at_ms, updated_at_ms)
        VALUES (?, ?, ?, NULL, ?, ?)
      `).bind(accountID, identityKey, displayName, now, now),
      db.prepare(`
        INSERT INTO pets(
          id, owner_account_id, display_name, appearance_schema_version,
          appearance_catalog_version, appearance_json, appearance_version,
          created_at_ms, updated_at_ms
        ) VALUES (?, ?, 'Mino', 1, 1, '{"rigID":"mino-default","body":"default"}', 1, ?, ?)
      `).bind(petID, accountID, now, now)
    ]);
    account = { id: accountID };
  }
  return issueSession(db, pepper, account.id, {
    ...(device.id ? { deviceID: device.id } : {}),
    displayName: device.displayName,
    platform: device.platform,
    appVersion: device.appVersion
  }, now);
}
