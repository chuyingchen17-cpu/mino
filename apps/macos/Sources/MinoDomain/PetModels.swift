import CoreGraphics
import Foundation

public enum PetID: String, CaseIterable, Codable, Sendable {
    case mine
    case partner
}

public enum PetFacing: String, Codable, Equatable, Sendable {
    case left
    case right
}

public enum PetActivity: String, Codable, Equatable, Sendable {
    case idle
    case walking
    case interacting
    case petting
    case eating
    case playing
    case sleeping
    case celebrating
    case offeringGift = "offering_gift"
}

public enum PetEmotion: String, Codable, Equatable, Sendable {
    case content
    case happy
    case shy
    case excited
    case sleepy
    case grateful
    case playful
}

public struct PetRuntimeState: Sendable {
    public let id: PetID
    public var displayName: String
    public var position: CGPoint
    public var facing: PetFacing
    public var activity: PetActivity
    public var emotion: PetEmotion
    public var avatar: AvatarRecipe
    public var characterID: PetCharacterID
    /// Optional semantic choreography selected by the interaction/visit runtime.
    /// Nil keeps the centralized activity/emotion resolver as the source.
    public var motionClipOverride: PetMotionClipID?
    /// Duration supplied by the originating reaction plan. Presentation uses
    /// it for one-shot pose playback while the runtime uses it for restoration.
    public var motionDurationOverride: TimeInterval?
    /// Identifies one concrete playback request. A new interaction receives a
    /// new value even when it resolves to the same clip, so animation replay is
    /// independent from care-value cooldown and emotion-only renders.
    public var motionPlaybackID: UUID?

    public init(
        id: PetID,
        displayName: String,
        position: CGPoint,
        facing: PetFacing,
        activity: PetActivity,
        emotion: PetEmotion,
        avatar: AvatarRecipe,
        characterID: PetCharacterID? = nil,
        motionClipOverride: PetMotionClipID? = nil,
        motionDurationOverride: TimeInterval? = nil,
        motionPlaybackID: UUID? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.position = position
        self.facing = facing
        self.activity = activity
        self.emotion = emotion
        self.avatar = avatar
        self.characterID = characterID ?? PetCharacterID(legacyAvatar: avatar)
        self.motionClipOverride = motionClipOverride
        self.motionDurationOverride = motionDurationOverride
        self.motionPlaybackID = motionPlaybackID
    }
}
