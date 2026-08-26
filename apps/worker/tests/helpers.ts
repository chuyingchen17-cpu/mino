import { env, exports } from "cloudflare:workers";

export interface DevProfile {
  profile: "alice" | "bob" | "charlie";
  token: string;
  refreshToken: string;
  accountID: string;
  deviceID: string;
  petID: string;
  friends: Array<{ friendshipID: string; accountID: string; petID: string }>;
}

export async function resetDatabase(): Promise<void> {
  for (const table of [
    "oauth_device_flows",
    "model_inferences", "letters", "conversation_messages", "conversations",
    "idempotency_records", "account_events", "visit_interaction_stats", "pet_interactions",
    "pet_familiarities", "pet_care_states", "visit_actions", "visits",
    "friendships", "sessions", "devices", "pets", "accounts"
  ]) {
    await env.DB.prepare(`DELETE FROM ${table}`).run();
  }
}

export async function request(
  path: string,
  options: { method?: string; token?: string; key?: string; body?: unknown; headers?: HeadersInit } = {}
): Promise<Response> {
  const headers = new Headers(options.headers);
  if (options.token) headers.set("authorization", `Bearer ${options.token}`);
  if (options.key) headers.set("idempotency-key", options.key);
  if (options.body !== undefined) headers.set("content-type", "application/json");
  return exports.default.fetch(`https://mino.test${path}`, {
    method: options.method ?? (options.body === undefined ? "GET" : "POST"),
    headers,
    ...(options.body !== undefined ? { body: JSON.stringify(options.body) } : {})
  });
}

export async function bootstrap(profile: DevProfile["profile"]): Promise<DevProfile> {
  const response = await request("/v1/dev/bootstrap", { body: { profile } });
  if (!response.ok) throw new Error(`bootstrap ${profile} failed: ${await response.text()}`);
  return (await response.json() as { data: DevProfile }).data;
}

export async function bootstrapAll() {
  const alice = await bootstrap("alice");
  const bob = await bootstrap("bob");
  const charlie = await bootstrap("charlie");
  return { alice, bob, charlie };
}

export async function jsonData<T>(response: Response): Promise<T> {
  return (await response.json() as { data: T }).data;
}

export function key(): string {
  return crypto.randomUUID();
}

export async function acceptVisit(visitor: DevProfile, host: DevProfile) {
  const created = await request("/v1/visits", {
    token: visitor.token,
    key: key(),
    body: {
      friendshipID: visitor.friends[0]!.friendshipID,
      visitorPetID: visitor.petID,
      hostAccountID: host.accountID,
      reason: "test visit"
    }
  });
  const visit = await jsonData<{ id: string }>(created);
  const accepted = await request(`/v1/visits/${visit.id}/respond`, {
    token: host.token,
    key: key(),
    body: { response: "accept", actorType: "human" }
  });
  return jsonData<{ id: string; status: string }>(accepted);
}
