import Foundation
import MinoDomain
import Testing

@Test
func ownerActivityUsesAnEnumInsteadOfBooleans() throws {
    let listening = OwnerActivity.listeningToMusic(title: "Night Walk")
    let encoded = try JSONEncoder().encode(listening)
    let decoded = try JSONDecoder().decode(OwnerActivity.self, from: encoded)

    #expect(decoded == listening)
    #expect(listening.wireValue == "listening_to_music")
    #expect(OwnerActivity.idle.wireValue == "idle")
}

@Test
func petSituationCarriesCareOwnerAndCompanionWithoutParallelFlags() {
    let care = PetCareState(fullness: 40, energy: 20, mood: 80, bond: 10)
    let owner = OwnerContext(
        presence: .present,
        activity: .listeningToMusic(title: nil),
        updatedAt: Date(timeIntervalSince1970: 10)
    )
    let situation = PetSituation(
        slot: .mine,
        care: care,
        activity: .sleeping,
        emotion: .sleepy,
        owner: owner,
        companionPresent: true
    )

    #expect(situation.care.fullness == 40)
    #expect(situation.owner.presence == .present)
    if case .listeningToMusic = situation.owner.activity {
        // Expected
    } else {
        Issue.record("Owner activity should stay an enum case")
    }
    #expect(situation.companionPresent)
}

@Test
func reactionContextDefaultsKeepExistingCallSitesStable() {
    let context = PetReactionContext(
        interactionID: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!,
        kind: .feed,
        relationship: .owner,
        state: PetCareState()
    )
    #expect(context.owner == .unknown)
    #expect(!context.companionPresent)
}
