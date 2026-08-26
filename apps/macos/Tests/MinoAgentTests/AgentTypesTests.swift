import Foundation
import MinoAgent
import MinoDomain
import Testing

@Test
func agentPetStateCopiesVisibleSituationWithoutStartingATurn() {
    var state = AgentPetState(emotion: .content, companionPresent: false)
    state.applyVisibleSituation(
        PetSituation(
            slot: .mine,
            care: PetCareState(fullness: 20, energy: 30, mood: 90),
            activity: .sleeping,
            emotion: .sleepy,
            owner: OwnerContext(presence: .present, activity: .listeningToMusic(title: nil)),
            companionPresent: true
        )
    )

    #expect(state.emotion == .sleepy)
    #expect(state.ownerPresence == .present)
    #expect(state.companionPresent)
    #expect(state.publicCare?.mood == .high)
    if case .listeningToMusic = state.ownerActivity {
        // Expected
    } else {
        Issue.record("Owner activity should copy onto Agent state")
    }
}

@Test
func petActionUsesStrictDiscriminatedJSON() throws {
    let decision = PetDecision(
        action: .sendPetMessage(
            petID: PetProfileID(rawValue: "pet_partner"),
            text: "一起玩吗？"
        ),
        publicReason: "想念团子"
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(decision)
    let json = try #require(String(data: data, encoding: .utf8))

    #expect(json.contains("\"type\":\"send_pet_message\""))
    #expect(try JSONDecoder().decode(PetDecision.self, from: data) == decision)

    let unknownAction = Data(
        """
        {"schemaVersion":1,"action":{"type":"run_shell"}}
        """.utf8
    )
    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(PetDecision.self, from: unknownAction)
    }
}

@Test
func contextAssemblerNeverExposesSealedLetterBody() {
    let observation = AgentObservation(
        kind: .sealedHumanLetterAvailable(
            senderAccountID: AccountID(rawValue: "account_partner")
        )
    )
    let context = AgentContextAssembler().assemble(
        identity: makeAgentIdentity(),
        state: AgentPetState(),
        current: observation,
        recentObservations: [],
        memories: []
    )

    #expect(context.currentEvent.kind == .sealedHumanLetterAvailable)
    #expect(context.currentEvent.content == nil)
    #expect(context.currentEvent.relatedAccountID == AccountID(rawValue: "account_partner"))
}

@Test
func contextAssemblerBoundsAndSanitizesInput() {
    let assembler = AgentContextAssembler(
        configuration: .init(
            maximumRecentEvents: 1,
            maximumMemories: 1,
            maximumTextCharacters: 5
        )
    )
    let old = AgentObservation(
        occurredAt: Date(timeIntervalSince1970: 1),
        kind: .ownerMessage(text: "old")
    )
    let recent = AgentObservation(
        occurredAt: Date(timeIntervalSince1970: 2),
        kind: .ownerMessage(text: "recent")
    )
    let current = AgentObservation(
        occurredAt: Date(timeIntervalSince1970: 3),
        kind: .ownerMessage(text: "\0 123456789 ")
    )
    let context = assembler.assemble(
        identity: makeAgentIdentity(),
        state: AgentPetState(),
        current: current,
        recentObservations: [old, recent, current],
        memories: [
            makeMemory(id: UUID(), importance: 0.1),
            makeMemory(id: UUID(), importance: 0.9)
        ]
    )

    #expect(context.currentEvent.content == "12345")
    #expect(context.recentEvents.map(\.id) == [recent.id])
    #expect(context.relevantMemories.count == 1)
    #expect(context.relevantMemories[0].importance == 0.9)
}

func makeAgentIdentity() -> AgentIdentity {
    AgentIdentity(
        petID: PetProfileID(rawValue: "pet_local"),
        ownerAccountID: AccountID(rawValue: "account_local"),
        displayName: "奶糖",
        friends: [
            AgentFriend(
                friendshipID: FriendshipID(rawValue: "friendship_1"),
                accountID: AccountID(rawValue: "account_partner"),
                petID: PetProfileID(rawValue: "pet_partner")
            )
        ]
    )
}

func makeMemory(
    id: UUID,
    petID: PetProfileID = PetProfileID(rawValue: "pet_local"),
    category: AgentMemoryCategory = .friendPet,
    summary: String = "团子喜欢草莓",
    reason: String = "一次聊天",
    relatedPetIDs: [PetProfileID] = [PetProfileID(rawValue: "pet_partner")],
    importance: Double = 0.5,
    createdAt: Date = Date(timeIntervalSince1970: 1_000)
) -> AgentMemory {
    AgentMemory(
        id: id,
        petID: petID,
        category: category,
        summary: summary,
        reason: reason,
        relatedPetIDs: relatedPetIDs,
        sourceObservationID: UUID(),
        importance: importance,
        createdAt: createdAt
    )
}
