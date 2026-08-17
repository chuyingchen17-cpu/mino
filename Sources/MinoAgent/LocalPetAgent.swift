import Foundation
import MinoDomain

public struct LocalPetAgentSnapshot: Equatable, Sendable {
    public let state: AgentPetState
    public let isProcessing: Bool
    public let queuedObservationCount: Int
    public let recentObservationCount: Int

    public init(
        state: AgentPetState,
        isProcessing: Bool,
        queuedObservationCount: Int,
        recentObservationCount: Int
    ) {
        self.state = state
        self.isProcessing = isProcessing
        self.queuedObservationCount = queuedObservationCount
        self.recentObservationCount = recentObservationCount
    }
}

/// Owns the event queue for one pet brain. Actor reentrancy is intentionally contained by the
/// explicit queue so only one model request can influence a pet at a time.
public actor LocalPetAgent {
    private var identity: AgentIdentity
    private var state: AgentPetState
    private let modelClient: any ManagedModelClient
    private let memoryStore: any AgentMemoryStore
    private let contextAssembler: AgentContextAssembler
    private let policyGuard: PetPolicyGuard
    private let now: @Sendable () -> Date
    private let makeUUID: @Sendable () -> UUID

    private var pendingObservations: [AgentObservation] = []
    private var waiters: [UUID: [CheckedContinuation<AgentTurnResult, Never>]] = [:]
    private var completedResults: [UUID: AgentTurnResult] = [:]
    private var completedOrder: [UUID] = []
    private var recentObservations: [AgentObservation] = []
    private var isProcessing = false
    private let maximumCompletedResults = 256

    public init(
        identity: AgentIdentity,
        initialState: AgentPetState = AgentPetState(),
        modelClient: any ManagedModelClient,
        memoryStore: any AgentMemoryStore,
        contextAssembler: AgentContextAssembler = AgentContextAssembler(),
        policyGuard: PetPolicyGuard = PetPolicyGuard(),
        now: @escaping @Sendable () -> Date = { Date() },
        makeUUID: @escaping @Sendable () -> UUID = { UUID() }
    ) {
        self.identity = identity
        self.state = initialState
        self.modelClient = modelClient
        self.memoryStore = memoryStore
        self.contextAssembler = contextAssembler
        self.policyGuard = policyGuard
        self.now = now
        self.makeUUID = makeUUID
    }

    public func updateState(_ state: AgentPetState) {
        self.state = state
    }

    public func updateFriends(_ friends: [AgentFriend]) {
        identity = AgentIdentity(
            petID: identity.petID,
            ownerAccountID: identity.ownerAccountID,
            displayName: identity.displayName,
            friends: friends,
            localeIdentifier: identity.localeIdentifier
        )
    }

    /// Submits an observation in FIFO order. Duplicate IDs share the in-flight or cached result.
    public func submit(_ observation: AgentObservation) async -> AgentTurnResult {
        if let completed = completedResults[observation.id] {
            return completed
        }

        return await withCheckedContinuation { continuation in
            if waiters[observation.id] == nil {
                waiters[observation.id] = [continuation]
                pendingObservations.append(observation)
            } else {
                waiters[observation.id, default: []].append(continuation)
            }
            scheduleDrainIfNeeded()
        }
    }

    public func snapshot() -> LocalPetAgentSnapshot {
        LocalPetAgentSnapshot(
            state: state,
            isProcessing: isProcessing,
            queuedObservationCount: pendingObservations.count,
            recentObservationCount: recentObservations.count
        )
    }

    private func scheduleDrainIfNeeded() {
        guard !isProcessing else { return }
        isProcessing = true
        Task { await self.drainQueue() }
    }

    private func drainQueue() async {
        while !pendingObservations.isEmpty {
            let observation = pendingObservations.removeFirst()
            let result = await process(observation)
            cache(result)
            let continuations = waiters.removeValue(forKey: observation.id) ?? []
            for continuation in continuations {
                continuation.resume(returning: result)
            }
        }
        isProcessing = false
    }

    private func process(_ observation: AgentObservation) async -> AgentTurnResult {
        let query = contextAssembler.memoryQuery(identity: identity, for: observation)
        let memories = (try? await memoryStore.memories(matching: query)) ?? []
        let context = contextAssembler.assemble(
            identity: identity,
            state: state,
            current: observation,
            recentObservations: recentObservations,
            memories: memories
        )
        let allowedActions = policyGuard.allowedActions(for: context)
        let request = ManagedModelRequest(
            // One durable observation maps to one billable inference across
            // client retries and restarts.
            inferenceID: observation.id,
            context: context,
            allowedActions: allowedActions
        )

        let response: ManagedModelResponse
        do {
            response = try await modelClient.decision(for: request)
        } catch {
            return finish(
                observation,
                result: fallback(for: observation, reason: .modelUnavailable)
            )
        }

        do {
            try response.validate(for: request)
        } catch {
            return finish(
                observation,
                result: fallback(for: observation, reason: .invalidModelOutput)
            )
        }

        do {
            try policyGuard.validate(
                decision: response.decision,
                memoryDisposition: response.memoryDisposition,
                in: context,
                allowedActions: allowedActions
            )
        } catch {
            return finish(
                observation,
                result: fallback(for: observation, reason: .policyRejected)
            )
        }

        let persistence = await persistMemory(
            response.memoryDisposition,
            for: observation
        )
        return finish(
            observation,
            result: AgentTurnResult(
                observationID: observation.id,
                decision: response.decision,
                memoryDisposition: response.memoryDisposition,
                memoryPersistence: persistence
            )
        )
    }

    private func persistMemory(
        _ disposition: MemoryDisposition,
        for observation: AgentObservation
    ) async -> AgentMemoryPersistence {
        switch disposition {
        case .discard:
            return .notRequested
        case .session:
            return .sessionOnly
        case let .longTerm(summary, reason):
            let metadata = contextAssembler.memoryMetadata(for: observation)
            let memory = AgentMemory(
                id: makeUUID(),
                petID: identity.petID,
                category: metadata.category,
                summary: summary.trimmingCharacters(in: .whitespacesAndNewlines),
                reason: reason.trimmingCharacters(in: .whitespacesAndNewlines),
                relatedPetIDs: metadata.relatedPetIDs,
                sourceObservationID: observation.id,
                importance: metadata.importance,
                createdAt: now()
            )
            do {
                try await memoryStore.save(memory)
                return .stored(memory.id)
            } catch {
                return .failed
            }
        }
    }

    private func fallback(
        for observation: AgentObservation,
        reason: AgentFallbackReason
    ) -> AgentTurnResult {
        AgentTurnResult(
            observationID: observation.id,
            decision: .idle,
            memoryDisposition: .discard,
            memoryPersistence: .notRequested,
            fallbackReason: reason
        )
    }

    private func finish(
        _ observation: AgentObservation,
        result: AgentTurnResult
    ) -> AgentTurnResult {
        recentObservations.append(observation)
        let maximumRecent = max(20, contextAssembler.configuration.maximumRecentEvents * 2)
        if recentObservations.count > maximumRecent {
            recentObservations.removeFirst(recentObservations.count - maximumRecent)
        }
        return result
    }

    private func cache(_ result: AgentTurnResult) {
        completedResults[result.observationID] = result
        completedOrder.append(result.observationID)
        if completedOrder.count > maximumCompletedResults {
            let removalCount = completedOrder.count - maximumCompletedResults
            let expired = Array(completedOrder.prefix(removalCount))
            completedOrder.removeFirst(removalCount)
            for observationID in expired {
                completedResults.removeValue(forKey: observationID)
            }
        }
    }
}
