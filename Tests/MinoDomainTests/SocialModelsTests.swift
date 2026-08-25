import Foundation
import Testing
@testable import MinoDomain

@Test
func socialWireModelsDecodeWorkerConversationAndMessage() throws {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .millisecondsSince1970
    let conversation = try decoder.decode(PetConversation.self, from: Data("""
    {"id":"conversation_1","friendshipID":"friendship_1","initiatorPetID":"pet_alice","recipientPetID":"pet_bob","status":"active","nextSpeakerPetID":"pet_bob","turnCount":1,"version":1,"createdAt":1000,"endedAt":null}
    """.utf8))
    let message = try decoder.decode(PetConversationMessage.self, from: Data("""
    {"id":"message_1","conversationID":"conversation_1","senderAccountID":"account_alice","actorType":"pet_agent","body":"你好","turnIndex":0,"createdAt":1000}
    """.utf8))

    #expect(conversation.version == 1)
    #expect(conversation.nextSpeakerPetID == PetProfileID(rawValue: "pet_bob"))
    #expect(message.actorType == .petAgent)
    #expect(message.body == "你好")
}

@Test
func accountLetterEventNeverCarriesPlaintext() throws {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .millisecondsSince1970
    let event = try decoder.decode(AccountEvent.self, from: Data("""
    {"sequence":8,"id":"event_8","schemaVersion":1,"recipientAccountID":"account_alice","friendshipID":"friendship_1","type":"letter.delivered","aggregateType":"letter","aggregateID":"letter_1","aggregateVersion":null,"payload":{"letterID":"letter_1","visitID":"visit_1","futureField":true},"timelineVisible":true,"occurredAt":1000}
    """.utf8))

    #expect(event.payload["body"] == nil)
    #expect(event.payload["futureField"] == .bool(true))
    #expect(event.timelineEvent()?.letterID == LetterID(rawValue: "letter_1"))
}

@Test
func visitCloseBecomesOneAggregatedInteractionTimelineEvent() throws {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .millisecondsSince1970
    let event = try decoder.decode(AccountEvent.self, from: Data("""
    {"sequence":9,"id":"event_9","schemaVersion":1,"recipientAccountID":"account_alice","friendshipID":"friendship_1","type":"visit.closed","aggregateType":"visit","aggregateID":"visit_1","aggregateVersion":3,"payload":{"visit":{"id":"visit_1","visitorPetID":"pet_bob"},"interactionSummary":{"counts":{"feed":2,"cuddle":1},"familiarityGained":3,"letterAttached":true}},"timelineVisible":true,"occurredAt":1000}
    """.utf8))

    let timeline = event.timelineEvent()
    #expect(timeline?.kind == .visitReturned)
    #expect(timeline?.visitInteractionSummary?.counts[.feed] == 2)
    #expect(timeline?.visitInteractionSummary?.counts[.cuddle] == 1)
    #expect(timeline?.visitInteractionSummary?.familiarityGained == 3)
    #expect(timeline?.visitInteractionSummary?.letterAttached == true)
}
