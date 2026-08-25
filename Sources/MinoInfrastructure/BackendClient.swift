import Foundation
import MinoDomain

public protocol AccessTokenProvider: Sendable {
    func accessToken() async throws -> String?
}

public struct AnonymousAccessTokenProvider: AccessTokenProvider {
    public init() {}
    public func accessToken() async throws -> String? { nil }
}

public enum BackendClientError: Error, Equatable, Sendable {
    case invalidRequest
    case invalidResponse
    case httpStatus(statusCode: Int, code: String?)
    case decoding
    case transport(String)
}

public struct OfflineBackendService: AccountBackendService {
    private let apiVersion: String
    public init(apiVersion: String = "v1") { self.apiVersion = apiVersion }

    public func checkHealth() async throws -> BackendHealth {
        BackendHealth(status: .offline, apiVersion: apiVersion)
    }
    public func startGitHubDeviceAuthorization() async throws -> GitHubDeviceAuthorization { throw BackendServiceError.offline }
    public func completeGitHubDeviceAuthorization(deviceCode: String, device: DeviceMetadata) async throws -> GitHubDeviceCompletion { throw BackendServiceError.offline }
    public func refreshSession(_ refreshToken: String) async throws -> AccountSession { throw BackendServiceError.offline }
    public func logout() async throws { throw BackendServiceError.offline }
    public func bootstrapDevelopmentProfile(_ profile: String) async throws -> DevBootstrapProfile { throw BackendServiceError.offline }
    public func fetchCurrentProfile() async throws -> CurrentProfile { throw BackendServiceError.offline }
    public func updateCurrentProfile(accountName: String, petName: String) async throws -> CurrentProfile { throw BackendServiceError.offline }
    public func updateOwnPetAppearance(_ command: PetAppearanceSelectionCommand) async throws -> PublicPetSnapshot { throw BackendServiceError.offline }
    public func fetchOwnPetCare() async throws -> PetCareState { throw BackendServiceError.offline }
    public func interactWithPet(petID: PetProfileID, command: PetInteractionCommand) async throws -> PetInteractionReceipt { throw BackendServiceError.offline }
    public func fetchFriends() async throws -> [FriendProfile] { throw BackendServiceError.offline }
    public func fetchFriendRequests(status: FriendRequestStatus?) async throws -> [FriendRequest] { throw BackendServiceError.offline }
    public func createFriendRequest(_ command: CreateFriendRequestCommand) async throws -> FriendRequest { throw BackendServiceError.offline }
    public func respondToFriendRequest(friendshipID: FriendshipID, command: RespondFriendRequestCommand) async throws -> FriendRequest { throw BackendServiceError.offline }
    public func closeFriendship(_ friendshipID: FriendshipID, idempotencyKey: UUID) async throws { throw BackendServiceError.offline }
    public func fetchSyncBootstrap() async throws -> SyncBootstrap { throw BackendServiceError.offline }
    public func fetchAccountEvents(after cursor: Int64, limit: Int, timelineVisible: Bool?) async throws -> AccountEventPage { throw BackendServiceError.offline }
    public func fetchVisits(status: VisitStatus?) async throws -> [Visit] { throw BackendServiceError.offline }
    public func createVisit(_ command: CreateVisitCommand) async throws -> Visit { throw BackendServiceError.offline }
    public func respondToVisit(visitID: PetVisitID, command: RespondToVisitCommand) async throws -> Visit { throw BackendServiceError.offline }
    public func endVisit(visitID: PetVisitID, command: EndVisitCommand) async throws -> Visit { throw BackendServiceError.offline }
    public func createVisitAction(visitID: PetVisitID, command: CreateVisitActionCommand) async throws -> VisitAction { throw BackendServiceError.offline }
    public func createConversation(_ command: CreateConversationCommand) async throws -> ConversationTurnReceipt { throw BackendServiceError.offline }
    public func fetchConversations() async throws -> [PetConversation] { throw BackendServiceError.offline }
    public func fetchConversationMessages(conversationID: ConversationID) async throws -> [PetConversationMessage] { throw BackendServiceError.offline }
    public func sendConversationMessage(conversationID: ConversationID, command: SendConversationMessageCommand) async throws -> ConversationTurnReceipt { throw BackendServiceError.offline }
    public func endConversation(conversationID: ConversationID, command: EndConversationCommand) async throws -> PetConversation { throw BackendServiceError.offline }
    public func createLetter(visitID: PetVisitID, command: CreateLetterCommand) async throws -> PetLetter { throw BackendServiceError.offline }
    public func fetchLetter(_ letterID: LetterID) async throws -> PetLetter { throw BackendServiceError.offline }
    public func claimPrimaryAgentDevice(_ deviceID: DeviceID, idempotencyKey: UUID) async throws { throw BackendServiceError.offline }
}

public actor HTTPBackendService: AccountBackendService {
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
        try await perform(requestBuilder.healthRequest())
    }

    public func startGitHubDeviceAuthorization() async throws -> GitHubDeviceAuthorization {
        try await perform(requestBuilder.githubDeviceStartRequest())
    }

    public func completeGitHubDeviceAuthorization(
        deviceCode: String,
        device: DeviceMetadata
    ) async throws -> GitHubDeviceCompletion {
        try await perform(requestBuilder.githubDeviceCompleteRequest(
            deviceCode: deviceCode,
            device: device
        ))
    }

    public func refreshSession(_ refreshToken: String) async throws -> AccountSession {
        try await perform(requestBuilder.refreshSessionRequest(refreshToken: refreshToken))
    }

    public func logout() async throws {
        try await performWithoutBody(try await authorized { try $0.logoutRequest(accessToken: $1) })
    }

    public func bootstrapDevelopmentProfile(_ profile: String) async throws -> DevBootstrapProfile {
        try await perform(requestBuilder.developmentBootstrapRequest(profile: profile))
    }

    public func fetchCurrentProfile() async throws -> CurrentProfile {
        try await perform(try await authorized { try $0.currentProfileRequest(accessToken: $1) })
    }

    public func updateCurrentProfile(accountName: String, petName: String) async throws -> CurrentProfile {
        try await perform(try await authorized {
            try $0.updateCurrentProfileRequest(accountName: accountName, petName: petName, accessToken: $1)
        })
    }

    public func updateOwnPetAppearance(
        _ command: PetAppearanceSelectionCommand
    ) async throws -> PublicPetSnapshot {
        try await perform(try await authorized {
            try $0.updateOwnPetAppearanceRequest(command, accessToken: $1)
        })
    }

    public func fetchOwnPetCare() async throws -> PetCareState {
        try await perform(try await authorized { try $0.ownPetCareRequest(accessToken: $1) })
    }

    public func interactWithPet(
        petID: PetProfileID,
        command: PetInteractionCommand
    ) async throws -> PetInteractionReceipt {
        try await perform(try await authorized {
            try $0.petInteractionRequest(petID: petID, command: command, accessToken: $1)
        })
    }

    public func fetchFriends() async throws -> [FriendProfile] {
        let wires: [FriendshipWire] = try await perform(try await authorized {
            try $0.friendshipsRequest(status: .accepted, accessToken: $1)
        })
        return wires.compactMap(\.friendProfile)
    }

    public func fetchFriendRequests(status: FriendRequestStatus?) async throws -> [FriendRequest] {
        let wires: [FriendshipWire] = try await perform(try await authorized {
            try $0.friendshipsRequest(status: status, accessToken: $1)
        })
        return wires.compactMap(\.friendRequest)
    }

    public func createFriendRequest(_ command: CreateFriendRequestCommand) async throws -> FriendRequest {
        let wire: FriendshipWire = try await perform(try await authorized {
            try $0.createFriendRequest(command, accessToken: $1)
        })
        guard let value = wire.friendRequest else { throw BackendClientError.decoding }
        return value
    }

    public func respondToFriendRequest(
        friendshipID: FriendshipID,
        command: RespondFriendRequestCommand
    ) async throws -> FriendRequest {
        let wire: FriendshipWire = try await perform(try await authorized {
            try $0.respondToFriendRequest(friendshipID: friendshipID, command: command, accessToken: $1)
        })
        guard let value = wire.friendRequest else {
            if let friend = wire.friendProfile {
                return FriendRequest(
                    id: FriendRequestID(rawValue: friend.friendshipID.rawValue),
                    requesterAccountID: wire.requesterAccountID,
                    addresseeAccountID: wire.addresseeAccountID,
                    friendAccountID: friend.accountID,
                    friendName: friend.accountName,
                    friendPetID: friend.petID,
                    friendPetName: friend.petName,
                    status: .accepted,
                    createdAt: wire.createdAt,
                    respondedAt: wire.respondedAt
                )
            }
            throw BackendClientError.decoding
        }
        return value
    }

    public func closeFriendship(_ friendshipID: FriendshipID, idempotencyKey: UUID) async throws {
        let _: FriendshipWire = try await perform(try await authorized {
            try $0.closeFriendshipRequest(friendshipID: friendshipID, idempotencyKey: idempotencyKey, accessToken: $1)
        })
    }

    public func fetchSyncBootstrap() async throws -> SyncBootstrap {
        try await perform(try await authorized { try $0.syncBootstrapRequest(accessToken: $1) })
    }

    public func fetchAccountEvents(
        after cursor: Int64,
        limit: Int = 100,
        timelineVisible: Bool? = nil
    ) async throws -> AccountEventPage {
        try await perform(try await authorized {
            try $0.accountEventsRequest(after: cursor, limit: limit, timelineVisible: timelineVisible, accessToken: $1)
        })
    }

    public func fetchVisits(status: VisitStatus?) async throws -> [Visit] {
        try await perform(try await authorized { try $0.visitsRequest(status: status, accessToken: $1) })
    }

    public func createVisit(_ command: CreateVisitCommand) async throws -> Visit {
        try await perform(try await authorized { try $0.createVisitRequest(command, accessToken: $1) })
    }

    public func respondToVisit(visitID: PetVisitID, command: RespondToVisitCommand) async throws -> Visit {
        try await perform(try await authorized {
            try $0.respondToVisitRequest(visitID: visitID, command: command, accessToken: $1)
        })
    }

    public func endVisit(visitID: PetVisitID, command: EndVisitCommand) async throws -> Visit {
        try await perform(try await authorized {
            try $0.endVisitRequest(visitID: visitID, command: command, accessToken: $1)
        })
    }

    public func createVisitAction(visitID: PetVisitID, command: CreateVisitActionCommand) async throws -> VisitAction {
        try await perform(try await authorized {
            try $0.visitActionRequest(visitID: visitID, command: command, accessToken: $1)
        })
    }

    public func createConversation(_ command: CreateConversationCommand) async throws -> ConversationTurnReceipt {
        try await perform(try await authorized { try $0.createConversationRequest(command, accessToken: $1) })
    }

    public func fetchConversations() async throws -> [PetConversation] {
        try await perform(try await authorized { try $0.conversationsRequest(accessToken: $1) })
    }

    public func fetchConversationMessages(conversationID: ConversationID) async throws -> [PetConversationMessage] {
        try await perform(try await authorized {
            try $0.conversationMessagesRequest(conversationID: conversationID, accessToken: $1)
        })
    }

    public func sendConversationMessage(
        conversationID: ConversationID,
        command: SendConversationMessageCommand
    ) async throws -> ConversationTurnReceipt {
        try await perform(try await authorized {
            try $0.sendConversationMessageRequest(conversationID: conversationID, command: command, accessToken: $1)
        })
    }

    public func endConversation(
        conversationID: ConversationID,
        command: EndConversationCommand
    ) async throws -> PetConversation {
        try await perform(try await authorized {
            try $0.endConversationRequest(conversationID: conversationID, command: command, accessToken: $1)
        })
    }

    public func createLetter(visitID: PetVisitID, command: CreateLetterCommand) async throws -> PetLetter {
        try await perform(try await authorized {
            try $0.createLetterRequest(visitID: visitID, command: command, accessToken: $1)
        })
    }

    public func fetchLetter(_ letterID: LetterID) async throws -> PetLetter {
        try await perform(try await authorized { try $0.letterRequest(letterID: letterID, accessToken: $1) })
    }

    public func claimPrimaryAgentDevice(_ deviceID: DeviceID, idempotencyKey: UUID) async throws {
        let _: JSONValue = try await perform(try await authorized {
            try $0.claimAgentRequest(deviceID: deviceID, idempotencyKey: idempotencyKey, accessToken: $1)
        })
    }

    private func authorized(
        _ make: (BackendRequestBuilder, String?) throws -> URLRequest
    ) async throws -> URLRequest {
        try make(requestBuilder, try await tokenProvider.accessToken())
    }

    private func perform<Response: Decodable & Sendable>(_ request: URLRequest) async throws -> Response {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw BackendClientError.transport(String(describing: error))
        }
        guard let http = response as? HTTPURLResponse else { throw BackendClientError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let envelope = try? Self.decoder.decode(APIErrorEnvelope.self, from: data)
            throw BackendClientError.httpStatus(statusCode: http.statusCode, code: envelope?.error.code)
        }
        do {
            return try Self.decoder.decode(APIEnvelope<Response>.self, from: data).data
        } catch {
            throw BackendClientError.decoding
        }
    }

    private func performWithoutBody(_ request: URLRequest) async throws {
        let response: URLResponse
        do {
            (_, response) = try await session.data(for: request)
        } catch {
            throw BackendClientError.transport(String(describing: error))
        }
        guard let http = response as? HTTPURLResponse else { throw BackendClientError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw BackendClientError.httpStatus(statusCode: http.statusCode, code: nil)
        }
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}

public enum BackendServiceFactory {
    public static func make(
        configuration: BackendConfiguration,
        tokenProvider: any AccessTokenProvider = AnonymousAccessTokenProvider()
    ) -> any AccountBackendService {
        switch configuration.mode {
        case .offline: OfflineBackendService(apiVersion: configuration.apiVersion)
        case .remote: HTTPBackendService(configuration: configuration, tokenProvider: tokenProvider)
        }
    }
}

package struct BackendRequestBuilder: Sendable {
    private let configuration: BackendConfiguration
    package init(configuration: BackendConfiguration) { self.configuration = configuration }

    package func healthRequest() throws -> URLRequest {
        try request(path: ["health"], method: "GET", accessToken: nil)
    }

    package func githubDeviceStartRequest() throws -> URLRequest {
        try request(path: ["auth", "github", "device", "start"], method: "POST", accessToken: nil)
    }

    package func githubDeviceCompleteRequest(
        deviceCode: String,
        device: DeviceMetadata
    ) throws -> URLRequest {
        try request(
            path: ["auth", "github", "device", "complete"],
            method: "POST",
            body: GitHubDeviceCompleteBody(deviceCode: deviceCode, device: device),
            accessToken: nil
        )
    }

    package func refreshSessionRequest(refreshToken: String) throws -> URLRequest {
        try request(
            path: ["auth", "refresh"],
            method: "POST",
            body: RefreshSessionBody(refreshToken: refreshToken),
            accessToken: nil
        )
    }

    package func logoutRequest(accessToken: String?) throws -> URLRequest {
        try request(path: ["auth", "logout"], method: "POST", accessToken: accessToken)
    }
    package func developmentBootstrapRequest(profile: String) throws -> URLRequest {
        try request(path: ["dev", "bootstrap"], method: "POST", body: BodyProfile(profile: profile), accessToken: nil)
    }
    package func currentProfileRequest(accessToken: String?) throws -> URLRequest {
        try request(path: ["me", "profile"], method: "GET", accessToken: accessToken)
    }
    package func updateCurrentProfileRequest(accountName: String, petName: String, accessToken: String?) throws -> URLRequest {
        try request(path: ["me", "profile"], method: "PATCH", body: ProfileBody(accountName: accountName, petName: petName), accessToken: accessToken)
    }
    package func updateOwnPetAppearanceRequest(
        _ command: PetAppearanceSelectionCommand,
        accessToken: String?
    ) throws -> URLRequest {
        var value = try request(
            path: ["me", "pet"],
            method: "PATCH",
            body: command,
            accessToken: accessToken
        )
        value.setValue(command.idempotencyKey.uuidString, forHTTPHeaderField: "Idempotency-Key")
        return value
    }
    package func ownPetCareRequest(accessToken: String?) throws -> URLRequest {
        try request(path: ["me", "pet-state"], method: "GET", accessToken: accessToken)
    }
    package func petInteractionRequest(
        petID: PetProfileID,
        command: PetInteractionCommand,
        accessToken: String?
    ) throws -> URLRequest {
        try idempotent(
            path: ["pets", petID.rawValue, "interactions"],
            body: command,
            key: command.idempotencyKey,
            accessToken: accessToken
        )
    }
    package func friendshipsRequest(status: FriendRequestStatus?, accessToken: String?) throws -> URLRequest {
        let value = status.map { $0 == .cancelled ? "closed" : $0.rawValue }
        return try request(path: ["friendships"], method: "GET", query: value.map { [URLQueryItem(name: "status", value: $0)] } ?? [], accessToken: accessToken)
    }
    package func createFriendRequest(_ command: CreateFriendRequestCommand, accessToken: String?) throws -> URLRequest {
        try idempotent(path: ["friendships"], body: command, key: command.idempotencyKey, accessToken: accessToken)
    }
    package func respondToFriendRequest(friendshipID: FriendshipID, command: RespondFriendRequestCommand, accessToken: String?) throws -> URLRequest {
        try idempotent(path: ["friendships", friendshipID.rawValue, "respond"], body: command, key: command.idempotencyKey, accessToken: accessToken)
    }
    package func closeFriendshipRequest(friendshipID: FriendshipID, idempotencyKey: UUID, accessToken: String?) throws -> URLRequest {
        try idempotent(path: ["friendships", friendshipID.rawValue, "close"], body: EmptyBody(), key: idempotencyKey, accessToken: accessToken)
    }
    package func syncBootstrapRequest(accessToken: String?) throws -> URLRequest {
        try request(path: ["sync", "bootstrap"], method: "GET", accessToken: accessToken)
    }
    package func accountEventsRequest(after cursor: Int64, limit: Int, timelineVisible: Bool?, accessToken: String?) throws -> URLRequest {
        var query = [URLQueryItem(name: "after", value: String(cursor)), URLQueryItem(name: "limit", value: String(limit))]
        if let timelineVisible { query.append(URLQueryItem(name: "timelineVisible", value: String(timelineVisible))) }
        return try request(path: ["events"], method: "GET", query: query, accessToken: accessToken)
    }
    package func visitsRequest(status: VisitStatus?, accessToken: String?) throws -> URLRequest {
        try request(path: ["visits"], method: "GET", query: status.map { [URLQueryItem(name: "status", value: $0.rawValue)] } ?? [], accessToken: accessToken)
    }
    package func createVisitRequest(_ command: CreateVisitCommand, accessToken: String?) throws -> URLRequest {
        try idempotent(path: ["visits"], body: command, key: command.idempotencyKey, accessToken: accessToken)
    }
    package func respondToVisitRequest(visitID: PetVisitID, command: RespondToVisitCommand, accessToken: String?) throws -> URLRequest {
        try idempotent(path: ["visits", visitID.rawValue, "respond"], body: command, key: command.idempotencyKey, accessToken: accessToken)
    }
    package func endVisitRequest(visitID: PetVisitID, command: EndVisitCommand, accessToken: String?) throws -> URLRequest {
        try idempotent(path: ["visits", visitID.rawValue, "end"], body: command, key: command.idempotencyKey, accessToken: accessToken)
    }
    package func visitActionRequest(visitID: PetVisitID, command: CreateVisitActionCommand, accessToken: String?) throws -> URLRequest {
        try idempotent(path: ["visits", visitID.rawValue, "actions"], body: command, key: command.idempotencyKey, accessToken: accessToken)
    }
    package func createConversationRequest(_ command: CreateConversationCommand, accessToken: String?) throws -> URLRequest {
        try idempotent(path: ["conversations"], body: command, key: command.idempotencyKey, accessToken: accessToken)
    }
    package func conversationsRequest(accessToken: String?) throws -> URLRequest {
        try request(path: ["conversations"], method: "GET", accessToken: accessToken)
    }
    package func conversationMessagesRequest(conversationID: ConversationID, accessToken: String?) throws -> URLRequest {
        try request(path: ["conversations", conversationID.rawValue, "messages"], method: "GET", accessToken: accessToken)
    }
    package func sendConversationMessageRequest(conversationID: ConversationID, command: SendConversationMessageCommand, accessToken: String?) throws -> URLRequest {
        try idempotent(path: ["conversations", conversationID.rawValue, "messages"], body: command, key: command.idempotencyKey, accessToken: accessToken)
    }
    package func endConversationRequest(conversationID: ConversationID, command: EndConversationCommand, accessToken: String?) throws -> URLRequest {
        try idempotent(path: ["conversations", conversationID.rawValue, "end"], body: command, key: command.idempotencyKey, accessToken: accessToken)
    }
    package func createLetterRequest(visitID: PetVisitID, command: CreateLetterCommand, accessToken: String?) throws -> URLRequest {
        try idempotent(path: ["visits", visitID.rawValue, "letters"], body: command, key: command.idempotencyKey, accessToken: accessToken)
    }
    package func letterRequest(letterID: LetterID, accessToken: String?) throws -> URLRequest {
        try request(path: ["letters", letterID.rawValue], method: "GET", accessToken: accessToken)
    }
    package func claimAgentRequest(deviceID: DeviceID, idempotencyKey: UUID, accessToken: String?) throws -> URLRequest {
        try idempotent(path: ["devices", deviceID.rawValue, "claim-agent"], body: EmptyBody(), key: idempotencyKey, accessToken: accessToken)
    }

    private func idempotent<Body: Encodable>(path: [String], body: Body, key: UUID, accessToken: String?) throws -> URLRequest {
        var value = try request(path: path, method: "POST", body: body, accessToken: accessToken)
        value.setValue(key.uuidString, forHTTPHeaderField: "Idempotency-Key")
        return value
    }

    private func request(path: [String], method: String, query: [URLQueryItem] = [], accessToken: String?) throws -> URLRequest {
        try request(path: path, method: method, data: nil, query: query, accessToken: accessToken)
    }
    private func request<Body: Encodable>(path: [String], method: String, body: Body, query: [URLQueryItem] = [], accessToken: String?) throws -> URLRequest {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return try request(path: path, method: method, data: encoder.encode(body), query: query, accessToken: accessToken)
    }
    private func request(path: [String], method: String, data: Data?, query: [URLQueryItem], accessToken: String?) throws -> URLRequest {
        guard let baseURL = configuration.baseURL else { throw BackendClientError.invalidRequest }
        var url = baseURL.appendingPathComponent(configuration.apiVersion, isDirectory: true)
        for (index, component) in path.enumerated() {
            url.appendPathComponent(component, isDirectory: index < path.count - 1)
        }
        if !query.isEmpty {
            guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw BackendClientError.invalidRequest }
            components.queryItems = query
            guard let queryURL = components.url else { throw BackendClientError.invalidRequest }
            url = queryURL
        }
        var result = URLRequest(url: url)
        result.httpMethod = method
        result.httpBody = data
        result.timeoutInterval = configuration.requestTimeout
        result.setValue("application/json", forHTTPHeaderField: "Accept")
        if data != nil { result.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let accessToken { result.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization") }
        result.setValue("macos", forHTTPHeaderField: "X-Mino-Client")
        return result
    }
}

package struct FriendshipWire: Codable, Sendable {
    struct Friend: Codable, Sendable {
        let accountID: AccountID
        let displayName: String
        let pet: PublicPetSnapshot
    }
    let id: FriendshipID
    let requesterAccountID: AccountID
    let addresseeAccountID: AccountID
    let status: FriendshipStatus
    let version: Int64
    let createdAt: Date
    let respondedAt: Date?
    let closedAt: Date?
    let friend: Friend
    let familiarity: PetFamiliarity?

    var friendProfile: FriendProfile? {
        guard status == .accepted else { return nil }
        return FriendProfile(
            friendshipID: id, accountID: friend.accountID, accountName: friend.displayName,
            petID: friend.pet.petID, petName: friend.pet.displayName,
            friendsSince: respondedAt ?? createdAt,
            publicCare: friend.pet.publicCare,
            familiarity: familiarity,
            characterID: PetCharacterID(appearance: friend.pet.appearance)
        )
    }
    var friendRequest: FriendRequest? {
        guard status != .accepted else { return nil }
        let mapped: FriendRequestStatus = switch status {
        case .pending: .pending
        case .accepted: .accepted
        case .rejected: .declined
        case .closed: .cancelled
        }
        return FriendRequest(
            id: FriendRequestID(rawValue: id.rawValue),
            requesterAccountID: requesterAccountID,
            addresseeAccountID: addresseeAccountID,
            friendAccountID: friend.accountID,
            friendName: friend.displayName,
            friendPetID: friend.pet.petID,
            friendPetName: friend.pet.displayName,
            status: mapped,
            createdAt: createdAt,
            respondedAt: respondedAt
        )
    }
}

private struct APIEnvelope<Value: Decodable>: Decodable { let data: Value }
private struct APIErrorEnvelope: Decodable {
    struct APIError: Decodable { let code: String; let message: String? }
    let error: APIError
}
private struct BodyProfile: Encodable { let profile: String }
private struct GitHubDeviceCompleteBody: Encodable {
    let deviceCode: String
    let device: DeviceMetadata
}
private struct RefreshSessionBody: Encodable { let refreshToken: String }
private struct ProfileBody: Encodable { let accountName: String; let petName: String }
private struct EmptyBody: Encodable {}
