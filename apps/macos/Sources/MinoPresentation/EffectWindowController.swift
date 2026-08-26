import AppKit
import SpriteKit

@MainActor
package final class EffectWindowController {
    private var panels: [NSPanel] = []

    package init() {}

    package func showKissHeart(at position: CGPoint) {
        let size = CGSize(width: 130, height: 120)
        present(
            scene: KissEffectScene(size: size),
            size: size,
            at: position,
            title: "Mino Effect: Kiss"
        )
    }

    package func showFlowerGift(at position: CGPoint) {
        let size = CGSize(width: 180, height: 145)
        present(
            scene: FlowerEffectScene(size: size),
            size: size,
            at: position,
            title: "Mino Effect: Flower"
        )
    }

    private func present(
        scene: TimedEffectScene,
        size: CGSize,
        at position: CGPoint,
        title: String
    ) {
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

        scene.onFinished = { [weak self, weak panel] in
            guard let self, let panel else { return }
            panel.orderOut(nil)
            self.panels.removeAll { $0 === panel }
        }
        view.presentScene(scene)

        panel.title = title
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
private class TimedEffectScene: SKScene {
    var onFinished: (() -> Void)?

    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = .clear
    }

    required init?(coder aDecoder: NSCoder) {
        nil
    }
}

@MainActor
private final class KissEffectScene: TimedEffectScene {

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

@MainActor
private final class FlowerEffectScene: TimedEffectScene {
    override func didMove(to view: SKView) {
        let label = SKLabelNode(text: "送你一朵花")
        label.fontName = "PingFangSC-Semibold"
        label.fontSize = 17
        label.fontColor = .systemPink
        label.position = CGPoint(x: size.width / 2, y: 19)
        addChild(label)

        let flower = SKNode()
        flower.position = CGPoint(x: size.width / 2, y: 72)
        flower.setScale(0.15)
        flower.alpha = 0
        addChild(flower)

        let stemPath = CGMutablePath()
        stemPath.move(to: CGPoint(x: 0, y: -34))
        stemPath.addCurve(
            to: CGPoint(x: 0, y: -2),
            control1: CGPoint(x: -7, y: -22),
            control2: CGPoint(x: 5, y: -13)
        )
        let stem = SKShapeNode(path: stemPath)
        stem.strokeColor = .systemGreen
        stem.lineWidth = 4
        stem.lineCap = .round
        flower.addChild(stem)

        for angle in stride(from: 0.0, to: Double.pi * 2, by: Double.pi / 3) {
            let petal = SKShapeNode(ellipseOf: CGSize(width: 21, height: 30))
            petal.fillColor = .systemPink
            petal.strokeColor = .white
            petal.lineWidth = 1.5
            petal.position = CGPoint(x: cos(angle) * 13, y: 9 + sin(angle) * 13)
            petal.zRotation = CGFloat(angle) - .pi / 2
            flower.addChild(petal)
        }

        let center = SKShapeNode(circleOfRadius: 9)
        center.fillColor = .systemYellow
        center.strokeColor = .white
        center.lineWidth = 1.5
        center.position = CGPoint(x: 0, y: 9)
        center.zPosition = 2
        flower.addChild(center)

        let appear = SKAction.group([
            .fadeIn(withDuration: 0.15),
            .scale(to: 1, duration: 0.32),
            .rotate(byAngle: 0.16, duration: 0.32)
        ])
        appear.timingMode = .easeOut
        flower.run(.sequence([
            appear,
            .wait(forDuration: 1.05),
            .group([
                .moveBy(x: 0, y: 17, duration: 0.55),
                .fadeOut(withDuration: 0.55)
            ])
        ]))

        for index in 0..<4 {
            let sparkle = SKShapeNode(circleOfRadius: 3)
            sparkle.fillColor = index.isMultiple(of: 2) ? .systemYellow : .systemPink
            sparkle.strokeColor = .clear
            sparkle.position = CGPoint(
                x: size.width / 2 + (index.isMultiple(of: 2) ? -1 : 1) * CGFloat(36 + index * 4),
                y: 75 + CGFloat(index % 2) * 22
            )
            sparkle.alpha = 0
            addChild(sparkle)
            sparkle.run(.sequence([
                .wait(forDuration: 0.25 + Double(index) * 0.1),
                .fadeIn(withDuration: 0.12),
                .scale(to: 1.8, duration: 0.22),
                .fadeOut(withDuration: 0.35)
            ]))
        }

        label.run(.sequence([
            .fadeIn(withDuration: 0.18),
            .wait(forDuration: 1.25),
            .fadeOut(withDuration: 0.35)
        ]))
        run(.sequence([
            .wait(forDuration: 2),
            .run { [weak self] in self?.onFinished?() }
        ]))
    }
}
