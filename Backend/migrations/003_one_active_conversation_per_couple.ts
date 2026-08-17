import { type Kysely, sql } from "kysely";
import type { Database } from "../src/database/schema.js";

export async function up(db: Kysely<Database>): Promise<void> {
  // Existing development databases may predate the one-active-conversation
  // invariant. Keep the newest active conversation in each couple and close
  // the rest before installing the constraint so the upgrade is deterministic.
  await sql`
    WITH ranked_active AS (
      SELECT
        id,
        row_number() OVER (
          PARTITION BY couple_id
          ORDER BY created_at DESC, id DESC
        ) AS active_rank
      FROM conversations
      WHERE status = 'active'
    )
    UPDATE conversations AS conversation
    SET
      status = 'ended',
      next_speaker_pet_id = NULL,
      ended_at = COALESCE(conversation.ended_at, now())
    FROM ranked_active
    WHERE conversation.id = ranked_active.id
      AND ranked_active.active_rank > 1
  `.execute(db);

  await sql`
    CREATE UNIQUE INDEX one_active_conversation_per_couple
    ON conversations (couple_id)
    WHERE status = 'active'
  `.execute(db);
}

export async function down(db: Kysely<Database>): Promise<void> {
  await sql`DROP INDEX IF EXISTS one_active_conversation_per_couple`.execute(db);
}
