import CoreGraphics
import Foundation

enum PetID: String, CaseIterable, Sendable {
    case mine
    case partner
}

enum PetFacing: Sendable {
    case left
    case right
}

enum PetActivity: Equatable, Sendable {
    case idle
    case walking
    case interacting
}

struct PetRuntimeState: Sendable {
    let id: PetID
    var position: CGPoint
    var facing: PetFacing
    var activity: PetActivity
    var avatar: AvatarRecipe
}

enum WorldMath {
    static func movedPoint(
        from origin: CGPoint,
        toward target: CGPoint,
        speed: CGFloat,
        deltaTime: TimeInterval
    ) -> (point: CGPoint, arrived: Bool) {
        let dx = target.x - origin.x
        let dy = target.y - origin.y
        let distance = hypot(dx, dy)
        let step = speed * CGFloat(deltaTime)

        guard distance > step, distance > 0 else {
            return (target, true)
        }

        return (
            CGPoint(
                x: origin.x + dx / distance * step,
                y: origin.y + dy / distance * step
            ),
            false
        )
    }
}

@MainActor
final class PetWorld {
    typealias VisibleFrameProvider = (CGPoint) -> CGRect

    private(set) var pets: [PetID: PetRuntimeState]
    var onStateChange: (([PetID: PetRuntimeState]) -> Void)?

    private let visibleFrameProvider: VisibleFrameProvider
    private var targets: [PetID: CGPoint] = [:]
    private var motionTimer: Timer?
    private var ambientTimer: Timer?
    private var lastMotionTime = ProcessInfo.processInfo.systemUptime

    init(pets: [PetRuntimeState], visibleFrameProvider: @escaping VisibleFrameProvider) {
        self.pets = Dictionary(uniqueKeysWithValues: pets.map { ($0.id, $0) })
        self.visibleFrameProvider = visibleFrameProvider
    }

    func start() {
        publish()
        ambientTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.scheduleAmbientWalks()
            }
        }
        ambientTimer?.tolerance = 0.6
    }

    func stop() {
        ambientTimer?.invalidate()
        motionTimer?.invalidate()
        ambientTimer = nil
        motionTimer = nil
    }

    func movePet(_ id: PetID, to position: CGPoint) {
        guard var pet = pets[id], pet.activity != .interacting else { return }
        targets[id] = nil
        pet.position = position
        pet.activity = .idle
        pets[id] = pet
        publish()
    }

    func walkAll() {
        for id in PetID.allCases {
            scheduleWalk(for: id)
        }
    }

    func togglePartnerAppearance() {
        guard var partner = pets[.partner] else { return }
        partner.avatar = partner.avatar == .partner ? .partnerAlternate : .partner
        pets[.partner] = partner
        publish()
    }

    private func scheduleAmbientWalks() {
        guard targets.isEmpty else { return }
        for id in PetID.allCases where Double.random(in: 0...1) < 0.45 {
            scheduleWalk(for: id)
        }
    }

    private func scheduleWalk(for id: PetID) {
        guard var pet = pets[id], pet.activity == .idle else { return }
        let frame = visibleFrameProvider(pet.position).insetBy(dx: 90, dy: 90)
        guard frame.width > 0, frame.height > 0 else { return }

        let target = CGPoint(
            x: CGFloat.random(in: frame.minX...frame.maxX),
            y: CGFloat.random(in: frame.minY...(frame.minY + min(120, frame.height)))
        )
        targets[id] = target
        pet.facing = target.x >= pet.position.x ? .right : .left
        pet.activity = .walking
        pets[id] = pet
        publish()
        ensureMotionTimer()
    }

    private func ensureMotionTimer() {
        guard motionTimer == nil else { return }
        lastMotionTime = ProcessInfo.processInfo.systemUptime
        motionTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tickMotion()
            }
        }
    }

    private func tickMotion() {
        let now = ProcessInfo.processInfo.systemUptime
        let deltaTime = min(0.1, now - lastMotionTime)
        lastMotionTime = now

        for (id, target) in targets {
            guard var pet = pets[id] else { continue }
            let result = WorldMath.movedPoint(
                from: pet.position,
                toward: target,
                speed: 85,
                deltaTime: deltaTime
            )
            pet.position = result.point
            if result.arrived {
                pet.activity = .idle
                targets[id] = nil
            }
            pets[id] = pet
        }

        publish()
        if targets.isEmpty {
            motionTimer?.invalidate()
            motionTimer = nil
        }
    }

    private func publish() {
        onStateChange?(pets)
    }
}
