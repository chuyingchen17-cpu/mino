import { randomUUID } from "node:crypto";
import { conflict, notFound } from "./errors.js";
import { devProfiles } from "./dev-fixtures.js";
import { requestFingerprint } from "./security/request-fingerprint.js";
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
} from "./domain.js";
import type {
  ConversationMutation,
  EndVisitReceipt,
  InteractionReceipt,
  MinoStore,
  ModelInferenceFailure,
  ModelUsageClaim,
  VisitReactionReceipt
} from "./store.js";

interface IdempotencyRecord {
  data: unknown;
  fingerprint: string;
}

interface ModelInferenceRecord {
  status: "started" | "completed" | "failed";
  claimedAt: number;
  requestFingerprint: string;
  response?: PetDecisionResponse;
  failure?: ModelInferenceFailure;
}

export class InMemoryMinoStore implements MinoStore {
  private readonly profiles = devProfiles();
  private bootstrapped = false;
  private readonly friendships = new Map<string, Friendship>();
  private readonly conversations = new Map<string, Conversation>();
  private readonly messages = new Map<string, ConversationMessage[]>();
  private readonly visits = new Map<string, Visit>();
  private readonly letters = new Map<string, Letter>();
  private readonly events: FriendshipEvent[] = [];
  private readonly idempotency = new Map<string, IdempotencyRecord>();
  private readonly modelInferences = new Map<string, ModelInferenceRecord>();

  async close(): Promise<void> {}

  fingerprintRequest(value: unknown): string {
    return requestFingerprint(value);
  }

  async bootstrapDevProfiles(): Promise<{ alice: DevProfile; bob: DevProfile; charlie: DevProfile }> {
    this.bootstrapped = true;
    if (!this.friendships.has(this.profiles.alice.friends[0]!.friendshipID)) {
      this.friendships.set(this.profiles.alice.friends[0]!.friendshipID, {
        id: this.profiles.alice.friends[0]!.friendshipID,
        requesterAccountID: this.profiles.alice.accountID,
        addresseeAccountID: this.profiles.bob.accountID,
        status: "accepted",
        createdAt: new Date(0).toISOString(),
        respondedAt: new Date(0).toISOString()
      });
    }
    return this.profiles;
  }

  async authenticate(token: string): Promise<AuthContext | null> {
    if (!this.bootstrapped) return null;
    const profile = [this.profiles.alice, this.profiles.bob, this.profiles.charlie]
      .find((candidate) => candidate.token === token);
    if (!profile) return null;
    return {
      accountID: profile.accountID,
      petID: profile.petID
    };
  }

  async listFriendships(context: AuthContext, status?: FriendshipStatus): Promise<FriendshipSummary[]> {
    return [...this.friendships.values()]
      .filter((friendship) =>
        this.isFriendshipMember(context, friendship) && (!status || friendship.status === status)
      )
      .map((friendship) => this.friendshipSummary(context, friendship))
      .sort((left, right) => right.createdAt.localeCompare(left.createdAt));
  }

  async requestFriendship(
    context: AuthContext,
    input: { addresseeAccountID: string; idempotencyKey: string }
  ): Promise<FriendshipSummary> {
    const identity = `${context.accountID}:friendship-request:${input.idempotencyKey}`;
    const fingerprint = requestFingerprint(input);
    const prior = this.idempotency.get(identity);
    if (prior) {
      if (prior.fingerprint !== fingerprint) {
        throw conflict("idempotency_key_reused", "The idempotency key was already used with a different request");
      }
      return prior.data as FriendshipSummary;
    }
    if (input.addresseeAccountID === context.accountID) {
      throw conflict("cannot_friend_self", "An account cannot send a friendship request to itself");
    }
    this.requireProfileForAccount(input.addresseeAccountID);
    const existing = [...this.friendships.values()].find((friendship) =>
      this.sameAccountPair(friendship, context.accountID, input.addresseeAccountID) &&
      friendship.status !== "rejected"
    );
    if (existing) throw conflict("friendship_exists", "A pending or accepted friendship already exists");
    const friendship: Friendship = {
      id: randomUUID(),
      requesterAccountID: context.accountID,
      addresseeAccountID: input.addresseeAccountID,
      status: "pending",
      createdAt: new Date().toISOString(),
      respondedAt: null
    };
    this.friendships.set(friendship.id, friendship);
    const summary = this.friendshipSummary(context, friendship);
    this.idempotency.set(identity, { data: summary, fingerprint });
    return summary;
  }

  async respondFriendship(
    context: AuthContext,
    friendshipID: string,
    input: { response: "accept" | "reject"; idempotencyKey: string }
  ): Promise<FriendshipSummary> {
    const identity = `${context.accountID}:friendship-response:${friendshipID}:${input.idempotencyKey}`;
    const fingerprint = requestFingerprint({ friendshipID, ...input });
    const prior = this.idempotency.get(identity);
    if (prior) {
      if (prior.fingerprint !== fingerprint) {
        throw conflict("idempotency_key_reused", "The idempotency key was already used with a different request");
      }
      return prior.data as FriendshipSummary;
    }
    const friendship = this.friendships.get(friendshipID);
    if (!friendship || friendship.addresseeAccountID !== context.accountID) throw notFound("friendship");
    if (friendship.status !== "pending") {
      throw conflict("friendship_resolved", "The friendship request has already been resolved");
    }
    const next: Friendship = {
      ...friendship,
      status: input.response === "accept" ? "accepted" : "rejected",
      respondedAt: new Date().toISOString()
    };
    this.friendships.set(friendshipID, next);
    const summary = this.friendshipSummary(context, next);
    this.idempotency.set(identity, { data: summary, fingerprint });
    return summary;
  }

  async resolveSingleAcceptedFriendship(context: AuthContext): Promise<string> {
    const accepted = [...this.friendships.values()].filter((friendship) =>
      friendship.status === "accepted" && this.isFriendshipMember(context, friendship)
    );
    if (accepted.length !== 1) {
      throw conflict("friendship_context_required", "Specify a friendship because the account does not have exactly one accepted friend");
    }
    return accepted[0]!.id;
  }

  async getEvents(
    context: AuthContext,
    friendshipID: string,
    after: string | undefined,
    limit: number,
    timelineOnly = false
  ): Promise<EventPage> {
    this.requireAcceptedFriendship(context, friendshipID);
    let afterSequence = 0;
    if (after) {
      const cursor = this.events.find((event) => event.friendshipID === friendshipID && event.id === after);
      if (!cursor) throw notFound("event cursor");
      afterSequence = cursor.sequence;
    }
    const events = this.events
      .filter((event) => event.friendshipID === friendshipID && event.sequence > afterSequence && (!timelineOnly || event.timelineVisible))
      .slice(0, limit);
    return { events, nextCursor: events.at(-1)?.id ?? after ?? null };
  }

  async getPresence(context: AuthContext, friendshipID: string): Promise<PresenceSnapshot> {
    const friendship = this.requireAcceptedFriendship(context, friendshipID);
    const now = new Date().toISOString();
    const friendAccountID = this.otherAccountID(context, friendship);
    const friendProfile = this.requireProfileForAccount(friendAccountID);
    const petOwners = [
      [context.petID, context.accountID],
      [friendProfile.petID, friendAccountID]
    ] as const;
    const petIDs = new Set(petOwners.map(([petID]) => petID));
    const globalActiveVisits = [...this.visits.values()].filter((visit) =>
      visit.status === "active" && petIDs.has(visit.visitorPetID)
    );
    const friendshipActiveVisits = globalActiveVisits.filter((visit) => visit.friendshipID === friendshipID);
    const pets = petOwners.map(([petID, ownerAccountID]) => {
      const activeVisit = globalActiveVisits.find((visit) => visit.visitorPetID === petID);
      const isVisibleVisit = activeVisit?.friendshipID === friendshipID;
      return {
        petID,
        ownerAccountID,
        phase: activeVisit ? "visiting" as const : "at_home" as const,
        currentHostAccountID: activeVisit ? (isVisibleVisit ? activeVisit.hostAccountID : null) : ownerAccountID,
        activeVisitID: isVisibleVisit ? activeVisit.id : null,
        revision: this.events.filter((event) => event.friendshipID === friendshipID).length,
        updatedAt: now
      };
    });
    return {
      friendshipID,
      pets,
      activeVisits: friendshipActiveVisits,
      serverCursor: this.events.filter((event) => event.friendshipID === friendshipID).at(-1)?.id ?? null,
      syncedAt: now
    };
  }

  async recordLegacyInteraction(
    context: AuthContext,
    friendshipID: string,
    input: { senderPetID: string; recipientPetID: string; kind: string; idempotencyKey: string }
  ): Promise<MutationResult<InteractionReceipt>> {
    const friend = this.friendProfile(context, friendshipID);
    if (input.senderPetID !== context.petID || input.recipientPetID !== friend.petID) {
      throw notFound("pet");
    }
    return this.once(friendshipID, "legacy-interaction", input.idempotencyKey, input, () => {
      const acceptedAt = new Date().toISOString();
      const data = { interactionID: randomUUID(), visitID: null, kind: input.kind, acceptedAt };
      const event = this.appendEvent(friendshipID, "interaction", "pet", context.petID, {
        interactionID: data.interactionID,
        kind: input.kind,
        senderPetID: context.petID,
        recipientPetID: friend.petID
      }, true);
      return { data, events: [event], replayed: false };
    });
  }

  async createConversation(
    context: AuthContext,
    friendshipID: string,
    input: { recipientPetID: string; openingMessage: string; idempotencyKey: string }
  ): Promise<MutationResult<ConversationMutation>> {
    const friend = this.friendProfile(context, friendshipID);
    if (input.recipientPetID !== friend.petID) throw notFound("recipient pet");
    return this.once(friendshipID, "create-conversation", input.idempotencyKey, input, () => {
      const activeExists = [...this.conversations.values()].some((conversation) =>
        conversation.friendshipID === friendshipID && conversation.status === "active"
      );
      if (activeExists) {
        throw conflict("active_conversation_exists", "This friendship already has an active conversation");
      }
      const now = new Date().toISOString();
      const conversation: Conversation = {
        id: randomUUID(), friendshipID, initiatorPetID: context.petID,
        recipientPetID: friend.petID, status: "active", nextSpeakerPetID: friend.petID,
        turnCount: 1, createdAt: now, endedAt: null
      };
      const message: ConversationMessage = {
        id: randomUUID(), conversationID: conversation.id, friendshipID,
        actorType: "pet", actorID: context.petID, recipientPetID: friend.petID,
        text: input.openingMessage, turnIndex: 0, createdAt: now
      };
      this.conversations.set(conversation.id, conversation);
      this.messages.set(conversation.id, [message]);
      const event = this.appendEvent(friendshipID, "conversation_message", "pet", context.petID, {
        conversationID: conversation.id, messageID: message.id, recipientPetID: friend.petID,
        text: message.text, turnIndex: 0
      }, false);
      return { data: { conversation, message }, events: [event], replayed: false };
    });
  }

  async listConversations(context: AuthContext, friendshipID: string, status: "active"): Promise<Conversation[]> {
    this.requireAcceptedFriendship(context, friendshipID);
    return [...this.conversations.values()]
      .filter((conversation) =>
        conversation.friendshipID === friendshipID &&
        conversation.status === status &&
        [conversation.initiatorPetID, conversation.recipientPetID].includes(context.petID)
      )
      .sort((left, right) => right.createdAt.localeCompare(left.createdAt));
  }

  async getConversationMessages(context: AuthContext, friendshipID: string, conversationID: string): Promise<ConversationMessage[]> {
    this.requireConversation(context, friendshipID, conversationID);
    return [...(this.messages.get(conversationID) ?? [])];
  }

  async addConversationMessage(
    context: AuthContext,
    friendshipID: string,
    conversationID: string,
    input: { actorType: "human" | "pet"; text: string; idempotencyKey: string }
  ): Promise<MutationResult<ConversationMutation>> {
    return this.once(friendshipID, "conversation-message", input.idempotencyKey, { conversationID, ...input }, () => {
      const conversation = this.requireConversation(context, friendshipID, conversationID);
      if (conversation.status !== "active") throw conflict("conversation_ended", "The conversation has already ended");
      if (input.actorType === "pet" && conversation.nextSpeakerPetID !== context.petID) {
        throw conflict("not_your_turn", "The other pet has the next turn");
      }
      if (input.actorType === "pet" && conversation.turnCount >= 6) {
        throw conflict("turn_limit_reached", "The conversation has reached six pet turns");
      }

      const now = new Date().toISOString();
      const recipientPetID = context.petID === conversation.initiatorPetID ? conversation.recipientPetID : conversation.initiatorPetID;
      const turnIndex = input.actorType === "pet" ? conversation.turnCount : null;
      const actorID = input.actorType === "pet" ? context.petID : context.accountID;
      const message: ConversationMessage = {
        id: randomUUID(), conversationID, friendshipID, actorType: input.actorType,
        actorID, recipientPetID, text: input.text, turnIndex, createdAt: now
      };
      const nextTurnCount = input.actorType === "pet" ? conversation.turnCount + 1 : conversation.turnCount;
      const nextConversation: Conversation = {
        ...conversation,
        turnCount: nextTurnCount,
        nextSpeakerPetID: nextTurnCount >= 6 ? null : input.actorType === "pet" ? recipientPetID : conversation.nextSpeakerPetID,
        status: nextTurnCount >= 6 ? "ended" : conversation.status,
        endedAt: nextTurnCount >= 6 ? now : conversation.endedAt
      };
      this.conversations.set(conversationID, nextConversation);
      this.messages.get(conversationID)?.push(message);
      const events = [this.appendEvent(friendshipID, "conversation_message", input.actorType, actorID, {
        conversationID, messageID: message.id, recipientPetID, text: input.text, turnIndex
      }, false)];
      return { data: { conversation: nextConversation, message }, events, replayed: false };
    });
  }

  async endConversation(
    context: AuthContext,
    friendshipID: string,
    conversationID: string,
    input: { summary: string; idempotencyKey: string }
  ): Promise<MutationResult<Conversation>> {
    return this.once(friendshipID, `end-conversation:${conversationID}`, input.idempotencyKey, { conversationID, ...input }, () => {
      const conversation = this.requireConversation(context, friendshipID, conversationID);
      if (conversation.initiatorPetID !== context.petID) throw notFound("conversation");
      const ended: Conversation = conversation.status === "ended" ? conversation : {
        ...conversation, status: "ended", nextSpeakerPetID: null, endedAt: new Date().toISOString()
      };
      this.conversations.set(conversationID, ended);
      const alreadySummarized = this.events.some((event) =>
        event.friendshipID === friendshipID &&
        event.type === "conversation_summary" &&
        event.payload.conversationID === conversationID
      );
      if (alreadySummarized) return { data: ended, events: [], replayed: false };
      const event = this.appendEvent(friendshipID, "conversation_summary", "pet", context.petID, {
        conversationID, summary: input.summary.trim()
      }, true);
      return { data: ended, events: [event], replayed: false };
    });
  }

  async createVisitInvitation(
    context: AuthContext,
    friendshipID: string,
    input: { visitorPetID: string; hostAccountID: string; reason?: string; idempotencyKey: string }
  ): Promise<MutationResult<Visit>> {
    const friend = this.friendProfile(context, friendshipID);
    const validDirection =
      (input.visitorPetID === context.petID && input.hostAccountID === friend.accountID) ||
      (input.visitorPetID === friend.petID && input.hostAccountID === context.accountID);
    if (!validDirection) throw notFound("visitor or host");
    return this.once(friendshipID, "create-visit-invitation", input.idempotencyKey, input, () => {
      const visitorOwnerAccountID = input.visitorPetID === context.petID ? context.accountID : friend.accountID;
      const visit: Visit = {
        id: randomUUID(), friendshipID, visitorPetID: input.visitorPetID,
        visitorOwnerAccountID, hostAccountID: input.hostAccountID, requestedByAccountID: context.accountID,
        reason: input.reason?.trim() || null, status: "pending", createdAt: new Date().toISOString(),
        startedAt: null, endedAt: null
      };
      this.visits.set(visit.id, visit);
      const responderAccountID = visit.requestedByAccountID === visit.visitorOwnerAccountID
        ? visit.hostAccountID
        : visit.visitorOwnerAccountID;
      const event = this.appendEvent(friendshipID, "visit_invited", "human", context.accountID, {
        visitID: visit.id, visitorPetID: visit.visitorPetID, hostAccountID: visit.hostAccountID,
        requestedByAccountID: visit.requestedByAccountID, responderAccountID, reason: visit.reason
      }, false);
      return { data: visit, events: [event], replayed: false };
    });
  }

  async listVisitInvitations(context: AuthContext, friendshipID: string, status = "pending"): Promise<Visit[]> {
    this.requireAcceptedFriendship(context, friendshipID);
    return [...this.visits.values()].filter((visit) => visit.friendshipID === friendshipID && visit.status === status);
  }

  async respondVisitInvitation(
    context: AuthContext,
    friendshipID: string,
    visitID: string,
    input: { response: "accept" | "decline"; idempotencyKey: string }
  ): Promise<MutationResult<Visit>> {
    return this.once(friendshipID, `respond-visit:${visitID}`, input.idempotencyKey, { visitID, ...input }, () => {
      const visit = this.requireVisit(context, friendshipID, visitID);
      const responderAccountID = visit.requestedByAccountID === visit.visitorOwnerAccountID
        ? visit.hostAccountID
        : visit.visitorOwnerAccountID;
      if (responderAccountID !== context.accountID) throw notFound("visit invitation");
      if (visit.status !== "pending") throw conflict("invitation_resolved", "The visit invitation has already been resolved");
      if (input.response === "accept") {
        const active = [...this.visits.values()].some((candidate) =>
          candidate.status === "active" &&
          (
            candidate.visitorPetID === visit.visitorPetID ||
            candidate.hostAccountID === visit.hostAccountID
          )
        );
        if (active) throw conflict("active_visit_exists", "The visitor or host already has an active visit");
      }
      const now = new Date().toISOString();
      const next: Visit = {
        ...visit,
        status: input.response === "accept" ? "active" : "cancelled",
        startedAt: input.response === "accept" ? now : null,
        endedAt: input.response === "decline" ? now : null
      };
      this.visits.set(visitID, next);
      const event = this.appendEvent(friendshipID, input.response === "accept" ? "visit_arrived" : "visit_declined", "pet", context.petID, {
        visitID, visitorPetID: visit.visitorPetID, hostAccountID: visit.hostAccountID,
        requestedByAccountID: visit.requestedByAccountID, responderAccountID
      }, input.response === "accept");
      return { data: next, events: [event], replayed: false };
    });
  }

  async addVisitInteraction(
    context: AuthContext,
    friendshipID: string,
    visitID: string,
    input: { kind: "feed" | "play" | "message"; text?: string; idempotencyKey: string }
  ): Promise<MutationResult<InteractionReceipt>> {
    return this.once(friendshipID, `visit-interaction:${visitID}`, input.idempotencyKey, { visitID, ...input }, () => {
      const visit = this.requireVisit(context, friendshipID, visitID);
      if (visit.status !== "active") throw conflict("visit_not_active", "Interactions require an active visit");
      if (visit.hostAccountID !== context.accountID) throw notFound("visit");
      const acceptedAt = new Date().toISOString();
      const data = { interactionID: randomUUID(), visitID, kind: input.kind, acceptedAt };
      const event = this.appendEvent(friendshipID, "visit_interaction", "human", context.accountID, {
        interactionID: data.interactionID, visitID, visitorPetID: visit.visitorPetID,
        kind: input.kind, ...(input.text ? { text: input.text } : {})
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
    return this.once(friendshipID, `visit-reaction:${visitID}`, input.idempotencyKey, { visitID, ...input }, () => {
      const visit = this.requireVisit(context, friendshipID, visitID);
      if (visit.status !== "active") throw conflict("visit_not_active", "Reactions require an active visit");
      if (visit.visitorOwnerAccountID !== context.accountID || visit.visitorPetID !== context.petID) throw notFound("visit");
      const data = {
        reactionID: randomUUID(), visitID, reaction: input.reaction, acceptedAt: new Date().toISOString()
      };
      const event = this.appendEvent(friendshipID, "visit_reaction", "pet", context.petID, {
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
    return this.once(friendshipID, "visit-letter", input.idempotencyKey, { visitID, ...input }, () => {
      const visit = this.requireVisit(context, friendshipID, visitID);
      if (visit.status !== "active") throw conflict("visit_not_active", "A letter can only be attached during an active visit");
      if (visit.hostAccountID !== context.accountID) throw notFound("visit");
      const letter: Letter = {
        id: randomUUID(), friendshipID, visitID,
        authorAccountID: context.accountID, recipientAccountID: visit.visitorOwnerAccountID,
        body: input.body, status: "carried", createdAt: new Date().toISOString(), deliveredAt: null
      };
      this.letters.set(letter.id, letter);
      const event = this.appendEvent(friendshipID, "letter_attached", "human", context.accountID, {
        letterID: letter.id, visitID, recipientAccountID: letter.recipientAccountID
      }, false);
      return { data: letter, events: [event], replayed: false };
    });
  }

  async getLetter(context: AuthContext, friendshipID: string, letterID: string): Promise<Letter> {
    this.requireAcceptedFriendship(context, friendshipID);
    const letter = this.letters.get(letterID);
    if (!letter || letter.friendshipID !== friendshipID) throw notFound("letter");
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
    return this.once(friendshipID, `end-visit:${visitID}`, input.idempotencyKey, { visitID, ...input }, () => {
      const visit = this.requireVisit(context, friendshipID, visitID);
      if (visit.status !== "active") throw conflict("visit_not_active", "The visit is not active");
      const now = new Date().toISOString();
      const ended: Visit = { ...visit, status: "ended", endedAt: now };
      this.visits.set(visitID, ended);
      const deliveredLetters = [...this.letters.values()]
        .filter((letter) => letter.visitID === visitID && letter.status === "carried")
        .map((letter) => ({ ...letter, status: "delivered" as const, deliveredAt: now }));
      for (const letter of deliveredLetters) this.letters.set(letter.id, letter);
      const events = [this.appendEvent(friendshipID, "visit_returned", "human", context.accountID, {
        visitID, visitorPetID: visit.visitorPetID
      }, true)];
      for (const letter of deliveredLetters) {
        events.push(this.appendEvent(friendshipID, "letter_received", "system", null, {
          letterID: letter.id, visitID, authorAccountID: letter.authorAccountID,
          recipientAccountID: letter.recipientAccountID
        }, true));
      }
      return { data: { visit: ended, deliveredLetters }, events, replayed: false };
    });
  }

  async claimModelInference(
    context: AuthContext,
    inferenceID: string,
    _provider: string,
    _model: string,
    fingerprint: string,
    staleAfterMilliseconds = 60_000
  ): Promise<ModelUsageClaim> {
    const key = `${context.accountID}:${inferenceID}`;
    const existing = this.modelInferences.get(key);
    if (existing && existing.requestFingerprint !== fingerprint) {
      throw conflict("inference_id_reused", "The inference ID was already used with a different request");
    }
    if (existing?.status === "completed" && existing.response) {
      return { state: "replay", response: { ...existing.response, replayed: true } };
    }
    if (existing?.status === "failed" && existing.failure) {
      return { state: "failed", failure: existing.failure };
    }
    if (
      existing?.status === "started" &&
      Date.now() - existing.claimedAt < staleAfterMilliseconds
    ) {
      return { state: "in_progress" };
    }
    if (existing?.status === "started") return { state: "outcome_unknown" };
    this.modelInferences.set(key, { status: "started", claimedAt: Date.now(), requestFingerprint: fingerprint });
    return { state: "claimed" };
  }

  async completeModelInference(
    context: AuthContext,
    inferenceID: string,
    status: "completed" | "failed",
    _inputTokens: number,
    _outputTokens: number,
    response?: PetDecisionResponse,
    failure?: ModelInferenceFailure
  ): Promise<void> {
    const key = `${context.accountID}:${inferenceID}`;
    const existing = this.modelInferences.get(key);
    if (!existing) throw new Error("Model inference was completed without a claim");
    this.modelInferences.set(key, {
      status,
      claimedAt: Date.now(),
      requestFingerprint: existing.requestFingerprint,
      ...(status === "completed" && response ? { response } : {}),
      ...(status === "failed" && failure ? { failure } : {})
    });
  }

  private requireConversation(context: AuthContext, friendshipID: string, id: string): Conversation {
    this.requireAcceptedFriendship(context, friendshipID);
    const conversation = this.conversations.get(id);
    if (!conversation || conversation.friendshipID !== friendshipID) throw notFound("conversation");
    if (![conversation.initiatorPetID, conversation.recipientPetID].includes(context.petID)) throw notFound("conversation");
    return conversation;
  }

  private requireVisit(context: AuthContext, friendshipID: string, id: string): Visit {
    this.requireAcceptedFriendship(context, friendshipID);
    const visit = this.visits.get(id);
    if (!visit || visit.friendshipID !== friendshipID) throw notFound("visit");
    return visit;
  }

  private requireAcceptedFriendship(context: AuthContext, friendshipID: string): Friendship {
    const friendship = this.friendships.get(friendshipID);
    if (!friendship || friendship.status !== "accepted" || !this.isFriendshipMember(context, friendship)) {
      throw notFound("friendship");
    }
    return friendship;
  }

  private isFriendshipMember(context: AuthContext, friendship: Friendship): boolean {
    return friendship.requesterAccountID === context.accountID || friendship.addresseeAccountID === context.accountID;
  }

  private sameAccountPair(friendship: Friendship, first: string, second: string): boolean {
    return (friendship.requesterAccountID === first && friendship.addresseeAccountID === second) ||
      (friendship.requesterAccountID === second && friendship.addresseeAccountID === first);
  }

  private otherAccountID(context: AuthContext, friendship: Friendship): string {
    if (friendship.requesterAccountID === context.accountID) return friendship.addresseeAccountID;
    if (friendship.addresseeAccountID === context.accountID) return friendship.requesterAccountID;
    throw notFound("friendship");
  }

  private requireProfileForAccount(accountID: string): DevProfile {
    const profile = [this.profiles.alice, this.profiles.bob, this.profiles.charlie]
      .find((candidate) => candidate.accountID === accountID);
    if (!profile) throw notFound("account");
    return profile;
  }

  private friendshipSummary(context: AuthContext, friendship: Friendship): FriendshipSummary {
    const friend = this.requireProfileForAccount(this.otherAccountID(context, friendship));
    return {
      ...friendship,
      friend: {
        accountID: friend.accountID,
        displayName: friend.accountName,
        petID: friend.petID,
        petName: friend.petName
      }
    };
  }

  private friendProfile(context: AuthContext, friendshipID: string): DevProfile {
    const friendship = this.requireAcceptedFriendship(context, friendshipID);
    return this.requireProfileForAccount(this.otherAccountID(context, friendship));
  }

  private appendEvent(
    friendshipID: string,
    type: string,
    actorType: FriendshipEvent["actorType"],
    actorID: string | null,
    payload: Record<string, unknown>,
    timelineVisible: boolean
  ): FriendshipEvent {
    const event: FriendshipEvent = {
      id: randomUUID(), sequence: this.events.length + 1, friendshipID,
      type, actorType, actorID, payload, timelineVisible, occurredAt: new Date().toISOString()
    };
    this.events.push(event);
    return event;
  }

  private async once<T>(
    friendshipID: string,
    scope: string,
    key: string,
    request: unknown,
    work: () => MutationResult<T>
  ): Promise<MutationResult<T>> {
    const identity = `${friendshipID}:${scope}:${key}`;
    const fingerprint = requestFingerprint(request);
    const prior = this.idempotency.get(identity);
    if (prior) {
      if (prior.fingerprint !== fingerprint) {
        throw conflict("idempotency_key_reused", "The idempotency key was already used with a different request");
      }
      return { data: prior.data as T, events: [], replayed: true };
    }
    const result = work();
    this.idempotency.set(identity, { data: result.data, fingerprint });
    return result;
  }
}
