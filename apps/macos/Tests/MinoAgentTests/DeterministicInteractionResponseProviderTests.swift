import Foundation
import MinoAgent
import MinoDomain
import Testing

@Test
func deterministicProviderReplaysTheSamePlanWithoutAModel() async {
    let provider = DeterministicInteractionResponseProvider()
    let id = UUID(uuidString: "00000000-0000-4000-8000-000000000123")!
    let context = PetReactionContext(
        interactionID: id,
        kind: .play,
        relationship: .friend,
        state: PetCareState(),
        familiarityTier: .familiar
    )

    let first = await provider.response(for: context)
    let replay = await provider.response(for: context)
    #expect(first == replay)
    #expect(first.activity == .playing)
    #expect(first.emotion == .playful)
}

@Test
func deterministicProviderReflectsCareThresholds() async {
    let provider = DeterministicInteractionResponseProvider()
    let context = PetReactionContext(
        interactionID: UUID(uuidString: "00000000-0000-4000-8000-000000000456")!,
        kind: .walk,
        relationship: .owner,
        state: PetCareState(energy: 10),
        outcome: .tooTired
    )

    let plan = await provider.response(for: context)
    #expect(plan.activity == .sleeping)
    #expect(plan.emotion == .sleepy)
}

@Test
func successfulPlayIsNotMisreadFromItsPostActionEnergy() async {
    let provider = DeterministicInteractionResponseProvider()
    let context = PetReactionContext(
        interactionID: UUID(uuidString: "00000000-0000-4000-8000-000000000457")!,
        kind: .play,
        relationship: .owner,
        state: PetCareState(energy: 10),
        outcome: .applied,
        effect: PetCareEffect(energy: -12, mood: 14, bond: 2)
    )

    let plan = await provider.response(for: context)
    #expect(plan.activity == .playing)
    #expect(plan.emotion == .playful)
}

@Test
func deterministicProviderUsesExplicitFailureAndRepeatOutcomes() async {
    let provider = DeterministicInteractionResponseProvider()
    let full = PetReactionContext(
        interactionID: UUID(uuidString: "00000000-0000-4000-8000-000000000458")!,
        kind: .feed,
        relationship: .owner,
        state: PetCareState(fullness: 20),
        outcome: .tooFull
    )
    let repeated = PetReactionContext(
        interactionID: UUID(uuidString: "00000000-0000-4000-8000-000000000459")!,
        kind: .flower,
        relationship: .friend,
        state: PetCareState(),
        outcome: .cosmeticOnly,
        recentRepeatCount: 1
    )
    let cooldown = PetReactionContext(
        interactionID: UUID(uuidString: "00000000-0000-4000-8000-000000000460")!,
        kind: .rest,
        relationship: .owner,
        state: PetCareState(energy: 20),
        outcome: .restingCooldown
    )
    let repeatedPet = PetReactionContext(
        interactionID: UUID(uuidString: "00000000-0000-4000-8000-000000000461")!,
        kind: .pet,
        relationship: .owner,
        state: PetCareState(),
        outcome: .cosmeticOnly,
        recentRepeatCount: 2
    )

    let fullPlan = await provider.response(for: full)
    let repeatedPlan = await provider.response(for: repeated)
    let cooldownPlan = await provider.response(for: cooldown)
    let repeatedPetPlan = await provider.response(for: repeatedPet)
    #expect(fullPlan.activity == .petting)
    #expect(fullPlan.emotion == .content)
    #expect(repeatedPlan.activity == .offeringGift)
    #expect(repeatedPlan.effect == .flower)
    #expect(cooldownPlan.activity == .sleeping)
    #expect(cooldownPlan.emotion == .content)
    #expect(repeatedPetPlan.activity == .petting)
    #expect(repeatedPetPlan.motionClip == .petReceive)
    #expect(repeatedPetPlan.duration == 2.4)
    #expect(!repeatedPetPlan.speech.isEmpty)
}
