import AppKit
import MinoDomain
import Testing

@testable import MinoPresentation

@Test
func invitationCopyDistinguishesBothVisitDirections() {
    let friendPet = invitation("visit-friend", direction: .friendPetToMyDesktop)
    let ownPet = invitation("visit-own", direction: .myPetToFriendDesktop)

    #expect(friendPet.message == "小文 想让 团子 来你的桌面")
    #expect(friendPet.direction.actionLabel == "来我家")
    #expect(ownPet.message == "小文 邀请你的 团子 去 TA 家")
    #expect(ownPet.direction.actionLabel == "去 TA 家")
}

@Test
func invitationWindowLayoutClampsToNegativeAndSmallVisibleFrames() {
    let frame = VisitInvitationWindowLayout.frame(
        in: CGRect(x: -1_600, y: 24, width: 1_200, height: 760)
    )
    #expect(frame.minX >= -1_584)
    #expect(frame.maxX <= -416)
    #expect(frame.minY >= 40)
    #expect(frame.maxY <= 768)

    let smallVisibleFrame = CGRect(x: 40, y: 50, width: 420, height: 180)
    let smallFrame = VisitInvitationWindowLayout.frame(in: smallVisibleFrame)
    #expect(smallVisibleFrame.contains(smallFrame))
}

@MainActor
@Test
func invitationQueueShowsProgressErrorAndAdvancesWithoutActivatingTheApp() {
    _ = NSApplication.shared
    let first = invitation("visit-1", direction: .friendPetToMyDesktop)
    let second = invitation("visit-2", direction: .myPetToFriendDesktop)
    var responses: [(PetVisitID, String)] = []
    let controller = VisitInvitationWindowController(
        visibleFrameProvider: { CGRect(x: 0, y: 0, width: 1_200, height: 800) },
        reduceMotionProvider: { true }
    ) { invitation, response in
        responses.append((invitation.id, response.rawValue))
    }

    controller.replaceQueue([first, first, second])

    #expect(controller.currentInvitation == first)
    #expect(controller.remainingInvitationCount == 1)
    #expect(controller.isBannerVisible)
    #expect(controller.window?.styleMask.contains(.nonactivatingPanel) == true)
    #expect(controller.window?.collectionBehavior.contains(.canJoinAllSpaces) == true)
    #expect(controller.window?.collectionBehavior.contains(.fullScreenAuxiliary) == true)

    controller.triggerResponseForTesting(.accept)
    #expect(controller.operationInProgress)
    #expect(responses.count == 1)
    #expect(responses.first?.0 == first.id)
    #expect(responses.first?.1 == VisitResponse.accept.rawValue)

    controller.failResponse(for: first.id, message: "网络暂时没有送达")
    #expect(!controller.operationInProgress)
    #expect(controller.responseErrorMessage == "网络暂时没有送达")

    controller.triggerResponseForTesting(.decline)
    #expect(responses.count == 2)
    controller.resolve(first.id)
    #expect(controller.currentInvitation == second)
    #expect(controller.remainingInvitationCount == 0)
    #expect(!controller.operationInProgress)
    #expect(controller.responseErrorMessage == nil)

    controller.resolve(second.id)
    #expect(controller.currentInvitation == nil)
    #expect(!controller.isBannerVisible)
}

private func invitation(
    _ id: String,
    direction: VisitPresentationDirection
) -> VisitInvitationPresentation {
    VisitInvitationPresentation(
        id: PetVisitID(rawValue: id),
        friendName: "小文",
        petName: "团子",
        direction: direction
    )
}
