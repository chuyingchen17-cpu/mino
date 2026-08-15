import CoreGraphics
import Foundation
import MinoDomain

public enum WorldMath {
    public static func movedPoint(
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
public final class PetWorld {
    public typealias VisibleFrameProvider = (CGPoint) -> CGRect

    public private(set) var pets: [PetID: PetRuntimeState]
    public var onStateChange: (([PetID: PetRuntimeState]) -> Void)?

    private let visibleFrameProvider: VisibleFrameProvider
    private var targets: [PetID: CGPoint] = [:]
    private var activeInteraction: ActiveInteraction?
    private var motionTimer: Timer?
    private var ambientTimer: Timer?
    private var lastMotionTime = ProcessInfo.processInfo.systemUptime
    public var onInteractionCue: ((InteractionCue) -> Void)?

    public init(pets: [PetRuntimeState], visibleFrameProvider: @escaping VisibleFrameProvider) {
        self.pets = Dictionary(uniqueKeysWithValues: pets.map { ($0.id, $0) })
        self.visibleFrameProvider = visibleFrameProvider
    }

    public func start() {
        publish()
        ambientTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.scheduleAmbientWalks()
            }
        }
        ambientTimer?.tolerance = 0.6
    }

    public func stop() {
        ambientTimer?.invalidate()
        motionTimer?.invalidate()
        ambientTimer = nil
        motionTimer = nil
    }

    public func movePet(_ id: PetID, to position: CGPoint) {
        guard activeInteraction == nil, var pet = pets[id] else { return }
        targets[id] = nil
        pet.position = position
        pet.activity = .idle
        pet.emotion = .content
        pets[id] = pet
        publish()
    }

    public func walkAll() {
        guard activeInteraction == nil else { return }
        for id in PetID.allCases {
            scheduleWalk(for: id)
        }
    }

    public func triggerKiss() {
        guard
            activeInteraction == nil,
            let mine = pets[.mine],
            let partner = pets[.partner]
        else {
            return
        }

        targets.removeAll()
        let visibleFrame = visibleFrameProvider(mine.position)
        activeInteraction = .kiss(
            KissInteractionSession(
                mine: mine,
                partner: partner,
                visibleFrame: visibleFrame
            )
        )
        ensureMotionTimer()
    }

    public func triggerFlowerGift() {
        guard
            activeInteraction == nil,
            let mine = pets[.mine],
            let partner = pets[.partner]
        else {
            return
        }

        targets.removeAll()
        let visibleFrame = visibleFrameProvider(mine.position)
        activeInteraction = .flower(
            FlowerInteractionSession(
                mine: mine,
                partner: partner,
                visibleFrame: visibleFrame
            )
        )
        ensureMotionTimer()
    }

    public func resetForDemo() {
        guard let anchor = pets[.mine]?.position else { return }
        let frame = visibleFrameProvider(anchor).insetBy(dx: 120, dy: 105)
        guard frame.width > 0, frame.height > 0 else { return }

        targets.removeAll()
        activeInteraction = nil
        let center = CGPoint(x: frame.midX, y: frame.minY + min(35, frame.height / 2))
        updatePet(.mine) { pet in
            pet.position = CGPoint(x: center.x - 150, y: center.y)
            pet.facing = .right
            pet.activity = .idle
            pet.emotion = .content
        }
        updatePet(.partner) { pet in
            pet.position = CGPoint(x: center.x + 150, y: center.y)
            pet.facing = .left
            pet.activity = .idle
            pet.emotion = .content
        }
        publish()
    }

    public func walkApartForDemo() {
        guard
            activeInteraction == nil,
            let mine = pets[.mine],
            let partner = pets[.partner]
        else {
            return
        }

        let centerX = (mine.position.x + partner.position.x) / 2
        scheduleWalk(for: .mine, to: CGPoint(x: centerX - 180, y: mine.position.y))
        scheduleWalk(for: .partner, to: CGPoint(x: centerX + 180, y: partner.position.y))
    }

    public func restorePetsToVisibleScreens() {
        targets.removeAll()
        activeInteraction = nil

        for id in PetID.allCases {
            updatePet(id) { pet in
                let frame = visibleFrameProvider(pet.position).insetBy(dx: 90, dy: 95)
                guard frame.width > 0, frame.height > 0 else { return }
                pet.position = CGPoint(
                    x: min(max(pet.position.x, frame.minX), frame.maxX),
                    y: min(max(pet.position.y, frame.minY), frame.maxY)
                )
                pet.activity = .idle
                pet.emotion = .content
            }
        }
        publish()
    }

    public func togglePartnerAppearance() {
        guard var partner = pets[.partner] else { return }
        partner.avatar = partner.avatar == .partner ? .partnerAlternate : .partner
        pets[.partner] = partner
        publish()
    }

    private func scheduleAmbientWalks() {
        guard targets.isEmpty, activeInteraction == nil else { return }
        for id in PetID.allCases where Double.random(in: 0...1) < 0.45 {
            scheduleWalk(for: id)
        }
    }

    private func scheduleWalk(for id: PetID) {
        guard let pet = pets[id], pet.activity == .idle else { return }
        let frame = visibleFrameProvider(pet.position).insetBy(dx: 90, dy: 90)
        guard frame.width > 0, frame.height > 0 else { return }

        let target = CGPoint(
            x: CGFloat.random(in: frame.minX...frame.maxX),
            y: CGFloat.random(in: frame.minY...(frame.minY + min(120, frame.height)))
        )
        scheduleWalk(for: id, to: target)
    }

    private func scheduleWalk(for id: PetID, to target: CGPoint) {
        guard var pet = pets[id], pet.activity == .idle else { return }
        targets[id] = target
        pet.facing = target.x >= pet.position.x ? .right : .left
        pet.activity = .walking
        pet.emotion = .content
        pets[id] = pet
        publish()
        ensureMotionTimer()
    }

    private func updatePet(_ id: PetID, update: (inout PetRuntimeState) -> Void) {
        guard var pet = pets[id] else { return }
        update(&pet)
        pets[id] = pet
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

        if activeInteraction != nil {
            tickInteraction(deltaTime: deltaTime)
        } else {
            tickAutonomousMotion(deltaTime: deltaTime)
        }

        publish()
        if targets.isEmpty, activeInteraction == nil {
            motionTimer?.invalidate()
            motionTimer = nil
        }
    }

    private func tickAutonomousMotion(deltaTime: TimeInterval) {
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
    }

    private func tickInteraction(deltaTime: TimeInterval) {
        guard
            var interaction = activeInteraction,
            var mine = pets[.mine],
            var partner = pets[.partner]
        else {
            activeInteraction = nil
            return
        }

        let advance = interaction.advance(
            mine: &mine,
            partner: &partner,
            deltaTime: deltaTime
        )
        pets[.mine] = mine
        pets[.partner] = partner

        if let cue = advance.cue {
            onInteractionCue?(cue)
        }
        activeInteraction = advance.completed ? nil : interaction
    }

    private func publish() {
        onStateChange?(pets)
    }
}
