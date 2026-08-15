import CoreGraphics
import Foundation

enum InteractionCue: Equatable, Sendable {
    case kissHeart(position: CGPoint)
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
            return InteractionAdvance(cue: .kissHeart(position: effectPosition))

        case .holdingPose:
            poseElapsed += deltaTime
            guard poseElapsed >= 1.7 else {
                return InteractionAdvance()
            }

            phase = .completed
            mine.activity = .idle
            partner.activity = .idle
            return InteractionAdvance(completed: true)

        case .completed:
            return InteractionAdvance(completed: true)
        }
    }
}

