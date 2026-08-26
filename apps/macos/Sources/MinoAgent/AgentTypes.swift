import Foundation
import MinoDomain

public struct AgentFriend: Codable, Equatable, Sendable {
    public let friendshipID: FriendshipID
    public let accountID: AccountID
    public let petID: PetProfileID

    public init(
        friendshipID: FriendshipID,
        accountID: AccountID,
        petID: PetProfileID
    ) {
        self.friendshipID = friendshipID
        self.accountID = accountID
        self.petID = petID
    }
}

public struct AgentIdentity: Codable, Equatable, Sendable {
    public let petID: PetProfileID
    public let ownerAccountID: AccountID
    public let displayName: String
    public let friends: [AgentFriend]
    public let localeIdentifier: String

    public init(
        petID: PetProfileID,
        ownerAccountID: AccountID,
        displayName: String,
        friends: [AgentFriend],
        localeIdentifier: String = "zh-Hans"
    ) {
        self.petID = petID
        self.ownerAccountID = ownerAccountID
        self.displayName = displayName
        self.friends = friends
        self.localeIdentifier = localeIdentifier
    }

    public func friend(withPetID petID: PetProfileID) -> AgentFriend? {
        friends.first { $0.petID == petID }
    }
}

public enum PetLogicalLocation: Equatable, Sendable {
    case home
    case visiting(PetVisitID)
}

extension PetLogicalLocation: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case visitID
    }

    private enum Kind: String, Codable {
        case home
        case visiting
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .home:
            self = .home
        case .visiting:
            self = .visiting(try container.decode(PetVisitID.self, forKey: .visitID))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .home:
            try container.encode(Kind.home, forKey: .type)
        case let .visiting(visitID):
            try container.encode(Kind.visiting, forKey: .type)
            try container.encode(visitID, forKey: .visitID)
        }
    }
}

public struct AgentPetState: Codable, Equatable, Sendable {
    public var location: PetLogicalLocation
    public var emotion: PetEmotion
    public var autonomousSocialEnabled: Bool
    public var ownerPresence: OwnerPresence
    public var ownerActivity: OwnerActivity
    public var companionPresent: Bool
    public var publicCare: PublicPetCareSummary?

    public init(
        location: PetLogicalLocation = .home,
        emotion: PetEmotion = .content,
        autonomousSocialEnabled: Bool = true,
        ownerPresence: OwnerPresence = .unknown,
        ownerActivity: OwnerActivity = .idle,
        companionPresent: Bool = false,
        publicCare: PublicPetCareSummary? = nil
    ) {
        self.location = location
        self.emotion = emotion
        self.autonomousSocialEnabled = autonomousSocialEnabled
        self.ownerPresence = ownerPresence
        self.ownerActivity = ownerActivity
        self.companionPresent = companionPresent
        self.publicCare = publicCare
    }

    /// Copies the visible desktop situation into Agent state. Does not enqueue
    /// a model turn — callers decide when an observation is worth inferring.
    public mutating func applyVisibleSituation(_ situation: PetSituation) {
        emotion = situation.emotion
        ownerPresence = situation.owner.presence
        ownerActivity = situation.owner.activity
        companionPresent = situation.companionPresent
        publicCare = situation.care.publicSummary
    }
}

public enum PetInteractionStimulus: Equatable, Sendable {
    case feeding(foodName: String?)
    case play
    case message(text: String)
}

public enum AgentObservationKind: Equatable, Sendable {
    case ownerMessage(text: String)
    case ownerInteraction(PetInteractionStimulus)
    case remoteHumanMessage(senderAccountID: AccountID, text: String)
    case petMessage(senderPetID: PetProfileID, text: String)
    case conversationEnded(conversationID: ConversationID, transcript: [String])
    case visitInvitation(
        invitationID: PetVisitInvitationID,
        senderPetID: PetProfileID,
        reason: String?
    )
    case visitInteraction(
        visitID: PetVisitID,
        actorAccountID: AccountID,
        stimulus: PetInteractionStimulus
    )
    case visitStarted(visitID: PetVisitID, hostAccountID: AccountID)
    case visitEnded(visitID: PetVisitID)
    /// The body is intentionally absent. Sealed human letters must never enter model context.
    case sealedHumanLetterAvailable(senderAccountID: AccountID)
    case periodicWake
}

public struct AgentObservation: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let occurredAt: Date
    public let kind: AgentObservationKind

    public init(
        id: UUID = UUID(),
        occurredAt: Date = Date(),
        kind: AgentObservationKind
    ) {
        self.id = id
        self.occurredAt = occurredAt
        self.kind = kind
    }
}

public enum PetVisitDecision: String, Codable, CaseIterable, Sendable {
    case accept
    case decline
}

public enum PetReaction: String, Codable, CaseIterable, Sendable {
    case happy
    case excited
    case shy
    case sleepy
    case grateful
    case playful
    case resting
}

public enum PetActionKind: String, Codable, CaseIterable, Sendable {
    case idle
    case speakToOwner = "speak_to_owner"
    case sendPetMessage = "send_pet_message"
    case proposeVisit = "propose_visit"
    case respondToVisit = "respond_to_visit"
    case reactToInteraction = "react_to_interaction"
    case requestReturn = "request_return"
}

public enum PetAction: Equatable, Sendable {
    case idle
    case speakToOwner(String)
    case sendPetMessage(petID: PetProfileID, text: String)
    case proposeVisit(petID: PetProfileID, reason: String)
    case respondToVisit(invitationID: PetVisitInvitationID, decision: PetVisitDecision)
    case reactToInteraction(PetReaction)
    case requestReturn(visitID: PetVisitID)

    public var kind: PetActionKind {
        switch self {
        case .idle: .idle
        case .speakToOwner: .speakToOwner
        case .sendPetMessage: .sendPetMessage
        case .proposeVisit: .proposeVisit
        case .respondToVisit: .respondToVisit
        case .reactToInteraction: .reactToInteraction
        case .requestReturn: .requestReturn
        }
    }
}

extension PetAction: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case petID
        case reason
        case invitationID
        case decision
        case reaction
        case visitID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(PetActionKind.self, forKey: .type) {
        case .idle:
            self = .idle
        case .speakToOwner:
            self = .speakToOwner(try container.decode(String.self, forKey: .text))
        case .sendPetMessage:
            self = .sendPetMessage(
                petID: try container.decode(PetProfileID.self, forKey: .petID),
                text: try container.decode(String.self, forKey: .text)
            )
        case .proposeVisit:
            self = .proposeVisit(
                petID: try container.decode(PetProfileID.self, forKey: .petID),
                reason: try container.decode(String.self, forKey: .reason)
            )
        case .respondToVisit:
            self = .respondToVisit(
                invitationID: try container.decode(PetVisitInvitationID.self, forKey: .invitationID),
                decision: try container.decode(PetVisitDecision.self, forKey: .decision)
            )
        case .reactToInteraction:
            self = .reactToInteraction(
                try container.decode(PetReaction.self, forKey: .reaction)
            )
        case .requestReturn:
            self = .requestReturn(
                visitID: try container.decode(PetVisitID.self, forKey: .visitID)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .type)
        switch self {
        case .idle:
            break
        case let .speakToOwner(text):
            try container.encode(text, forKey: .text)
        case let .sendPetMessage(petID, text):
            try container.encode(petID, forKey: .petID)
            try container.encode(text, forKey: .text)
        case let .proposeVisit(petID, reason):
            try container.encode(petID, forKey: .petID)
            try container.encode(reason, forKey: .reason)
        case let .respondToVisit(invitationID, decision):
            try container.encode(invitationID, forKey: .invitationID)
            try container.encode(decision, forKey: .decision)
        case let .reactToInteraction(reaction):
            try container.encode(reaction, forKey: .reaction)
        case let .requestReturn(visitID):
            try container.encode(visitID, forKey: .visitID)
        }
    }
}

public struct PetDecision: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let action: PetAction
    /// A short, user-visible motivation. This must never contain hidden reasoning.
    public let publicReason: String?

    public init(
        schemaVersion: Int = PetDecision.currentSchemaVersion,
        action: PetAction,
        publicReason: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.action = action
        self.publicReason = publicReason
    }

    public static let idle = PetDecision(action: .idle)
}

public enum MemoryDisposition: Equatable, Sendable {
    case discard
    case session
    case longTerm(summary: String, reason: String)
}

extension MemoryDisposition: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case summary
        case reason
    }

    private enum Kind: String, Codable {
        case discard
        case session
        case longTerm = "long_term"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .discard:
            self = .discard
        case .session:
            self = .session
        case .longTerm:
            self = .longTerm(
                summary: try container.decode(String.self, forKey: .summary),
                reason: try container.decode(String.self, forKey: .reason)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .discard:
            try container.encode(Kind.discard, forKey: .type)
        case .session:
            try container.encode(Kind.session, forKey: .type)
        case let .longTerm(summary, reason):
            try container.encode(Kind.longTerm, forKey: .type)
            try container.encode(summary, forKey: .summary)
            try container.encode(reason, forKey: .reason)
        }
    }
}

public enum AgentMemoryCategory: String, CaseIterable, Sendable {
    case owner
    case friendPet = "friend_pet"
    case visit
    case interaction
    case general
}

extension AgentMemoryCategory: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        self = value == "partner_pet"
            ? .friendPet
            : (AgentMemoryCategory(rawValue: value) ?? .general)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct AgentMemory: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let petID: PetProfileID
    public let category: AgentMemoryCategory
    public let summary: String
    public let reason: String
    public let relatedPetIDs: [PetProfileID]
    public let sourceObservationID: UUID
    public let importance: Double
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        petID: PetProfileID,
        category: AgentMemoryCategory,
        summary: String,
        reason: String,
        relatedPetIDs: [PetProfileID] = [],
        sourceObservationID: UUID,
        importance: Double = 0.5,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.petID = petID
        self.category = category
        self.summary = summary
        self.reason = reason
        self.relatedPetIDs = relatedPetIDs
        self.sourceObservationID = sourceObservationID
        self.importance = min(max(importance, 0), 1)
        self.createdAt = createdAt
    }
}

public struct AgentMemoryQuery: Equatable, Sendable {
    public let petID: PetProfileID
    public let relatedPetID: PetProfileID?
    public let categories: Set<AgentMemoryCategory>
    public let terms: [String]
    public let limit: Int

    public init(
        petID: PetProfileID,
        relatedPetID: PetProfileID? = nil,
        categories: Set<AgentMemoryCategory> = [],
        terms: [String] = [],
        limit: Int = 12
    ) {
        self.petID = petID
        self.relatedPetID = relatedPetID
        self.categories = categories
        self.terms = terms
        self.limit = max(0, limit)
    }
}

public enum AgentFallbackReason: String, Codable, Equatable, Sendable {
    case modelUnavailable = "model_unavailable"
    case invalidModelOutput = "invalid_model_output"
    case policyRejected = "policy_rejected"
}

public enum AgentMemoryPersistence: Equatable, Sendable {
    case notRequested
    case sessionOnly
    case stored(UUID)
    case failed
}

public struct AgentTurnResult: Equatable, Sendable {
    public let observationID: UUID
    public let decision: PetDecision
    public let memoryDisposition: MemoryDisposition
    public let memoryPersistence: AgentMemoryPersistence
    public let fallbackReason: AgentFallbackReason?

    public init(
        observationID: UUID,
        decision: PetDecision,
        memoryDisposition: MemoryDisposition,
        memoryPersistence: AgentMemoryPersistence,
        fallbackReason: AgentFallbackReason? = nil
    ) {
        self.observationID = observationID
        self.decision = decision
        self.memoryDisposition = memoryDisposition
        self.memoryPersistence = memoryPersistence
        self.fallbackReason = fallbackReason
    }
}
