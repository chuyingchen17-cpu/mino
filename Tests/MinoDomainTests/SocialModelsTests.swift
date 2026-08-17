import Foundation
import Testing

@testable import MinoDomain

@Test
func socialWireModelsDecodeBackendConversationAndVisit() throws {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let conversationData = Data(
        #"{"id":"conversation_1","coupleID":"couple_1","initiatorPetID":"pet_alice","recipientPetID":"pet_bob","status":"active","nextSpeakerPetID":"pet_bob","turnCount":1,"createdAt":"2026-08-15T12:00:00Z","endedAt":null}"#.utf8
    )
    let visitData = Data(
        #"{"id":"visit_1","coupleID":"couple_1","visitorPetID":"pet_bob","visitorOwnerAccountID":"account_bob","hostAccountID":"account_alice","requestedByAccountID":"account_alice","reason":"来玩吧","status":"active","createdAt":"2026-08-15T12:00:00Z","startedAt":"2026-08-15T12:01:00Z","endedAt":null}"#.utf8
    )

    let conversation = try decoder.decode(PetConversation.self, from: conversationData)
    let visit = try decoder.decode(MVPVisit.self, from: visitData)

    #expect(conversation.nextSpeakerPetID == PetProfileID(rawValue: "pet_bob"))
    #expect(conversation.turnCount == 1)
    #expect(visit.status == .active)
    #expect(visit.visitorOwnerAccountID == AccountID(rawValue: "account_bob"))
}

@Test
func durableEventPayloadIsForwardCompatibleAndKeepsLetterBodyAbsent() throws {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let data = Data(
        #"{"id":"event_9","sequence":9,"coupleID":"couple_1","type":"letter_received","actorType":"system","actorID":null,"payload":{"letterID":"letter_1","visitID":"visit_1","futureField":true},"timelineVisible":true,"occurredAt":"2026-08-15T12:02:00Z"}"#.utf8
    )

    let event = try decoder.decode(FriendshipEvent.self, from: data)

    #expect(event.payload["letterID"]?.stringValue == "letter_1")
    #expect(event.payload["body"] == nil)
    #expect(event.payload["futureField"] == .bool(true))
    let timeline = try #require(event.timelineEvent())
    #expect(timeline.kind == .letterReceived)
    #expect(timeline.letterID == LetterID(rawValue: "letter_1"))
}

@Test
func conversationSummaryMapsToEventLineWithoutDuration() {
    let event = FriendshipEvent(
        id: "event_10",
        sequence: 10,
        friendshipID: FriendshipID(rawValue: "friendship_1"),
        type: "conversation_summary",
        actorType: .pet,
        actorID: "pet_alice",
        payload: .object([
            "conversationID": .string("conversation_1"),
            "summary": .string("奶糖和团子约好下次一起晒太阳")
        ]),
        timelineVisible: true,
        occurredAt: Date(timeIntervalSince1970: 100)
    )

    let timeline = event.timelineEvent()

    #expect(timeline?.kind == .conversationSummary)
    #expect(timeline?.summary == "奶糖和团子约好下次一起晒太阳")
    #expect(timeline?.occurredAt == Date(timeIntervalSince1970: 100))
}

@Test
func developmentProfileCarriesOnlyTheLocalIdentity() throws {
    let decoder = JSONDecoder()
    let data = Data(
        #"{"profile":"alice","token":"dev-token","accountID":"account_alice","petID":"pet_alice","accountName":"Alice","petName":"奶糖","friends":[{"friendshipID":"friendship_1","accountID":"account_bob","petID":"pet_bob","accountName":"Bob","petName":"团子"}]}"#.utf8
    )

    let profile = try decoder.decode(DevBootstrapProfile.self, from: data)

    #expect(profile.petName == "奶糖")
    #expect(profile.accountID == AccountID(rawValue: "account_alice"))
    #expect(!String(decoding: data, as: UTF8.self).contains("coordinate"))
}
