import type { AuthContext } from "../domain/models";
import type {
  AgentVisitActionKind,
  HostVisitActionKind,
  VisitAction,
  VisitActionActorType,
  VisitActionKind
} from "../domain/visit-action";
import { conflict, notFound } from "../errors";
import {
  accountEventFromMarkerStatement,
  idempotencyFromMarkerStatement
} from "../storage/events-repository";
import { requireFriendship } from "../storage/friendships-repository";
import { findVisit, findVisitAction } from "../storage/visits-repository";
import { executeIdempotent } from "./idempotency";

const hostKinds = new Set<HostVisitActionKind>([
  "feed", "play", "pet", "hug", "kiss", "flower", "walk", "message"
]);
const agentKinds = new Set<AgentVisitActionKind>([
  "reaction", "activity", "speech", "acknowledgement"
]);

export async function createVisitAction(
  db: D1Database,
  context: AuthContext,
  visitID: string,
  input: {
    kind: VisitActionKind;
    payload: Record<string, unknown>;
    replyToActionID?: string;
    actorType: Exclude<VisitActionActorType, "system">;
  },
  idempotencyKey: string,
  now = Date.now()
) {
  return executeIdempotent<VisitAction>(
    db, context, `createVisitAction:${visitID}`, idempotencyKey, input,
    async (fingerprint) => {
      const visit = await findVisit(db, context, visitID);
      if (visit.status !== "active") throw conflict("visit_not_active", "Visit actions require an active visit");
      await requireFriendship(db, context, visit.friendshipID, true);
      const isHostAction = context.accountID === visit.hostAccountID && hostKinds.has(input.kind as HostVisitActionKind);
      const isAgentReply = context.accountID === visit.visitorOwnerAccountID &&
        agentKinds.has(input.kind as AgentVisitActionKind);
      if (!isHostAction && !isAgentReply) throw notFound("visit");
      if (isHostAction && input.actorType !== "human") {
        throw conflict("invalid_actor_type", "Host actions are explicit human actions");
      }
      if (isAgentReply) {
        if (input.actorType !== "pet_agent") throw conflict("invalid_actor_type", "Visitor replies come from the pet Agent");
        if (!context.isPrimaryAgentDevice) {
          throw conflict("not_primary_agent_device", "Only the primary Agent device can reply for a pet");
        }
        if (!input.replyToActionID) {
          throw conflict("reply_required", "A visitor Agent action must reply to a host action");
        }
        const original = await findVisitAction(db, visitID, input.replyToActionID);
        if (!original || original.senderAccountID !== visit.hostAccountID || !original.requiresResponse) {
          throw notFound("visit action");
        }
        const reply = await db.prepare("SELECT id FROM visit_actions WHERE reply_to_action_id = ?")
          .bind(input.replyToActionID).first();
        if (reply) throw conflict("action_already_replied", "This action already has a reply");
      } else if (input.replyToActionID) {
        throw conflict("unexpected_reply", "Host actions cannot be replies");
      }

      const action: VisitAction = {
        id: crypto.randomUUID(),
        visitID,
        senderAccountID: context.accountID,
        actorType: input.actorType,
        kind: input.kind,
        payload: input.payload,
        replyToActionID: input.replyToActionID ?? null,
        requiresResponse: isHostAction,
        createdAt: now
      };
      const recipientAccountID = isHostAction ? visit.visitorOwnerAccountID : visit.hostAccountID;
      const eventType = isHostAction ? "visit.action.created" : "visit.action.replied";
      const event = (accountID: string) => accountEventFromMarkerStatement(db, {
        recipientAccountID: accountID,
        friendshipID: visit.friendshipID,
        type: eventType,
        aggregateType: "visit_action",
        aggregateID: action.id,
        payload: { action },
        timelineVisible: false,
        occurredAt: now
      }, "visit_actions", "id", action.id, action.id);
      return {
        data: action,
        status: 201,
        notifyAccountIDs: [context.accountID, recipientAccountID],
        statements: [
          db.prepare(`
            INSERT INTO visit_actions(
              id, visit_id, sender_account_id, actor_type, kind, payload_json,
              reply_to_action_id, requires_response, created_at_ms
            )
            SELECT ?, ?, ?, ?, ?, ?, ?, ?, ?
            FROM visits
            JOIN friendships ON friendships.id = visits.friendship_id
            WHERE visits.id = ? AND visits.status = 'active' AND visits.version = ?
              AND friendships.status = 'accepted'
          `).bind(
            action.id, action.visitID, action.senderAccountID, action.actorType, action.kind,
            JSON.stringify(action.payload), action.replyToActionID, action.requiresResponse ? 1 : 0,
            action.createdAt, visit.id, visit.version
          ),
          event(recipientAccountID),
          event(context.accountID),
          idempotencyFromMarkerStatement(
            db, context.accountID, `createVisitAction:${visitID}`, idempotencyKey,
            fingerprint, 201, action, now, "visit_actions", "id", action.id, action.id
          )
        ]
      };
    }
  ).catch(async (error) => {
    if (error instanceof Error && /reply_to_action_id|UNIQUE constraint/i.test(error.message)) {
      throw conflict("action_already_replied", "This action already has a reply");
    }
    throw error;
  });
}
