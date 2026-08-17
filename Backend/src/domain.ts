export type ActorType = "human" | "pet" | "system";
export type ConversationStatus = "active" | "ended";
export type VisitStatus = "pending" | "active" | "ended" | "cancelled";
export type FriendshipStatus = "pending" | "accepted" | "rejected";

export interface AuthContext {
  accountID: string;
  petID: string;
}

export interface DevProfile extends AuthContext {
  profile: "alice" | "bob" | "charlie";
  token: string;
  accountName: string;
  petName: string;
  friends: Array<{
    friendshipID: string;
    accountID: string;
    petID: string;
    accountName: string;
    petName: string;
  }>;
}

export interface Friendship {
  id: string;
  requesterAccountID: string;
  addresseeAccountID: string;
  status: FriendshipStatus;
  createdAt: string;
  respondedAt: string | null;
}

export interface FriendshipSummary extends Friendship {
  friend: {
    accountID: string;
    displayName: string;
    petID: string;
    petName: string;
  };
}

export interface FriendshipEvent {
  id: string;
  sequence: number;
  friendshipID: string;
  type: string;
  actorType: ActorType;
  actorID: string | null;
  payload: Record<string, unknown>;
  timelineVisible: boolean;
  occurredAt: string;
}

export interface Conversation {
  id: string;
  friendshipID: string;
  initiatorPetID: string;
  recipientPetID: string;
  status: ConversationStatus;
  nextSpeakerPetID: string | null;
  turnCount: number;
  createdAt: string;
  endedAt: string | null;
}

export interface ConversationMessage {
  id: string;
  conversationID: string;
  friendshipID: string;
  actorType: "human" | "pet";
  actorID: string;
  recipientPetID: string;
  text: string;
  turnIndex: number | null;
  createdAt: string;
}

export interface Visit {
  id: string;
  friendshipID: string;
  visitorPetID: string;
  visitorOwnerAccountID: string;
  hostAccountID: string;
  requestedByAccountID: string;
  reason: string | null;
  status: VisitStatus;
  createdAt: string;
  startedAt: string | null;
  endedAt: string | null;
}

export interface Letter {
  id: string;
  friendshipID: string;
  visitID: string;
  authorAccountID: string;
  recipientAccountID: string;
  body: string;
  status: "carried" | "delivered";
  createdAt: string;
  deliveredAt: string | null;
}

export interface PresenceSnapshot {
  friendshipID: string;
  pets: Array<{
    petID: string;
    ownerAccountID: string;
    phase: "at_home" | "visiting";
    currentHostAccountID: string | null;
    activeVisitID: string | null;
    revision: number;
    updatedAt: string;
  }>;
  activeVisits: Visit[];
  serverCursor: string | null;
  syncedAt: string;
}

export interface MutationResult<T> {
  data: T;
  events: FriendshipEvent[];
  replayed: boolean;
}

export interface EventPage {
  events: FriendshipEvent[];
  nextCursor: string | null;
}

export interface PetDecisionRequest {
  inferenceID: string;
  petID: string;
  trigger: {
    type: string;
    summary: string;
  };
  state: {
    location?: "home" | "visiting";
    visitID?: string;
    emotion?: "content" | "happy" | "shy";
    autonomousSocialEnabled?: boolean;
    ownerAccountID?: string;
    friendshipID?: string;
    friendPetIDs?: string[];
    targetPetID?: string;
    invitationID?: string;
    senderPetID?: string;
    currentEventVisitID?: string;
  };
  memories: Array<{
    summary: string;
    kind?: string;
  }>;
  availableActions: string[];
}

export type PetDecision =
  | { kind: "idle" }
  | { kind: "speak_to_owner"; text: string }
  | { kind: "send_pet_message"; recipientPetID: string; text: string }
  | { kind: "propose_visit"; recipientPetID: string; reason: string }
  | { kind: "respond_to_visit"; invitationID: string; response: "accept" | "decline"; reply?: string | undefined }
  | { kind: "react_to_interaction"; reaction: "happy" | "excited" | "shy" | "sleepy"; text?: string | undefined }
  | { kind: "request_return"; visitID: string };

export type MemoryDisposition =
  | { kind: "discard" }
  | { kind: "session" }
  | { kind: "long_term"; summary: string; reason: string };

export interface PetDecisionResponse {
  inferenceID: string;
  decision: PetDecision;
  memoryDisposition: MemoryDisposition;
  replayed: boolean;
  usage: {
    inputTokens: number;
    outputTokens: number;
  };
}
