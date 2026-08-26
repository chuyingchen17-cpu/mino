import Foundation

public enum VisitStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case active
    case closed
}

public enum VisitCloseReason: String, Codable, CaseIterable, Sendable {
    case declined
    case cancelled
    case expired
    case recalled
    case sentHome = "sent_home"
    case friendshipClosed = "friendship_closed"
}

/// The only server-authoritative visit aggregate. Desktop coordinates and
/// animation state deliberately stay in MinoRuntime.
public struct Visit: Codable, Equatable, Identifiable, Sendable {
    public let id: PetVisitID
    public let friendshipID: FriendshipID
    public let visitorPetID: PetProfileID
    public let visitorOwnerAccountID: AccountID
    public let hostAccountID: AccountID
    public let requestedByAccountID: AccountID
    public let responderAccountID: AccountID
    public let status: VisitStatus
    public let closeReason: VisitCloseReason?
    public let reason: String?
    public let version: Int64
    public let createdAt: Date
    public let expiresAt: Date
    public let startedAt: Date?
    public let closedAt: Date?

    public init(
        id: PetVisitID,
        friendshipID: FriendshipID,
        visitorPetID: PetProfileID,
        visitorOwnerAccountID: AccountID,
        hostAccountID: AccountID,
        requestedByAccountID: AccountID,
        responderAccountID: AccountID,
        status: VisitStatus,
        closeReason: VisitCloseReason? = nil,
        reason: String? = nil,
        version: Int64,
        createdAt: Date,
        expiresAt: Date,
        startedAt: Date? = nil,
        closedAt: Date? = nil
    ) {
        self.id = id
        self.friendshipID = friendshipID
        self.visitorPetID = visitorPetID
        self.visitorOwnerAccountID = visitorOwnerAccountID
        self.hostAccountID = hostAccountID
        self.requestedByAccountID = requestedByAccountID
        self.responderAccountID = responderAccountID
        self.status = status
        self.closeReason = closeReason
        self.reason = reason
        self.version = version
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.startedAt = startedAt
        self.closedAt = closedAt
    }
}

public struct PublicPetSnapshot: Codable, Equatable, Sendable {
    public let petID: PetProfileID
    public let displayName: String
    public let appearanceSchemaVersion: Int
    public let appearanceCatalogVersion: Int
    public let appearanceVersion: Int64
    public let appearance: [String: String]
    public let publicCare: PublicPetCareSummary?

    public init(
        petID: PetProfileID,
        displayName: String,
        appearanceSchemaVersion: Int,
        appearanceCatalogVersion: Int,
        appearanceVersion: Int64,
        appearance: [String: String],
        publicCare: PublicPetCareSummary? = nil
    ) {
        self.petID = petID
        self.displayName = displayName
        self.appearanceSchemaVersion = appearanceSchemaVersion
        self.appearanceCatalogVersion = appearanceCatalogVersion
        self.appearanceVersion = appearanceVersion
        self.appearance = appearance
        self.publicCare = publicCare
    }
}

public struct DeviceID: RawRepresentable, Codable, Hashable, Sendable {
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

public struct Device: Codable, Equatable, Identifiable, Sendable {
    public let id: DeviceID
    public let accountID: AccountID
    public let displayName: String
    public let platform: String
    public let appVersion: String
    public let createdAt: Date
    public let revokedAt: Date?
}

public enum AgentDeviceRole: String, Codable, Sendable {
    case primary
    case secondary
}

public struct AccountSummary: Codable, Equatable, Sendable {
    public let id: AccountID
    public let displayName: String
    public let primaryAgentDeviceID: DeviceID?
    public let createdAt: Date
    public let updatedAt: Date
}

public struct DeviceMetadata: Codable, Equatable, Sendable {
    public let id: DeviceID?
    public let displayName: String
    public let platform: String
    public let appVersion: String

    public init(
        id: DeviceID? = nil,
        displayName: String,
        platform: String = "macos",
        appVersion: String
    ) {
        self.id = id
        self.displayName = displayName
        self.platform = platform
        self.appVersion = appVersion
    }
}

public struct AccountSession: Codable, Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String
    public let accessExpiresAt: Date
    public let refreshExpiresAt: Date
    public let accountID: AccountID
    public let device: Device
    public let pet: PublicPetSnapshot
    public let isPrimaryAgentDevice: Bool
}

public struct GitHubDeviceAuthorization: Codable, Equatable, Sendable {
    public let deviceCode: String
    public let userCode: String
    public let verificationURI: URL
    public let expiresIn: Int
    public let interval: Int
}

public struct GitHubDeviceCompletion: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable {
        case pending
        case authenticated
    }

    public let status: Status
    public let retryAfterSeconds: Int?
    public let session: AccountSession?
}

public enum FriendshipStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case accepted
    case rejected
    case closed
}

public struct FriendshipSummary: Codable, Equatable, Identifiable, Sendable {
    public struct Friend: Codable, Equatable, Sendable {
        public let accountID: AccountID
        public let displayName: String
        public let pet: PublicPetSnapshot
    }

    public let id: FriendshipID
    public let requesterAccountID: AccountID
    public let addresseeAccountID: AccountID
    public let status: FriendshipStatus
    public let version: Int64
    public let createdAt: Date
    public let respondedAt: Date?
    public let closedAt: Date?
    public let friend: Friend
    public let familiarity: PetFamiliarity?
}

public enum VisitActionActorType: String, Codable, Sendable {
    case human
    case petAgent = "pet_agent"
    case system
}

public enum VisitActionKind: String, Codable, CaseIterable, Sendable {
    case feed
    case play
    case pet
    case hug
    case kiss
    case flower
    case walk
    case message
    case reaction
    case activity
    case speech
    case acknowledgement
}

public struct VisitAction: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let visitID: PetVisitID
    public let senderAccountID: AccountID
    public let actorType: VisitActionActorType
    public let kind: VisitActionKind
    public let payload: JSONValue
    public let replyToActionID: UUID?
    public let requiresResponse: Bool
    public let createdAt: Date
}

public struct CreateVisitCommand: Encodable, Equatable, Sendable {
    public let friendshipID: FriendshipID
    public let visitorPetID: PetProfileID
    public let hostAccountID: AccountID
    public let reason: String?
    public let idempotencyKey: UUID

    public init(
        friendshipID: FriendshipID,
        visitorPetID: PetProfileID,
        hostAccountID: AccountID,
        reason: String? = nil,
        idempotencyKey: UUID = UUID()
    ) {
        self.friendshipID = friendshipID
        self.visitorPetID = visitorPetID
        self.hostAccountID = hostAccountID
        self.reason = reason
        self.idempotencyKey = idempotencyKey
    }

    private enum CodingKeys: String, CodingKey {
        case friendshipID, visitorPetID, hostAccountID, reason
    }
}

public enum VisitResponse: String, Codable, Sendable {
    case accept
    case decline
}

public struct RespondToVisitCommand: Encodable, Equatable, Sendable {
    public let response: VisitResponse
    public let actorType: VisitActionActorType
    public let idempotencyKey: UUID

    public init(
        response: VisitResponse,
        actorType: VisitActionActorType,
        idempotencyKey: UUID = UUID()
    ) {
        self.response = response
        self.actorType = actorType
        self.idempotencyKey = idempotencyKey
    }

    private enum CodingKeys: String, CodingKey { case response, actorType }
}

public struct EndVisitCommand: Encodable, Equatable, Sendable {
    public let actorType: VisitActionActorType
    public let idempotencyKey: UUID

    public init(
        actorType: VisitActionActorType = .human,
        idempotencyKey: UUID = UUID()
    ) {
        self.actorType = actorType
        self.idempotencyKey = idempotencyKey
    }

    private enum CodingKeys: String, CodingKey { case actorType }
}

public struct CreateVisitActionCommand: Encodable, Equatable, Sendable {
    public let kind: VisitActionKind
    public let actorType: VisitActionActorType
    public let payload: JSONValue
    public let replyToActionID: UUID?
    public let idempotencyKey: UUID

    public init(
        kind: VisitActionKind,
        actorType: VisitActionActorType,
        payload: JSONValue = .object([:]),
        replyToActionID: UUID? = nil,
        idempotencyKey: UUID = UUID()
    ) {
        self.kind = kind
        self.actorType = actorType
        self.payload = payload
        self.replyToActionID = replyToActionID
        self.idempotencyKey = idempotencyKey
    }

    private enum CodingKeys: String, CodingKey {
        case kind, actorType, payload, replyToActionID
    }
}

public struct AccountEvent: Codable, Equatable, Identifiable, Sendable {
    public let sequence: Int64
    public let id: String
    public let schemaVersion: Int
    public let recipientAccountID: AccountID
    public let friendshipID: FriendshipID?
    public let type: String
    public let aggregateType: String
    public let aggregateID: String
    public let aggregateVersion: Int64?
    public let payload: JSONValue
    public let timelineVisible: Bool
    public let occurredAt: Date
}

public struct AccountEventPage: Codable, Equatable, Sendable {
    public let events: [AccountEvent]
    public let nextCursor: Int64
}

public struct SyncBootstrap: Codable, Equatable, Sendable {
    public let account: AccountSummary
    public let currentDevice: Device
    public let isPrimaryAgentDevice: Bool
    public let pet: PublicPetSnapshot
    public let ownPetCare: PetCareState
    public let petFamiliarities: [PetFamiliarity]
    public let friendships: [FriendshipSummary]
    public let pendingVisits: [Visit]
    public let activeVisits: [Visit]
    public let unresolvedVisitActions: [VisitAction]
    public let activeConversations: [PetConversation]
    public let cursor: Int64
    public let serverTime: Date
}

extension SyncBootstrap {
    private enum CodingKeys: String, CodingKey {
        case account, currentDevice, isPrimaryAgentDevice, pet
        case ownPetCare, petFamiliarities, friendships
        case pendingVisits, activeVisits, unresolvedVisitActions
        case activeConversations, cursor, serverTime
    }

    /// Care fields were added after the initial account bootstrap contract.
    /// Defaults keep the macOS rollout compatible while Worker and client
    /// versions overlap during staged deployment.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        account = try container.decode(AccountSummary.self, forKey: .account)
        currentDevice = try container.decode(Device.self, forKey: .currentDevice)
        isPrimaryAgentDevice = try container.decode(Bool.self, forKey: .isPrimaryAgentDevice)
        pet = try container.decode(PublicPetSnapshot.self, forKey: .pet)
        let decodedServerTime = try container.decode(Date.self, forKey: .serverTime)
        ownPetCare = try container.decodeIfPresent(PetCareState.self, forKey: .ownPetCare)
            ?? PetCareState(evaluatedAt: decodedServerTime)
        petFamiliarities = try container.decodeIfPresent([PetFamiliarity].self, forKey: .petFamiliarities) ?? []
        friendships = try container.decode([FriendshipSummary].self, forKey: .friendships)
        pendingVisits = try container.decode([Visit].self, forKey: .pendingVisits)
        activeVisits = try container.decode([Visit].self, forKey: .activeVisits)
        unresolvedVisitActions = try container.decode([VisitAction].self, forKey: .unresolvedVisitActions)
        activeConversations = try container.decode([PetConversation].self, forKey: .activeConversations)
        cursor = try container.decode(Int64.self, forKey: .cursor)
        serverTime = decodedServerTime
    }
}

public enum AccountRealtimeSignal: Equatable, Sendable {
    case ready
    case eventsAvailable
}

public protocol AccountEventCursorStore: Sendable {
    func load(for accountID: AccountID) async throws -> Int64?
    func save(_ cursor: Int64, for accountID: AccountID) async throws
    func clear(for accountID: AccountID) async throws
}

public enum SocialMutationKind: String, Codable, Sendable {
    case createVisit
    case respondVisit
    case createVisitAction
    case endVisit
    case createLetter
    case createConversation
    case sendConversationMessage
    case endConversation
    case petInteraction
    case petAppearanceSelection
}

public struct SocialMutation: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let kind: SocialMutationKind
    public let aggregateID: String?
    public let idempotencyKey: UUID
    public let body: JSONValue
    public let createdAt: Date
    public var attemptCount: Int
    public var nextAttemptAt: Date

    public init(
        id: UUID = UUID(),
        kind: SocialMutationKind,
        aggregateID: String? = nil,
        idempotencyKey: UUID = UUID(),
        body: JSONValue,
        createdAt: Date = Date(),
        attemptCount: Int = 0,
        nextAttemptAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.aggregateID = aggregateID
        self.idempotencyKey = idempotencyKey
        self.body = body
        self.createdAt = createdAt
        self.attemptCount = attemptCount
        self.nextAttemptAt = nextAttemptAt
    }
}

public protocol SocialMutationOutboxStore: Sendable {
    func enqueue(_ mutation: SocialMutation) async throws
    func due(at date: Date) async throws -> [SocialMutation]
    func markSucceeded(_ id: UUID) async throws
    func markFailed(_ id: UUID, retryAt: Date) async throws
    func clear() async throws
}
