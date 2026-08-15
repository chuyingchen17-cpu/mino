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
}

public enum PetEmotion: String, Codable, Equatable, Sendable {
    case content
    case happy
    case shy
}

public struct PetRuntimeState: Sendable {
    public let id: PetID
    public var displayName: String
    public var position: CGPoint
    public var facing: PetFacing
    public var activity: PetActivity
    public var emotion: PetEmotion
    public var avatar: AvatarRecipe

    public init(
        id: PetID,
        displayName: String,
        position: CGPoint,
        facing: PetFacing,
        activity: PetActivity,
        emotion: PetEmotion,
        avatar: AvatarRecipe
    ) {
        self.id = id
        self.displayName = displayName
        self.position = position
        self.facing = facing
        self.activity = activity
        self.emotion = emotion
        self.avatar = avatar
    }
}
