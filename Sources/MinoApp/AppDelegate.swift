import AppKit
import MinoDomain
import MinoPresentation
import MinoRuntime

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var world: PetWorld?
    private var petWindows: [PetID: PetWindowController] = [:]
    private let effectWindows = EffectWindowController()
    private let demoSequence = DemoSequenceController()
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
            onMoved: { [weak self, weak world] position in
                self?.demoSequence.stop()
                world?.movePet(.mine, to: position)
            },
            onClicked: { [weak self, weak world] in
                self?.demoSequence.stop()
                world?.triggerKiss()
            }
        )
        petWindows[.partner] = PetWindowController(
            id: .partner,
            onMoved: { [weak self, weak world] position in
                self?.demoSequence.stop()
                world?.movePet(.partner, to: position)
            },
            onClicked: { [weak self, weak world] in
                self?.demoSequence.stop()
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
            case .flowerGift(let position):
                self?.effectWindows.showFlowerGift(at: position)
            }
        }

        for controller in petWindows.values {
            controller.show()
        }
        self.world = world
        world.start()
        setupStatusItem()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenConfigurationChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        demoSequence.stop()
        world?.stop()
        NotificationCenter.default.removeObserver(self)
    }

    private func setupStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.title = "♡"
        statusItem.button?.toolTip = "Mino 情侣桌宠 Demo"

        let menu = NSMenu()
        let identityItem = NSMenuItem(title: "奶糖  ♡  团子", action: nil, keyEquivalent: "")
        identityItem.isEnabled = false
        menu.addItem(identityItem)

        let demoItem = NSMenuItem(title: "播放完整 Demo", action: #selector(playDemo), keyEquivalent: "d")
        demoItem.target = self
        menu.addItem(demoItem)
        menu.addItem(.separator())

        let kissItem = NSMenuItem(title: "亲亲", action: #selector(kissPets), keyEquivalent: "k")
        kissItem.target = self
        menu.addItem(kissItem)

        let flowerItem = NSMenuItem(title: "送花", action: #selector(giveFlower), keyEquivalent: "f")
        flowerItem.target = self
        menu.addItem(flowerItem)

        let walkItem = NSMenuItem(title: "一起散步", action: #selector(walkPets), keyEquivalent: "w")
        walkItem.target = self
        menu.addItem(walkItem)

        let avatarItem = NSMenuItem(
            title: "给 TA 换装",
            action: #selector(togglePartnerAppearance),
            keyEquivalent: "a"
        )
        avatarItem.target = self
        menu.addItem(avatarItem)

        let resetItem = NSMenuItem(title: "重置位置", action: #selector(resetDemo), keyEquivalent: "r")
        resetItem.target = self
        menu.addItem(resetItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出 Mino", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
        statusItem.menu = menu
        self.statusItem = statusItem
    }

    @objc
    private func playDemo() {
        guard let world else { return }
        demoSequence.play(in: world)
    }

    @objc
    private func walkPets() {
        demoSequence.stop()
        world?.walkAll()
    }

    @objc
    private func togglePartnerAppearance() {
        demoSequence.stop()
        world?.togglePartnerAppearance()
    }

    @objc
    private func kissPets() {
        demoSequence.stop()
        world?.triggerKiss()
    }

    @objc
    private func giveFlower() {
        demoSequence.stop()
        world?.triggerFlowerGift()
    }

    @objc
    private func resetDemo() {
        demoSequence.stop()
        world?.resetForDemo()
    }

    @objc
    private func screenConfigurationChanged() {
        demoSequence.stop()
        world?.restorePetsToVisibleScreens()
    }
}
