import Foundation
import MinoDomain
import Testing

@testable import MinoInfrastructure

@Test
func offlineIsTheSafeDefault() throws {
    let configuration = try AppConfigurationLoader.load(info: [:], environment: [:])

    #expect(configuration.backend.mode == .offline)
    #expect(configuration.backend.baseURL == nil)
    #expect(configuration.clientProfile == .standard)
}

@Test
func debugClientProfilesProvideIsolatedRuntimeMetadata() throws {
    let alice = try AppConfigurationLoader.load(
        info: ["MinoClientProfile": "bob"],
        environment: ["MINO_CLIENT_PROFILE": " Alice "]
    )
    let bob = try AppConfigurationLoader.load(
        info: [:],
        environment: ["MINO_CLIENT_PROFILE": "BOB"]
    )

    #expect(alice.clientProfile.id == "alice")
    #expect(alice.clientProfile.storageNamespace == "alice")
    #expect(alice.clientProfile.keychainNamespace == "alice")
    #expect(alice.clientProfile.screenRegion == .leftHalf)
    #expect(alice.clientProfile.debugDisplayName == "Alice / 奶糖")
    #expect(bob.clientProfile.id == "bob")
    #expect(bob.clientProfile.screenRegion == .rightHalf)
    #expect(bob.clientProfile.storageNamespace != alice.clientProfile.storageNamespace)
    #expect(bob.clientProfile.keychainNamespace != alice.clientProfile.keychainNamespace)
}

@Test
func unknownClientProfileIsRejectedBeforeItCanBecomeAPathNamespace() {
    #expect(throws: ConfigurationError.unknownClientProfile("../alice")) {
        try AppConfigurationLoader.load(
            info: [:],
            environment: ["MINO_CLIENT_PROFILE": "../alice"]
        )
    }
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

@Test
func requestBuilderSupportsPresenceVisitAndReturnCargo() throws {
    let configuration = BackendConfiguration(
        mode: .remote,
        baseURL: URL(string: "https://api.example.com/mino"),
        apiVersion: "v1",
        requestTimeout: 9
    )
    let builder = BackendRequestBuilder(configuration: configuration)
    let start = StartPetVisitCommand(
        idempotencyKey: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
        petID: PetProfileID(rawValue: "pet_mine"),
        destinationAccountID: AccountID(rawValue: "account_partner"),
        outboundCargo: [
            PetCargoItem(
                itemID: PetItemID(rawValue: "item_flower"),
                kind: .gift,
                displayName: "小花"
            )
        ],
        expectedPresenceRevision: 3,
        clientCreatedAt: Date(timeIntervalSince1970: 1_000)
    )
    let returning = ReturnPetVisitCommand(
        idempotencyKey: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
        visitID: PetVisitID(rawValue: "visit_1"),
        returnCargo: [
            PetCargoItem(
                itemID: PetItemID(rawValue: "item_reply"),
                kind: .letter,
                displayName: "回信"
            )
        ],
        expectedVisitRevision: 5,
        clientCreatedAt: Date(timeIntervalSince1970: 2_000)
    )

    let presenceRequest = try builder.petPresenceRequest(accessToken: "token")
    let startRequest = try builder.startPetVisitRequest(start, accessToken: "token")
    let returnRequest = try builder.returnPetVisitRequest(returning, accessToken: "token")

    #expect(presenceRequest.url?.absoluteString == "https://api.example.com/mino/v1/pet-presence")
    #expect(presenceRequest.httpMethod == "GET")
    #expect(startRequest.url?.absoluteString == "https://api.example.com/mino/v1/pet-visits")
    #expect(startRequest.httpMethod == "POST")
    #expect(returnRequest.url?.absoluteString == "https://api.example.com/mino/v1/pet-visits/visit_1/return")
    #expect(returnRequest.httpMethod == "POST")
    #expect(
        startRequest.value(forHTTPHeaderField: "Idempotency-Key")
            == "11111111-2222-3333-4444-555555555555"
    )
    #expect(
        returnRequest.value(forHTTPHeaderField: "Idempotency-Key")
            == "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
    )

    let startBody = try #require(startRequest.httpBody)
    let startJSON = try #require(JSONSerialization.jsonObject(with: startBody) as? [String: Any])
    let outboundCargo = try #require(startJSON["outboundCargo"] as? [[String: Any]])
    #expect(outboundCargo.first?["displayName"] as? String == "小花")

    let returnBody = try #require(returnRequest.httpBody)
    let returnJSON = try #require(JSONSerialization.jsonObject(with: returnBody) as? [String: Any])
    let returnCargo = try #require(returnJSON["returnCargo"] as? [[String: Any]])
    #expect(returnCargo.first?["displayName"] as? String == "回信")
}

@Test
func requestBuilderSupportsVisitInvitationsAndTimelineCursor() throws {
    let configuration = BackendConfiguration(
        mode: .remote,
        baseURL: URL(string: "https://api.example.com/mino"),
        apiVersion: "v1",
        requestTimeout: 9
    )
    let builder = BackendRequestBuilder(configuration: configuration)
    let invitationID = PetVisitInvitationID(rawValue: "invite_1")
    let send = SendPetVisitInvitationCommand(
        idempotencyKey: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
        requestedPetID: PetProfileID(rawValue: "pet_partner"),
        clientCreatedAt: Date(timeIntervalSince1970: 1_000)
    )
    let response = RespondToPetVisitInvitationCommand(
        idempotencyKey: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
        invitationID: invitationID,
        response: .accept,
        expectedPresenceRevision: 4,
        clientCreatedAt: Date(timeIntervalSince1970: 2_000)
    )

    let sendRequest = try builder.sendPetVisitInvitationRequest(send, accessToken: "token")
    let pendingRequest = try builder.pendingPetVisitInvitationsRequest(accessToken: "token")
    let responseRequest = try builder.respondToPetVisitInvitationRequest(response, accessToken: "token")
    let timelineRequest = try builder.personalTimelineRequest(after: "cursor 1", accessToken: "token")

    #expect(sendRequest.url?.absoluteString == "https://api.example.com/mino/v1/pet-visit-invitations")
    #expect(sendRequest.httpMethod == "POST")
    #expect(pendingRequest.url?.absoluteString == "https://api.example.com/mino/v1/pet-visit-invitations?status=pending")
    #expect(responseRequest.url?.absoluteString == "https://api.example.com/mino/v1/pet-visit-invitations/invite_1/response")
    #expect(timelineRequest.url?.absoluteString == "https://api.example.com/mino/v1/friendship-events?after=cursor%201")
    #expect(
        responseRequest.value(forHTTPHeaderField: "Idempotency-Key")
            == "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
    )
}
