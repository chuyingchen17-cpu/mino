import AppKit
import SpriteKit

@MainActor
final class EffectWindowController {
    private var panels: [NSPanel] = []

    func showKissHeart(at position: CGPoint) {
        let size = CGSize(width: 130, height: 120)
        let panel = NSPanel(
            contentRect: CGRect(
                x: position.x - size.width / 2,
                y: position.y - size.height / 2,
                width: size.width,
                height: size.height
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        let view = SKView(frame: CGRect(origin: .zero, size: size))
        view.allowsTransparency = true
        view.preferredFramesPerSecond = 30

        let scene = KissEffectScene(size: size)
        scene.onFinished = { [weak self, weak panel] in
            guard let self, let panel else { return }
            panel.orderOut(nil)
            self.panels.removeAll { $0 === panel }
        }
        view.presentScene(scene)

        panel.title = "Mino Effect: Kiss"
        panel.setAccessibilityLabel(panel.title)
        panel.contentView = view
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
        panel.isReleasedWhenClosed = false

        panels.append(panel)
        panel.orderFrontRegardless()
    }
}

@MainActor
private final class KissEffectScene: SKScene {
    var onFinished: (() -> Void)?

    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = .clear
    }

    required init?(coder aDecoder: NSCoder) {
        nil
    }

    override func didMove(to view: SKView) {
        let label = SKLabelNode(text: "啵~")
        label.fontName = "PingFangSC-Semibold"
        label.fontSize = 18
        label.fontColor = .systemPink
        label.position = CGPoint(x: size.width / 2, y: 22)
        addChild(label)

        for index in 0..<3 {
            let heart = makeHeart()
            heart.position = CGPoint(
                x: size.width / 2 + CGFloat(index - 1) * 24,
                y: 47 + CGFloat(abs(index - 1)) * 5
            )
            heart.setScale(0.15)
            heart.alpha = 0
            addChild(heart)

            let delay = SKAction.wait(forDuration: Double(index) * 0.12)
            let appear = SKAction.group([
                .fadeIn(withDuration: 0.12),
                .scale(to: 1, duration: 0.24)
            ])
            appear.timingMode = .easeOut
            let float = SKAction.group([
                .moveBy(x: 0, y: 30, duration: 0.9),
                .fadeOut(withDuration: 0.9)
            ])
            heart.run(.sequence([delay, appear, float, .removeFromParent()]))
        }

        label.run(.sequence([
            .fadeIn(withDuration: 0.15),
            .wait(forDuration: 0.85),
            .fadeOut(withDuration: 0.3)
        ]))

        run(.sequence([
            .wait(forDuration: 1.45),
            .run { [weak self] in self?.onFinished?() }
        ]))
    }

    private func makeHeart() -> SKShapeNode {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: -13))
        path.addCurve(
            to: CGPoint(x: 0, y: 8),
            control1: CGPoint(x: -22, y: -2),
            control2: CGPoint(x: -18, y: 17)
        )
        path.addCurve(
            to: CGPoint(x: 0, y: -13),
            control1: CGPoint(x: 18, y: 17),
            control2: CGPoint(x: 22, y: -2)
        )
        path.closeSubpath()

        let heart = SKShapeNode(path: path)
        heart.fillColor = .systemPink
        heart.strokeColor = .white
        heart.lineWidth = 2
        return heart
    }
}

