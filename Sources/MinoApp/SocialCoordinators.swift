import Foundation
import MinoAgent
import MinoDomain

enum EventSyncStatus: Equatable, Sendable {
    case stopped
    case catchingUp
    case realtime
    case polling
}

/// Reconciles durable REST events before consuming best-effort WebSocket pushes.
/// The cursor advances only after the UI/Agent event handler has run.
@MainActor
final class EventSyncCoordinator {
    typealias EventHandler = @MainActor @Sendable (FriendshipEvent) async throws -> Void
    typealias StatusHandler = @MainActor @Sendable (EventSyncStatus) -> Void

    private let backend: any MVPBackendService
    private let realtime: (any FriendshipEventRealtimeService)?
    private let cursorStore: any FriendshipEventCursorStore
    private let friendshipID: FriendshipID
    private let fallbackInterval: Duration
    private var syncTask: Task<Void, Never>?
    private var recentlyHandledIDs: [String] = []
    private var recentlyHandledIDSet = Set<String>()

    init(
        backend: any MVPBackendService,
        realtime: (any FriendshipEventRealtimeService)?,
        cursorStore: any FriendshipEventCursorStore,
        friendshipID: FriendshipID,
        fallbackInterval: Duration = .seconds(8)
    ) {
        self.backend = backend
        self.realtime = realtime
        self.cursorStore = cursorStore
        self.friendshipID = friendshipID
        self.fallbackInterval = fallbackInterval
    }

    func start(
        onEvent: @escaping EventHandler,
        onStatusChange: @escaping StatusHandler = { _ in }
    ) {
        stop()
        syncTask = Task { [weak self] in
            await self?.run(onEvent: onEvent, onStatusChange: onStatusChange)
        }
    }

    func stop() {
        syncTask?.cancel()
        syncTask = nil
    }

    private func run(
        onEvent: @escaping EventHandler,
        onStatusChange: @escaping StatusHandler
    ) async {
        var cursor: String?
        do {
            cursor = try await cursorStore.load(for: friendshipID)
        } catch {
            cursor = nil
        }

        while !Task.isCancelled {
            onStatusChange(.catchingUp)
            do {
                cursor = try await catchUp(
                    after: cursor,
                    onEvent: onEvent
                )
            } catch {
                onStatusChange(.polling)
                guard await pauseForFallback() else { break }
                continue
            }

            guard let realtime else {
                onStatusChange(.polling)
                guard await pauseForFallback() else { break }
                continue
            }

            do {
                let stream = try await realtime.events(
                    friendshipID: friendshipID,
                    after: cursor
                )
                onStatusChange(.realtime)
                for try await event in stream {
                    guard !Task.isCancelled else { break }
                    if try await deliver(event, onEvent: onEvent) {
                        cursor = event.id
                    }
                }
            } catch {
                // REST catch-up on the next iteration closes any WebSocket gap.
            }

            guard !Task.isCancelled else { break }
            onStatusChange(.polling)
            guard await pauseForFallback() else { break }
        }

        onStatusChange(.stopped)
    }

    private func catchUp(
        after initialCursor: String?,
        onEvent: @escaping EventHandler
    ) async throws -> String? {
        var cursor = initialCursor
        while !Task.isCancelled {
            let requestedCursor = cursor
            let page = try await backend.fetchEvents(
                friendshipID: friendshipID,
                after: cursor
            )
            let ordered = page.events.sorted { lhs, rhs in
                if lhs.sequence == rhs.sequence { return lhs.id < rhs.id }
                return lhs.sequence < rhs.sequence
            }

            for event in ordered {
                if try await deliver(event, onEvent: onEvent) {
                    cursor = event.id
                }
            }

            guard !ordered.isEmpty else { break }
            let pageCursor = page.nextCursor ?? ordered.last?.id
            guard pageCursor != requestedCursor else { break }
            cursor = pageCursor
        }
        return cursor
    }

    @discardableResult
    private func deliver(
        _ event: FriendshipEvent,
        onEvent: @escaping EventHandler
    ) async throws -> Bool {
        guard !recentlyHandledIDSet.contains(event.id) else { return false }
        try await onEvent(event)
        try await cursorStore.save(event.id, for: friendshipID)
        recentlyHandledIDs.append(event.id)
        recentlyHandledIDSet.insert(event.id)
        if recentlyHandledIDs.count > 512 {
            let expired = recentlyHandledIDs.removeFirst()
            recentlyHandledIDSet.remove(expired)
        }
        return true
    }

    private func pauseForFallback() async -> Bool {
        do {
            try await Task.sleep(for: fallbackInterval)
            return !Task.isCancelled
        } catch {
            return false
        }
    }
}

enum ConversationCoordinationError: Error, Equatable, Sendable {
    case conversationNotFound
    case conversationEnded
    case turnLimitReached
    case wrongPetTurn(expected: PetProfileID?)
}

actor ConversationCoordinator {
    private let backend: any MVPBackendService
    private var conversations: [ConversationID: PetConversation] = [:]
    private var transcripts: [ConversationID: [String]] = [:]

    init(backend: any MVPBackendService) {
        self.backend = backend
    }

    func start(
        friendshipID: FriendshipID,
        with recipientPetID: PetProfileID,
        openingMessage: String,
        idempotencyKey: UUID = UUID()
    ) async throws -> ConversationTurnReceipt {
        let receipt = try await backend.createConversation(
            friendshipID: friendshipID,
            CreateConversationCommand(
                recipientPetID: recipientPetID,
                openingMessage: openingMessage,
                idempotencyKey: idempotencyKey
            )
        )
        conversations[receipt.conversation.id] = receipt.conversation
        appendTranscript(
            "pet:\(receipt.message.actorID): \(receipt.message.text)",
            to: receipt.conversation.id
        )
        return receipt
    }

    func sendPetTurn(
        conversationID: ConversationID,
        petID: PetProfileID,
        text: String,
        idempotencyKey: UUID = UUID()
    ) async throws -> ConversationTurnReceipt {
        if let current = conversations[conversationID] {
            guard current.status == .active else {
                throw ConversationCoordinationError.conversationEnded
            }
            guard current.turnCount < 6 else {
                throw ConversationCoordinationError.turnLimitReached
            }
            guard current.nextSpeakerPetID == petID else {
                throw ConversationCoordinationError.wrongPetTurn(
                    expected: current.nextSpeakerPetID
                )
            }
        }

        let receipt = try await backend.sendConversationMessage(
            friendshipID: try friendshipID(for: conversationID),
            conversationID: conversationID,
            command: SendConversationMessageCommand(
                actorType: .pet,
                text: text,
                idempotencyKey: idempotencyKey
            )
        )
        conversations[conversationID] = receipt.conversation
        appendTranscript(
            "pet:\(receipt.message.actorID): \(receipt.message.text)",
            to: conversationID
        )
        return receipt
    }

    func sendHumanMessage(
        conversationID: ConversationID,
        text: String,
        idempotencyKey: UUID = UUID()
    ) async throws -> ConversationTurnReceipt {
        if conversations[conversationID]?.status == .ended {
            throw ConversationCoordinationError.conversationEnded
        }
        let receipt = try await backend.sendConversationMessage(
            friendshipID: try friendshipID(for: conversationID),
            conversationID: conversationID,
            command: SendConversationMessageCommand(
                actorType: .human,
                text: text,
                idempotencyKey: idempotencyKey
            )
        )
        conversations[conversationID] = receipt.conversation
        appendTranscript(
            "human:\(receipt.message.actorID): \(receipt.message.text)",
            to: conversationID
        )
        return receipt
    }

    func end(
        conversationID: ConversationID,
        summary: String,
        idempotencyKey: UUID = UUID()
    ) async throws -> PetConversation {
        let conversation = try await backend.endConversation(
            friendshipID: try friendshipID(for: conversationID),
            conversationID: conversationID,
            command: EndConversationCommand(
                summary: summary,
                idempotencyKey: idempotencyKey
            )
        )
        conversations[conversation.id] = conversation
        return conversation
    }

    func apply(_ conversation: PetConversation) {
        conversations[conversation.id] = conversation
    }

    func restore(
        _ conversation: PetConversation,
        messages: [PetConversationMessage]
    ) {
        conversations[conversation.id] = conversation
        transcripts[conversation.id] = []
        for message in messages.sorted(by: {
            if $0.createdAt == $1.createdAt { return $0.id.rawValue < $1.id.rawValue }
            return $0.createdAt < $1.createdAt
        }) {
            appendTranscript(
                "\(message.actorType.rawValue):\(message.actorID): \(message.text)",
                to: conversation.id
            )
        }
    }

    func recordIncomingMessage(
        conversationID: ConversationID,
        actorType: SocialActorType,
        actorID: String,
        recipientPetID: PetProfileID,
        turnIndex: Int?,
        text: String
    ) {
        appendTranscript(
            "\(actorType.rawValue):\(actorID): \(text)",
            to: conversationID
        )
        guard
            actorType == .pet,
            let turnIndex,
            let current = conversations[conversationID]
        else { return }
        let nextTurnCount = max(current.turnCount, turnIndex + 1)
        conversations[conversationID] = PetConversation(
            id: current.id,
            friendshipID: current.friendshipID,
            initiatorPetID: current.initiatorPetID,
            recipientPetID: current.recipientPetID,
            status: nextTurnCount >= 6 ? .ended : .active,
            nextSpeakerPetID: nextTurnCount >= 6 ? nil : recipientPetID,
            turnCount: nextTurnCount,
            createdAt: current.createdAt,
            endedAt: nextTurnCount >= 6 ? Date() : current.endedAt
        )
    }

    func transcript(for conversationID: ConversationID) -> [String] {
        transcripts[conversationID] ?? []
    }

    func completeTranscript(for conversationID: ConversationID) async throws -> [String] {
        let messages = try await backend.fetchConversationMessages(
            friendshipID: try friendshipID(for: conversationID),
            conversationID: conversationID
        )
        if let conversation = conversations[conversationID] {
            restore(conversation, messages: messages)
        } else {
            transcripts[conversationID] = []
            for message in messages {
                appendTranscript(
                    "\(message.actorType.rawValue):\(message.actorID): \(message.text)",
                    to: conversationID
                )
            }
        }
        return transcripts[conversationID] ?? []
    }

    private func friendshipID(for conversationID: ConversationID) throws -> FriendshipID {
        guard let friendshipID = conversations[conversationID]?.friendshipID else {
            throw ConversationCoordinationError.conversationNotFound
        }
        return friendshipID
    }

    private func appendTranscript(_ line: String, to conversationID: ConversationID) {
        var values = transcripts[conversationID] ?? []
        values.append(String(line.prefix(600)))
        if values.count > 16 {
            values.removeFirst(values.count - 16)
        }
        transcripts[conversationID] = values
    }
}

enum VisitCoordinationMVPError: Error, Equatable, Sendable {
    case visitNotActive
    case emptyLetter
}

actor VisitCoordinator {
    private let backend: any MVPBackendService
    private var visits: [PetVisitID: MVPVisit] = [:]

    init(backend: any MVPBackendService) {
        self.backend = backend
    }

    func invite(
        friendshipID: FriendshipID,
        visitorPetID: PetProfileID,
        hostAccountID: AccountID,
        reason: String?,
        idempotencyKey: UUID = UUID()
    ) async throws -> MVPVisit {
        let visit = try await backend.createVisitInvitation(
            friendshipID: friendshipID,
            CreateVisitInvitationCommand(
                visitorPetID: visitorPetID,
                hostAccountID: hostAccountID,
                reason: reason,
                idempotencyKey: idempotencyKey
            )
        )
        visits[visit.id] = visit
        return visit
    }

    func respond(
        visitID: PetVisitID,
        response: PetVisitInvitationResponse,
        idempotencyKey: UUID = UUID()
    ) async throws -> MVPVisit {
        let friendshipID = try requireVisit(visitID).friendshipID
        let visit = try await backend.respondToVisitInvitation(
            friendshipID: friendshipID,
            visitID: visitID,
            command: RespondToVisitInvitationCommand(
                response: response,
                idempotencyKey: idempotencyKey
            )
        )
        visits[visit.id] = visit
        return visit
    }

    func interact(
        visitID: PetVisitID,
        kind: VisitInteractionKind,
        text: String? = nil,
        idempotencyKey: UUID = UUID()
    ) async throws -> VisitInteractionReceipt {
        let visit = try requireActiveVisit(visitID)
        return try await backend.sendVisitInteraction(
            friendshipID: visit.friendshipID,
            visitID: visitID,
            command: CreateVisitInteractionCommand(
                kind: kind,
                text: text,
                idempotencyKey: idempotencyKey
            )
        )
    }

    func react(
        visitID: PetVisitID,
        reaction: VisitPetReaction,
        text: String? = nil,
        idempotencyKey: UUID = UUID()
    ) async throws -> VisitReactionReceipt {
        let visit = try requireActiveVisit(visitID)
        return try await backend.sendVisitReaction(
            friendshipID: visit.friendshipID,
            visitID: visitID,
            command: CreateVisitReactionCommand(
                reaction: reaction,
                text: text,
                idempotencyKey: idempotencyKey
            )
        )
    }

    /// Letter bodies go directly to the letter endpoint and are never exposed to
    /// an Agent callback or included in a social event payload.
    func leaveLetter(
        visitID: PetVisitID,
        body: String,
        idempotencyKey: UUID = UUID()
    ) async throws -> PetLetter {
        let visit = try requireActiveVisit(visitID)
        let normalized = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw VisitCoordinationMVPError.emptyLetter }
        return try await backend.createLetter(
            friendshipID: visit.friendshipID,
            visitID: visitID,
            command: CreateLetterCommand(body: normalized, idempotencyKey: idempotencyKey)
        )
    }

    func fetchLetter(
        friendshipID: FriendshipID,
        _ letterID: LetterID
    ) async throws -> PetLetter {
        try await backend.fetchLetter(friendshipID: friendshipID, letterID)
    }

    func end(
        visitID: PetVisitID,
        idempotencyKey: UUID = UUID()
    ) async throws -> EndVisitReceipt {
        let visit = try requireActiveVisit(visitID)
        let receipt = try await backend.endVisit(
            friendshipID: visit.friendshipID,
            visitID: visitID,
            command: EndVisitCommand(idempotencyKey: idempotencyKey)
        )
        visits[receipt.visit.id] = receipt.visit
        return receipt
    }

    func apply(_ visit: MVPVisit) {
        visits[visit.id] = visit
    }

    func visit(id: PetVisitID) -> MVPVisit? {
        visits[id]
    }

    private func requireVisit(_ id: PetVisitID) throws -> MVPVisit {
        guard let visit = visits[id] else {
            throw VisitCoordinationMVPError.visitNotActive
        }
        return visit
    }

    private func requireActiveVisit(_ id: PetVisitID) throws -> MVPVisit {
        let visit = try requireVisit(id)
        guard visit.status == .active else {
            throw VisitCoordinationMVPError.visitNotActive
        }
        return visit
    }
}

/// Bridges one local pet brain to network coordinators. The server never runs a
/// substitute brain; if this actor is offline, remote observations simply wait
/// in the durable event stream until the owning client reconnects.
actor AgentCoordinator {
    typealias OwnerSpeechHandler = @MainActor @Sendable (String) -> Void
    typealias ReactionHandler = @MainActor @Sendable (PetReaction) -> Void
    typealias FailureHandler = @MainActor @Sendable (Error) -> Void

    private var identity: AgentIdentity
    private let agent: LocalPetAgent
    private let conversations: ConversationCoordinator
    private let visits: VisitCoordinator
    private let onOwnerSpeech: OwnerSpeechHandler
    private let onReaction: ReactionHandler
    private let onFailure: FailureHandler
    private var activeConversationIDs: [FriendshipID: ConversationID] = [:]

    init(
        identity: AgentIdentity,
        agent: LocalPetAgent,
        conversations: ConversationCoordinator,
        visits: VisitCoordinator,
        onOwnerSpeech: @escaping OwnerSpeechHandler,
        onReaction: @escaping ReactionHandler,
        onFailure: @escaping FailureHandler = { _ in }
    ) {
        self.identity = identity
        self.agent = agent
        self.conversations = conversations
        self.visits = visits
        self.onOwnerSpeech = onOwnerSpeech
        self.onReaction = onReaction
        self.onFailure = onFailure
    }

    func observe(_ observation: AgentObservation) async {
        do {
            try await observeEvent(observation)
        } catch {
            // Owner actions and periodic wakes are not tied to a durable server
            // cursor. Their failures are surfaced, but do not need event replay.
        }
    }

    func updateFriends(_ friends: [AgentFriend]) async {
        identity = AgentIdentity(
            petID: identity.petID,
            ownerAccountID: identity.ownerAccountID,
            displayName: identity.displayName,
            friends: friends,
            localeIdentifier: identity.localeIdentifier
        )
        await agent.updateFriends(friends)
    }

    /// Processes a durable server event. Delivery failures are rethrown so the
    /// event synchronizer does not advance its cursor until the idempotent
    /// action has actually reached the server.
    func observeEvent(_ observation: AgentObservation) async throws {
        let result = await agent.submit(observation)
        do {
            try await execute(
                result.decision.action,
                idempotencyKey: observation.id
            )
        } catch {
            await onFailure(error)
            throw error
        }
    }

    func applyConversation(_ conversation: PetConversation) async {
        await conversations.apply(conversation)
        activeConversationIDs[conversation.friendshipID] = conversation.status == .active
            ? conversation.id
            : nil
    }

    func restoreConversation(
        _ conversation: PetConversation,
        messages: [PetConversationMessage]
    ) async {
        await conversations.restore(conversation, messages: messages)
        activeConversationIDs[conversation.friendshipID] = conversation.status == .active
            ? conversation.id
            : nil
    }

    func setActiveConversationID(
        _ conversationID: ConversationID?,
        for friendshipID: FriendshipID
    ) {
        activeConversationIDs[friendshipID] = conversationID
    }

    func recordConversationMessage(
        conversationID: ConversationID,
        actorType: SocialActorType,
        actorID: String,
        recipientPetID: PetProfileID,
        turnIndex: Int?,
        text: String
    ) async {
        await conversations.recordIncomingMessage(
            conversationID: conversationID,
            actorType: actorType,
            actorID: actorID,
            recipientPetID: recipientPetID,
            turnIndex: turnIndex,
            text: text
        )
    }

    /// The initiating pet performs one final local inference and publishes only
    /// a compact summary; individual conversation turns remain off the event line.
    func finishConversation(
        friendshipID: FriendshipID,
        conversationID: ConversationID,
        occurredAt: Date
    ) async throws {
        let transcript = try await conversations.completeTranscript(for: conversationID)
        let observationID = UUID(uuidString: conversationID.rawValue) ?? UUID()
        let result = await agent.submit(
            AgentObservation(
                id: observationID,
                occurredAt: occurredAt,
                kind: .conversationEnded(
                    conversationID: conversationID,
                    transcript: transcript
                )
            )
        )
        let summary = switch result.decision.action {
        case .speakToOwner(let text): text
        default: "它们交换了今天的心情，也悄悄惦记着彼此。"
        }
        _ = try await conversations.end(
            conversationID: conversationID,
            summary: summary,
            idempotencyKey: observationID
        )
        activeConversationIDs[friendshipID] = nil
    }

    /// Lets the owner explicitly join an already-running pet conversation as a
    /// human actor. Returning `false` means there is no conversation to join.
    func sendOwnerMessageToActiveConversation(
        _ text: String,
        friendshipID: FriendshipID,
        idempotencyKey: UUID = UUID()
    ) async throws -> Bool {
        guard let activeConversationID = activeConversationIDs[friendshipID] else {
            return false
        }
        let receipt = try await conversations.sendHumanMessage(
            conversationID: activeConversationID,
            text: text,
            idempotencyKey: idempotencyKey
        )
        activeConversationIDs[friendshipID] = receipt.conversation.status == .active
            ? receipt.conversation.id
            : nil
        return true
    }

    func applyVisit(_ visit: MVPVisit) async {
        await visits.apply(visit)
        guard visit.visitorPetID == identity.petID else { return }
        let location: PetLogicalLocation =
            visit.status == .active
            ? .visiting(visit.id)
            : .home
        var state = await agent.snapshot().state
        state.location = location
        await agent.updateState(state)
    }

    private func execute(_ action: PetAction, idempotencyKey: UUID) async throws {
        switch action {
        case .idle:
            return

        case .speakToOwner(let text):
            await onOwnerSpeech(text)

        case .sendPetMessage(let petID, let text):
            guard let friend = identity.friend(withPetID: petID) else {
                throw PetPolicyViolation.targetIsNotFriend(petID)
            }
            if let activeConversationID = activeConversationIDs[friend.friendshipID] {
                do {
                    let receipt = try await conversations.sendPetTurn(
                        conversationID: activeConversationID,
                        petID: identity.petID,
                        text: text,
                        idempotencyKey: idempotencyKey
                    )
                    activeConversationIDs[friend.friendshipID] = receipt.conversation.status == .active
                        ? receipt.conversation.id
                        : nil
                    return
                } catch let error as ConversationCoordinationError {
                    switch error {
                    case .conversationNotFound, .conversationEnded, .turnLimitReached:
                        activeConversationIDs[friend.friendshipID] = nil
                    case .wrongPetTurn:
                        throw error
                    }
                }
            }
            let receipt = try await conversations.start(
                friendshipID: friend.friendshipID,
                with: petID,
                openingMessage: text,
                idempotencyKey: idempotencyKey
            )
            activeConversationIDs[friend.friendshipID] = receipt.conversation.id

        case .proposeVisit(let petID, let reason):
            guard let friend = identity.friend(withPetID: petID) else {
                throw PetPolicyViolation.targetIsNotFriend(petID)
            }
            _ = try await visits.invite(
                friendshipID: friend.friendshipID,
                visitorPetID: identity.petID,
                hostAccountID: friend.accountID,
                reason: reason,
                idempotencyKey: idempotencyKey
            )

        case .respondToVisit(let invitationID, let decision):
            _ = try await visits.respond(
                visitID: PetVisitID(rawValue: invitationID.rawValue),
                response: decision == .accept ? .accept : .decline,
                idempotencyKey: idempotencyKey
            )

        case .reactToInteraction(let reaction):
            let state = await agent.snapshot().state
            if case .visiting(let visitID) = state.location {
                _ = try await visits.react(
                    visitID: visitID,
                    reaction: VisitPetReaction(reaction),
                    idempotencyKey: idempotencyKey
                )
            } else {
                await onReaction(reaction)
            }

        case .requestReturn(let visitID):
            _ = try await visits.end(
                visitID: visitID,
                idempotencyKey: idempotencyKey
            )
        }
    }

}

private extension VisitPetReaction {
    init(_ reaction: PetReaction) {
        self = switch reaction {
        case .happy: .happy
        case .excited: .excited
        case .shy: .shy
        case .sleepy: .sleepy
        case .grateful: .grateful
        case .playful: .playful
        case .resting: .resting
        }
    }
}
