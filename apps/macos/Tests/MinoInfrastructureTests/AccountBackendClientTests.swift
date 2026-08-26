import Foundation
import MinoDomain
import Testing
@testable import MinoInfrastructure

private let key = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
private let friendshipID = FriendshipID(rawValue: "00000000-0000-4000-8000-000000000001")
private let visitID = PetVisitID(rawValue: "00000000-0000-4000-8000-000000000010")

@Test
func accountEventsUseOneNumericCursorWithoutFriendshipScope() throws {
    let request = try builder.accountEventsRequest(
        after: 42, limit: 100, timelineVisible: nil, accessToken: "token"
    )
    #expect(request.url?.absoluteString == "http://127.0.0.1:4310/v1/events?after=42&limit=100")
    #expect(request.url?.query?.contains("friendshipID") == false)
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token")
}

@Test
func visitCommandsUseAggregatePathsAndHeaderOnlyIdempotency() throws {
    let create = try builder.createVisitRequest(
        CreateVisitCommand(
            friendshipID: friendshipID,
            visitorPetID: PetProfileID(rawValue: "pet_alice"),
            hostAccountID: AccountID(rawValue: "account_bob"),
            idempotencyKey: key
        ),
        accessToken: "token"
    )
    let action = try builder.visitActionRequest(
        visitID: visitID,
        command: CreateVisitActionCommand(
            kind: .message,
            actorType: .human,
            payload: .object(["text": .string("你好")]),
            idempotencyKey: key
        ),
        accessToken: "token"
    )
    #expect(create.url?.path == "/v1/visits")
    #expect(action.url?.path == "/v1/visits/\(visitID.rawValue)/actions")
    #expect(create.value(forHTTPHeaderField: "Idempotency-Key") == key.uuidString)
    let data = try #require(create.httpBody)
    let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(body["idempotencyKey"] == nil)
    #expect(body["friendshipID"] as? String == friendshipID.rawValue)
}

@Test
func conversationAndLetterPathsCarryNoClientFriendshipQuery() throws {
    let message = try builder.sendConversationMessageRequest(
        conversationID: ConversationID(rawValue: "conversation private/1"),
        command: SendConversationMessageCommand(actorType: .human, text: "你好", idempotencyKey: key),
        accessToken: "token"
    )
    let letter = try builder.createLetterRequest(
        visitID: visitID,
        command: CreateLetterCommand(body: "只给真人看的信", idempotencyKey: key),
        accessToken: "token"
    )
    #expect(message.url?.query == nil)
    #expect(letter.url?.path == "/v1/visits/\(visitID.rawValue)/letters")
}

@Test
func developmentBootstrapDoesNotRequireBearerToken() throws {
    let request = try builder.developmentBootstrapRequest(profile: "bob")
    #expect(request.url?.path == "/v1/dev/bootstrap")
    #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
}

@Test
func permanentCharacterSelectionUsesPatchAndHeaderIdempotency() throws {
    let request = try builder.updateOwnPetAppearanceRequest(
        PetAppearanceSelectionCommand(
            characterID: .retrieverYellow,
            idempotencyKey: key
        ),
        accessToken: "token"
    )
    #expect(request.url?.path == "/v1/me/pet")
    #expect(request.httpMethod == "PATCH")
    #expect(request.value(forHTTPHeaderField: "Idempotency-Key") == key.uuidString)
    let data = try #require(request.httpBody)
    let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(body["appearanceSchemaVersion"] as? Int == 1)
    #expect(body["appearanceCatalogVersion"] as? Int == 2)
    #expect(body["idempotencyKey"] == nil)
    let appearance = try #require(body["appearance"] as? [String: String])
    #expect(appearance == [
        "rigID": "maltese-pair-v1",
        "body": "retriever-yellow"
    ])
}

@Test
func githubDeviceFlowUsesAnonymousAccountScopedEndpoints() throws {
    let start = try builder.githubDeviceStartRequest()
    let complete = try builder.githubDeviceCompleteRequest(
        deviceCode: "github-device-code-12345678901234567890",
        device: DeviceMetadata(
            id: DeviceID(rawValue: "00000000-0000-4000-8000-0000000000d1"),
            displayName: "Mino Mac",
            appVersion: "1.0"
        )
    )
    #expect(start.url?.path == "/v1/auth/github/device/start")
    #expect(start.httpMethod == "POST")
    #expect(start.value(forHTTPHeaderField: "Authorization") == nil)
    #expect(complete.url?.path == "/v1/auth/github/device/complete")
    #expect(complete.value(forHTTPHeaderField: "Authorization") == nil)
    let data = try #require(complete.httpBody)
    let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(body["deviceCode"] as? String == "github-device-code-12345678901234567890")
    let device = try #require(body["device"] as? [String: Any])
    #expect(device["platform"] as? String == "macos")
}

@Test
func friendshipWireMapsNestedPublicPetSnapshot() throws {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .millisecondsSince1970
    let wire = try decoder.decode(FriendshipWire.self, from: Data("""
    {"id":"00000000-0000-4000-8000-000000000001","requesterAccountID":"account_alice","addresseeAccountID":"account_bob","status":"accepted","version":1,"createdAt":1000,"respondedAt":2000,"closedAt":null,"friend":{"accountID":"account_bob","displayName":"Bob","pet":{"petID":"pet_bob","displayName":"团子","appearanceSchemaVersion":1,"appearanceCatalogVersion":1,"appearanceVersion":1,"appearance":{"rigID":"mino-default","body":"default"}}}}
    """.utf8))
    #expect(wire.friendProfile?.petID == PetProfileID(rawValue: "pet_bob"))
    #expect(wire.friendProfile?.petName == "团子")
    #expect(wire.friendProfile?.characterID == nil)
}

@Test
func friendshipWireMapsCatalogTwoCharacter() throws {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .millisecondsSince1970
    let wire = try decoder.decode(FriendshipWire.self, from: Data("""
    {"id":"00000000-0000-4000-8000-000000000001","requesterAccountID":"account_alice","addresseeAccountID":"account_bob","status":"accepted","version":1,"createdAt":1000,"respondedAt":2000,"closedAt":null,"friend":{"accountID":"account_bob","displayName":"Bob","pet":{"petID":"pet_bob","displayName":"团子","appearanceSchemaVersion":1,"appearanceCatalogVersion":2,"appearanceVersion":2,"appearance":{"rigID":"maltese-pair-v1","body":"retriever-yellow"}}}}
    """.utf8))
    #expect(wire.friendProfile?.characterID == .retrieverYellow)
}

private let builder = BackendRequestBuilder(
    configuration: BackendConfiguration(
        mode: .remote,
        baseURL: URL(string: "http://127.0.0.1:4310"),
        apiVersion: "v1"
    )
)
