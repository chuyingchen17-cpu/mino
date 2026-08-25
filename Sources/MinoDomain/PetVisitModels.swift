import Foundation

public struct PetVisitID: RawRepresentable, Codable, Hashable, Sendable {
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

/// Agent observation identifiers are intentionally distinct from the Visit ID
/// even though an invitation is represented by a pending Visit on the wire.
public struct PetVisitInvitationID: RawRepresentable, Codable, Hashable, Sendable {
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

public struct PetItemID: RawRepresentable, Codable, Hashable, Sendable {
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

public enum PetCargoKind: String, Codable, CaseIterable, Sendable {
    case gift, keepsake, consumable, letter, custom
}

/// Historical timeline presentation data. Cargo is not server visit state.
public struct PetCargoItem: Codable, Equatable, Sendable {
    public let itemID: PetItemID
    public let kind: PetCargoKind
    public let displayName: String
    public let quantity: Int

    public init(
        itemID: PetItemID,
        kind: PetCargoKind,
        displayName: String,
        quantity: Int = 1
    ) {
        self.itemID = itemID
        self.kind = kind
        self.displayName = displayName
        self.quantity = min(max(1, quantity), 99)
    }
}

public enum PersonalTimelineEventKind: String, Codable, CaseIterable, Sendable {
    case visitInvited = "visit_invited"
    case visitArrived = "visit_arrived"
    case visitReturned = "visit_returned"
    case invitationDeclined = "invitation_declined"
    case interaction
    case visitInteraction = "visit_interaction"
    case conversationSummary = "conversation_summary"
    case letterReceived = "letter_received"
    case cargoReceived = "cargo_received"
    case postcardReceived = "postcard_received"
}

public struct PetPostcard: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let message: String?
    public let imageURL: URL?
    public let createdAt: Date

    public init(
        id: String,
        title: String,
        message: String? = nil,
        imageURL: URL? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.message = message
        self.imageURL = imageURL
        self.createdAt = createdAt
    }
}

public struct PersonalTimelineEvent: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let friendshipID: FriendshipID?
    public let kind: PersonalTimelineEventKind
    public let occurredAt: Date
    public let petID: PetProfileID?
    public let visitID: PetVisitID?
    public let invitationID: PetVisitInvitationID?
    public let actorAccountID: AccountID?
    public let interactionKind: PetInteractionKind?
    public let visitInteractionKind: VisitActionKind?
    public let cargoItems: [PetCargoItem]
    public let postcard: PetPostcard?
    public let summary: String?
    public let letterID: LetterID?
    public let conversationID: ConversationID?
    public let visitInteractionSummary: VisitInteractionSummary?

    public init(
        id: String = UUID().uuidString,
        friendshipID: FriendshipID? = nil,
        kind: PersonalTimelineEventKind,
        occurredAt: Date = Date(),
        petID: PetProfileID? = nil,
        visitID: PetVisitID? = nil,
        invitationID: PetVisitInvitationID? = nil,
        actorAccountID: AccountID? = nil,
        interactionKind: PetInteractionKind? = nil,
        visitInteractionKind: VisitActionKind? = nil,
        cargoItems: [PetCargoItem] = [],
        postcard: PetPostcard? = nil,
        summary: String? = nil,
        letterID: LetterID? = nil,
        conversationID: ConversationID? = nil,
        visitInteractionSummary: VisitInteractionSummary? = nil
    ) {
        self.id = id
        self.friendshipID = friendshipID
        self.kind = kind
        self.occurredAt = occurredAt
        self.petID = petID
        self.visitID = visitID
        self.invitationID = invitationID
        self.actorAccountID = actorAccountID
        self.interactionKind = interactionKind
        self.visitInteractionKind = visitInteractionKind
        self.cargoItems = cargoItems
        self.postcard = postcard
        self.summary = summary
        self.letterID = letterID
        self.conversationID = conversationID
        self.visitInteractionSummary = visitInteractionSummary
    }

    private enum CodingKeys: String, CodingKey {
        case id, friendshipID, kind, occurredAt, petID, visitID, invitationID
        case actorAccountID, interactionKind, visitInteractionKind, cargoItems
        case postcard, summary, letterID, conversationID, visitInteractionSummary
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            friendshipID: try container.decodeIfPresent(FriendshipID.self, forKey: .friendshipID),
            kind: try container.decode(PersonalTimelineEventKind.self, forKey: .kind),
            occurredAt: try container.decode(Date.self, forKey: .occurredAt),
            petID: try container.decodeIfPresent(PetProfileID.self, forKey: .petID),
            visitID: try container.decodeIfPresent(PetVisitID.self, forKey: .visitID),
            invitationID: try container.decodeIfPresent(PetVisitInvitationID.self, forKey: .invitationID),
            actorAccountID: try container.decodeIfPresent(AccountID.self, forKey: .actorAccountID),
            interactionKind: try container.decodeIfPresent(PetInteractionKind.self, forKey: .interactionKind),
            visitInteractionKind: try container.decodeIfPresent(VisitActionKind.self, forKey: .visitInteractionKind),
            cargoItems: try container.decodeIfPresent([PetCargoItem].self, forKey: .cargoItems) ?? [],
            postcard: try container.decodeIfPresent(PetPostcard.self, forKey: .postcard),
            summary: try container.decodeIfPresent(String.self, forKey: .summary),
            letterID: try container.decodeIfPresent(LetterID.self, forKey: .letterID),
            conversationID: try container.decodeIfPresent(ConversationID.self, forKey: .conversationID),
            visitInteractionSummary: try container.decodeIfPresent(
                VisitInteractionSummary.self,
                forKey: .visitInteractionSummary
            )
        )
    }
}

public protocol PersonalTimelineStore: Sendable {
    func load() async throws -> [PersonalTimelineEvent]
    func append(_ event: PersonalTimelineEvent) async throws
    func merge(_ events: [PersonalTimelineEvent]) async throws
    func clear() async throws
}

public extension AccountEvent {
    func timelineEvent() -> PersonalTimelineEvent? {
        guard timelineVisible, let friendshipID else { return nil }
        let visit = payload["visit"]
        let action = payload["action"]
        let visitID = (visit?["id"] ?? payload["visitID"])?.stringValue.map(PetVisitID.init(rawValue:))
        let visitorPetID = visit?["visitorPetID"]?.stringValue.map(PetProfileID.init(rawValue:))

        switch type {
        case "visit.requested":
            return PersonalTimelineEvent(
                id: id, friendshipID: friendshipID, kind: .visitInvited,
                occurredAt: occurredAt, petID: visitorPetID, visitID: visitID,
                invitationID: visitID.map { PetVisitInvitationID(rawValue: $0.rawValue) }
            )
        case "visit.activated":
            return PersonalTimelineEvent(
                id: id, friendshipID: friendshipID, kind: .visitArrived,
                occurredAt: occurredAt, petID: visitorPetID, visitID: visitID
            )
        case "visit.closed":
            return PersonalTimelineEvent(
                id: id, friendshipID: friendshipID, kind: .visitReturned,
                occurredAt: occurredAt, petID: visitorPetID, visitID: visitID,
                visitInteractionSummary: decodePayload(
                    payload["interactionSummary"],
                    as: VisitInteractionSummary.self
                )
            )
        case "visit.action.created", "visit.action.replied":
            return PersonalTimelineEvent(
                id: id, friendshipID: friendshipID, kind: .visitInteraction,
                occurredAt: occurredAt, visitID: visitID,
                actorAccountID: action?["senderAccountID"]?.stringValue.map(AccountID.init(rawValue:)),
                visitInteractionKind: action?["kind"]?.stringValue.flatMap(VisitActionKind.init(rawValue:))
            )
        case "conversation.ended":
            return PersonalTimelineEvent(
                id: id, friendshipID: friendshipID, kind: .conversationSummary,
                occurredAt: occurredAt,
                summary: payload["summary"]?.stringValue,
                conversationID: payload["conversation"]?["id"]?.stringValue.map(ConversationID.init(rawValue:))
            )
        case "letter.delivered":
            return PersonalTimelineEvent(
                id: id, friendshipID: friendshipID, kind: .letterReceived,
                occurredAt: occurredAt, visitID: visitID,
                letterID: payload["letterID"]?.stringValue.map(LetterID.init(rawValue:))
            )
        default:
            return nil
        }
    }

    private func decodePayload<Value: Decodable>(
        _ value: JSONValue?,
        as _: Value.Type
    ) -> Value? {
        guard let value, let data = try? JSONEncoder().encode(value) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try? decoder.decode(Value.self, from: data)
    }
}
