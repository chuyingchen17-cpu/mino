import Foundation
import MinoDomain

public protocol AccessTokenProvider: Sendable {
    func accessToken() async throws -> String?
}

public struct AnonymousAccessTokenProvider: AccessTokenProvider {
    public init() {}

    public func accessToken() async throws -> String? {
        nil
    }
}

public enum BackendClientError: Error, Equatable, Sendable {
    case invalidRequest
    case invalidResponse
    case httpStatus(statusCode: Int, code: String?)
    case decoding
    case transport(String)
}

public struct OfflineBackendService: MVPBackendService {
    private let apiVersion: String

    public init(apiVersion: String = "v1") {
        self.apiVersion = apiVersion
    }

    public func checkHealth() async throws -> BackendHealth {
        BackendHealth(status: .offline, apiVersion: apiVersion)
    }

    public func sendInteraction(_ command: InteractionCommand) async throws -> InteractionReceipt {
        throw BackendServiceError.offline
    }

    public func fetchPetPresence() async throws -> PetPresenceSnapshot {
        throw BackendServiceError.offline
    }

    public func startPetVisit(_ command: StartPetVisitCommand) async throws -> PetVisitReceipt {
        throw BackendServiceError.offline
    }

    public func returnPetVisit(_ command: ReturnPetVisitCommand) async throws -> PetVisitReceipt {
        throw BackendServiceError.offline
    }

    public func sendPetVisitInvitation(
        _ command: SendPetVisitInvitationCommand
    ) async throws -> PetVisitInvitation {
        throw BackendServiceError.offline
    }

    public func fetchPendingPetVisitInvitations() async throws -> [PetVisitInvitation] {
        throw BackendServiceError.offline
    }

    public func respondToPetVisitInvitation(
        _ command: RespondToPetVisitInvitationCommand
    ) async throws -> PetVisitInvitationReceipt {
        throw BackendServiceError.offline
    }

    public func fetchPersonalTimeline(after cursor: String?) async throws -> PersonalTimelinePage {
        throw BackendServiceError.offline
    }

    public func bootstrapDevelopmentProfile(_ profile: String) async throws -> DevBootstrapProfile {
        throw BackendServiceError.offline
    }

    public func fetchFriends() async throws -> [FriendProfile] {
        throw BackendServiceError.offline
    }

    public func fetchFriendRequests(status: FriendRequestStatus?) async throws -> [FriendRequest] {
        throw BackendServiceError.offline
    }

    public func createFriendRequest(_ command: CreateFriendRequestCommand) async throws -> FriendRequest {
        throw BackendServiceError.offline
    }

    public func respondToFriendRequest(
        requestID: FriendRequestID,
        command: RespondFriendRequestCommand
    ) async throws -> FriendRequest {
        throw BackendServiceError.offline
    }

    public func fetchEvents(
        friendshipID: FriendshipID,
        after eventID: String?
    ) async throws -> FriendshipEventPage {
        throw BackendServiceError.offline
    }

    public func fetchTimelineEvents(
        friendshipID: FriendshipID,
        after eventID: String?
    ) async throws -> FriendshipEventPage {
        throw BackendServiceError.offline
    }

    public func createConversation(
        friendshipID: FriendshipID,
        _ command: CreateConversationCommand
    ) async throws -> ConversationTurnReceipt {
        throw BackendServiceError.offline
    }

    public func fetchConversations(
        friendshipID: FriendshipID,
        status: ConversationStatus?
    ) async throws -> [PetConversation] {
        throw BackendServiceError.offline
    }

    public func fetchConversationMessages(
        friendshipID: FriendshipID,
        conversationID: ConversationID
    ) async throws -> [PetConversationMessage] {
        throw BackendServiceError.offline
    }

    public func sendConversationMessage(
        friendshipID: FriendshipID,
        conversationID: ConversationID,
        command: SendConversationMessageCommand
    ) async throws -> ConversationTurnReceipt {
        throw BackendServiceError.offline
    }

    public func endConversation(
        friendshipID: FriendshipID,
        conversationID: ConversationID,
        command: EndConversationCommand
    ) async throws -> PetConversation {
        throw BackendServiceError.offline
    }

    public func createVisitInvitation(
        friendshipID: FriendshipID,
        _ command: CreateVisitInvitationCommand
    ) async throws -> MVPVisit {
        throw BackendServiceError.offline
    }

    public func fetchVisitInvitations(
        friendshipID: FriendshipID,
        status: MVPVisitStatus?
    ) async throws -> [MVPVisit] {
        throw BackendServiceError.offline
    }

    public func respondToVisitInvitation(
        friendshipID: FriendshipID,
        visitID: PetVisitID,
        command: RespondToVisitInvitationCommand
    ) async throws -> MVPVisit {
        throw BackendServiceError.offline
    }

    public func sendVisitInteraction(
        friendshipID: FriendshipID,
        visitID: PetVisitID,
        command: CreateVisitInteractionCommand
    ) async throws -> VisitInteractionReceipt {
        throw BackendServiceError.offline
    }

    public func sendVisitReaction(
        friendshipID: FriendshipID,
        visitID: PetVisitID,
        command: CreateVisitReactionCommand
    ) async throws -> VisitReactionReceipt {
        throw BackendServiceError.offline
    }

    public func createLetter(
        friendshipID: FriendshipID,
        visitID: PetVisitID,
        command: CreateLetterCommand
    ) async throws -> PetLetter {
        throw BackendServiceError.offline
    }

    public func fetchLetter(
        friendshipID: FriendshipID,
        _ letterID: LetterID
    ) async throws -> PetLetter {
        throw BackendServiceError.offline
    }

    public func endVisit(
        friendshipID: FriendshipID,
        visitID: PetVisitID,
        command: EndVisitCommand
    ) async throws -> EndVisitReceipt {
        throw BackendServiceError.offline
    }
}

public actor HTTPBackendService: MVPBackendService {
    private let session: URLSession
    private let tokenProvider: any AccessTokenProvider
    private let requestBuilder: BackendRequestBuilder

    public init(
        configuration: BackendConfiguration,
        session: URLSession = .shared,
        tokenProvider: any AccessTokenProvider = AnonymousAccessTokenProvider()
    ) {
        self.session = session
        self.tokenProvider = tokenProvider
        self.requestBuilder = BackendRequestBuilder(configuration: configuration)
    }

    public func checkHealth() async throws -> BackendHealth {
        try await perform(requestBuilder.healthRequest(accessToken: nil))
    }

    public func sendInteraction(_ command: InteractionCommand) async throws -> InteractionReceipt {
        let token = try await tokenProvider.accessToken()
        return try await perform(
            requestBuilder.interactionRequest(command, accessToken: token)
        )
    }

    public func fetchPetPresence() async throws -> PetPresenceSnapshot {
        let token = try await tokenProvider.accessToken()
        return try await perform(
            requestBuilder.petPresenceRequest(accessToken: token)
        )
    }

    public func startPetVisit(_ command: StartPetVisitCommand) async throws -> PetVisitReceipt {
        let token = try await tokenProvider.accessToken()
        return try await perform(
            requestBuilder.startPetVisitRequest(command, accessToken: token)
        )
    }

    public func returnPetVisit(_ command: ReturnPetVisitCommand) async throws -> PetVisitReceipt {
        let token = try await tokenProvider.accessToken()
        return try await perform(
            requestBuilder.returnPetVisitRequest(command, accessToken: token)
        )
    }

    public func sendPetVisitInvitation(
        _ command: SendPetVisitInvitationCommand
    ) async throws -> PetVisitInvitation {
        let token = try await tokenProvider.accessToken()
        return try await perform(
            requestBuilder.sendPetVisitInvitationRequest(command, accessToken: token)
        )
    }

    public func fetchPendingPetVisitInvitations() async throws -> [PetVisitInvitation] {
        let token = try await tokenProvider.accessToken()
        return try await perform(
            requestBuilder.pendingPetVisitInvitationsRequest(accessToken: token)
        )
    }

    public func respondToPetVisitInvitation(
        _ command: RespondToPetVisitInvitationCommand
    ) async throws -> PetVisitInvitationReceipt {
        let token = try await tokenProvider.accessToken()
        return try await perform(
            requestBuilder.respondToPetVisitInvitationRequest(command, accessToken: token)
        )
    }

    public func fetchPersonalTimeline(after cursor: String?) async throws -> PersonalTimelinePage {
        let token = try await tokenProvider.accessToken()
        return try await perform(
            requestBuilder.personalTimelineRequest(after: cursor, accessToken: token)
        )
    }

    public func bootstrapDevelopmentProfile(_ profile: String) async throws -> DevBootstrapProfile {
        try await perform(requestBuilder.developmentBootstrapRequest(profile: profile))
    }

    public func fetchFriends() async throws -> [FriendProfile] {
        let token = try await tokenProvider.accessToken()
        let friendships: [FriendshipWire] = try await perform(
            requestBuilder.friendshipsRequest(status: .accepted, accessToken: token)
        )
        return friendships.compactMap(\.friendProfile)
    }

    public func fetchFriendRequests(status: FriendRequestStatus?) async throws -> [FriendRequest] {
        let token = try await tokenProvider.accessToken()
        let friendships: [FriendshipWire] = try await perform(
            requestBuilder.friendshipsRequest(status: status, accessToken: token)
        )
        return friendships.compactMap(\.friendRequest)
    }

    public func createFriendRequest(_ command: CreateFriendRequestCommand) async throws -> FriendRequest {
        let token = try await tokenProvider.accessToken()
        let friendship: FriendshipWire = try await perform(
            requestBuilder.createFriendRequest(command, accessToken: token)
        )
        guard let request = friendship.friendRequest else {
            throw BackendClientError.decoding
        }
        return request
    }

    public func respondToFriendRequest(
        requestID: FriendRequestID,
        command: RespondFriendRequestCommand
    ) async throws -> FriendRequest {
        let token = try await tokenProvider.accessToken()
        let friendship: FriendshipWire = try await perform(
            requestBuilder.respondToFriendRequest(
                requestID: requestID,
                command: command,
                accessToken: token
            )
        )
        guard let request = friendship.friendRequest else {
            throw BackendClientError.decoding
        }
        return request
    }

    public func fetchEvents(
        friendshipID: FriendshipID,
        after eventID: String?
    ) async throws -> FriendshipEventPage {
        let token = try await tokenProvider.accessToken()
        return try await perform(
            requestBuilder.eventsRequest(
                friendshipID: friendshipID,
                after: eventID,
                accessToken: token
            )
        )
    }

    public func fetchTimelineEvents(
        friendshipID: FriendshipID,
        after eventID: String?
    ) async throws -> FriendshipEventPage {
        let token = try await tokenProvider.accessToken()
        return try await perform(
            requestBuilder.timelineRequest(
                friendshipID: friendshipID,
                after: eventID,
                accessToken: token
            )
        )
    }

    public func createConversation(
        friendshipID: FriendshipID,
        _ command: CreateConversationCommand
    ) async throws -> ConversationTurnReceipt {
        let token = try await tokenProvider.accessToken()
        return try await perform(
            requestBuilder.createConversationRequest(
                friendshipID: friendshipID,
                command,
                accessToken: token
            )
        )
    }

    public func fetchConversations(
        friendshipID: FriendshipID,
        status: ConversationStatus?
    ) async throws -> [PetConversation] {
        let token = try await tokenProvider.accessToken()
        return try await perform(
            requestBuilder.conversationsRequest(
                friendshipID: friendshipID,
                status: status,
                accessToken: token
            )
        )
    }

    public func fetchConversationMessages(
        friendshipID: FriendshipID,
        conversationID: ConversationID
    ) async throws -> [PetConversationMessage] {
        let token = try await tokenProvider.accessToken()
        return try await perform(
            requestBuilder.conversationMessagesRequest(
                friendshipID: friendshipID,
                conversationID: conversationID,
                accessToken: token
            )
        )
    }

    public func sendConversationMessage(
        friendshipID: FriendshipID,
        conversationID: ConversationID,
        command: SendConversationMessageCommand
    ) async throws -> ConversationTurnReceipt {
        let token = try await tokenProvider.accessToken()
        return try await perform(
            requestBuilder.sendConversationMessageRequest(
                friendshipID: friendshipID,
                conversationID: conversationID,
                command: command,
                accessToken: token
            )
        )
    }

    public func endConversation(
        friendshipID: FriendshipID,
        conversationID: ConversationID,
        command: EndConversationCommand
    ) async throws -> PetConversation {
        let token = try await tokenProvider.accessToken()
        return try await perform(
            requestBuilder.endConversationRequest(
                friendshipID: friendshipID,
                conversationID: conversationID,
                command: command,
                accessToken: token
            )
        )
    }

    public func createVisitInvitation(
        friendshipID: FriendshipID,
        _ command: CreateVisitInvitationCommand
    ) async throws -> MVPVisit {
        let token = try await tokenProvider.accessToken()
        return try await perform(
            requestBuilder.createVisitInvitationRequest(
                friendshipID: friendshipID,
                command,
                accessToken: token
            )
        )
    }

    public func fetchVisitInvitations(
        friendshipID: FriendshipID,
        status: MVPVisitStatus?
    ) async throws -> [MVPVisit] {
        let token = try await tokenProvider.accessToken()
        return try await perform(
            requestBuilder.visitInvitationsRequest(
                friendshipID: friendshipID,
                status: status,
                accessToken: token
            )
        )
    }

    public func respondToVisitInvitation(
        friendshipID: FriendshipID,
        visitID: PetVisitID,
        command: RespondToVisitInvitationCommand
    ) async throws -> MVPVisit {
        let token = try await tokenProvider.accessToken()
        return try await perform(
            requestBuilder.respondToVisitInvitationRequest(
                friendshipID: friendshipID,
                visitID: visitID,
                command: command,
                accessToken: token
            )
        )
    }

    public func sendVisitInteraction(
        friendshipID: FriendshipID,
        visitID: PetVisitID,
        command: CreateVisitInteractionCommand
    ) async throws -> VisitInteractionReceipt {
        let token = try await tokenProvider.accessToken()
        return try await perform(
            requestBuilder.visitInteractionRequest(
                friendshipID: friendshipID,
                visitID: visitID,
                command: command,
                accessToken: token
            )
        )
    }

    public func sendVisitReaction(
        friendshipID: FriendshipID,
        visitID: PetVisitID,
        command: CreateVisitReactionCommand
    ) async throws -> VisitReactionReceipt {
        let token = try await tokenProvider.accessToken()
        return try await perform(
            requestBuilder.visitReactionRequest(
                friendshipID: friendshipID,
                visitID: visitID,
                command: command,
                accessToken: token
            )
        )
    }

    public func createLetter(
        friendshipID: FriendshipID,
        visitID: PetVisitID,
        command: CreateLetterCommand
    ) async throws -> PetLetter {
        let token = try await tokenProvider.accessToken()
        return try await perform(
            requestBuilder.createLetterRequest(
                friendshipID: friendshipID,
                visitID: visitID,
                command: command,
                accessToken: token
            )
        )
    }

    public func fetchLetter(
        friendshipID: FriendshipID,
        _ letterID: LetterID
    ) async throws -> PetLetter {
        let token = try await tokenProvider.accessToken()
        return try await perform(
            requestBuilder.letterRequest(
                friendshipID: friendshipID,
                letterID: letterID,
                accessToken: token
            )
        )
    }

    public func endVisit(
        friendshipID: FriendshipID,
        visitID: PetVisitID,
        command: EndVisitCommand
    ) async throws -> EndVisitReceipt {
        let token = try await tokenProvider.accessToken()
        return try await perform(
            requestBuilder.endVisitRequest(
                friendshipID: friendshipID,
                visitID: visitID,
                command: command,
                accessToken: token
            )
        )
    }

    private func perform<Response: Decodable & Sendable>(_ request: URLRequest) async throws -> Response {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw BackendClientError.transport(String(describing: error))
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw BackendClientError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let errorEnvelope = try? Self.decoder.decode(APIErrorEnvelope.self, from: data)
            throw BackendClientError.httpStatus(
                statusCode: httpResponse.statusCode,
                code: errorEnvelope?.error.code
            )
        }

        do {
            return try Self.decoder.decode(APIEnvelope<Response>.self, from: data).data
        } catch {
            throw BackendClientError.decoding
        }
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

public enum BackendServiceFactory {
    public static func make(
        configuration: BackendConfiguration,
        tokenProvider: any AccessTokenProvider = AnonymousAccessTokenProvider()
    ) -> any MVPBackendService {
        switch configuration.mode {
        case .offline:
            OfflineBackendService(apiVersion: configuration.apiVersion)
        case .remote:
            HTTPBackendService(
                configuration: configuration,
                tokenProvider: tokenProvider
            )
        }
    }
}

package struct BackendRequestBuilder: Sendable {
    private let configuration: BackendConfiguration

    package init(configuration: BackendConfiguration) {
        self.configuration = configuration
    }

    package func healthRequest(accessToken: String?) throws -> URLRequest {
        try request(path: "health", method: "GET", body: nil, accessToken: accessToken)
    }

    package func interactionRequest(
        _ command: InteractionCommand,
        accessToken: String?
    ) throws -> URLRequest {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let body = try encoder.encode(command)
        var request = try request(
            path: "interactions",
            method: "POST",
            body: body,
            accessToken: accessToken
        )
        request.setValue(command.idempotencyKey.uuidString, forHTTPHeaderField: "Idempotency-Key")
        return request
    }

    package func petPresenceRequest(accessToken: String?) throws -> URLRequest {
        try request(
            pathComponents: ["pet-presence"],
            method: "GET",
            body: nil,
            accessToken: accessToken
        )
    }

    package func startPetVisitRequest(
        _ command: StartPetVisitCommand,
        accessToken: String?
    ) throws -> URLRequest {
        let body = try Self.encoder.encode(command)
        var request = try request(
            pathComponents: ["pet-visits"],
            method: "POST",
            body: body,
            accessToken: accessToken
        )
        request.setValue(command.idempotencyKey.uuidString, forHTTPHeaderField: "Idempotency-Key")
        return request
    }

    package func returnPetVisitRequest(
        _ command: ReturnPetVisitCommand,
        accessToken: String?
    ) throws -> URLRequest {
        let body = try Self.encoder.encode(command)
        var request = try request(
            pathComponents: ["pet-visits", command.visitID.rawValue, "return"],
            method: "POST",
            body: body,
            accessToken: accessToken
        )
        request.setValue(command.idempotencyKey.uuidString, forHTTPHeaderField: "Idempotency-Key")
        return request
    }

    package func sendPetVisitInvitationRequest(
        _ command: SendPetVisitInvitationCommand,
        accessToken: String?
    ) throws -> URLRequest {
        let body = try Self.encoder.encode(command)
        var request = try request(
            pathComponents: ["pet-visit-invitations"],
            method: "POST",
            body: body,
            accessToken: accessToken
        )
        request.setValue(command.idempotencyKey.uuidString, forHTTPHeaderField: "Idempotency-Key")
        return request
    }

    package func pendingPetVisitInvitationsRequest(
        accessToken: String?
    ) throws -> URLRequest {
        var request = try request(
            pathComponents: ["pet-visit-invitations"],
            method: "GET",
            body: nil,
            accessToken: accessToken
        )
        if var components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false) {
            components.queryItems = [URLQueryItem(name: "status", value: "pending")]
            request.url = components.url
        }
        return request
    }

    package func respondToPetVisitInvitationRequest(
        _ command: RespondToPetVisitInvitationCommand,
        accessToken: String?
    ) throws -> URLRequest {
        let body = try Self.encoder.encode(command)
        var request = try request(
            pathComponents: [
                "pet-visit-invitations",
                command.invitationID.rawValue,
                "response"
            ],
            method: "POST",
            body: body,
            accessToken: accessToken
        )
        request.setValue(command.idempotencyKey.uuidString, forHTTPHeaderField: "Idempotency-Key")
        return request
    }

    package func personalTimelineRequest(
        after cursor: String?,
        accessToken: String?
    ) throws -> URLRequest {
        var request = try request(
            pathComponents: ["friendship-events"],
            method: "GET",
            body: nil,
            accessToken: accessToken
        )
        if let cursor, !cursor.isEmpty,
           var components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false) {
            components.queryItems = [URLQueryItem(name: "after", value: cursor)]
            request.url = components.url
        }
        return request
    }

    @available(*, deprecated, renamed: "personalTimelineRequest(after:accessToken:)")
    package func coupleTimelineRequest(
        after cursor: String?,
        accessToken: String?
    ) throws -> URLRequest {
        try personalTimelineRequest(after: cursor, accessToken: accessToken)
    }

    package func developmentBootstrapRequest(profile: String) throws -> URLRequest {
        struct Body: Encodable { let profile: String }
        return try request(
            pathComponents: ["dev", "bootstrap"],
            method: "POST",
            body: Self.encoder.encode(Body(profile: profile)),
            accessToken: nil
        )
    }

    package func friendshipsRequest(
        status: FriendRequestStatus?,
        accessToken: String?
    ) throws -> URLRequest {
        var result = try request(
            pathComponents: ["friendships"],
            method: "GET",
            body: nil,
            accessToken: accessToken
        )
        if let status,
           var components = URLComponents(url: result.url!, resolvingAgainstBaseURL: false) {
            components.queryItems = [URLQueryItem(name: "status", value: status.rawValue)]
            result.url = components.url
        }
        return result
    }

    package func createFriendRequest(
        _ command: CreateFriendRequestCommand,
        accessToken: String?
    ) throws -> URLRequest {
        try idempotentRequest(
            pathComponents: ["friendships"],
            body: command,
            key: command.idempotencyKey,
            accessToken: accessToken
        )
    }

    package func respondToFriendRequest(
        requestID: FriendRequestID,
        command: RespondFriendRequestCommand,
        accessToken: String?
    ) throws -> URLRequest {
        try idempotentRequest(
            pathComponents: ["friendships", requestID.rawValue, "respond"],
            body: command,
            key: command.idempotencyKey,
            accessToken: accessToken
        )
    }

    package func eventsRequest(
        friendshipID: FriendshipID,
        after eventID: String?,
        accessToken: String?
    ) throws -> URLRequest {
        try cursorRequest(
            pathComponents: ["events"],
            friendshipID: friendshipID,
            after: eventID,
            accessToken: accessToken
        )
    }

    package func timelineRequest(
        friendshipID: FriendshipID,
        after eventID: String?,
        accessToken: String?
    ) throws -> URLRequest {
        try cursorRequest(
            pathComponents: ["timeline"],
            friendshipID: friendshipID,
            after: eventID,
            accessToken: accessToken
        )
    }

    package func createConversationRequest(
        friendshipID: FriendshipID,
        _ command: CreateConversationCommand,
        accessToken: String?
    ) throws -> URLRequest {
        try addingFriendshipID(friendshipID, to: idempotentRequest(
            pathComponents: ["conversations"],
            body: command,
            key: command.idempotencyKey,
            accessToken: accessToken
        ))
    }

    package func conversationsRequest(
        friendshipID: FriendshipID,
        status: ConversationStatus?,
        accessToken: String?
    ) throws -> URLRequest {
        var result = try request(
            pathComponents: ["conversations"],
            method: "GET",
            body: nil,
            accessToken: accessToken
        )
        if let status,
           var components = URLComponents(url: result.url!, resolvingAgainstBaseURL: false) {
            components.queryItems = [URLQueryItem(name: "status", value: status.rawValue)]
            result.url = components.url
        }
        return try addingFriendshipID(friendshipID, to: result)
    }

    package func conversationMessagesRequest(
        friendshipID: FriendshipID,
        conversationID: ConversationID,
        accessToken: String?
    ) throws -> URLRequest {
        try addingFriendshipID(friendshipID, to: request(
            pathComponents: ["conversations", conversationID.rawValue, "messages"],
            method: "GET",
            body: nil,
            accessToken: accessToken
        ))
    }

    package func sendConversationMessageRequest(
        friendshipID: FriendshipID,
        conversationID: ConversationID,
        command: SendConversationMessageCommand,
        accessToken: String?
    ) throws -> URLRequest {
        try addingFriendshipID(friendshipID, to: idempotentRequest(
            pathComponents: ["conversations", conversationID.rawValue, "messages"],
            body: command,
            key: command.idempotencyKey,
            accessToken: accessToken
        ))
    }

    package func endConversationRequest(
        friendshipID: FriendshipID,
        conversationID: ConversationID,
        command: EndConversationCommand,
        accessToken: String?
    ) throws -> URLRequest {
        try addingFriendshipID(friendshipID, to: idempotentRequest(
            pathComponents: ["conversations", conversationID.rawValue, "end"],
            body: command,
            key: command.idempotencyKey,
            accessToken: accessToken
        ))
    }

    package func createVisitInvitationRequest(
        friendshipID: FriendshipID,
        _ command: CreateVisitInvitationCommand,
        accessToken: String?
    ) throws -> URLRequest {
        try addingFriendshipID(friendshipID, to: idempotentRequest(
            pathComponents: ["visit-invitations"],
            body: command,
            key: command.idempotencyKey,
            accessToken: accessToken
        ))
    }

    package func visitInvitationsRequest(
        friendshipID: FriendshipID,
        status: MVPVisitStatus?,
        accessToken: String?
    ) throws -> URLRequest {
        var result = try request(
            pathComponents: ["visit-invitations"],
            method: "GET",
            body: nil,
            accessToken: accessToken
        )
        if let status,
           var components = URLComponents(url: result.url!, resolvingAgainstBaseURL: false) {
            components.queryItems = [URLQueryItem(name: "status", value: status.rawValue)]
            result.url = components.url
        }
        return try addingFriendshipID(friendshipID, to: result)
    }

    package func respondToVisitInvitationRequest(
        friendshipID: FriendshipID,
        visitID: PetVisitID,
        command: RespondToVisitInvitationCommand,
        accessToken: String?
    ) throws -> URLRequest {
        try addingFriendshipID(friendshipID, to: idempotentRequest(
            pathComponents: ["visit-invitations", visitID.rawValue, "respond"],
            body: command,
            key: command.idempotencyKey,
            accessToken: accessToken
        ))
    }

    package func visitInteractionRequest(
        friendshipID: FriendshipID,
        visitID: PetVisitID,
        command: CreateVisitInteractionCommand,
        accessToken: String?
    ) throws -> URLRequest {
        try addingFriendshipID(friendshipID, to: idempotentRequest(
            pathComponents: ["visits", visitID.rawValue, "interactions"],
            body: command,
            key: command.idempotencyKey,
            accessToken: accessToken
        ))
    }

    package func visitReactionRequest(
        friendshipID: FriendshipID,
        visitID: PetVisitID,
        command: CreateVisitReactionCommand,
        accessToken: String?
    ) throws -> URLRequest {
        try addingFriendshipID(friendshipID, to: idempotentRequest(
            pathComponents: ["visits", visitID.rawValue, "reactions"],
            body: command,
            key: command.idempotencyKey,
            accessToken: accessToken
        ))
    }

    package func createLetterRequest(
        friendshipID: FriendshipID,
        visitID: PetVisitID,
        command: CreateLetterCommand,
        accessToken: String?
    ) throws -> URLRequest {
        try addingFriendshipID(friendshipID, to: idempotentRequest(
            pathComponents: ["visits", visitID.rawValue, "letter"],
            body: command,
            key: command.idempotencyKey,
            accessToken: accessToken
        ))
    }

    package func letterRequest(
        friendshipID: FriendshipID,
        letterID: LetterID,
        accessToken: String?
    ) throws -> URLRequest {
        try addingFriendshipID(friendshipID, to: request(
            pathComponents: ["letters", letterID.rawValue],
            method: "GET",
            body: nil,
            accessToken: accessToken
        ))
    }

    package func endVisitRequest(
        friendshipID: FriendshipID,
        visitID: PetVisitID,
        command: EndVisitCommand,
        accessToken: String?
    ) throws -> URLRequest {
        try addingFriendshipID(friendshipID, to: idempotentRequest(
            pathComponents: ["visits", visitID.rawValue, "end"],
            body: command,
            key: command.idempotencyKey,
            accessToken: accessToken
        ))
    }

    private func addingFriendshipID(
        _ friendshipID: FriendshipID,
        to request: URLRequest
    ) throws -> URLRequest {
        guard let url = request.url,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw BackendClientError.invalidRequest
        }
        var result = request
        var queryItems = components.queryItems ?? []
        queryItems.removeAll { $0.name == "friendshipID" }
        queryItems.insert(
            URLQueryItem(name: "friendshipID", value: friendshipID.rawValue),
            at: 0
        )
        components.queryItems = queryItems
        guard let scopedURL = components.url else {
            throw BackendClientError.invalidRequest
        }
        result.url = scopedURL
        return result
    }

    private func cursorRequest(
        pathComponents: [String],
        friendshipID: FriendshipID,
        after eventID: String?,
        accessToken: String?
    ) throws -> URLRequest {
        var result = try request(
            pathComponents: pathComponents,
            method: "GET",
            body: nil,
            accessToken: accessToken
        )
        if var components = URLComponents(url: result.url!, resolvingAgainstBaseURL: false) {
            var queryItems = [
                URLQueryItem(name: "friendshipID", value: friendshipID.rawValue)
            ]
            if let eventID, !eventID.isEmpty {
                queryItems.append(URLQueryItem(name: "after", value: eventID))
            }
            components.queryItems = queryItems
            result.url = components.url
        }
        return result
    }

    private func idempotentRequest<Body: Encodable>(
        pathComponents: [String],
        body: Body,
        key: UUID,
        accessToken: String?
    ) throws -> URLRequest {
        var result = try request(
            pathComponents: pathComponents,
            method: "POST",
            body: Self.encoder.encode(body),
            accessToken: accessToken
        )
        result.setValue(key.uuidString, forHTTPHeaderField: "Idempotency-Key")
        return result
    }

    private func request(
        path: String,
        method: String,
        body: Data?,
        accessToken: String?
    ) throws -> URLRequest {
        try request(
            pathComponents: path.split(separator: "/").map(String.init),
            method: method,
            body: body,
            accessToken: accessToken
        )
    }

    private func request(
        pathComponents: [String],
        method: String,
        body: Data?,
        accessToken: String?
    ) throws -> URLRequest {
        guard let baseURL = configuration.baseURL else {
            throw BackendClientError.invalidRequest
        }
        var url = baseURL.appendingPathComponent(configuration.apiVersion, isDirectory: true)
        for (index, component) in pathComponents.enumerated() {
            url.appendPathComponent(component, isDirectory: index < pathComponents.count - 1)
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = configuration.requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        request.setValue("macos", forHTTPHeaderField: "X-Mino-Client")
        if let accessToken, !accessToken.isEmpty {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private struct APIEnvelope<Payload: Decodable & Sendable>: Decodable, Sendable {
    let data: Payload
}

package struct FriendshipWire: Decodable, Sendable {
    struct Friend: Decodable, Sendable {
        let accountID: AccountID
        let displayName: String
        let petID: PetProfileID
        let petName: String
    }

    let id: FriendshipID
    let requesterAccountID: AccountID
    let addresseeAccountID: AccountID
    let status: FriendRequestStatus
    let createdAt: Date
    let respondedAt: Date?
    let friend: Friend

    var friendProfile: FriendProfile? {
        guard status == .accepted else { return nil }
        return FriendProfile(
            friendshipID: id,
            accountID: friend.accountID,
            accountName: friend.displayName,
            petID: friend.petID,
            petName: friend.petName,
            friendsSince: respondedAt ?? createdAt
        )
    }

    var friendRequest: FriendRequest? {
        guard status != .cancelled else { return nil }
        return FriendRequest(
            id: FriendRequestID(rawValue: id.rawValue),
            requesterAccountID: requesterAccountID,
            addresseeAccountID: addresseeAccountID,
            friendAccountID: friend.accountID,
            friendName: friend.displayName,
            friendPetID: friend.petID,
            friendPetName: friend.petName,
            status: status,
            createdAt: createdAt,
            respondedAt: respondedAt
        )
    }
}

private struct APIErrorEnvelope: Decodable, Sendable {
    struct APIError: Decodable, Sendable {
        let code: String
        let message: String?
    }

    let error: APIError
}
