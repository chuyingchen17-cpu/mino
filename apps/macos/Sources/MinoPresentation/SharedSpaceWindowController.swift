import AppKit
import MinoDomain
import SwiftUI

@MainActor
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

@MainActor
package final class SharedSpaceWindowController: NSWindowController, NSWindowDelegate {
    private let onVisibilityChange: (Bool) -> Void
    package let model = SharedSpaceModel()

    package init(
        debugIdentityLabel: String? = nil,
        identity: SharedSpaceIdentity = .localDefault,
        onFriendAction: @escaping (FriendDirectoryAction) -> Void,
        onProfileAction: @escaping (ProfileAction) -> Void,
        onOpenLetter: @escaping (LetterID) -> Void = { _ in },
        onVisibilityChange: @escaping (Bool) -> Void
    ) {
        self.onVisibilityChange = onVisibilityChange
        let rootView = SharedSpaceView(
            model: model,
            debugIdentityLabel: debugIdentityLabel,
            identity: identity,
            onFriendAction: onFriendAction,
            onProfileAction: onProfileAction,
            onOpenLetter: onOpenLetter
        )
        let hostingView = FirstMouseHostingView(rootView: rootView)
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 1_080, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.title = debugIdentityLabel.map { "Mino — \($0)" } ?? "Mino"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(Color.minoCanvas)
        window.minSize = CGSize(width: 900, height: 640)
        window.setContentSize(CGSize(width: 1_080, height: 760))
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
