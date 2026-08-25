CREATE TABLE letters (
  id TEXT PRIMARY KEY,
  visit_id TEXT NOT NULL REFERENCES visits(id),
  friendship_id TEXT NOT NULL REFERENCES friendships(id),
  author_account_id TEXT NOT NULL REFERENCES accounts(id),
  recipient_account_id TEXT NOT NULL REFERENCES accounts(id),
  ciphertext TEXT NOT NULL,
  iv TEXT NOT NULL,
  key_version INTEGER NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('attached', 'delivered')),
  created_at_ms INTEGER NOT NULL,
  delivered_at_ms INTEGER
) STRICT;

CREATE INDEX letters_visit_status ON letters(visit_id, status, created_at_ms);
