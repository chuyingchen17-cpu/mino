CREATE TABLE visits (
  id TEXT PRIMARY KEY,
  friendship_id TEXT NOT NULL REFERENCES friendships(id),
  visitor_pet_id TEXT NOT NULL REFERENCES pets(id),
  visitor_owner_account_id TEXT NOT NULL REFERENCES accounts(id),
  host_account_id TEXT NOT NULL REFERENCES accounts(id),
  requested_by_account_id TEXT NOT NULL REFERENCES accounts(id),
  responder_account_id TEXT NOT NULL REFERENCES accounts(id),
  status TEXT NOT NULL CHECK (status IN ('pending', 'active', 'closed')),
  close_reason TEXT CHECK (close_reason IN (
    'declined', 'cancelled', 'expired', 'recalled', 'sent_home', 'friendship_closed'
  )),
  reason TEXT CHECK (reason IS NULL OR length(reason) <= 240),
  version INTEGER NOT NULL DEFAULT 1,
  last_transition_id TEXT NOT NULL,
  created_at_ms INTEGER NOT NULL,
  expires_at_ms INTEGER NOT NULL,
  started_at_ms INTEGER,
  closed_at_ms INTEGER,
  CHECK (visitor_owner_account_id <> host_account_id)
) STRICT;

CREATE UNIQUE INDEX one_active_visit_per_visitor
ON visits(visitor_pet_id) WHERE status = 'active';

CREATE UNIQUE INDEX one_active_visit_per_host
ON visits(host_account_id) WHERE status = 'active';

CREATE UNIQUE INDEX one_pending_visit_per_pair
ON visits(visitor_pet_id, host_account_id) WHERE status = 'pending';

CREATE INDEX visits_friendship_status ON visits(friendship_id, status, created_at_ms);
CREATE INDEX visits_responder_status ON visits(responder_account_id, status, created_at_ms);

CREATE TABLE visit_actions (
  id TEXT PRIMARY KEY,
  visit_id TEXT NOT NULL REFERENCES visits(id) ON DELETE CASCADE,
  sender_account_id TEXT NOT NULL REFERENCES accounts(id),
  actor_type TEXT NOT NULL CHECK (actor_type IN ('human', 'pet_agent', 'system')),
  kind TEXT NOT NULL CHECK (kind IN (
    'feed', 'play', 'pet', 'hug', 'kiss', 'flower', 'walk', 'message',
    'reaction', 'activity', 'speech', 'acknowledgement'
  )),
  payload_json TEXT NOT NULL CHECK (json_valid(payload_json) AND length(payload_json) <= 8192),
  reply_to_action_id TEXT REFERENCES visit_actions(id),
  requires_response INTEGER NOT NULL CHECK (requires_response IN (0, 1)),
  created_at_ms INTEGER NOT NULL
) STRICT;

CREATE UNIQUE INDEX one_reply_per_visit_action
ON visit_actions(reply_to_action_id) WHERE reply_to_action_id IS NOT NULL;

CREATE INDEX visit_actions_unresolved
ON visit_actions(visit_id, requires_response, created_at_ms);
