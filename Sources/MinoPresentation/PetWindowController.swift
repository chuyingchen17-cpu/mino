import AppKit
import MinoDomain
import SpriteKit

@MainActor
final class PetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

package enum PetContextAction: Int, Sendable {
    case pet
    case speak
    case feed
    case play
    case requestVisit
    case viewMemory
    case leaveLetter
    case kiss
    case flower
    case walk
    case changeAppearance
    case sendHome
    case resetPosition
}

@MainActor
final class PetInteractionView: SKView {
    var onMoved: ((CGPoint) -> Void)?
    var onClicked: (() -> Void)?
    var onHoverChanged: ((Bool) -> Void)?
    var onContextAction: ((PetContextAction) -> Void)?

    private let petID: PetID
    private let displayName: String
    private var dragOffset = CGSize.zero
    private var didDrag = false
    private var isHovering = false
    private var petTrackingArea: NSTrackingArea?

    init(frame: CGRect, petID: PetID, displayName: String) {
        self.petID = petID
        self.displayName = displayName
        super.init(frame: frame)
        menu = makeContextMenu()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        if let petTrackingArea {
            removeTrackingArea(petTrackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        petTrackingArea = trackingArea
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        setHovering(true)
    }

    override func mouseExited(with event: NSEvent) {
        setHovering(false)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

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

    override func rightMouseDown(with event: NSEvent) {
        showContextMenu(for: event)
    }

    func showContextMenu(for event: NSEvent) {
        setHovering(true)
        NSMenu.popUpContextMenu(menu ?? makeContextMenu(), with: event, for: self)
    }

    private func setHovering(_ hovering: Bool) {
        guard isHovering != hovering else { return }
        isHovering = hovering
        onHoverChanged?(hovering)
    }

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu(title: displayName)
        addMenuItem(to: menu, title: "摸摸\(displayName)", action: .pet)
        addMenuItem(to: menu, title: "和\(displayName)说话", action: .speak)
        addMenuItem(to: menu, title: "投喂", action: .feed)
        addMenuItem(to: menu, title: "陪它玩", action: .play)

        if petID == .partner {
            addMenuItem(to: menu, title: "亲亲", action: .kiss)
            addMenuItem(to: menu, title: "送花", action: .flower)
        }

        addMenuItem(to: menu, title: "一起散步", action: .walk)
        menu.addItem(.separator())

        if petID == .partner {
            addMenuItem(to: menu, title: "托付一封文字信", action: .leaveLetter)
            addMenuItem(to: menu, title: "换个造型", action: .changeAppearance)
            addMenuItem(to: menu, title: "让\(displayName)回家", action: .sendHome)
        } else {
            addMenuItem(to: menu, title: "请求去串门", action: .requestVisit)
            addMenuItem(to: menu, title: "查看记忆", action: .viewMemory)
            addMenuItem(to: menu, title: "重置位置", action: .resetPosition)
        }
        return menu
    }

    private func addMenuItem(to menu: NSMenu, title: String, action: PetContextAction) {
        let item = NSMenuItem(
            title: title,
            action: #selector(performContextAction(_:)),
            keyEquivalent: ""
        )
        item.target = self
        item.tag = action.rawValue
        menu.addItem(item)
    }

    @objc
    private func performContextAction(_ sender: NSMenuItem) {
        guard let action = PetContextAction(rawValue: sender.tag) else { return }
        onContextAction?(action)
    }
}

@MainActor
package final class PetWindowController {
    package static let windowSize = CGSize(width: 170, height: 180)

    package let id: PetID
    private let panel: PetPanel
    private let scene: PetScene
    private weak var coveringWindow: NSWindow?
    private var rightClickMonitor: Any?

    package init(
        id: PetID,
        displayName: String? = nil,
        onMoved: @escaping (CGPoint) -> Void,
        onClicked: (() -> Void)? = nil,
        onHoverChanged: ((Bool) -> Void)? = nil,
        onContextAction: ((PetContextAction) -> Void)? = nil
    ) {
        self.id = id
        panel = PetPanel(
            contentRect: CGRect(origin: .zero, size: Self.windowSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        let view = PetInteractionView(
            frame: CGRect(origin: .zero, size: Self.windowSize),
            petID: id,
            displayName: displayName ?? (id == .mine ? "奶糖" : "团子")
        )
        view.allowsTransparency = true
        view.preferredFramesPerSecond = 30
        scene = PetScene(size: Self.windowSize)
        view.presentScene(scene)
        view.onMoved = onMoved
        view.onClicked = { [weak scene] in
            scene?.reactToClick()
            onClicked?()
        }
        view.onHoverChanged = onHoverChanged
        view.onContextAction = { [weak scene] action in
            if action == .pet {
                scene?.reactToClick()
            }
            onContextAction?(action)
        }

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

        rightClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) {
            [weak panel, weak view] event in
            guard
                let panel,
                let view,
                panel.isVisible,
                event.window === panel
            else {
                return event
            }
            view.showContextMenu(for: event)
            return nil
        }
    }

    package func show() {
        if !panel.isVisible {
            panel.orderFrontRegardless()
            placeBelowCoveringWindowIfNeeded()
        }
    }

    package func hide() {
        if panel.isVisible {
            panel.orderOut(nil)
        }
    }

    package func setCovered(by window: NSWindow?) {
        coveringWindow = window
        if let window {
            panel.level = .normal
            if panel.isVisible {
                window.order(.above, relativeTo: panel.windowNumber)
            }
        } else {
            panel.level = .floating
            if panel.isVisible {
                panel.orderFrontRegardless()
            }
        }
    }

    private func placeBelowCoveringWindowIfNeeded() {
        guard let coveringWindow else { return }
        panel.level = .normal
        coveringWindow.order(.above, relativeTo: panel.windowNumber)
    }

    package func render(_ state: PetRuntimeState) {
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
