import type { AuthContext, MutationResult } from "../domain/models";
import { readIdempotency } from "../storage/events-repository";
import { requestFingerprint } from "../security/request-fingerprint";

export interface PreparedMutation<T> {
  data: T;
  status: number;
  notifyAccountIDs: string[];
  statements: D1PreparedStatement[];
}

export async function executeIdempotent<T>(
  db: D1Database,
  context: AuthContext,
  operation: string,
  key: string,
  request: unknown,
  prepare: (fingerprint: string) => Promise<PreparedMutation<T>>,
  maxConditionalRetries = 0
): Promise<MutationResult<T>> {
  const fingerprint = await requestFingerprint(request);
  for (let attempt = 0; ; attempt += 1) {
    const prior = await readIdempotency<T>(db, context.accountID, operation, key, fingerprint);
    if (prior) {
      return { ...prior, notifyAccountIDs: [], replayed: true };
    }
    const mutation = await prepare(fingerprint);
    try {
      await db.batch(mutation.statements);
      const receipt = await readIdempotency<T>(db, context.accountID, operation, key, fingerprint);
      if (!receipt) throw new Error("conditional_mutation_failed");
      return {
        data: receipt.data,
        status: receipt.status,
        notifyAccountIDs: mutation.notifyAccountIDs,
        replayed: false
      };
    } catch (error) {
      const raced = await readIdempotency<T>(db, context.accountID, operation, key, fingerprint);
      if (raced) return { ...raced, notifyAccountIDs: [], replayed: true };
      if (error instanceof Error
          && error.message === "conditional_mutation_failed"
          && attempt < maxConditionalRetries) {
        continue;
      }
      throw error;
    }
  }
}
