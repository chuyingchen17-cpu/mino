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
    case feed
    case play
    case requestVisit
    case viewMemory
    case leaveLetter
    case kiss
    case flower
    case walk
    case sendHome
    case resetPosition
    case rest
}

package struct PetActionDescriptor: Equatable, Sendable {
    package let action: PetContextAction
    package let title: String
    package let startsSection: Bool
}

private extension PetContextAction {
    static func descriptors(for petID: PetID, displayName: String) -> [PetActionDescriptor] {
        var descriptors = [
            PetActionDescriptor(action: .pet, title: "摸摸\(displayName)", startsSection: false),
            PetActionDescriptor(action: .feed, title: "投喂", startsSection: false),
            PetActionDescriptor(action: .play, title: "陪它玩", startsSection: false)
        ]
        if petID == .partner {
            descriptors.append(PetActionDescriptor(action: .kiss, title: "贴贴", startsSection: false))
            descriptors.append(PetActionDescriptor(action: .flower, title: "送花", startsSection: false))
        }
        descriptors.append(PetActionDescriptor(action: .walk, title: "一起散步", startsSection: false))
        if petID == .partner {
            descriptors.append(
                PetActionDescriptor(action: .leaveLetter, title: "托付一封文字信", startsSection: true)
            )
            descriptors.append(
                PetActionDescriptor(action: .sendHome, title: "让\(displayName)回家", startsSection: false)
            )
        } else {
            descriptors.append(
                PetActionDescriptor(action: .requestVisit, title: "请求去串门", startsSection: true)
            )
            descriptors.append(PetActionDescriptor(action: .viewMemory, title: "查看状态", startsSection: false))
            descriptors.append(PetActionDescriptor(action: .rest, title: "休息一下", startsSection: false))
            descriptors.append(PetActionDescriptor(action: .resetPosition, title: "重置位置", startsSection: false))
        }
        return descriptors
    }
}

@MainActor
private final class PetActionBarView: NSVisualEffectView {
    var onHoverChanged: ((Bool) -> Void)?

    private var hoverTrackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        hoverTrackingArea = trackingArea
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChanged?(false)
    }
}

@MainActor
final class PetInteractionView: SKView {
    var onMoved: ((CGPoint) -> Void)?
    var onClicked: (() -> Void)?
    var onHoverChanged: ((Bool) -> Void)?
    var onContextAction: ((PetContextAction) -> Void)?
    var onContextMenuPresentationChanged: ((Bool) -> Void)?

    private let petID: PetID
    private var displayName: String
    private var dragOffset = CGSize.zero
    private var didDrag = false
    private var isHovering = false
    private var petTrackingArea: NSTrackingArea?

    var displayNameForMenu: String { displayName }

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
        let rawOrigin = CGPoint(
            x: mouse.x - dragOffset.width,
            y: mouse.y - dragOffset.height
        )
        let destinationScreen = NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? window.screen
            ?? NSScreen.main
        let origin = PetWindowController.quantizedPoint(
            rawOrigin,
            backingScaleFactor: destinationScreen?.backingScaleFactor ?? 1
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
        presentContextMenu {
            NSMenu.popUpContextMenu(menu ?? makeContextMenu(), with: event, for: self)
        }
    }

    func showContextMenu(positionedAt point: CGPoint, in anchorView: NSView) {
        presentContextMenu {
            (menu ?? makeContextMenu()).popUp(positioning: nil, at: point, in: anchorView)
        }
    }

    func updateDisplayName(_ name: String) {
        displayName = name
        menu = makeContextMenu()
    }

    private func setHovering(_ hovering: Bool) {
        guard isHovering != hovering else { return }
        isHovering = hovering
        onHoverChanged?(hovering)
    }

    private func presentContextMenu(_ presentation: () -> Void) {
        onContextMenuPresentationChanged?(true)
        defer { onContextMenuPresentationChanged?(false) }
        presentation()
    }

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu(title: displayName)
        for descriptor in PetContextAction.descriptors(for: petID, displayName: displayName) {
            if descriptor.startsSection {
                menu.addItem(.separator())
            }
            addMenuItem(to: menu, title: descriptor.title, action: descriptor.action)
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
    private let interactionView: PetInteractionView
    private var actionPanel: PetPanel?
    private var speechPanel: PetPanel?
    private var actionBarShowTask: Task<Void, Never>?
    private var actionBarHideTask: Task<Void, Never>?
    private var speechTask: Task<Void, Never>?
    private var isPetHovered = false
    private var isActionBarHovered = false
    private var isContextMenuPresented = false
    private var usesSyntheticHoverState = false
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

        interactionView = PetInteractionView(
            frame: CGRect(origin: .zero, size: Self.windowSize),
            petID: id,
            displayName: displayName ?? (id == .mine ? "奶糖" : "团子")
        )
        let view = interactionView
        view.allowsTransparency = true
        view.preferredFramesPerSecond = 60
        scene = PetScene(size: Self.windowSize)
        view.presentScene(scene)
        view.onMoved = onMoved
        view.onClicked = { [weak scene] in
            scene?.reactToClick()
            onClicked?()
        }
        view.onHoverChanged = { [weak self] hovering in
            onHoverChanged?(hovering)
            self?.handleNativePetHoverChanged(hovering)
        }
        view.onContextAction = { [weak scene] action in
            if action == .pet {
                scene?.reactToClick()
            }
            onContextAction?(action)
        }
        view.onContextMenuPresentationChanged = { [weak self] isPresented in
            self?.handleContextMenuPresentationChanged(isPresented)
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
        configureActionPanel()
        configureSpeechPanel()
    }

    package func show() {
        if !panel.isVisible {
            panel.orderFrontRegardless()
            placeBelowCoveringWindowIfNeeded()
        }
    }

    package func updateDisplayName(_ name: String) {
        interactionView.updateDisplayName(name)
    }

    package func hide() {
        actionBarShowTask?.cancel()
        actionBarHideTask?.cancel()
        isPetHovered = false
        isActionBarHovered = false
        isContextMenuPresented = false
        usesSyntheticHoverState = false
        if panel.isVisible {
            panel.orderOut(nil)
        }
        actionPanel?.orderOut(nil)
        speechPanel?.orderOut(nil)
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
        let destinationScreen = NSScreen.screens.first { $0.frame.contains(state.position) }
            ?? panel.screen
            ?? NSScreen.main
        let origin = Self.quantizedOrigin(
            forCenter: state.position,
            windowSize: Self.windowSize,
            backingScaleFactor: destinationScreen?.backingScaleFactor ?? 1
        )
        if panel.frame.origin != origin {
            panel.setFrameOrigin(origin)
            positionAccessoryPanels()
        }
        scene.render(state)
    }

    package func showSpeech(
        _ text: String,
        duration: TimeInterval = MinoDesign.Motion.petFeedbackDuration
    ) {
        guard let speechPanel,
              let label = speechPanel.contentView?.viewWithTag(200) as? NSTextField else { return }
        speechTask?.cancel()
        label.stringValue = text
        positionAccessoryPanels()
        speechPanel.orderFrontRegardless()
        speechTask = Task { @MainActor [weak speechPanel] in
            do {
                try await Task.sleep(for: .seconds(duration))
            } catch {
                return
            }
            speechPanel?.orderOut(nil)
        }
    }

    private func handlePetHoverChanged(_ hovering: Bool) {
        isPetHovered = hovering
        if hovering {
            scheduleActionBarPresentation()
        } else {
            scheduleActionBarDismissalIfNeeded()
        }
    }

    private func handleNativePetHoverChanged(_ hovering: Bool) {
        guard !usesSyntheticHoverState else { return }
        handlePetHoverChanged(hovering)
    }

    private func handleActionBarHoverChanged(_ hovering: Bool) {
        isActionBarHovered = hovering
        if hovering {
            actionBarHideTask?.cancel()
        } else {
            scheduleActionBarDismissalIfNeeded()
        }
    }

    private func handleNativeActionBarHoverChanged(_ hovering: Bool) {
        guard !usesSyntheticHoverState else { return }
        handleActionBarHoverChanged(hovering)
    }

    private func handleContextMenuPresentationChanged(_ isPresented: Bool) {
        isContextMenuPresented = isPresented
        if isPresented {
            actionBarHideTask?.cancel()
        } else {
            refreshHoverStateFromPointer()
            scheduleActionBarDismissalIfNeeded()
        }
    }

    private func scheduleActionBarPresentation() {
        actionBarHideTask?.cancel()
        guard actionPanel?.isVisible != true else { return }
        actionBarShowTask?.cancel()
        actionBarShowTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(MinoDesign.Motion.petHoverDelay))
            } catch {
                return
            }
            guard let self, isPetHovered, panel.isVisible else { return }
            positionAccessoryPanels()
            actionPanel?.orderFrontRegardless()
        }
    }

    private func scheduleActionBarDismissalIfNeeded() {
        guard !isPetHovered, !isActionBarHovered, !isContextMenuPresented else {
            actionBarHideTask?.cancel()
            return
        }
        actionBarShowTask?.cancel()
        guard actionPanel?.isVisible == true else { return }
        actionBarHideTask?.cancel()
        actionBarHideTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(180))
            } catch {
                return
            }
            guard let self else { return }
            // AppKit tracking callbacks and the delayed task both arrive on the
            // main actor. Re-read the pointer before hiding so a busy run loop
            // cannot process the timeout ahead of an already-completed move.
            if !usesSyntheticHoverState {
                refreshHoverStateFromPointer()
            }
            guard !isPetHovered, !isActionBarHovered, !isContextMenuPresented else { return }
            actionPanel?.orderOut(nil)
        }
    }

    private func refreshHoverStateFromPointer() {
        let pointer = NSEvent.mouseLocation
        isPetHovered = panel.isVisible && panel.frame.contains(pointer)
        isActionBarHovered = actionPanel?.isVisible == true && actionPanel?.frame.contains(pointer) == true
    }

    private func configureActionPanel() {
        let accessory = PetPanel(
            contentRect: CGRect(origin: .zero, size: MinoDesign.Size.petActionBar),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        accessory.isOpaque = false
        accessory.backgroundColor = .clear
        accessory.hasShadow = true
        accessory.level = .floating
        accessory.collectionBehavior = panel.collectionBehavior

        let material = PetActionBarView(frame: accessory.contentView?.bounds ?? .zero)
        material.material = .popover
        material.state = .active
        material.wantsLayer = true
        material.layer?.cornerRadius = MinoDesign.Radius.petAccessory
        material.layer?.masksToBounds = true
        material.autoresizingMask = [.width, .height]
        material.setAccessibilityLabel("宠物操作")
        material.onHoverChanged = { [weak self] hovering in
            self?.handleNativeActionBarHoverChanged(hovering)
        }

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 3
        stack.alignment = .centerY
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        let actions: [(String, PetContextAction?)] = [
            ("投喂", .feed), ("陪玩", .play), ("散步", .walk), ("更多", nil)
        ]
        for (title, action) in actions {
            let button = NSButton(title: title, target: self, action: #selector(performQuickAction(_:)))
            button.isBordered = false
            button.font = .systemFont(ofSize: 12, weight: .semibold)
            button.tag = action?.rawValue ?? -1
            button.setAccessibilityLabel(action == nil ? "更多宠物操作" : title)
            stack.addArrangedSubview(button)
        }
        material.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: material.leadingAnchor, constant: 7),
            stack.trailingAnchor.constraint(equalTo: material.trailingAnchor, constant: -7),
            stack.topAnchor.constraint(equalTo: material.topAnchor, constant: 5),
            stack.bottomAnchor.constraint(equalTo: material.bottomAnchor, constant: -5)
        ])
        accessory.contentView = material
        actionPanel = accessory
    }

    private func configureSpeechPanel() {
        let accessory = PetPanel(
            contentRect: CGRect(origin: .zero, size: MinoDesign.Size.petSpeechBubble),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        accessory.isOpaque = false
        accessory.backgroundColor = .clear
        accessory.hasShadow = true
        accessory.level = .floating
        accessory.collectionBehavior = panel.collectionBehavior
        accessory.ignoresMouseEvents = true

        let bubble = NSVisualEffectView(frame: accessory.contentView?.bounds ?? .zero)
        bubble.material = .popover
        bubble.state = .active
        bubble.wantsLayer = true
        bubble.layer?.cornerRadius = MinoDesign.Radius.speechBubble
        bubble.layer?.masksToBounds = true
        bubble.autoresizingMask = [.width, .height]
        let label = NSTextField(labelWithString: "")
        label.tag = 200
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor
        label.alignment = .center
        label.maximumNumberOfLines = 2
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        bubble.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 14),
            label.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -14),
            label.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 9),
            label.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -9)
        ])
        accessory.contentView = bubble
        speechPanel = accessory
    }

    private func positionAccessoryPanels() {
        guard let screen = panel.screen ?? NSScreen.main else { return }
        let scale = screen.backingScaleFactor
        let actionSize = actionPanel?.frame.size ?? .zero
        let speechSize = speechPanel?.frame.size ?? .zero
        let actionX = min(
            max(panel.frame.midX - actionSize.width / 2, screen.visibleFrame.minX + 8),
            screen.visibleFrame.maxX - actionSize.width - 8
        )
        let actionY = min(panel.frame.maxY - 8, screen.visibleFrame.maxY - actionSize.height - 8)
        actionPanel?.setFrameOrigin(Self.quantizedPoint(
            CGPoint(x: actionX, y: actionY),
            backingScaleFactor: scale
        ))
        let speechX = min(
            max(panel.frame.midX - speechSize.width / 2, screen.visibleFrame.minX + 8),
            screen.visibleFrame.maxX - speechSize.width - 8
        )
        let speechY = min(actionY + actionSize.height + 6, screen.visibleFrame.maxY - speechSize.height - 8)
        speechPanel?.setFrameOrigin(Self.quantizedPoint(
            CGPoint(x: speechX, y: speechY),
            backingScaleFactor: scale
        ))
    }

    package static func quantizedOrigin(
        forCenter center: CGPoint,
        windowSize: CGSize = PetWindowController.windowSize,
        backingScaleFactor: CGFloat
    ) -> CGPoint {
        quantizedPoint(
            CGPoint(
                x: center.x - windowSize.width / 2,
                y: center.y - windowSize.height / 2
            ),
            backingScaleFactor: backingScaleFactor
        )
    }

    package static func quantizedPoint(
        _ point: CGPoint,
        backingScaleFactor: CGFloat
    ) -> CGPoint {
        let scale = max(backingScaleFactor, 1)
        return CGPoint(
            x: (point.x * scale).rounded() / scale,
            y: (point.y * scale).rounded() / scale
        )
    }

    @objc
    private func performQuickAction(_ sender: NSButton) {
        if sender.tag == -1 {
            interactionView.showContextMenu(
                positionedAt: CGPoint(x: sender.bounds.minX, y: sender.bounds.maxY + 4),
                in: sender
            )
        } else if let action = PetContextAction(rawValue: sender.tag) {
            interactionView.onContextAction?(action)
        }
    }

    // Package-visible probes keep interaction tests focused on behavior without
    // exposing AppKit window internals as production API.
    package var quickActionLabels: [String] { ["投喂", "陪玩", "散步", "更多"] }
    package var menuActionDescriptors: [PetActionDescriptor] {
        PetContextAction.descriptors(for: id, displayName: interactionView.displayNameForMenu)
    }
    package var isActionBarVisible: Bool { actionPanel?.isVisible == true }
    package var isSpeechVisible: Bool { speechPanel?.isVisible == true }
    package var renderedClipForTesting: PetMotionClipID? { scene.renderedClipForTesting }
    package var motionStartCountForTesting: Int { scene.motionStartCountForTesting }

    package func triggerClickForTesting() {
        interactionView.onClicked?()
    }

    package func triggerQuickActionForTesting(_ action: PetContextAction) {
        interactionView.onContextAction?(action)
    }

    package func triggerContextActionForTesting(_ action: PetContextAction) {
        interactionView.onContextAction?(action)
    }

    package func performExternalMenuAction(_ action: PetContextAction) {
        interactionView.onContextAction?(action)
    }

    package func setPetHoveredForTesting(_ hovering: Bool) {
        usesSyntheticHoverState = true
        handlePetHoverChanged(hovering)
    }

    package func setActionBarHoveredForTesting(_ hovering: Bool) {
        usesSyntheticHoverState = true
        handleActionBarHoverChanged(hovering)
    }

    package func setContextMenuPresentedForTesting(_ isPresented: Bool) {
        usesSyntheticHoverState = true
        isContextMenuPresented = isPresented
        if isPresented {
            actionBarHideTask?.cancel()
        } else {
            scheduleActionBarDismissalIfNeeded()
        }
    }

    package func waitForActionBarPresentationForTesting() async {
        guard let actionBarShowTask else { return }
        await actionBarShowTask.value
    }

    package func waitForActionBarDismissalForTesting() async {
        guard let actionBarHideTask else { return }
        await actionBarHideTask.value
    }

    package func waitForSpeechDismissalForTesting() async {
        guard let speechTask else { return }
        await speechTask.value
    }
}
