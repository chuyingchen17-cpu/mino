export interface AccountEvent {
  sequence: number;
  id: string;
  schemaVersion: number;
  recipientAccountID: string;
  friendshipID: string | null;
  type: string;
  aggregateType: string;
  aggregateID: string;
  aggregateVersion: number | null;
  payload: Record<string, unknown>;
  timelineVisible: boolean;
  occurredAt: number;
}

export interface AccountEventRow {
  sequence: number;
  id: string;
  schema_version: number;
  recipient_account_id: string;
  friendship_id: string | null;
  type: string;
  aggregate_type: string;
  aggregate_id: string;
  aggregate_version: number | null;
  payload_json: string;
  timeline_visible: number;
  occurred_at_ms: number;
}

export function accountEventFromRow(row: AccountEventRow): AccountEvent {
  return {
    sequence: row.sequence,
    id: row.id,
    schemaVersion: row.schema_version,
    recipientAccountID: row.recipient_account_id,
    friendshipID: row.friendship_id,
    type: row.type,
    aggregateType: row.aggregate_type,
    aggregateID: row.aggregate_id,
    aggregateVersion: row.aggregate_version,
    payload: JSON.parse(row.payload_json) as Record<string, unknown>,
    timelineVisible: row.timeline_visible === 1,
    occurredAt: row.occurred_at_ms
  };
}

export interface PendingAccountEvent {
  recipientAccountID: string;
  friendshipID?: string | null;
  type: string;
  aggregateType: string;
  aggregateID: string;
  aggregateVersion?: number | null;
  payload: Record<string, unknown>;
  timelineVisible: boolean;
  occurredAt: number;
}
