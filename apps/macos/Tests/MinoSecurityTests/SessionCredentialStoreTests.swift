import CryptoKit
import Foundation
import MinoDomain
import Testing

@testable import MinoSecurity

@Test
func keychainNamespacesIsolateDebugClientProfilesAndPreserveLegacyDefault() throws {
    let standard = try KeychainSessionCredentialStore.serviceName(for: "")
    let alice = try KeychainSessionCredentialStore.serviceName(for: "alice")
    let bob = try KeychainSessionCredentialStore.serviceName(for: "bob")

    #expect(standard == "com.mino.app.session")
    #expect(alice == "com.mino.app.session.profile.alice")
    #expect(bob == "com.mino.app.session.profile.bob")
    #expect(alice != bob)
}

@Test
func keychainNamespaceRejectsUnsafeValues() {
    #expect(throws: KeychainCredentialStoreError.invalidNamespace("../alice")) {
        try KeychainSessionCredentialStore.serviceName(for: "../alice")
    }
}

@Test
func executableScopedServiceIsStableForOneBinaryAndChangesAfterRebuild() throws {
    let firstBinary = Data((0..<20).map(UInt8.init))
    let rebuiltBinary = Data((1...20).map(UInt8.init))

    let firstLaunch = try KeychainSessionCredentialStore.serviceName(
        for: "",
        executableFingerprint: firstBinary
    )
    let secondLaunch = try KeychainSessionCredentialStore.serviceName(
        for: "",
        executableFingerprint: firstBinary
    )
    let rebuiltLaunch = try KeychainSessionCredentialStore.serviceName(
        for: "",
        executableFingerprint: rebuiltBinary
    )

    #expect(firstLaunch == secondLaunch)
    #expect(firstLaunch == "com.mino.app.session.executable.000102030405060708090a0b0c0d0e0f10111213")
    #expect(rebuiltLaunch != firstLaunch)
}

@Test
func executableScopedServicePreservesClientProfileIsolation() throws {
    let fingerprint = Data(repeating: 0xab, count: 20)
    let standard = try KeychainSessionCredentialStore.serviceName(
        for: "",
        executableFingerprint: fingerprint
    )
    let alice = try KeychainSessionCredentialStore.serviceName(
        for: "alice",
        executableFingerprint: fingerprint
    )

    #expect(standard.hasPrefix("com.mino.app.session.executable."))
    #expect(alice.hasPrefix("com.mino.app.session.profile.alice.executable."))
    #expect(alice != standard)
}

@Test
func executableScopedServiceRejectsAnEmptyFingerprint() {
    #expect(throws: KeychainCredentialStoreError.invalidExecutableFingerprint) {
        try KeychainSessionCredentialStore.serviceName(
            for: "",
            executableFingerprint: Data()
        )
    }
}

@Test
func storagePolicyUsesEncryptedFileFallbackOnlyWithoutAStableSignature() {
    let fingerprint = Data(repeating: 0xcd, count: 20)
    let signed = KeychainExecutableIdentity(
        fingerprint: fingerprint,
        requiresExecutableIsolation: false
    )
    let adHoc = KeychainExecutableIdentity(
        fingerprint: fingerprint,
        requiresExecutableIsolation: true
    )

    #expect(KeychainSessionCredentialStore.executableFingerprintForLocalFallback(
        identity: signed
    ) == nil)
    #expect(KeychainSessionCredentialStore.executableFingerprintForLocalFallback(
        identity: adHoc
    ) == fingerprint)
}

@Test
func credentialRefreshUsesSafetyLeeway() {
    let now = Date(timeIntervalSince1970: 1_000)
    let credential = SessionCredential(
        accountID: AccountID(rawValue: "account_1"),
        accessToken: "access-secret",
        refreshToken: "refresh-secret",
        accessTokenExpiresAt: now.addingTimeInterval(90),
        issuedAt: now
    )

    #expect(!credential.needsRefresh(at: now, leeway: 60))
    #expect(credential.needsRefresh(at: now.addingTimeInterval(31), leeway: 60))
}

@Test
func credentialDescriptionRedactsTokens() {
    let credential = SessionCredential(
        accountID: AccountID(rawValue: "account_1"),
        accessToken: "access-secret",
        refreshToken: "refresh-secret",
        accessTokenExpiresAt: .distantFuture,
        issuedAt: .distantPast
    )

    #expect(!credential.description.contains("access-secret"))
    #expect(!credential.description.contains("refresh-secret"))
    #expect(!credential.description.contains("account_1"))
    #expect(credential.description.contains("<redacted>"))
}

@Test
func inMemoryCredentialStoreSupportsSessionLifecycle() async throws {
    let store = InMemorySessionCredentialStore()
    let credential = SessionCredential(
        accountID: AccountID(rawValue: "account_1"),
        accessToken: "access-secret",
        refreshToken: nil,
        accessTokenExpiresAt: .distantFuture,
        issuedAt: .distantPast
    )

    #expect(try await store.load() == nil)
    try await store.save(credential)
    #expect(try await store.load() == credential)
    try await store.clear()
    #expect(try await store.load() == nil)
}

@Test
func encryptedFileCredentialStoreSurvivesStoreRecreation() async throws {
    let fixture = try SessionFileStoreFixture()
    defer { fixture.removeTemporaryDirectory() }
    let credential = makeSessionCredential()

    let firstStore = EncryptedFileSessionCredentialStore(
        fileURL: fixture.credentialURL,
        keyProvider: fixture.keyProvider
    )
    try await firstStore.save(credential)

    let recreatedStore = EncryptedFileSessionCredentialStore(
        fileURL: fixture.credentialURL,
        keyProvider: fixture.keyProvider
    )
    #expect(try await recreatedStore.load() == credential)
}

@Test
func encryptedFileCredentialStoreSurvivesProcessStyleKeyProviderRecreation() async throws {
    let fixture = try SessionFileStoreFixture()
    defer { fixture.removeTemporaryDirectory() }
    let credential = makeSessionCredential()
    let keyURL = fixture.rootURL
        .appendingPathComponent("local-secrets", isDirectory: true)
        .appendingPathComponent("session.key", isDirectory: false)
    let firstStore = EncryptedFileSessionCredentialStore(
        fileURL: fixture.credentialURL,
        keyProvider: FileAgentMemoryKeyStore(fileURL: keyURL)
    )
    try await firstStore.save(credential)

    let relaunchedStore = EncryptedFileSessionCredentialStore(
        fileURL: fixture.credentialURL,
        keyProvider: FileAgentMemoryKeyStore(fileURL: keyURL)
    )

    #expect(try await relaunchedStore.load() == credential)
}

@Test
func encryptedFileCredentialStoreNeverWritesTokensInPlaintext() async throws {
    let fixture = try SessionFileStoreFixture()
    defer { fixture.removeTemporaryDirectory() }
    let credential = makeSessionCredential()
    let store = EncryptedFileSessionCredentialStore(
        fileURL: fixture.credentialURL,
        keyProvider: fixture.keyProvider
    )

    try await store.save(credential)

    let persisted = try Data(contentsOf: fixture.credentialURL)
    let persistedText = String(decoding: persisted, as: UTF8.self)
    #expect(!persistedText.contains(credential.accessToken))
    #expect(!persistedText.contains(credential.refreshToken ?? ""))
}

@Test
func encryptedFileCredentialStoreRejectsAnotherLocalKey() async throws {
    let fixture = try SessionFileStoreFixture()
    defer { fixture.removeTemporaryDirectory() }
    let writer = EncryptedFileSessionCredentialStore(
        fileURL: fixture.credentialURL,
        keyProvider: fixture.keyProvider
    )
    try await writer.save(makeSessionCredential())

    let wrongKey = FixedLocalSecretKeyProvider(
        key: SymmetricKey(data: Data(repeating: 0x7f, count: 32))
    )
    let reader = EncryptedFileSessionCredentialStore(
        fileURL: fixture.credentialURL,
        keyProvider: wrongKey
    )

    await #expect(throws: EncryptedFileSessionCredentialStoreError.decryptionFailed) {
        try await reader.load()
    }
}

@Test
func encryptedFileCredentialStoreClearRemovesPersistedSession() async throws {
    let fixture = try SessionFileStoreFixture()
    defer { fixture.removeTemporaryDirectory() }
    let store = EncryptedFileSessionCredentialStore(
        fileURL: fixture.credentialURL,
        keyProvider: fixture.keyProvider
    )
    try await store.save(makeSessionCredential())

    try await store.clear()

    #expect(!FileManager.default.fileExists(atPath: fixture.credentialURL.path))
    #expect(try await store.load() == nil)
    try await store.clear()
}

@Test
func encryptedFileCredentialStoreEnforcesPrivatePOSIXPermissions() async throws {
    let fixture = try SessionFileStoreFixture()
    defer { fixture.removeTemporaryDirectory() }
    let store = EncryptedFileSessionCredentialStore(
        fileURL: fixture.credentialURL,
        keyProvider: fixture.keyProvider
    )

    try await store.save(makeSessionCredential())

    let directoryAttributes = try FileManager.default.attributesOfItem(
        atPath: fixture.credentialURL.deletingLastPathComponent().path
    )
    let fileAttributes = try FileManager.default.attributesOfItem(
        atPath: fixture.credentialURL.path
    )
    let directoryMode = try #require(directoryAttributes[.posixPermissions] as? NSNumber)
    let fileMode = try #require(fileAttributes[.posixPermissions] as? NSNumber)
    #expect(directoryMode.intValue & 0o777 == 0o700)
    #expect(fileMode.intValue & 0o777 == 0o600)
}

@Test
func encryptedFileCredentialStoreErrorsDoNotExposeCredentialSecrets() async throws {
    let fixture = try SessionFileStoreFixture()
    defer { fixture.removeTemporaryDirectory() }
    let credential = makeSessionCredential()
    let writer = EncryptedFileSessionCredentialStore(
        fileURL: fixture.credentialURL,
        keyProvider: fixture.keyProvider
    )
    try await writer.save(credential)

    let reader = EncryptedFileSessionCredentialStore(
        fileURL: fixture.credentialURL,
        keyProvider: FixedLocalSecretKeyProvider(
            key: SymmetricKey(data: Data(repeating: 0x33, count: 32))
        )
    )
    do {
        _ = try await reader.load()
        Issue.record("Expected decryption to fail")
    } catch {
        let description = String(reflecting: error)
        #expect(!description.contains(credential.accessToken))
        #expect(!description.contains(credential.refreshToken ?? ""))
    }
}

private actor FixedLocalSecretKeyProvider: LocalSecretKeyProvider {
    private let key: SymmetricKey

    init(key: SymmetricKey) {
        self.key = key
    }

    func loadOrCreateKey() async throws -> SymmetricKey {
        key
    }
}

private struct SessionFileStoreFixture {
    let rootURL: URL
    let credentialURL: URL
    let keyProvider: FixedLocalSecretKeyProvider

    init() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mino-session-store-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        credentialURL = rootURL
            .appendingPathComponent("credentials", isDirectory: true)
            .appendingPathComponent("session.json", isDirectory: false)
        keyProvider = FixedLocalSecretKeyProvider(
            key: SymmetricKey(data: Data(repeating: 0x42, count: 32))
        )
    }

    func removeTemporaryDirectory() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}

private func makeSessionCredential() -> SessionCredential {
    SessionCredential(
        accountID: AccountID(rawValue: "account_secret_fixture"),
        deviceID: DeviceID(rawValue: "device_secret_fixture"),
        accessToken: "access-secret-credential-fixture",
        refreshToken: "refresh-secret-credential-fixture",
        accessTokenExpiresAt: Date(timeIntervalSince1970: 2_000_000_000),
        issuedAt: Date(timeIntervalSince1970: 1_900_000_000)
    )
}
