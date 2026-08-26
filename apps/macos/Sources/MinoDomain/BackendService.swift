import Foundation

public enum PetInteractionKind: String, Codable, CaseIterable, Sendable {
    case kiss
    case flowerGift = "flower_gift"
    case walk
}

public struct PetProfileID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct BackendHealth: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable {
        case healthy, degraded, offline
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

/// Minimal durable source used by the account synchronization loop.
public protocol AccountEventSource: Sendable {
    func fetchSyncBootstrap() async throws -> SyncBootstrap
    func fetchAccountEvents(
        after cursor: Int64,
        limit: Int,
        timelineVisible: Bool?
    ) async throws -> AccountEventPage
}

/// The single account-scoped network boundary used by the macOS app.
public protocol AccountBackendService: AccountEventSource {
    func checkHealth() async throws -> BackendHealth
    func startGitHubDeviceAuthorization() async throws -> GitHubDeviceAuthorization
    func completeGitHubDeviceAuthorization(
        deviceCode: String,
        device: DeviceMetadata
    ) async throws -> GitHubDeviceCompletion
    func refreshSession(_ refreshToken: String) async throws -> AccountSession
    func logout() async throws
    func bootstrapDevelopmentProfile(_ profile: String) async throws -> DevBootstrapProfile
    func fetchCurrentProfile() async throws -> CurrentProfile
    func updateCurrentProfile(accountName: String, petName: String) async throws -> CurrentProfile
    func updateOwnPetAppearance(
        _ command: PetAppearanceSelectionCommand
    ) async throws -> PublicPetSnapshot
    func fetchOwnPetCare() async throws -> PetCareState
    func interactWithPet(
        petID: PetProfileID,
        command: PetInteractionCommand
    ) async throws -> PetInteractionReceipt

    func fetchFriends() async throws -> [FriendProfile]
    func fetchFriendRequests(status: FriendRequestStatus?) async throws -> [FriendRequest]
    func createFriendRequest(_ command: CreateFriendRequestCommand) async throws -> FriendRequest
    func respondToFriendRequest(
        friendshipID: FriendshipID,
        command: RespondFriendRequestCommand
    ) async throws -> FriendRequest
    func closeFriendship(_ friendshipID: FriendshipID, idempotencyKey: UUID) async throws

    func fetchVisits(status: VisitStatus?) async throws -> [Visit]
    func createVisit(_ command: CreateVisitCommand) async throws -> Visit
    func respondToVisit(
        visitID: PetVisitID,
        command: RespondToVisitCommand
    ) async throws -> Visit
    func endVisit(visitID: PetVisitID, command: EndVisitCommand) async throws -> Visit
    func createVisitAction(
        visitID: PetVisitID,
        command: CreateVisitActionCommand
    ) async throws -> VisitAction

    func createConversation(_ command: CreateConversationCommand) async throws -> ConversationTurnReceipt
    func fetchConversations() async throws -> [PetConversation]
    func fetchConversationMessages(
        conversationID: ConversationID
    ) async throws -> [PetConversationMessage]
    func sendConversationMessage(
        conversationID: ConversationID,
        command: SendConversationMessageCommand
    ) async throws -> ConversationTurnReceipt
    func endConversation(
        conversationID: ConversationID,
        command: EndConversationCommand
    ) async throws -> PetConversation

    func createLetter(
        visitID: PetVisitID,
        command: CreateLetterCommand
    ) async throws -> PetLetter
    func fetchLetter(_ letterID: LetterID) async throws -> PetLetter
    func claimPrimaryAgentDevice(_ deviceID: DeviceID, idempotencyKey: UUID) async throws
}

/// WebSocket carries only account-level hints. Durable events always come from REST.
public protocol AccountEventSignalService: Sendable {
    func signals() async throws -> AsyncThrowingStream<AccountRealtimeSignal, Error>
}
