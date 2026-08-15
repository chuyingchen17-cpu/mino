import AppKit
import SpriteKit

@MainActor
final class PetScene: SKScene {
    private let root = SKNode()
    private let avatar = PetAvatarNode()
    private var lastActivity: PetActivity?

    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = .clear

        root.position = CGPoint(x: size.width / 2, y: size.height / 2 - 4)
        addChild(root)
        root.addChild(avatar)
    }

    required init?(coder aDecoder: NSCoder) {
        nil
    }

    func render(_ state: PetRuntimeState) {
        avatar.apply(state.avatar)
        avatar.setFacing(state.facing)

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
