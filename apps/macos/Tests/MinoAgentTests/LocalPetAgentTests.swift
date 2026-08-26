import Foundation
import MinoAgent
import MinoDomain
import Testing

@Test
func localAgentSerializesEventsInFIFOOrder() async {
    let model = TestModelClient(mode: .echo, delayNanoseconds: 30_000_000)
    let agent = LocalPetAgent(
        identity: makeAgentIdentity(),
        modelClient: model,
        memoryStore: InMemoryAgentMemoryStore()
    )
    let first = AgentObservation(kind: .ownerMessage(text: "one"))
    let second = AgentObservation(kind: .ownerMessage(text: "two"))
    let third = AgentObservation(kind: .ownerMessage(text: "three"))

    let firstTask = Task { await agent.submit(first) }
    await waitUntil { await model.requestCount() == 1 }
    let secondTask = Task { await agent.submit(second) }
    await waitUntil { await agent.snapshot().queuedObservationCount == 1 }
    let thirdTask = Task { await agent.submit(third) }

    let results = await [firstTask.value, secondTask.value, thirdTask.value]
    #expect(results.map(\.observationID) == [first.id, second.id, third.id])
    #expect(await model.currentEventContents() == ["one", "two", "three"])
    #expect(await model.maximumConcurrentRequests() == 1)
    #expect(!(await agent.snapshot()).isProcessing)
}

@Test
func duplicateObservationSharesOneInferenceAndCachedResult() async {
    let model = TestModelClient(mode: .echo, delayNanoseconds: 30_000_000)
    let agent = LocalPetAgent(
        identity: makeAgentIdentity(),
        modelClient: model,
        memoryStore: InMemoryAgentMemoryStore()
    )
    let observation = AgentObservation(kind: .ownerMessage(text: "same event"))

    async let first = agent.submit(observation)
    async let second = agent.submit(observation)
    let pair = await (first, second)
    let cached = await agent.submit(observation)

    #expect(pair.0 == pair.1)
    #expect(cached == pair.0)
    #expect(await model.requestCount() == 1)
}

@Test
func policyViolationBecomesSafeIdleDecision() async {
    let model = TestModelClient(mode: .wrongTarget)
    let agent = LocalPetAgent(
        identity: makeAgentIdentity(),
        modelClient: model,
        memoryStore: InMemoryAgentMemoryStore()
    )

    let result = await agent.submit(
        AgentObservation(kind: .ownerMessage(text: "去联系团子"))
    )

    #expect(result.decision == .idle)
    #expect(result.fallbackReason == .policyRejected)
    #expect(result.memoryDisposition == .discard)
}

@Test
func malformedModelEnvelopeBecomesSafeIdleDecision() async {
    let model = TestModelClient(mode: .mismatchedInference)
    let agent = LocalPetAgent(
        identity: makeAgentIdentity(),
        modelClient: model,
        memoryStore: InMemoryAgentMemoryStore()
    )

    let result = await agent.submit(AgentObservation(kind: .periodicWake))

    #expect(result.decision == .idle)
    #expect(result.fallbackReason == .invalidModelOutput)
}

@Test
func modelFailureBecomesSafeIdleDecision() async {
    let model = TestModelClient(mode: .failure)
    let agent = LocalPetAgent(
        identity: makeAgentIdentity(),
        modelClient: model,
        memoryStore: InMemoryAgentMemoryStore()
    )

    let result = await agent.submit(AgentObservation(kind: .periodicWake))

    #expect(result.decision == .idle)
    #expect(result.fallbackReason == .modelUnavailable)
}

@Test
func validLongTermMemoryIsStoredLocally() async throws {
    let fixedMemoryID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    let memoryStore = InMemoryAgentMemoryStore()
    let model = TestModelClient(mode: .longTermMemory)
    let agent = LocalPetAgent(
        identity: makeAgentIdentity(),
        modelClient: model,
        memoryStore: memoryStore,
        now: { Date(timeIntervalSince1970: 9_000) },
        makeUUID: { fixedMemoryID }
    )
    let observation = AgentObservation(
        id: UUID(),
        occurredAt: Date(timeIntervalSince1970: 8_000),
        kind: .petMessage(
            senderPetID: PetProfileID(rawValue: "pet_partner"),
            text: "我喜欢草莓"
        )
    )

    let result = await agent.submit(observation)
    let memories = try await memoryStore.allMemories(
        for: PetProfileID(rawValue: "pet_local")
    )

    #expect(result.memoryPersistence == .stored(fixedMemoryID))
    #expect(memories.count == 1)
    #expect(memories[0].summary == "团子喜欢草莓")
    #expect(memories[0].relatedPetIDs == [PetProfileID(rawValue: "pet_partner")])
    #expect(memories[0].sourceObservationID == observation.id)
    #expect(memories[0].createdAt == Date(timeIntervalSince1970: 9_000))
}

@Test
func modelResponseValidationChecksInferenceAndAllowedAction() throws {
    let observation = AgentObservation(kind: .periodicWake)
    let context = AgentContextAssembler().assemble(
        identity: makeAgentIdentity(),
        state: AgentPetState(autonomousSocialEnabled: false),
        current: observation,
        recentObservations: [],
        memories: []
    )
    let inferenceID = UUID()
    let request = ManagedModelRequest(
        inferenceID: inferenceID,
        context: context,
        allowedActions: [.idle]
    )

    #expect(throws: ManagedModelClientError.mismatchedInferenceID) {
        try ManagedModelResponse(
            inferenceID: UUID(),
            decision: .idle
        ).validate(for: request)
    }
    #expect(throws: ManagedModelClientError.actionOutsideRequestedSchema(.speakToOwner)) {
        try ManagedModelResponse(
            inferenceID: inferenceID,
            decision: PetDecision(action: .speakToOwner("hi"))
        ).validate(for: request)
    }
}

private actor TestModelClient: ManagedModelClient {
    enum Mode: Sendable {
        case echo
        case wrongTarget
        case mismatchedInference
        case longTermMemory
        case failure
    }

    enum TestFailure: Error {
        case unavailable
    }

    private let mode: Mode
    private let delayNanoseconds: UInt64
    private var requests: [ManagedModelRequest] = []
    private var activeRequests = 0
    private var maximumActiveRequests = 0

    init(mode: Mode, delayNanoseconds: UInt64 = 0) {
        self.mode = mode
        self.delayNanoseconds = delayNanoseconds
    }

    func decision(for request: ManagedModelRequest) async throws -> ManagedModelResponse {
        requests.append(request)
        activeRequests += 1
        maximumActiveRequests = max(maximumActiveRequests, activeRequests)
        defer { activeRequests -= 1 }
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }

        switch mode {
        case .echo:
            return ManagedModelResponse(
                inferenceID: request.inferenceID,
                decision: PetDecision(
                    action: .speakToOwner(request.context.currentEvent.content ?? "醒来啦")
                )
            )
        case .wrongTarget:
            return ManagedModelResponse(
                inferenceID: request.inferenceID,
                decision: PetDecision(
                    action: .sendPetMessage(
                        petID: PetProfileID(rawValue: "pet_stranger"),
                        text: "你好"
                    )
                )
            )
        case .mismatchedInference:
            return ManagedModelResponse(
                inferenceID: UUID(),
                decision: .idle
            )
        case .longTermMemory:
            return ManagedModelResponse(
                inferenceID: request.inferenceID,
                decision: PetDecision(
                    action: .sendPetMessage(
                        petID: PetProfileID(rawValue: "pet_partner"),
                        text: "下次给你带草莓"
                    )
                ),
                memoryDisposition: .longTerm(
                    summary: "团子喜欢草莓",
                    reason: "团子亲口告诉我的"
                )
            )
        case .failure:
            throw TestFailure.unavailable
        }
    }

    func requestCount() -> Int {
        requests.count
    }

    func currentEventContents() -> [String] {
        requests.compactMap(\.context.currentEvent.content)
    }

    func maximumConcurrentRequests() -> Int {
        maximumActiveRequests
    }
}

private func waitUntil(
    maximumYields: Int = 10_000,
    condition: @escaping @Sendable () async -> Bool
) async {
    for _ in 0..<maximumYields {
        if await condition() { return }
        await Task.yield()
    }
    Issue.record("Timed out waiting for asynchronous condition")
}
