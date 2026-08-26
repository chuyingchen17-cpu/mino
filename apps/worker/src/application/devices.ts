import type { AuthContext } from "../domain/models";
import { conflict, notFound } from "../errors";
import {
  accountEventFromMarkerStatement,
  idempotencyFromMarkerStatement
} from "../storage/events-repository";
import { executeIdempotent } from "./idempotency";

export async function claimAgentDevice(
  db: D1Database,
  context: AuthContext,
  deviceID: string,
  idempotencyKey: string,
  now = Date.now()
) {
  if (deviceID !== context.deviceID) {
    throw conflict("device_mismatch", "A session can only claim its own device");
  }
  return executeIdempotent<{ previousDeviceID: string | null; currentDeviceID: string }>(
    db, context, `claimAgentDevice:${deviceID}`, idempotencyKey, {},
    async (fingerprint) => {
      const device = await db.prepare(`
        SELECT id FROM devices WHERE id = ? AND account_id = ? AND revoked_at_ms IS NULL
      `).bind(deviceID, context.accountID).first();
      if (!device) throw notFound("device");
      const account = await db.prepare("SELECT primary_agent_device_id FROM accounts WHERE id = ?")
        .bind(context.accountID).first<{ primary_agent_device_id: string | null }>();
      if (!account) throw notFound("account");
      const data = { previousDeviceID: account.primary_agent_device_id, currentDeviceID: deviceID };
      return {
        data,
        status: 200,
        notifyAccountIDs: [context.accountID],
        statements: [
          db.prepare("UPDATE accounts SET primary_agent_device_id = ?, updated_at_ms = ? WHERE id = ?")
            .bind(deviceID, now, context.accountID),
          accountEventFromMarkerStatement(db, {
            recipientAccountID: context.accountID,
            type: "agent.primary.changed",
            aggregateType: "account",
            aggregateID: context.accountID,
            payload: data,
            timelineVisible: false,
            occurredAt: now
          }, "accounts", "primary_agent_device_id", context.accountID, deviceID),
          idempotencyFromMarkerStatement(
            db, context.accountID, `claimAgentDevice:${deviceID}`, idempotencyKey,
            fingerprint, 200, data, now, "accounts", "primary_agent_device_id",
            context.accountID, deviceID
          )
        ]
      };
    }
  );
}
