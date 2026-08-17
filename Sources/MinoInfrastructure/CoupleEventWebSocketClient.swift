import Foundation
import MinoDomain

public enum FriendshipEventWebSocketError: Error, Equatable, Sendable {
    case offline
    case missingBaseURL
    case missingAccessToken
    case invalidWebSocketURL
    case unsupportedMessage
    case decoding
}

/// Thin realtime transport. Durable ordering, deduplication and reconnection are
/// owned by `EventSyncCoordinator`, which always catches up through REST first.
public actor WebSocketFriendshipEventService: FriendshipEventRealtimeService {
    private let configuration: BackendConfiguration
    private let session: URLSession
    private let tokenProvider: any AccessTokenProvider

    public init(
        configuration: BackendConfiguration,
        session: URLSession = .shared,
        tokenProvider: any AccessTokenProvider
    ) {
        self.configuration = configuration
        self.session = session
        self.tokenProvider = tokenProvider
    }

    public func events(
        friendshipID: FriendshipID,
        after eventID: String?
    ) async throws -> AsyncThrowingStream<FriendshipEvent, Error> {
        guard configuration.mode == .remote else {
            throw FriendshipEventWebSocketError.offline
        }
        guard let token = try await tokenProvider.accessToken(), !token.isEmpty else {
            throw FriendshipEventWebSocketError.missingAccessToken
        }
        let request = try makeRequest(
            friendshipID: friendshipID,
            after: eventID,
            token: token
        )
        let socket = session.webSocketTask(with: request)
        socket.resume()

        return AsyncThrowingStream { continuation in
            let receiveTask = Task {
                do {
                    while !Task.isCancelled {
                        let message = try await socket.receive()
                        guard let data = Self.data(from: message) else {
                            throw FriendshipEventWebSocketError.unsupportedMessage
                        }
                        let envelope: ServerMessage
                        do {
                            envelope = try Self.decoder.decode(ServerMessage.self, from: data)
                        } catch {
                            throw FriendshipEventWebSocketError.decoding
                        }

                        switch envelope.type {
                        case "ready":
                            continue
                        case "friendship_event", "couple_event":
                            guard let event = envelope.data else {
                                throw FriendshipEventWebSocketError.decoding
                            }
                            continuation.yield(event)
                        default:
                            continue
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                receiveTask.cancel()
                socket.cancel(with: .goingAway, reason: nil)
            }
        }
    }

    private func makeRequest(
        friendshipID: FriendshipID,
        after eventID: String?,
        token: String
    ) throws -> URLRequest {
        guard let baseURL = configuration.baseURL else {
            throw FriendshipEventWebSocketError.missingBaseURL
        }
        var url = baseURL
            .appendingPathComponent(configuration.apiVersion, isDirectory: true)
            .appendingPathComponent("ws", isDirectory: false)
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw FriendshipEventWebSocketError.invalidWebSocketURL
        }
        switch components.scheme?.lowercased() {
        case "https": components.scheme = "wss"
        case "http": components.scheme = "ws"
        default: throw FriendshipEventWebSocketError.invalidWebSocketURL
        }
        var queryItems = [
            URLQueryItem(name: "friendshipID", value: friendshipID.rawValue)
        ]
        if let eventID, !eventID.isEmpty {
            queryItems.append(URLQueryItem(name: "after", value: eventID))
        }
        components.queryItems = queryItems
        guard let webSocketURL = components.url else {
            throw FriendshipEventWebSocketError.invalidWebSocketURL
        }
        url = webSocketURL

        var request = URLRequest(url: url)
        request.timeoutInterval = configuration.requestTimeout
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("macos", forHTTPHeaderField: "X-Mino-Client")
        return request
    }

    private nonisolated static func data(from message: URLSessionWebSocketTask.Message) -> Data? {
        switch message {
        case .data(let data): data
        case .string(let text): text.data(using: .utf8)
        @unknown default: nil
        }
    }

    private nonisolated static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private struct ServerMessage: Decodable, Sendable {
    let type: String
    let cursor: String?
    let data: FriendshipEvent?
}

@available(*, deprecated, renamed: "FriendshipEventWebSocketError")
public typealias CoupleEventWebSocketError = FriendshipEventWebSocketError

@available(*, deprecated, renamed: "WebSocketFriendshipEventService")
public typealias WebSocketCoupleEventService = WebSocketFriendshipEventService
