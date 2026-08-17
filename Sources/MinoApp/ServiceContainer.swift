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
    let backend: any MVPBackendService
    let realtimeEvents: (any FriendshipEventRealtimeService)?
    let sessionStore: any SessionCredentialStore
    let interactionOutbox: any InteractionOutboxStore
    let personalTimelineStore: any PersonalTimelineStore
    let friendshipEventCursorStore: any FriendshipEventCursorStore
    let agentMemoryKeyStore: any AgentMemoryKeyStore
    let agentMemoryFileURL: URL?
    let storageMode: StorageMode

    static func live(configuration: AppConfiguration) throws -> ServiceContainer {
        let profile = configuration.clientProfile
        let paths = try AppStoragePaths.live(storageNamespace: profile.storageNamespace)
        let sessionStore = try KeychainSessionCredentialStore(
            namespace: profile.keychainNamespace
        )
        let tokenProvider = StoredAccessTokenProvider(store: sessionStore)
        let backend = BackendServiceFactory.make(
            configuration: configuration.backend,
            tokenProvider: tokenProvider
        )
        let realtimeEvents: (any FriendshipEventRealtimeService)? =
            configuration.backend.mode == .remote
            ? WebSocketFriendshipEventService(
                configuration: configuration.backend,
                tokenProvider: tokenProvider
            )
            : nil
        return ServiceContainer(
            configuration: configuration,
            backend: backend,
            realtimeEvents: realtimeEvents,
            sessionStore: sessionStore,
            interactionOutbox: FileInteractionOutboxStore(paths: paths),
            personalTimelineStore: FilePersonalTimelineStore(paths: paths),
            friendshipEventCursorStore: FileFriendshipEventCursorStore(paths: paths),
            agentMemoryKeyStore: try KeychainAgentMemoryKeyStore(
                namespace: profile.keychainNamespace
            ),
            agentMemoryFileURL: paths.rootDirectory.appendingPathComponent(
                "agent-memory.json.enc",
                isDirectory: false
            ),
            storageMode: .persistent
        )
    }

    static func ephemeral(configuration: AppConfiguration) -> ServiceContainer {
        let sessionStore = InMemorySessionCredentialStore()
        let tokenProvider = StoredAccessTokenProvider(store: sessionStore)
        return ServiceContainer(
            configuration: configuration,
            backend: BackendServiceFactory.make(
                configuration: configuration.backend,
                tokenProvider: tokenProvider
            ),
            realtimeEvents: nil,
            sessionStore: sessionStore,
            interactionOutbox: InMemoryInteractionOutboxStore(),
            personalTimelineStore: InMemoryPersonalTimelineStore(),
            friendshipEventCursorStore: InMemoryFriendshipEventCursorStore(),
            agentMemoryKeyStore: InMemoryAgentMemoryKeyStore(),
            agentMemoryFileURL: nil,
            storageMode: .ephemeral
        )
    }
}

private struct StoredAccessTokenProvider: AccessTokenProvider {
    let store: any SessionCredentialStore

    func accessToken() async throws -> String? {
        guard let credential = try await store.load(), !credential.needsRefresh() else {
            return nil
        }
        return credential.accessToken
    }
}
