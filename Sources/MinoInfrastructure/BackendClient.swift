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

public struct OfflineBackendService: BackendService {
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
}

public actor HTTPBackendService: BackendService {
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
    public static func make(configuration: BackendConfiguration) -> any BackendService {
        switch configuration.mode {
        case .offline:
            OfflineBackendService(apiVersion: configuration.apiVersion)
        case .remote:
            HTTPBackendService(configuration: configuration)
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

    private func request(
        path: String,
        method: String,
        body: Data?,
        accessToken: String?
    ) throws -> URLRequest {
        guard let baseURL = configuration.baseURL else {
            throw BackendClientError.invalidRequest
        }
        let url = baseURL
            .appendingPathComponent(configuration.apiVersion, isDirectory: true)
            .appendingPathComponent(path, isDirectory: false)

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
}

private struct APIEnvelope<Payload: Decodable & Sendable>: Decodable, Sendable {
    let data: Payload
}

private struct APIErrorEnvelope: Decodable, Sendable {
    struct APIError: Decodable, Sendable {
        let code: String
        let message: String?
    }

    let error: APIError
}
