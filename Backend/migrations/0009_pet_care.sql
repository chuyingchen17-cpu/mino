CREATE TABLE pet_care_states (
  pet_id TEXT PRIMARY KEY REFERENCES pets(id) ON DELETE CASCADE,
  fullness INTEGER NOT NULL DEFAULT 70 CHECK (fullness BETWEEN 0 AND 100),
  energy INTEGER NOT NULL DEFAULT 80 CHECK (energy BETWEEN 0 AND 100),
  mood INTEGER NOT NULL DEFAULT 70 CHECK (mood BETWEEN 0 AND 100),
  bond INTEGER NOT NULL DEFAULT 20 CHECK (bond BETWEEN 0 AND 100),
  version INTEGER NOT NULL DEFAULT 1,
  last_transition_id TEXT,
  evaluated_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL
) STRICT;

INSERT INTO pet_care_states(pet_id, evaluated_at_ms, updated_at_ms)
SELECT id, created_at_ms, created_at_ms FROM pets;

CREATE TABLE pet_familiarities (
  pet_id TEXT NOT NULL REFERENCES pets(id) ON DELETE CASCADE,
  friendship_id TEXT NOT NULL REFERENCES friendships(id) ON DELETE CASCADE,
  score INTEGER NOT NULL DEFAULT 0 CHECK (score BETWEEN 0 AND 100),
  version INTEGER NOT NULL DEFAULT 1,
  updated_at_ms INTEGER NOT NULL,
  PRIMARY KEY (pet_id, friendship_id)
) STRICT;

CREATE TABLE pet_interactions (
  id TEXT PRIMARY KEY,
  target_pet_id TEXT NOT NULL REFERENCES pets(id) ON DELETE CASCADE,
  actor_account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  friendship_id TEXT REFERENCES friendships(id) ON DELETE CASCADE,
  visit_id TEXT REFERENCES visits(id) ON DELETE CASCADE,
  kind TEXT NOT NULL CHECK (kind IN ('pet', 'feed', 'play', 'walk', 'rest', 'cuddle', 'flower')),
  outcome TEXT NOT NULL CHECK (outcome IN (
    'applied', 'cosmetic_only', 'too_full', 'too_tired', 'resting_cooldown'
  )),
  fullness_delta INTEGER NOT NULL DEFAULT 0,
  energy_delta INTEGER NOT NULL DEFAULT 0,
  mood_delta INTEGER NOT NULL DEFAULT 0,
  bond_delta INTEGER NOT NULL DEFAULT 0,
  familiarity_delta INTEGER NOT NULL DEFAULT 0,
  occurred_at_ms INTEGER NOT NULL,
  created_at_ms INTEGER NOT NULL
) STRICT;

CREATE INDEX pet_interactions_recent
ON pet_interactions(target_pet_id, actor_account_id, kind, created_at_ms DESC);

CREATE INDEX pet_interactions_visit
ON pet_interactions(visit_id, created_at_ms);

CREATE TABLE visit_interaction_stats (
  visit_id TEXT PRIMARY KEY REFERENCES visits(id) ON DELETE CASCADE,
  pet_count INTEGER NOT NULL DEFAULT 0,
  feed_count INTEGER NOT NULL DEFAULT 0,
  play_count INTEGER NOT NULL DEFAULT 0,
  walk_count INTEGER NOT NULL DEFAULT 0,
  rest_count INTEGER NOT NULL DEFAULT 0,
  cuddle_count INTEGER NOT NULL DEFAULT 0,
  flower_count INTEGER NOT NULL DEFAULT 0,
  familiarity_gained INTEGER NOT NULL DEFAULT 0,
  updated_at_ms INTEGER NOT NULL
) STRICT;
