import Foundation

public struct PetVisitID: RawRepresentable, Codable, Hashable, Sendable {
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

public struct PetItemID: RawRepresentable, Codable, Hashable, Sendable {
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

public enum PetCargoKind: String, Codable, CaseIterable, Sendable {
    case gift
    case keepsake
    case consumable
    case letter
    case custom
}

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

public enum PetPresencePhase: String, Codable, CaseIterable, Sendable {
    case atHome = "at_home"
    case outbound
    case visiting
    case returning
}

public enum PetPresenceInvariantError: Error, Equatable, Sendable {
    case homeMustBeOwnedByCurrentHost
    case homeCannotHaveActiveVisit
    case transitCannotHaveCurrentHost
    case activeVisitRequired
    case visitHostRequired
    case visitHostCannotBeOwner
}

public struct PetPresenceRecord: Codable, Equatable, Sendable {
    public let petID: PetProfileID
    public let ownerAccountID: AccountID
    public let phase: PetPresencePhase
    public let currentHostAccountID: AccountID?
    public let activeVisitID: PetVisitID?
    public let revision: Int64
    public let updatedAt: Date

    public init(
        petID: PetProfileID,
        ownerAccountID: AccountID,
        phase: PetPresencePhase,
        currentHostAccountID: AccountID?,
        activeVisitID: PetVisitID?,
        revision: Int64,
        updatedAt: Date
    ) throws {
        switch phase {
        case .atHome:
            guard currentHostAccountID == ownerAccountID else {
                throw PetPresenceInvariantError.homeMustBeOwnedByCurrentHost
            }
            guard activeVisitID == nil else {
                throw PetPresenceInvariantError.homeCannotHaveActiveVisit
            }

        case .outbound, .returning:
            guard currentHostAccountID == nil else {
                throw PetPresenceInvariantError.transitCannotHaveCurrentHost
            }
            guard activeVisitID != nil else {
                throw PetPresenceInvariantError.activeVisitRequired
            }

        case .visiting:
            switch (currentHostAccountID, activeVisitID) {
            case (nil, nil):
                // The pet is visiting through another friendship. The server
                // intentionally redacts that friendship's host and visit IDs.
                break
            case let (currentHostAccountID?, activeVisitID?):
                guard currentHostAccountID != ownerAccountID else {
                    throw PetPresenceInvariantError.visitHostCannotBeOwner
                }
                _ = activeVisitID
            case (nil, _?):
                throw PetPresenceInvariantError.visitHostRequired
            case (_?, nil):
                throw PetPresenceInvariantError.activeVisitRequired
            }
        }

        self.petID = petID
        self.ownerAccountID = ownerAccountID
        self.phase = phase
        self.currentHostAccountID = currentHostAccountID
        self.activeVisitID = activeVisitID
        self.revision = revision
        self.updatedAt = updatedAt
    }

    public func isVisible(on accountID: AccountID) -> Bool {
        currentHostAccountID == accountID
    }

    private enum CodingKeys: String, CodingKey {
        case petID
        case ownerAccountID
        case phase
        case currentHostAccountID
        case activeVisitID
        case revision
        case updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            petID: container.decode(PetProfileID.self, forKey: .petID),
            ownerAccountID: container.decode(AccountID.self, forKey: .ownerAccountID),
            phase: container.decode(PetPresencePhase.self, forKey: .phase),
            currentHostAccountID: container.decodeIfPresent(AccountID.self, forKey: .currentHostAccountID),
            activeVisitID: container.decodeIfPresent(PetVisitID.self, forKey: .activeVisitID),
            revision: container.decode(Int64.self, forKey: .revision),
            updatedAt: container.decode(Date.self, forKey: .updatedAt)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(petID, forKey: .petID)
        try container.encode(ownerAccountID, forKey: .ownerAccountID)
        try container.encode(phase, forKey: .phase)
        try container.encodeIfPresent(currentHostAccountID, forKey: .currentHostAccountID)
        try container.encodeIfPresent(activeVisitID, forKey: .activeVisitID)
        try container.encode(revision, forKey: .revision)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

public enum PetVisitPhase: String, Codable, CaseIterable, Sendable {
    case outbound
    case visiting
    case returning
    case completed
    case cancelled
}

public struct PetVisitJourney: Codable, Equatable, Sendable {
    public let id: PetVisitID
    public let coupleID: CoupleID
    public let petID: PetProfileID
    public let ownerAccountID: AccountID
    public let hostAccountID: AccountID
    public let phase: PetVisitPhase
    public let outboundCargo: [PetCargoItem]
    public let returnCargo: [PetCargoItem]
    public let revision: Int64
    public let departedAt: Date
    public let arrivedAt: Date?
    public let returnStartedAt: Date?
    public let completedAt: Date?

    public init(
        id: PetVisitID,
        coupleID: CoupleID,
        petID: PetProfileID,
        ownerAccountID: AccountID,
        hostAccountID: AccountID,
        phase: PetVisitPhase,
        outboundCargo: [PetCargoItem],
        returnCargo: [PetCargoItem],
        revision: Int64,
        departedAt: Date,
        arrivedAt: Date? = nil,
        returnStartedAt: Date? = nil,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.coupleID = coupleID
        self.petID = petID
        self.ownerAccountID = ownerAccountID
        self.hostAccountID = hostAccountID
        self.phase = phase
        self.outboundCargo = outboundCargo
        self.returnCargo = returnCargo
        self.revision = revision
        self.departedAt = departedAt
        self.arrivedAt = arrivedAt
        self.returnStartedAt = returnStartedAt
        self.completedAt = completedAt
    }
}

public enum PetPresenceSnapshotInvariantError: Error, Equatable, Sendable {
    case duplicatePet(PetProfileID)
    case duplicateVisit(PetVisitID)
    case missingActiveVisit(PetVisitID)
    case visitPetMismatch(PetVisitID)
    case missingPresenceForVisit(PetVisitID)
}

public struct PetPresenceSnapshot: Codable, Equatable, Sendable {
    public let coupleID: CoupleID
    public let pets: [PetPresenceRecord]
    public let activeVisits: [PetVisitJourney]
    public let serverCursor: String?
    public let syncedAt: Date

    public init(
        coupleID: CoupleID,
        pets: [PetPresenceRecord],
        activeVisits: [PetVisitJourney],
        serverCursor: String?,
        syncedAt: Date
    ) throws {
        var petIDs = Set<PetProfileID>()
        for pet in pets where !petIDs.insert(pet.petID).inserted {
            throw PetPresenceSnapshotInvariantError.duplicatePet(pet.petID)
        }

        var visitsByID: [PetVisitID: PetVisitJourney] = [:]
        for visit in activeVisits {
            guard visitsByID.updateValue(visit, forKey: visit.id) == nil else {
                throw PetPresenceSnapshotInvariantError.duplicateVisit(visit.id)
            }
        }

        for pet in pets {
            guard let activeVisitID = pet.activeVisitID else { continue }
            guard let visit = visitsByID[activeVisitID] else {
                throw PetPresenceSnapshotInvariantError.missingActiveVisit(activeVisitID)
            }
            guard visit.petID == pet.petID else {
                throw PetPresenceSnapshotInvariantError.visitPetMismatch(activeVisitID)
            }
        }

        for visit in activeVisits where !petIDs.contains(visit.petID) {
            throw PetPresenceSnapshotInvariantError.missingPresenceForVisit(visit.id)
        }

        self.coupleID = coupleID
        self.pets = pets
        self.activeVisits = activeVisits
        self.serverCursor = serverCursor
        self.syncedAt = syncedAt
    }

    public func visiblePets(on accountID: AccountID) -> [PetPresenceRecord] {
        pets.filter { $0.isVisible(on: accountID) }
    }

    private enum CodingKeys: String, CodingKey {
        case coupleID
        case pets
        case activeVisits
        case serverCursor
        case syncedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            coupleID: container.decode(CoupleID.self, forKey: .coupleID),
            pets: container.decode([PetPresenceRecord].self, forKey: .pets),
            activeVisits: container.decode([PetVisitJourney].self, forKey: .activeVisits),
            serverCursor: container.decodeIfPresent(String.self, forKey: .serverCursor),
            syncedAt: container.decode(Date.self, forKey: .syncedAt)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(coupleID, forKey: .coupleID)
        try container.encode(pets, forKey: .pets)
        try container.encode(activeVisits, forKey: .activeVisits)
        try container.encodeIfPresent(serverCursor, forKey: .serverCursor)
        try container.encode(syncedAt, forKey: .syncedAt)
    }
}

public struct StartPetVisitCommand: Codable, Equatable, Sendable {
    public let idempotencyKey: UUID
    public let petID: PetProfileID
    public let destinationAccountID: AccountID
    public let outboundCargo: [PetCargoItem]
    public let expectedPresenceRevision: Int64
    public let clientCreatedAt: Date

    public init(
        idempotencyKey: UUID = UUID(),
        petID: PetProfileID,
        destinationAccountID: AccountID,
        outboundCargo: [PetCargoItem] = [],
        expectedPresenceRevision: Int64,
        clientCreatedAt: Date = Date()
    ) {
        self.idempotencyKey = idempotencyKey
        self.petID = petID
        self.destinationAccountID = destinationAccountID
        self.outboundCargo = outboundCargo
        self.expectedPresenceRevision = expectedPresenceRevision
        self.clientCreatedAt = clientCreatedAt
    }
}

public struct ReturnPetVisitCommand: Codable, Equatable, Sendable {
    public let idempotencyKey: UUID
    public let visitID: PetVisitID
    public let returnCargo: [PetCargoItem]
    public let expectedVisitRevision: Int64
    public let clientCreatedAt: Date

    public init(
        idempotencyKey: UUID = UUID(),
        visitID: PetVisitID,
        returnCargo: [PetCargoItem] = [],
        expectedVisitRevision: Int64,
        clientCreatedAt: Date = Date()
    ) {
        self.idempotencyKey = idempotencyKey
        self.visitID = visitID
        self.returnCargo = returnCargo
        self.expectedVisitRevision = expectedVisitRevision
        self.clientCreatedAt = clientCreatedAt
    }
}

public struct PetVisitReceipt: Codable, Equatable, Sendable {
    public let visit: PetVisitJourney
    public let presence: PetPresenceRecord
    public let acceptedAt: Date

    public init(visit: PetVisitJourney, presence: PetPresenceRecord, acceptedAt: Date) {
        self.visit = visit
        self.presence = presence
        self.acceptedAt = acceptedAt
    }
}

public struct PetVisitInvitationID: RawRepresentable, Codable, Hashable, Sendable {
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

public enum PetVisitInvitationStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case accepted
    case declined
    case cancelled
    case expired
}

public struct PetVisitInvitation: Codable, Equatable, Sendable {
    public let id: PetVisitInvitationID
    public let coupleID: CoupleID
    public let inviterAccountID: AccountID
    public let invitedAccountID: AccountID
    public let requestedPetID: PetProfileID
    public let hostAccountID: AccountID
    public let status: PetVisitInvitationStatus
    public let createdAt: Date
    public let respondedAt: Date?

    public init(
        id: PetVisitInvitationID,
        coupleID: CoupleID,
        inviterAccountID: AccountID,
        invitedAccountID: AccountID,
        requestedPetID: PetProfileID,
        hostAccountID: AccountID,
        status: PetVisitInvitationStatus,
        createdAt: Date,
        respondedAt: Date? = nil
    ) {
        self.id = id
        self.coupleID = coupleID
        self.inviterAccountID = inviterAccountID
        self.invitedAccountID = invitedAccountID
        self.requestedPetID = requestedPetID
        self.hostAccountID = hostAccountID
        self.status = status
        self.createdAt = createdAt
        self.respondedAt = respondedAt
    }
}

public struct SendPetVisitInvitationCommand: Codable, Equatable, Sendable {
    public let idempotencyKey: UUID
    public let requestedPetID: PetProfileID
    public let clientCreatedAt: Date

    public init(
        idempotencyKey: UUID = UUID(),
        requestedPetID: PetProfileID,
        clientCreatedAt: Date = Date()
    ) {
        self.idempotencyKey = idempotencyKey
        self.requestedPetID = requestedPetID
        self.clientCreatedAt = clientCreatedAt
    }
}

public enum PetVisitInvitationResponse: String, Codable, Sendable {
    case accept
    case decline
}

public struct RespondToPetVisitInvitationCommand: Codable, Equatable, Sendable {
    public let idempotencyKey: UUID
    public let invitationID: PetVisitInvitationID
    public let response: PetVisitInvitationResponse
    public let expectedPresenceRevision: Int64
    public let clientCreatedAt: Date

    public init(
        idempotencyKey: UUID = UUID(),
        invitationID: PetVisitInvitationID,
        response: PetVisitInvitationResponse,
        expectedPresenceRevision: Int64,
        clientCreatedAt: Date = Date()
    ) {
        self.idempotencyKey = idempotencyKey
        self.invitationID = invitationID
        self.response = response
        self.expectedPresenceRevision = expectedPresenceRevision
        self.clientCreatedAt = clientCreatedAt
    }
}

public struct PetVisitInvitationReceipt: Codable, Equatable, Sendable {
    public let invitation: PetVisitInvitation
    public let visit: PetVisitJourney?
    public let presence: PetPresenceRecord?
    public let acceptedAt: Date

    public init(
        invitation: PetVisitInvitation,
        visit: PetVisitJourney? = nil,
        presence: PetPresenceRecord? = nil,
        acceptedAt: Date
    ) {
        self.invitation = invitation
        self.visit = visit
        self.presence = presence
        self.acceptedAt = acceptedAt
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
    public let visitInteractionKind: VisitInteractionKind?
    public let cargoItems: [PetCargoItem]
    public let postcard: PetPostcard?
    public let summary: String?
    public let letterID: LetterID?
    public let conversationID: ConversationID?

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
        visitInteractionKind: VisitInteractionKind? = nil,
        cargoItems: [PetCargoItem] = [],
        postcard: PetPostcard? = nil,
        summary: String? = nil,
        letterID: LetterID? = nil,
        conversationID: ConversationID? = nil
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
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case friendshipID
        case kind
        case occurredAt
        case petID
        case visitID
        case invitationID
        case actorAccountID
        case interactionKind
        case visitInteractionKind
        case cargoItems
        case postcard
        case summary
        case letterID
        case conversationID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            friendshipID: try container.decodeIfPresent(
                FriendshipID.self,
                forKey: .friendshipID
            ),
            kind: try container.decode(PersonalTimelineEventKind.self, forKey: .kind),
            occurredAt: try container.decode(Date.self, forKey: .occurredAt),
            petID: try container.decodeIfPresent(PetProfileID.self, forKey: .petID),
            visitID: try container.decodeIfPresent(PetVisitID.self, forKey: .visitID),
            invitationID: try container.decodeIfPresent(PetVisitInvitationID.self, forKey: .invitationID),
            actorAccountID: try container.decodeIfPresent(AccountID.self, forKey: .actorAccountID),
            interactionKind: try container.decodeIfPresent(PetInteractionKind.self, forKey: .interactionKind),
            visitInteractionKind: try container.decodeIfPresent(VisitInteractionKind.self, forKey: .visitInteractionKind),
            cargoItems: try container.decodeIfPresent([PetCargoItem].self, forKey: .cargoItems) ?? [],
            postcard: try container.decodeIfPresent(PetPostcard.self, forKey: .postcard),
            summary: try container.decodeIfPresent(String.self, forKey: .summary),
            letterID: try container.decodeIfPresent(LetterID.self, forKey: .letterID),
            conversationID: try container.decodeIfPresent(ConversationID.self, forKey: .conversationID)
        )
    }
}

public struct PersonalTimelinePage: Codable, Equatable, Sendable {
    public let events: [PersonalTimelineEvent]
    public let nextCursor: String?

    public init(events: [PersonalTimelineEvent], nextCursor: String?) {
        self.events = events
        self.nextCursor = nextCursor
    }
}

public protocol PersonalTimelineStore: Sendable {
    func load() async throws -> [PersonalTimelineEvent]
    func append(_ event: PersonalTimelineEvent) async throws
    func merge(_ events: [PersonalTimelineEvent]) async throws
    func clear() async throws
}

@available(*, deprecated, renamed: "PersonalTimelineEventKind")
public typealias CoupleTimelineEventKind = PersonalTimelineEventKind

@available(*, deprecated, renamed: "PersonalTimelineEvent")
public typealias CoupleTimelineEvent = PersonalTimelineEvent

@available(*, deprecated, renamed: "PersonalTimelinePage")
public typealias CoupleTimelinePage = PersonalTimelinePage

@available(*, deprecated, renamed: "PersonalTimelineStore")
public typealias CoupleTimelineStore = PersonalTimelineStore
