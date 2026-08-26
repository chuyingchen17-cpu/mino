ALTER TABLE accounts RENAME COLUMN apple_subject TO provider_subject;

CREATE TABLE oauth_device_flows (
  device_code_hash TEXT PRIMARY KEY,
  provider TEXT NOT NULL CHECK (provider IN ('github')),
  interval_ms INTEGER NOT NULL CHECK (interval_ms >= 1000),
  next_poll_at_ms INTEGER NOT NULL,
  expires_at_ms INTEGER NOT NULL,
  consumed_at_ms INTEGER,
  created_at_ms INTEGER NOT NULL
) STRICT;

CREATE INDEX oauth_device_flows_expiry
ON oauth_device_flows(expires_at_ms, consumed_at_ms);
