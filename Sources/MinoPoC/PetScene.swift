import AppKit
import SpriteKit

@MainActor
final class PetScene: SKScene {
    private let root = SKNode()
    private let body = SKShapeNode(circleOfRadius: 43)
    private let leftEye = SKShapeNode(circleOfRadius: 4)
    private let rightEye = SKShapeNode(circleOfRadius: 4)
    private var lastActivity: PetActivity?

    init(size: CGSize, tint: NSColor) {
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = .clear

        root.position = CGPoint(x: size.width / 2, y: size.height / 2 - 4)
        addChild(root)

        body.fillColor = tint
        body.strokeColor = tint.blended(withFraction: 0.25, of: .black) ?? .black
        body.lineWidth = 3
        root.addChild(body)

        for (eye, x) in [(leftEye, -15.0), (rightEye, 15.0)] {
            eye.fillColor = .black
            eye.strokeColor = .clear
            eye.position = CGPoint(x: x, y: 9)
            body.addChild(eye)
        }
    }

    required init?(coder aDecoder: NSCoder) {
        nil
    }

    func render(_ state: PetRuntimeState) {
        let facingScale: CGFloat = state.facing == .right ? 1 : -1
        body.xScale = facingScale

        guard lastActivity != state.activity else { return }
        lastActivity = state.activity
        root.removeAction(forKey: "activity")

        switch state.activity {
        case .idle:
            let breathe = SKAction.sequence([
                .scaleY(to: 1.035, duration: 0.9),
                .scaleY(to: 1, duration: 0.9)
            ])
            breathe.timingMode = .easeInEaseOut
            root.run(.repeatForever(breathe), withKey: "activity")
        case .walking:
            let hop = SKAction.sequence([
                .moveBy(x: 0, y: 5, duration: 0.16),
                .moveBy(x: 0, y: -5, duration: 0.16)
            ])
            root.run(.repeatForever(hop), withKey: "activity")
        case .interacting:
            root.run(.scale(to: 1.06, duration: 0.18), withKey: "activity")
        }
    }

    func reactToClick() {
        let pulse = SKAction.sequence([
            .scale(to: 1.12, duration: 0.1),
            .scale(to: 1, duration: 0.16)
        ])
        root.run(pulse, withKey: "click")
    }
}

