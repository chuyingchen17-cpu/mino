import Foundation
import MinoDomain
import Testing
@testable import MinoApp

@MainActor
@Test
func careSessionAppliesOptimisticStateAndExposesOwnerAwareContext() {
    let session = PetCareSession()
    let at = Date(timeIntervalSince1970: 5_000)
    session.updateOwner(
        OwnerContext(presence: .present, activity: .listeningToMusic(title: "Rain"), updatedAt: at)
    )

    let applied = session.applyLocal(
        .feed,
        for: .mine,
        relationship: .owner,
        familiarityTier: nil,
        companionPresent: true,
        at: at,
        interactionID: UUID(uuidString: "00000000-0000-4000-8000-000000000010")!
    )

    #expect(applied.transition.outcome == .applied)
    #expect(session.care(for: .mine).fullness == 90)
    #expect(applied.context.owner.presence == .present)
    #expect(applied.context.companionPresent)
    if case .listeningToMusic(let title) = applied.context.owner.activity {
        #expect(title == "Rain")
    } else {
        Issue.record("Owner activity should flow into the reaction context")
    }
}

@MainActor
@Test
func careSessionIgnoresStaleRollbackAfterANewerInteraction() {
    let session = PetCareSession(
        careStates: [.mine: PetCareState(fullness: 40, energy: 80, mood: 70, bond: 10)]
    )
    let firstAt = Date(timeIntervalSince1970: 8_000)
    let secondAt = firstAt.addingTimeInterval(31)
    let first = session.applyLocal(
        .feed,
        for: .mine,
        relationship: .owner,
        familiarityTier: nil,
        companionPresent: false,
        at: firstAt
    )
    let second = session.applyLocal(
        .feed,
        for: .mine,
        relationship: .owner,
        familiarityTier: nil,
        companionPresent: false,
        at: secondAt
    )

    #expect(session.care(for: .mine).fullness == 80)
    #expect(!session.rollback(first))
    #expect(session.care(for: .mine).fullness == 80)
    #expect(session.rollback(second))
    #expect(session.care(for: .mine).fullness == 60)
}

@MainActor
@Test
func authoritativeReplacePreventsInFlightRollbackFromWinning() {
    let session = PetCareSession(
        careStates: [.mine: PetCareState(fullness: 40, energy: 80, mood: 70, bond: 10)]
    )
    let applied = session.applyLocal(
        .play,
        for: .mine,
        relationship: .owner,
        familiarityTier: nil,
        companionPresent: false,
        at: Date(timeIntervalSince1970: 9_000)
    )
    session.replaceCare(
        PetCareState(fullness: 12, energy: 8, mood: 40, bond: 10, version: 9),
        for: .mine
    )

    #expect(!session.rollback(applied))
    #expect(session.care(for: .mine).fullness == 12)
}

@MainActor
@Test
func situationSnapshotIsTheSingleReadModelForAgentAndReactions() {
    let session = PetCareSession()
    session.updateOwner(OwnerContext(presence: .away, activity: .idle, updatedAt: Date()))
    let situation = session.situation(
        for: .mine,
        activity: .walking,
        emotion: .excited,
        companionPresent: true
    )
    #expect(situation.slot == .mine)
    #expect(situation.activity == .walking)
    #expect(situation.owner.presence == .away)
    #expect(situation.companionPresent)
}
