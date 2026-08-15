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
    let backend: any BackendService
    let sessionStore: any SessionCredentialStore
    let coupleSnapshotStore: any CoupleSnapshotStore
    let interactionOutbox: any InteractionOutboxStore
    let storageMode: StorageMode

    static func live(configuration: AppConfiguration) throws -> ServiceContainer {
        let paths = try AppStoragePaths.live()
        let sessionStore = KeychainSessionCredentialStore()
        let tokenProvider = StoredAccessTokenProvider(store: sessionStore)
        return ServiceContainer(
            configuration: configuration,
            backend: BackendServiceFactory.make(
                configuration: configuration.backend,
                tokenProvider: tokenProvider
            ),
            sessionStore: sessionStore,
            coupleSnapshotStore: FileCoupleSnapshotStore(paths: paths),
            interactionOutbox: FileInteractionOutboxStore(paths: paths),
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
            sessionStore: sessionStore,
            coupleSnapshotStore: InMemoryCoupleSnapshotStore(),
            interactionOutbox: InMemoryInteractionOutboxStore(),
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
