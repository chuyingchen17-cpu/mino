import Foundation

/// Account command used for the one-time, permanently locked character choice.
/// The idempotency key is carried as an HTTP header and is not encoded in the body.
public struct PetAppearanceSelectionCommand: Encodable, Equatable, Sendable {
    public let appearanceSchemaVersion: Int
    public let appearanceCatalogVersion: Int
    public let appearance: [String: String]
    public let idempotencyKey: UUID

    public init(
        characterID: PetCharacterID,
        idempotencyKey: UUID = UUID()
    ) {
        appearanceSchemaVersion = PetCharacterID.appearanceSchema
        appearanceCatalogVersion = PetCharacterID.appearanceCatalog
        appearance = characterID.appearance
        self.idempotencyKey = idempotencyKey
    }

    public var characterID: PetCharacterID? {
        guard
            appearanceSchemaVersion == PetCharacterID.appearanceSchema,
            appearanceCatalogVersion == PetCharacterID.appearanceCatalog
        else { return nil }
        return PetCharacterID(appearance: appearance)
    }

    private enum CodingKeys: String, CodingKey {
        case appearanceSchemaVersion
        case appearanceCatalogVersion
        case appearance
    }
}
