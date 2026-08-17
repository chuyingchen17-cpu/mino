import Foundation
import MinoDomain
import Testing

@testable import MinoInfrastructure

@Test
func socialRequestBuilderUsesMVPPathsCursorsAndIdempotency() throws {
    let builder = BackendRequestBuilder(
        configuration: BackendConfiguration(
            mode: .remote,
            baseURL: URL(string: "http://127.0.0.1:4310"),
            apiVersion: "v1",
            requestTimeout: 10
        )
    )
    let key = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    let friendshipID = FriendshipID(rawValue: "friendship_1")
    let eventRequest = try builder.eventsRequest(
        friendshipID: friendshipID,
        after: "event 8",
        accessToken: "token"
    )
    let messageRequest = try builder.sendConversationMessageRequest(
        friendshipID: friendshipID,
        conversationID: ConversationID(rawValue: "conversation_1"),
        command: SendConversationMessageCommand(
            actorType: .human,
            text: "你好",
            idempotencyKey: key
        ),
        accessToken: "token"
    )
    let activeConversationsRequest = try builder.conversationsRequest(
        friendshipID: friendshipID,
        status: .active,
        accessToken: "token"
    )
    let conversationMessagesRequest = try builder.conversationMessagesRequest(
        friendshipID: friendshipID,
        conversationID: ConversationID(rawValue: "conversation private/1"),
        accessToken: "token"
    )
    let letterRequest = try builder.createLetterRequest(
        friendshipID: friendshipID,
        visitID: PetVisitID(rawValue: "visit_1"),
        command: CreateLetterCommand(body: "只给真人看的信", idempotencyKey: key),
        accessToken: "token"
    )
    let reactionRequest = try builder.visitReactionRequest(
        friendshipID: friendshipID,
        visitID: PetVisitID(rawValue: "visit_1"),
        command: CreateVisitReactionCommand(
            reaction: .happy,
            text: "谢谢招待",
            idempotencyKey: key
        ),
        accessToken: "token"
    )
    let fetchLetterRequest = try builder.letterRequest(
        friendshipID: friendshipID,
        letterID: LetterID(rawValue: "letter private/1"),
        accessToken: "token"
    )

    #expect(
        eventRequest.url?.absoluteString
            == "http://127.0.0.1:4310/v1/events?friendshipID=friendship_1&after=event%208"
    )
    #expect(
        messageRequest.url?.absoluteString
            == "http://127.0.0.1:4310/v1/conversations/conversation_1/messages?friendshipID=friendship_1"
    )
    #expect(messageRequest.value(forHTTPHeaderField: "Authorization") == "Bearer token")
    #expect(messageRequest.value(forHTTPHeaderField: "Idempotency-Key") == key.uuidString)
    #expect(
        activeConversationsRequest.url?.absoluteString
            == "http://127.0.0.1:4310/v1/conversations?friendshipID=friendship_1&status=active"
    )
    #expect(
        conversationMessagesRequest.url?.absoluteString
            == "http://127.0.0.1:4310/v1/conversations/conversation%20private/1/messages?friendshipID=friendship_1"
    )
    #expect(letterRequest.url?.query == "friendshipID=friendship_1")
    #expect(letterRequest.value(forHTTPHeaderField: "Idempotency-Key") == key.uuidString)
    #expect(reactionRequest.url?.query == "friendshipID=friendship_1")
    #expect(reactionRequest.value(forHTTPHeaderField: "Idempotency-Key") == key.uuidString)
    #expect(
        fetchLetterRequest.url?.absoluteString
            == "http://127.0.0.1:4310/v1/letters/letter%20private/1?friendshipID=friendship_1"
    )
    #expect(fetchLetterRequest.value(forHTTPHeaderField: "Authorization") == "Bearer token")

    let body = try #require(letterRequest.httpBody)
    let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    #expect(object["body"] as? String == "只给真人看的信")

    let reactionBody = try #require(reactionRequest.httpBody)
    let reactionObject = try #require(
        JSONSerialization.jsonObject(with: reactionBody) as? [String: Any]
    )
    #expect(reactionObject["reaction"] as? String == "happy")
    #expect(reactionObject["text"] as? String == "谢谢招待")
}

@Test
func developmentBootstrapDoesNotRequireBearerToken() throws {
    let builder = BackendRequestBuilder(
        configuration: BackendConfiguration(
            mode: .remote,
            baseURL: URL(string: "http://localhost:4310"),
            apiVersion: "v1"
        )
    )

    let request = try builder.developmentBootstrapRequest(profile: "bob")

    #expect(request.url?.path == "/v1/dev/bootstrap")
    #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    let body = try #require(request.httpBody)
    let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    #expect(object["profile"] as? String == "bob")
}

@Test
func friendshipRequestsUseUnifiedEndpointAndServerVocabulary() throws {
    let builder = BackendRequestBuilder(
        configuration: BackendConfiguration(
            mode: .remote,
            baseURL: URL(string: "http://localhost:4310"),
            apiVersion: "v1"
        )
    )
    let key = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

    let pending = try builder.friendshipsRequest(status: .pending, accessToken: "token")
    let create = try builder.createFriendRequest(
        CreateFriendRequestCommand(
            addresseeAccountID: AccountID(rawValue: "account_bob"),
            idempotencyKey: key
        ),
        accessToken: "token"
    )
    let reject = try builder.respondToFriendRequest(
        requestID: FriendRequestID(rawValue: "friendship_1"),
        command: RespondFriendRequestCommand(response: .decline, idempotencyKey: key),
        accessToken: "token"
    )

    #expect(pending.url?.absoluteString == "http://localhost:4310/v1/friendships?status=pending")
    #expect(create.url?.path == "/v1/friendships")
    #expect(reject.url?.path == "/v1/friendships/friendship_1/respond")
    let body = try #require(reject.httpBody)
    let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    #expect(object["response"] as? String == "reject")
}

@Test
func friendshipWireMapsCounterpartyForFriendAndRequestViews() throws {
    let accepted = Data(
        """
        {
          "id":"friendship_1",
          "requesterAccountID":"account_alice",
          "addresseeAccountID":"account_bob",
          "status":"accepted",
          "createdAt":"2026-08-15T08:00:00Z",
          "respondedAt":"2026-08-15T08:05:00Z",
          "friend":{
            "accountID":"account_bob",
            "displayName":"Bob",
            "petID":"pet_bob",
            "petName":"团子"
          }
        }
        """.utf8
    )
    let rejected = Data(
        """
        {
          "id":"friendship_2",
          "requesterAccountID":"account_charlie",
          "addresseeAccountID":"account_alice",
          "status":"rejected",
          "createdAt":"2026-08-15T09:00:00Z",
          "respondedAt":null,
          "friend":{
            "accountID":"account_charlie",
            "displayName":"Charlie",
            "petID":"pet_charlie",
            "petName":"星星"
          }
        }
        """.utf8
    )
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let acceptedWire = try decoder.decode(FriendshipWire.self, from: accepted)
    let friend = try #require(acceptedWire.friendProfile)
    #expect(friend.friendshipID == FriendshipID(rawValue: "friendship_1"))
    #expect(friend.accountID == AccountID(rawValue: "account_bob"))
    #expect(friend.petName == "团子")

    let rejectedWire = try decoder.decode(FriendshipWire.self, from: rejected)
    let request = try #require(rejectedWire.friendRequest)
    #expect(request.status == .declined)
    #expect(request.friendAccountID == AccountID(rawValue: "account_charlie"))
    #expect(request.friendPetName == "星星")
}
