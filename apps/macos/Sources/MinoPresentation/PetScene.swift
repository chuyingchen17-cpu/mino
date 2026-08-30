import AppKit
import MinoDomain
import SpriteKit

@MainActor
final class PetScene: SKScene {
    /// `avatar` is itself the world anchor and owns only a fixed shadow plus a
    /// pose-only body container. The scene never adds a second hop/bounce owner.
    private let avatar = PetAvatarNode()
    private let nameBadge = SKShapeNode()
    private let nameLabel = SKLabelNode()

    private static let nameBadgeHeight: CGFloat = 25
    private static let nameBadgeMinWidth: CGFloat = 44
    private static let nameBadgeHorizontalPadding: CGFloat = 13
    private var nameBadgeSourceText = ""

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
        nameLabel.numberOfLines = 1
        nameLabel.position = nameBadge.position
        nameLabel.zPosition = 101
        addChild(nameLabel)
        layoutNameBadge()

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
        // 牌子宽度上限跟着场景宽度走，换了尺寸要重排。
        layoutNameBadge()
    }

    /// 名字牌宽度跟着名字长短走。
    ///
    /// 原来写死 78pt：自己的桌宠牌子上还挂着“· 我”时刚好填满，去掉之后两个字的名字
    /// 会在里面空一大片；而名字本来就能改，长一点又会顶出窗口，所以两头都要管。
    private func layoutNameBadge() {
        let maxWidth = max(Self.nameBadgeMinWidth, size.width - 16)
        let maxTextWidth = maxWidth - Self.nameBadgeHorizontalPadding * 2
        nameLabel.text = Self.name(nameBadgeSourceText, truncatedToFit: maxTextWidth, measuredBy: nameLabel)
        let width = min(
            maxWidth,
            max(
                Self.nameBadgeMinWidth,
                ceil(nameLabel.frame.width) + Self.nameBadgeHorizontalPadding * 2
            )
        )
        nameBadge.path = CGPath(
            roundedRect: CGRect(
                x: -width / 2,
                y: -Self.nameBadgeHeight / 2,
                width: width,
                height: Self.nameBadgeHeight
            ),
            cornerWidth: Self.nameBadgeHeight / 2,
            cornerHeight: Self.nameBadgeHeight / 2,
            transform: nil
        )
    }

    /// 自己裁，不能交给 SKLabelNode。
    ///
    /// 它的 `preferredMaxLayoutWidth` 配 `byTruncatingTail` 在单行下不生效：实测 14 个
    /// 汉字的名字依旧报 170pt 宽，牌子跟着它算就会被文字铺出去。
    private static func name(
        _ name: String,
        truncatedToFit maxWidth: CGFloat,
        measuredBy label: SKLabelNode
    ) -> String {
        label.text = name
        guard ceil(label.frame.width) > maxWidth else { return name }
        var characters = Array(name)
        while !characters.isEmpty {
            characters.removeLast()
            let candidate = String(characters) + "…"
            label.text = candidate
            if ceil(label.frame.width) <= maxWidth { return candidate }
        }
        return "…"
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
        // 自己的桌宠只显示名字：牌子就挂在它身上，不用再标一次“我”。来访的好友宠物
        // 仍然标出来——两只同时在桌面上时得分得清哪只不是自己的。
        let name = state.id == .mine
            ? state.displayName
            : "\(state.displayName)  ·  TA"
        setNameBadgeText(name)
    }

    private func setNameBadgeText(_ name: String) {
        guard nameBadgeSourceText != name else { return }
        nameBadgeSourceText = name
        layoutNameBadge()
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
