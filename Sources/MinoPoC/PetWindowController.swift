import AppKit
import SpriteKit

@MainActor
final class PetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PetInteractionView: SKView {
    var onMoved: ((CGPoint) -> Void)?
    var onClicked: (() -> Void)?

    private var dragOffset = CGSize.zero
    private var didDrag = false

    override func mouseDown(with event: NSEvent) {
        didDrag = false
        guard let window else { return }
        let mouse = NSEvent.mouseLocation
        dragOffset = CGSize(
            width: mouse.x - window.frame.minX,
            height: mouse.y - window.frame.minY
        )
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        didDrag = true
        let mouse = NSEvent.mouseLocation
        let origin = CGPoint(
            x: mouse.x - dragOffset.width,
            y: mouse.y - dragOffset.height
        )
        window.setFrameOrigin(origin)
        onMoved?(CGPoint(x: window.frame.midX, y: window.frame.midY))
    }

    override func mouseUp(with event: NSEvent) {
        if didDrag, let window {
            onMoved?(CGPoint(x: window.frame.midX, y: window.frame.midY))
        } else {
            onClicked?()
        }
        didDrag = false
    }
}

@MainActor
final class PetWindowController {
    static let windowSize = CGSize(width: 150, height: 150)

    let id: PetID
    private let panel: PetPanel
    private let scene: PetScene

    init(id: PetID, onMoved: @escaping (CGPoint) -> Void) {
        self.id = id
        panel = PetPanel(
            contentRect: CGRect(origin: .zero, size: Self.windowSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        let view = PetInteractionView(frame: CGRect(origin: .zero, size: Self.windowSize))
        view.allowsTransparency = true
        view.preferredFramesPerSecond = 30
        scene = PetScene(size: Self.windowSize)
        view.presentScene(scene)
        view.onMoved = onMoved
        view.onClicked = { [weak scene] in scene?.reactToClick() }

        panel.contentView = view
        panel.title = id == .mine ? "Mino Pet: Mine" : "Mino Pet: Partner"
        panel.setAccessibilityLabel(panel.title)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
        panel.isReleasedWhenClosed = false
    }

    func show() {
        panel.orderFrontRegardless()
    }

    func render(_ state: PetRuntimeState) {
        let origin = CGPoint(
            x: state.position.x - Self.windowSize.width / 2,
            y: state.position.y - Self.windowSize.height / 2
        )
        if panel.frame.origin != origin {
            panel.setFrameOrigin(origin)
        }
        scene.render(state)
    }
}
