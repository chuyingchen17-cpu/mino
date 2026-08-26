import AppKit
import MinoDomain
import SpriteKit

public enum PetCharacterRenderingBackend: Equatable, Sendable {
    case rasterFrames
    case missingRasterFrames
}

/// The world anchor for one pet. Locomotion owns this node's position; pose
/// animation is strictly contained in `bodyContainer` and never moves shadow.
@MainActor
final class PetAvatarNode: SKNode {
    private(set) var shadowNode = SKShapeNode(ellipseOf: CGSize(width: 58, height: 8))
    private(set) var bodyContainer = SKNode()
    private var spriteNode: SKSpriteNode?
    private var characterID: PetCharacterID?
    private(set) var renderingBackend: PetCharacterRenderingBackend?
    private(set) var currentClip: PetMotionClipID?
    private var currentReduceMotion = false
    private var currentPlaybackID: UUID?
    private var externallyDriven = false
    private(set) var motionStartCount = 0
    private(set) var lastRequestedDuration: TimeInterval?

    override init() {
        super.init()
        name = "worldAnchor"
        shadowNode.name = "shadow"
        shadowNode.fillColor = NSColor.black.withAlphaComponent(0.12)
        shadowNode.strokeColor = .clear
        shadowNode.position = CGPoint(x: 1, y: -47)
        shadowNode.zPosition = -10
        addChild(shadowNode)

        bodyContainer.name = "bodyContainer"
        addChild(bodyContainer)
    }

    required init?(coder aDecoder: NSCoder) {
        nil
    }

    /// Compatibility entry point. Old avatar recipes only select a catalog-2
    /// character; product rendering still resolves to its raster frame set.
    func apply(
        _ recipe: AvatarRecipe,
        activity: PetActivity,
        emotion: PetEmotion,
        facing: PetFacing,
        duration: TimeInterval? = nil,
        playbackID: UUID? = nil,
        reduceMotion: Bool? = nil,
        motionProgress: Double? = nil
    ) {
        apply(
            characterID: PetCharacterID(legacyAvatar: recipe),
            clip: PetMotionResolver.resolve(activity: activity, emotion: emotion),
            facing: facing,
            duration: duration,
            playbackID: playbackID,
            reduceMotion: reduceMotion,
            motionProgress: motionProgress
        )
    }

    func apply(
        characterID: PetCharacterID,
        clip requestedClip: PetMotionClipID,
        facing: PetFacing,
        duration: TimeInterval? = nil,
        playbackID: UUID? = nil,
        reduceMotion: Bool? = nil,
        motionProgress: Double? = nil
    ) {
        let exactRasterAnimation = PetFrameAnimationCatalog.shared.animation(
            for: characterID,
            clip: requestedClip
        )
        let rasterAnimation = exactRasterAnimation
            ?? (requestedClip == .idle ? nil : PetFrameAnimationCatalog.shared.animation(
                for: characterID,
                clip: .idle
            ))
        if exactRasterAnimation == nil {
            NSLog(
                "Mino frame catalog missing clip %@ for %@; vector fallback is disabled",
                requestedClip.rawValue,
                characterID.rawValue
            )
        }
        let clip = requestedClip
        let shouldReduceMotion = (reduceMotion
            ?? NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )

        if self.characterID != characterID {
            self.characterID = characterID
            currentClip = nil
            currentPlaybackID = nil
        }
        ensureRasterRenderer(hasFrames: rasterAnimation != nil)
        bodyContainer.xScale = facing == .right ? 1 : -1
        bodyContainer.yScale = 1

        if let motionProgress {
            externallyDriven = true
            spriteNode?.removeAction(forKey: "motion")
            bodyContainer.removeAction(forKey: "motion")
            currentClip = clip
            currentReduceMotion = shouldReduceMotion
            currentPlaybackID = playbackID
            if let rasterAnimation, let spriteNode {
                spriteNode.texture = rasterAnimation.texture(
                    progress: motionProgress,
                    reduceMotion: shouldReduceMotion
                )
            } else {
                spriteNode?.texture = nil
            }
            return
        }

        // Emotion-only state changes resolving to the same clip do not restart it.
        let changed = currentClip != clip
            || currentReduceMotion != shouldReduceMotion
            || externallyDriven
            || currentPlaybackID != playbackID
        guard changed else { return }
        externallyDriven = false
        currentClip = clip
        currentReduceMotion = shouldReduceMotion
        currentPlaybackID = playbackID
        startMotion(
            clip,
            frameAnimation: rasterAnimation,
            requestedDuration: duration,
            reduceMotion: shouldReduceMotion
        )
    }

    func apply(
        characterID: PetCharacterID,
        reactionPlan: PetReactionPlan,
        facing: PetFacing,
        clip: PetMotionClipID? = nil,
        reduceMotion: Bool? = nil,
        motionProgress: Double? = nil
    ) {
        apply(
            characterID: characterID,
            clip: clip ?? reactionPlan.motionClip ?? PetMotionResolver.resolve(
                activity: reactionPlan.activity,
                emotion: reactionPlan.emotion
            ),
            facing: facing,
            duration: reactionPlan.duration,
            playbackID: nil,
            reduceMotion: reduceMotion,
            motionProgress: motionProgress
        )
    }

    /// Input feedback is presentation-local, so it starts before any async
    /// provider/outbox work. The subsequent authoritative reaction gets its own
    /// playback ID and may restart the same semantic clip without a dead tap.
    func playImmediatePetReceive(
        duration: TimeInterval,
        reduceMotion: Bool? = nil
    ) {
        guard let characterID, spriteNode != nil else { return }
        let shouldReduceMotion = reduceMotion
            ?? NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let rasterAnimation = PetFrameAnimationCatalog.shared.animation(
            for: characterID,
            clip: .petReceive
        )
        ensureRasterRenderer(hasFrames: rasterAnimation != nil)
        externallyDriven = false
        currentClip = .petReceive
        currentReduceMotion = shouldReduceMotion
        currentPlaybackID = UUID()
        startMotion(
            .petReceive,
            frameAnimation: rasterAnimation,
            requestedDuration: duration,
            reduceMotion: shouldReduceMotion
        )
    }

    var currentPlaybackIDForTesting: UUID? { currentPlaybackID }

    private func ensureRasterRenderer(hasFrames: Bool) {
        if spriteNode == nil {
            bodyContainer.removeAllChildren()
            let sprite = SKSpriteNode(color: .clear, size: CGSize(width: 120, height: 120))
            sprite.name = "frameSprite"
            sprite.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            sprite.position = .zero
            sprite.zPosition = 20
            bodyContainer.addChild(sprite)
            spriteNode = sprite
            currentClip = nil
            currentPlaybackID = nil
        }
        renderingBackend = hasFrames ? .rasterFrames : .missingRasterFrames
    }

    private func startMotion(
        _ clip: PetMotionClipID,
        frameAnimation: PetFrameAnimation?,
        requestedDuration: TimeInterval?,
        reduceMotion: Bool
    ) {
        spriteNode?.removeAction(forKey: "motion")
        bodyContainer.removeAction(forKey: "motion")
        bodyContainer.removeAction(forKey: "reduceMotionFade")
        motionStartCount += 1
        let authoredDuration = frameAnimation?.clipDuration ?? defaultDuration(for: clip)
        let duration = max(0.12, requestedDuration ?? authoredDuration)
        lastRequestedDuration = duration
        if reduceMotion {
            if let frameAnimation, let spriteNode {
                spriteNode.texture = frameAnimation.reduceMotionTexture
            } else {
                spriteNode?.texture = nil
            }
            bodyContainer.alpha = 0.82
            bodyContainer.run(.fadeAlpha(to: 1, duration: 0.12), withKey: "reduceMotionFade")
            return
        }

        bodyContainer.alpha = 1
        guard let frameAnimation, let spriteNode, !frameAnimation.textures.isEmpty else {
            spriteNode?.texture = nil
            return
        }

        spriteNode.texture = frameAnimation.textures.first
        spriteNode.run(
            frameAnimation.playbackAction(fitting: duration),
            withKey: "motion"
        )
    }

    var usesRasterFramesForTesting: Bool {
        renderingBackend == .rasterFrames && spriteNode != nil
    }

    var currentTextureFilteringModeForTesting: SKTextureFilteringMode? {
        spriteNode?.texture?.filteringMode
    }

    var currentTextureForTesting: SKTexture? {
        spriteNode?.texture
    }

    var hasActiveFrameMotionForTesting: Bool {
        spriteNode?.action(forKey: "motion") != nil
    }

    var frameSpritePositionForTesting: CGPoint? {
        spriteNode?.position
    }

    private func defaultDuration(for clip: PetMotionClipID) -> TimeInterval {
        switch clip {
        case .walk: 0.72
        case .idle: 1.6
        case .sleep: 2.1
        case .petReceive, .shy, .wave: 0.9
        case .eat, .play, .happy, .welcome: 1.15
        case .tiredRefuse, .fullRefuse: 1.25
        case .cuddleGive, .cuddleReceive: 1.35
        case .flowerGive, .flowerReceive, .letterGive: 1.4
        }
    }
}
