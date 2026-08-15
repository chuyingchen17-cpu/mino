import MinoDomain
import MinoInfrastructure

struct ServiceContainer: Sendable {
    let configuration: AppConfiguration
    let backend: any BackendService

    static func live(configuration: AppConfiguration) -> ServiceContainer {
        ServiceContainer(
            configuration: configuration,
            backend: BackendServiceFactory.make(configuration: configuration.backend)
        )
    }
}
