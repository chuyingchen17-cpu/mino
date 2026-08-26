import Foundation
import MinoAgent
import MinoDomain
import MinoInfrastructure

func shouldRetrySocialMutation(_ error: Error) -> Bool {
    guard let backend = error as? BackendClientError else {
        return error is BackendServiceError
    }
    switch backend {
    case .transport, .invalidResponse, .decoding:
        return true
    case .invalidRequest:
        return false
    case .httpStatus(let statusCode, _):
        return statusCode == 429 || statusCode >= 500
    }
}

enum ConversationCoordinationError: Error, Equatable, Sendable {
    case conversationNotFound
    case conversationEnded
    case turnLimitReached
    case wrongPetTurn(expected: PetProfileID?)
}

actor ConversationCoordinator {
    private let backend: any AccountBackendService
    private let outbox: any SocialMutationOutboxStore
    private var conversations: [ConversationID: PetConversation] = [:]
    private var transcripts: [ConversationID: [String]] = [:]

    init(
        backend: any AccountBackendService,
        outbox: any SocialMutationOutboxStore
    ) {
        self.backend = backend
        self.outbox = outbox
    }

    func start(
        friendshipID: FriendshipID,
        with recipientPetID: PetProfileID,
        openingMessage: String,
        idempotencyKey: UUID = UUID()
    ) async throws -> ConversationTurnReceipt {
        let command = CreateConversationCommand(
            friendshipID: friendshipID,
            recipientPetID: recipientPetID,
            openingMessage: openingMessage,
            idempotencyKey: idempotencyKey
        )
        let mutation = SocialMutation(
            id: idempotencyKey,
            kind: .createConversation,
            idempotencyKey: idempotencyKey,
            body: .object([
                "friendshipID": .string(friendshipID.rawValue),
                "recipientPetID": .string(recipientPetID.rawValue),
                "openingMessage": .string(openingMessage),
                "actorType": .string(SocialActorType.petAgent.rawValue)
            ])
        )
        let receipt = try await deliver(mutation) {
            try await backend.createConversation(command)
        }
        conversations[receipt.conversation.id] = receipt.conversation
        appendTranscript(
            "pet_agent:\(receipt.message.senderAccountID.rawValue): \(receipt.message.body)",
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

        let command = SendConversationMessageCommand(
            actorType: .petAgent,
            text: text,
            idempotencyKey: idempotencyKey
        )
        let receipt = try await deliver(messageMutation(
            conversationID: conversationID,
            command: command
        )) {
            try await backend.sendConversationMessage(
                conversationID: conversationID,
                command: command
            )
        }
        conversations[conversationID] = receipt.conversation
        appendTranscript(
            "pet_agent:\(receipt.message.senderAccountID.rawValue): \(receipt.message.body)",
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
        let command = SendConversationMessageCommand(
            actorType: .human,
            text: text,
            idempotencyKey: idempotencyKey
        )
        let receipt = try await deliver(messageMutation(
            conversationID: conversationID,
            command: command
        )) {
            try await backend.sendConversationMessage(
                conversationID: conversationID,
                command: command
            )
        }
        conversations[conversationID] = receipt.conversation
        appendTranscript(
            "human:\(receipt.message.senderAccountID.rawValue): \(receipt.message.body)",
            to: conversationID
        )
        return receipt
    }

    func end(
        conversationID: ConversationID,
        summary: String,
        idempotencyKey: UUID = UUID()
    ) async throws -> PetConversation {
        let command = EndConversationCommand(
            summary: summary,
            idempotencyKey: idempotencyKey
        )
        let mutation = SocialMutation(
            id: idempotencyKey,
            kind: .endConversation,
            aggregateID: conversationID.rawValue,
            idempotencyKey: idempotencyKey,
            body: .object([
                "summary": .string(summary),
                "actorType": .string(SocialActorType.petAgent.rawValue)
            ])
        )
        let conversation = try await deliver(mutation) {
            try await backend.endConversation(
                conversationID: conversationID,
                command: command
            )
        }
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
                "\(message.actorType.rawValue):\(message.senderAccountID.rawValue): \(message.body)",
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
            actorType == .petAgent,
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
            version: current.version + 1,
            createdAt: current.createdAt,
            endedAt: nextTurnCount >= 6 ? Date() : current.endedAt
        )
    }

    func transcript(for conversationID: ConversationID) -> [String] {
        transcripts[conversationID] ?? []
    }

    func completeTranscript(for conversationID: ConversationID) async throws -> [String] {
        let messages = try await backend.fetchConversationMessages(
            conversationID: conversationID
        )
        if let conversation = conversations[conversationID] {
            restore(conversation, messages: messages)
        } else {
            transcripts[conversationID] = []
            for message in messages {
                appendTranscript(
                    "\(message.actorType.rawValue):\(message.senderAccountID.rawValue): \(message.body)",
                    to: conversationID
                )
            }
        }
        return transcripts[conversationID] ?? []
    }

    private func appendTranscript(_ line: String, to conversationID: ConversationID) {
        var values = transcripts[conversationID] ?? []
        values.append(String(line.prefix(600)))
        if values.count > 16 {
            values.removeFirst(values.count - 16)
        }
        transcripts[conversationID] = values
    }

    private func messageMutation(
        conversationID: ConversationID,
        command: SendConversationMessageCommand
    ) -> SocialMutation {
        SocialMutation(
            id: command.idempotencyKey,
            kind: .sendConversationMessage,
            aggregateID: conversationID.rawValue,
            idempotencyKey: command.idempotencyKey,
            body: .object([
                "actorType": .string(command.actorType.rawValue),
                "text": .string(command.text)
            ])
        )
    }

    private func deliver<Value: Sendable>(
        _ mutation: SocialMutation,
        operation: () async throws -> Value
    ) async throws -> Value {
        try await outbox.enqueue(mutation)
        do {
            let value = try await operation()
            try await outbox.markSucceeded(mutation.id)
            return value
        } catch {
            if shouldRetrySocialMutation(error) {
                try? await outbox.markFailed(
                    mutation.id,
                    retryAt: Date().addingTimeInterval(2)
                )
            } else {
                try? await outbox.markSucceeded(mutation.id)
            }
            throw error
        }
    }
}

enum VisitCoordinationError: Error, Equatable, Sendable {
    case visitNotActive
    case emptyLetter
    case invalidOutboxMutation
}

actor VisitCoordinator {
    private let backend: any AccountBackendService
    private let outbox: any SocialMutationOutboxStore
    private var visits: [PetVisitID: Visit] = [:]

    init(
        backend: any AccountBackendService,
        outbox: any SocialMutationOutboxStore
    ) {
        self.backend = backend
        self.outbox = outbox
    }

    func invite(
        friendshipID: FriendshipID,
        visitorPetID: PetProfileID,
        hostAccountID: AccountID,
        reason: String?,
        idempotencyKey: UUID = UUID()
    ) async throws -> Visit {
        var body: [String: JSONValue] = [
            "friendshipID": .string(friendshipID.rawValue),
            "visitorPetID": .string(visitorPetID.rawValue),
            "hostAccountID": .string(hostAccountID.rawValue)
        ]
        if let reason { body["reason"] = .string(reason) }
        let mutation = SocialMutation(
            id: idempotencyKey,
            kind: .createVisit,
            idempotencyKey: idempotencyKey,
            body: .object(body)
        )
        let visit = try await deliver(mutation) {
            try await backend.createVisit(
                CreateVisitCommand(
                    friendshipID: friendshipID,
                    visitorPetID: visitorPetID,
                    hostAccountID: hostAccountID,
                    reason: reason,
                    idempotencyKey: idempotencyKey
                )
            )
        }
        visits[visit.id] = visit
        return visit
    }

    func respond(
        visitID: PetVisitID,
        response: VisitResponse,
        actorType: VisitActionActorType = .petAgent,
        idempotencyKey: UUID = UUID()
    ) async throws -> Visit {
        _ = try requireVisit(visitID)
        let mutation = SocialMutation(
            id: idempotencyKey,
            kind: .respondVisit,
            aggregateID: visitID.rawValue,
            idempotencyKey: idempotencyKey,
            body: .object([
                "response": .string(response.rawValue),
                "actorType": .string(actorType.rawValue)
            ])
        )
        let visit = try await deliver(mutation) {
            try await backend.respondToVisit(
                visitID: visitID,
                command: RespondToVisitCommand(
                    response: response,
                    actorType: actorType,
                    idempotencyKey: idempotencyKey
                )
            )
        }
        visits[visit.id] = visit
        return visit
    }

    func interact(
        visitID: PetVisitID,
        kind: VisitActionKind,
        text: String? = nil,
        idempotencyKey: UUID = UUID()
    ) async throws -> VisitAction {
        _ = try requireActiveVisit(visitID)
        let payload: JSONValue = switch kind {
        case .message: .object(["text": .string(text ?? "")])
        case .walk: .object(text.map { ["destination": .string($0)] } ?? [:])
        default: .object([:])
        }
        let command = CreateVisitActionCommand(
            kind: kind,
            actorType: .human,
            payload: payload,
            idempotencyKey: idempotencyKey
        )
        return try await deliver(actionMutation(visitID: visitID, command: command)) {
            try await backend.createVisitAction(visitID: visitID, command: command)
        }
    }

    func interactWithPet(
        petID: PetProfileID,
        kind: PetCareInteractionKind,
        visitID: PetVisitID? = nil,
        occurredAt: Date = Date(),
        idempotencyKey: UUID = UUID()
    ) async throws -> PetInteractionReceipt {
        if let visitID { _ = try requireActiveVisit(visitID) }
        var body: [String: JSONValue] = [
            "petID": .string(petID.rawValue),
            "kind": .string(kind.rawValue),
            "occurredAt": .number(occurredAt.timeIntervalSince1970 * 1_000)
        ]
        if let visitID { body["visitID"] = .string(visitID.rawValue) }
        let mutation = SocialMutation(
            id: idempotencyKey,
            kind: .petInteraction,
            aggregateID: petID.rawValue,
            idempotencyKey: idempotencyKey,
            body: .object(body)
        )
        return try await deliver(mutation) {
            try await backend.interactWithPet(
                petID: petID,
                command: PetInteractionCommand(
                    kind: kind,
                    visitID: visitID,
                    occurredAt: occurredAt,
                    idempotencyKey: idempotencyKey
                )
            )
        }
    }

    func updateOwnPetAppearance(
        characterID: PetCharacterID,
        idempotencyKey: UUID = UUID()
    ) async throws -> PublicPetSnapshot {
        let command = PetAppearanceSelectionCommand(
            characterID: characterID,
            idempotencyKey: idempotencyKey
        )
        let mutation = SocialMutation(
            id: idempotencyKey,
            kind: .petAppearanceSelection,
            aggregateID: nil,
            idempotencyKey: idempotencyKey,
            body: .object([
                "appearanceSchemaVersion": .number(Double(command.appearanceSchemaVersion)),
                "appearanceCatalogVersion": .number(Double(command.appearanceCatalogVersion)),
                "appearance": .object(command.appearance.mapValues(JSONValue.string))
            ])
        )
        return try await deliver(mutation) {
            try await backend.updateOwnPetAppearance(command)
        }
    }

    func react(
        visitID: PetVisitID,
        reaction: PetReaction,
        text: String? = nil,
        idempotencyKey: UUID = UUID()
    ) async throws -> VisitAction {
        _ = try requireActiveVisit(visitID)
        var payload: [String: JSONValue] = ["reaction": .string(reaction.rawValue)]
        if let text { payload["text"] = .string(text) }
        let command = CreateVisitActionCommand(
            kind: .reaction,
            actorType: .petAgent,
            payload: .object(payload),
            replyToActionID: idempotencyKey,
            idempotencyKey: idempotencyKey
        )
        return try await deliver(actionMutation(visitID: visitID, command: command)) {
            try await backend.createVisitAction(visitID: visitID, command: command)
        }
    }

    /// Letter bodies go directly to the letter endpoint and are never exposed to
    /// an Agent callback or included in a social event payload.
    func leaveLetter(
        visitID: PetVisitID,
        body: String,
        idempotencyKey: UUID = UUID()
    ) async throws -> PetLetter {
        _ = try requireActiveVisit(visitID)
        let normalized = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw VisitCoordinationError.emptyLetter }
        let mutation = SocialMutation(
            id: idempotencyKey,
            kind: .createLetter,
            aggregateID: visitID.rawValue,
            idempotencyKey: idempotencyKey,
            body: .object(["body": .string(normalized)])
        )
        return try await deliver(mutation) {
            try await backend.createLetter(
                visitID: visitID,
                command: CreateLetterCommand(body: normalized, idempotencyKey: idempotencyKey)
            )
        }
    }

    func fetchLetter(
        friendshipID _: FriendshipID,
        _ letterID: LetterID
    ) async throws -> PetLetter {
        try await backend.fetchLetter(letterID)
    }

    func end(
        visitID: PetVisitID,
        actorType: VisitActionActorType = .human,
        idempotencyKey: UUID = UUID()
    ) async throws -> Visit {
        _ = try requireVisit(visitID)
        let mutation = SocialMutation(
            id: idempotencyKey,
            kind: .endVisit,
            aggregateID: visitID.rawValue,
            idempotencyKey: idempotencyKey,
            body: .object(["actorType": .string(actorType.rawValue)])
        )
        let visit = try await deliver(mutation) {
            try await backend.endVisit(
                visitID: visitID,
                command: EndVisitCommand(actorType: actorType, idempotencyKey: idempotencyKey)
            )
        }
        visits[visit.id] = visit
        return visit
    }

    func apply(_ visit: Visit) {
        visits[visit.id] = visit
    }

    func visit(id: PetVisitID) -> Visit? {
        visits[id]
    }

    func retryPendingMutations(now: Date = Date()) async {
        guard let pending = try? await outbox.due(at: now) else { return }
        for mutation in pending {
            do {
                try await retry(mutation)
                try await outbox.markSucceeded(mutation.id)
            } catch {
                guard shouldRetrySocialMutation(error) else {
                    try? await outbox.markSucceeded(mutation.id)
                    continue
                }
                let exponent = min(mutation.attemptCount, 7)
                let delay = min(300, pow(2, Double(exponent + 1)))
                try? await outbox.markFailed(
                    mutation.id,
                    retryAt: now.addingTimeInterval(delay)
                )
            }
        }
    }

    private func retry(_ mutation: SocialMutation) async throws {
        let key = mutation.idempotencyKey
        switch mutation.kind {
        case .createVisit:
            guard let friendshipID = mutation.body["friendshipID"]?.stringValue,
                  let visitorPetID = mutation.body["visitorPetID"]?.stringValue,
                  let hostAccountID = mutation.body["hostAccountID"]?.stringValue
            else { throw VisitCoordinationError.invalidOutboxMutation }
            _ = try await backend.createVisit(
                CreateVisitCommand(
                    friendshipID: FriendshipID(rawValue: friendshipID),
                    visitorPetID: PetProfileID(rawValue: visitorPetID),
                    hostAccountID: AccountID(rawValue: hostAccountID),
                    reason: mutation.body["reason"]?.stringValue,
                    idempotencyKey: key
                )
            )
        case .respondVisit:
            guard let visitID = mutation.aggregateID,
                  let response = mutation.body["response"]?.stringValue.flatMap(VisitResponse.init(rawValue:)),
                  let actor = mutation.body["actorType"]?.stringValue.flatMap(VisitActionActorType.init(rawValue:))
            else { throw VisitCoordinationError.invalidOutboxMutation }
            _ = try await backend.respondToVisit(
                visitID: PetVisitID(rawValue: visitID),
                command: RespondToVisitCommand(response: response, actorType: actor, idempotencyKey: key)
            )
        case .createVisitAction:
            guard let visitID = mutation.aggregateID,
                  let kind = mutation.body["kind"]?.stringValue.flatMap(VisitActionKind.init(rawValue:)),
                  let actor = mutation.body["actorType"]?.stringValue.flatMap(VisitActionActorType.init(rawValue:)),
                  let payload = mutation.body["payload"]
            else { throw VisitCoordinationError.invalidOutboxMutation }
            let replyID = mutation.body["replyToActionID"]?.stringValue.flatMap(UUID.init(uuidString:))
            _ = try await backend.createVisitAction(
                visitID: PetVisitID(rawValue: visitID),
                command: CreateVisitActionCommand(
                    kind: kind,
                    actorType: actor,
                    payload: payload,
                    replyToActionID: replyID,
                    idempotencyKey: key
                )
            )
        case .endVisit:
            guard let visitID = mutation.aggregateID,
                  let actor = mutation.body["actorType"]?.stringValue.flatMap(VisitActionActorType.init(rawValue:))
            else { throw VisitCoordinationError.invalidOutboxMutation }
            _ = try await backend.endVisit(
                visitID: PetVisitID(rawValue: visitID),
                command: EndVisitCommand(actorType: actor, idempotencyKey: key)
            )
        case .createLetter:
            guard let visitID = mutation.aggregateID,
                  let body = mutation.body["body"]?.stringValue
            else { throw VisitCoordinationError.invalidOutboxMutation }
            _ = try await backend.createLetter(
                visitID: PetVisitID(rawValue: visitID),
                command: CreateLetterCommand(body: body, idempotencyKey: key)
            )
        case .createConversation:
            guard let friendshipID = mutation.body["friendshipID"]?.stringValue,
                  let recipientPetID = mutation.body["recipientPetID"]?.stringValue,
                  let openingMessage = mutation.body["openingMessage"]?.stringValue
            else { throw VisitCoordinationError.invalidOutboxMutation }
            _ = try await backend.createConversation(
                CreateConversationCommand(
                    friendshipID: FriendshipID(rawValue: friendshipID),
                    recipientPetID: PetProfileID(rawValue: recipientPetID),
                    openingMessage: openingMessage,
                    idempotencyKey: key
                )
            )
        case .sendConversationMessage:
            guard let conversationID = mutation.aggregateID,
                  let actor = mutation.body["actorType"]?.stringValue.flatMap(SocialActorType.init(rawValue:)),
                  let text = mutation.body["text"]?.stringValue
            else { throw VisitCoordinationError.invalidOutboxMutation }
            _ = try await backend.sendConversationMessage(
                conversationID: ConversationID(rawValue: conversationID),
                command: SendConversationMessageCommand(
                    actorType: actor,
                    text: text,
                    idempotencyKey: key
                )
            )
        case .endConversation:
            guard let conversationID = mutation.aggregateID,
                  let summary = mutation.body["summary"]?.stringValue
            else { throw VisitCoordinationError.invalidOutboxMutation }
            _ = try await backend.endConversation(
                conversationID: ConversationID(rawValue: conversationID),
                command: EndConversationCommand(summary: summary, idempotencyKey: key)
            )
        case .petInteraction:
            guard let petID = mutation.body["petID"]?.stringValue,
                  let kind = mutation.body["kind"]?.stringValue.flatMap(
                    PetCareInteractionKind.init(rawValue:)
                  ),
                  let occurredAt = mutation.body["occurredAt"]?.numberValue
            else { throw VisitCoordinationError.invalidOutboxMutation }
            _ = try await backend.interactWithPet(
                petID: PetProfileID(rawValue: petID),
                command: PetInteractionCommand(
                    kind: kind,
                    visitID: mutation.body["visitID"]?.stringValue.map(
                        PetVisitID.init(rawValue:)
                    ),
                    occurredAt: Date(timeIntervalSince1970: occurredAt / 1_000),
                    idempotencyKey: key
                )
            )
        case .petAppearanceSelection:
            guard
                let schema = mutation.body["appearanceSchemaVersion"]?.numberValue,
                let catalog = mutation.body["appearanceCatalogVersion"]?.numberValue,
                Int(schema) == PetCharacterID.appearanceSchema,
                Int(catalog) == PetCharacterID.appearanceCatalog,
                case .object(let appearance)? = mutation.body["appearance"],
                let rigID = appearance["rigID"]?.stringValue,
                let body = appearance["body"]?.stringValue,
                let characterID = PetCharacterID(appearance: ["rigID": rigID, "body": body])
            else { throw VisitCoordinationError.invalidOutboxMutation }
            _ = try await backend.updateOwnPetAppearance(
                PetAppearanceSelectionCommand(
                    characterID: characterID,
                    idempotencyKey: key
                )
            )
        }
    }

    private func actionMutation(
        visitID: PetVisitID,
        command: CreateVisitActionCommand
    ) -> SocialMutation {
        var body: [String: JSONValue] = [
            "kind": .string(command.kind.rawValue),
            "actorType": .string(command.actorType.rawValue),
            "payload": command.payload
        ]
        if let reply = command.replyToActionID {
            body["replyToActionID"] = .string(reply.uuidString)
        }
        return SocialMutation(
            id: command.idempotencyKey,
            kind: .createVisitAction,
            aggregateID: visitID.rawValue,
            idempotencyKey: command.idempotencyKey,
            body: .object(body)
        )
    }

    private func deliver<Value: Sendable>(
        _ mutation: SocialMutation,
        operation: () async throws -> Value
    ) async throws -> Value {
        try await outbox.enqueue(mutation)
        do {
            let value = try await operation()
            try await outbox.markSucceeded(mutation.id)
            return value
        } catch {
            if shouldRetrySocialMutation(error) {
                try? await outbox.markFailed(
                    mutation.id,
                    retryAt: Date().addingTimeInterval(2)
                )
            } else {
                try? await outbox.markSucceeded(mutation.id)
            }
            throw error
        }
    }

    private func requireVisit(_ id: PetVisitID) throws -> Visit {
        guard let visit = visits[id] else {
            throw VisitCoordinationError.visitNotActive
        }
        return visit
    }

    private func requireActiveVisit(_ id: PetVisitID) throws -> Visit {
        let visit = try requireVisit(id)
        guard visit.status == .active else {
            throw VisitCoordinationError.visitNotActive
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

    func updateDisplayName(_ displayName: String) async {
        identity = AgentIdentity(
            petID: identity.petID,
            ownerAccountID: identity.ownerAccountID,
            displayName: displayName,
            friends: identity.friends,
            localeIdentifier: identity.localeIdentifier
        )
        await agent.updateDisplayName(displayName)
    }

    func hasFriends() -> Bool {
        !identity.friends.isEmpty
    }

    func snapshot() async -> LocalPetAgentSnapshot {
        await agent.snapshot()
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

    func applyVisit(_ visit: Visit) async {
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

    /// Pushes care / owner / companion facts into the Agent without starting a turn.
    func updateVisibleSituation(_ situation: PetSituation) async {
        var state = await agent.snapshot().state
        state.applyVisibleSituation(situation)
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
                    reaction: reaction,
                    idempotencyKey: idempotencyKey
                )
            } else {
                await onReaction(reaction)
            }

        case .requestReturn(let visitID):
            _ = try await visits.end(
                visitID: visitID,
                actorType: .petAgent,
                idempotencyKey: idempotencyKey
            )
        }
    }

}
