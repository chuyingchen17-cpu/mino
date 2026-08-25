import type { FriendshipRow } from "../domain/friendship";
import { friendshipFromRow, pairKey } from "../domain/friendship";
import type { AuthContext, FriendshipSummary, PublicPetSnapshot } from "../domain/models";
import { visitFromRow, type VisitRow } from "../domain/visit";
import { conflict, notFound } from "../errors";
import { publicPetFromRow } from "../storage/accounts-repository";
import {
  accountEventFromMarkerStatement,
  accountEventStatement,
  idempotencyFromMarkerStatement,
  idempotencyStatement
} from "../storage/events-repository";
import { friendshipSummary } from "../storage/friendships-repository";
import { executeIdempotent } from "./idempotency";

interface FriendIdentity {
  account_id: string;
  account_name: string;
  pet_id: string;
  pet_name: string;
  appearance_schema_version: number;
  appearance_catalog_version: number;
  appearance_json: string;
  appearance_version: number;
}

async function friendIdentity(db: D1Database, accountID: string): Promise<FriendIdentity> {
  const row = await db.prepare(`
    SELECT accounts.id AS account_id, accounts.display_name AS account_name,
      pets.id AS pet_id, pets.display_name AS pet_name,
      pets.appearance_schema_version, pets.appearance_catalog_version,
      pets.appearance_json, pets.appearance_version
    FROM accounts JOIN pets ON pets.owner_account_id = accounts.id
    WHERE accounts.id = ?
  `).bind(accountID).first<FriendIdentity>();
  if (!row) throw notFound("account");
  return row;
}

function publicPet(identity: FriendIdentity): PublicPetSnapshot {
  return publicPetFromRow({
    id: identity.pet_id,
    display_name: identity.pet_name,
    appearance_schema_version: identity.appearance_schema_version,
    appearance_catalog_version: identity.appearance_catalog_version,
    appearance_json: identity.appearance_json,
    appearance_version: identity.appearance_version
  });
}

export async function createFriendship(
  db: D1Database,
  context: AuthContext,
  input: { addresseeAccountID: string },
  idempotencyKey: string,
  now = Date.now()
) {
  if (input.addresseeAccountID === context.accountID) {
    throw conflict("cannot_friend_self", "An account cannot befriend itself");
  }
  const target = await friendIdentity(db, input.addresseeAccountID);
  return executeIdempotent<FriendshipSummary>(
    db, context, "createFriendship", idempotencyKey, input,
    async (fingerprint) => {
      const existing = await db.prepare(`
        SELECT id FROM friendships WHERE pair_key = ? AND status IN ('pending', 'accepted')
      `).bind(pairKey(context.accountID, input.addresseeAccountID)).first();
      if (existing) throw conflict("friendship_exists", "A pending or accepted friendship already exists");
      const id = crypto.randomUUID();
      const transitionID = crypto.randomUUID();
      const data: FriendshipSummary = {
        id,
        requesterAccountID: context.accountID,
        addresseeAccountID: input.addresseeAccountID,
        status: "pending",
        version: 1,
        createdAt: now,
        respondedAt: null,
        closedAt: null,
        friend: {
          accountID: target.account_id,
          displayName: target.account_name,
          pet: publicPet(target)
        }
      };
      const payload = { friendship: friendshipFromRow({
        id,
        requester_account_id: context.accountID,
        addressee_account_id: input.addresseeAccountID,
        pair_key: pairKey(context.accountID, input.addresseeAccountID),
        status: "pending",
        version: 1,
        last_transition_id: transitionID,
        created_at_ms: now,
        responded_at_ms: null,
        closed_at_ms: null
      }) };
      return {
        data,
        status: 201,
        notifyAccountIDs: [context.accountID, input.addresseeAccountID],
        statements: [
          db.prepare(`
            INSERT INTO friendships(
              id, requester_account_id, addressee_account_id, pair_key, status,
              version, last_transition_id, created_at_ms, responded_at_ms, closed_at_ms
            ) VALUES (?, ?, ?, ?, 'pending', 1, ?, ?, NULL, NULL)
          `).bind(id, context.accountID, input.addresseeAccountID,
            pairKey(context.accountID, input.addresseeAccountID), transitionID, now),
          accountEventStatement(db, {
            recipientAccountID: context.accountID,
            friendshipID: id,
            type: "friendship.requested",
            aggregateType: "friendship",
            aggregateID: id,
            aggregateVersion: 1,
            payload,
            timelineVisible: false,
            occurredAt: now
          }),
          accountEventStatement(db, {
            recipientAccountID: input.addresseeAccountID,
            friendshipID: id,
            type: "friendship.requested",
            aggregateType: "friendship",
            aggregateID: id,
            aggregateVersion: 1,
            payload,
            timelineVisible: false,
            occurredAt: now
          }),
          idempotencyStatement(db, context.accountID, "createFriendship", idempotencyKey,
            fingerprint, 201, data, now)
        ]
      };
    }
  );
}

export async function respondFriendship(
  db: D1Database,
  context: AuthContext,
  friendshipID: string,
  input: { response: "accept" | "reject" },
  idempotencyKey: string,
  now = Date.now()
) {
  return executeIdempotent<FriendshipSummary>(
    db, context, `respondFriendship:${friendshipID}`, idempotencyKey, input,
    async (fingerprint) => {
      const row = await db.prepare("SELECT * FROM friendships WHERE id = ? AND addressee_account_id = ?")
        .bind(friendshipID, context.accountID).first<FriendshipRow>();
      if (!row) throw notFound("friendship");
      if (row.status !== "pending") throw conflict("friendship_resolved", "The friendship is already resolved");
      const nextStatus = input.response === "accept" ? "accepted" : "rejected";
      const transitionID = crypto.randomUUID();
      const version = row.version + 1;
      const requester = await friendIdentity(db, row.requester_account_id);
      const data: FriendshipSummary = {
        ...friendshipFromRow({
          ...row,
          status: nextStatus,
          version,
          last_transition_id: transitionID,
          responded_at_ms: now
        }),
        friend: {
          accountID: requester.account_id,
          displayName: requester.account_name,
          pet: publicPet(requester)
        }
      };
      const eventType = nextStatus === "accepted" ? "friendship.accepted" : "friendship.rejected";
      const event = (recipientAccountID: string) => accountEventFromMarkerStatement(db, {
        recipientAccountID,
        friendshipID,
        type: eventType,
        aggregateType: "friendship",
        aggregateID: friendshipID,
        aggregateVersion: version,
        payload: { friendship: { ...data, friend: undefined } },
        timelineVisible: false,
        occurredAt: now
      }, "friendships", "last_transition_id", friendshipID, transitionID);
      return {
        data,
        status: 200,
        notifyAccountIDs: [row.requester_account_id, row.addressee_account_id],
        statements: [
          db.prepare(`
            UPDATE friendships
            SET status = ?, version = ?, last_transition_id = ?, responded_at_ms = ?
            WHERE id = ? AND status = 'pending' AND version = ? AND addressee_account_id = ?
          `).bind(nextStatus, version, transitionID, now, friendshipID, row.version, context.accountID),
          event(row.requester_account_id),
          event(row.addressee_account_id),
          idempotencyFromMarkerStatement(db, context.accountID, `respondFriendship:${friendshipID}`,
            idempotencyKey, fingerprint, 200, data, now, "friendships", "last_transition_id",
            friendshipID, transitionID)
        ]
      };
    }
  );
}

export async function currentFriendshipSummary(
  db: D1Database,
  context: AuthContext,
  friendshipID: string
): Promise<FriendshipSummary> {
  return friendshipSummary(db, context, friendshipID);
}

export async function closeFriendship(
  db: D1Database,
  context: AuthContext,
  friendshipID: string,
  idempotencyKey: string,
  now = Date.now()
) {
  return executeIdempotent<FriendshipSummary>(
    db, context, `closeFriendship:${friendshipID}`, idempotencyKey, {},
    async (fingerprint) => {
      const row = await db.prepare(`
        SELECT * FROM friendships WHERE id = ?
          AND ? IN (requester_account_id, addressee_account_id)
      `).bind(friendshipID, context.accountID).first<FriendshipRow>();
      if (!row) throw notFound("friendship");
      const current = await friendshipSummary(db, context, friendshipID);
      if (row.status === "closed") {
        const data = { ...current, status: "closed" as const };
        return {
          data,
          status: 200,
          notifyAccountIDs: [],
          statements: [
            idempotencyStatement(db, context.accountID, `closeFriendship:${friendshipID}`,
              idempotencyKey, fingerprint, 200, data, now)
          ]
        };
      }
      const transitionID = crypto.randomUUID();
      const data: FriendshipSummary = {
        ...current,
        status: "closed",
        version: row.version + 1,
        closedAt: now
      };
      const accountIDs = [row.requester_account_id, row.addressee_account_id];
      const openVisits = await db.prepare(`
        SELECT * FROM visits WHERE friendship_id = ? AND status IN ('pending', 'active')
      `).bind(friendshipID).all<VisitRow>();
      const statements: D1PreparedStatement[] = [
        db.prepare(`
          UPDATE friendships SET status = 'closed', version = ?, last_transition_id = ?, closed_at_ms = ?
          WHERE id = ? AND status <> 'closed' AND version = ?
        `).bind(data.version, transitionID, now, friendshipID, row.version)
      ];
      for (const accountID of accountIDs) {
        statements.push(accountEventFromMarkerStatement(db, {
          recipientAccountID: accountID,
          friendshipID,
          type: "friendship.closed",
          aggregateType: "friendship",
          aggregateID: friendshipID,
          aggregateVersion: data.version,
          payload: { friendship: { ...data, friend: undefined } },
          timelineVisible: false,
          occurredAt: now
        }, "friendships", "last_transition_id", friendshipID, transitionID));
      }
      for (const visitRow of openVisits.results) {
        const visitTransitionID = crypto.randomUUID();
        const visitVersion = visitRow.version + 1;
        const closedVisit = visitFromRow({
          ...visitRow,
          status: "closed",
          close_reason: "friendship_closed",
          version: visitVersion,
          last_transition_id: visitTransitionID,
          closed_at_ms: now
        });
        const letters = await db.prepare(`
          SELECT id, author_account_id, recipient_account_id
          FROM letters WHERE visit_id = ? AND status = 'attached'
        `).bind(visitRow.id).all<{
          id: string; author_account_id: string; recipient_account_id: string;
        }>();
        statements.push(db.prepare(`
          UPDATE visits SET status = 'closed', close_reason = 'friendship_closed',
            version = ?, last_transition_id = ?, closed_at_ms = ?
          WHERE id = ? AND status IN ('pending', 'active') AND version = ?
            AND EXISTS (SELECT 1 FROM friendships WHERE id = ? AND last_transition_id = ?)
        `).bind(visitVersion, visitTransitionID, now, visitRow.id, visitRow.version, friendshipID, transitionID));
        statements.push(db.prepare(`
          UPDATE letters SET status = 'delivered', delivered_at_ms = ?
          WHERE visit_id = ? AND status = 'attached'
            AND EXISTS (SELECT 1 FROM visits WHERE id = ? AND last_transition_id = ?)
        `).bind(now, visitRow.id, visitRow.id, visitTransitionID));
        for (const accountID of accountIDs) {
          statements.push(accountEventFromMarkerStatement(db, {
            recipientAccountID: accountID,
            friendshipID,
            type: "visit.closed",
            aggregateType: "visit",
            aggregateID: visitRow.id,
            aggregateVersion: visitVersion,
            payload: { visit: closedVisit },
            timelineVisible: true,
            occurredAt: now
          }, "visits", "last_transition_id", visitRow.id, visitTransitionID));
        }
        for (const letter of letters.results) {
          statements.push(accountEventFromMarkerStatement(db, {
            recipientAccountID: letter.recipient_account_id,
            friendshipID,
            type: "letter.delivered",
            aggregateType: "letter",
            aggregateID: letter.id,
            payload: {
              letterID: letter.id,
              visitID: visitRow.id,
              authorAccountID: letter.author_account_id,
              recipientAccountID: letter.recipient_account_id,
              status: "delivered"
            },
            timelineVisible: true,
            occurredAt: now
          }, "visits", "last_transition_id", visitRow.id, visitTransitionID));
        }
      }
      statements.push(idempotencyFromMarkerStatement(
        db, context.accountID, `closeFriendship:${friendshipID}`, idempotencyKey,
        fingerprint, 200, data, now, "friendships", "last_transition_id",
        friendshipID, transitionID
      ));
      return { data, status: 200, notifyAccountIDs: accountIDs, statements };
    }
  );
}
