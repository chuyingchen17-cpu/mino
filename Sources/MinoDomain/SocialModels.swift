import Foundation

/// Forward-compatible JSON used only at transport/event boundaries.
public indirect enum JSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([String: JSONValue].self) { self = .object(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else {
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
    public init(rawValue: String) { self.rawValue = rawValue }
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
    public init(rawValue: String) { self.rawValue = rawValue }
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
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum SocialActorType: String, Codable, Sendable {
    case human
    case petAgent = "pet_agent"
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
    public let version: Int64
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
        version: Int64,
        createdAt: Date,
        endedAt: Date?
    ) {
        self.id = id
        self.friendshipID = friendshipID
        self.initiatorPetID = initiatorPetID
        self.recipientPetID = recipientPetID
        self.status = status
        self.nextSpeakerPetID = nextSpeakerPetID
        self.turnCount = turnCount
        self.version = version
        self.createdAt = createdAt
        self.endedAt = endedAt
    }
}

public struct PetConversationMessage: Codable, Equatable, Sendable {
    public let id: ConversationMessageID
    public let conversationID: ConversationID
    public let senderAccountID: AccountID
    public let actorType: SocialActorType
    public let body: String
    public let turnIndex: Int?
    public let createdAt: Date
}

public struct CreateConversationCommand: Encodable, Equatable, Sendable {
    public let friendshipID: FriendshipID
    public let recipientPetID: PetProfileID
    public let openingMessage: String
    public let actorType: SocialActorType
    public let idempotencyKey: UUID

    public init(
        friendshipID: FriendshipID,
        recipientPetID: PetProfileID,
        openingMessage: String,
        idempotencyKey: UUID = UUID()
    ) {
        self.friendshipID = friendshipID
        self.recipientPetID = recipientPetID
        self.openingMessage = openingMessage
        self.actorType = .petAgent
        self.idempotencyKey = idempotencyKey
    }

    private enum CodingKeys: String, CodingKey {
        case friendshipID, recipientPetID, openingMessage, actorType
    }
}

public struct ConversationTurnReceipt: Codable, Equatable, Sendable {
    public let conversation: PetConversation
    public let message: PetConversationMessage
}

public struct SendConversationMessageCommand: Encodable, Equatable, Sendable {
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

    private enum CodingKeys: String, CodingKey { case actorType, text }
}

public struct EndConversationCommand: Encodable, Equatable, Sendable {
    public let summary: String
    public let actorType: SocialActorType
    public let idempotencyKey: UUID

    public init(summary: String, idempotencyKey: UUID = UUID()) {
        self.summary = summary
        self.actorType = .petAgent
        self.idempotencyKey = idempotencyKey
    }

    private enum CodingKeys: String, CodingKey { case summary, actorType }
}

public enum LetterStatus: String, Codable, Sendable {
    case attached
    case delivered
}

public struct PetLetter: Codable, Equatable, Identifiable, Sendable {
    public let id: LetterID
    public let friendshipID: FriendshipID
    public let visitID: PetVisitID
    public let authorAccountID: AccountID
    public let recipientAccountID: AccountID
    public let body: String?
    public let status: LetterStatus
    public let createdAt: Date
    public let deliveredAt: Date?
}

public struct CreateLetterCommand: Encodable, Equatable, Sendable {
    public let body: String
    public let idempotencyKey: UUID

    public init(body: String, idempotencyKey: UUID = UUID()) {
        self.body = body
        self.idempotencyKey = idempotencyKey
    }

    private enum CodingKeys: String, CodingKey { case body }
}

public struct DevBootstrapProfile: Codable, Equatable, Sendable {
    public let profile: String
    public let token: String
    public let refreshToken: String
    public let accountID: AccountID
    public let deviceID: DeviceID
    public let petID: PetProfileID
    public let accountName: String
    public let petName: String

    public init(
        profile: String,
        token: String,
        refreshToken: String,
        accountID: AccountID,
        deviceID: DeviceID,
        petID: PetProfileID,
        accountName: String,
        petName: String
    ) {
        self.profile = profile
        self.token = token
        self.refreshToken = refreshToken
        self.accountID = accountID
        self.deviceID = deviceID
        self.petID = petID
        self.accountName = accountName
        self.petName = petName
    }
}
