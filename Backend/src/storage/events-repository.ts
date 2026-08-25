import type { AccountEvent, AccountEventRow, PendingAccountEvent } from "../domain/account-event";
import { accountEventFromRow } from "../domain/account-event";
import { conflict } from "../errors";

export interface IdempotencyReceipt<T> {
  data: T;
  status: number;
}

export async function readIdempotency<T>(
  db: D1Database,
  accountID: string,
  operation: string,
  key: string,
  fingerprint: string
): Promise<IdempotencyReceipt<T> | null> {
  const row = await db.prepare(`
    SELECT request_fingerprint, response_status, response_json
    FROM idempotency_records
    WHERE account_id = ? AND operation = ? AND idempotency_key = ?
  `).bind(accountID, operation, key).first<{
    request_fingerprint: string;
    response_status: number;
    response_json: string;
  }>();
  if (!row) return null;
  if (row.request_fingerprint !== fingerprint) {
    throw conflict("idempotency_key_reused", "The idempotency key was reused with a different request");
  }
  return { data: JSON.parse(row.response_json) as T, status: row.response_status };
}

export function idempotencyStatement(
  db: D1Database,
  accountID: string,
  operation: string,
  key: string,
  fingerprint: string,
  status: number,
  response: unknown,
  now: number
): D1PreparedStatement {
  return db.prepare(`
    INSERT INTO idempotency_records(
      account_id, operation, idempotency_key, request_fingerprint,
      response_status, response_json, created_at_ms
    ) VALUES (?, ?, ?, ?, ?, ?, ?)
  `).bind(accountID, operation, key, fingerprint, status, JSON.stringify(response), now);
}

export function accountEventStatement(db: D1Database, event: PendingAccountEvent): D1PreparedStatement {
  return db.prepare(`
    INSERT INTO account_events(
      id, schema_version, recipient_account_id, friendship_id, type,
      aggregate_type, aggregate_id, aggregate_version, payload_json,
      timeline_visible, occurred_at_ms
    ) VALUES (?, 1, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `).bind(
    crypto.randomUUID(),
    event.recipientAccountID,
    event.friendshipID ?? null,
    event.type,
    event.aggregateType,
    event.aggregateID,
    event.aggregateVersion ?? null,
    JSON.stringify(event.payload),
    event.timelineVisible ? 1 : 0,
    event.occurredAt
  );
}

type MarkerTable = "accounts" | "friendships" | "visits" | "visit_actions" | "conversations" | "conversation_messages" | "letters" | "pets" | "pet_interactions";
type MarkerColumn = "last_transition_id" | "id" | "appearance_version" | "version" | "primary_agent_device_id";

export function accountEventFromMarkerStatement(
  db: D1Database,
  event: PendingAccountEvent,
  table: MarkerTable,
  markerColumn: MarkerColumn,
  aggregateID: string,
  markerValue: string | number
): D1PreparedStatement {
  return db.prepare(`
    INSERT INTO account_events(
      id, schema_version, recipient_account_id, friendship_id, type,
      aggregate_type, aggregate_id, aggregate_version, payload_json,
      timeline_visible, occurred_at_ms
    )
    SELECT ?, 1, ?, ?, ?, ?, ?, ?, ?, ?, ?
    FROM ${table}
    WHERE id = ? AND ${markerColumn} = ?
  `).bind(
    crypto.randomUUID(),
    event.recipientAccountID,
    event.friendshipID ?? null,
    event.type,
    event.aggregateType,
    event.aggregateID,
    event.aggregateVersion ?? null,
    JSON.stringify(event.payload),
    event.timelineVisible ? 1 : 0,
    event.occurredAt,
    aggregateID,
    markerValue
  );
}

export function idempotencyFromMarkerStatement(
  db: D1Database,
  accountID: string,
  operation: string,
  key: string,
  fingerprint: string,
  status: number,
  response: unknown,
  now: number,
  table: MarkerTable,
  markerColumn: MarkerColumn,
  aggregateID: string,
  markerValue: string | number
): D1PreparedStatement {
  return db.prepare(`
    INSERT INTO idempotency_records(
      account_id, operation, idempotency_key, request_fingerprint,
      response_status, response_json, created_at_ms
    )
    SELECT ?, ?, ?, ?, ?, ?, ?
    FROM ${table}
    WHERE id = ? AND ${markerColumn} = ?
  `).bind(
    accountID,
    operation,
    key,
    fingerprint,
    status,
    JSON.stringify(response),
    now,
    aggregateID,
    markerValue
  );
}

export async function fetchAccountEvents(
  db: D1Database,
  accountID: string,
  after: number,
  limit: number,
  timelineOnly = false
): Promise<{ events: AccountEvent[]; nextCursor: number }> {
  const timeline = timelineOnly ? "AND timeline_visible = 1" : "";
  const result = await db.prepare(`
    SELECT * FROM account_events
    WHERE recipient_account_id = ? AND sequence > ? ${timeline}
    ORDER BY sequence ASC LIMIT ?
  `).bind(accountID, after, limit).all<AccountEventRow>();
  const events = result.results.map(accountEventFromRow);
  return { events, nextCursor: events.at(-1)?.sequence ?? after };
}

export async function currentAccountCursor(db: D1Database, accountID: string): Promise<number> {
  const row = await db.prepare(`
    SELECT COALESCE(MAX(sequence), 0) AS cursor FROM account_events WHERE recipient_account_id = ?
  `).bind(accountID).first<{ cursor: number }>();
  return row?.cursor ?? 0;
}
