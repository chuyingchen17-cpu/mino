import { type Kysely, sql } from "kysely";
import type { Database } from "../src/database/schema.js";

export async function up(db: Kysely<Database>): Promise<void> {
  await db.schema.alterTable("model_usage")
    .addColumn("request_fingerprint", "text")
    .execute();
  await sql`
    UPDATE model_usage
    SET request_fingerprint = 'legacy-unverifiable:' || id
    WHERE request_fingerprint IS NULL
  `.execute(db);
  await db.schema.alterTable("model_usage")
    .alterColumn("request_fingerprint", (column) => column.setNotNull())
    .execute();
}

export async function down(db: Kysely<Database>): Promise<void> {
  await db.schema.alterTable("model_usage").dropColumn("request_fingerprint").execute();
}
