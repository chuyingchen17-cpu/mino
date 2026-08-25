import Foundation
import Testing
@testable import MinoDomain

private let accountID = AccountID(rawValue: "00000000-0000-4000-8000-00000000000a")
private let petID = PetProfileID(rawValue: "00000000-0000-4000-8000-0000000000a1")
private let friendPetID = PetProfileID(rawValue: "00000000-0000-4000-8000-0000000000b1")

@Test
func accountEventUsesNumericCursorAndMilliseconds() throws {
    let event = try decoder.decode(AccountEvent.self, from: Data("""
    {
      "sequence":42,
      "id":"event-42",
      "schemaVersion":1,
      "recipientAccountID":"00000000-0000-4000-8000-00000000000a",
      "friendshipID":"00000000-0000-4000-8000-000000000001",
      "type":"visit.closed",
      "aggregateType":"visit",
      "aggregateID":"00000000-0000-4000-8000-000000000010",
      "aggregateVersion":3,
      "payload":{},
      "timelineVisible":true,
      "occurredAt":1700000000123
    }
    """.utf8))

    #expect(event.sequence == 42)
    #expect(event.occurredAt == Date(timeIntervalSince1970: 1_700_000_000.123))
}

@Test
func bootstrapRestoresOutgoingAndIncomingVisitVisibility() throws {
    var outgoing = VisitProjectionReducer(accountID: accountID, ownPetID: petID)
    outgoing.reconcile(try bootstrap(activeVisit: activeVisitJSON(visitorOwner: accountID.rawValue, host: friendAccountID)))
    #expect(outgoing.projection.ownPetIsVisible == false)
    #expect(outgoing.projection.activeOutgoingVisit?.visitorPetID == petID)

    var incoming = VisitProjectionReducer(accountID: accountID, ownPetID: petID)
    incoming.reconcile(try bootstrap(activeVisit: activeVisitJSON(visitorOwner: friendAccountID, host: accountID.rawValue)))
    #expect(incoming.projection.ownPetIsVisible)
    #expect(incoming.projection.activeIncomingVisit?.visitorPetID == friendPetID)
    #expect(incoming.projection.remotePet?.petID == friendPetID)
}

@Test
func projectionDeduplicatesAggregateVersionAndRecoversOnClose() throws {
    var reducer = VisitProjectionReducer(accountID: accountID, ownPetID: petID)
    reducer.reconcile(try bootstrap(activeVisit: activeVisitJSON(visitorOwner: accountID.rawValue, host: friendAccountID)))
    let close = try event(type: "visit.closed", version: 2, status: "closed")
    #expect(reducer.apply(close) == .applied)
    #expect(reducer.projection.ownPetIsVisible)
    #expect(reducer.projection.activeOutgoingVisit == nil)

    let replay = try event(type: "visit.closed", version: 2, status: "closed", id: "event-replay")
    #expect(reducer.apply(replay) == .duplicate)
}

@Test
func unknownEventRequestsBootstrapWithoutMutatingProjection() throws {
    var reducer = VisitProjectionReducer(accountID: accountID, ownPetID: petID)
    let unknown = try event(type: "future.visit.teleported", version: 1, status: "active")
    #expect(reducer.apply(unknown) == .requiresBootstrap)
    #expect(reducer.projection.ownPetIsVisible)
}

private let friendAccountID = "00000000-0000-4000-8000-00000000000b"
private let visitID = "00000000-0000-4000-8000-000000000010"

private func bootstrap(activeVisit: String) throws -> SyncBootstrap {
    try decoder.decode(SyncBootstrap.self, from: Data("""
    {
      "account":{"id":"\(accountID.rawValue)","displayName":"Alice","primaryAgentDeviceID":"00000000-0000-4000-8000-0000000000da","createdAt":1,"updatedAt":1},
      "currentDevice":{"id":"00000000-0000-4000-8000-0000000000da","accountID":"\(accountID.rawValue)","displayName":"Mac","platform":"macos","appVersion":"dev","createdAt":1,"revokedAt":null},
      "isPrimaryAgentDevice":true,
      "pet":{"petID":"\(petID.rawValue)","displayName":"奶糖","appearanceSchemaVersion":1,"appearanceCatalogVersion":1,"appearanceVersion":1,"appearance":{"rigID":"mino-default","body":"default"}},
      "friendships":[{"id":"00000000-0000-4000-8000-000000000001","requesterAccountID":"\(accountID.rawValue)","addresseeAccountID":"\(friendAccountID)","status":"accepted","version":1,"createdAt":1,"respondedAt":1,"closedAt":null,"friend":{"accountID":"\(friendAccountID)","displayName":"Bob","pet":{"petID":"\(friendPetID.rawValue)","displayName":"团子","appearanceSchemaVersion":1,"appearanceCatalogVersion":1,"appearanceVersion":1,"appearance":{"rigID":"mino-default","body":"default"}}}}],
      "pendingVisits":[],"activeVisits":[\(activeVisit)],"unresolvedVisitActions":[],"activeConversations":[],"cursor":7,"serverTime":2
    }
    """.utf8))
}

private func activeVisitJSON(visitorOwner: String, host: String, status: String = "active") -> String {
    let visitor = visitorOwner == accountID.rawValue ? petID.rawValue : friendPetID.rawValue
    return """
    {"id":"\(visitID)","friendshipID":"00000000-0000-4000-8000-000000000001","visitorPetID":"\(visitor)","visitorOwnerAccountID":"\(visitorOwner)","hostAccountID":"\(host)","requestedByAccountID":"\(visitorOwner)","responderAccountID":"\(host)","status":"\(status)","closeReason":null,"reason":"hello","version":1,"createdAt":1,"expiresAt":9999999999999,"startedAt":2,"closedAt":null}
    """
}

private func event(
    type: String,
    version: Int,
    status: String,
    id: String = "event-1"
) throws -> AccountEvent {
    let visit = activeVisitJSON(visitorOwner: accountID.rawValue, host: friendAccountID, status: status)
    return try decoder.decode(AccountEvent.self, from: Data("""
    {"sequence":9,"id":"\(id)","schemaVersion":1,"recipientAccountID":"\(accountID.rawValue)","friendshipID":"00000000-0000-4000-8000-000000000001","type":"\(type)","aggregateType":"visit","aggregateID":"\(visitID)","aggregateVersion":\(version),"payload":{"visit":\(visit)},"timelineVisible":true,"occurredAt":3}
    """.utf8))
}

private var decoder: JSONDecoder {
    let value = JSONDecoder()
    value.dateDecodingStrategy = .millisecondsSince1970
    return value
}
