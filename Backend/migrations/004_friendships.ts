import { type Kysely, sql } from "kysely";
import type { Database } from "../src/database/schema.js";

export async function up(db: Kysely<Database>): Promise<void> {
  await sql`
    DO $$
    BEGIN
      IF EXISTS (
        SELECT 1
        FROM couples
        GROUP BY LEAST(account_a_id, account_b_id), GREATEST(account_a_id, account_b_id)
        HAVING count(*) > 1
      ) THEN
        RAISE EXCEPTION 'duplicate legacy relationship pairs must be reconciled before migration 004';
      END IF;
    END $$
  `.execute(db);

  await sql`
    DO $$
    BEGIN
      IF EXISTS (
        SELECT 1
        FROM pets
        GROUP BY owner_account_id
        HAVING count(*) > 1
      ) THEN
        RAISE EXCEPTION 'duplicate legacy pets per owner must be reconciled before migration 004';
      END IF;
    END $$
  `.execute(db);

  await db.schema
    .createTable("friendships")
    .ifNotExists()
    .addColumn("id", "text", (column) => column.primaryKey())
    .addColumn("scope_id", "text", (column) => column.notNull().unique().references("couples.id").onDelete("cascade"))
    .addColumn("requester_account_id", "text", (column) => column.notNull().references("accounts.id"))
    .addColumn("addressee_account_id", "text", (column) => column.notNull().references("accounts.id"))
    .addColumn("pair_key", "text", (column) => column.notNull())
    .addColumn("status", "text", (column) => column.notNull())
    .addColumn("request_idempotency_key", "text", (column) => column.notNull())
    .addColumn("response_idempotency_key", "text")
    .addColumn("created_at", "timestamptz", (column) => column.notNull().defaultTo(sql`now()`))
    .addColumn("responded_at", "timestamptz")
    .addCheckConstraint("friendship_accounts_differ", sql`requester_account_id <> addressee_account_id`)
    .addCheckConstraint("friendship_id_matches_scope", sql`id = scope_id`)
    .addCheckConstraint("friendship_status", sql`status IN ('pending', 'accepted', 'rejected')`)
    .addUniqueConstraint("friendship_request_idempotency", ["requester_account_id", "request_idempotency_key"])
    .execute();

  await sql`
    CREATE UNIQUE INDEX friendship_active_pair
    ON friendships (pair_key)
    WHERE status IN ('pending', 'accepted')
  `.execute(db);

  // Keep existing installations usable: every old couple becomes an accepted
  // friendship with the same identifier as its legacy relationship scope.
  await sql`
    INSERT INTO friendships (
      id, scope_id, requester_account_id, addressee_account_id, pair_key, status,
      request_idempotency_key, created_at, responded_at
    )
    SELECT
      id,
      id,
      account_a_id,
      account_b_id,
      LEAST(account_a_id, account_b_id) || ':' || GREATEST(account_a_id, account_b_id),
      'accepted',
      'legacy:' || id,
      created_at,
      created_at
    FROM couples
  `.execute(db);

  // A pet belongs to its account, not to one relationship. The old column is
  // retained only so pre-friendship rows and foreign keys remain compatible.
  await db.schema.alterTable("pets").dropConstraint("one_pet_per_owner_per_couple").execute();
  await db.schema.alterTable("pets").dropConstraint("pets_couple_id_fkey").execute();
  await db.schema.alterTable("pets").alterColumn("couple_id", (column) => column.dropNotNull()).execute();
  await db.schema.alterTable("pets")
    .addForeignKeyConstraint("pets_legacy_scope_fkey", ["couple_id"], "couples", ["id"], (constraint) =>
      constraint.onDelete("set null")
    )
    .execute();
  await db.schema.createIndex("one_pet_per_owner").unique().on("pets").column("owner_account_id").execute();

  // A pet and a host can each participate in only one active visit globally,
  // even when either account has several accepted friendships.
  await sql`DROP INDEX IF EXISTS one_active_visit_per_couple`.execute(db);
  await sql`
    CREATE UNIQUE INDEX one_active_visit_per_visitor_pet
    ON visits (visitor_pet_id)
    WHERE status = 'active'
  `.execute(db);
  await sql`
    CREATE UNIQUE INDEX one_active_visit_per_host_account
    ON visits (host_account_id)
    WHERE status = 'active'
  `.execute(db);

  // Inference ownership follows the authenticated pet owner rather than a
  // friendship. Legacy rows cannot identify the original caller, so the
  // canonical account_a member is used for deterministic backfill.
  await db.schema.alterTable("model_usage")
    .addColumn("account_id", "text", (column) => column.references("accounts.id").onDelete("cascade"))
    .execute();
  await sql`
    UPDATE model_usage AS usage
    SET account_id = relationship.account_a_id
    FROM couples AS relationship
    WHERE usage.couple_id = relationship.id
      AND usage.account_id IS NULL
  `.execute(db);
  await sql`
    DO $$
    BEGIN
      IF EXISTS (SELECT 1 FROM model_usage WHERE account_id IS NULL) THEN
        RAISE EXCEPTION 'legacy model usage rows without an owning account must be reconciled before migration 004';
      END IF;
    END $$
  `.execute(db);
  await db.schema.alterTable("model_usage")
    .alterColumn("account_id", (column) => column.setNotNull())
    .execute();
  await db.schema.alterTable("model_usage").dropConstraint("model_inference_once").execute();
  await db.schema.alterTable("model_usage").dropConstraint("model_usage_couple_id_fkey").execute();
  await db.schema.alterTable("model_usage")
    .alterColumn("couple_id", (column) => column.dropNotNull())
    .execute();
  await db.schema.alterTable("model_usage")
    .addForeignKeyConstraint("model_usage_legacy_scope_fkey", ["couple_id"], "couples", ["id"], (constraint) =>
      constraint.onDelete("set null")
    )
    .execute();
  await db.schema.alterTable("model_usage")
    .addUniqueConstraint("model_inference_once_per_account", ["account_id", "inference_id"])
    .execute();
}

export async function down(db: Kysely<Database>): Promise<void> {
  await db.schema.alterTable("model_usage").dropConstraint("model_inference_once_per_account").execute();
  await db.schema.alterTable("model_usage").dropConstraint("model_usage_legacy_scope_fkey").execute();
  await sql`
    UPDATE model_usage AS usage
    SET couple_id = (
      SELECT friendship.scope_id
      FROM friendships AS friendship
      WHERE friendship.status = 'accepted'
        AND usage.account_id IN (friendship.requester_account_id, friendship.addressee_account_id)
      ORDER BY friendship.created_at, friendship.id
      LIMIT 1
    )
    WHERE usage.couple_id IS NULL
  `.execute(db);
  await sql`
    DO $$
    BEGIN
      IF EXISTS (SELECT 1 FROM model_usage WHERE couple_id IS NULL) THEN
        RAISE EXCEPTION 'account-scoped model usage without a legacy relationship prevents migration 004 rollback';
      END IF;
    END $$
  `.execute(db);
  await db.schema.alterTable("model_usage")
    .alterColumn("couple_id", (column) => column.setNotNull())
    .execute();
  await db.schema.alterTable("model_usage")
    .addForeignKeyConstraint("model_usage_couple_id_fkey", ["couple_id"], "couples", ["id"], (constraint) =>
      constraint.onDelete("cascade")
    )
    .execute();
  await db.schema.alterTable("model_usage")
    .addUniqueConstraint("model_inference_once", ["couple_id", "inference_id"])
    .execute();
  await db.schema.alterTable("model_usage").dropColumn("account_id").execute();

  await sql`DROP INDEX IF EXISTS one_active_visit_per_host_account`.execute(db);
  await sql`DROP INDEX IF EXISTS one_active_visit_per_visitor_pet`.execute(db);
  await sql`
    CREATE UNIQUE INDEX one_active_visit_per_couple
    ON visits (couple_id)
    WHERE status = 'active'
  `.execute(db);

  await db.schema.dropIndex("one_pet_per_owner").ifExists().execute();
  await db.schema.alterTable("pets").dropConstraint("pets_legacy_scope_fkey").execute();
  await sql`
    DO $$
    BEGIN
      IF EXISTS (SELECT 1 FROM pets WHERE couple_id IS NULL) THEN
        RAISE EXCEPTION 'pets without a legacy relationship prevent migration 004 rollback';
      END IF;
    END $$
  `.execute(db);
  await db.schema.alterTable("pets").alterColumn("couple_id", (column) => column.setNotNull()).execute();
  await db.schema.alterTable("pets")
    .addForeignKeyConstraint("pets_couple_id_fkey", ["couple_id"], "couples", ["id"], (constraint) =>
      constraint.onDelete("cascade")
    )
    .execute();
  await db.schema.alterTable("pets")
    .addUniqueConstraint("one_pet_per_owner_per_couple", ["couple_id", "owner_account_id"])
    .execute();
  await db.schema.dropTable("friendships").ifExists().execute();
}
