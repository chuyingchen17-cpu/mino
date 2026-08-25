PRAGMA foreign_keys = ON;

CREATE TABLE accounts (
  id TEXT PRIMARY KEY,
  apple_subject TEXT UNIQUE,
  display_name TEXT NOT NULL CHECK (length(display_name) BETWEEN 1 AND 40),
  primary_agent_device_id TEXT,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL
) STRICT;

CREATE TABLE devices (
  id TEXT PRIMARY KEY,
  account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  display_name TEXT NOT NULL CHECK (length(display_name) BETWEEN 1 AND 80),
  platform TEXT NOT NULL CHECK (platform IN ('macos')),
  app_version TEXT NOT NULL CHECK (length(app_version) BETWEEN 1 AND 40),
  created_at_ms INTEGER NOT NULL,
  revoked_at_ms INTEGER
) STRICT;

CREATE INDEX devices_account ON devices(account_id, created_at_ms);

CREATE TABLE sessions (
  id TEXT PRIMARY KEY,
  account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  device_id TEXT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  access_token_hash TEXT NOT NULL UNIQUE,
  refresh_token_hash TEXT NOT NULL UNIQUE,
  access_expires_at_ms INTEGER NOT NULL,
  refresh_expires_at_ms INTEGER NOT NULL,
  revoked_at_ms INTEGER,
  created_at_ms INTEGER NOT NULL
) STRICT;

CREATE INDEX sessions_access_lookup ON sessions(access_token_hash, access_expires_at_ms);
CREATE INDEX sessions_refresh_lookup ON sessions(refresh_token_hash, refresh_expires_at_ms);

CREATE TABLE pets (
  id TEXT PRIMARY KEY,
  owner_account_id TEXT NOT NULL UNIQUE REFERENCES accounts(id) ON DELETE CASCADE,
  display_name TEXT NOT NULL CHECK (length(display_name) BETWEEN 1 AND 24),
  appearance_schema_version INTEGER NOT NULL DEFAULT 1,
  appearance_catalog_version INTEGER NOT NULL DEFAULT 1,
  appearance_json TEXT NOT NULL DEFAULT '{}'
    CHECK (json_valid(appearance_json) AND length(appearance_json) <= 8192),
  appearance_version INTEGER NOT NULL DEFAULT 1,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL
) STRICT;

CREATE TRIGGER accounts_primary_device_belongs_to_account
BEFORE UPDATE OF primary_agent_device_id ON accounts
WHEN NEW.primary_agent_device_id IS NOT NULL
 AND NOT EXISTS (
   SELECT 1 FROM devices
   WHERE id = NEW.primary_agent_device_id
     AND account_id = NEW.id
     AND revoked_at_ms IS NULL
 )
BEGIN
  SELECT RAISE(ABORT, 'primary_agent_device_invalid');
END;
