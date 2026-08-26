import Foundation

public enum PetCareBand: String, Codable, CaseIterable, Sendable {
    case low
    case steady
    case high

    public init(value: Int) {
        switch min(max(value, 0), 100) {
        case 0...34: self = .low
        case 35...69: self = .steady
        default: self = .high
        }
    }
}

public struct PetCareState: Codable, Equatable, Sendable {
    public var fullness: Int
    public var energy: Int
    public var mood: Int
    public var bond: Int
    public var version: Int64
    public var evaluatedAt: Date

    public init(
        fullness: Int = 70,
        energy: Int = 80,
        mood: Int = 70,
        bond: Int = 20,
        version: Int64 = 1,
        evaluatedAt: Date = Date()
    ) {
        self.fullness = Self.clamped(fullness)
        self.energy = Self.clamped(energy)
        self.mood = Self.clamped(mood)
        self.bond = Self.clamped(bond)
        self.version = max(1, version)
        self.evaluatedAt = evaluatedAt
    }

    public var publicSummary: PublicPetCareSummary {
        PublicPetCareSummary(
            fullness: PetCareBand(value: fullness),
            energy: PetCareBand(value: energy),
            mood: PetCareBand(value: mood)
        )
    }

    public func evaluated(at date: Date) -> PetCareState {
        guard date > evaluatedAt else { return self }
        let elapsedDays = date.timeIntervalSince(evaluatedAt) / 86_400
        var value = self
        value.fullness = max(35, fullness - Int(floor(elapsedDays * 20)))
        value.energy = min(85, energy + Int(floor(elapsedDays * 20)))
        let moodShift = Int(floor(elapsedDays * 10))
        if mood > 60 {
            value.mood = max(60, mood - moodShift)
        } else if mood < 60 {
            value.mood = min(60, mood + moodShift)
        }
        value.evaluatedAt = date
        return value
    }

    public mutating func clamp() {
        fullness = Self.clamped(fullness)
        energy = Self.clamped(energy)
        mood = Self.clamped(mood)
        bond = Self.clamped(bond)
    }

    private static func clamped(_ value: Int) -> Int {
        min(max(value, 0), 100)
    }
}

public struct PublicPetCareSummary: Codable, Equatable, Sendable {
    public let fullness: PetCareBand
    public let energy: PetCareBand
    public let mood: PetCareBand

    public init(fullness: PetCareBand, energy: PetCareBand, mood: PetCareBand) {
        self.fullness = fullness
        self.energy = energy
        self.mood = mood
    }

    public static let content = PublicPetCareSummary(
        fullness: .steady,
        energy: .steady,
        mood: .steady
    )
}

public enum PetFamiliarityTier: String, Codable, CaseIterable, Sendable {
    case firstMeeting = "first_meeting"
    case recognized
    case familiar
    case close

    public init(score: Int) {
        switch min(max(score, 0), 100) {
        case 0...19: self = .firstMeeting
        case 20...44: self = .recognized
        case 45...74: self = .familiar
        default: self = .close
        }
    }

    public var displayName: String {
        switch self {
        case .firstMeeting: "初见"
        case .recognized: "眼熟"
        case .familiar: "熟悉"
        case .close: "亲近"
        }
    }
}

public struct PetFamiliarity: Codable, Equatable, Sendable {
    public let petID: PetProfileID
    public let friendshipID: FriendshipID
    public var score: Int
    public var version: Int64
    public var updatedAt: Date

    public init(
        petID: PetProfileID,
        friendshipID: FriendshipID,
        score: Int = 0,
        version: Int64 = 1,
        updatedAt: Date = Date()
    ) {
        self.petID = petID
        self.friendshipID = friendshipID
        self.score = min(max(score, 0), 100)
        self.version = max(1, version)
        self.updatedAt = updatedAt
    }

    public var tier: PetFamiliarityTier { PetFamiliarityTier(score: score) }
}

public enum PetCareInteractionKind: String, Codable, CaseIterable, Sendable {
    case pet
    case feed
    case play
    case walk
    case rest
    case cuddle
    case flower
}

public enum PetInteractionActorRelationship: String, Codable, Sendable {
    case owner
    case friend
}

public enum PetInteractionOutcome: String, Codable, Sendable {
    case applied
    case cosmeticOnly = "cosmetic_only"
    case tooFull = "too_full"
    case tooTired = "too_tired"
    case restingCooldown = "resting_cooldown"
}

public struct PetCareEffect: Codable, Equatable, Sendable {
    public let fullness: Int
    public let energy: Int
    public let mood: Int
    public let bond: Int
    public let familiarity: Int

    public init(
        fullness: Int = 0,
        energy: Int = 0,
        mood: Int = 0,
        bond: Int = 0,
        familiarity: Int = 0
    ) {
        self.fullness = fullness
        self.energy = energy
        self.mood = mood
        self.bond = bond
        self.familiarity = familiarity
    }

    public static let none = PetCareEffect()
}

public struct PetCareTransition: Equatable, Sendable {
    public let state: PetCareState
    public let outcome: PetInteractionOutcome
    public let effect: PetCareEffect

    public init(state: PetCareState, outcome: PetInteractionOutcome, effect: PetCareEffect) {
        self.state = state
        self.outcome = outcome
        self.effect = effect
    }
}

public enum PetCareRules {
    public static func transition(
        state source: PetCareState,
        kind: PetCareInteractionKind,
        relationship: PetInteractionActorRelationship,
        repeatedWithinCooldown: Bool = false,
        restOnCooldown: Bool = false,
        relationshipGainRemaining: Int = .max,
        at date: Date = Date()
    ) -> PetCareTransition {
        var state = source.evaluated(at: date)
        guard !repeatedWithinCooldown else {
            return PetCareTransition(state: state, outcome: .cosmeticOnly, effect: .none)
        }

        let base: PetCareEffect
        let outcome: PetInteractionOutcome
        switch kind {
        case .pet:
            base = PetCareEffect(mood: 4, bond: 1, familiarity: 1)
            outcome = .applied
        case .feed where state.fullness >= 90:
            base = .none
            outcome = .tooFull
        case .feed:
            base = PetCareEffect(fullness: 20, mood: 3, bond: 1, familiarity: 1)
            outcome = .applied
        case .play where state.energy < 15:
            base = .none
            outcome = .tooTired
        case .play:
            base = PetCareEffect(energy: -12, mood: 14, bond: 2, familiarity: 2)
            outcome = .applied
        case .walk where state.energy < 25:
            base = .none
            outcome = .tooTired
        case .walk:
            base = PetCareEffect(energy: -18, mood: 12, bond: 2, familiarity: 2)
            outcome = .applied
        case .rest where relationship != .owner:
            base = .none
            outcome = .cosmeticOnly
        case .rest where restOnCooldown:
            base = .none
            outcome = .restingCooldown
        case .rest:
            base = PetCareEffect(energy: 15)
            outcome = .applied
        case .cuddle:
            base = PetCareEffect(mood: 6, bond: 2, familiarity: 2)
            outcome = .applied
        case .flower:
            base = PetCareEffect(mood: 5, bond: 1, familiarity: 1)
            outcome = .applied
        }

        let allowedRelationshipGain = max(0, relationshipGainRemaining)
        let bond = relationship == .owner ? min(base.bond, allowedRelationshipGain) : 0
        let familiarity = relationship == .friend
            ? min(base.familiarity, allowedRelationshipGain)
            : 0
        let applied = PetCareEffect(
            fullness: base.fullness,
            energy: base.energy,
            mood: base.mood,
            bond: bond,
            familiarity: familiarity
        )
        state.fullness += applied.fullness
        state.energy += applied.energy
        state.mood += applied.mood
        state.bond += applied.bond
        state.clamp()
        return PetCareTransition(state: state, outcome: outcome, effect: applied)
    }
}

public struct PetInteractionCommand: Encodable, Equatable, Sendable {
    public let kind: PetCareInteractionKind
    public let visitID: PetVisitID?
    public let occurredAt: Date
    public let idempotencyKey: UUID

    public init(
        kind: PetCareInteractionKind,
        visitID: PetVisitID? = nil,
        occurredAt: Date = Date(),
        idempotencyKey: UUID = UUID()
    ) {
        self.kind = kind
        self.visitID = visitID
        self.occurredAt = occurredAt
        self.idempotencyKey = idempotencyKey
    }

    private enum CodingKeys: String, CodingKey { case kind, visitID, occurredAt }
}

public struct PetInteractionReceipt: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let targetPetID: PetProfileID
    public let actorAccountID: AccountID
    public let friendshipID: FriendshipID?
    public let visitID: PetVisitID?
    public let kind: PetCareInteractionKind
    public let outcome: PetInteractionOutcome
    public let effect: PetCareEffect
    public let careState: PetCareState?
    public let publicCare: PublicPetCareSummary
    public let familiarity: PetFamiliarity?
    public let occurredAt: Date

    public init(
        id: UUID,
        targetPetID: PetProfileID,
        actorAccountID: AccountID,
        friendshipID: FriendshipID? = nil,
        visitID: PetVisitID? = nil,
        kind: PetCareInteractionKind,
        outcome: PetInteractionOutcome,
        effect: PetCareEffect,
        careState: PetCareState? = nil,
        publicCare: PublicPetCareSummary,
        familiarity: PetFamiliarity? = nil,
        occurredAt: Date
    ) {
        self.id = id
        self.targetPetID = targetPetID
        self.actorAccountID = actorAccountID
        self.friendshipID = friendshipID
        self.visitID = visitID
        self.kind = kind
        self.outcome = outcome
        self.effect = effect
        self.careState = careState
        self.publicCare = publicCare
        self.familiarity = familiarity
        self.occurredAt = occurredAt
    }
}

public struct VisitInteractionSummary: Codable, Equatable, Sendable {
    public let counts: [PetCareInteractionKind: Int]
    public let familiarityGained: Int
    public let letterAttached: Bool

    public init(
        counts: [PetCareInteractionKind: Int] = [:],
        familiarityGained: Int = 0,
        letterAttached: Bool = false
    ) {
        self.counts = counts
        self.familiarityGained = max(0, familiarityGained)
        self.letterAttached = letterAttached
    }

    public var isEmpty: Bool {
        counts.values.allSatisfy { $0 == 0 } && familiarityGained == 0 && !letterAttached
    }

    private enum CodingKeys: String, CodingKey {
        case counts, familiarityGained, letterAttached
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let wireCounts = try container.decodeIfPresent([String: Int].self, forKey: .counts) ?? [:]
        self.init(
            counts: Dictionary(uniqueKeysWithValues: wireCounts.compactMap { key, value in
                PetCareInteractionKind(rawValue: key).map { ($0, value) }
            }),
            familiarityGained: try container.decodeIfPresent(Int.self, forKey: .familiarityGained) ?? 0,
            letterAttached: try container.decodeIfPresent(Bool.self, forKey: .letterAttached) ?? false
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(
            Dictionary(uniqueKeysWithValues: counts.map { ($0.key.rawValue, $0.value) }),
            forKey: .counts
        )
        try container.encode(familiarityGained, forKey: .familiarityGained)
        try container.encode(letterAttached, forKey: .letterAttached)
    }
}

public enum PetReactionEffect: String, Codable, Sendable {
    case none
    case heart
    case flower
}

public struct PetReactionContext: Equatable, Sendable {
    public let interactionID: UUID
    public let kind: PetCareInteractionKind
    public let relationship: PetInteractionActorRelationship
    public let state: PetCareState
    public let outcome: PetInteractionOutcome
    public let effect: PetCareEffect
    public let familiarityTier: PetFamiliarityTier?
    public let recentRepeatCount: Int
    public let occurredAt: Date
    public let owner: OwnerContext
    public let companionPresent: Bool

    public init(
        interactionID: UUID,
        kind: PetCareInteractionKind,
        relationship: PetInteractionActorRelationship,
        state: PetCareState,
        outcome: PetInteractionOutcome = .applied,
        effect: PetCareEffect = .none,
        familiarityTier: PetFamiliarityTier? = nil,
        recentRepeatCount: Int = 0,
        occurredAt: Date = Date(),
        owner: OwnerContext = .unknown,
        companionPresent: Bool = false
    ) {
        self.interactionID = interactionID
        self.kind = kind
        self.relationship = relationship
        self.state = state
        self.outcome = outcome
        self.effect = effect
        self.familiarityTier = familiarityTier
        self.recentRepeatCount = max(0, recentRepeatCount)
        self.occurredAt = occurredAt
        self.owner = owner
        self.companionPresent = companionPresent
    }
}

public struct PetReactionPlan: Equatable, Sendable {
    public let speech: String
    public let activity: PetActivity
    public let emotion: PetEmotion
    public let motionClip: PetMotionClipID?
    public let effect: PetReactionEffect
    public let duration: TimeInterval

    public init(
        speech: String,
        activity: PetActivity,
        emotion: PetEmotion,
        motionClip: PetMotionClipID? = nil,
        effect: PetReactionEffect = .none,
        duration: TimeInterval = 2.4
    ) {
        self.speech = String(speech.prefix(80))
        self.activity = activity
        self.emotion = emotion
        self.motionClip = motionClip
        self.effect = effect
        self.duration = min(max(duration, 0.8), 6)
    }
}

public protocol InteractionResponseProvider: Sendable {
    func response(for context: PetReactionContext) async -> PetReactionPlan
}

public struct AIInteractionEnhancementRequest: Equatable, Sendable {
    public let billingAccountID: AccountID
    public let interactionID: UUID
    public let context: PetReactionContext

    public init(
        billingAccountID: AccountID,
        interactionID: UUID,
        context: PetReactionContext
    ) {
        self.billingAccountID = billingAccountID
        self.interactionID = interactionID
        self.context = context
    }
}
