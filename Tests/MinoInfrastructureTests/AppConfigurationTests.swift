import Foundation
import MinoDomain
import Testing
@testable import MinoInfrastructure

@Test
func standardClientUsesTheBuiltInMinoCloudByDefault() throws {
    let configuration = try AppConfigurationLoader.load(info: [:], environment: [:])
    #expect(configuration == .minoCloud)
    #expect(configuration.backend.baseURL?.absoluteString == "https://api.mino.pet")
}

@Test
func explicitOfflineModeRemainsAvailableForLocalDevelopment() throws {
    let configuration = try AppConfigurationLoader.load(
        info: [:],
        environment: ["MINO_BACKEND_MODE": "offline"]
    )
    #expect(configuration == .offline)
}

@Test
func debugClientProfilesProvideIsolatedRuntimeMetadata() throws {
    let alice = try AppConfigurationLoader.load(info: [:], environment: ["MINO_CLIENT_PROFILE": "alice"])
    let bob = try AppConfigurationLoader.load(info: [:], environment: ["MINO_CLIENT_PROFILE": "bob"])
    #expect(alice.clientProfile.storageNamespace != bob.clientProfile.storageNamespace)
    #expect(alice.clientProfile.screenRegion == .leftHalf)
    #expect(bob.clientProfile.screenRegion == .rightHalf)
    #expect(alice.backend.mode == .offline)
    #expect(bob.backend.mode == .offline)
}

@Test
func debugRemoteProfileRequiresAnExplicitEndpoint() {
    #expect(throws: ConfigurationError.missingBackendBaseURL) {
        try AppConfigurationLoader.load(info: [:], environment: [
            "MINO_CLIENT_PROFILE": "alice",
            "MINO_BACKEND_MODE": "remote"
        ])
    }
}

@Test
func environmentOverridesBundledBackendConfiguration() throws {
    let configuration = try AppConfigurationLoader.load(
        info: ["MinoBackendMode": "offline"],
        environment: [
            "MINO_BACKEND_MODE": "remote",
            "MINO_API_BASE_URL": "http://127.0.0.1:4310",
            "MINO_API_VERSION": "v1"
        ]
    )
    #expect(configuration.backend.mode == .remote)
    #expect(configuration.backend.baseURL?.port == 4310)
}

@Test
func productionBundleUsesTheBuiltInMinoAPI() throws {
    let configuration = try AppConfigurationLoader.load(
        info: [
            "MinoBackendMode": "remote",
            "MinoAPIBaseURL": "https://api.mino.pet",
            "MinoAPIVersion": "v1"
        ],
        environment: [:]
    )
    #expect(configuration.backend.mode == .remote)
    #expect(configuration.backend.baseURL?.absoluteString == "https://api.mino.pet")
}

@Test
func remoteBackendRejectsInsecureNonLocalURL() {
    #expect(throws: ConfigurationError.insecureBackendBaseURL("http://api.example.com")) {
        try AppConfigurationLoader.load(info: [:], environment: [
            "MINO_BACKEND_MODE": "remote",
            "MINO_API_BASE_URL": "http://api.example.com"
        ])
    }
}

@Test
func profileRequestBuilderSupportsWorkerReadAndUpdate() throws {
    let builder = BackendRequestBuilder(configuration: remoteConfiguration())
    let read = try builder.currentProfileRequest(accessToken: "token")
    let update = try builder.updateCurrentProfileRequest(
        accountName: "Alice", petName: "奶糖", accessToken: "token"
    )
    #expect(read.url?.path == "/v1/me/profile")
    #expect(update.httpMethod == "PATCH")
    #expect(update.value(forHTTPHeaderField: "Authorization") == "Bearer token")
}

private func remoteConfiguration() -> BackendConfiguration {
    BackendConfiguration(mode: .remote, baseURL: URL(string: "http://127.0.0.1:4310"), apiVersion: "v1")
}
