import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var world: PetWorld?
    private var petWindows: [PetID: PetWindowController] = [:]
    private let effectWindows = EffectWindowController()
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let visibleFrame = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let baseline = visibleFrame.minY + 105
        let initialPets = [
            PetRuntimeState(
                id: .mine,
                displayName: "奶糖",
                position: CGPoint(x: visibleFrame.midX - 95, y: baseline),
                facing: .right,
                activity: .idle,
                emotion: .content,
                avatar: .mine
            ),
            PetRuntimeState(
                id: .partner,
                displayName: "团子",
                position: CGPoint(x: visibleFrame.midX + 95, y: baseline),
                facing: .left,
                activity: .idle,
                emotion: .content,
                avatar: .partner
            )
        ]

        let world = PetWorld(pets: initialPets) { point in
            NSScreen.screens.first(where: { $0.frame.contains(point) })?.visibleFrame
                ?? NSScreen.main?.visibleFrame
                ?? visibleFrame
        }

        petWindows[.mine] = PetWindowController(
            id: .mine,
            onMoved: { [weak world] position in
                world?.movePet(.mine, to: position)
            },
            onClicked: { [weak world] in
                world?.triggerKiss()
            }
        )
        petWindows[.partner] = PetWindowController(
            id: .partner,
            onMoved: { [weak world] position in
                world?.movePet(.partner, to: position)
            },
            onClicked: { [weak world] in
                world?.triggerKiss()
            }
        )

        world.onStateChange = { [weak self] states in
            for (id, state) in states {
                self?.petWindows[id]?.render(state)
            }
        }
        world.onInteractionCue = { [weak self] cue in
            switch cue {
            case .kissHeart(let position):
                self?.effectWindows.showKissHeart(at: position)
            }
        }

        for controller in petWindows.values {
            controller.show()
        }
        self.world = world
        world.start()
        setupStatusItem()
    }

    func applicationWillTerminate(_ notification: Notification) {
        world?.stop()
    }

    private func setupStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.title = "♡"
        statusItem.button?.toolTip = "Mino PoC"

        let menu = NSMenu()
        let walkItem = NSMenuItem(title: "Debug: Walk", action: #selector(walkPets), keyEquivalent: "w")
        walkItem.target = self
        menu.addItem(walkItem)

        let avatarItem = NSMenuItem(
            title: "Debug: Change Partner Avatar",
            action: #selector(togglePartnerAppearance),
            keyEquivalent: "a"
        )
        avatarItem.target = self
        menu.addItem(avatarItem)

        let kissItem = NSMenuItem(title: "Debug: Kiss", action: #selector(kissPets), keyEquivalent: "k")
        kissItem.target = self
        menu.addItem(kissItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Mino PoC", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
        statusItem.menu = menu
        self.statusItem = statusItem
    }

    @objc
    private func walkPets() {
        world?.walkAll()
    }

    @objc
    private func togglePartnerAppearance() {
        world?.togglePartnerAppearance()
    }

    @objc
    private func kissPets() {
        world?.triggerKiss()
    }
}
