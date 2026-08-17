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
