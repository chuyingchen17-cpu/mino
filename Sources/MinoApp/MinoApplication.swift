import AppKit
import MinoInfrastructure

@main
enum MinoApplication {
    @MainActor
    private static var retainedDelegate: AppDelegate?

    @MainActor
    static func main() {
        let application = NSApplication.shared
        let configuration: AppConfiguration
        do {
            configuration = try AppConfigurationLoader.load()
        } catch {
            MinoLog.lifecycle.error(
                "Invalid configuration; falling back to offline mode: \(String(describing: error), privacy: .public)"
            )
            configuration = .offline
        }
        let services: ServiceContainer
        do {
            services = try .live(configuration: configuration)
        } catch {
            MinoLog.lifecycle.fault(
                "Persistent services unavailable; using ephemeral stores: \(String(describing: error), privacy: .public)"
            )
            services = .ephemeral(configuration: configuration)
        }
        let delegate = AppDelegate(services: services)

        retainedDelegate = delegate
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}
