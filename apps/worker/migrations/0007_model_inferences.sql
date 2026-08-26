CREATE TABLE model_inferences (
  id TEXT PRIMARY KEY,
  account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  device_id TEXT NOT NULL REFERENCES devices(id),
  inference_id TEXT NOT NULL,
  provider TEXT NOT NULL,
  model TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('started', 'completed', 'failed')),
  request_fingerprint TEXT NOT NULL,
  response_json TEXT CHECK (response_json IS NULL OR json_valid(response_json)),
  input_tokens INTEGER NOT NULL DEFAULT 0,
  output_tokens INTEGER NOT NULL DEFAULT 0,
  claimed_at_ms INTEGER NOT NULL,
  completed_at_ms INTEGER,
  UNIQUE(account_id, inference_id)
) STRICT;
