import CryptoKit
import Darwin
import Foundation
import MinoDomain
import Security

public struct SessionCredential: Codable, Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let accountID: AccountID
    public let deviceID: DeviceID?
    public let accessToken: String
    public let refreshToken: String?
    public let accessTokenExpiresAt: Date
    public let issuedAt: Date

    public init(
        accountID: AccountID,
        deviceID: DeviceID? = nil,
        accessToken: String,
        refreshToken: String?,
        accessTokenExpiresAt: Date,
        issuedAt: Date
    ) {
        self.accountID = accountID
        self.deviceID = deviceID
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

/// Failures exposed by the encrypted file store deliberately contain no
/// credential payloads or underlying error descriptions.
public enum EncryptedFileSessionCredentialStoreError: Error, Equatable, Sendable {
    case invalidFileLocation
    case keyUnavailable
    case encodingFailed
    case encryptionFailed
    case invalidPayload
    case unsupportedSchema(Int)
    case decryptionFailed
    case fileOperationFailed(operation: String, code: Int32)
}

/// Persists the complete signed-in session without relying on Keychain access
/// control for the credential itself. The encryption key remains independently
/// supplied by a local secret provider, so the file is never useful on its own.
public actor EncryptedFileSessionCredentialStore: SessionCredentialStore {
    private static let fileSchemaVersion = 1
    private static let authenticatedContext = Data("mino.session-credential.v1".utf8)

    private let fileURL: URL
    private let keyProvider: any LocalSecretKeyProvider
    private let fileManager: FileManager

    /// `fileURL` should live inside a directory dedicated to Mino credentials.
    /// The store enforces mode 0700 on that directory and 0600 on the file.
    public init(
        fileURL: URL,
        keyProvider: any LocalSecretKeyProvider,
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL.standardizedFileURL
        self.keyProvider = keyProvider
        self.fileManager = fileManager
    }

    public func load() async throws -> SessionCredential? {
        try validateFileLocation()
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        try ensureRegularCredentialFile()
        try setPermissions(at: fileURL, mode: 0o600, operation: "protect-file")

        let encoded: Data
        do {
            encoded = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
        } catch let error as NSError {
            if error.domain == NSCocoaErrorDomain,
               error.code == CocoaError.fileReadNoSuchFile.rawValue {
                return nil
            }
            throw Self.fileError(operation: "read", error: error)
        }

        let encryptedEnvelope: EncryptedCredentialFileEnvelope
        do {
            encryptedEnvelope = try JSONDecoder().decode(
                EncryptedCredentialFileEnvelope.self,
                from: encoded
            )
        } catch {
            throw EncryptedFileSessionCredentialStoreError.invalidPayload
        }
        guard encryptedEnvelope.schemaVersion == Self.fileSchemaVersion else {
            throw EncryptedFileSessionCredentialStoreError.unsupportedSchema(
                encryptedEnvelope.schemaVersion
            )
        }

        let sealedBox: AES.GCM.SealedBox
        do {
            sealedBox = try AES.GCM.SealedBox(combined: encryptedEnvelope.sealedCredential)
        } catch {
            throw EncryptedFileSessionCredentialStoreError.invalidPayload
        }

        let key = try await localKey()
        let plaintext: Data
        do {
            plaintext = try AES.GCM.open(
                sealedBox,
                using: key,
                authenticating: Self.authenticatedContext
            )
        } catch {
            throw EncryptedFileSessionCredentialStoreError.decryptionFailed
        }

        let header: CredentialSchemaHeader
        do {
            header = try JSONDecoder().decode(CredentialSchemaHeader.self, from: plaintext)
        } catch {
            throw EncryptedFileSessionCredentialStoreError.invalidPayload
        }
        guard header.schemaVersion == Self.fileSchemaVersion else {
            throw EncryptedFileSessionCredentialStoreError.unsupportedSchema(
                header.schemaVersion
            )
        }

        do {
            return try JSONDecoder().decode(CredentialEnvelope.self, from: plaintext).credential
        } catch {
            throw EncryptedFileSessionCredentialStoreError.invalidPayload
        }
    }

    public func save(_ credential: SessionCredential) async throws {
        try validateFileLocation()
        try ensurePrivateParentDirectory()

        let plaintext: Data
        do {
            plaintext = try JSONEncoder().encode(
                CredentialEnvelope(
                    schemaVersion: Self.fileSchemaVersion,
                    credential: credential
                )
            )
        } catch {
            throw EncryptedFileSessionCredentialStoreError.encodingFailed
        }

        let key = try await localKey()
        let sealedBox: AES.GCM.SealedBox
        do {
            sealedBox = try AES.GCM.seal(
                plaintext,
                using: key,
                authenticating: Self.authenticatedContext
            )
        } catch {
            throw EncryptedFileSessionCredentialStoreError.encryptionFailed
        }
        guard let combined = sealedBox.combined else {
            throw EncryptedFileSessionCredentialStoreError.encryptionFailed
        }

        let encoded: Data
        do {
            encoded = try JSONEncoder().encode(
                EncryptedCredentialFileEnvelope(
                    schemaVersion: Self.fileSchemaVersion,
                    sealedCredential: combined
                )
            )
        } catch {
            throw EncryptedFileSessionCredentialStoreError.encodingFailed
        }
        try atomicWrite(encoded)
    }

    public func clear() async throws {
        try validateFileLocation()
        guard unlink(fileURL.path) != 0 else { return }
        guard errno == ENOENT else {
            throw EncryptedFileSessionCredentialStoreError.fileOperationFailed(
                operation: "delete",
                code: errno
            )
        }
    }

    private func localKey() async throws -> SymmetricKey {
        do {
            return try await keyProvider.loadOrCreateKey()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw EncryptedFileSessionCredentialStoreError.keyUnavailable
        }
    }

    private func validateFileLocation() throws {
        let parent = fileURL.deletingLastPathComponent()
        guard fileURL.isFileURL,
              !fileURL.lastPathComponent.isEmpty,
              fileURL.path != parent.path,
              parent.path != "/" else {
            throw EncryptedFileSessionCredentialStoreError.invalidFileLocation
        }
    }

    private func ensurePrivateParentDirectory() throws {
        let parent = fileURL.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: parent.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else {
                throw EncryptedFileSessionCredentialStoreError.invalidFileLocation
            }
            let attributes: [FileAttributeKey: Any]
            do {
                attributes = try fileManager.attributesOfItem(atPath: parent.path)
            } catch let error as NSError {
                throw Self.fileError(operation: "inspect-directory", error: error)
            }
            guard attributes[.type] as? FileAttributeType == .typeDirectory else {
                throw EncryptedFileSessionCredentialStoreError.invalidFileLocation
            }
        } else {
            do {
                try fileManager.createDirectory(
                    at: parent,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: NSNumber(value: 0o700)]
                )
            } catch let error as NSError {
                throw Self.fileError(operation: "create-directory", error: error)
            }
        }
        try setPermissions(at: parent, mode: 0o700, operation: "protect-directory")
    }

    private func ensureRegularCredentialFile() throws {
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
        } catch let error as NSError {
            throw Self.fileError(operation: "inspect-file", error: error)
        }
        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            throw EncryptedFileSessionCredentialStoreError.invalidFileLocation
        }
    }

    private func setPermissions(at url: URL, mode: Int, operation: String) throws {
        do {
            try fileManager.setAttributes(
                [.posixPermissions: NSNumber(value: mode)],
                ofItemAtPath: url.path
            )
        } catch let error as NSError {
            throw Self.fileError(operation: operation, error: error)
        }
    }

    private func atomicWrite(_ data: Data) throws {
        let parent = fileURL.deletingLastPathComponent()
        let temporaryURL = parent.appendingPathComponent(
            ".\(fileURL.lastPathComponent).\(UUID().uuidString).tmp",
            isDirectory: false
        )
        var shouldRemoveTemporaryFile = true
        defer {
            if shouldRemoveTemporaryFile {
                try? fileManager.removeItem(at: temporaryURL)
            }
        }

        let descriptor = open(
            temporaryURL.path,
            O_WRONLY | O_CREAT | O_EXCL,
            S_IRUSR | S_IWUSR
        )
        guard descriptor >= 0 else {
            throw EncryptedFileSessionCredentialStoreError.fileOperationFailed(
                operation: "create-temporary-file",
                code: errno
            )
        }
        defer { _ = close(descriptor) }

        try data.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let result = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    buffer.count - offset
                )
                if result < 0, errno == EINTR { continue }
                guard result > 0 else {
                    throw EncryptedFileSessionCredentialStoreError.fileOperationFailed(
                        operation: "write",
                        code: errno
                    )
                }
                offset += result
            }
        }
        guard fsync(descriptor) == 0 else {
            throw EncryptedFileSessionCredentialStoreError.fileOperationFailed(
                operation: "sync",
                code: errno
            )
        }
        guard rename(temporaryURL.path, fileURL.path) == 0 else {
            throw EncryptedFileSessionCredentialStoreError.fileOperationFailed(
                operation: "replace",
                code: errno
            )
        }
        shouldRemoveTemporaryFile = false
        try setPermissions(at: fileURL, mode: 0o600, operation: "protect-file")
    }

    private static func fileError(operation: String, error: NSError) -> Error {
        EncryptedFileSessionCredentialStoreError.fileOperationFailed(
            operation: operation,
            code: Int32(clamping: error.code)
        )
    }
}

public enum KeychainCredentialStoreError: Error, Equatable, Sendable {
    case invalidNamespace(String)
    case invalidExecutableFingerprint
    case executableIdentityUnavailable(operation: String, status: Int32)
    case invalidExecutableIdentity
    case operationFailed(operation: String, status: Int32)
    case invalidPayload
    case unsupportedSchema(Int)
}

package struct KeychainExecutableIdentity: Equatable, Sendable {
    package let fingerprint: Data
    package let requiresExecutableIsolation: Bool

    package init(fingerprint: Data, requiresExecutableIsolation: Bool) {
        self.fingerprint = fingerprint
        self.requiresExecutableIsolation = requiresExecutableIsolation
    }
}

public actor KeychainSessionCredentialStore: SessionCredentialStore {
    private static let schemaVersion = 1
    private static let defaultService = "com.mino.app.session"
    private static let adHocSignatureFlag: UInt32 = 0x0002

    private let service: String
    private let account: String

    public init(service: String = "com.mino.app.session", account: String = "primary") {
        self.service = service
        self.account = account
    }

    /// Creates a credential store isolated from other local client profiles and,
    /// when supplied, from credentials owned by a different development binary.
    /// An empty namespace and no fingerprint preserve the production service.
    public init(namespace: String, executableFingerprint: Data? = nil) throws {
        self.service = try Self.serviceName(
            for: namespace,
            executableFingerprint: executableFingerprint
        )
        self.account = "primary"
    }

    package static func serviceName(
        for namespace: String,
        executableFingerprint: Data? = nil
    ) throws -> String {
        guard isValidNamespace(namespace) else {
            throw KeychainCredentialStoreError.invalidNamespace(namespace)
        }
        let baseService = namespace.isEmpty
            ? defaultService
            : "\(defaultService).profile.\(namespace)"
        guard let executableFingerprint else { return baseService }
        guard !executableFingerprint.isEmpty else {
            throw KeychainCredentialStoreError.invalidExecutableFingerprint
        }
        // The code-signing unique value is currently a 20-byte CDHash. Limit a
        // future longer representation to the same 160-bit stable suffix.
        let fingerprint = executableFingerprint.prefix(20).map {
            String(format: "%02x", $0)
        }.joined()
        return "\(baseService).executable.\(fingerprint)"
    }

    /// Returns the operating system's stable identity for exactly the running
    /// executable. Ad-hoc signatures have a different CDHash after a rebuild,
    /// while repeated launches of the same binary return the same value.
    package static func currentExecutableIdentity() throws -> KeychainExecutableIdentity {
        var dynamicCode: SecCode?
        let copySelfStatus = SecCodeCopySelf([], &dynamicCode)
        guard copySelfStatus == errSecSuccess, let dynamicCode else {
            throw KeychainCredentialStoreError.executableIdentityUnavailable(
                operation: "copy-self",
                status: copySelfStatus
            )
        }

        var staticCode: SecStaticCode?
        let copyStaticStatus = SecCodeCopyStaticCode(dynamicCode, [], &staticCode)
        guard copyStaticStatus == errSecSuccess, let staticCode else {
            throw KeychainCredentialStoreError.executableIdentityUnavailable(
                operation: "copy-static-code",
                status: copyStaticStatus
            )
        }

        var information: CFDictionary?
        let signingStatus = SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &information
        )
        guard signingStatus == errSecSuccess, let information else {
            throw KeychainCredentialStoreError.executableIdentityUnavailable(
                operation: "copy-signing-information",
                status: signingStatus
            )
        }

        let values = information as NSDictionary
        guard let fingerprint = values[kSecCodeInfoUnique] as? Data,
              !fingerprint.isEmpty,
              let flags = values[kSecCodeInfoFlags] as? NSNumber else {
            throw KeychainCredentialStoreError.invalidExecutableIdentity
        }
        let teamIdentifier = values[kSecCodeInfoTeamIdentifier] as? String
        let isAdHoc = flags.uint32Value & adHocSignatureFlag != 0
        return KeychainExecutableIdentity(
            fingerprint: fingerprint,
            requiresExecutableIsolation: isAdHoc || teamIdentifier?.isEmpty != false
        )
    }

    package static func executableFingerprintForLocalFallback(
        identity: KeychainExecutableIdentity
    ) -> Data? {
        identity.requiresExecutableIsolation ? identity.fingerprint : nil
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

    private static func isValidNamespace(_ value: String) -> Bool {
        guard value.count <= 64 else { return false }
        return value.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 48...57, 65...90, 97...122, 45, 95:
                true
            default:
                false
            }
        }
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

private struct EncryptedCredentialFileEnvelope: Codable, Sendable {
    let schemaVersion: Int
    let sealedCredential: Data
}
