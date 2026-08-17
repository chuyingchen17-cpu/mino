import AppKit
import MinoDomain
import SwiftUI

@MainActor
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

package enum SharedSpaceAction: Sendable {
    case kiss
    case flower
    case walk
}

package enum FriendDirectoryAction: Sendable {
    case refresh
    case addFriend(AccountID)
    case respondToRequest(FriendRequestID, FriendRequestDecision)
    case selectFriend(FriendshipID)
    case inviteFriend(FriendshipID)
    case endVisit
}

package struct SharedSpaceIdentity: Equatable, Sendable {
    package let localPetName: String
    package let fallbackFriendPetName: String

    package init(localPetName: String, fallbackFriendPetName: String) {
        self.localPetName = localPetName
        self.fallbackFriendPetName = fallbackFriendPetName
    }

    package static let demo = SharedSpaceIdentity(
        localPetName: "奶糖",
        fallbackFriendPetName: "好友宠物"
    )
}

package enum FriendVisitState: Equatable, Sendable {
    case away
    case sendingInvitation
    case invitationSent
    case consideringInvitation
    case visiting
    case ownPetVisiting
    case returning
}

@MainActor
package final class SharedSpaceModel: ObservableObject {
    @Published package var localAccountID: AccountID?
    @Published package var visitState: FriendVisitState = .away
    @Published package var timelineEvents: [PersonalTimelineEvent] = []
    @Published package var friends: [FriendProfile] = []
    @Published package var friendRequests: [FriendRequest] = []
    @Published package var selectedFriendshipID: FriendshipID?
    @Published package var activeVisitFriendshipID: FriendshipID?
    @Published package var friendOperationInProgress = false
    @Published package var friendErrorMessage: String?
    @Published package var visitErrorMessage: String?
    @Published package var agentMessage: String?
    @Published package var eventSyncStatusText = "离线演示"
}

@MainActor
package final class SharedSpaceWindowController: NSWindowController, NSWindowDelegate {
    private let onVisibilityChange: (Bool) -> Void
    package let model = SharedSpaceModel()

    package init(
        debugIdentityLabel: String? = nil,
        identity: SharedSpaceIdentity = .demo,
        onInteraction: @escaping (SharedSpaceAction) -> Void,
        onFriendAction: @escaping (FriendDirectoryAction) -> Void,
        onSendChatMessage: @escaping (String) -> Void = { _ in },
        onOpenLetter: @escaping (LetterID) -> Void = { _ in },
        onVisibilityChange: @escaping (Bool) -> Void
    ) {
        self.onVisibilityChange = onVisibilityChange
        let rootView = SharedSpaceView(
            model: model,
            debugIdentityLabel: debugIdentityLabel,
            identity: identity,
            onInteraction: onInteraction,
            onFriendAction: onFriendAction,
            onSendChatMessage: onSendChatMessage,
            onOpenLetter: onOpenLetter
        )
        let hostingView = FirstMouseHostingView(rootView: rootView)
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 1_260, height: 860),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.title = debugIdentityLabel.map { "Mino — \($0)" } ?? "Mino"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(calibratedRed: 1, green: 0.985, blue: 0.965, alpha: 1)
        window.minSize = CGSize(width: 980, height: 680)
        window.setContentSize(CGSize(width: 1_260, height: 860))
        window.isReleasedWhenClosed = false
        window.acceptsMouseMovedEvents = true
        window.collectionBehavior = [.fullScreenPrimary]

        super.init(window: window)
        window.delegate = self
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    package func show() {
        guard let window else { return }
        onVisibilityChange(true)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    package func windowWillClose(_ notification: Notification) {
        onVisibilityChange(false)
    }

    package func windowDidMiniaturize(_ notification: Notification) {
        onVisibilityChange(false)
    }

    package func windowDidDeminiaturize(_ notification: Notification) {
        onVisibilityChange(true)
    }
}
