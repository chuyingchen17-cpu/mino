import Foundation
import MinoDomain
import Testing

@Test
func careStateUsesGentleLazyEvaluation() {
    let start = Date(timeIntervalSince1970: 1_000)
    let state = PetCareState(fullness: 70, energy: 60, mood: 90, bond: 20, evaluatedAt: start)
    let evaluated = state.evaluated(at: start.addingTimeInterval(86_400))

    #expect(evaluated.fullness == 50)
    #expect(evaluated.energy == 80)
    #expect(evaluated.mood == 80)
    #expect(evaluated.bond == 20)
}

@Test
func careRulesApplyThresholdsCooldownAndRelationshipCaps() {
    let date = Date(timeIntervalSince1970: 2_000)
    let full = PetCareRules.transition(
        state: PetCareState(fullness: 92, evaluatedAt: date),
        kind: .feed,
        relationship: .owner,
        at: date
    )
    #expect(full.outcome == .tooFull)
    #expect(full.state.fullness == 92)

    let tired = PetCareRules.transition(
        state: PetCareState(energy: 10, evaluatedAt: date),
        kind: .play,
        relationship: .friend,
        at: date
    )
    #expect(tired.outcome == .tooTired)
    #expect(tired.effect == .none)

    let repeated = PetCareRules.transition(
        state: PetCareState(evaluatedAt: date),
        kind: .pet,
        relationship: .owner,
        repeatedWithinCooldown: true,
        at: date
    )
    #expect(repeated.outcome == .cosmeticOnly)

    let capped = PetCareRules.transition(
        state: PetCareState(bond: 40, evaluatedAt: date),
        kind: .play,
        relationship: .owner,
        relationshipGainRemaining: 1,
        at: date
    )
    #expect(capped.state.bond == 41)
    #expect(capped.effect.bond == 1)
    #expect(capped.effect.familiarity == 0)
}

@Test
func careBandsAndFamiliarityTiersUseStableThresholds() {
    #expect(PetCareBand(value: 34) == .low)
    #expect(PetCareBand(value: 35) == .steady)
    #expect(PetCareBand(value: 70) == .high)
    #expect(PetFamiliarityTier(score: 19) == .firstMeeting)
    #expect(PetFamiliarityTier(score: 20) == .recognized)
    #expect(PetFamiliarityTier(score: 45) == .familiar)
    #expect(PetFamiliarityTier(score: 75) == .close)
}
