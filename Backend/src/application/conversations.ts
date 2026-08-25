import type { AuthContext } from "../domain/models";
import { conflict, notFound } from "../errors";
import {
  accountEventFromMarkerStatement,
  idempotencyFromMarkerStatement
} from "../storage/events-repository";
import { requireFriendship } from "../storage/friendships-repository";
import { executeIdempotent } from "./idempotency";

export interface Conversation {
  id: string;
  friendshipID: string;
  initiatorPetID: string;
  recipientPetID: string;
  status: "active" | "ended";
  nextSpeakerPetID: string | null;
  turnCount: number;
  version: number;
  createdAt: number;
  endedAt: number | null;
}

export interface ConversationMessage {
  id: string;
  conversationID: string;
  senderAccountID: string;
  actorType: "human" | "pet_agent";
  body: string;
  turnIndex: number | null;
  createdAt: number;
}

interface ConversationRow {
  id: string;
  friendship_id: string;
  initiator_pet_id: string;
  recipient_pet_id: string;
  status: "active" | "ended";
  next_speaker_pet_id: string | null;
  turn_count: number;
  version: number;
  created_at_ms: number;
  ended_at_ms: number | null;
}

interface MessageRow {
  id: string;
  conversation_id: string;
  sender_account_id: string;
  actor_type: "human" | "pet_agent";
  body: string;
  turn_index: number | null;
  created_at_ms: number;
}

function conversationFromRow(row: ConversationRow): Conversation {
  return {
    id: row.id,
    friendshipID: row.friendship_id,
    initiatorPetID: row.initiator_pet_id,
    recipientPetID: row.recipient_pet_id,
    status: row.status,
    nextSpeakerPetID: row.next_speaker_pet_id,
    turnCount: row.turn_count,
    version: row.version,
    createdAt: row.created_at_ms,
    endedAt: row.ended_at_ms
  };
}

function messageFromRow(row: MessageRow): ConversationMessage {
  return {
    id: row.id,
    conversationID: row.conversation_id,
    senderAccountID: row.sender_account_id,
    actorType: row.actor_type,
    body: row.body,
    turnIndex: row.turn_index,
    createdAt: row.created_at_ms
  };
}

async function findConversation(db: D1Database, context: AuthContext, conversationID: string): Promise<Conversation> {
  const row = await db.prepare(`
    SELECT conversations.* FROM conversations
    JOIN friendships ON friendships.id = conversations.friendship_id
    WHERE conversations.id = ?
      AND ? IN (friendships.requester_account_id, friendships.addressee_account_id)
  `).bind(conversationID, context.accountID).first<ConversationRow>();
  if (!row) throw notFound("conversation");
  return conversationFromRow(row);
}

export async function listActiveConversations(db: D1Database, context: AuthContext): Promise<Conversation[]> {
  const rows = await db.prepare(`
    SELECT conversations.* FROM conversations
    JOIN friendships ON friendships.id = conversations.friendship_id
    WHERE conversations.status = 'active'
      AND ? IN (friendships.requester_account_id, friendships.addressee_account_id)
    ORDER BY conversations.created_at_ms DESC
  `).bind(context.accountID).all<ConversationRow>();
  return rows.results.map(conversationFromRow);
}

export async function listConversationMessages(
  db: D1Database,
  context: AuthContext,
  conversationID: string
): Promise<ConversationMessage[]> {
  await findConversation(db, context, conversationID);
  const rows = await db.prepare(`
    SELECT * FROM conversation_messages WHERE conversation_id = ?
    ORDER BY created_at_ms ASC, id ASC
  `).bind(conversationID).all<MessageRow>();
  return rows.results.map(messageFromRow);
}

export async function createConversation(
  db: D1Database,
  context: AuthContext,
  input: { friendshipID: string; recipientPetID: string; openingMessage: string; actorType: "pet_agent" },
  idempotencyKey: string,
  now = Date.now()
) {
  if (!context.isPrimaryAgentDevice) {
    throw conflict("not_primary_agent_device", "Only the primary Agent device can start a pet conversation");
  }
  const access = await requireFriendship(db, context, input.friendshipID, true);
  if (input.recipientPetID !== access.friendPetID) throw notFound("pet");
  return executeIdempotent<{ conversation: Conversation; message: ConversationMessage }>(
    db, context, "createConversation", idempotencyKey, input,
    async (fingerprint) => {
      const conversation: Conversation = {
        id: crypto.randomUUID(),
        friendshipID: input.friendshipID,
        initiatorPetID: context.petID,
        recipientPetID: input.recipientPetID,
        status: "active",
        nextSpeakerPetID: input.recipientPetID,
        turnCount: 1,
        version: 1,
        createdAt: now,
        endedAt: null
      };
      const message: ConversationMessage = {
        id: crypto.randomUUID(),
        conversationID: conversation.id,
        senderAccountID: context.accountID,
        actorType: "pet_agent",
        body: input.openingMessage,
        turnIndex: 0,
        createdAt: now
      };
      const data = { conversation, message };
      const event = (recipientAccountID: string) => accountEventFromMarkerStatement(db, {
        recipientAccountID,
        friendshipID: conversation.friendshipID,
        type: "conversation.message.created",
        aggregateType: "conversation",
        aggregateID: conversation.id,
        aggregateVersion: 1,
        payload: data,
        timelineVisible: false,
        occurredAt: now
      }, "conversations", "id", conversation.id, conversation.id);
      return {
        data,
        status: 201,
        notifyAccountIDs: [context.accountID, access.friendAccountID],
        statements: [
          db.prepare(`
            INSERT INTO conversations(
              id, friendship_id, initiator_pet_id, recipient_pet_id, status,
              next_speaker_pet_id, turn_count, version, created_at_ms, ended_at_ms
            ) VALUES (?, ?, ?, ?, 'active', ?, 1, 1, ?, NULL)
          `).bind(conversation.id, conversation.friendshipID, conversation.initiatorPetID,
            conversation.recipientPetID, conversation.nextSpeakerPetID, now),
          db.prepare(`
            INSERT INTO conversation_messages(
              id, conversation_id, sender_account_id, actor_type, body, turn_index, created_at_ms
            ) VALUES (?, ?, ?, 'pet_agent', ?, 0, ?)
          `).bind(message.id, message.conversationID, message.senderAccountID, message.body, now),
          event(context.accountID),
          event(access.friendAccountID),
          idempotencyFromMarkerStatement(
            db, context.accountID, "createConversation", idempotencyKey, fingerprint,
            201, data, now, "conversations", "id", conversation.id, conversation.id
          )
        ]
      };
    }
  );
}

export async function sendConversationMessage(
  db: D1Database,
  context: AuthContext,
  conversationID: string,
  input: { actorType: "human" | "pet_agent"; text: string },
  idempotencyKey: string,
  now = Date.now()
) {
  if (input.actorType === "pet_agent" && !context.isPrimaryAgentDevice) {
    throw conflict("not_primary_agent_device", "Only the primary Agent device can speak for a pet");
  }
  return executeIdempotent<{ conversation: Conversation; message: ConversationMessage }>(
    db, context, `sendConversationMessage:${conversationID}`, idempotencyKey, input,
    async (fingerprint) => {
      const current = await findConversation(db, context, conversationID);
      if (current.status !== "active") throw conflict("conversation_ended", "The conversation has ended");
      const access = await requireFriendship(db, context, current.friendshipID, true);
      if (input.actorType === "pet_agent" && current.nextSpeakerPetID !== context.petID) {
        throw conflict("not_your_turn", "The other pet has the next turn");
      }
      if (input.actorType === "pet_agent" && current.turnCount >= 6) {
        throw conflict("turn_limit_reached", "The conversation reached six pet turns");
      }
      const turnIndex = input.actorType === "pet_agent" ? current.turnCount : null;
      const nextTurnCount = input.actorType === "pet_agent" ? current.turnCount + 1 : current.turnCount;
      const endsNow = nextTurnCount >= 6;
      const nextPetID = context.petID === current.initiatorPetID
        ? current.recipientPetID
        : current.initiatorPetID;
      const conversation: Conversation = {
        ...current,
        status: endsNow ? "ended" : "active",
        nextSpeakerPetID: endsNow ? null : input.actorType === "pet_agent" ? nextPetID : current.nextSpeakerPetID,
        turnCount: nextTurnCount,
        version: current.version + 1,
        endedAt: endsNow ? now : null
      };
      const message: ConversationMessage = {
        id: crypto.randomUUID(),
        conversationID,
        senderAccountID: context.accountID,
        actorType: input.actorType,
        body: input.text,
        turnIndex,
        createdAt: now
      };
      const data = { conversation, message };
      const event = (recipientAccountID: string) => accountEventFromMarkerStatement(db, {
        recipientAccountID,
        friendshipID: conversation.friendshipID,
        type: "conversation.message.created",
        aggregateType: "conversation",
        aggregateID: conversation.id,
        aggregateVersion: conversation.version,
        payload: data,
        timelineVisible: false,
        occurredAt: now
      }, "conversation_messages", "id", message.id, message.id);
      return {
        data,
        status: 201,
        notifyAccountIDs: [context.accountID, access.friendAccountID],
        statements: [
          db.prepare(`
            UPDATE conversations SET status = ?, next_speaker_pet_id = ?, turn_count = ?,
              version = ?, ended_at_ms = ?
            WHERE id = ? AND status = 'active' AND version = ?
          `).bind(conversation.status, conversation.nextSpeakerPetID, conversation.turnCount,
            conversation.version, conversation.endedAt, conversation.id, current.version),
          db.prepare(`
            INSERT INTO conversation_messages(
              id, conversation_id, sender_account_id, actor_type, body, turn_index, created_at_ms
            )
            SELECT ?, ?, ?, ?, ?, ?, ? FROM conversations WHERE id = ? AND version = ?
          `).bind(message.id, conversationID, context.accountID, input.actorType, input.text,
            turnIndex, now, conversationID, conversation.version),
          event(context.accountID),
          event(access.friendAccountID),
          idempotencyFromMarkerStatement(
            db, context.accountID, `sendConversationMessage:${conversationID}`, idempotencyKey,
            fingerprint, 201, data, now, "conversation_messages", "id", message.id, message.id
          )
        ]
      };
    }
  );
}

export async function endConversation(
  db: D1Database,
  context: AuthContext,
  conversationID: string,
  input: { summary: string; actorType: "pet_agent" },
  idempotencyKey: string,
  now = Date.now()
) {
  if (!context.isPrimaryAgentDevice) {
    throw conflict("not_primary_agent_device", "Only the primary Agent device can end autonomously");
  }
  return executeIdempotent<Conversation>(
    db, context, `endConversation:${conversationID}`, idempotencyKey, input,
    async (fingerprint) => {
      const current = await findConversation(db, context, conversationID);
      const access = await requireFriendship(db, context, current.friendshipID, true);
      const conversation: Conversation = current.status === "ended" ? current : {
        ...current,
        status: "ended",
        nextSpeakerPetID: null,
        version: current.version + 1,
        endedAt: now
      };
      const event = (recipientAccountID: string) => accountEventFromMarkerStatement(db, {
        recipientAccountID,
        friendshipID: conversation.friendshipID,
        type: "conversation.ended",
        aggregateType: "conversation",
        aggregateID: conversation.id,
        aggregateVersion: conversation.version,
        payload: { conversation, summary: input.summary },
        timelineVisible: true,
        occurredAt: now
      }, "conversations", "version", conversation.id, conversation.version);
      const statements = current.status === "ended"
        ? [idempotencyFromMarkerStatement(
          db, context.accountID, `endConversation:${conversationID}`, idempotencyKey,
          fingerprint, 200, conversation, now, "conversations", "version",
          conversation.id, conversation.version
        )]
        : [
          db.prepare(`
            UPDATE conversations SET status = 'ended', next_speaker_pet_id = NULL,
              version = ?, ended_at_ms = ?
            WHERE id = ? AND status = 'active' AND version = ?
          `).bind(conversation.version, now, conversation.id, current.version),
          event(context.accountID),
          event(access.friendAccountID),
          idempotencyFromMarkerStatement(
            db, context.accountID, `endConversation:${conversationID}`, idempotencyKey,
            fingerprint, 200, conversation, now, "conversations", "version",
            conversation.id, conversation.version
          )
        ];
      return {
        data: conversation,
        status: 200,
        notifyAccountIDs: current.status === "ended" ? [] : [context.accountID, access.friendAccountID],
        statements
      };
    }
  );
}
