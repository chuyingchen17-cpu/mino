CREATE TABLE friendships (
  id TEXT PRIMARY KEY,
  requester_account_id TEXT NOT NULL REFERENCES accounts(id),
  addressee_account_id TEXT NOT NULL REFERENCES accounts(id),
  pair_key TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('pending', 'accepted', 'rejected', 'closed')),
  version INTEGER NOT NULL DEFAULT 1,
  last_transition_id TEXT NOT NULL,
  created_at_ms INTEGER NOT NULL,
  responded_at_ms INTEGER,
  closed_at_ms INTEGER,
  CHECK (requester_account_id <> addressee_account_id)
) STRICT;

CREATE UNIQUE INDEX friendship_open_pair
ON friendships(pair_key)
WHERE status IN ('pending', 'accepted');

CREATE INDEX friendships_requester ON friendships(requester_account_id, status, created_at_ms);
CREATE INDEX friendships_addressee ON friendships(addressee_account_id, status, created_at_ms);
