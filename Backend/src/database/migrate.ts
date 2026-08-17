import { promises as fs } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { FileMigrationProvider, Migrator } from "kysely";
import { loadConfig } from "../config.js";
import { createDatabase } from "./connection.js";

const config = loadConfig();
const database = createDatabase(config.databaseURL);
const currentDirectory = path.dirname(fileURLToPath(import.meta.url));
const migrationFolder = path.resolve(currentDirectory, "../../migrations");
const migrator = new Migrator({
  db: database,
  provider: new FileMigrationProvider({ fs, path, migrationFolder })
});

const direction = process.argv[2];
const result = direction === "down" ? await migrator.migrateDown() : await migrator.migrateToLatest();

for (const migration of result.results ?? []) {
  process.stdout.write(`${migration.migrationName}: ${migration.status}\n`);
}

if (result.error) {
  console.error(result.error);
  await database.destroy();
  process.exitCode = 1;
} else {
  await database.destroy();
}
