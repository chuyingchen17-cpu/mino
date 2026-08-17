import AppKit
import Darwin
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
            if requiresLiveConfiguration() {
                terminateForInvalidLiveConfiguration(error)
            }
            MinoLog.lifecycle.error(
                "Invalid configuration; falling back to offline mode: \(String(describing: error), privacy: .public)"
            )
            // Keep a valid debug identity isolated even when another setting is
            // malformed. Alice and Bob must never collapse into the same local
            // storage or Keychain namespace as a side effect of fallback.
            let profile = switch ProcessInfo.processInfo.environment["MINO_CLIENT_PROFILE"]?
                .lowercased() {
            case "alice": ClientRuntimeProfile.alice
            case "bob": ClientRuntimeProfile.bob
            default: ClientRuntimeProfile.standard
            }
            configuration = AppConfiguration(
                backend: .offline,
                clientProfile: profile
            )
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

    private static func requiresLiveConfiguration(
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        let info = bundle.infoDictionary ?? [:]
        let mode = environment["MINO_BACKEND_MODE"]
            ?? info["MinoBackendMode"] as? String
        let profile = environment["MINO_CLIENT_PROFILE"]
            ?? info["MinoClientProfile"] as? String
        return mode?.lowercased() == "remote"
            || !(profile?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    private static func terminateForInvalidLiveConfiguration(_ error: Error) -> Never {
        let message = "Invalid live Mino configuration; refusing offline fallback: \(error)"
        MinoLog.lifecycle.fault("\(message, privacy: .public)")
        FileHandle.standardError.write(Data("\(message)\n".utf8))
        Darwin.exit(78)
    }
}
