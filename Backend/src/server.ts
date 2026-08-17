import { buildApp } from "./app.js";
import { loadConfig } from "./config.js";
import { createDatabase } from "./database/connection.js";
import { PostgresMinoStore } from "./database/postgres-store.js";
import { createModelProvider } from "./model/provider.js";
import { ModelDecisionService } from "./model/service.js";
import { LetterCipher } from "./security/letter-cipher.js";

const config = loadConfig();
const letterCipher = config.letterEncryptionKey
  ? LetterCipher.fromBase64(config.letterEncryptionKey)
  : LetterCipher.development(config.databaseURL);
const store = new PostgresMinoStore(
  createDatabase(config.databaseURL),
  letterCipher,
  config.nodeEnv !== "production" && config.devBootstrapEnabled
);
const modelService = new ModelDecisionService(store, createModelProvider(config.model));
const app = await buildApp({ config, store, modelService });

const shutdown = async (): Promise<void> => {
  await app.close();
  process.exit(0);
};

process.on("SIGINT", () => void shutdown());
process.on("SIGTERM", () => void shutdown());

try {
  await app.listen({ host: config.host, port: config.port });
} catch (error) {
  app.log.error(error);
  await app.close();
  process.exit(1);
}
