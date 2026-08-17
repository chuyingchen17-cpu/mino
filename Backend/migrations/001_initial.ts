import { type Kysely, sql } from "kysely";
import type { Database } from "../src/database/schema.js";

export async function up(db: Kysely<Database>): Promise<void> {
  await db.schema
    .createTable("accounts")
    .ifNotExists()
    .addColumn("id", "text", (column) => column.primaryKey())
    .addColumn("display_name", "text", (column) => column.notNull())
    .addColumn("auth_token_hash", "text", (column) => column.notNull().unique())
    .addColumn("created_at", "timestamptz", (column) => column.notNull().defaultTo(sql`now()`))
    .execute();

  await db.schema
    .createTable("couples")
    .ifNotExists()
    .addColumn("id", "text", (column) => column.primaryKey())
    .addColumn("account_a_id", "text", (column) => column.notNull().references("accounts.id"))
    .addColumn("account_b_id", "text", (column) => column.notNull().references("accounts.id"))
    .addColumn("created_at", "timestamptz", (column) => column.notNull().defaultTo(sql`now()`))
    .addCheckConstraint("couple_members_differ", sql`account_a_id <> account_b_id`)
    .execute();

  await db.schema
    .createTable("pets")
    .ifNotExists()
    .addColumn("id", "text", (column) => column.primaryKey())
    .addColumn("couple_id", "text", (column) => column.notNull().references("couples.id").onDelete("cascade"))
    .addColumn("owner_account_id", "text", (column) => column.notNull().references("accounts.id"))
    .addColumn("display_name", "text", (column) => column.notNull())
    .addColumn("created_at", "timestamptz", (column) => column.notNull().defaultTo(sql`now()`))
    .addUniqueConstraint("one_pet_per_owner_per_couple", ["couple_id", "owner_account_id"])
    .execute();

  await db.schema
    .createTable("conversations")
    .ifNotExists()
    .addColumn("id", "text", (column) => column.primaryKey())
    .addColumn("couple_id", "text", (column) => column.notNull().references("couples.id").onDelete("cascade"))
    .addColumn("initiator_pet_id", "text", (column) => column.notNull().references("pets.id"))
    .addColumn("recipient_pet_id", "text", (column) => column.notNull().references("pets.id"))
    .addColumn("status", "text", (column) => column.notNull())
    .addColumn("next_speaker_pet_id", "text", (column) => column.references("pets.id"))
    .addColumn("turn_count", "integer", (column) => column.notNull().defaultTo(0))
    .addColumn("created_at", "timestamptz", (column) => column.notNull().defaultTo(sql`now()`))
    .addColumn("ended_at", "timestamptz")
    .addColumn("idempotency_key", "text", (column) => column.notNull())
    .addUniqueConstraint("conversation_idempotency", ["couple_id", "idempotency_key"])
    .addCheckConstraint("conversation_status", sql`status IN ('active', 'ended')`)
    .addCheckConstraint("conversation_turn_limit", sql`turn_count BETWEEN 0 AND 6`)
    .execute();

  await db.schema
    .createTable("messages")
    .ifNotExists()
    .addColumn("id", "text", (column) => column.primaryKey())
    .addColumn("conversation_id", "text", (column) => column.notNull().references("conversations.id").onDelete("cascade"))
    .addColumn("couple_id", "text", (column) => column.notNull().references("couples.id").onDelete("cascade"))
    .addColumn("actor_type", "text", (column) => column.notNull())
    .addColumn("actor_id", "text", (column) => column.notNull())
    .addColumn("recipient_pet_id", "text", (column) => column.notNull().references("pets.id"))
    .addColumn("body", "text", (column) => column.notNull())
    .addColumn("turn_index", "integer")
    .addColumn("created_at", "timestamptz", (column) => column.notNull().defaultTo(sql`now()`))
    .addColumn("idempotency_key", "text", (column) => column.notNull())
    .addUniqueConstraint("message_idempotency", ["couple_id", "idempotency_key"])
    .addCheckConstraint("message_actor_type", sql`actor_type IN ('human', 'pet')`)
    .execute();

  await db.schema
    .createIndex("one_pet_turn_per_conversation")
    .ifNotExists()
    .unique()
    .on("messages")
    .columns(["conversation_id", "turn_index"])
    .where("turn_index", "is not", null)
    .execute();

  await db.schema
    .createTable("visits")
    .ifNotExists()
    .addColumn("id", "text", (column) => column.primaryKey())
    .addColumn("couple_id", "text", (column) => column.notNull().references("couples.id").onDelete("cascade"))
    .addColumn("visitor_pet_id", "text", (column) => column.notNull().references("pets.id"))
    .addColumn("visitor_owner_account_id", "text", (column) => column.notNull().references("accounts.id"))
    .addColumn("host_account_id", "text", (column) => column.notNull().references("accounts.id"))
    .addColumn("requested_by_account_id", "text", (column) => column.notNull().references("accounts.id"))
    .addColumn("reason", "text")
    .addColumn("status", "text", (column) => column.notNull())
    .addColumn("created_at", "timestamptz", (column) => column.notNull().defaultTo(sql`now()`))
    .addColumn("started_at", "timestamptz")
    .addColumn("ended_at", "timestamptz")
    .addColumn("idempotency_key", "text", (column) => column.notNull())
    .addUniqueConstraint("visit_idempotency", ["couple_id", "idempotency_key"])
    .addCheckConstraint("visit_status", sql`status IN ('pending', 'active', 'ended', 'cancelled')`)
    .addCheckConstraint("visitor_not_host", sql`visitor_owner_account_id <> host_account_id`)
    .execute();

  await sql`
    CREATE UNIQUE INDEX IF NOT EXISTS one_active_visit_per_couple
    ON visits (couple_id)
    WHERE status = 'active'
  `.execute(db);

  await db.schema
    .createTable("letters")
    .ifNotExists()
    .addColumn("id", "text", (column) => column.primaryKey())
    .addColumn("couple_id", "text", (column) => column.notNull().references("couples.id").onDelete("cascade"))
    .addColumn("visit_id", "text", (column) => column.notNull().references("visits.id").onDelete("cascade"))
    .addColumn("author_account_id", "text", (column) => column.notNull().references("accounts.id"))
    .addColumn("recipient_account_id", "text", (column) => column.notNull().references("accounts.id"))
    .addColumn("body", "text", (column) => column.notNull())
    .addColumn("status", "text", (column) => column.notNull())
    .addColumn("created_at", "timestamptz", (column) => column.notNull().defaultTo(sql`now()`))
    .addColumn("delivered_at", "timestamptz")
    .addColumn("idempotency_key", "text", (column) => column.notNull())
    .addUniqueConstraint("letter_idempotency", ["couple_id", "idempotency_key"])
    .addCheckConstraint("letter_status", sql`status IN ('carried', 'delivered')`)
    .execute();

  await db.schema
    .createTable("couple_events")
    .ifNotExists()
    .addColumn("sequence", "bigserial", (column) => column.primaryKey())
    .addColumn("id", "text", (column) => column.notNull().unique())
    .addColumn("couple_id", "text", (column) => column.notNull().references("couples.id").onDelete("cascade"))
    .addColumn("type", "text", (column) => column.notNull())
    .addColumn("actor_type", "text", (column) => column.notNull())
    .addColumn("actor_id", "text")
    .addColumn("payload", "jsonb", (column) => column.notNull().defaultTo(sql`'{}'::jsonb`))
    .addColumn("timeline_visible", "boolean", (column) => column.notNull().defaultTo(false))
    .addColumn("occurred_at", "timestamptz", (column) => column.notNull().defaultTo(sql`now()`))
    .addCheckConstraint("event_actor_type", sql`actor_type IN ('human', 'pet', 'system')`)
    .execute();

  await db.schema.createIndex("events_couple_sequence").ifNotExists().on("couple_events").columns(["couple_id", "sequence"]).execute();

  await db.schema
    .createTable("model_usage")
    .ifNotExists()
    .addColumn("id", "text", (column) => column.primaryKey())
    .addColumn("couple_id", "text", (column) => column.notNull().references("couples.id").onDelete("cascade"))
    .addColumn("inference_id", "text", (column) => column.notNull())
    .addColumn("provider", "text", (column) => column.notNull())
    .addColumn("model", "text", (column) => column.notNull())
    .addColumn("status", "text", (column) => column.notNull())
    .addColumn("input_tokens", "integer", (column) => column.notNull().defaultTo(0))
    .addColumn("output_tokens", "integer", (column) => column.notNull().defaultTo(0))
    .addColumn("created_at", "timestamptz", (column) => column.notNull().defaultTo(sql`now()`))
    .addColumn("completed_at", "timestamptz")
    .addUniqueConstraint("model_inference_once", ["couple_id", "inference_id"])
    .execute();

  await db.schema
    .createTable("idempotency_records")
    .ifNotExists()
    .addColumn("couple_id", "text", (column) => column.notNull().references("couples.id").onDelete("cascade"))
    .addColumn("scope", "text", (column) => column.notNull())
    .addColumn("idempotency_key", "text", (column) => column.notNull())
    .addColumn("response", "jsonb", (column) => column.notNull())
    .addColumn("created_at", "timestamptz", (column) => column.notNull().defaultTo(sql`now()`))
    .addPrimaryKeyConstraint("idempotency_records_pk", ["couple_id", "scope", "idempotency_key"])
    .execute();
}

export async function down(db: Kysely<Database>): Promise<void> {
  for (const table of [
    "idempotency_records",
    "model_usage",
    "couple_events",
    "letters",
    "visits",
    "messages",
    "conversations",
    "pets",
    "couples",
    "accounts"
  ] as const) {
    await db.schema.dropTable(table).ifExists().cascade().execute();
  }
}
