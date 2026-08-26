import Foundation

public struct AccountID: RawRepresentable, Codable, Hashable, Sendable {
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

public struct CurrentProfile: Codable, Equatable, Sendable {
    public let accountID: AccountID
    public let petID: PetProfileID
    public var accountName: String
    public var petName: String
    public let createdAt: Date

    public init(
        accountID: AccountID,
        petID: PetProfileID,
        accountName: String,
        petName: String,
        createdAt: Date
    ) {
        self.accountID = accountID
        self.petID = petID
        self.accountName = accountName
        self.petName = petName
        self.createdAt = createdAt
    }
}
