import Foundation

public enum PetInteractionKind: String, Codable, CaseIterable, Sendable {
    case kiss
    case flowerGift = "flower_gift"
    case walk
}

public struct PetProfileID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct InteractionCommand: Codable, Equatable, Sendable {
    public let idempotencyKey: UUID
    public let kind: PetInteractionKind
    public let senderPetID: PetProfileID
    public let recipientPetID: PetProfileID
    public let clientCreatedAt: Date

    public init(
        idempotencyKey: UUID = UUID(),
        kind: PetInteractionKind,
        senderPetID: PetProfileID,
        recipientPetID: PetProfileID,
        clientCreatedAt: Date = Date()
    ) {
        self.idempotencyKey = idempotencyKey
        self.kind = kind
        self.senderPetID = senderPetID
        self.recipientPetID = recipientPetID
        self.clientCreatedAt = clientCreatedAt
    }
}

public struct InteractionReceipt: Codable, Equatable, Sendable {
    public let interactionID: String
    public let acceptedAt: Date

    public init(interactionID: String, acceptedAt: Date) {
        self.interactionID = interactionID
        self.acceptedAt = acceptedAt
    }
}

public struct BackendHealth: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable {
        case healthy
        case degraded
        case offline
    }

    public let status: Status
    public let apiVersion: String

    public init(status: Status, apiVersion: String) {
        self.status = status
        self.apiVersion = apiVersion
    }
}

public enum BackendServiceError: Error, Equatable, Sendable {
    case offline
}

public protocol BackendService: Sendable {
    func checkHealth() async throws -> BackendHealth
    func sendInteraction(_ command: InteractionCommand) async throws -> InteractionReceipt
    func fetchPetPresence() async throws -> PetPresenceSnapshot
    func startPetVisit(_ command: StartPetVisitCommand) async throws -> PetVisitReceipt
    func returnPetVisit(_ command: ReturnPetVisitCommand) async throws -> PetVisitReceipt
    func sendPetVisitInvitation(
        _ command: SendPetVisitInvitationCommand
    ) async throws -> PetVisitInvitation
    func fetchPendingPetVisitInvitations() async throws -> [PetVisitInvitation]
    func respondToPetVisitInvitation(
        _ command: RespondToPetVisitInvitationCommand
    ) async throws -> PetVisitInvitationReceipt
    func fetchPersonalTimeline(after cursor: String?) async throws -> PersonalTimelinePage
}

public extension BackendService {
    @available(*, deprecated, renamed: "fetchPersonalTimeline(after:)")
    func fetchCoupleTimeline(after cursor: String?) async throws -> PersonalTimelinePage {
        try await fetchPersonalTimeline(after: cursor)
    }
}

@available(*, deprecated, renamed: "PetInteractionKind")
public typealias CoupleInteractionKind = PetInteractionKind

/// Network capabilities used by the two-client social MVP.
///
/// Kept separate from `BackendService` so the existing offline demo and its
/// lightweight test doubles remain source-compatible while the MVP rolls out.
public protocol MVPBackendService: BackendService {
    func bootstrapDevelopmentProfile(_ profile: String) async throws -> DevBootstrapProfile

    func fetchFriends() async throws -> [FriendProfile]
    func fetchFriendRequests(status: FriendRequestStatus?) async throws -> [FriendRequest]
    func createFriendRequest(_ command: CreateFriendRequestCommand) async throws -> FriendRequest
    func respondToFriendRequest(
        requestID: FriendRequestID,
        command: RespondFriendRequestCommand
    ) async throws -> FriendRequest

    func fetchEvents(
        friendshipID: FriendshipID,
        after eventID: String?
    ) async throws -> FriendshipEventPage
    func fetchTimelineEvents(
        friendshipID: FriendshipID,
        after eventID: String?
    ) async throws -> FriendshipEventPage

    func createConversation(
        friendshipID: FriendshipID,
        _ command: CreateConversationCommand
    ) async throws -> ConversationTurnReceipt
    func fetchConversations(
        friendshipID: FriendshipID,
        status: ConversationStatus?
    ) async throws -> [PetConversation]
    func fetchConversationMessages(
        friendshipID: FriendshipID,
        conversationID: ConversationID
    ) async throws -> [PetConversationMessage]
    func sendConversationMessage(
        friendshipID: FriendshipID,
        conversationID: ConversationID,
        command: SendConversationMessageCommand
    ) async throws -> ConversationTurnReceipt
    func endConversation(
        friendshipID: FriendshipID,
        conversationID: ConversationID,
        command: EndConversationCommand
    ) async throws -> PetConversation

    func createVisitInvitation(
        friendshipID: FriendshipID,
        _ command: CreateVisitInvitationCommand
    ) async throws -> MVPVisit
    func fetchVisitInvitations(
        friendshipID: FriendshipID,
        status: MVPVisitStatus?
    ) async throws -> [MVPVisit]
    func respondToVisitInvitation(
        friendshipID: FriendshipID,
        visitID: PetVisitID,
        command: RespondToVisitInvitationCommand
    ) async throws -> MVPVisit
    func sendVisitInteraction(
        friendshipID: FriendshipID,
        visitID: PetVisitID,
        command: CreateVisitInteractionCommand
    ) async throws -> VisitInteractionReceipt
    func sendVisitReaction(
        friendshipID: FriendshipID,
        visitID: PetVisitID,
        command: CreateVisitReactionCommand
    ) async throws -> VisitReactionReceipt
    func createLetter(
        friendshipID: FriendshipID,
        visitID: PetVisitID,
        command: CreateLetterCommand
    ) async throws -> PetLetter
    func fetchLetter(
        friendshipID: FriendshipID,
        _ letterID: LetterID
    ) async throws -> PetLetter
    func endVisit(
        friendshipID: FriendshipID,
        visitID: PetVisitID,
        command: EndVisitCommand
    ) async throws -> EndVisitReceipt
}

/// Realtime delivery is deliberately independent from REST lifecycle. Consumers
/// always retain `/events?after=` as the recovery source of truth.
public protocol FriendshipEventRealtimeService: Sendable {
    func events(
        friendshipID: FriendshipID,
        after eventID: String?
    ) async throws -> AsyncThrowingStream<FriendshipEvent, Error>
}

@available(*, deprecated, renamed: "FriendshipEventRealtimeService")
public typealias CoupleEventRealtimeService = FriendshipEventRealtimeService
