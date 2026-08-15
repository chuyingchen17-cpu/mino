import Foundation

public struct AccountID: RawRepresentable, Codable, Hashable, Sendable {
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

public struct CoupleID: RawRepresentable, Codable, Hashable, Sendable {
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

public struct AccountProfile: Codable, Equatable, Sendable {
    public let id: AccountID
    public var displayName: String
    public let createdAt: Date

    public init(id: AccountID, displayName: String, createdAt: Date) {
        self.id = id
        self.displayName = displayName
        self.createdAt = createdAt
    }
}

public enum CoupleStatus: String, Codable, Equatable, Sendable {
    case pending
    case active
    case disconnected
}

public struct CoupleContext: Codable, Equatable, Sendable {
    public let id: CoupleID
    public let localAccountID: AccountID
    public let partnerAccountID: AccountID
    public var status: CoupleStatus
    public let pairedAt: Date?
    public var updatedAt: Date

    public init(
        id: CoupleID,
        localAccountID: AccountID,
        partnerAccountID: AccountID,
        status: CoupleStatus,
        pairedAt: Date?,
        updatedAt: Date
    ) {
        self.id = id
        self.localAccountID = localAccountID
        self.partnerAccountID = partnerAccountID
        self.status = status
        self.pairedAt = pairedAt
        self.updatedAt = updatedAt
    }
}

public struct PetProfile: Codable, Equatable, Sendable {
    public let id: PetProfileID
    public let ownerAccountID: AccountID
    public var displayName: String
    public var avatar: AvatarRecipe
    public var revision: Int64
    public var updatedAt: Date

    public init(
        id: PetProfileID,
        ownerAccountID: AccountID,
        displayName: String,
        avatar: AvatarRecipe,
        revision: Int64,
        updatedAt: Date
    ) {
        self.id = id
        self.ownerAccountID = ownerAccountID
        self.displayName = displayName
        self.avatar = avatar
        self.revision = revision
        self.updatedAt = updatedAt
    }
}

public struct CoupleSnapshot: Codable, Equatable, Sendable {
    public let context: CoupleContext
    public let localAccount: AccountProfile
    public let partnerAccount: AccountProfile
    public let localPet: PetProfile
    public let partnerPet: PetProfile
    public let serverCursor: String?
    public let syncedAt: Date

    public init(
        context: CoupleContext,
        localAccount: AccountProfile,
        partnerAccount: AccountProfile,
        localPet: PetProfile,
        partnerPet: PetProfile,
        serverCursor: String?,
        syncedAt: Date
    ) {
        self.context = context
        self.localAccount = localAccount
        self.partnerAccount = partnerAccount
        self.localPet = localPet
        self.partnerPet = partnerPet
        self.serverCursor = serverCursor
        self.syncedAt = syncedAt
    }
}

public protocol CoupleSnapshotStore: Sendable {
    func load() async throws -> CoupleSnapshot?
    func save(_ snapshot: CoupleSnapshot) async throws
    func clear() async throws
}
