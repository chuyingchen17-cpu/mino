import Foundation

public enum BackendMode: String, Codable, Sendable {
    case offline
    case remote
}

public struct BackendConfiguration: Equatable, Sendable {
    public let mode: BackendMode
    public let baseURL: URL?
    public let apiVersion: String
    public let requestTimeout: TimeInterval

    public init(
        mode: BackendMode,
        baseURL: URL?,
        apiVersion: String = "v1",
        requestTimeout: TimeInterval = 10
    ) {
        self.mode = mode
        self.baseURL = baseURL
        self.apiVersion = apiVersion
        self.requestTimeout = requestTimeout
    }

    public static let offline = BackendConfiguration(
        mode: .offline,
        baseURL: nil
    )
}

public struct AppConfiguration: Equatable, Sendable {
    public let backend: BackendConfiguration

    public init(backend: BackendConfiguration) {
        self.backend = backend
    }

    public static let offline = AppConfiguration(backend: .offline)
}

public enum ConfigurationError: Error, Equatable, Sendable {
    case unknownBackendMode(String)
    case missingBackendBaseURL
    case invalidBackendBaseURL(String)
    case insecureBackendBaseURL(String)
    case invalidAPIVersion(String)
    case invalidRequestTimeout(String)
}

public enum AppConfigurationLoader {
    public static func load(
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> AppConfiguration {
        try load(
            info: bundle.infoDictionary ?? [:],
            environment: environment
        )
    }

    public static func load(
        info: [String: Any],
        environment: [String: String]
    ) throws -> AppConfiguration {
        let modeValue = value(
            environmentKey: "MINO_BACKEND_MODE",
            infoKey: "MinoBackendMode",
            info: info,
            environment: environment
        ) ?? BackendMode.offline.rawValue

        guard let mode = BackendMode(rawValue: modeValue.lowercased()) else {
            throw ConfigurationError.unknownBackendMode(modeValue)
        }

        let apiVersion = value(
            environmentKey: "MINO_API_VERSION",
            infoKey: "MinoAPIVersion",
            info: info,
            environment: environment
        ) ?? "v1"
        guard isValidAPIVersion(apiVersion) else {
            throw ConfigurationError.invalidAPIVersion(apiVersion)
        }

        let timeoutValue = value(
            environmentKey: "MINO_REQUEST_TIMEOUT",
            infoKey: "MinoRequestTimeout",
            info: info,
            environment: environment
        ) ?? "10"
        guard let timeout = TimeInterval(timeoutValue), (1...60).contains(timeout) else {
            throw ConfigurationError.invalidRequestTimeout(timeoutValue)
        }

        guard mode == .remote else {
            return AppConfiguration(
                backend: BackendConfiguration(
                    mode: .offline,
                    baseURL: nil,
                    apiVersion: apiVersion,
                    requestTimeout: timeout
                )
            )
        }

        guard let baseURLValue = value(
            environmentKey: "MINO_API_BASE_URL",
            infoKey: "MinoAPIBaseURL",
            info: info,
            environment: environment
        ), let baseURL = URL(string: baseURLValue), baseURL.host != nil else {
            throw ConfigurationError.missingBackendBaseURL
        }
        guard baseURL.query == nil, baseURL.fragment == nil else {
            throw ConfigurationError.invalidBackendBaseURL(baseURLValue)
        }
        guard isSecureOrLocal(baseURL), baseURL.user == nil, baseURL.password == nil else {
            throw ConfigurationError.insecureBackendBaseURL(baseURLValue)
        }

        return AppConfiguration(
            backend: BackendConfiguration(
                mode: .remote,
                baseURL: baseURL,
                apiVersion: apiVersion,
                requestTimeout: timeout
            )
        )
    }

    private static func value(
        environmentKey: String,
        infoKey: String,
        info: [String: Any],
        environment: [String: String]
    ) -> String? {
        if let environmentValue = environment[environmentKey], !environmentValue.isEmpty {
            return environmentValue
        }
        if let string = info[infoKey] as? String, !string.isEmpty {
            return string
        }
        if let number = info[infoKey] as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    private static func isValidAPIVersion(_ value: String) -> Bool {
        !value.isEmpty && value.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_")).contains($0)
        }
    }

    private static func isSecureOrLocal(_ url: URL) -> Bool {
        if url.scheme?.lowercased() == "https" {
            return true
        }
        guard url.scheme?.lowercased() == "http" else { return false }
        return ["localhost", "127.0.0.1", "::1"].contains(url.host?.lowercased() ?? "")
    }
}
