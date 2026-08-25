import AppKit
import MinoDomain
import Testing
@testable import MinoPresentation

@MainActor
@Test func quickBarAndContextMenuShareTheSameActionBoundary() {
    var actions: [PetContextAction] = []
    let controller = PetWindowController(
        id: .mine,
        displayName: "奶糖",
        onMoved: { _ in },
        onContextAction: { actions.append($0) }
    )

    #expect(controller.quickActionLabels == ["投喂", "陪玩", "散步", "更多"])
    controller.triggerQuickActionForTesting(.feed)
    controller.triggerContextActionForTesting(.feed)
    controller.performExternalMenuAction(.feed)
    #expect(actions == [.feed, .feed, .feed])

    #expect(controller.menuActionDescriptors.map(\.title) == [
        "摸摸奶糖", "投喂", "陪它玩", "一起散步",
        "请求去串门", "查看状态", "休息一下", "重置位置"
    ])
}

@MainActor
@Test func singleClickImmediatelyPlaysPetReceiveAndRoutesEveryTap() {
    var clickCount = 0
    let controller = PetWindowController(
        id: .mine,
        displayName: "奶糖",
        onMoved: { _ in },
        onClicked: { clickCount += 1 }
    )
    controller.render(
        PetRuntimeState(
            id: .mine,
            displayName: "奶糖",
            position: CGPoint(x: 200, y: 160),
            facing: .right,
            activity: .idle,
            emotion: .content,
            avatar: .mine,
            characterID: .malteseWhite
        )
    )
    let initialStarts = controller.motionStartCountForTesting

    controller.triggerClickForTesting()
    controller.triggerClickForTesting()

    #expect(clickCount == 2)
    #expect(controller.renderedClipForTesting == .petReceive)
    #expect(controller.motionStartCountForTesting == initialStarts + 2)
}

@MainActor
@Test func speechBubbleAppearsImmediatelyAndHasABoundedLifetime() async throws {
    let controller = PetWindowController(
        id: .mine,
        displayName: "奶糖",
        onMoved: { _ in }
    )

    controller.showSpeech("摸摸收到啦。", duration: 0.08)
    #expect(controller.isSpeechVisible)
    await controller.waitForSpeechDismissalForTesting()
    #expect(!controller.isSpeechVisible)
}

@MainActor
@Test func actionBarStaysVisibleWhilePointerMovesFromPetIntoBar() async throws {
    let controller = PetWindowController(
        id: .mine,
        displayName: "奶糖",
        onMoved: { _ in }
    )
    controller.show()
    defer { controller.hide() }

    controller.setPetHoveredForTesting(true)
    await controller.waitForActionBarPresentationForTesting()
    #expect(controller.isActionBarVisible)

    controller.setPetHoveredForTesting(false)
    controller.setActionBarHoveredForTesting(true)
    await controller.waitForActionBarDismissalForTesting()
    #expect(controller.isActionBarVisible)

    controller.setActionBarHoveredForTesting(false)
    await controller.waitForActionBarDismissalForTesting()
    #expect(!controller.isActionBarVisible)
}

@MainActor
@Test func openMoreMenuPreventsHoverDismissal() async throws {
    let controller = PetWindowController(
        id: .mine,
        displayName: "奶糖",
        onMoved: { _ in }
    )
    controller.show()
    defer { controller.hide() }

    controller.setPetHoveredForTesting(true)
    await controller.waitForActionBarPresentationForTesting()
    #expect(controller.isActionBarVisible)

    controller.setContextMenuPresentedForTesting(true)
    controller.setPetHoveredForTesting(false)
    #expect(controller.isActionBarVisible)

    controller.setContextMenuPresentedForTesting(false)
    await controller.waitForActionBarDismissalForTesting()
    #expect(!controller.isActionBarVisible)
}

@MainActor
@Test func petWindowOriginIsQuantizedToPhysicalPixelsAtOneAndTwoX() {
    let center = CGPoint(x: 423.333, y: 108.247)
    let oneX = PetWindowController.quantizedOrigin(
        forCenter: center,
        backingScaleFactor: 1
    )
    let twoX = PetWindowController.quantizedOrigin(
        forCenter: center,
        backingScaleFactor: 2
    )

    #expect(oneX.x.rounded() == oneX.x)
    #expect(oneX.y.rounded() == oneX.y)
    #expect((twoX.x * 2).rounded() == twoX.x * 2)
    #expect((twoX.y * 2).rounded() == twoX.y * 2)
}

@MainActor
@Test func repeatedQuantizationDoesNotIntroduceVerticalDrift() {
    let centers = (0..<120).map { frame in
        CGPoint(x: 100 + Double(frame) * 0.37, y: 105)
    }
    let yValues = centers.map {
        PetWindowController.quantizedOrigin(
            forCenter: $0,
            backingScaleFactor: 2
        ).y
    }
    #expect(Set(yValues).count == 1)
}
