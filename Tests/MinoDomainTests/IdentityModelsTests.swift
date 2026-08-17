import Foundation
import Testing

@testable import MinoDomain

@Test
func visitInvitationAndTimelineRoundTripThroughJSON() throws {
    let invitation = PetVisitInvitation(
        id: PetVisitInvitationID(rawValue: "invite_1"),
        coupleID: CoupleID(rawValue: "couple_1"),
        inviterAccountID: AccountID(rawValue: "account_local"),
        invitedAccountID: AccountID(rawValue: "account_partner"),
        requestedPetID: PetProfileID(rawValue: "pet_partner"),
        hostAccountID: AccountID(rawValue: "account_local"),
        status: .pending,
        createdAt: Date(timeIntervalSince1970: 1_000)
    )
    let event = PersonalTimelineEvent(
        id: "event_1",
        kind: .postcardReceived,
        occurredAt: Date(timeIntervalSince1970: 1_000),
        petID: invitation.requestedPetID,
        invitationID: invitation.id,
        interactionKind: .walk,
        cargoItems: [
            PetCargoItem(
                itemID: PetItemID(rawValue: "item_flower"),
                kind: .gift,
                displayName: "小花"
            )
        ],
        postcard: PetPostcard(
            id: "postcard_1",
            title: "海边的下午",
            message: "下次一起去",
            imageURL: URL(string: "https://example.com/postcard.jpg"),
            createdAt: Date(timeIntervalSince1970: 900)
        )
    )

    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    #expect(try decoder.decode(PetVisitInvitation.self, from: encoder.encode(invitation)) == invitation)
    #expect(try decoder.decode(PersonalTimelineEvent.self, from: encoder.encode(event)) == event)
}

@Test
func timelineEventDecodesBeforeOptionalPayloadFieldsExisted() throws {
    let data = Data(
        #"{"id":"event_legacy","kind":"visit_arrived","occurredAt":1000}"#.utf8
    )
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .millisecondsSince1970

    let event = try decoder.decode(PersonalTimelineEvent.self, from: data)

    #expect(event.id == "event_legacy")
    #expect(event.cargoItems.isEmpty)
    #expect(event.postcard == nil)
}

@Test
func strongIdentifiersEncodeAsStrings() throws {
    let accountID = AccountID(rawValue: "account_123")
    let coupleID = CoupleID(rawValue: "couple_456")

    #expect(String(data: try JSONEncoder().encode(accountID), encoding: .utf8) == "\"account_123\"")
    #expect(String(data: try JSONEncoder().encode(coupleID), encoding: .utf8) == "\"couple_456\"")
}

@Test
func petPresenceHasExactlyOneVisibleHost() throws {
    let owner = AccountID(rawValue: "account_owner")
    let partner = AccountID(rawValue: "account_partner")
    let petID = PetProfileID(rawValue: "pet_1")
    let visitID = PetVisitID(rawValue: "visit_1")
    let now = Date(timeIntervalSince1970: 1_000)

    let atHome = try PetPresenceRecord(
        petID: petID,
        ownerAccountID: owner,
        phase: .atHome,
        currentHostAccountID: owner,
        activeVisitID: nil,
        revision: 1,
        updatedAt: now
    )
    #expect(atHome.isVisible(on: owner))
    #expect(!atHome.isVisible(on: partner))

    let visiting = try PetPresenceRecord(
        petID: petID,
        ownerAccountID: owner,
        phase: .visiting,
        currentHostAccountID: partner,
        activeVisitID: visitID,
        revision: 2,
        updatedAt: now
    )
    #expect(!visiting.isVisible(on: owner))
    #expect(visiting.isVisible(on: partner))

    let returning = try PetPresenceRecord(
        petID: petID,
        ownerAccountID: owner,
        phase: .returning,
        currentHostAccountID: nil,
        activeVisitID: visitID,
        revision: 3,
        updatedAt: now
    )
    #expect(!returning.isVisible(on: owner))
    #expect(!returning.isVisible(on: partner))
}

@Test
func invalidPresenceCombinationsAreRejected() {
    let owner = AccountID(rawValue: "account_owner")

    #expect(throws: PetPresenceInvariantError.visitHostCannotBeOwner) {
        try PetPresenceRecord(
            petID: PetProfileID(rawValue: "pet_1"),
            ownerAccountID: owner,
            phase: .visiting,
            currentHostAccountID: owner,
            activeVisitID: PetVisitID(rawValue: "visit_1"),
            revision: 1,
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )
    }

    #expect(throws: PetPresenceInvariantError.transitCannotHaveCurrentHost) {
        try PetPresenceRecord(
            petID: PetProfileID(rawValue: "pet_1"),
            ownerAccountID: owner,
            phase: .outbound,
            currentHostAccountID: AccountID(rawValue: "account_partner"),
            activeVisitID: PetVisitID(rawValue: "visit_1"),
            revision: 1,
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )
    }
}

@Test
func visitCommandsKeepOutboundAndReturnCargoSeparate() throws {
    let outbound = PetCargoItem(
        itemID: PetItemID(rawValue: "item_flower"),
        kind: .gift,
        displayName: "小花"
    )
    let returnItem = PetCargoItem(
        itemID: PetItemID(rawValue: "item_letter"),
        kind: .letter,
        displayName: "回信"
    )
    let start = StartPetVisitCommand(
        petID: PetProfileID(rawValue: "pet_1"),
        destinationAccountID: AccountID(rawValue: "account_partner"),
        outboundCargo: [outbound],
        expectedPresenceRevision: 4,
        clientCreatedAt: Date(timeIntervalSince1970: 1_000)
    )
    let returning = ReturnPetVisitCommand(
        visitID: PetVisitID(rawValue: "visit_1"),
        returnCargo: [returnItem],
        expectedVisitRevision: 7,
        clientCreatedAt: Date(timeIntervalSince1970: 2_000)
    )

    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    #expect(try decoder.decode(StartPetVisitCommand.self, from: encoder.encode(start)) == start)
    #expect(try decoder.decode(ReturnPetVisitCommand.self, from: encoder.encode(returning)) == returning)
    #expect(start.outboundCargo == [outbound])
    #expect(returning.returnCargo == [returnItem])
}

@Test
func presenceSnapshotRejectsDuplicatePetLocations() throws {
    let owner = AccountID(rawValue: "account_owner")
    let petID = PetProfileID(rawValue: "pet_1")
    let now = Date(timeIntervalSince1970: 1_000)
    let first = try PetPresenceRecord(
        petID: petID,
        ownerAccountID: owner,
        phase: .atHome,
        currentHostAccountID: owner,
        activeVisitID: nil,
        revision: 1,
        updatedAt: now
    )
    let second = try PetPresenceRecord(
        petID: petID,
        ownerAccountID: owner,
        phase: .atHome,
        currentHostAccountID: owner,
        activeVisitID: nil,
        revision: 2,
        updatedAt: now
    )

    #expect(throws: PetPresenceSnapshotInvariantError.duplicatePet(petID)) {
        try PetPresenceSnapshot(
            coupleID: CoupleID(rawValue: "couple_1"),
            pets: [first, second],
            activeVisits: [],
            serverCursor: nil,
            syncedAt: now
        )
    }
}

@Test
func retryPolicyUsesBoundedExponentialBackoff() {
    let policy = OutboxRetryPolicy(baseDelay: 2, maximumDelay: 10)

    #expect(policy.delay(afterAttempt: 1) == 2)
    #expect(policy.delay(afterAttempt: 2) == 4)
    #expect(policy.delay(afterAttempt: 3) == 8)
    #expect(policy.delay(afterAttempt: 4) == 10)
    #expect(policy.delay(afterAttempt: 100) == 10)
}
