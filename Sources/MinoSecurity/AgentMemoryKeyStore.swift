import CryptoKit
import Darwin
import Foundation
import Security

public protocol LocalSecretKeyProvider: Sendable {
    func loadOrCreateKey() async throws -> SymmetricKey
}

public protocol AgentMemoryKeyStore: LocalSecretKeyProvider {}

public enum AgentMemoryKeyStoreError: Error, Equatable, Sendable {
    case invalidNamespace(String)
    case invalidExecutableFingerprint
    case randomGenerationFailed(Int32)
    case operationFailed(operation: String, status: Int32)
    case fileOperationFailed(operation: String, code: Int)
    case unsafeStorageLayout
    case invalidKey
}

/// Keeps the per-profile AES key outside the encrypted memory JSON file.
public actor KeychainAgentMemoryKeyStore: AgentMemoryKeyStore {
    private static let defaultService = "com.mino.app.agent-memory-key"
    private let service: String
    private let account = "primary"

    public init(
        namespace: String = "",
        executableFingerprint: Data? = nil
    ) throws {
        service = try Self.serviceName(
            for: namespace,
            executableFingerprint: executableFingerprint
        )
    }

    package static func serviceName(
        for namespace: String,
        executableFingerprint: Data? = nil
    ) throws -> String {
        guard Self.isValidNamespace(namespace) else {
            throw AgentMemoryKeyStoreError.invalidNamespace(namespace)
        }
        let baseService = namespace.isEmpty
            ? defaultService
            : "\(defaultService).profile.\(namespace)"
        guard let executableFingerprint else { return baseService }
        guard !executableFingerprint.isEmpty else {
            throw AgentMemoryKeyStoreError.invalidExecutableFingerprint
        }
        let fingerprint = executableFingerprint.prefix(20).map {
            String(format: "%02x", $0)
        }.joined()
        return "\(baseService).executable.\(fingerprint)"
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

/// Persists a device-local 256-bit secret without depending on Keychain ACLs.
/// The containing directory is private to the current user and writes never
/// expose a partially written key at the final path.
public actor FileAgentMemoryKeyStore: AgentMemoryKeyStore {
    private let fileURL: URL
    private let fileManager: FileManager

    public init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL.standardizedFileURL
        self.fileManager = fileManager
    }

    public func loadOrCreateKey() async throws -> SymmetricKey {
        try ensurePrivateParentDirectory()
        if fileManager.fileExists(atPath: fileURL.path) {
            return SymmetricKey(data: try loadKeyData())
        }

        let data = try generateKeyData()
        if try installKeyDataAtomically(data) {
            return SymmetricKey(data: data)
        }
        // A second process won the exclusive rename. Its complete key is now
        // authoritative; the losing process never replaces it.
        return SymmetricKey(data: try loadKeyData())
    }

    private func ensurePrivateParentDirectory() throws {
        guard fileURL.isFileURL, !fileURL.lastPathComponent.isEmpty else {
            throw AgentMemoryKeyStoreError.unsafeStorageLayout
        }
        let directoryURL = fileURL.deletingLastPathComponent()
        if fileManager.fileExists(atPath: directoryURL.path) {
            let attributes: [FileAttributeKey: Any]
            do {
                attributes = try fileManager.attributesOfItem(atPath: directoryURL.path)
            } catch {
                throw fileError(operation: "inspect-directory", error: error)
            }
            guard attributes[.type] as? FileAttributeType == .typeDirectory else {
                throw AgentMemoryKeyStoreError.unsafeStorageLayout
            }
        } else {
            do {
                try fileManager.createDirectory(
                    at: directoryURL,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: NSNumber(value: 0o700)]
                )
            } catch {
                throw fileError(operation: "create-directory", error: error)
            }
        }
        do {
            try fileManager.setAttributes(
                [.posixPermissions: NSNumber(value: 0o700)],
                ofItemAtPath: directoryURL.path
            )
        } catch {
            throw fileError(operation: "set-directory-permissions", error: error)
        }
    }

    private func loadKeyData() throws -> Data {
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
        } catch {
            throw fileError(operation: "inspect-key", error: error)
        }
        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            throw AgentMemoryKeyStoreError.unsafeStorageLayout
        }
        do {
            try fileManager.setAttributes(
                [.posixPermissions: NSNumber(value: 0o600)],
                ofItemAtPath: fileURL.path
            )
        } catch {
            throw fileError(operation: "set-file-permissions", error: error)
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw fileError(operation: "read", error: error)
        }
        guard data.count == 32 else {
            throw AgentMemoryKeyStoreError.invalidKey
        }
        return data
    }

    private func generateKeyData() throws -> Data {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw AgentMemoryKeyStoreError.randomGenerationFailed(status)
        }
        return Data(bytes)
    }

    private func installKeyDataAtomically(_ data: Data) throws -> Bool {
        let temporaryURL = fileURL.deletingLastPathComponent().appendingPathComponent(
            ".\(fileURL.lastPathComponent).\(UUID().uuidString).tmp",
            isDirectory: false
        )
        defer { try? fileManager.removeItem(at: temporaryURL) }
        do {
            try data.write(to: temporaryURL, options: .withoutOverwriting)
            try fileManager.setAttributes(
                [.posixPermissions: NSNumber(value: 0o600)],
                ofItemAtPath: temporaryURL.path
            )
        } catch {
            throw fileError(operation: "write-temporary", error: error)
        }

        let renameStatus: Int32 = temporaryURL.withUnsafeFileSystemRepresentation { source in
            guard let source else { return -1 }
            return fileURL.withUnsafeFileSystemRepresentation { destination in
                guard let destination else { return -1 }
                return renamex_np(source, destination, UInt32(RENAME_EXCL))
            }
        }
        guard renameStatus == 0 else {
            let code = errno
            if code == EEXIST { return false }
            throw AgentMemoryKeyStoreError.fileOperationFailed(
                operation: "install-key",
                code: Int(code == 0 ? EINVAL : code)
            )
        }
        return true
    }

    private func fileError(operation: String, error: Error) -> AgentMemoryKeyStoreError {
        AgentMemoryKeyStoreError.fileOperationFailed(
            operation: operation,
            code: (error as NSError).code
        )
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
