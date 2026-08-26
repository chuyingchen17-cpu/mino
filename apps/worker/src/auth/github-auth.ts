import { badRequest, upstreamUnavailable } from "../errors";
import { hashToken } from "../security/tokens";

const githubHeaders = {
  accept: "application/json",
  "content-type": "application/x-www-form-urlencoded",
  "user-agent": "Mino"
};

export interface GitHubDeviceAuthorization {
  deviceCode: string;
  userCode: string;
  verificationURI: string;
  expiresIn: number;
  interval: number;
}

export type GitHubDevicePoll =
  | { status: "pending"; retryAfterSeconds: number }
  | { status: "slow_down"; retryAfterSeconds: number }
  | { status: "authorized"; accessToken: string }
  | { status: "expired" }
  | { status: "denied" };

export interface GitHubIdentity {
  subject: string;
  login: string;
}

export async function startGitHubDeviceAuthorization(
  clientID: string
): Promise<GitHubDeviceAuthorization> {
  const response = await fetch("https://github.com/login/device/code", {
    method: "POST",
    headers: githubHeaders,
    body: new URLSearchParams({ client_id: clientID })
  });
  if (!response.ok) {
    throw upstreamUnavailable("github_unavailable", "GitHub authentication is unavailable");
  }
  const body = await response.json() as Record<string, unknown>;
  if (typeof body.device_code !== "string" || typeof body.user_code !== "string" ||
      typeof body.verification_uri !== "string" || typeof body.expires_in !== "number" ||
      typeof body.interval !== "number" || body.expires_in < 1 || body.interval < 1) {
    throw upstreamUnavailable("github_invalid_response", "GitHub returned an invalid authorization response");
  }
  return {
    deviceCode: body.device_code,
    userCode: body.user_code,
    verificationURI: body.verification_uri,
    expiresIn: body.expires_in,
    interval: body.interval
  };
}

export async function pollGitHubDeviceAuthorization(
  clientID: string,
  deviceCode: string,
  retryAfterSeconds: number
): Promise<GitHubDevicePoll> {
  const response = await fetch("https://github.com/login/oauth/access_token", {
    method: "POST",
    headers: githubHeaders,
    body: new URLSearchParams({
      client_id: clientID,
      device_code: deviceCode,
      grant_type: "urn:ietf:params:oauth:grant-type:device_code"
    })
  });
  if (!response.ok) {
    throw upstreamUnavailable("github_unavailable", "GitHub authentication is unavailable");
  }
  const body = await response.json() as Record<string, unknown>;
  if (typeof body.access_token === "string" && body.access_token.length > 0) {
    return { status: "authorized", accessToken: body.access_token };
  }
  switch (body.error) {
    case "authorization_pending":
      return { status: "pending", retryAfterSeconds };
    case "slow_down":
      return { status: "slow_down", retryAfterSeconds: retryAfterSeconds + 5 };
    case "expired_token":
      return { status: "expired" };
    case "access_denied":
      return { status: "denied" };
    default:
      throw badRequest("github_authorization_failed", "GitHub authorization failed");
  }
}

export async function fetchGitHubIdentity(accessToken: string): Promise<GitHubIdentity> {
  const response = await fetch("https://api.github.com/user", {
    headers: {
      accept: "application/vnd.github+json",
      authorization: `Bearer ${accessToken}`,
      "user-agent": "Mino",
      "x-github-api-version": "2022-11-28"
    }
  });
  if (!response.ok) throw badRequest("github_identity_invalid", "GitHub identity could not be verified");
  const body = await response.json() as Record<string, unknown>;
  if (!Number.isSafeInteger(body.id) || typeof body.login !== "string" || body.login.length < 1) {
    throw upstreamUnavailable("github_invalid_response", "GitHub returned an invalid user identity");
  }
  return { subject: String(body.id), login: body.login.slice(0, 40) };
}

export async function rememberGitHubDeviceFlow(
  db: D1Database,
  pepper: string,
  authorization: GitHubDeviceAuthorization,
  now = Date.now()
): Promise<void> {
  const hash = await hashToken(authorization.deviceCode, pepper);
  await db.prepare(`
    INSERT INTO oauth_device_flows(
      device_code_hash, provider, interval_ms, next_poll_at_ms,
      expires_at_ms, consumed_at_ms, created_at_ms
    ) VALUES (?, 'github', ?, ?, ?, NULL, ?)
  `).bind(
    hash,
    authorization.interval * 1_000,
    now + authorization.interval * 1_000,
    now + authorization.expiresIn * 1_000,
    now
  ).run();
}

interface DeviceFlowRow {
  interval_ms: number;
  next_poll_at_ms: number;
  expires_at_ms: number;
  consumed_at_ms: number | null;
}

export async function claimGitHubDevicePoll(
  db: D1Database,
  pepper: string,
  deviceCode: string,
  now = Date.now()
): Promise<{ poll: boolean; retryAfterSeconds: number; hash: string }> {
  const hash = await hashToken(deviceCode, pepper);
  const row = await db.prepare(`
    SELECT interval_ms, next_poll_at_ms, expires_at_ms, consumed_at_ms
    FROM oauth_device_flows WHERE device_code_hash = ? AND provider = 'github'
  `).bind(hash).first<DeviceFlowRow>();
  if (!row || row.consumed_at_ms !== null || row.expires_at_ms <= now) {
    throw badRequest("github_device_code_invalid", "GitHub device authorization expired or is invalid");
  }
  if (row.next_poll_at_ms > now) {
    return {
      poll: false,
      retryAfterSeconds: Math.max(1, Math.ceil((row.next_poll_at_ms - now) / 1_000)),
      hash
    };
  }
  const leaseUntil = now + Math.max(row.interval_ms, 30_000);
  const claimed = await db.prepare(`
    UPDATE oauth_device_flows SET next_poll_at_ms = ?
    WHERE device_code_hash = ? AND consumed_at_ms IS NULL
      AND expires_at_ms > ? AND next_poll_at_ms <= ?
  `).bind(leaseUntil, hash, now, now).run();
  if (claimed.meta.changes !== 1) {
    return { poll: false, retryAfterSeconds: Math.ceil(row.interval_ms / 1_000), hash };
  }
  return { poll: true, retryAfterSeconds: Math.ceil(row.interval_ms / 1_000), hash };
}

export async function rescheduleGitHubDevicePoll(
  db: D1Database,
  hash: string,
  retryAfterSeconds: number,
  now = Date.now()
): Promise<void> {
  await db.prepare(`
    UPDATE oauth_device_flows
    SET interval_ms = ?, next_poll_at_ms = ?
    WHERE device_code_hash = ? AND consumed_at_ms IS NULL
  `).bind(retryAfterSeconds * 1_000, now + retryAfterSeconds * 1_000, hash).run();
}

export async function consumeGitHubDeviceFlow(
  db: D1Database,
  hash: string,
  now = Date.now()
): Promise<void> {
  await db.prepare(`
    UPDATE oauth_device_flows SET consumed_at_ms = ?
    WHERE device_code_hash = ? AND consumed_at_ms IS NULL
  `).bind(now, hash).run();
}
