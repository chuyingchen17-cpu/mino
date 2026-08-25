import AppKit
import MinoDomain
import SpriteKit

@MainActor
final class PetScene: SKScene {
    /// `avatar` is itself the world anchor and owns only a fixed shadow plus a
    /// pose-only body container. The scene never adds a second hop/bounce owner.
    private let avatar = PetAvatarNode()
    private let nameBadge = SKShapeNode(rectOf: CGSize(width: 78, height: 25), cornerRadius: 12.5)
    private let nameLabel = SKLabelNode()

    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = .clear

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

        avatar.position = restingPosition
        addChild(avatar)
    }

    required init?(coder aDecoder: NSCoder) {
        nil
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        avatar.position = restingPosition
        nameBadge.position = CGPoint(x: size.width / 2, y: 18)
        nameLabel.position = nameBadge.position
    }

    func render(
        _ state: PetRuntimeState,
        reactionPlan: PetReactionPlan? = nil,
        clipOverride: PetMotionClipID? = nil,
        reduceMotion: Bool? = nil,
        motionProgress: Double? = nil
    ) {
        let clip = clipOverride
            ?? state.motionClipOverride
            ?? reactionPlan?.motionClip
            ?? reactionPlan.map { PetMotionResolver.resolve(activity: $0.activity, emotion: $0.emotion) }
            ?? PetMotionResolver.resolve(activity: state.activity, emotion: state.emotion)
        avatar.apply(
            characterID: state.characterID,
            clip: clip,
            facing: state.facing,
            duration: reactionPlan?.duration ?? state.motionDurationOverride,
            playbackID: state.motionPlaybackID,
            reduceMotion: reduceMotion,
            motionProgress: motionProgress
        )
        nameLabel.text = state.id == .mine
            ? "\(state.displayName)  ·  我"
            : "\(state.displayName)  ·  TA"
    }

    /// Explicit interaction choreography for paired giver/receiver actions.
    func renderInteraction(
        _ state: PetRuntimeState,
        kind: PetCareInteractionKind,
        outcome: PetInteractionOutcome = .applied,
        role: PetMotionRole = .single,
        duration: TimeInterval,
        reduceMotion: Bool? = nil,
        motionProgress: Double? = nil
    ) {
        let clip = PetMotionResolver.resolve(
            activity: state.activity,
            emotion: state.emotion,
            interaction: kind,
            outcome: outcome,
            role: role
        )
        avatar.apply(
            characterID: state.characterID,
            clip: clip,
            facing: state.facing,
            duration: duration,
            playbackID: state.motionPlaybackID,
            reduceMotion: reduceMotion,
            motionProgress: motionProgress
        )
    }

    /// Explicit visit sequence: walkingIn -> welcome -> active -> waveGoodbye
    /// -> walkingOut. Position still belongs to the runtime/world anchor.
    func renderVisit(
        _ state: PetRuntimeState,
        phase: PetVisitMotionPhase,
        duration: TimeInterval,
        reduceMotion: Bool? = nil,
        motionProgress: Double? = nil
    ) {
        let clip = PetMotionResolver.resolve(
            activity: state.activity,
            emotion: state.emotion,
            visitPhase: phase
        )
        avatar.apply(
            characterID: state.characterID,
            clip: clip,
            facing: state.facing,
            duration: duration,
            playbackID: state.motionPlaybackID,
            reduceMotion: reduceMotion,
            motionProgress: motionProgress
        )
    }

    func reactToClick(reduceMotion: Bool? = nil) {
        avatar.playImmediatePetReceive(
            duration: 0.72,
            reduceMotion: reduceMotion
        )
    }

    var renderedClipForTesting: PetMotionClipID? { avatar.currentClip }
    var worldAnchorPositionForTesting: CGPoint { avatar.position }
    var shadowPositionForTesting: CGPoint { avatar.shadowNode.position }
    var bodyContainerPositionForTesting: CGPoint { avatar.bodyContainer.position }
    var motionStartCountForTesting: Int { avatar.motionStartCount }
    var lastMotionDurationForTesting: TimeInterval? { avatar.lastRequestedDuration }
    var playbackIDForTesting: UUID? { avatar.currentPlaybackIDForTesting }
    var currentTextureForTesting: SKTexture? { avatar.currentTextureForTesting }
    var hasActiveFrameMotionForTesting: Bool { avatar.hasActiveFrameMotionForTesting }
    var frameSpritePositionForTesting: CGPoint? { avatar.frameSpritePositionForTesting }

    private var restingPosition: CGPoint {
        CGPoint(x: size.width / 2, y: 94)
    }
}
