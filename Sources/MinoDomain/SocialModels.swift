import Foundation

/// A JSON value used at the durable event boundary.
///
/// Event payloads intentionally remain forward-compatible: clients can consume
/// known fields without failing when a newer server adds metadata.
public indirect enum JSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    public subscript(key: String) -> JSONValue? {
        guard case .object(let object) = self else { return nil }
        return object[key]
    }

    public var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    public var numberValue: Double? {
        guard case .number(let value) = self else { return nil }
        return value
    }
}

public struct ConversationID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct ConversationMessageID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct LetterID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum SocialActorType: String, Codable, Sendable {
    case pet
    case human
    case system
}

public enum ConversationStatus: String, Codable, Sendable {
    case active
    case ended
}

public struct PetConversation: Codable, Equatable, Sendable {
    public let id: ConversationID
    public let friendshipID: FriendshipID
    public let initiatorPetID: PetProfileID
    public let recipientPetID: PetProfileID
    public let status: ConversationStatus
    public let nextSpeakerPetID: PetProfileID?
    public let turnCount: Int
    public let createdAt: Date
    public let endedAt: Date?

    public init(
        id: ConversationID,
        friendshipID: FriendshipID,
        initiatorPetID: PetProfileID,
        recipientPetID: PetProfileID,
        status: ConversationStatus,
        nextSpeakerPetID: PetProfileID?,
        turnCount: Int,
        createdAt: Date,
        endedAt: Date? = nil
    ) {
        self.id = id
        self.friendshipID = friendshipID
        self.initiatorPetID = initiatorPetID
        self.recipientPetID = recipientPetID
        self.status = status
        self.nextSpeakerPetID = nextSpeakerPetID
        self.turnCount = turnCount
        self.createdAt = createdAt
        self.endedAt = endedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case friendshipID
        case legacyCoupleID = "coupleID"
        case initiatorPetID
        case recipientPetID
        case status
        case nextSpeakerPetID
        case turnCount
        case createdAt
        case endedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let friendshipID = try container.decodeIfPresent(
            FriendshipID.self,
            forKey: .friendshipID
        ) ?? container.decode(FriendshipID.self, forKey: .legacyCoupleID)
        self.init(
            id: try container.decode(ConversationID.self, forKey: .id),
            friendshipID: friendshipID,
            initiatorPetID: try container.decode(PetProfileID.self, forKey: .initiatorPetID),
            recipientPetID: try container.decode(PetProfileID.self, forKey: .recipientPetID),
            status: try container.decode(ConversationStatus.self, forKey: .status),
            nextSpeakerPetID: try container.decodeIfPresent(
                PetProfileID.self,
                forKey: .nextSpeakerPetID
            ),
            turnCount: try container.decode(Int.self, forKey: .turnCount),
            createdAt: try container.decode(Date.self, forKey: .createdAt),
            endedAt: try container.decodeIfPresent(Date.self, forKey: .endedAt)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(friendshipID, forKey: .friendshipID)
        try container.encode(initiatorPetID, forKey: .initiatorPetID)
        try container.encode(recipientPetID, forKey: .recipientPetID)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(nextSpeakerPetID, forKey: .nextSpeakerPetID)
        try container.encode(turnCount, forKey: .turnCount)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(endedAt, forKey: .endedAt)
    }
}

public struct PetConversationMessage: Codable, Equatable, Sendable {
    public let id: ConversationMessageID
    public let conversationID: ConversationID
    public let actorType: SocialActorType
    public let actorID: String
    public let recipientPetID: PetProfileID
    public let text: String
    public let turnIndex: Int?
    public let createdAt: Date

    public init(
        id: ConversationMessageID,
        conversationID: ConversationID,
        actorType: SocialActorType,
        actorID: String,
        recipientPetID: PetProfileID,
        text: String,
        turnIndex: Int?,
        createdAt: Date
    ) {
        self.id = id
        self.conversationID = conversationID
        self.actorType = actorType
        self.actorID = actorID
        self.recipientPetID = recipientPetID
        self.text = text
        self.turnIndex = turnIndex
        self.createdAt = createdAt
    }
}

public struct CreateConversationCommand: Codable, Equatable, Sendable {
    public let recipientPetID: PetProfileID
    public let openingMessage: String
    public let idempotencyKey: UUID

    public init(
        recipientPetID: PetProfileID,
        openingMessage: String,
        idempotencyKey: UUID = UUID()
    ) {
        self.recipientPetID = recipientPetID
        self.openingMessage = openingMessage
        self.idempotencyKey = idempotencyKey
    }
}

public struct ConversationTurnReceipt: Codable, Equatable, Sendable {
    public let conversation: PetConversation
    public let message: PetConversationMessage

    public init(conversation: PetConversation, message: PetConversationMessage) {
        self.conversation = conversation
        self.message = message
    }
}

public struct SendConversationMessageCommand: Codable, Equatable, Sendable {
    public let actorType: SocialActorType
    public let text: String
    public let idempotencyKey: UUID

    public init(
        actorType: SocialActorType,
        text: String,
        idempotencyKey: UUID = UUID()
    ) {
        self.actorType = actorType
        self.text = text
        self.idempotencyKey = idempotencyKey
    }
}

public struct EndConversationCommand: Codable, Equatable, Sendable {
    public let summary: String
    public let idempotencyKey: UUID

    public init(summary: String, idempotencyKey: UUID = UUID()) {
        self.summary = summary
        self.idempotencyKey = idempotencyKey
    }
}

public enum MVPVisitStatus: String, Codable, Sendable {
    case pending
    case active
    case ended
    case cancelled
}

/// The server-authoritative logical visit. It contains no desktop coordinates.
public struct MVPVisit: Codable, Equatable, Sendable {
    public let id: PetVisitID
    public let friendshipID: FriendshipID
    public let visitorPetID: PetProfileID
    public let visitorOwnerAccountID: AccountID
    public let hostAccountID: AccountID
    public let requestedByAccountID: AccountID
    public let status: MVPVisitStatus
    public let reason: String?
    public let createdAt: Date
    public let startedAt: Date?
    public let endedAt: Date?

    public init(
        id: PetVisitID,
        friendshipID: FriendshipID,
        visitorPetID: PetProfileID,
        visitorOwnerAccountID: AccountID,
        hostAccountID: AccountID,
        requestedByAccountID: AccountID,
        status: MVPVisitStatus,
        reason: String? = nil,
        createdAt: Date,
        startedAt: Date? = nil,
        endedAt: Date? = nil
    ) {
        self.id = id
        self.friendshipID = friendshipID
        self.visitorPetID = visitorPetID
        self.visitorOwnerAccountID = visitorOwnerAccountID
        self.hostAccountID = hostAccountID
        self.requestedByAccountID = requestedByAccountID
        self.status = status
        self.reason = reason
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.endedAt = endedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case friendshipID
        case legacyCoupleID = "coupleID"
        case visitorPetID
        case visitorOwnerAccountID
        case hostAccountID
        case requestedByAccountID
        case status
        case reason
        case createdAt
        case startedAt
        case endedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let friendshipID = try container.decodeIfPresent(
            FriendshipID.self,
            forKey: .friendshipID
        ) ?? container.decode(FriendshipID.self, forKey: .legacyCoupleID)
        self.init(
            id: try container.decode(PetVisitID.self, forKey: .id),
            friendshipID: friendshipID,
            visitorPetID: try container.decode(PetProfileID.self, forKey: .visitorPetID),
            visitorOwnerAccountID: try container.decode(
                AccountID.self,
                forKey: .visitorOwnerAccountID
            ),
            hostAccountID: try container.decode(AccountID.self, forKey: .hostAccountID),
            requestedByAccountID: try container.decode(
                AccountID.self,
                forKey: .requestedByAccountID
            ),
            status: try container.decode(MVPVisitStatus.self, forKey: .status),
            reason: try container.decodeIfPresent(String.self, forKey: .reason),
            createdAt: try container.decode(Date.self, forKey: .createdAt),
            startedAt: try container.decodeIfPresent(Date.self, forKey: .startedAt),
            endedAt: try container.decodeIfPresent(Date.self, forKey: .endedAt)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(friendshipID, forKey: .friendshipID)
        try container.encode(visitorPetID, forKey: .visitorPetID)
        try container.encode(visitorOwnerAccountID, forKey: .visitorOwnerAccountID)
        try container.encode(hostAccountID, forKey: .hostAccountID)
        try container.encode(requestedByAccountID, forKey: .requestedByAccountID)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(reason, forKey: .reason)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(startedAt, forKey: .startedAt)
        try container.encodeIfPresent(endedAt, forKey: .endedAt)
    }
}

public struct CreateVisitInvitationCommand: Codable, Equatable, Sendable {
    public let visitorPetID: PetProfileID
    public let hostAccountID: AccountID
    public let reason: String?
    public let idempotencyKey: UUID

    public init(
        visitorPetID: PetProfileID,
        hostAccountID: AccountID,
        reason: String? = nil,
        idempotencyKey: UUID = UUID()
    ) {
        self.visitorPetID = visitorPetID
        self.hostAccountID = hostAccountID
        self.reason = reason
        self.idempotencyKey = idempotencyKey
    }
}

public struct RespondToVisitInvitationCommand: Codable, Equatable, Sendable {
    public let response: PetVisitInvitationResponse
    public let idempotencyKey: UUID

    public init(
        response: PetVisitInvitationResponse,
        idempotencyKey: UUID = UUID()
    ) {
        self.response = response
        self.idempotencyKey = idempotencyKey
    }
}

public enum VisitInteractionKind: String, Codable, CaseIterable, Sendable {
    case feed
    case play
    case message
}

public struct CreateVisitInteractionCommand: Codable, Equatable, Sendable {
    public let kind: VisitInteractionKind
    public let text: String?
    public let idempotencyKey: UUID

    public init(
        kind: VisitInteractionKind,
        text: String? = nil,
        idempotencyKey: UUID = UUID()
    ) {
        self.kind = kind
        self.text = text
        self.idempotencyKey = idempotencyKey
    }
}

public struct VisitInteractionReceipt: Codable, Equatable, Sendable {
    public let interactionID: String
    public let visitID: PetVisitID
    public let kind: VisitInteractionKind
    public let acceptedAt: Date

    public init(
        interactionID: String,
        visitID: PetVisitID,
        kind: VisitInteractionKind,
        acceptedAt: Date
    ) {
        self.interactionID = interactionID
        self.visitID = visitID
        self.kind = kind
        self.acceptedAt = acceptedAt
    }
}

/// A small, transport-safe vocabulary for reactions chosen by the visiting
/// pet's Agent. The server relays these values but never selects one itself.
public enum VisitPetReaction: String, Codable, CaseIterable, Sendable {
    case happy
    case excited
    case shy
    case sleepy
    case grateful
    case playful
    case resting
}

public struct CreateVisitReactionCommand: Codable, Equatable, Sendable {
    public let reaction: VisitPetReaction
    public let text: String?
    public let idempotencyKey: UUID

    public init(
        reaction: VisitPetReaction,
        text: String? = nil,
        idempotencyKey: UUID = UUID()
    ) {
        self.reaction = reaction
        self.text = text
        self.idempotencyKey = idempotencyKey
    }
}

public struct VisitReactionReceipt: Codable, Equatable, Sendable {
    public let reactionID: String
    public let visitID: PetVisitID
    public let reaction: VisitPetReaction
    public let acceptedAt: Date

    public init(
        reactionID: String,
        visitID: PetVisitID,
        reaction: VisitPetReaction,
        acceptedAt: Date
    ) {
        self.reactionID = reactionID
        self.visitID = visitID
        self.reaction = reaction
        self.acceptedAt = acceptedAt
    }
}

public enum LetterStatus: String, Codable, Sendable {
    case carried
    case delivered
    case draft
}

public struct PetLetter: Codable, Equatable, Sendable {
    public let id: LetterID
    public let friendshipID: FriendshipID
    public let visitID: PetVisitID
    public let authorAccountID: AccountID
    public let recipientAccountID: AccountID
    public let body: String
    public let status: LetterStatus
    public let createdAt: Date
    public let deliveredAt: Date?

    public init(
        id: LetterID,
        friendshipID: FriendshipID,
        visitID: PetVisitID,
        authorAccountID: AccountID,
        recipientAccountID: AccountID,
        body: String,
        status: LetterStatus,
        createdAt: Date,
        deliveredAt: Date? = nil
    ) {
        self.id = id
        self.friendshipID = friendshipID
        self.visitID = visitID
        self.authorAccountID = authorAccountID
        self.recipientAccountID = recipientAccountID
        self.body = body
        self.status = status
        self.createdAt = createdAt
        self.deliveredAt = deliveredAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case friendshipID
        case legacyCoupleID = "coupleID"
        case visitID
        case authorAccountID
        case recipientAccountID
        case body
        case status
        case createdAt
        case deliveredAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let friendshipID = try container.decodeIfPresent(
            FriendshipID.self,
            forKey: .friendshipID
        ) ?? container.decode(FriendshipID.self, forKey: .legacyCoupleID)
        self.init(
            id: try container.decode(LetterID.self, forKey: .id),
            friendshipID: friendshipID,
            visitID: try container.decode(PetVisitID.self, forKey: .visitID),
            authorAccountID: try container.decode(AccountID.self, forKey: .authorAccountID),
            recipientAccountID: try container.decode(AccountID.self, forKey: .recipientAccountID),
            body: try container.decode(String.self, forKey: .body),
            status: try container.decode(LetterStatus.self, forKey: .status),
            createdAt: try container.decode(Date.self, forKey: .createdAt),
            deliveredAt: try container.decodeIfPresent(Date.self, forKey: .deliveredAt)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(friendshipID, forKey: .friendshipID)
        try container.encode(visitID, forKey: .visitID)
        try container.encode(authorAccountID, forKey: .authorAccountID)
        try container.encode(recipientAccountID, forKey: .recipientAccountID)
        try container.encode(body, forKey: .body)
        try container.encode(status, forKey: .status)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(deliveredAt, forKey: .deliveredAt)
    }
}

public struct CreateLetterCommand: Codable, Equatable, Sendable {
    public let body: String
    public let idempotencyKey: UUID

    public init(body: String, idempotencyKey: UUID = UUID()) {
        self.body = body
        self.idempotencyKey = idempotencyKey
    }
}

public struct EndVisitCommand: Codable, Equatable, Sendable {
    public let idempotencyKey: UUID

    public init(idempotencyKey: UUID = UUID()) {
        self.idempotencyKey = idempotencyKey
    }
}

public struct EndVisitReceipt: Codable, Equatable, Sendable {
    public let visit: MVPVisit
    public let deliveredLetters: [PetLetter]

    public init(visit: MVPVisit, deliveredLetters: [PetLetter]) {
        self.visit = visit
        self.deliveredLetters = deliveredLetters
    }
}

public struct FriendshipEvent: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let sequence: Int64
    public let friendshipID: FriendshipID
    public let type: String
    public let actorType: SocialActorType
    public let actorID: String?
    public let payload: JSONValue
    public let timelineVisible: Bool
    public let occurredAt: Date

    public init(
        id: String,
        sequence: Int64,
        friendshipID: FriendshipID,
        type: String,
        actorType: SocialActorType,
        actorID: String? = nil,
        payload: JSONValue = .object([:]),
        timelineVisible: Bool,
        occurredAt: Date
    ) {
        self.id = id
        self.sequence = sequence
        self.friendshipID = friendshipID
        self.type = type
        self.actorType = actorType
        self.actorID = actorID
        self.payload = payload
        self.timelineVisible = timelineVisible
        self.occurredAt = occurredAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case sequence
        case friendshipID
        case legacyCoupleID = "coupleID"
        case type
        case actorType
        case actorID
        case payload
        case timelineVisible
        case occurredAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let friendshipID = try container.decodeIfPresent(
            FriendshipID.self,
            forKey: .friendshipID
        ) ?? container.decode(FriendshipID.self, forKey: .legacyCoupleID)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            sequence: try container.decode(Int64.self, forKey: .sequence),
            friendshipID: friendshipID,
            type: try container.decode(String.self, forKey: .type),
            actorType: try container.decode(SocialActorType.self, forKey: .actorType),
            actorID: try container.decodeIfPresent(String.self, forKey: .actorID),
            payload: try container.decode(JSONValue.self, forKey: .payload),
            timelineVisible: try container.decode(Bool.self, forKey: .timelineVisible),
            occurredAt: try container.decode(Date.self, forKey: .occurredAt)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(sequence, forKey: .sequence)
        try container.encode(friendshipID, forKey: .friendshipID)
        try container.encode(type, forKey: .type)
        try container.encode(actorType, forKey: .actorType)
        try container.encodeIfPresent(actorID, forKey: .actorID)
        try container.encode(payload, forKey: .payload)
        try container.encode(timelineVisible, forKey: .timelineVisible)
        try container.encode(occurredAt, forKey: .occurredAt)
    }
}

public extension FriendshipEvent {
    /// Converts durable server events to the intentionally compact event-line
    /// presentation model. No elapsed/visit duration is derived here.
    func timelineEvent() -> PersonalTimelineEvent? {
        guard timelineVisible else { return nil }

        let actorAccountID = actorType == .human
            ? actorID.map(AccountID.init(rawValue:))
            : nil
        let visitID = payload["visitID"]?.stringValue.map(PetVisitID.init(rawValue:))
        let visitorPetID = payload["visitorPetID"]?.stringValue.map(PetProfileID.init(rawValue:))

        switch type {
        case "conversation_summary":
            return PersonalTimelineEvent(
                id: id,
                friendshipID: friendshipID,
                kind: .conversationSummary,
                occurredAt: occurredAt,
                actorAccountID: actorAccountID,
                summary: payload["summary"]?.stringValue,
                conversationID: payload["conversationID"]?.stringValue.map(
                    ConversationID.init(rawValue:)
                )
            )

        case "visit_arrived":
            return PersonalTimelineEvent(
                id: id,
                friendshipID: friendshipID,
                kind: .visitArrived,
                occurredAt: occurredAt,
                petID: visitorPetID,
                visitID: visitID,
                actorAccountID: actorAccountID
            )

        case "visit_returned":
            return PersonalTimelineEvent(
                id: id,
                friendshipID: friendshipID,
                kind: .visitReturned,
                occurredAt: occurredAt,
                petID: visitorPetID,
                visitID: visitID,
                actorAccountID: actorAccountID
            )

        case "visit_interaction":
            guard let rawKind = payload["kind"]?.stringValue,
                  let interaction = VisitInteractionKind(rawValue: rawKind) else {
                return nil
            }
            return PersonalTimelineEvent(
                id: id,
                friendshipID: friendshipID,
                kind: .visitInteraction,
                occurredAt: occurredAt,
                petID: visitorPetID,
                visitID: visitID,
                actorAccountID: actorAccountID,
                visitInteractionKind: interaction
            )

        case "letter_received":
            return PersonalTimelineEvent(
                id: id,
                friendshipID: friendshipID,
                kind: .letterReceived,
                occurredAt: occurredAt,
                visitID: visitID,
                actorAccountID: actorAccountID,
                letterID: payload["letterID"]?.stringValue.map(LetterID.init(rawValue:))
            )

        case "interaction":
            return PersonalTimelineEvent(
                id: id,
                friendshipID: friendshipID,
                kind: .interaction,
                occurredAt: occurredAt,
                petID: payload["senderPetID"]?.stringValue.map(PetProfileID.init(rawValue:)),
                actorAccountID: actorAccountID,
                interactionKind: payload["kind"]?.stringValue.flatMap(PetInteractionKind.init(rawValue:))
            )

        default:
            return nil
        }
    }
}

public struct FriendshipEventPage: Codable, Equatable, Sendable {
    public let events: [FriendshipEvent]
    public let nextCursor: String?

    public init(events: [FriendshipEvent], nextCursor: String?) {
        self.events = events
        self.nextCursor = nextCursor
    }
}

public protocol FriendshipEventCursorStore: Sendable {
    func load(for friendshipID: FriendshipID) async throws -> String?
    func save(_ eventID: String, for friendshipID: FriendshipID) async throws
    func clear(for friendshipID: FriendshipID) async throws
}

@available(*, deprecated, renamed: "FriendshipEvent")
public typealias CoupleEvent = FriendshipEvent

@available(*, deprecated, renamed: "FriendshipEventPage")
public typealias CoupleEventPage = FriendshipEventPage

public struct DevBootstrapProfile: Codable, Equatable, Sendable {
    public let profile: String
    public let token: String
    public let accountID: AccountID
    public let petID: PetProfileID
    public let accountName: String
    public let petName: String

    public init(
        profile: String,
        token: String,
        accountID: AccountID,
        petID: PetProfileID,
        accountName: String,
        petName: String
    ) {
        self.profile = profile
        self.token = token
        self.accountID = accountID
        self.petID = petID
        self.accountName = accountName
        self.petName = petName
    }
}
