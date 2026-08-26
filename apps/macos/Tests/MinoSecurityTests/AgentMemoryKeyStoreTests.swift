import CryptoKit
import Foundation
import Testing

@testable import MinoSecurity

@Test
func memoryKeyNamespacesAreProfileIsolated() throws {
    let standard = try KeychainAgentMemoryKeyStore.serviceName(for: "")
    let alice = try KeychainAgentMemoryKeyStore.serviceName(for: "alice")
    let bob = try KeychainAgentMemoryKeyStore.serviceName(for: "bob")

    #expect(standard == "com.mino.app.agent-memory-key")
    #expect(alice != bob)
    #expect(alice.hasSuffix(".alice"))
    #expect(bob.hasSuffix(".bob"))
}

@Test
func memoryKeyNamespaceRejectsTraversal() {
    #expect(throws: AgentMemoryKeyStoreError.invalidNamespace("../bob")) {
        try KeychainAgentMemoryKeyStore.serviceName(for: "../bob")
    }
}

@Test
func memoryKeyServiceUsesTheSameExecutableIsolationAsTheSession() throws {
    let fingerprint = Data((0..<20).map(UInt8.init))
    let firstLaunch = try KeychainAgentMemoryKeyStore.serviceName(
        for: "",
        executableFingerprint: fingerprint
    )
    let secondLaunch = try KeychainAgentMemoryKeyStore.serviceName(
        for: "",
        executableFingerprint: fingerprint
    )
    let profile = try KeychainAgentMemoryKeyStore.serviceName(
        for: "alice",
        executableFingerprint: fingerprint
    )

    #expect(firstLaunch == secondLaunch)
    #expect(firstLaunch == "com.mino.app.agent-memory-key.executable.000102030405060708090a0b0c0d0e0f10111213")
    #expect(profile.hasPrefix("com.mino.app.agent-memory-key.profile.alice.executable."))
    #expect(profile != firstLaunch)
}

@Test
func memoryKeyServiceRejectsAnEmptyExecutableFingerprint() {
    #expect(throws: AgentMemoryKeyStoreError.invalidExecutableFingerprint) {
        try KeychainAgentMemoryKeyStore.serviceName(
            for: "",
            executableFingerprint: Data()
        )
    }
}

@Test
func fileKeyStorePersistsOneKeyWithPrivatePermissions() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "mino-file-key-\(UUID().uuidString)",
        isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let directory = root.appendingPathComponent("secrets", isDirectory: true)
    let keyURL = directory.appendingPathComponent("local.key", isDirectory: false)

    let firstStore = FileAgentMemoryKeyStore(fileURL: keyURL)
    let first = try await firstStore.loadOrCreateKey()
    let reloadedStore = FileAgentMemoryKeyStore(fileURL: keyURL)
    let reloaded = try await reloadedStore.loadOrCreateKey()
    let firstData = first.withUnsafeBytes { Data($0) }
    let reloadedData = reloaded.withUnsafeBytes { Data($0) }

    #expect(firstData.count == 32)
    #expect(reloadedData == firstData)
    let directoryAttributes = try FileManager.default.attributesOfItem(atPath: directory.path)
    let fileAttributes = try FileManager.default.attributesOfItem(atPath: keyURL.path)
    let directoryMode = (directoryAttributes[.posixPermissions] as? NSNumber)?.intValue
    let fileMode = (fileAttributes[.posixPermissions] as? NSNumber)?.intValue
    #expect(directoryMode == 0o700)
    #expect(fileMode == 0o600)
}

@Test
func fileKeyStoreRejectsInvalidPayloadWithoutEchoingIt() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "mino-invalid-file-key-\(UUID().uuidString)",
        isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(
        at: root,
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: NSNumber(value: 0o700)]
    )
    let keyURL = root.appendingPathComponent("local.key", isDirectory: false)
    let invalidPayload = "must-never-appear-in-an-error"
    try Data(invalidPayload.utf8).write(to: keyURL, options: .atomic)

    let store = FileAgentMemoryKeyStore(fileURL: keyURL)
    do {
        _ = try await store.loadOrCreateKey()
        Issue.record("Expected an invalid key error")
    } catch {
        #expect(error as? AgentMemoryKeyStoreError == .invalidKey)
        #expect(!String(describing: error).contains(invalidPayload))
    }
}

@Test
func inMemoryKeyStoreReturnsStable256BitKey() async throws {
    let store = InMemoryAgentMemoryKeyStore()
    let first = try await store.loadOrCreateKey()
    let second = try await store.loadOrCreateKey()
    let firstBytes = first.withUnsafeBytes { Data($0) }
    let secondBytes = second.withUnsafeBytes { Data($0) }

    #expect(firstBytes.count == 32)
    #expect(firstBytes == secondBytes)
}
