import Foundation
import MinoDomain

public enum AccountEventWebSocketError: Error, Equatable, Sendable {
    case offline
    case missingBaseURL
    case missingAccessToken
    case invalidWebSocketURL
    case unsupportedMessage
}

/// Thin, account-scoped hint channel. It never decodes or acknowledges a
/// business event; REST catch-up remains authoritative.
public actor WebSocketAccountEventSignalService: AccountEventSignalService {
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

    public func signals() async throws -> AsyncThrowingStream<AccountRealtimeSignal, Error> {
        guard configuration.mode == .remote else { throw AccountEventWebSocketError.offline }
        guard let token = try await tokenProvider.accessToken(), !token.isEmpty else {
            throw AccountEventWebSocketError.missingAccessToken
        }
        let socket = session.webSocketTask(with: try makeRequest(token: token))
        socket.resume()

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    while !Task.isCancelled {
                        let message = try await socket.receive()
                        guard let data = Self.data(from: message),
                              let envelope = try? JSONDecoder().decode(ServerSignal.self, from: data)
                        else { throw AccountEventWebSocketError.unsupportedMessage }
                        switch envelope.type {
                        case "ready": continuation.yield(.ready)
                        case "events_available": continuation.yield(.eventsAvailable)
                        default: continue
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
                task.cancel()
                socket.cancel(with: .goingAway, reason: nil)
            }
        }
    }

    private func makeRequest(token: String) throws -> URLRequest {
        guard let baseURL = configuration.baseURL else {
            throw AccountEventWebSocketError.missingBaseURL
        }
        let endpoint = baseURL
            .appendingPathComponent(configuration.apiVersion, isDirectory: true)
            .appendingPathComponent("realtime", isDirectory: false)
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw AccountEventWebSocketError.invalidWebSocketURL
        }
        switch components.scheme?.lowercased() {
        case "https": components.scheme = "wss"
        case "http": components.scheme = "ws"
        default: throw AccountEventWebSocketError.invalidWebSocketURL
        }
        guard let url = components.url else { throw AccountEventWebSocketError.invalidWebSocketURL }
        var request = URLRequest(url: url)
        request.timeoutInterval = configuration.requestTimeout
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("macos", forHTTPHeaderField: "X-Mino-Client")
        return request
    }

    private nonisolated static func data(from message: URLSessionWebSocketTask.Message) -> Data? {
        switch message {
        case .data(let data): data
        case .string(let value): value.data(using: .utf8)
        @unknown default: nil
        }
    }
}

private struct ServerSignal: Decodable, Sendable { let type: String }
