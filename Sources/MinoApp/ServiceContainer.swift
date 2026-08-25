import Foundation
import MinoDomain
import MinoInfrastructure
import MinoPersistence
import MinoSecurity

struct ServiceContainer: Sendable {
    enum StorageMode: String, Sendable {
        case persistent
        case ephemeral
    }

    let configuration: AppConfiguration
    let backend: any AccountBackendService
    let realtimeSignals: (any AccountEventSignalService)?
    let sessionStore: any SessionCredentialStore
    let socialMutationOutbox: any SocialMutationOutboxStore
    let personalTimelineStore: any PersonalTimelineStore
    let accountEventCursorStore: any AccountEventCursorStore
    let agentMemoryKeyStore: any AgentMemoryKeyStore
    let agentMemoryFileURL: URL?
    let storageMode: StorageMode

    static func live(configuration: AppConfiguration) throws -> ServiceContainer {
        let profile = configuration.clientProfile
        let paths = try AppStoragePaths.live(storageNamespace: profile.storageNamespace)
        let executableIdentity = try KeychainSessionCredentialStore.currentExecutableIdentity()
        let sessionExecutableFingerprint = KeychainSessionCredentialStore
            .executableFingerprintForLocalFallback(identity: executableIdentity)
        let agentMemoryFileURL = paths.rootDirectory.appendingPathComponent(
            agentMemoryFileName(executableFingerprint: sessionExecutableFingerprint),
            isDirectory: false
        )
        let sessionStore: any SessionCredentialStore
        let agentMemoryKeyStore: any AgentMemoryKeyStore
        if let sessionExecutableFingerprint {
            // Ad-hoc executables have no stable Keychain designated
            // requirement. Keep their credentials encrypted in owner-only,
            // build-scoped files so a relaunch works without a password prompt.
            let securityDirectory = paths.rootDirectory.appendingPathComponent(
                localSecurityDirectoryName(
                    executableFingerprint: sessionExecutableFingerprint
                ),
                isDirectory: true
            )
            let fileKeyStore = FileAgentMemoryKeyStore(
                fileURL: securityDirectory.appendingPathComponent(
                    "local-secret.key",
                    isDirectory: false
                )
            )
            sessionStore = EncryptedFileSessionCredentialStore(
                fileURL: securityDirectory.appendingPathComponent(
                    "session.enc",
                    isDirectory: false
                ),
                keyProvider: fileKeyStore
            )
            agentMemoryKeyStore = fileKeyStore
        } else {
            sessionStore = try KeychainSessionCredentialStore(
                namespace: profile.keychainNamespace
            )
            agentMemoryKeyStore = try KeychainAgentMemoryKeyStore(
                namespace: profile.keychainNamespace
            )
        }
        let tokenProvider = StoredAccessTokenProvider(
            store: sessionStore,
            configuration: configuration.backend
        )
        let backend = BackendServiceFactory.make(
            configuration: configuration.backend,
            tokenProvider: tokenProvider
        )
        let realtimeSignals: (any AccountEventSignalService)? =
            configuration.backend.mode == .remote
            ? WebSocketAccountEventSignalService(
                configuration: configuration.backend,
                tokenProvider: tokenProvider
            )
            : nil
        return ServiceContainer(
            configuration: configuration,
            backend: backend,
            realtimeSignals: realtimeSignals,
            sessionStore: sessionStore,
            socialMutationOutbox: FileSocialMutationOutboxStore(paths: paths),
            personalTimelineStore: FilePersonalTimelineStore(paths: paths),
            accountEventCursorStore: FileAccountEventCursorStore(paths: paths),
            agentMemoryKeyStore: agentMemoryKeyStore,
            agentMemoryFileURL: agentMemoryFileURL,
            storageMode: .persistent
        )
    }

    package static func agentMemoryFileName(executableFingerprint: Data?) -> String {
        guard let executableFingerprint, !executableFingerprint.isEmpty else {
            return "agent-memory.json.enc"
        }
        let suffix = executableFingerprint.prefix(20).map {
            String(format: "%02x", $0)
        }.joined()
        return "agent-memory.executable.\(suffix).json.enc"
    }

    package static func localSecurityDirectoryName(
        executableFingerprint: Data
    ) -> String {
        let suffix = executableFingerprint.prefix(20).map {
            String(format: "%02x", $0)
        }.joined()
        return "local-security.executable.\(suffix)"
    }

    static func ephemeral(configuration: AppConfiguration) -> ServiceContainer {
        let sessionStore = InMemorySessionCredentialStore()
        let tokenProvider = StoredAccessTokenProvider(
            store: sessionStore,
            configuration: configuration.backend
        )
        return ServiceContainer(
            configuration: configuration,
            backend: BackendServiceFactory.make(
                configuration: configuration.backend,
                tokenProvider: tokenProvider
            ),
            realtimeSignals: nil,
            sessionStore: sessionStore,
            socialMutationOutbox: InMemorySocialMutationOutboxStore(),
            personalTimelineStore: InMemoryPersonalTimelineStore(),
            accountEventCursorStore: InMemoryAccountEventCursorStore(),
            agentMemoryKeyStore: InMemoryAgentMemoryKeyStore(),
            agentMemoryFileURL: nil,
            storageMode: .ephemeral
        )
    }
}

private actor StoredAccessTokenProvider: AccessTokenProvider {
    let store: any SessionCredentialStore
    let authenticationBackend: HTTPBackendService

    init(store: any SessionCredentialStore, configuration: BackendConfiguration) {
        self.store = store
        authenticationBackend = HTTPBackendService(
            configuration: configuration,
            tokenProvider: AnonymousAccessTokenProvider()
        )
    }

    func accessToken() async throws -> String? {
        guard var credential = try await store.load() else { return nil }
        if credential.needsRefresh() {
            guard let refreshToken = credential.refreshToken, !refreshToken.isEmpty else {
                return nil
            }
            let session = try await authenticationBackend.refreshSession(refreshToken)
            credential = SessionCredential(
                accountID: session.accountID,
                deviceID: session.device.id,
                accessToken: session.accessToken,
                refreshToken: session.refreshToken,
                accessTokenExpiresAt: session.accessExpiresAt,
                issuedAt: Date()
            )
            try await store.save(credential)
        }
        return credential.accessToken
    }
}
