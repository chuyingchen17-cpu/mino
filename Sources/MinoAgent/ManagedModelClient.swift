import Foundation
import MinoDomain
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct ManagedModelRequest: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let inferenceID: UUID
    public let context: AgentContext
    public let allowedActions: [PetActionKind]

    public init(
        schemaVersion: Int = ManagedModelRequest.currentSchemaVersion,
        inferenceID: UUID = UUID(),
        context: AgentContext,
        allowedActions: [PetActionKind]
    ) {
        self.schemaVersion = schemaVersion
        self.inferenceID = inferenceID
        self.context = context
        self.allowedActions = allowedActions
    }
}

public struct ManagedModelUsage: Codable, Equatable, Sendable {
    public let inputTokens: Int
    public let outputTokens: Int

    public init(inputTokens: Int, outputTokens: Int) {
        self.inputTokens = max(0, inputTokens)
        self.outputTokens = max(0, outputTokens)
    }
}

public struct ManagedModelResponse: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let inferenceID: UUID
    public let decision: PetDecision
    public let memoryDisposition: MemoryDisposition
    public let usage: ManagedModelUsage?

    public init(
        schemaVersion: Int = ManagedModelResponse.currentSchemaVersion,
        inferenceID: UUID,
        decision: PetDecision,
        memoryDisposition: MemoryDisposition = .discard,
        usage: ManagedModelUsage? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.inferenceID = inferenceID
        self.decision = decision
        self.memoryDisposition = memoryDisposition
        self.usage = usage
    }

    public func validate(for request: ManagedModelRequest) throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw ManagedModelClientError.unsupportedResponseSchema(
                expected: Self.currentSchemaVersion,
                actual: schemaVersion
            )
        }
        guard inferenceID == request.inferenceID else {
            throw ManagedModelClientError.mismatchedInferenceID
        }
        guard request.allowedActions.contains(decision.action.kind) else {
            throw ManagedModelClientError.actionOutsideRequestedSchema(decision.action.kind)
        }
    }
}

public protocol ManagedModelClient: Sendable {
    func decision(for request: ManagedModelRequest) async throws -> ManagedModelResponse
}

public protocol ManagedModelTokenProvider: Sendable {
    func accessToken() async throws -> String?
}

public struct AnonymousManagedModelTokenProvider: ManagedModelTokenProvider {
    public init() {}

    public func accessToken() async throws -> String? {
        nil
    }
}

public enum ManagedModelClientError: Error, Equatable, Sendable {
    case invalidResponse
    case httpStatus(statusCode: Int, code: String?)
    case encoding
    case decoding
    case transport
    case mismatchedInferenceID
    case unsupportedResponseSchema(expected: Int, actual: Int)
    case actionOutsideRequestedSchema(PetActionKind)
}

/// HTTP implementation for the MVP `/agent/decision` endpoint. It deliberately depends only on
/// Foundation so MinoAgent does not need to depend on the broader infrastructure target.
public actor HTTPManagedModelClient: ManagedModelClient {
    private let endpoint: URL
    private let session: URLSession
    private let tokenProvider: any ManagedModelTokenProvider

    public init(
        endpoint: URL,
        session: URLSession = .shared,
        tokenProvider: any ManagedModelTokenProvider = AnonymousManagedModelTokenProvider()
    ) {
        self.endpoint = endpoint
        self.session = session
        self.tokenProvider = tokenProvider
    }

    public func decision(for request: ManagedModelRequest) async throws -> ManagedModelResponse {
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(request.inferenceID.uuidString, forHTTPHeaderField: "X-Inference-ID")
        if let accessToken = try await tokenProvider.accessToken(), !accessToken.isEmpty {
            urlRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        do {
            urlRequest.httpBody = try Self.encoder.encode(ServerDecisionRequest(request))
        } catch {
            throw ManagedModelClientError.encoding
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            throw ManagedModelClientError.transport
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ManagedModelClientError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let envelope = try? Self.decoder.decode(ModelErrorEnvelope.self, from: data)
            throw ManagedModelClientError.httpStatus(
                statusCode: httpResponse.statusCode,
                code: envelope?.error.code
            )
        }

        let serverResponse: ServerDecisionResponse
        do {
            if let envelope = try? Self.decoder.decode(
                ModelResponseEnvelope<ServerDecisionResponse>.self,
                from: data
            ) {
                serverResponse = envelope.data
            } else {
                serverResponse = try Self.decoder.decode(ServerDecisionResponse.self, from: data)
            }
        } catch {
            throw ManagedModelClientError.decoding
        }
        let modelResponse = serverResponse.managedResponse
        try modelResponse.validate(for: request)
        return modelResponse
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private struct ServerDecisionRequest: Encodable, Sendable {
    struct Trigger: Encodable, Sendable {
        let type: String
        let summary: String
    }

    struct State: Encodable, Sendable {
        let location: String
        let visitID: PetVisitID?
        let emotion: PetEmotion
        let autonomousSocialEnabled: Bool
        let ownerAccountID: AccountID
        let friendPetIDs: [PetProfileID]
        let invitationID: PetVisitInvitationID?
        let senderPetID: PetProfileID?
        let currentEventVisitID: PetVisitID?
    }

    struct Memory: Encodable, Sendable {
        let summary: String
        let kind: AgentMemoryCategory
    }

    let inferenceID: UUID
    let petID: PetProfileID
    let trigger: Trigger
    let state: State
    let memories: [Memory]
    let availableActions: [PetActionKind]

    init(_ request: ManagedModelRequest) {
        let context = request.context
        let location: String
        let visitID: PetVisitID?
        switch context.state.location {
        case .home:
            location = "home"
            visitID = nil
        case .visiting(let currentVisitID):
            location = "visiting"
            visitID = currentVisitID
        }

        inferenceID = request.inferenceID
        petID = context.identity.petID
        trigger = Trigger(
            type: context.currentEvent.kind.rawValue,
            summary: context.currentEvent.content ?? context.currentEvent.kind.rawValue
        )
        state = State(
            location: location,
            visitID: visitID,
            emotion: context.state.emotion,
            autonomousSocialEnabled: context.state.autonomousSocialEnabled,
            ownerAccountID: context.identity.ownerAccountID,
            friendPetIDs: context.identity.friends.map(\.petID),
            invitationID: context.currentEvent.invitationID,
            senderPetID: context.currentEvent.relatedPetID,
            currentEventVisitID: context.currentEvent.visitID
        )
        memories = context.relevantMemories.map {
            Memory(summary: $0.summary, kind: $0.category)
        }
        availableActions = request.allowedActions
    }
}

private struct ServerDecisionResponse: Decodable, Sendable {
    let inferenceID: UUID
    let decision: ServerDecision
    let replayed: Bool
    let usage: ManagedModelUsage?
    let memoryDisposition: ServerMemoryDisposition?

    var managedResponse: ManagedModelResponse {
        ManagedModelResponse(
            inferenceID: inferenceID,
            decision: PetDecision(action: decision.action),
            memoryDisposition: memoryDisposition?.value ?? .discard,
            usage: usage
        )
    }
}

private enum ServerMemoryDisposition: Decodable, Sendable {
    case discard
    case session
    case longTerm(summary: String, reason: String)

    private enum CodingKeys: String, CodingKey {
        case kind
        case summary
        case reason
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .kind) {
        case "discard": self = .discard
        case "session": self = .session
        case "long_term":
            self = .longTerm(
                summary: try container.decode(String.self, forKey: .summary),
                reason: try container.decode(String.self, forKey: .reason)
            )
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "Unknown memory disposition"
            )
        }
    }

    var value: MemoryDisposition {
        switch self {
        case .discard: .discard
        case .session: .session
        case .longTerm(let summary, let reason): .longTerm(summary: summary, reason: reason)
        }
    }
}

private enum ServerDecision: Decodable, Sendable {
    case idle
    case speakToOwner(String)
    case sendPetMessage(PetProfileID, String)
    case proposeVisit(PetProfileID, String)
    case respondToVisit(PetVisitInvitationID, PetVisitDecision)
    case reactToInteraction(PetReaction)
    case requestReturn(PetVisitID)

    private enum CodingKeys: String, CodingKey {
        case kind
        case text
        case recipientPetID
        case reason
        case invitationID
        case response
        case reaction
        case visitID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(PetActionKind.self, forKey: .kind)
        switch kind {
        case .idle:
            self = .idle
        case .speakToOwner:
            self = .speakToOwner(try container.decode(String.self, forKey: .text))
        case .sendPetMessage:
            self = .sendPetMessage(
                try container.decode(PetProfileID.self, forKey: .recipientPetID),
                try container.decode(String.self, forKey: .text)
            )
        case .proposeVisit:
            self = .proposeVisit(
                try container.decode(PetProfileID.self, forKey: .recipientPetID),
                try container.decode(String.self, forKey: .reason)
            )
        case .respondToVisit:
            self = .respondToVisit(
                try container.decode(PetVisitInvitationID.self, forKey: .invitationID),
                try container.decode(PetVisitDecision.self, forKey: .response)
            )
        case .reactToInteraction:
            self = .reactToInteraction(
                try container.decode(PetReaction.self, forKey: .reaction)
            )
        case .requestReturn:
            self = .requestReturn(
                try container.decode(PetVisitID.self, forKey: .visitID)
            )
        }
    }

    var action: PetAction {
        switch self {
        case .idle: .idle
        case .speakToOwner(let text): .speakToOwner(text)
        case .sendPetMessage(let petID, let text): .sendPetMessage(petID: petID, text: text)
        case .proposeVisit(let petID, let reason): .proposeVisit(petID: petID, reason: reason)
        case .respondToVisit(let invitationID, let decision):
            .respondToVisit(invitationID: invitationID, decision: decision)
        case .reactToInteraction(let reaction): .reactToInteraction(reaction)
        case .requestReturn(let visitID): .requestReturn(visitID: visitID)
        }
    }
}

private struct ModelResponseEnvelope<Value: Decodable & Sendable>: Decodable, Sendable {
    let data: Value
}

private struct ModelErrorEnvelope: Decodable, Sendable {
    struct ModelError: Decodable, Sendable {
        let code: String?
    }

    let error: ModelError
}
