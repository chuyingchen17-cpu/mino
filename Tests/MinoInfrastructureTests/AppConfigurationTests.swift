import Foundation
import MinoDomain
import Testing

@testable import MinoInfrastructure

@Test
func offlineIsTheSafeDefault() throws {
    let configuration = try AppConfigurationLoader.load(info: [:], environment: [:])

    #expect(configuration.backend.mode == .offline)
    #expect(configuration.backend.baseURL == nil)
}

@Test
func environmentOverridesBundledBackendConfiguration() throws {
    let configuration = try AppConfigurationLoader.load(
        info: [
            "MinoBackendMode": "offline",
            "MinoAPIVersion": "v1"
        ],
        environment: [
            "MINO_BACKEND_MODE": "remote",
            "MINO_API_BASE_URL": "https://api.example.com/mino",
            "MINO_API_VERSION": "v2",
            "MINO_REQUEST_TIMEOUT": "12"
        ]
    )

    #expect(configuration.backend.mode == .remote)
    #expect(configuration.backend.baseURL == URL(string: "https://api.example.com/mino"))
    #expect(configuration.backend.apiVersion == "v2")
    #expect(configuration.backend.requestTimeout == 12)
}

@Test
func remoteBackendRejectsInsecureNonLocalURL() {
    #expect(throws: ConfigurationError.insecureBackendBaseURL("http://api.example.com")) {
        try AppConfigurationLoader.load(
            info: [:],
            environment: [
                "MINO_BACKEND_MODE": "remote",
                "MINO_API_BASE_URL": "http://api.example.com"
            ]
        )
    }
}

@Test
func requestBuilderUsesVersionedPathsAndIdempotency() throws {
    let configuration = BackendConfiguration(
        mode: .remote,
        baseURL: URL(string: "https://api.example.com/mino"),
        apiVersion: "v1",
        requestTimeout: 9
    )
    let builder = BackendRequestBuilder(configuration: configuration)
    let command = InteractionCommand(
        idempotencyKey: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
        kind: .flowerGift,
        senderPetID: PetProfileID(rawValue: "pet_mine"),
        recipientPetID: PetProfileID(rawValue: "pet_partner"),
        clientCreatedAt: Date(timeIntervalSince1970: 0)
    )

    let healthRequest = try builder.healthRequest(accessToken: nil)
    let interactionRequest = try builder.interactionRequest(command, accessToken: "token")

    #expect(healthRequest.url?.absoluteString == "https://api.example.com/mino/v1/health")
    #expect(healthRequest.httpMethod == "GET")
    #expect(interactionRequest.url?.absoluteString == "https://api.example.com/mino/v1/interactions")
    #expect(interactionRequest.httpMethod == "POST")
    #expect(interactionRequest.value(forHTTPHeaderField: "Authorization") == "Bearer token")
    #expect(
        interactionRequest.value(forHTTPHeaderField: "Idempotency-Key")
            == "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
    )
    let body = try #require(interactionRequest.httpBody)
    let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    #expect(json["senderPetID"] as? String == "pet_mine")
    #expect(json["recipientPetID"] as? String == "pet_partner")
}
