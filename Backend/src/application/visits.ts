import type { AuthContext } from "../domain/models";
import type { Visit, VisitCloseReason, VisitRow } from "../domain/visit";
import { visitFromRow } from "../domain/visit";
import { conflict, notFound } from "../errors";
import {
  accountEventFromMarkerStatement,
  accountEventStatement,
  idempotencyFromMarkerStatement,
  idempotencyStatement
} from "../storage/events-repository";
import { requireFriendship } from "../storage/friendships-repository";
import { findVisit, publicPetSnapshot } from "../storage/visits-repository";
import { executeIdempotent } from "./idempotency";
import { visitInteractionSummary } from "./pet-care";

function visitRowFromVisit(visit: Visit, transitionID: string): VisitRow {
  return {
    id: visit.id,
    friendship_id: visit.friendshipID,
    visitor_pet_id: visit.visitorPetID,
    visitor_owner_account_id: visit.visitorOwnerAccountID,
    host_account_id: visit.hostAccountID,
    requested_by_account_id: visit.requestedByAccountID,
    responder_account_id: visit.responderAccountID,
    status: visit.status,
    close_reason: visit.closeReason,
    reason: visit.reason,
    version: visit.version,
    last_transition_id: transitionID,
    created_at_ms: visit.createdAt,
    expires_at_ms: visit.expiresAt,
    started_at_ms: visit.startedAt,
    closed_at_ms: visit.closedAt
  };
}

function visitEventStatements(
  db: D1Database,
  visit: Visit,
  type: string,
  payload: Record<string, unknown>,
  timelineVisible: boolean,
  now: number,
  transitionID?: string
): D1PreparedStatement[] {
  const recipients = [visit.visitorOwnerAccountID, visit.hostAccountID];
  return recipients.map((recipientAccountID) => {
    const event = {
      recipientAccountID,
      friendshipID: visit.friendshipID,
      type,
      aggregateType: "visit",
      aggregateID: visit.id,
      aggregateVersion: visit.version,
      payload,
      timelineVisible,
      occurredAt: now
    };
    return transitionID
      ? accountEventFromMarkerStatement(db, event, "visits", "last_transition_id", visit.id, transitionID)
      : accountEventStatement(db, event);
  });
}

export async function createVisit(
  db: D1Database,
  context: AuthContext,
  input: { friendshipID: string; visitorPetID: string; hostAccountID: string; reason?: string },
  idempotencyKey: string,
  now = Date.now()
) {
  const access = await requireFriendship(db, context, input.friendshipID, true);
  const visitorIsSelf = input.visitorPetID === context.petID && input.hostAccountID === access.friendAccountID;
  const visitorIsFriend = input.visitorPetID === access.friendPetID && input.hostAccountID === context.accountID;
  if (!visitorIsSelf && !visitorIsFriend) throw notFound("visitor or host");
  const visitorOwnerAccountID = visitorIsSelf ? context.accountID : access.friendAccountID;
  const responderAccountID = context.accountID === visitorOwnerAccountID
    ? input.hostAccountID
    : visitorOwnerAccountID;
  return executeIdempotent<Visit>(db, context, "createVisit", idempotencyKey, input, async (fingerprint) => {
    const duplicate = await db.prepare(`
      SELECT id FROM visits WHERE visitor_pet_id = ? AND host_account_id = ? AND status = 'pending'
    `).bind(input.visitorPetID, input.hostAccountID).first();
    if (duplicate) throw conflict("visit_pending", "This visitor already has a pending visit for the host");
    const transitionID = crypto.randomUUID();
    const visit: Visit = {
      id: crypto.randomUUID(),
      friendshipID: input.friendshipID,
      visitorPetID: input.visitorPetID,
      visitorOwnerAccountID,
      hostAccountID: input.hostAccountID,
      requestedByAccountID: context.accountID,
      responderAccountID,
      status: "pending",
      closeReason: null,
      reason: input.reason?.trim() || null,
      version: 1,
      createdAt: now,
      expiresAt: now + 24 * 60 * 60 * 1_000,
      startedAt: null,
      closedAt: null
    };
    const pet = await publicPetSnapshot(db, visit.visitorPetID);
    const payload = {
      visit,
      publicPetSnapshot: pet,
      requestedByAccountID: visit.requestedByAccountID,
      responderAccountID: visit.responderAccountID
    };
    return {
      data: visit,
      status: 201,
      notifyAccountIDs: [visit.visitorOwnerAccountID, visit.hostAccountID],
      statements: [
        db.prepare(`
          INSERT INTO visits(
            id, friendship_id, visitor_pet_id, visitor_owner_account_id, host_account_id,
            requested_by_account_id, responder_account_id, status, close_reason, reason,
            version, last_transition_id, created_at_ms, expires_at_ms, started_at_ms, closed_at_ms
          ) VALUES (?, ?, ?, ?, ?, ?, ?, 'pending', NULL, ?, 1, ?, ?, ?, NULL, NULL)
        `).bind(
          visit.id, visit.friendshipID, visit.visitorPetID, visit.visitorOwnerAccountID,
          visit.hostAccountID, visit.requestedByAccountID, visit.responderAccountID,
          visit.reason, transitionID, visit.createdAt, visit.expiresAt
        ),
        ...visitEventStatements(db, visit, "visit.requested", payload, false, now),
        idempotencyStatement(db, context.accountID, "createVisit", idempotencyKey,
          fingerprint, 201, visit, now)
      ]
    };
  });
}

export async function respondVisit(
  db: D1Database,
  context: AuthContext,
  visitID: string,
  input: { response: "accept" | "decline"; actorType: "human" | "pet_agent" },
  idempotencyKey: string,
  now = Date.now()
) {
  if (input.actorType === "pet_agent" && !context.isPrimaryAgentDevice) {
    throw conflict("not_primary_agent_device", "Only the primary Agent device can answer autonomously");
  }
  try {
    return await executeIdempotent<Visit>(
      db, context, `respondVisit:${visitID}`, idempotencyKey, input,
      async (fingerprint) => {
        const current = await findVisit(db, context, visitID);
        if (current.responderAccountID !== context.accountID) throw notFound("visit");
        if (current.status !== "pending") throw conflict("visit_resolved", "The visit is already resolved");
        if (current.expiresAt <= now) {
          const transitionID = crypto.randomUUID();
          const expired: Visit = {
            ...current,
            status: "closed",
            closeReason: "expired",
            version: current.version + 1,
            closedAt: now
          };
          return {
            data: expired,
            status: 200,
            notifyAccountIDs: [expired.visitorOwnerAccountID, expired.hostAccountID],
            statements: [
              db.prepare(`
                UPDATE visits SET status = 'closed', close_reason = 'expired',
                  version = ?, last_transition_id = ?, closed_at_ms = ?
                WHERE id = ? AND status = 'pending' AND version = ? AND expires_at_ms <= ?
              `).bind(expired.version, transitionID, now, expired.id, current.version, now),
              ...visitEventStatements(
                db, expired, "visit.closed", { visit: expired }, true, now, transitionID
              ),
              idempotencyFromMarkerStatement(
                db, context.accountID, `respondVisit:${visitID}`, idempotencyKey, fingerprint,
                200, expired, now, "visits", "last_transition_id", expired.id, transitionID
              )
            ]
          };
        }
        await requireFriendship(db, context, current.friendshipID, true);
        const transitionID = crypto.randomUUID();
        const version = current.version + 1;
        const visit: Visit = {
          ...current,
          status: input.response === "accept" ? "active" : "closed",
          closeReason: input.response === "accept" ? null : "declined",
          version,
          startedAt: input.response === "accept" ? now : null,
          closedAt: input.response === "decline" ? now : null
        };
        const payload = { visit };
        const eventType = input.response === "accept" ? "visit.activated" : "visit.closed";
        return {
          data: visit,
          status: 200,
          notifyAccountIDs: [visit.visitorOwnerAccountID, visit.hostAccountID],
          statements: [
            db.prepare(`
              UPDATE visits SET
                status = ?, close_reason = ?, version = ?, last_transition_id = ?,
                started_at_ms = ?, closed_at_ms = ?
              WHERE id = ? AND status = 'pending' AND version = ? AND responder_account_id = ?
            `).bind(
              visit.status, visit.closeReason, version, transitionID,
              visit.startedAt, visit.closedAt, visit.id, current.version, context.accountID
            ),
            ...visitEventStatements(db, visit, eventType, payload, true, now, transitionID),
            idempotencyFromMarkerStatement(
              db, context.accountID, `respondVisit:${visitID}`, idempotencyKey, fingerprint,
              200, visit, now, "visits", "last_transition_id", visit.id, transitionID
            )
          ]
        };
      }
    );
  } catch (error) {
    if (error instanceof Error && /UNIQUE constraint failed|constraint failed/i.test(error.message)) {
      const current = await findVisit(db, context, visitID);
      const visitorBusy = await db.prepare(`
        SELECT id FROM visits WHERE visitor_pet_id = ? AND status = 'active' AND id <> ?
      `).bind(current.visitorPetID, visitID).first();
      if (visitorBusy) throw conflict("visitor_busy", "The visitor is already in another active visit");
      const hostBusy = await db.prepare(`
        SELECT id FROM visits WHERE host_account_id = ? AND status = 'active' AND id <> ?
      `).bind(current.hostAccountID, visitID).first();
      if (hostBusy) throw conflict("host_busy", "The host is already receiving another active visitor");
    }
    throw error;
  }
}

interface LetterDeliveryRow {
  id: string;
  author_account_id: string;
  recipient_account_id: string;
}

export async function endVisit(
  db: D1Database,
  context: AuthContext,
  visitID: string,
  input: { actorType: "human" | "pet_agent" },
  idempotencyKey: string,
  now = Date.now()
) {
  if (input.actorType === "pet_agent" && !context.isPrimaryAgentDevice) {
    throw conflict("not_primary_agent_device", "Only the primary Agent device can act autonomously");
  }
  try {
    return await executeIdempotent<Visit>(db, context, `endVisit:${visitID}`, idempotencyKey, input, async (fingerprint) => {
    const current = await findVisit(db, context, visitID);
    if (![current.visitorOwnerAccountID, current.hostAccountID].includes(context.accountID)) throw notFound("visit");
    if (current.status === "closed") {
      return {
        data: current,
        status: 200,
        notifyAccountIDs: [],
        statements: [
          idempotencyStatement(db, context.accountID, `endVisit:${visitID}`, idempotencyKey,
            fingerprint, 200, current, now)
        ]
      };
    }
    if (current.status === "pending" && current.requestedByAccountID !== context.accountID) {
      throw conflict("visit_pending", "Only the requester can cancel a pending visit");
    }
    const closeReason: VisitCloseReason = current.status === "pending"
      ? "cancelled"
      : context.accountID === current.visitorOwnerAccountID ? "recalled" : "sent_home";
    const transitionID = crypto.randomUUID();
    const visit: Visit = {
      ...current,
      status: "closed",
      closeReason,
      version: current.version + 1,
      closedAt: now
    };
    const letters = await db.prepare(`
      SELECT id, author_account_id, recipient_account_id FROM letters
      WHERE visit_id = ? AND status = 'attached'
    `).bind(visitID).all<LetterDeliveryRow>();
    const interactionSummary = await visitInteractionSummary(db, visitID, letters.results.length > 0);
    const statements: D1PreparedStatement[] = [
      db.prepare(`
        UPDATE visits SET status = 'closed', close_reason = ?, version = ?,
          last_transition_id = ?, closed_at_ms = ?
        WHERE id = ? AND status = ? AND version = ?
      `).bind(closeReason, visit.version, transitionID, now, visit.id, current.status, current.version),
      db.prepare(`
        UPDATE letters SET status = 'delivered', delivered_at_ms = ?
        WHERE visit_id = ? AND status = 'attached'
          AND EXISTS (SELECT 1 FROM visits WHERE id = ? AND last_transition_id = ?)
      `).bind(now, visitID, visitID, transitionID),
      ...visitEventStatements(
        db, visit, "visit.closed", { visit, interactionSummary }, true, now, transitionID
      )
    ];
    for (const letter of letters.results) {
      statements.push(accountEventFromMarkerStatement(db, {
        recipientAccountID: letter.recipient_account_id,
        friendshipID: visit.friendshipID,
        type: "letter.delivered",
        aggregateType: "letter",
        aggregateID: letter.id,
        payload: {
          letterID: letter.id,
          visitID,
          authorAccountID: letter.author_account_id,
          recipientAccountID: letter.recipient_account_id,
          status: "delivered"
        },
        timelineVisible: true,
        occurredAt: now
      }, "visits", "last_transition_id", visit.id, transitionID));
    }
    statements.push(idempotencyFromMarkerStatement(
      db, context.accountID, `endVisit:${visitID}`, idempotencyKey, fingerprint,
      200, visit, now, "visits", "last_transition_id", visit.id, transitionID
    ));
    return {
      data: visit,
      status: 200,
      notifyAccountIDs: [visit.visitorOwnerAccountID, visit.hostAccountID],
      statements
    };
    });
  } catch (error) {
    const converged = await findVisit(db, context, visitID);
    if (converged.status === "closed") {
      return executeIdempotent<Visit>(
        db, context, `endVisit:${visitID}`, idempotencyKey, input,
        async (fingerprint) => ({
          data: converged,
          status: 200,
          notifyAccountIDs: [],
          statements: [
            idempotencyStatement(db, context.accountID, `endVisit:${visitID}`, idempotencyKey,
              fingerprint, 200, converged, now)
          ]
        })
      );
    }
    throw error;
  }
}
