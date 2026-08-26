import Foundation
import MinoDomain

/// Owns optimistic care values, cooldowns and owner context for desktop pet slots.
///
/// AppDelegate decides *whether* an interaction is allowed (visit visibility,
/// rest is owner-only) and plays the result. This type is the single in-memory
/// source of care numbers so rapid clicks and server receipts cannot clobber
/// each other through copied fields.
@MainActor
final class PetCareSession {
    struct AppliedInteraction: Equatable {
        let generation: UInt64
        let petSlot: PetID
        let kind: PetCareInteractionKind
        let occurredAt: Date
        let interactionID: UUID
        let relationship: PetInteractionActorRelationship
        let source: PetCareState
        let transition: PetCareTransition
        let previousRestAt: Date?
        let context: PetReactionContext
    }

    private(set) var ownerContext: OwnerContext
    private var careStates: [PetID: PetCareState]
    private var recentCareInteractions: [PetID: (kind: PetCareInteractionKind, at: Date, count: Int)] = [:]
    private var recentRestAt: [PetID: Date] = [:]
    private var generationBySlot: [PetID: UInt64] = [:]

    init(
        careStates: [PetID: PetCareState] = [
            .mine: PetCareState(),
            .partner: PetCareState()
        ],
        ownerContext: OwnerContext = .unknown
    ) {
        self.careStates = careStates
        self.ownerContext = ownerContext
    }

    func care(for slot: PetID) -> PetCareState {
        careStates[slot] ?? PetCareState()
    }

    func situation(
        for slot: PetID,
        activity: PetActivity,
        emotion: PetEmotion,
        companionPresent: Bool
    ) -> PetSituation {
        PetSituation(
            slot: slot,
            care: care(for: slot),
            activity: activity,
            emotion: emotion,
            owner: ownerContext,
            companionPresent: companionPresent
        )
    }

    func updateOwner(_ context: OwnerContext) {
        ownerContext = context
    }

    /// Authoritative replacement from bootstrap or `pet.care.updated`.
    /// Bumps generation so an in-flight optimistic rollback cannot overwrite it.
    func replaceCare(_ state: PetCareState, for slot: PetID) {
        careStates[slot] = state
        bumpGeneration(for: slot)
    }

    func applyLocal(
        _ kind: PetCareInteractionKind,
        for slot: PetID,
        relationship: PetInteractionActorRelationship,
        familiarityTier: PetFamiliarityTier?,
        companionPresent: Bool,
        partnerPublicCare: PublicPetCareSummary? = nil,
        at date: Date = Date(),
        interactionID: UUID = UUID()
    ) -> AppliedInteraction {
        let previous = recentCareInteractions[slot]
        let repeated = previous?.kind == kind
            && date.timeIntervalSince(previous?.at ?? .distantPast) < 30
        let repeatCount = repeated ? (previous?.count ?? 0) + 1 : 0
        recentCareInteractions[slot] = (kind, date, repeatCount)

        let source = resolvedCare(for: slot, at: date, partnerPublicCare: partnerPublicCare)
        let previousRestAt = recentRestAt[slot]
        let restOnCooldown = kind == .rest
            && date.timeIntervalSince(previousRestAt ?? .distantPast) < 3_600
        let transition = PetCareRules.transition(
            state: source,
            kind: kind,
            relationship: relationship,
            repeatedWithinCooldown: repeated,
            restOnCooldown: restOnCooldown,
            at: date
        )
        if kind == .rest, transition.outcome == .applied {
            recentRestAt[slot] = date
        }
        careStates[slot] = transition.state
        let generation = bumpGeneration(for: slot)
        let context = PetReactionContext(
            interactionID: interactionID,
            kind: kind,
            relationship: relationship,
            state: transition.state,
            outcome: transition.outcome,
            effect: transition.effect,
            familiarityTier: familiarityTier,
            recentRepeatCount: repeatCount,
            occurredAt: date,
            owner: ownerContext,
            companionPresent: companionPresent
        )
        return AppliedInteraction(
            generation: generation,
            petSlot: slot,
            kind: kind,
            occurredAt: date,
            interactionID: interactionID,
            relationship: relationship,
            source: source,
            transition: transition,
            previousRestAt: previousRestAt,
            context: context
        )
    }

    /// Restores the pre-interaction care only when this application is still current.
    @discardableResult
    func rollback(_ applied: AppliedInteraction) -> Bool {
        guard generationBySlot[applied.petSlot] == applied.generation else { return false }
        careStates[applied.petSlot] = applied.source
        if applied.kind == .rest, applied.transition.outcome == .applied {
            recentRestAt[applied.petSlot] = applied.previousRestAt
        }
        return true
    }

    /// Applies a server receipt only when this application is still current.
    @discardableResult
    func reconcile(_ receipt: PetInteractionReceipt, applying applied: AppliedInteraction) -> Bool {
        guard generationBySlot[applied.petSlot] == applied.generation else { return false }
        if let careState = receipt.careState {
            careStates[applied.petSlot] = careState
        } else if applied.petSlot == .partner {
            careStates[.partner] = Self.care(from: receipt.publicCare, at: receipt.occurredAt)
        }
        return true
    }

    private func resolvedCare(
        for slot: PetID,
        at date: Date,
        partnerPublicCare: PublicPetCareSummary?
    ) -> PetCareState {
        if let state = careStates[slot] { return state.evaluated(at: date) }
        guard slot == .partner, let summary = partnerPublicCare else {
            return PetCareState(evaluatedAt: date)
        }
        return Self.care(from: summary, at: date)
    }

    @discardableResult
    private func bumpGeneration(for slot: PetID) -> UInt64 {
        let value = (generationBySlot[slot] ?? 0) + 1
        generationBySlot[slot] = value
        return value
    }

    static func care(from summary: PublicPetCareSummary, at date: Date = Date()) -> PetCareState {
        PetCareState(
            fullness: representativeValue(summary.fullness),
            energy: representativeValue(summary.energy),
            mood: representativeValue(summary.mood),
            evaluatedAt: date
        )
    }

    static func representativeValue(_ band: PetCareBand) -> Int {
        switch band {
        case .low: 24
        case .steady: 54
        case .high: 82
        }
    }
}
