import AppKit
import MinoDomain
import SpriteKit

@MainActor
final class PetScene: SKScene {
    private let root = SKNode()
    private let avatar = PetAvatarNode()
    private let shadow = SKShapeNode(ellipseOf: CGSize(width: 74, height: 15))
    private let nameBadge = SKShapeNode(rectOf: CGSize(width: 78, height: 25), cornerRadius: 12.5)
    private let nameLabel = SKLabelNode()
    private var lastActivity: PetActivity?

    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = .clear

        shadow.fillColor = NSColor.black.withAlphaComponent(0.16)
        shadow.strokeColor = .clear
        shadow.position = CGPoint(x: size.width / 2, y: 49)
        shadow.zPosition = -10
        addChild(shadow)

        nameBadge.fillColor = NSColor.windowBackgroundColor.withAlphaComponent(0.88)
        nameBadge.strokeColor = NSColor.white.withAlphaComponent(0.85)
        nameBadge.lineWidth = 1.5
        nameBadge.position = CGPoint(x: size.width / 2, y: 18)
        nameBadge.zPosition = 100
        addChild(nameBadge)

        nameLabel.fontName = "PingFangSC-Medium"
        nameLabel.fontSize = 12
        nameLabel.fontColor = .labelColor
        nameLabel.verticalAlignmentMode = .center
        nameLabel.position = nameBadge.position
        nameLabel.zPosition = 101
        addChild(nameLabel)

        root.position = restingPosition
        addChild(root)
        root.addChild(avatar)
    }

    required init?(coder aDecoder: NSCoder) {
        nil
    }

    func render(_ state: PetRuntimeState) {
        avatar.apply(state.avatar, emotion: state.emotion)
        avatar.setFacing(state.facing)
        nameLabel.text = state.id == .mine
            ? "\(state.displayName)  ·  我"
            : "\(state.displayName)  ·  TA"

        guard lastActivity != state.activity else { return }
        lastActivity = state.activity
        root.removeAction(forKey: "activity")
        root.position = restingPosition
        root.xScale = 1
        root.yScale = 1
        shadow.removeAction(forKey: "activity")
        shadow.xScale = 1
        shadow.yScale = 1

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
            let shadowPulse = SKAction.sequence([
                .scaleX(to: 0.84, duration: 0.16),
                .scaleX(to: 1, duration: 0.16)
            ])
            shadow.run(.repeatForever(shadowPulse), withKey: "activity")
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

    private var restingPosition: CGPoint {
        CGPoint(x: size.width / 2, y: 94)
    }
}
