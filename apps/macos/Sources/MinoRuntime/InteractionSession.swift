import CoreGraphics
import Foundation
import MinoDomain

public enum InteractionCue: Equatable, Sendable {
    case kissHeart(position: CGPoint)
    case flowerGift(position: CGPoint)
}

public enum InteractionCueKind: Equatable, Sendable {
    case none
    case kissHeart
    case flowerGift
}

public struct InteractionAdvance: Sendable {
    public var cue: InteractionCue?
    public var completed = false

    public init(cue: InteractionCue? = nil, completed: Bool = false) {
        self.cue = cue
        self.completed = completed
    }
}

/// Built-in two-pet desktop choreographies. A new paired animation is a new
/// case plus a `PairedPetChoreography` value — not a new session type.
public enum PairedPetInteractionKind: String, Equatable, Sendable {
    case kissHeart = "kiss_heart"
    case flowerGift = "flower_gift"

    public var choreography: PairedPetChoreography {
        switch self {
        case .kissHeart: .kissHeart
        case .flowerGift: .flowerGift
        }
    }
}

public struct PairedPetPose: Equatable, Sendable {
    public var activity: PetActivity
    public var emotion: PetEmotion
    public var clip: PetMotionClipID

    public init(activity: PetActivity, emotion: PetEmotion, clip: PetMotionClipID) {
        self.activity = activity
        self.emotion = emotion
        self.clip = clip
    }
}

/// Data description of a two-pet approach → pose → rest sequence.
/// SpriteKit only plays the clips named here; it does not own the choreography.
public struct PairedPetChoreography: Equatable, Sendable {
    public var id: String
    public var cue: InteractionCueKind
    public var approachInset: CGSize
    public var halfGap: CGFloat
    public var effectOffset: CGPoint
    public var giverSpeed: CGFloat
    public var receiverSpeed: CGFloat
    public var poseDuration: TimeInterval
    public var giverPose: PairedPetPose
    public var receiverPose: PairedPetPose
    public var giverRestEmotion: PetEmotion
    public var receiverRestEmotion: PetEmotion

    public init(
        id: String,
        cue: InteractionCueKind,
        approachInset: CGSize,
        halfGap: CGFloat,
        effectOffset: CGPoint,
        giverSpeed: CGFloat,
        receiverSpeed: CGFloat,
        poseDuration: TimeInterval,
        giverPose: PairedPetPose,
        receiverPose: PairedPetPose,
        giverRestEmotion: PetEmotion,
        receiverRestEmotion: PetEmotion
    ) {
        self.id = id
        self.cue = cue
        self.approachInset = approachInset
        self.halfGap = halfGap
        self.effectOffset = effectOffset
        self.giverSpeed = giverSpeed
        self.receiverSpeed = receiverSpeed
        self.poseDuration = poseDuration
        self.giverPose = giverPose
        self.receiverPose = receiverPose
        self.giverRestEmotion = giverRestEmotion
        self.receiverRestEmotion = receiverRestEmotion
    }

    public static let kissHeart = PairedPetChoreography(
        id: PairedPetInteractionKind.kissHeart.rawValue,
        cue: .kissHeart,
        approachInset: CGSize(width: 120, height: 100),
        halfGap: 46,
        effectOffset: CGPoint(x: 0, y: 42),
        giverSpeed: 180,
        receiverSpeed: 180,
        poseDuration: 1.7,
        giverPose: PairedPetPose(activity: .celebrating, emotion: .shy, clip: .cuddleGive),
        receiverPose: PairedPetPose(activity: .celebrating, emotion: .happy, clip: .cuddleReceive),
        giverRestEmotion: .content,
        receiverRestEmotion: .content
    )

    public static let flowerGift = PairedPetChoreography(
        id: PairedPetInteractionKind.flowerGift.rawValue,
        cue: .flowerGift,
        approachInset: CGSize(width: 130, height: 110),
        halfGap: 58,
        effectOffset: CGPoint(x: 4, y: 34),
        giverSpeed: 180,
        receiverSpeed: 145,
        poseDuration: 2.2,
        giverPose: PairedPetPose(activity: .offeringGift, emotion: .happy, clip: .flowerGive),
        receiverPose: PairedPetPose(activity: .celebrating, emotion: .shy, clip: .flowerReceive),
        giverRestEmotion: .content,
        receiverRestEmotion: .happy
    )

    func cue(at effectPosition: CGPoint) -> InteractionCue? {
        switch cue {
        case .none: nil
        case .kissHeart: .kissHeart(position: effectPosition)
        case .flowerGift: .flowerGift(position: effectPosition)
        }
    }
}

public extension PetReactionEffect {
    var pairedInteraction: PairedPetInteractionKind? {
        switch self {
        case .heart: .kissHeart
        case .flower: .flowerGift
        case .none: nil
        }
    }
}

public struct PairedPetInteractionSession: Sendable {
    public enum Phase: Equatable, Sendable {
        case approaching
        case posing
        case completed
    }

    public private(set) var phase: Phase = .approaching
    public let choreography: PairedPetChoreography
    public let giverTarget: CGPoint
    public let receiverTarget: CGPoint
    public let effectPosition: CGPoint

    private var poseElapsed: TimeInterval = 0

    public init(
        choreography: PairedPetChoreography,
        giver: PetRuntimeState,
        receiver: PetRuntimeState,
        visibleFrame: CGRect
    ) {
        self.choreography = choreography
        let inset = visibleFrame.insetBy(
            dx: choreography.approachInset.width,
            dy: choreography.approachInset.height
        )
        let rawCenter = CGPoint(
            x: (giver.position.x + receiver.position.x) / 2,
            y: (giver.position.y + receiver.position.y) / 2
        )
        let center = CGPoint(
            x: min(max(rawCenter.x, inset.minX), inset.maxX),
            y: min(max(rawCenter.y, inset.minY), inset.maxY)
        )
        giverTarget = CGPoint(x: center.x - choreography.halfGap, y: center.y)
        receiverTarget = CGPoint(x: center.x + choreography.halfGap, y: center.y)
        effectPosition = CGPoint(
            x: center.x + choreography.effectOffset.x,
            y: center.y + choreography.effectOffset.y
        )
    }

    public mutating func advance(
        giver: inout PetRuntimeState,
        receiver: inout PetRuntimeState,
        deltaTime: TimeInterval
    ) -> InteractionAdvance {
        switch phase {
        case .approaching:
            let giverStep = WorldMath.movedPoint(
                from: giver.position,
                toward: giverTarget,
                speed: choreography.giverSpeed,
                deltaTime: deltaTime
            )
            let receiverStep = WorldMath.movedPoint(
                from: receiver.position,
                toward: receiverTarget,
                speed: choreography.receiverSpeed,
                deltaTime: deltaTime
            )

            applyApproach(&giver, step: giverStep, facing: .right)
            applyApproach(&receiver, step: receiverStep, facing: .left)

            guard giverStep.arrived, receiverStep.arrived else {
                return InteractionAdvance()
            }

            phase = .posing
            applyPose(&giver, choreography.giverPose)
            applyPose(&receiver, choreography.receiverPose)
            return InteractionAdvance(cue: choreography.cue(at: effectPosition))

        case .posing:
            poseElapsed += deltaTime
            guard poseElapsed >= choreography.poseDuration else {
                return InteractionAdvance()
            }

            phase = .completed
            rest(&giver, emotion: choreography.giverRestEmotion)
            rest(&receiver, emotion: choreography.receiverRestEmotion)
            return InteractionAdvance(completed: true)

        case .completed:
            return InteractionAdvance(completed: true)
        }
    }

    private func applyApproach(
        _ pet: inout PetRuntimeState,
        step: (point: CGPoint, arrived: Bool),
        facing: PetFacing
    ) {
        pet.position = step.point
        pet.facing = facing
        pet.activity = .walking
        pet.motionClipOverride = .walk
        pet.motionDurationOverride = nil
        pet.motionPlaybackID = nil
    }

    private func applyPose(_ pet: inout PetRuntimeState, _ pose: PairedPetPose) {
        pet.activity = pose.activity
        pet.emotion = pose.emotion
        pet.motionClipOverride = pose.clip
        pet.motionDurationOverride = choreography.poseDuration
    }

    private func rest(_ pet: inout PetRuntimeState, emotion: PetEmotion) {
        pet.activity = .idle
        pet.emotion = emotion
        pet.motionClipOverride = nil
        pet.motionDurationOverride = nil
        pet.motionPlaybackID = nil
    }
}

struct ActivePairedInteraction: Sendable {
    var giverID: PetID
    var receiverID: PetID
    var session: PairedPetInteractionSession
}
