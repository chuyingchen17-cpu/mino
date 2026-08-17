import CryptoKit
import Foundation
import Security

public protocol AgentMemoryKeyStore: Sendable {
    func loadOrCreateKey() async throws -> SymmetricKey
}

public enum AgentMemoryKeyStoreError: Error, Equatable, Sendable {
    case invalidNamespace(String)
    case randomGenerationFailed(Int32)
    case operationFailed(operation: String, status: Int32)
    case invalidKey
}

/// Keeps the per-profile AES key outside the encrypted memory JSON file.
public actor KeychainAgentMemoryKeyStore: AgentMemoryKeyStore {
    private static let defaultService = "com.mino.app.agent-memory-key"
    private let service: String
    private let account = "primary"

    public init(namespace: String = "") throws {
        service = try Self.serviceName(for: namespace)
    }

    package static func serviceName(for namespace: String) throws -> String {
        guard Self.isValidNamespace(namespace) else {
            throw AgentMemoryKeyStoreError.invalidNamespace(namespace)
        }
        guard !namespace.isEmpty else { return defaultService }
        return "\(defaultService).profile.\(namespace)"
    }

    public func loadOrCreateKey() async throws -> SymmetricKey {
        if let existing = try loadData() {
            guard existing.count == 32 else { throw AgentMemoryKeyStoreError.invalidKey }
            return SymmetricKey(data: existing)
        }

        var bytes = [UInt8](repeating: 0, count: 32)
        let randomStatus = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard randomStatus == errSecSuccess else {
            throw AgentMemoryKeyStoreError.randomGenerationFailed(randomStatus)
        }
        let data = Data(bytes)
        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecDuplicateItem, let existing = try loadData(), existing.count == 32 {
            return SymmetricKey(data: existing)
        }
        guard status == errSecSuccess else {
            throw AgentMemoryKeyStoreError.operationFailed(operation: "add", status: status)
        }
        return SymmetricKey(data: data)
    }

    private func loadData() throws -> Data? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw AgentMemoryKeyStoreError.operationFailed(operation: "load", status: status)
        }
        guard let data = result as? Data else {
            throw AgentMemoryKeyStoreError.invalidKey
        }
        return data
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private static func isValidNamespace(_ value: String) -> Bool {
        guard value.count <= 64 else { return false }
        return value.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 48...57, 65...90, 97...122, 45, 95: true
            default: false
            }
        }
    }
}

public actor InMemoryAgentMemoryKeyStore: AgentMemoryKeyStore {
    private var key: SymmetricKey?

    public init(key: SymmetricKey? = nil) {
        self.key = key
    }

    public func loadOrCreateKey() async throws -> SymmetricKey {
        if let key { return key }
        let generated = SymmetricKey(size: .bits256)
        key = generated
        return generated
    }
}
