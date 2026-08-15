import CoreGraphics
import Foundation

enum InteractionCue: Equatable, Sendable {
    case kissHeart(position: CGPoint)
    case flowerGift(position: CGPoint)
}

struct InteractionAdvance: Sendable {
    var cue: InteractionCue?
    var completed = false
}

struct KissInteractionSession: Sendable {
    enum Phase: Equatable, Sendable {
        case approaching
        case holdingPose
        case completed
    }

    private(set) var phase: Phase = .approaching
    let mineTarget: CGPoint
    let partnerTarget: CGPoint
    let effectPosition: CGPoint

    private var poseElapsed: TimeInterval = 0

    init(mine: PetRuntimeState, partner: PetRuntimeState, visibleFrame: CGRect) {
        let inset = visibleFrame.insetBy(dx: 120, dy: 100)
        let rawCenter = CGPoint(
            x: (mine.position.x + partner.position.x) / 2,
            y: (mine.position.y + partner.position.y) / 2
        )
        let center = CGPoint(
            x: min(max(rawCenter.x, inset.minX), inset.maxX),
            y: min(max(rawCenter.y, inset.minY), inset.maxY)
        )
        let halfGap: CGFloat = 46

        mineTarget = CGPoint(x: center.x - halfGap, y: center.y)
        partnerTarget = CGPoint(x: center.x + halfGap, y: center.y)
        effectPosition = CGPoint(x: center.x, y: center.y + 42)
    }

    mutating func advance(
        mine: inout PetRuntimeState,
        partner: inout PetRuntimeState,
        deltaTime: TimeInterval
    ) -> InteractionAdvance {
        switch phase {
        case .approaching:
            let mineStep = WorldMath.movedPoint(
                from: mine.position,
                toward: mineTarget,
                speed: 180,
                deltaTime: deltaTime
            )
            let partnerStep = WorldMath.movedPoint(
                from: partner.position,
                toward: partnerTarget,
                speed: 180,
                deltaTime: deltaTime
            )

            mine.position = mineStep.point
            partner.position = partnerStep.point
            mine.facing = .right
            partner.facing = .left
            mine.activity = .walking
            partner.activity = .walking

            guard mineStep.arrived, partnerStep.arrived else {
                return InteractionAdvance()
            }

            phase = .holdingPose
            mine.activity = .interacting
            partner.activity = .interacting
            mine.emotion = .shy
            partner.emotion = .happy
            return InteractionAdvance(cue: .kissHeart(position: effectPosition))

        case .holdingPose:
            poseElapsed += deltaTime
            guard poseElapsed >= 1.7 else {
                return InteractionAdvance()
            }

            phase = .completed
            mine.activity = .idle
            partner.activity = .idle
            mine.emotion = .content
            partner.emotion = .content
            return InteractionAdvance(completed: true)

        case .completed:
            return InteractionAdvance(completed: true)
        }
    }
}

struct FlowerInteractionSession: Sendable {
    enum Phase: Equatable, Sendable {
        case approaching
        case offering
        case completed
    }

    private(set) var phase: Phase = .approaching
    let mineTarget: CGPoint
    let partnerTarget: CGPoint
    let effectPosition: CGPoint

    private var poseElapsed: TimeInterval = 0

    init(mine: PetRuntimeState, partner: PetRuntimeState, visibleFrame: CGRect) {
        let inset = visibleFrame.insetBy(dx: 130, dy: 110)
        let rawCenter = CGPoint(
            x: (mine.position.x + partner.position.x) / 2,
            y: (mine.position.y + partner.position.y) / 2
        )
        let center = CGPoint(
            x: min(max(rawCenter.x, inset.minX), inset.maxX),
            y: min(max(rawCenter.y, inset.minY), inset.maxY)
        )

        mineTarget = CGPoint(x: center.x - 58, y: center.y)
        partnerTarget = CGPoint(x: center.x + 58, y: center.y)
        effectPosition = CGPoint(x: center.x + 4, y: center.y + 34)
    }

    mutating func advance(
        mine: inout PetRuntimeState,
        partner: inout PetRuntimeState,
        deltaTime: TimeInterval
    ) -> InteractionAdvance {
        switch phase {
        case .approaching:
            let mineStep = WorldMath.movedPoint(
                from: mine.position,
                toward: mineTarget,
                speed: 180,
                deltaTime: deltaTime
            )
            let partnerStep = WorldMath.movedPoint(
                from: partner.position,
                toward: partnerTarget,
                speed: 145,
                deltaTime: deltaTime
            )

            mine.position = mineStep.point
            partner.position = partnerStep.point
            mine.facing = .right
            partner.facing = .left
            mine.activity = .walking
            partner.activity = .walking

            guard mineStep.arrived, partnerStep.arrived else {
                return InteractionAdvance()
            }

            phase = .offering
            mine.activity = .interacting
            partner.activity = .interacting
            mine.emotion = .happy
            partner.emotion = .shy
            return InteractionAdvance(cue: .flowerGift(position: effectPosition))

        case .offering:
            poseElapsed += deltaTime
            guard poseElapsed >= 2.2 else {
                return InteractionAdvance()
            }

            phase = .completed
            mine.activity = .idle
            partner.activity = .idle
            mine.emotion = .content
            partner.emotion = .happy
            return InteractionAdvance(completed: true)

        case .completed:
            return InteractionAdvance(completed: true)
        }
    }
}

enum ActiveInteraction: Sendable {
    case kiss(KissInteractionSession)
    case flower(FlowerInteractionSession)

    mutating func advance(
        mine: inout PetRuntimeState,
        partner: inout PetRuntimeState,
        deltaTime: TimeInterval
    ) -> InteractionAdvance {
        switch self {
        case .kiss(var session):
            let result = session.advance(
                mine: &mine,
                partner: &partner,
                deltaTime: deltaTime
            )
            self = .kiss(session)
            return result

        case .flower(var session):
            let result = session.advance(
                mine: &mine,
                partner: &partner,
                deltaTime: deltaTime
            )
            self = .flower(session)
            return result
        }
    }
}
