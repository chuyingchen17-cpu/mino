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
func inMemoryKeyStoreReturnsStable256BitKey() async throws {
    let store = InMemoryAgentMemoryKeyStore()
    let first = try await store.loadOrCreateKey()
    let second = try await store.loadOrCreateKey()
    let firstBytes = first.withUnsafeBytes { Data($0) }
    let secondBytes = second.withUnsafeBytes { Data($0) }

    #expect(firstBytes.count == 32)
    #expect(firstBytes == secondBytes)
}
