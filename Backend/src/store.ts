import type {
  AuthContext,
  Conversation,
  ConversationMessage,
  DevProfile,
  EventPage,
  FriendshipSummary,
  FriendshipStatus,
  Letter,
  MutationResult,
  PetDecisionResponse,
  PresenceSnapshot,
  Visit
} from "./domain.js";

export interface ConversationMutation {
  conversation: Conversation;
  message: ConversationMessage;
}

export interface InteractionReceipt {
  interactionID: string;
  visitID: string | null;
  kind: string;
  acceptedAt: string;
}

export interface VisitReactionReceipt {
  reactionID: string;
  visitID: string;
  reaction: string;
  acceptedAt: string;
}

export interface EndVisitReceipt {
  visit: Visit;
  deliveredLetters: Letter[];
}

export type ModelUsageClaim =
  | { state: "claimed" }
  | { state: "in_progress" }
  | { state: "outcome_unknown" }
  | { state: "failed"; failure: ModelInferenceFailure }
  | { state: "replay"; response: PetDecisionResponse };

export interface ModelInferenceFailure {
  statusCode: number;
  code: string;
  message: string;
}

export interface MinoStore {
  close(): Promise<void>;
  fingerprintRequest(value: unknown): string;
  bootstrapDevProfiles(): Promise<{ alice: DevProfile; bob: DevProfile; charlie: DevProfile }>;
  authenticate(token: string): Promise<AuthContext | null>;

  listFriendships(context: AuthContext, status?: FriendshipStatus): Promise<FriendshipSummary[]>;
  requestFriendship(
    context: AuthContext,
    input: { addresseeAccountID: string; idempotencyKey: string }
  ): Promise<FriendshipSummary>;
  respondFriendship(
    context: AuthContext,
    friendshipID: string,
    input: { response: "accept" | "reject"; idempotencyKey: string }
  ): Promise<FriendshipSummary>;

  getEvents(
    context: AuthContext,
    friendshipID: string,
    after: string | undefined,
    limit: number,
    timelineOnly?: boolean
  ): Promise<EventPage>;
  getPresence(context: AuthContext, friendshipID: string): Promise<PresenceSnapshot>;
  resolveSingleAcceptedFriendship(context: AuthContext): Promise<string>;

  recordLegacyInteraction(
    context: AuthContext,
    friendshipID: string,
    input: { senderPetID: string; recipientPetID: string; kind: string; idempotencyKey: string }
  ): Promise<MutationResult<InteractionReceipt>>;

  createConversation(
    context: AuthContext,
    friendshipID: string,
    input: { recipientPetID: string; openingMessage: string; idempotencyKey: string }
  ): Promise<MutationResult<ConversationMutation>>;

  listConversations(context: AuthContext, friendshipID: string, status: "active"): Promise<Conversation[]>;

  getConversationMessages(context: AuthContext, friendshipID: string, conversationID: string): Promise<ConversationMessage[]>;

  addConversationMessage(
    context: AuthContext,
    friendshipID: string,
    conversationID: string,
    input: { actorType: "human" | "pet"; text: string; idempotencyKey: string }
  ): Promise<MutationResult<ConversationMutation>>;

  endConversation(
    context: AuthContext,
    friendshipID: string,
    conversationID: string,
    input: { summary: string; idempotencyKey: string }
  ): Promise<MutationResult<Conversation>>;

  createVisitInvitation(
    context: AuthContext,
    friendshipID: string,
    input: { visitorPetID: string; hostAccountID: string; reason?: string; idempotencyKey: string }
  ): Promise<MutationResult<Visit>>;

  listVisitInvitations(context: AuthContext, friendshipID: string, status?: string): Promise<Visit[]>;

  respondVisitInvitation(
    context: AuthContext,
    friendshipID: string,
    visitID: string,
    input: { response: "accept" | "decline"; idempotencyKey: string }
  ): Promise<MutationResult<Visit>>;

  addVisitInteraction(
    context: AuthContext,
    friendshipID: string,
    visitID: string,
    input: { kind: "feed" | "play" | "message"; text?: string; idempotencyKey: string }
  ): Promise<MutationResult<InteractionReceipt>>;

  addVisitReaction(
    context: AuthContext,
    friendshipID: string,
    visitID: string,
    input: { reaction: string; text?: string; idempotencyKey: string }
  ): Promise<MutationResult<VisitReactionReceipt>>;

  createVisitLetter(
    context: AuthContext,
    friendshipID: string,
    visitID: string,
    input: { body: string; idempotencyKey: string }
  ): Promise<MutationResult<Letter>>;

  getLetter(context: AuthContext, friendshipID: string, letterID: string): Promise<Letter>;

  endVisit(
    context: AuthContext,
    friendshipID: string,
    visitID: string,
    input: { idempotencyKey: string }
  ): Promise<MutationResult<EndVisitReceipt>>;

  claimModelInference(
    context: AuthContext,
    inferenceID: string,
    provider: string,
    model: string,
    requestFingerprint: string,
    staleAfterMilliseconds?: number
  ): Promise<ModelUsageClaim>;

  completeModelInference(
    context: AuthContext,
    inferenceID: string,
    status: "completed" | "failed",
    inputTokens: number,
    outputTokens: number,
    response?: PetDecisionResponse,
    failure?: ModelInferenceFailure
  ): Promise<void>;
}
