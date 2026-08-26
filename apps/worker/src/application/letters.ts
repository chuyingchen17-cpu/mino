import type { AuthContext } from "../domain/models";
import { conflict, notFound } from "../errors";
import { decryptLetter, encryptLetter } from "../security/crypto";
import {
  accountEventFromMarkerStatement,
  idempotencyFromMarkerStatement
} from "../storage/events-repository";
import { requireFriendship } from "../storage/friendships-repository";
import { findVisit } from "../storage/visits-repository";
import { executeIdempotent } from "./idempotency";

export interface LetterMetadata {
  id: string;
  visitID: string;
  friendshipID: string;
  authorAccountID: string;
  recipientAccountID: string;
  status: "attached" | "delivered";
  createdAt: number;
  deliveredAt: number | null;
}

export async function createLetter(
  db: D1Database,
  context: AuthContext,
  visitID: string,
  plaintext: string,
  idempotencyKey: string,
  secret: string,
  now = Date.now()
) {
  return executeIdempotent<LetterMetadata>(
    db, context, `createLetter:${visitID}`, idempotencyKey, { visitID, plaintext },
    async (fingerprint) => {
      const visit = await findVisit(db, context, visitID);
      if (visit.status !== "active") throw conflict("visit_not_active", "A letter requires an active visit");
      if (visit.hostAccountID !== context.accountID) throw notFound("visit");
      await requireFriendship(db, context, visit.friendshipID, true);
      const sealed = await encryptLetter(plaintext, secret);
      const letter: LetterMetadata = {
        id: crypto.randomUUID(),
        visitID,
        friendshipID: visit.friendshipID,
        authorAccountID: context.accountID,
        recipientAccountID: visit.visitorOwnerAccountID,
        status: "attached",
        createdAt: now,
        deliveredAt: null
      };
      const event = (recipientAccountID: string) => accountEventFromMarkerStatement(db, {
        recipientAccountID,
        friendshipID: visit.friendshipID,
        type: "letter.attached",
        aggregateType: "letter",
        aggregateID: letter.id,
        payload: {
          letterID: letter.id,
          visitID,
          authorAccountID: letter.authorAccountID,
          recipientAccountID: letter.recipientAccountID,
          status: letter.status
        },
        timelineVisible: false,
        occurredAt: now
      }, "letters", "id", letter.id, letter.id);
      return {
        data: letter,
        status: 201,
        notifyAccountIDs: [letter.authorAccountID, letter.recipientAccountID],
        statements: [
          db.prepare(`
            INSERT INTO letters(
              id, visit_id, friendship_id, author_account_id, recipient_account_id,
              ciphertext, iv, key_version, status, created_at_ms, delivered_at_ms
            )
            SELECT ?, ?, ?, ?, ?, ?, ?, ?, 'attached', ?, NULL
            FROM visits JOIN friendships ON friendships.id = visits.friendship_id
            WHERE visits.id = ? AND visits.status = 'active' AND visits.version = ?
              AND friendships.status = 'accepted'
          `).bind(
            letter.id, visitID, visit.friendshipID, letter.authorAccountID, letter.recipientAccountID,
            sealed.ciphertext, sealed.iv, sealed.keyVersion, now, visit.id, visit.version
          ),
          event(letter.authorAccountID),
          event(letter.recipientAccountID),
          idempotencyFromMarkerStatement(
            db, context.accountID, `createLetter:${visitID}`, idempotencyKey,
            fingerprint, 201, letter, now, "letters", "id", letter.id, letter.id
          )
        ]
      };
    }
  );
}

export async function getLetter(
  db: D1Database,
  context: AuthContext,
  letterID: string,
  secret: string
) {
  const row = await db.prepare(`
    SELECT letters.* FROM letters
    JOIN friendships ON friendships.id = letters.friendship_id
    WHERE letters.id = ?
      AND ? IN (friendships.requester_account_id, friendships.addressee_account_id)
  `).bind(letterID, context.accountID).first<{
    id: string;
    visit_id: string;
    friendship_id: string;
    author_account_id: string;
    recipient_account_id: string;
    ciphertext: string;
    iv: string;
    key_version: number;
    status: "attached" | "delivered";
    created_at_ms: number;
    delivered_at_ms: number | null;
  }>();
  if (!row) throw notFound("letter");
  const canRead = row.author_account_id === context.accountID ||
    (row.recipient_account_id === context.accountID && row.status === "delivered");
  if (!canRead) throw notFound("letter");
  if (row.key_version !== 1) throw new Error("unsupported_letter_key_version");
  return {
    id: row.id,
    visitID: row.visit_id,
    friendshipID: row.friendship_id,
    authorAccountID: row.author_account_id,
    recipientAccountID: row.recipient_account_id,
    body: await decryptLetter(row.ciphertext, row.iv, secret),
    status: row.status,
    createdAt: row.created_at_ms,
    deliveredAt: row.delivered_at_ms
  };
}
