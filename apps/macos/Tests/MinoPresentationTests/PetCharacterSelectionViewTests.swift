import MinoDomain
import Testing
@testable import MinoPresentation

@Test
func characterSelectionRequiresAnIntentionalPermanentChoice() {
    let presentation = PetCharacterSelectionPresentation(
        state: .required(preselected: nil)
    )

    #expect(presentation.selectedCharacterID == nil)
    #expect(!presentation.locksChoice)
    #expect(!presentation.isWorking)
    #expect(presentation.status == nil)
    #expect(presentation.completionButtonTitle == nil)
}

@Test
func pendingCharacterSelectionTruthfullyReportsLocalFirstSync() throws {
    let presentation = PetCharacterSelectionPresentation(
        state: .pendingSync(.retrieverYellow)
    )

    #expect(presentation.selectedCharacterID == .retrieverYellow)
    #expect(presentation.locksChoice)
    #expect(!presentation.isWorking)
    #expect(presentation.completionButtonTitle == "完成")
    let status = try #require(presentation.status)
    #expect(status.title == "角色已在本机生效")
    #expect(status.detail.contains("网络恢复后会自动同步"))
}

@Test
func crossDeviceConflictNamesTheAuthoritativeCharacter() throws {
    let presentation = PetCharacterSelectionPresentation(
        state: .conflict(authoritative: .malteseWhite)
    )

    #expect(presentation.selectedCharacterID == .malteseWhite)
    #expect(presentation.locksChoice)
    #expect(presentation.completionButtonTitle == "知道了")
    let status = try #require(presentation.status)
    #expect(status.detail.contains("白色马尔济斯"))
}

@Test
func failedSyncKeepsTheLocallyChosenCharacterLockedForRetry() {
    let presentation = PetCharacterSelectionPresentation(
        state: .failed(preselected: .retrieverYellow, message: "网络暂时不可用")
    )

    #expect(presentation.selectedCharacterID == .retrieverYellow)
    #expect(presentation.locksChoice)
    #expect(presentation.completionButtonTitle == nil)
}

@MainActor
@Test
func sharedSpaceCharacterStateDefaultsDoNotPretendSelectionSucceeded() {
    let model = SharedSpaceModel()

    #expect(model.ownPetCharacterID == nil)
    #expect(model.friendCharacterIDs.isEmpty)
    #expect(model.petCharacterSelectionState == .hidden)
}

@Test
func invitationFallbackMatchesTheTwoDebugCharacters() {
    let friendPet = VisitInvitationPresentation(
        id: PetVisitID(rawValue: "friend"),
        friendName: "Alice",
        petName: "小黄",
        direction: .friendPetToMyDesktop
    )
    let ownPet = VisitInvitationPresentation(
        id: PetVisitID(rawValue: "own"),
        friendName: "Bob",
        petName: "小白",
        direction: .myPetToFriendDesktop
    )

    #expect(friendPet.characterID == .retrieverYellow)
    #expect(ownPet.characterID == .malteseWhite)
}
