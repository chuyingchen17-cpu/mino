import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var world: PetWorld?
    private var petWindows: [PetID: PetWindowController] = [:]
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let visibleFrame = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let baseline = visibleFrame.minY + 105
        let initialPets = [
            PetRuntimeState(
                id: .mine,
                position: CGPoint(x: visibleFrame.midX - 95, y: baseline),
                facing: .right,
                activity: .idle,
                avatar: .mine
            ),
            PetRuntimeState(
                id: .partner,
                position: CGPoint(x: visibleFrame.midX + 95, y: baseline),
                facing: .left,
                activity: .idle,
                avatar: .partner
            )
        ]

        let world = PetWorld(pets: initialPets) { point in
            NSScreen.screens.first(where: { $0.frame.contains(point) })?.visibleFrame
                ?? NSScreen.main?.visibleFrame
                ?? visibleFrame
        }

        petWindows[.mine] = PetWindowController(id: .mine) { [weak world] position in
            world?.movePet(.mine, to: position)
        }
        petWindows[.partner] = PetWindowController(id: .partner) { [weak world] position in
            world?.movePet(.partner, to: position)
        }

        world.onStateChange = { [weak self] states in
            for (id, state) in states {
                self?.petWindows[id]?.render(state)
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

        let kissItem = NSMenuItem(title: "Debug: Kiss (next step)", action: nil, keyEquivalent: "")
        kissItem.isEnabled = false
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
}
