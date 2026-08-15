import Foundation
import MinoDomain
import Security

public struct SessionCredential: Codable, Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let accountID: AccountID
    public let accessToken: String
    public let refreshToken: String?
    public let accessTokenExpiresAt: Date
    public let issuedAt: Date

    public init(
        accountID: AccountID,
        accessToken: String,
        refreshToken: String?,
        accessTokenExpiresAt: Date,
        issuedAt: Date
    ) {
        self.accountID = accountID
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.accessTokenExpiresAt = accessTokenExpiresAt
        self.issuedAt = issuedAt
    }

    public func needsRefresh(at date: Date = Date(), leeway: TimeInterval = 60) -> Bool {
        accessTokenExpiresAt <= date.addingTimeInterval(leeway)
    }

    public var description: String {
        "SessionCredential(accountID: <redacted>, accessToken: <redacted>, refreshToken: <redacted>)"
    }

    public var debugDescription: String { description }
}

public protocol SessionCredentialStore: Sendable {
    func load() async throws -> SessionCredential?
    func save(_ credential: SessionCredential) async throws
    func clear() async throws
}

public enum KeychainCredentialStoreError: Error, Equatable, Sendable {
    case operationFailed(operation: String, status: Int32)
    case invalidPayload
    case unsupportedSchema(Int)
}

public actor KeychainSessionCredentialStore: SessionCredentialStore {
    private static let schemaVersion = 1

    private let service: String
    private let account: String

    public init(service: String = "com.mino.app.session", account: String = "primary") {
        self.service = service
        self.account = account
    }

    public func load() async throws -> SessionCredential? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainCredentialStoreError.operationFailed(
                operation: "load",
                status: status
            )
        }
        guard let data = result as? Data else {
            throw KeychainCredentialStoreError.invalidPayload
        }

        let header: CredentialSchemaHeader
        do {
            header = try JSONDecoder().decode(CredentialSchemaHeader.self, from: data)
        } catch {
            throw KeychainCredentialStoreError.invalidPayload
        }
        guard header.schemaVersion == Self.schemaVersion else {
            throw KeychainCredentialStoreError.unsupportedSchema(header.schemaVersion)
        }

        let envelope: CredentialEnvelope
        do {
            envelope = try JSONDecoder().decode(CredentialEnvelope.self, from: data)
        } catch {
            throw KeychainCredentialStoreError.invalidPayload
        }
        return envelope.credential
    }

    public func save(_ credential: SessionCredential) async throws {
        let envelope = CredentialEnvelope(
            schemaVersion: Self.schemaVersion,
            credential: credential
        )
        let data = try JSONEncoder().encode(envelope)
        let updateAttributes = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            updateAttributes as CFDictionary
        )

        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainCredentialStoreError.operationFailed(
                operation: "update",
                status: updateStatus
            )
        }

        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainCredentialStoreError.operationFailed(
                operation: "add",
                status: addStatus
            )
        }
    }

    public func clear() async throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainCredentialStoreError.operationFailed(
                operation: "delete",
                status: status
            )
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

public actor InMemorySessionCredentialStore: SessionCredentialStore {
    private var credential: SessionCredential?

    public init(credential: SessionCredential? = nil) {
        self.credential = credential
    }

    public func load() async throws -> SessionCredential? {
        credential
    }

    public func save(_ credential: SessionCredential) async throws {
        self.credential = credential
    }

    public func clear() async throws {
        credential = nil
    }
}

private struct CredentialEnvelope: Codable, Sendable {
    let schemaVersion: Int
    let credential: SessionCredential
}

private struct CredentialSchemaHeader: Decodable {
    let schemaVersion: Int
}
