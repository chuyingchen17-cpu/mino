import { randomUUID } from "node:crypto";
import { sql, type Kysely, type Transaction } from "kysely";
import { conflict, notFound } from "../errors.js";
import { devProfiles, hashToken, isDevBootstrapToken, DEV_IDS } from "../dev-fixtures.js";
import type {
  AuthContext,
  Conversation,
  ConversationMessage,
  DevProfile,
  EventPage,
  Friendship,
  FriendshipEvent,
  FriendshipStatus,
  FriendshipSummary,
  Letter,
  MutationResult,
  PetDecisionResponse,
  PresenceSnapshot,
  Visit
} from "../domain.js";
import type {
  ConversationMutation,
  EndVisitReceipt,
  InteractionReceipt,
  MinoStore,
  ModelInferenceFailure,
  ModelUsageClaim,
  VisitReactionReceipt
} from "../store.js";
import { LetterCipher } from "../security/letter-cipher.js";
import { requestFingerprint } from "../security/request-fingerprint.js";
import type { Database } from "./schema.js";

type DBTransaction = Transaction<Database>;

interface IdempotencyCodec<T> {
  encode(value: T): unknown;
  decode(value: unknown): T;
}

interface FriendshipRow {
  id: string;
  scope_id: string;
  requester_account_id: string;
  addressee_account_id: string;
  pair_key: string;
  status: string;
  request_idempotency_key: string;
  response_idempotency_key: string | null;
  created_at: Date | string;
  responded_at: Date | string | null;
}

interface FriendshipAccess {
  friendshipID: string;
  scopeID: string;
  friendAccountID: string;
  friendPetID: string;
}

function iso(value: Date | string | null | undefined): string | null {
  if (value == null) return null;
  return value instanceof Date ? value.toISOString() : new Date(value).toISOString();
}

function pairKey(firstAccountID: string, secondAccountID: string): string {
  return [firstAccountID, secondAccountID].sort().join(":");
}

function friendshipFromRow(row: FriendshipRow): Friendship {
  return {
    id: row.id,
    requesterAccountID: row.requester_account_id,
    addresseeAccountID: row.addressee_account_id,
    status: row.status as FriendshipStatus,
    createdAt: iso(row.created_at)!,
    respondedAt: iso(row.responded_at)
  };
}

function conversationFromRow(row: {
  id: string; couple_id: string; initiator_pet_id: string; recipient_pet_id: string;
  status: string; next_speaker_pet_id: string | null; turn_count: number;
  created_at: Date | string; ended_at: Date | string | null;
}): Conversation {
  return {
    id: row.id,
    friendshipID: row.couple_id,
    initiatorPetID: row.initiator_pet_id,
    recipientPetID: row.recipient_pet_id,
    status: row.status as Conversation["status"],
    nextSpeakerPetID: row.next_speaker_pet_id,
    turnCount: row.turn_count,
    createdAt: iso(row.created_at)!,
    endedAt: iso(row.ended_at)
  };
}

function messageFromRow(row: {
  id: string; conversation_id: string; couple_id: string; actor_type: string; actor_id: string;
  recipient_pet_id: string; body: string; turn_index: number | null; created_at: Date | string;
}): ConversationMessage {
  return {
    id: row.id,
    conversationID: row.conversation_id,
    friendshipID: row.couple_id,
    actorType: row.actor_type as ConversationMessage["actorType"],
    actorID: row.actor_id,
    recipientPetID: row.recipient_pet_id,
    text: row.body,
    turnIndex: row.turn_index,
    createdAt: iso(row.created_at)!
  };
}

function visitFromRow(row: {
  id: string; couple_id: string; visitor_pet_id: string; visitor_owner_account_id: string;
  host_account_id: string; requested_by_account_id: string; reason: string | null; status: string;
  created_at: Date | string; started_at: Date | string | null; ended_at: Date | string | null;
}): Visit {
  return {
    id: row.id,
    friendshipID: row.couple_id,
    visitorPetID: row.visitor_pet_id,
    visitorOwnerAccountID: row.visitor_owner_account_id,
    hostAccountID: row.host_account_id,
    requestedByAccountID: row.requested_by_account_id,
    reason: row.reason,
    status: row.status as Visit["status"],
    createdAt: iso(row.created_at)!,
    startedAt: iso(row.started_at),
    endedAt: iso(row.ended_at)
  };
}

function letterFromRow(row: {
  id: string; couple_id: string; visit_id: string; author_account_id: string;
  recipient_account_id: string; body: string; status: string; created_at: Date | string;
  delivered_at: Date | string | null;
}, cipher: LetterCipher): Letter {
  return {
    id: row.id,
    friendshipID: row.couple_id,
    visitID: row.visit_id,
    authorAccountID: row.author_account_id,
    recipientAccountID: row.recipient_account_id,
    body: cipher.decrypt(row.body),
    status: row.status as Letter["status"],
    createdAt: iso(row.created_at)!,
    deliveredAt: iso(row.delivered_at)
  };
}

function eventFromRow(row: {
  id: string; sequence: string; couple_id: string; type: string; actor_type: string;
  actor_id: string | null; payload: unknown; timeline_visible: boolean; occurred_at: Date | string;
}): FriendshipEvent {
  return {
    id: row.id,
    sequence: Number(row.sequence),
    friendshipID: row.couple_id,
    type: row.type,
    actorType: row.actor_type as FriendshipEvent["actorType"],
    actorID: row.actor_id,
    payload: (row.payload ?? {}) as Record<string, unknown>,
    timelineVisible: row.timeline_visible,
    occurredAt: iso(row.occurred_at)!
  };
}

function isUniqueViolation(error: unknown): boolean {
  return typeof error === "object" && error !== null && "code" in error && (error as { code?: string }).code === "23505";
}

function isUniqueConstraintViolation(error: unknown, constraint: string): boolean {
  return isUniqueViolation(error) &&
    "constraint" in (error as object) &&
    (error as { constraint?: string }).constraint === constraint;
}

export class PostgresMinoStore implements MinoStore {
  constructor(
    private readonly database: Kysely<Database>,
    private readonly letterCipher: LetterCipher,
    private readonly allowDevCredentials = false
  ) {}

  async close(): Promise<void> {
    await this.database.destroy();
  }

  fingerprintRequest(value: unknown): string {
    return this.letterCipher.fingerprint(value);
  }

  async bootstrapDevProfiles(): Promise<{ alice: DevProfile; bob: DevProfile; charlie: DevProfile }> {
    const profiles = devProfiles();
    await this.database.transaction().execute(async (trx) => {
      for (const account of [profiles.alice, profiles.bob, profiles.charlie]) {
        await trx.insertInto("accounts").values({
          id: account.accountID,
          display_name: account.accountName,
          auth_token_hash: hashToken(account.token)
        }).onConflict((builder) => builder.column("id").doUpdateSet({
          display_name: account.accountName,
          auth_token_hash: hashToken(account.token)
        })).execute();
      }

      await trx.insertInto("couples").values({
        id: DEV_IDS.couple,
        account_a_id: DEV_IDS.aliceAccount,
        account_b_id: DEV_IDS.bobAccount
      }).onConflict((builder) => builder.column("id").doNothing()).execute();

      for (const pet of [profiles.alice, profiles.bob, profiles.charlie]) {
        await trx.insertInto("pets").values({
          id: pet.petID,
          couple_id: pet.profile === "charlie" ? null : DEV_IDS.couple,
          owner_account_id: pet.accountID,
          display_name: pet.petName
        }).onConflict((builder) => builder.column("id").doUpdateSet({
          owner_account_id: pet.accountID,
          display_name: pet.petName,
          couple_id: pet.profile === "charlie" ? null : DEV_IDS.couple
        })).execute();
      }

      await trx.insertInto("friendships").values({
        id: DEV_IDS.friendship,
        scope_id: DEV_IDS.couple,
        requester_account_id: DEV_IDS.aliceAccount,
        addressee_account_id: DEV_IDS.bobAccount,
        pair_key: pairKey(DEV_IDS.aliceAccount, DEV_IDS.bobAccount),
        status: "accepted",
        request_idempotency_key: `legacy:${DEV_IDS.friendship}`,
        response_idempotency_key: null,
        responded_at: new Date(0)
      }).onConflict((builder) => builder.column("id").doUpdateSet({
        status: "accepted",
        responded_at: new Date(0)
      })).execute();
    });
    return profiles;
  }

  async authenticate(token: string): Promise<AuthContext | null> {
    if (!this.allowDevCredentials && isDevBootstrapToken(token)) return null;
    const account = await this.database.selectFrom("accounts")
      .select("id")
      .where("auth_token_hash", "=", hashToken(token))
      .executeTakeFirst();
    if (!account) return null;
    const pet = await this.database.selectFrom("pets")
      .select("id")
      .where("owner_account_id", "=", account.id)
      .executeTakeFirst();
    if (!pet) return null;
    return { accountID: account.id, petID: pet.id };
  }

  async listFriendships(context: AuthContext, status?: FriendshipStatus): Promise<FriendshipSummary[]> {
    let query = this.database.selectFrom("friendships").selectAll()
      .where((expression) => expression.or([
        expression("requester_account_id", "=", context.accountID),
        expression("addressee_account_id", "=", context.accountID)
      ]));
    if (status) query = query.where("status", "=", status);
    const rows = await query.orderBy("created_at", "desc").orderBy("id", "desc").execute();
    return Promise.all(rows.map((row) => this.friendshipSummary(context, row)));
  }

  async requestFriendship(
    context: AuthContext,
    input: { addresseeAccountID: string; idempotencyKey: string }
  ): Promise<FriendshipSummary> {
    if (input.addresseeAccountID === context.accountID) {
      throw conflict("cannot_friend_self", "An account cannot send a friendship request to itself");
    }
    const target = await this.database.selectFrom("accounts")
      .innerJoin("pets", "pets.owner_account_id", "accounts.id")
      .select(["accounts.id"])
      .where("accounts.id", "=", input.addresseeAccountID)
      .executeTakeFirst();
    if (!target) throw notFound("account");

    const canonicalPair = pairKey(context.accountID, input.addresseeAccountID);
    const requestFingerprintValue = requestFingerprint(input);
    const result = await this.database.transaction().execute(async (trx) => {
      await sql`select pg_advisory_xact_lock(hashtext(${`friendship-request:${context.accountID}:${input.idempotencyKey}`}))`.execute(trx);
      const prior = await trx.selectFrom("friendships").selectAll()
        .where("requester_account_id", "=", context.accountID)
        .where("request_idempotency_key", "=", input.idempotencyKey)
        .executeTakeFirst();
      if (prior) {
        if (requestFingerprint({
          addresseeAccountID: prior.addressee_account_id,
          idempotencyKey: prior.request_idempotency_key
        }) !== requestFingerprintValue) {
          throw conflict("idempotency_key_reused", "The idempotency key was already used with a different request");
        }
        return { row: prior, replayed: true };
      }

      await sql`select pg_advisory_xact_lock(hashtext(${`friendship-pair:${canonicalPair}`}))`.execute(trx);
      const existing = await trx.selectFrom("friendships").select("id")
        .where("pair_key", "=", canonicalPair)
        .where("status", "in", ["pending", "accepted"])
        .executeTakeFirst();
      if (existing) throw conflict("friendship_exists", "A pending or accepted friendship already exists");

      const friendshipID = randomUUID();
      const accounts = [context.accountID, input.addresseeAccountID].sort();
      await trx.insertInto("couples").values({
        id: friendshipID,
        account_a_id: accounts[0]!,
        account_b_id: accounts[1]!
      }).execute();
      const row = await trx.insertInto("friendships").values({
        id: friendshipID,
        scope_id: friendshipID,
        requester_account_id: context.accountID,
        addressee_account_id: input.addresseeAccountID,
        pair_key: canonicalPair,
        status: "pending",
        request_idempotency_key: input.idempotencyKey,
        response_idempotency_key: null,
        responded_at: null
      }).returningAll().executeTakeFirstOrThrow();
      return { row, replayed: false };
    });
    const summary = await this.friendshipSummary(context, result.row);
    return result.replayed ? { ...summary, status: "pending", respondedAt: null } : summary;
  }

  async respondFriendship(
    context: AuthContext,
    friendshipID: string,
    input: { response: "accept" | "reject"; idempotencyKey: string }
  ): Promise<FriendshipSummary> {
    const row = await this.database.transaction().execute(async (trx) => {
      const current = await trx.selectFrom("friendships").selectAll()
        .where("id", "=", friendshipID)
        .where("addressee_account_id", "=", context.accountID)
        .forUpdate()
        .executeTakeFirst();
      if (!current) throw notFound("friendship");

      if (current.response_idempotency_key === input.idempotencyKey) {
        const expectedStatus = input.response === "accept" ? "accepted" : "rejected";
        if (current.status !== expectedStatus) {
          throw conflict("idempotency_key_reused", "The idempotency key was already used with a different request");
        }
        return current;
      }
      if (current.status !== "pending") {
        throw conflict("friendship_resolved", "The friendship request has already been resolved");
      }
      return trx.updateTable("friendships").set({
        status: input.response === "accept" ? "accepted" : "rejected",
        response_idempotency_key: input.idempotencyKey,
        responded_at: new Date()
      }).where("id", "=", friendshipID).returningAll().executeTakeFirstOrThrow();
    });
    return this.friendshipSummary(context, row);
  }

  async resolveSingleAcceptedFriendship(context: AuthContext): Promise<string> {
    const rows = await this.database.selectFrom("friendships").select("id")
      .where("status", "=", "accepted")
      .where((expression) => expression.or([
        expression("requester_account_id", "=", context.accountID),
        expression("addressee_account_id", "=", context.accountID)
      ]))
      .limit(2)
      .execute();
    if (rows.length !== 1) {
      throw conflict("friendship_context_required", "Specify a friendship because the account does not have exactly one accepted friend");
    }
    return rows[0]!.id;
  }

  async getEvents(
    context: AuthContext,
    friendshipID: string,
    after: string | undefined,
    limit: number,
    timelineOnly = false
  ): Promise<EventPage> {
    const access = await this.requireAcceptedFriendship(context, friendshipID);
    let afterSequence = "0";
    if (after) {
      const cursor = await this.database.selectFrom("couple_events")
        .select("sequence")
        .where("couple_id", "=", access.scopeID)
        .where("id", "=", after)
        .executeTakeFirst();
      if (!cursor) throw notFound("event cursor");
      afterSequence = cursor.sequence;
    }
    let query = this.database.selectFrom("couple_events").selectAll()
      .where("couple_id", "=", access.scopeID)
      .where("sequence", ">", afterSequence)
      .orderBy("sequence", "asc")
      .limit(limit);
    if (timelineOnly) query = query.where("timeline_visible", "=", true);
    const events = (await query.execute()).map(eventFromRow);
    return { events, nextCursor: events.at(-1)?.id ?? after ?? null };
  }

  async getPresence(context: AuthContext, friendshipID: string): Promise<PresenceSnapshot> {
    const access = await this.requireAcceptedFriendship(context, friendshipID);
    const [pets, lastEvent] = await Promise.all([
      this.database.selectFrom("pets").selectAll()
        .where("owner_account_id", "in", [context.accountID, access.friendAccountID]).execute(),
      this.database.selectFrom("couple_events").select(["id", "sequence", "occurred_at"])
        .where("couple_id", "=", access.scopeID).orderBy("sequence", "desc").executeTakeFirst()
    ]);
    const petIDs = pets.map((pet) => pet.id);
    const globalActiveRows = petIDs.length === 0
      ? []
      : await this.database.selectFrom("visits").selectAll()
        .where("visitor_pet_id", "in", petIDs)
        .where("status", "=", "active")
        .execute();
    const globalActiveVisits = globalActiveRows.map(visitFromRow);
    const friendshipActiveVisits = globalActiveVisits.filter((visit) => visit.friendshipID === access.scopeID);
    const now = new Date().toISOString();
    return {
      friendshipID,
      pets: pets.map((pet) => {
        const activeVisit = globalActiveVisits.find((visit) => visit.visitorPetID === pet.id);
        const isVisibleVisit = activeVisit?.friendshipID === access.scopeID;
        return {
          petID: pet.id,
          ownerAccountID: pet.owner_account_id,
          phase: activeVisit ? "visiting" as const : "at_home" as const,
          currentHostAccountID: activeVisit ? (isVisibleVisit ? activeVisit.hostAccountID : null) : pet.owner_account_id,
          activeVisitID: isVisibleVisit ? activeVisit.id : null,
          revision: Number(lastEvent?.sequence ?? 0),
          updatedAt: iso(lastEvent?.occurred_at) ?? now
        };
      }),
      activeVisits: friendshipActiveVisits,
      serverCursor: lastEvent?.id ?? null,
      syncedAt: now
    };
  }

  async recordLegacyInteraction(
    context: AuthContext,
    friendshipID: string,
    input: { senderPetID: string; recipientPetID: string; kind: string; idempotencyKey: string }
  ): Promise<MutationResult<InteractionReceipt>> {
    const access = await this.requireAcceptedFriendship(context, friendshipID);
    if (input.senderPetID !== context.petID || input.recipientPetID !== access.friendPetID) throw notFound("pet");
    return this.idempotent(access.scopeID, "legacy-interaction", input.idempotencyKey, input, async (trx) => {
      const data = { interactionID: randomUUID(), visitID: null, kind: input.kind, acceptedAt: new Date().toISOString() };
      const event = await this.appendEvent(trx, access.scopeID, "interaction", "pet", context.petID, {
        interactionID: data.interactionID,
        kind: input.kind,
        senderPetID: context.petID,
        recipientPetID: access.friendPetID
      }, true);
      return { data, events: [event], replayed: false };
    });
  }

  async createConversation(
    context: AuthContext,
    friendshipID: string,
    input: { recipientPetID: string; openingMessage: string; idempotencyKey: string }
  ): Promise<MutationResult<ConversationMutation>> {
    const access = await this.requireAcceptedFriendship(context, friendshipID);
    if (input.recipientPetID !== access.friendPetID) throw notFound("recipient pet");
    try {
      return await this.idempotent(access.scopeID, "create-conversation", input.idempotencyKey, input, async (trx) => {
        const conversationID = randomUUID();
        const conversationRow = await trx.insertInto("conversations").values({
          id: conversationID,
          couple_id: access.scopeID,
          initiator_pet_id: context.petID,
          recipient_pet_id: access.friendPetID,
          status: "active",
          next_speaker_pet_id: access.friendPetID,
          turn_count: 1,
          ended_at: null,
          idempotency_key: input.idempotencyKey
        }).returningAll().executeTakeFirstOrThrow();
        const messageRow = await trx.insertInto("messages").values({
          id: randomUUID(),
          conversation_id: conversationID,
          couple_id: access.scopeID,
          actor_type: "pet",
          actor_id: context.petID,
          recipient_pet_id: access.friendPetID,
          body: input.openingMessage,
          turn_index: 0,
          idempotency_key: `${input.idempotencyKey}:opening`
        }).returningAll().executeTakeFirstOrThrow();
        const conversation = conversationFromRow(conversationRow);
        const message = messageFromRow(messageRow);
        const event = await this.appendEvent(trx, access.scopeID, "conversation_message", "pet", context.petID, {
          conversationID,
          messageID: message.id,
          recipientPetID: access.friendPetID,
          text: message.text,
          turnIndex: 0
        }, false);
        return { data: { conversation, message }, events: [event], replayed: false };
      });
    } catch (error) {
      if (isUniqueConstraintViolation(error, "one_active_conversation_per_couple")) {
        throw conflict("active_conversation_exists", "This friendship already has an active conversation");
      }
      throw error;
    }
  }

  async listConversations(context: AuthContext, friendshipID: string, status: "active"): Promise<Conversation[]> {
    const access = await this.requireAcceptedFriendship(context, friendshipID);
    const rows = await this.database.selectFrom("conversations").selectAll()
      .where("couple_id", "=", access.scopeID)
      .where("status", "=", status)
      .where((expression) => expression.or([
        expression("initiator_pet_id", "=", context.petID),
        expression("recipient_pet_id", "=", context.petID)
      ]))
      .orderBy("created_at", "desc")
      .execute();
    return rows.map(conversationFromRow);
  }

  async getConversationMessages(
    context: AuthContext,
    friendshipID: string,
    conversationID: string
  ): Promise<ConversationMessage[]> {
    const access = await this.requireAcceptedFriendship(context, friendshipID);
    const conversation = await this.database.selectFrom("conversations")
      .select(["initiator_pet_id", "recipient_pet_id"])
      .where("id", "=", conversationID)
      .where("couple_id", "=", access.scopeID)
      .executeTakeFirst();
    if (!conversation || ![conversation.initiator_pet_id, conversation.recipient_pet_id].includes(context.petID)) {
      throw notFound("conversation");
    }
    const rows = await this.database.selectFrom("messages").selectAll()
      .where("couple_id", "=", access.scopeID)
      .where("conversation_id", "=", conversationID)
      .orderBy("created_at", "asc")
      .orderBy("id", "asc")
      .execute();
    return rows.map(messageFromRow);
  }

  async addConversationMessage(
    context: AuthContext,
    friendshipID: string,
    conversationID: string,
    input: { actorType: "human" | "pet"; text: string; idempotencyKey: string }
  ): Promise<MutationResult<ConversationMutation>> {
    const access = await this.requireAcceptedFriendship(context, friendshipID);
    return this.idempotent(access.scopeID, "conversation-message", input.idempotencyKey, { conversationID, ...input }, async (trx) => {
      const row = await trx.selectFrom("conversations").selectAll()
        .where("id", "=", conversationID).where("couple_id", "=", access.scopeID)
        .forUpdate().executeTakeFirst();
      if (!row || ![row.initiator_pet_id, row.recipient_pet_id].includes(context.petID)) throw notFound("conversation");
      if (row.status !== "active") throw conflict("conversation_ended", "The conversation has already ended");
      if (input.actorType === "pet" && row.next_speaker_pet_id !== context.petID) {
        throw conflict("not_your_turn", "The other pet has the next turn");
      }
      if (input.actorType === "pet" && row.turn_count >= 6) {
        throw conflict("turn_limit_reached", "The conversation has reached six pet turns");
      }

      const recipientPetID = context.petID === row.initiator_pet_id ? row.recipient_pet_id : row.initiator_pet_id;
      const turnIndex = input.actorType === "pet" ? row.turn_count : null;
      const nextTurnCount = input.actorType === "pet" ? row.turn_count + 1 : row.turn_count;
      const endsNow = nextTurnCount >= 6;
      const now = new Date();
      const updatedRow = await trx.updateTable("conversations").set({
        turn_count: nextTurnCount,
        next_speaker_pet_id: endsNow ? null : input.actorType === "pet" ? recipientPetID : row.next_speaker_pet_id,
        status: endsNow ? "ended" : "active",
        ended_at: endsNow ? now : null
      }).where("id", "=", conversationID).where("couple_id", "=", access.scopeID)
        .returningAll().executeTakeFirstOrThrow();
      const actorID = input.actorType === "pet" ? context.petID : context.accountID;
      const messageRow = await trx.insertInto("messages").values({
        id: randomUUID(),
        conversation_id: conversationID,
        couple_id: access.scopeID,
        actor_type: input.actorType,
        actor_id: actorID,
        recipient_pet_id: recipientPetID,
        body: input.text,
        turn_index: turnIndex,
        idempotency_key: input.idempotencyKey
      }).returningAll().executeTakeFirstOrThrow();
      const message = messageFromRow(messageRow);
      const events = [await this.appendEvent(trx, access.scopeID, "conversation_message", input.actorType, actorID, {
        conversationID,
        messageID: message.id,
        recipientPetID,
        text: input.text,
        turnIndex
      }, false)];
      return { data: { conversation: conversationFromRow(updatedRow), message }, events, replayed: false };
    });
  }

  async endConversation(
    context: AuthContext,
    friendshipID: string,
    conversationID: string,
    input: { summary: string; idempotencyKey: string }
  ): Promise<MutationResult<Conversation>> {
    const access = await this.requireAcceptedFriendship(context, friendshipID);
    return this.idempotent(access.scopeID, `end-conversation:${conversationID}`, input.idempotencyKey, { conversationID, ...input }, async (trx) => {
      const row = await trx.selectFrom("conversations").selectAll()
        .where("id", "=", conversationID).where("couple_id", "=", access.scopeID)
        .forUpdate().executeTakeFirst();
      if (!row || row.initiator_pet_id !== context.petID) throw notFound("conversation");
      const endedRow = row.status === "ended" ? row : await trx.updateTable("conversations").set({
        status: "ended",
        next_speaker_pet_id: null,
        ended_at: new Date()
      }).where("id", "=", conversationID).returningAll().executeTakeFirstOrThrow();
      const existingSummary = await trx.selectFrom("couple_events").select("id")
        .where("couple_id", "=", access.scopeID)
        .where("type", "=", "conversation_summary")
        .where(sql<string>`payload ->> 'conversationID'`, "=", conversationID)
        .executeTakeFirst();
      if (existingSummary) return { data: conversationFromRow(endedRow), events: [], replayed: false };
      const event = await this.appendEvent(trx, access.scopeID, "conversation_summary", "pet", context.petID, {
        conversationID,
        summary: input.summary.trim()
      }, true);
      return { data: conversationFromRow(endedRow), events: [event], replayed: false };
    });
  }

  async createVisitInvitation(
    context: AuthContext,
    friendshipID: string,
    input: { visitorPetID: string; hostAccountID: string; reason?: string; idempotencyKey: string }
  ): Promise<MutationResult<Visit>> {
    const access = await this.requireAcceptedFriendship(context, friendshipID);
    const validDirection =
      (input.visitorPetID === context.petID && input.hostAccountID === access.friendAccountID) ||
      (input.visitorPetID === access.friendPetID && input.hostAccountID === context.accountID);
    if (!validDirection) throw notFound("visitor or host");
    return this.idempotent(access.scopeID, "create-visit-invitation", input.idempotencyKey, input, async (trx) => {
      const visitorOwnerAccountID = input.visitorPetID === context.petID ? context.accountID : access.friendAccountID;
      const row = await trx.insertInto("visits").values({
        id: randomUUID(),
        couple_id: access.scopeID,
        visitor_pet_id: input.visitorPetID,
        visitor_owner_account_id: visitorOwnerAccountID,
        host_account_id: input.hostAccountID,
        requested_by_account_id: context.accountID,
        reason: input.reason?.trim() || null,
        status: "pending",
        started_at: null,
        ended_at: null,
        idempotency_key: input.idempotencyKey
      }).returningAll().executeTakeFirstOrThrow();
      const visit = visitFromRow(row);
      const responderAccountID = visit.requestedByAccountID === visit.visitorOwnerAccountID
        ? visit.hostAccountID
        : visit.visitorOwnerAccountID;
      const event = await this.appendEvent(trx, access.scopeID, "visit_invited", "human", context.accountID, {
        visitID: visit.id,
        visitorPetID: visit.visitorPetID,
        hostAccountID: visit.hostAccountID,
        requestedByAccountID: visit.requestedByAccountID,
        responderAccountID,
        reason: visit.reason
      }, false);
      return { data: visit, events: [event], replayed: false };
    });
  }

  async listVisitInvitations(context: AuthContext, friendshipID: string, status = "pending"): Promise<Visit[]> {
    const access = await this.requireAcceptedFriendship(context, friendshipID);
    const rows = await this.database.selectFrom("visits").selectAll()
      .where("couple_id", "=", access.scopeID).where("status", "=", status)
      .orderBy("created_at", "desc").execute();
    return rows.map(visitFromRow);
  }

  async respondVisitInvitation(
    context: AuthContext,
    friendshipID: string,
    visitID: string,
    input: { response: "accept" | "decline"; idempotencyKey: string }
  ): Promise<MutationResult<Visit>> {
    const access = await this.requireAcceptedFriendship(context, friendshipID);
    try {
      return await this.idempotent(access.scopeID, `respond-visit:${visitID}`, input.idempotencyKey, { visitID, ...input }, async (trx) => {
        const row = await trx.selectFrom("visits").selectAll()
          .where("id", "=", visitID).where("couple_id", "=", access.scopeID)
          .forUpdate().executeTakeFirst();
        if (!row) throw notFound("visit invitation");
        const responderAccountID = row.requested_by_account_id === row.visitor_owner_account_id
          ? row.host_account_id
          : row.visitor_owner_account_id;
        if (responderAccountID !== context.accountID) throw notFound("visit invitation");
        if (row.status !== "pending") throw conflict("invitation_resolved", "The visit invitation has already been resolved");
        if (input.response === "accept") {
          const active = await trx.selectFrom("visits").select("id")
            .where("status", "=", "active")
            .where((expression) => expression.or([
              expression("visitor_pet_id", "=", row.visitor_pet_id),
              expression("host_account_id", "=", row.host_account_id)
            ]))
            .executeTakeFirst();
          if (active) throw conflict("active_visit_exists", "The visitor or host already has an active visit");
        }
        const now = new Date();
        const updated = await trx.updateTable("visits").set({
          status: input.response === "accept" ? "active" : "cancelled",
          started_at: input.response === "accept" ? now : null,
          ended_at: input.response === "decline" ? now : null
        }).where("id", "=", visitID).where("couple_id", "=", access.scopeID)
          .returningAll().executeTakeFirstOrThrow();
        const visit = visitFromRow(updated);
        const event = await this.appendEvent(
          trx,
          access.scopeID,
          input.response === "accept" ? "visit_arrived" : "visit_declined",
          "pet",
          context.petID,
          {
            visitID,
            visitorPetID: visit.visitorPetID,
            hostAccountID: visit.hostAccountID,
            requestedByAccountID: visit.requestedByAccountID,
            responderAccountID
          },
          input.response === "accept"
        );
        return { data: visit, events: [event], replayed: false };
      });
    } catch (error) {
      if (
        isUniqueConstraintViolation(error, "one_active_visit_per_visitor_pet") ||
        isUniqueConstraintViolation(error, "one_active_visit_per_host_account")
      ) {
        throw conflict("active_visit_exists", "The visitor or host already has an active visit");
      }
      throw error;
    }
  }

  async addVisitInteraction(
    context: AuthContext,
    friendshipID: string,
    visitID: string,
    input: { kind: "feed" | "play" | "message"; text?: string; idempotencyKey: string }
  ): Promise<MutationResult<InteractionReceipt>> {
    const access = await this.requireAcceptedFriendship(context, friendshipID);
    return this.idempotent(access.scopeID, `visit-interaction:${visitID}`, input.idempotencyKey, { visitID, ...input }, async (trx) => {
      const visit = await this.requireVisit(trx, access.scopeID, visitID, true);
      if (visit.status !== "active") throw conflict("visit_not_active", "Interactions require an active visit");
      if (visit.hostAccountID !== context.accountID) throw notFound("visit");
      const data = { interactionID: randomUUID(), visitID, kind: input.kind, acceptedAt: new Date().toISOString() };
      const event = await this.appendEvent(trx, access.scopeID, "visit_interaction", "human", context.accountID, {
        interactionID: data.interactionID,
        visitID,
        visitorPetID: visit.visitorPetID,
        kind: input.kind,
        ...(input.text ? { text: input.text } : {})
      }, input.kind !== "message");
      return { data, events: [event], replayed: false };
    });
  }

  async addVisitReaction(
    context: AuthContext,
    friendshipID: string,
    visitID: string,
    input: { reaction: string; text?: string; idempotencyKey: string }
  ): Promise<MutationResult<VisitReactionReceipt>> {
    const access = await this.requireAcceptedFriendship(context, friendshipID);
    return this.idempotent(access.scopeID, `visit-reaction:${visitID}`, input.idempotencyKey, { visitID, ...input }, async (trx) => {
      const visit = await this.requireVisit(trx, access.scopeID, visitID, true);
      if (visit.status !== "active") throw conflict("visit_not_active", "Reactions require an active visit");
      if (visit.visitorOwnerAccountID !== context.accountID || visit.visitorPetID !== context.petID) throw notFound("visit");
      const data = {
        reactionID: randomUUID(),
        visitID,
        reaction: input.reaction,
        acceptedAt: new Date().toISOString()
      };
      const event = await this.appendEvent(trx, access.scopeID, "visit_reaction", "pet", context.petID, {
        visitID,
        visitorPetID: visit.visitorPetID,
        reaction: input.reaction,
        ...(input.text ? { text: input.text } : {})
      }, false);
      return { data, events: [event], replayed: false };
    });
  }

  async createVisitLetter(
    context: AuthContext,
    friendshipID: string,
    visitID: string,
    input: { body: string; idempotencyKey: string }
  ): Promise<MutationResult<Letter>> {
    const access = await this.requireAcceptedFriendship(context, friendshipID);
    return this.idempotent(access.scopeID, "visit-letter", input.idempotencyKey, { visitID, ...input }, async (trx) => {
      const visit = await this.requireVisit(trx, access.scopeID, visitID, true);
      if (visit.status !== "active") throw conflict("visit_not_active", "A letter can only be attached during an active visit");
      if (visit.hostAccountID !== context.accountID) throw notFound("visit");
      const row = await trx.insertInto("letters").values({
        id: randomUUID(),
        couple_id: access.scopeID,
        visit_id: visitID,
        author_account_id: context.accountID,
        recipient_account_id: visit.visitorOwnerAccountID,
        body: this.letterCipher.encrypt(input.body),
        status: "carried",
        delivered_at: null,
        idempotency_key: input.idempotencyKey
      }).returningAll().executeTakeFirstOrThrow();
      const letter = letterFromRow(row, this.letterCipher);
      const event = await this.appendEvent(trx, access.scopeID, "letter_attached", "human", context.accountID, {
        letterID: letter.id,
        visitID,
        recipientAccountID: letter.recipientAccountID
      }, false);
      return { data: letter, events: [event], replayed: false };
    }, {
      encode: (letter) => this.sealLetterResponse(letter),
      decode: (stored) => this.openLetterResponse(stored as Letter)
    });
  }

  async getLetter(context: AuthContext, friendshipID: string, letterID: string): Promise<Letter> {
    const access = await this.requireAcceptedFriendship(context, friendshipID);
    const row = await this.database.selectFrom("letters").selectAll()
      .where("id", "=", letterID)
      .where("couple_id", "=", access.scopeID)
      .executeTakeFirst();
    if (!row) throw notFound("letter");
    const letter = letterFromRow(row, this.letterCipher);
    const authorCanRead = letter.authorAccountID === context.accountID;
    const recipientCanRead = letter.recipientAccountID === context.accountID && letter.status === "delivered";
    if (!authorCanRead && !recipientCanRead) throw notFound("letter");
    return letter;
  }

  async endVisit(
    context: AuthContext,
    friendshipID: string,
    visitID: string,
    input: { idempotencyKey: string }
  ): Promise<MutationResult<EndVisitReceipt>> {
    const access = await this.requireAcceptedFriendship(context, friendshipID);
    return this.idempotent(access.scopeID, `end-visit:${visitID}`, input.idempotencyKey, { visitID, ...input }, async (trx) => {
      const visit = await this.requireVisit(trx, access.scopeID, visitID, true);
      if (visit.status !== "active") throw conflict("visit_not_active", "The visit is not active");
      const now = new Date();
      const endedRow = await trx.updateTable("visits").set({ status: "ended", ended_at: now })
        .where("id", "=", visitID).where("couple_id", "=", access.scopeID)
        .returningAll().executeTakeFirstOrThrow();
      const deliveredRows = await trx.updateTable("letters").set({ status: "delivered", delivered_at: now })
        .where("visit_id", "=", visitID).where("couple_id", "=", access.scopeID).where("status", "=", "carried")
        .returningAll().execute();
      const ended = visitFromRow(endedRow);
      const deliveredLetters = deliveredRows.map((row) => letterFromRow(row, this.letterCipher));
      const events = [await this.appendEvent(trx, access.scopeID, "visit_returned", "human", context.accountID, {
        visitID,
        visitorPetID: ended.visitorPetID
      }, true)];
      for (const letter of deliveredLetters) {
        events.push(await this.appendEvent(trx, access.scopeID, "letter_received", "system", null, {
          letterID: letter.id,
          visitID,
          authorAccountID: letter.authorAccountID,
          recipientAccountID: letter.recipientAccountID
        }, true));
      }
      return { data: { visit: ended, deliveredLetters }, events, replayed: false };
    }, {
      encode: (receipt) => ({
        ...receipt,
        deliveredLetters: receipt.deliveredLetters.map((letter) => this.sealLetterResponse(letter))
      }),
      decode: (stored) => {
        const receipt = stored as EndVisitReceipt;
        return {
          ...receipt,
          deliveredLetters: receipt.deliveredLetters.map((letter) => this.openLetterResponse(letter))
        };
      }
    });
  }

  async claimModelInference(
    context: AuthContext,
    inferenceID: string,
    provider: string,
    model: string,
    fingerprint: string,
    staleAfterMilliseconds = 60_000
  ): Promise<ModelUsageClaim> {
    return this.database.transaction().execute(async (trx) => {
      await sql`select pg_advisory_xact_lock(hashtext(${`${context.accountID}:inference:${inferenceID}`}))`.execute(trx);
      const existing = await trx.selectFrom("model_usage").selectAll()
        .where("account_id", "=", context.accountID)
        .where("inference_id", "=", inferenceID)
        .executeTakeFirst();
      if (!existing) {
        await trx.insertInto("model_usage").values({
          id: randomUUID(),
          couple_id: null,
          account_id: context.accountID,
          inference_id: inferenceID,
          provider,
          model,
          status: "started",
          input_tokens: 0,
          output_tokens: 0,
          claimed_at: new Date(),
          completed_at: null,
          request_fingerprint: fingerprint,
          response: null
        }).execute();
        return { state: "claimed" };
      }
      if (existing.request_fingerprint !== fingerprint) {
        throw conflict("inference_id_reused", "The inference ID was already used with a different request");
      }
      if (existing.status === "completed" && existing.response) {
        return {
          state: "replay",
          response: { ...(existing.response as PetDecisionResponse), replayed: true }
        };
      }
      if (existing.status === "failed") {
        const stored = existing.response as { failure?: ModelInferenceFailure } | null;
        return {
          state: "failed",
          failure: stored?.failure ?? {
            statusCode: 503,
            code: "model_inference_failed",
            message: "The previous model inference failed"
          }
        };
      }
      const claimedAt = existing.claimed_at instanceof Date
        ? existing.claimed_at.getTime()
        : new Date(existing.claimed_at).getTime();
      if (existing.status === "started" && Date.now() - claimedAt < staleAfterMilliseconds) {
        return { state: "in_progress" };
      }
      return { state: "outcome_unknown" };
    });
  }

  async completeModelInference(
    context: AuthContext,
    inferenceID: string,
    status: "completed" | "failed",
    inputTokens: number,
    outputTokens: number,
    response?: PetDecisionResponse,
    failure?: ModelInferenceFailure
  ): Promise<void> {
    await this.database.updateTable("model_usage").set({
      status,
      input_tokens: inputTokens,
      output_tokens: outputTokens,
      completed_at: new Date(),
      response: status === "completed"
        ? response ?? null
        : failure ? { failure } : null
    }).where("account_id", "=", context.accountID).where("inference_id", "=", inferenceID).execute();
  }

  private async friendshipSummary(context: AuthContext, row: FriendshipRow): Promise<FriendshipSummary> {
    const friendship = friendshipFromRow(row);
    const friendAccountID = row.requester_account_id === context.accountID
      ? row.addressee_account_id
      : row.requester_account_id;
    if (![row.requester_account_id, row.addressee_account_id].includes(context.accountID)) throw notFound("friendship");
    const friend = await this.database.selectFrom("accounts")
      .innerJoin("pets", "pets.owner_account_id", "accounts.id")
      .select([
        "accounts.id as account_id",
        "accounts.display_name as account_name",
        "pets.id as pet_id",
        "pets.display_name as pet_name"
      ])
      .where("accounts.id", "=", friendAccountID)
      .executeTakeFirst();
    if (!friend) throw notFound("friendship");
    return {
      ...friendship,
      friend: {
        accountID: friend.account_id,
        displayName: friend.account_name,
        petID: friend.pet_id,
        petName: friend.pet_name
      }
    };
  }

  private async requireAcceptedFriendship(context: AuthContext, friendshipID: string): Promise<FriendshipAccess> {
    const row = await this.database.selectFrom("friendships").selectAll()
      .where("id", "=", friendshipID)
      .where("status", "=", "accepted")
      .where((expression) => expression.or([
        expression("requester_account_id", "=", context.accountID),
        expression("addressee_account_id", "=", context.accountID)
      ]))
      .executeTakeFirst();
    if (!row) throw notFound("friendship");
    const friendAccountID = row.requester_account_id === context.accountID
      ? row.addressee_account_id
      : row.requester_account_id;
    const pets = await this.database.selectFrom("pets").select(["id", "owner_account_id"])
      .where("owner_account_id", "in", [context.accountID, friendAccountID])
      .execute();
    const ownPetID = pets.find((pet) => pet.owner_account_id === context.accountID)?.id;
    const friendPetID = pets.find((pet) => pet.owner_account_id === friendAccountID)?.id;
    if (ownPetID !== context.petID || !friendPetID) throw notFound("friendship");
    return { friendshipID: row.id, scopeID: row.scope_id, friendAccountID, friendPetID };
  }

  private sealLetterResponse(letter: Letter): Letter {
    return { ...letter, body: this.letterCipher.encrypt(letter.body) };
  }

  private openLetterResponse(letter: Letter): Letter {
    return { ...letter, body: this.letterCipher.decrypt(letter.body) };
  }

  private async requireVisit(trx: DBTransaction, scopeID: string, visitID: string, lock: boolean): Promise<Visit> {
    let query = trx.selectFrom("visits").selectAll().where("id", "=", visitID).where("couple_id", "=", scopeID);
    if (lock) query = query.forUpdate();
    const row = await query.executeTakeFirst();
    if (!row) throw notFound("visit");
    return visitFromRow(row);
  }

  private async appendEvent(
    trx: DBTransaction,
    scopeID: string,
    type: string,
    actorType: FriendshipEvent["actorType"],
    actorID: string | null,
    payload: Record<string, unknown>,
    timelineVisible: boolean
  ): Promise<FriendshipEvent> {
    // PostgreSQL sequences are allocated before commit. Holding one transaction
    // lock per friendship keeps sequence order aligned with commit visibility,
    // so an event can never appear behind a cursor that clients already saved.
    // The two-int advisory-lock namespace does not overlap the one-bigint locks
    // used by command idempotency. 0x4D494E4F is the stable "MINO" namespace.
    await sql`select pg_advisory_xact_lock(1296649807, hashtext(${scopeID}))`.execute(trx);
    const row = await trx.insertInto("couple_events").values({
      id: randomUUID(),
      couple_id: scopeID,
      type,
      actor_type: actorType,
      actor_id: actorID,
      payload,
      timeline_visible: timelineVisible
    }).returningAll().executeTakeFirstOrThrow();
    return eventFromRow(row);
  }

  private async idempotent<T>(
    scopeID: string,
    scope: string,
    key: string,
    request: unknown,
    work: (trx: DBTransaction) => Promise<MutationResult<T>>,
    codec?: IdempotencyCodec<T>
  ): Promise<MutationResult<T>> {
    const fingerprint = this.fingerprintRequest(request);
    const legacyFingerprint = requestFingerprint(request);
    const replay = (record: { response: unknown; request_fingerprint: string }): MutationResult<T> => {
      if (record.request_fingerprint !== fingerprint && record.request_fingerprint !== legacyFingerprint) {
        throw conflict("idempotency_key_reused", "The idempotency key was already used with a different request");
      }
      return {
        data: codec ? codec.decode(record.response) : record.response as T,
        events: [],
        replayed: true
      };
    };
    const prior = await this.database.selectFrom("idempotency_records").select(["response", "request_fingerprint"])
      .where("couple_id", "=", scopeID).where("scope", "=", scope).where("idempotency_key", "=", key)
      .executeTakeFirst();
    if (prior) return replay(prior);

    try {
      return await this.database.transaction().execute(async (trx) => {
        await sql`select pg_advisory_xact_lock(hashtext(${`${scopeID}:${scope}:${key}`}))`.execute(trx);
        const inside = await trx.selectFrom("idempotency_records").select(["response", "request_fingerprint"])
          .where("couple_id", "=", scopeID).where("scope", "=", scope).where("idempotency_key", "=", key)
          .executeTakeFirst();
        if (inside) return replay(inside);
        const result = await work(trx);
        await trx.insertInto("idempotency_records").values({
          couple_id: scopeID,
          scope,
          idempotency_key: key,
          request_fingerprint: fingerprint,
          response: codec ? codec.encode(result.data) : result.data
        }).execute();
        return result;
      });
    } catch (error) {
      if (!isUniqueViolation(error)) throw error;
      const raced = await this.database.selectFrom("idempotency_records").select(["response", "request_fingerprint"])
        .where("couple_id", "=", scopeID).where("scope", "=", scope).where("idempotency_key", "=", key)
        .executeTakeFirst();
      if (raced) return replay(raced);
      throw error;
    }
  }
}
