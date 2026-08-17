import Foundation
import MinoDomain

public enum PetPolicyViolation: Error, Equatable, Sendable {
    case unsupportedDecisionSchema(expected: Int, actual: Int)
    case actionNotAllowed(PetActionKind)
    case targetIsNotFriend(PetProfileID)
    case invitationMismatch
    case visitMismatch
    case emptyText(field: String)
    case textTooLong(field: String, maximum: Int)
    case invalidControlCharacters(field: String)
    case invalidMemory
}

public struct PetPolicyGuard: Sendable {
    public struct Configuration: Equatable, Sendable {
        public let maximumMessageCharacters: Int
        public let maximumReasonCharacters: Int
        public let maximumMemoryCharacters: Int

        public init(
            maximumMessageCharacters: Int = 500,
            maximumReasonCharacters: Int = 200,
            maximumMemoryCharacters: Int = 500
        ) {
            self.maximumMessageCharacters = max(1, maximumMessageCharacters)
            self.maximumReasonCharacters = max(1, maximumReasonCharacters)
            self.maximumMemoryCharacters = max(1, maximumMemoryCharacters)
        }
    }

    public let configuration: Configuration

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    public func allowedActions(for context: AgentContext) -> [PetActionKind] {
        var allowed: Set<PetActionKind> = [.idle, .speakToOwner]

        if context.state.autonomousSocialEnabled,
           context.currentEvent.kind != .conversationEnded {
            allowed.insert(.sendPetMessage)
            if case .home = context.state.location {
                allowed.insert(.proposeVisit)
            }
            if context.currentEvent.kind == .visitInvitation,
               case .home = context.state.location {
                allowed.insert(.respondToVisit)
            }
        }

        if context.currentEvent.kind == .visitInteraction
            || context.currentEvent.kind == .visitStarted
            || context.currentEvent.kind == .ownerInteraction {
            allowed.insert(.reactToInteraction)
        }
        if case .visiting = context.state.location {
            allowed.insert(.requestReturn)
        }

        return PetActionKind.allCases.filter(allowed.contains)
    }

    public func validate(
        decision: PetDecision,
        memoryDisposition: MemoryDisposition,
        in context: AgentContext,
        allowedActions: [PetActionKind]
    ) throws {
        guard decision.schemaVersion == PetDecision.currentSchemaVersion else {
            throw PetPolicyViolation.unsupportedDecisionSchema(
                expected: PetDecision.currentSchemaVersion,
                actual: decision.schemaVersion
            )
        }
        guard allowedActions.contains(decision.action.kind) else {
            throw PetPolicyViolation.actionNotAllowed(decision.action.kind)
        }

        if let publicReason = decision.publicReason {
            try validateText(
                publicReason,
                field: "publicReason",
                maximum: configuration.maximumReasonCharacters
            )
        }

        switch decision.action {
        case .idle:
            break
        case let .speakToOwner(text):
            try validateText(
                text,
                field: "text",
                maximum: configuration.maximumMessageCharacters
            )
        case let .sendPetMessage(petID, text):
            guard context.identity.friend(withPetID: petID) != nil else {
                throw PetPolicyViolation.targetIsNotFriend(petID)
            }
            try validateText(
                text,
                field: "text",
                maximum: configuration.maximumMessageCharacters
            )
        case let .proposeVisit(petID, reason):
            guard context.identity.friend(withPetID: petID) != nil else {
                throw PetPolicyViolation.targetIsNotFriend(petID)
            }
            try validateText(
                reason,
                field: "reason",
                maximum: configuration.maximumReasonCharacters
            )
        case let .respondToVisit(invitationID, _):
            guard context.currentEvent.invitationID == invitationID else {
                throw PetPolicyViolation.invitationMismatch
            }
        case .reactToInteraction:
            guard context.currentEvent.kind == .visitInteraction
                    || context.currentEvent.kind == .visitStarted
                    || context.currentEvent.kind == .ownerInteraction else {
                throw PetPolicyViolation.actionNotAllowed(.reactToInteraction)
            }
        case let .requestReturn(visitID):
            guard case let .visiting(activeVisitID) = context.state.location,
                  activeVisitID == visitID else {
                throw PetPolicyViolation.visitMismatch
            }
        }

        switch memoryDisposition {
        case .discard, .session:
            break
        case let .longTerm(summary, reason):
            do {
                try validateText(
                    summary,
                    field: "memorySummary",
                    maximum: configuration.maximumMemoryCharacters
                )
                try validateText(
                    reason,
                    field: "memoryReason",
                    maximum: configuration.maximumReasonCharacters
                )
            } catch {
                throw PetPolicyViolation.invalidMemory
            }
        }
    }

    private func validateText(_ value: String, field: String, maximum: Int) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw PetPolicyViolation.emptyText(field: field)
        }
        guard trimmed.count <= maximum else {
            throw PetPolicyViolation.textTooLong(field: field, maximum: maximum)
        }
        let containsDisallowedControl = trimmed.unicodeScalars.contains {
            CharacterSet.controlCharacters.contains($0) && $0 != "\n" && $0 != "\t"
        }
        guard !containsDisallowedControl else {
            throw PetPolicyViolation.invalidControlCharacters(field: field)
        }
    }
}
