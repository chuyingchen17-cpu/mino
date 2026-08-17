import type { ColumnType, Generated } from "kysely";

type Timestamp = ColumnType<Date, Date | string, Date | string>;
type GeneratedTimestamp = ColumnType<Date, Date | string | undefined, Date | string>;
type JSONValue = ColumnType<unknown, unknown, unknown>;

export interface AccountsTable {
  id: string;
  display_name: string;
  auth_token_hash: string;
  created_at: GeneratedTimestamp;
}

export interface CouplesTable {
  id: string;
  account_a_id: string;
  account_b_id: string;
  created_at: GeneratedTimestamp;
}

export interface FriendshipsTable {
  id: string;
  scope_id: string;
  requester_account_id: string;
  addressee_account_id: string;
  pair_key: string;
  status: string;
  request_idempotency_key: string;
  response_idempotency_key: string | null;
  created_at: GeneratedTimestamp;
  responded_at: Timestamp | null;
}

export interface PetsTable {
  id: string;
  couple_id: string | null;
  owner_account_id: string;
  display_name: string;
  created_at: GeneratedTimestamp;
}

export interface ConversationsTable {
  id: string;
  couple_id: string;
  initiator_pet_id: string;
  recipient_pet_id: string;
  status: string;
  next_speaker_pet_id: string | null;
  turn_count: number;
  created_at: GeneratedTimestamp;
  ended_at: Timestamp | null;
  idempotency_key: string;
}

export interface MessagesTable {
  id: string;
  conversation_id: string;
  couple_id: string;
  actor_type: string;
  actor_id: string;
  recipient_pet_id: string;
  body: string;
  turn_index: number | null;
  created_at: GeneratedTimestamp;
  idempotency_key: string;
}

export interface VisitsTable {
  id: string;
  couple_id: string;
  visitor_pet_id: string;
  visitor_owner_account_id: string;
  host_account_id: string;
  requested_by_account_id: string;
  reason: string | null;
  status: string;
  created_at: GeneratedTimestamp;
  started_at: Timestamp | null;
  ended_at: Timestamp | null;
  idempotency_key: string;
}

export interface LettersTable {
  id: string;
  couple_id: string;
  visit_id: string;
  author_account_id: string;
  recipient_account_id: string;
  body: string;
  status: string;
  created_at: GeneratedTimestamp;
  delivered_at: Timestamp | null;
  idempotency_key: string;
}

export interface CoupleEventsTable {
  sequence: Generated<string>;
  id: string;
  couple_id: string;
  type: string;
  actor_type: string;
  actor_id: string | null;
  payload: JSONValue;
  timeline_visible: boolean;
  occurred_at: GeneratedTimestamp;
}

export interface ModelUsageTable {
  id: string;
  couple_id: string | null;
  account_id: string;
  inference_id: string;
  provider: string;
  model: string;
  status: string;
  input_tokens: number;
  output_tokens: number;
  created_at: GeneratedTimestamp;
  completed_at: Timestamp | null;
  claimed_at: GeneratedTimestamp;
  request_fingerprint: string;
  response: JSONValue | null;
}

export interface IdempotencyRecordsTable {
  couple_id: string;
  scope: string;
  idempotency_key: string;
  response: JSONValue;
  request_fingerprint: string;
  created_at: GeneratedTimestamp;
}

export interface Database {
  accounts: AccountsTable;
  couples: CouplesTable;
  friendships: FriendshipsTable;
  pets: PetsTable;
  conversations: ConversationsTable;
  messages: MessagesTable;
  visits: VisitsTable;
  letters: LettersTable;
  couple_events: CoupleEventsTable;
  model_usage: ModelUsageTable;
  idempotency_records: IdempotencyRecordsTable;
}
