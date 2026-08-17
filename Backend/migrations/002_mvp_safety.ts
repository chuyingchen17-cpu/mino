import { type Kysely, sql } from "kysely";
import type { Database } from "../src/database/schema.js";

export async function up(db: Kysely<Database>): Promise<void> {
  await db.schema.alterTable("model_usage")
    .addColumn("claimed_at", "timestamptz", (column) => column.notNull().defaultTo(sql`now()`))
    .addColumn("response", "jsonb")
    .execute();

  await db.schema.alterTable("idempotency_records")
    .addColumn("request_fingerprint", "text")
    .execute();
  await db.updateTable("idempotency_records").set({ request_fingerprint: "legacy" }).execute();
  await db.schema.alterTable("idempotency_records")
    .alterColumn("request_fingerprint", (column) => column.setNotNull())
    .execute();
}

export async function down(db: Kysely<Database>): Promise<void> {
  await db.schema.alterTable("idempotency_records").dropColumn("request_fingerprint").execute();
  await db.schema.alterTable("model_usage").dropColumn("response").dropColumn("claimed_at").execute();
}
