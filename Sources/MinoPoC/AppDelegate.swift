import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let contentRect = NSRect(x: 0, y: 0, width: 320, height: 120)
        let window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Mino PoC"
        window.center()

        let label = NSTextField(labelWithString: "Mino runtime is ready")
        label.alignment = .center
        label.font = .systemFont(ofSize: 18, weight: .semibold)
        label.frame = contentRect
        window.contentView = label
        window.makeKeyAndOrderFront(nil)

        self.window = window
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

