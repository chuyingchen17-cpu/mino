import Foundation

public enum CoupleInteractionKind: String, Codable, CaseIterable, Sendable {
    case kiss
    case flowerGift = "flower_gift"
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
    public let kind: CoupleInteractionKind
    public let senderPetID: PetProfileID
    public let recipientPetID: PetProfileID
    public let clientCreatedAt: Date

    public init(
        idempotencyKey: UUID = UUID(),
        kind: CoupleInteractionKind,
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
}
