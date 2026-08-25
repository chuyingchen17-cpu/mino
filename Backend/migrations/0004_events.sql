CREATE TABLE account_events (
  sequence INTEGER PRIMARY KEY AUTOINCREMENT,
  id TEXT NOT NULL UNIQUE,
  schema_version INTEGER NOT NULL,
  recipient_account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  friendship_id TEXT REFERENCES friendships(id),
  type TEXT NOT NULL,
  aggregate_type TEXT NOT NULL,
  aggregate_id TEXT NOT NULL,
  aggregate_version INTEGER,
  payload_json TEXT NOT NULL CHECK (json_valid(payload_json) AND length(payload_json) <= 32768),
  timeline_visible INTEGER NOT NULL CHECK (timeline_visible IN (0, 1)),
  occurred_at_ms INTEGER NOT NULL
) STRICT;

CREATE INDEX account_events_recipient_sequence
ON account_events(recipient_account_id, sequence);

CREATE INDEX account_events_recipient_timeline_sequence
ON account_events(recipient_account_id, timeline_visible, sequence);

CREATE INDEX account_events_aggregate_version
ON account_events(aggregate_type, aggregate_id, aggregate_version);

CREATE TABLE idempotency_records (
  account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  operation TEXT NOT NULL,
  idempotency_key TEXT NOT NULL,
  request_fingerprint TEXT NOT NULL,
  response_status INTEGER NOT NULL,
  response_json TEXT NOT NULL CHECK (json_valid(response_json) AND length(response_json) <= 65536),
  created_at_ms INTEGER NOT NULL,
  PRIMARY KEY (account_id, operation, idempotency_key)
) WITHOUT ROWID, STRICT;
