CREATE TABLE conversations (
  id TEXT PRIMARY KEY,
  friendship_id TEXT NOT NULL REFERENCES friendships(id),
  initiator_pet_id TEXT NOT NULL REFERENCES pets(id),
  recipient_pet_id TEXT NOT NULL REFERENCES pets(id),
  status TEXT NOT NULL CHECK (status IN ('active', 'ended')),
  next_speaker_pet_id TEXT REFERENCES pets(id),
  turn_count INTEGER NOT NULL DEFAULT 0 CHECK (turn_count BETWEEN 0 AND 6),
  version INTEGER NOT NULL DEFAULT 1,
  created_at_ms INTEGER NOT NULL,
  ended_at_ms INTEGER
) STRICT;

CREATE UNIQUE INDEX one_active_conversation_per_friendship
ON conversations(friendship_id) WHERE status = 'active';

CREATE TABLE conversation_messages (
  id TEXT PRIMARY KEY,
  conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  sender_account_id TEXT NOT NULL REFERENCES accounts(id),
  actor_type TEXT NOT NULL CHECK (actor_type IN ('human', 'pet_agent')),
  body TEXT NOT NULL CHECK (length(body) BETWEEN 1 AND 500),
  turn_index INTEGER,
  created_at_ms INTEGER NOT NULL
) STRICT;

CREATE UNIQUE INDEX one_pet_turn_per_conversation
ON conversation_messages(conversation_id, turn_index)
WHERE turn_index IS NOT NULL;
