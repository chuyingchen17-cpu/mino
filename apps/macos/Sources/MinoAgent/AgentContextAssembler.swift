import Foundation
import MinoDomain

public enum AgentContextEventKind: String, Codable, Sendable {
    case ownerMessage = "owner_message"
    case ownerInteraction = "owner_interaction"
    case remoteHumanMessage = "remote_human_message"
    case petMessage = "pet_message"
    case conversationEnded = "conversation_ended"
    case visitInvitation = "visit_invitation"
    case visitInteraction = "visit_interaction"
    case visitStarted = "visit_started"
    case visitEnded = "visit_ended"
    case sealedHumanLetterAvailable = "sealed_human_letter_available"
    case periodicWake = "periodic_wake"
}

public struct AgentContextEvent: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let kind: AgentContextEventKind
    public let occurredAt: Date
    public let content: String?
    public let relatedPetID: PetProfileID?
    public let relatedAccountID: AccountID?
    public let invitationID: PetVisitInvitationID?
    public let visitID: PetVisitID?
    public let conversationID: ConversationID?

    public init(
        id: UUID,
        kind: AgentContextEventKind,
        occurredAt: Date,
        content: String? = nil,
        relatedPetID: PetProfileID? = nil,
        relatedAccountID: AccountID? = nil,
        invitationID: PetVisitInvitationID? = nil,
        visitID: PetVisitID? = nil,
        conversationID: ConversationID? = nil
    ) {
        self.id = id
        self.kind = kind
        self.occurredAt = occurredAt
        self.content = content
        self.relatedPetID = relatedPetID
        self.relatedAccountID = relatedAccountID
        self.invitationID = invitationID
        self.visitID = visitID
        self.conversationID = conversationID
    }
}

public struct AgentContext: Codable, Equatable, Sendable {
    public let identity: AgentIdentity
    public let state: AgentPetState
    public let currentEvent: AgentContextEvent
    public let recentEvents: [AgentContextEvent]
    public let relevantMemories: [AgentMemory]

    public init(
        identity: AgentIdentity,
        state: AgentPetState,
        currentEvent: AgentContextEvent,
        recentEvents: [AgentContextEvent],
        relevantMemories: [AgentMemory]
    ) {
        self.identity = identity
        self.state = state
        self.currentEvent = currentEvent
        self.recentEvents = recentEvents
        self.relevantMemories = relevantMemories
    }
}

public struct AgentContextAssembler: Sendable {
    public struct Configuration: Equatable, Sendable {
        public let maximumRecentEvents: Int
        public let maximumMemories: Int
        public let maximumTextCharacters: Int

        public init(
            maximumRecentEvents: Int = 10,
            maximumMemories: Int = 12,
            maximumTextCharacters: Int = 500
        ) {
            self.maximumRecentEvents = max(0, maximumRecentEvents)
            self.maximumMemories = max(0, maximumMemories)
            self.maximumTextCharacters = max(1, maximumTextCharacters)
        }
    }

    public let configuration: Configuration

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    public func assemble(
        identity: AgentIdentity,
        state: AgentPetState,
        current observation: AgentObservation,
        recentObservations: [AgentObservation],
        memories: [AgentMemory]
    ) -> AgentContext {
        let recent = recentObservations
            .filter { $0.id != observation.id }
            .sorted { $0.occurredAt < $1.occurredAt }
            .suffix(configuration.maximumRecentEvents)
            .map(contextEvent)

        let selectedMemories = memories
            .filter { $0.petID == identity.petID }
            .sorted {
                if $0.importance == $1.importance {
                    return $0.createdAt > $1.createdAt
                }
                return $0.importance > $1.importance
            }
            .prefix(configuration.maximumMemories)

        return AgentContext(
            identity: identity,
            state: state,
            currentEvent: contextEvent(observation),
            recentEvents: Array(recent),
            relevantMemories: Array(selectedMemories)
        )
    }

    public func memoryQuery(
        identity: AgentIdentity,
        for observation: AgentObservation
    ) -> AgentMemoryQuery {
        let metadata = memoryMetadata(for: observation)
        return AgentMemoryQuery(
            petID: identity.petID,
            relatedPetID: metadata.relatedPetIDs.first,
            categories: [metadata.category],
            terms: searchTerms(for: observation),
            limit: configuration.maximumMemories
        )
    }

    public func memoryMetadata(
        for observation: AgentObservation
    ) -> (category: AgentMemoryCategory, relatedPetIDs: [PetProfileID], importance: Double) {
        switch observation.kind {
        case .ownerMessage:
            (.owner, [], 0.6)
        case .ownerInteraction:
            (.interaction, [], 0.55)
        case .remoteHumanMessage:
            (.general, [], 0.6)
        case let .petMessage(senderPetID, _):
            (.friendPet, [senderPetID], 0.6)
        case .conversationEnded:
            (.friendPet, [], 0.7)
        case let .visitInvitation(_, senderPetID, _):
            (.visit, [senderPetID], 0.55)
        case .visitInteraction:
            (.interaction, [], 0.55)
        case .visitStarted:
            (.visit, [], 0.75)
        case .visitEnded:
            (.visit, [], 0.7)
        case .sealedHumanLetterAvailable:
            (.general, [], 0.5)
        case .periodicWake:
            (.general, [], 0.3)
        }
    }

    public func contextEvent(_ observation: AgentObservation) -> AgentContextEvent {
        switch observation.kind {
        case let .ownerMessage(text):
            AgentContextEvent(
                id: observation.id,
                kind: .ownerMessage,
                occurredAt: observation.occurredAt,
                content: sanitized(text)
            )
        case let .ownerInteraction(stimulus):
            AgentContextEvent(
                id: observation.id,
                kind: .ownerInteraction,
                occurredAt: observation.occurredAt,
                content: interactionContent(stimulus)
            )
        case let .remoteHumanMessage(senderAccountID, text):
            AgentContextEvent(
                id: observation.id,
                kind: .remoteHumanMessage,
                occurredAt: observation.occurredAt,
                content: sanitized(text),
                relatedAccountID: senderAccountID
            )
        case let .petMessage(senderPetID, text):
            AgentContextEvent(
                id: observation.id,
                kind: .petMessage,
                occurredAt: observation.occurredAt,
                content: sanitized(text),
                relatedPetID: senderPetID
            )
        case let .conversationEnded(conversationID, transcript):
            AgentContextEvent(
                id: observation.id,
                kind: .conversationEnded,
                occurredAt: observation.occurredAt,
                content: sanitized(transcript.suffix(12).joined(separator: "\n")),
                conversationID: conversationID
            )
        case let .visitInvitation(invitationID, senderPetID, reason):
            AgentContextEvent(
                id: observation.id,
                kind: .visitInvitation,
                occurredAt: observation.occurredAt,
                content: reason.map(sanitized),
                relatedPetID: senderPetID,
                invitationID: invitationID
            )
        case let .visitInteraction(visitID, actorAccountID, stimulus):
            AgentContextEvent(
                id: observation.id,
                kind: .visitInteraction,
                occurredAt: observation.occurredAt,
                content: interactionContent(stimulus),
                relatedAccountID: actorAccountID,
                visitID: visitID
            )
        case let .visitStarted(visitID, hostAccountID):
            AgentContextEvent(
                id: observation.id,
                kind: .visitStarted,
                occurredAt: observation.occurredAt,
                relatedAccountID: hostAccountID,
                visitID: visitID
            )
        case let .visitEnded(visitID):
            AgentContextEvent(
                id: observation.id,
                kind: .visitEnded,
                occurredAt: observation.occurredAt,
                visitID: visitID
            )
        case let .sealedHumanLetterAvailable(senderAccountID):
            AgentContextEvent(
                id: observation.id,
                kind: .sealedHumanLetterAvailable,
                occurredAt: observation.occurredAt,
                content: nil,
                relatedAccountID: senderAccountID
            )
        case .periodicWake:
            AgentContextEvent(
                id: observation.id,
                kind: .periodicWake,
                occurredAt: observation.occurredAt
            )
        }
    }

    private func interactionContent(_ stimulus: PetInteractionStimulus) -> String {
        switch stimulus {
        case let .feeding(foodName):
            guard let foodName else { return "feeding" }
            return "feeding: \(sanitized(foodName))"
        case .play:
            return "play"
        case let .message(text):
            return "message: \(sanitized(text))"
        }
    }

    private func searchTerms(for observation: AgentObservation) -> [String] {
        let text: String?
        switch observation.kind {
        case let .ownerMessage(value),
             let .remoteHumanMessage(_, value),
             let .petMessage(_, value):
            text = value
        case let .conversationEnded(_, transcript):
            text = transcript.suffix(4).joined(separator: " ")
        case let .visitInvitation(_, _, reason):
            text = reason
        case let .visitInteraction(_, _, .message(value)):
            text = value
        case let .ownerInteraction(.message(value)):
            text = value
        default:
            text = nil
        }

        guard let text else { return [] }
        return text
            .split(whereSeparator: { $0.isWhitespace || $0.isPunctuation })
            .prefix(6)
            .map { String($0.prefix(32)).lowercased() }
            .filter { !$0.isEmpty }
    }

    private func sanitized(_ value: String) -> String {
        let normalized = value
            .replacingOccurrences(of: "\0", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(normalized.prefix(configuration.maximumTextCharacters))
    }
}
