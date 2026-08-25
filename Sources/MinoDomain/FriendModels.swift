import Foundation

public struct FriendshipID: RawRepresentable, Codable, Hashable, Sendable {
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

public struct FriendRequestID: RawRepresentable, Codable, Hashable, Sendable {
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

public struct FriendProfile: Codable, Equatable, Identifiable, Sendable {
    public let friendshipID: FriendshipID
    public let accountID: AccountID
    public let accountName: String
    public let petID: PetProfileID
    public let petName: String
    public let friendsSince: Date
    public let publicCare: PublicPetCareSummary?
    public let familiarity: PetFamiliarity?
    public let characterID: PetCharacterID?

    public var id: FriendshipID { friendshipID }

    public init(
        friendshipID: FriendshipID,
        accountID: AccountID,
        accountName: String,
        petID: PetProfileID,
        petName: String,
        friendsSince: Date,
        publicCare: PublicPetCareSummary? = nil,
        familiarity: PetFamiliarity? = nil,
        characterID: PetCharacterID? = nil
    ) {
        self.friendshipID = friendshipID
        self.accountID = accountID
        self.accountName = accountName
        self.petID = petID
        self.petName = petName
        self.friendsSince = friendsSince
        self.publicCare = publicCare
        self.familiarity = familiarity
        self.characterID = characterID
    }
}

public enum FriendRequestStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case accepted
    case declined = "rejected"
    case cancelled
}

public struct FriendRequest: Codable, Equatable, Identifiable, Sendable {
    public let id: FriendRequestID
    public let requesterAccountID: AccountID
    public let addresseeAccountID: AccountID
    /// The other account as seen by the authenticated user.
    public let friendAccountID: AccountID
    public let friendName: String
    public let friendPetID: PetProfileID
    public let friendPetName: String
    public let status: FriendRequestStatus
    public let createdAt: Date
    public let respondedAt: Date?

    public init(
        id: FriendRequestID,
        requesterAccountID: AccountID,
        addresseeAccountID: AccountID,
        friendAccountID: AccountID,
        friendName: String,
        friendPetID: PetProfileID,
        friendPetName: String,
        status: FriendRequestStatus,
        createdAt: Date,
        respondedAt: Date? = nil
    ) {
        self.id = id
        self.requesterAccountID = requesterAccountID
        self.addresseeAccountID = addresseeAccountID
        self.friendAccountID = friendAccountID
        self.friendName = friendName
        self.friendPetID = friendPetID
        self.friendPetName = friendPetName
        self.status = status
        self.createdAt = createdAt
        self.respondedAt = respondedAt
    }
}

public struct CreateFriendRequestCommand: Encodable, Equatable, Sendable {
    public let addresseeAccountID: AccountID
    public let idempotencyKey: UUID

    public init(addresseeAccountID: AccountID, idempotencyKey: UUID = UUID()) {
        self.addresseeAccountID = addresseeAccountID
        self.idempotencyKey = idempotencyKey
    }

    private enum CodingKeys: String, CodingKey { case addresseeAccountID }
}

public enum FriendRequestDecision: String, Codable, CaseIterable, Sendable {
    case accept
    case decline = "reject"
}

public struct RespondFriendRequestCommand: Encodable, Equatable, Sendable {
    public let response: FriendRequestDecision
    public let idempotencyKey: UUID

    public init(response: FriendRequestDecision, idempotencyKey: UUID = UUID()) {
        self.response = response
        self.idempotencyKey = idempotencyKey
    }


    private enum CodingKeys: String, CodingKey { case response }
}
