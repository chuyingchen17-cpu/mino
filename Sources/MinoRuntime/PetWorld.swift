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

    public static func constrainedPoint(
        _ point: CGPoint,
        to frame: CGRect,
        horizontalInset: CGFloat = 90,
        verticalInset: CGFloat = 95
    ) -> CGPoint {
        let safeHorizontalInset = min(max(horizontalInset, 0), max(frame.width / 2, 0))
        let safeVerticalInset = min(max(verticalInset, 0), max(frame.height / 2, 0))
        let bounds = frame.insetBy(dx: safeHorizontalInset, dy: safeVerticalInset)
        return CGPoint(
            x: min(max(point.x, bounds.minX), bounds.maxX),
            y: min(max(point.y, bounds.minY), bounds.maxY)
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
    private var explicitMovementPets: Set<PetID> = []
    private var hoveredPets: Set<PetID> = []
    private var waitingForRemoteAgentPets: Set<PetID> = []
    private var activeInteraction: ActiveInteraction?
    private var motionTimer: Timer?
    private var ambientTimer: Timer?
    private var lastMotionTime = ProcessInfo.processInfo.systemUptime
    public var onInteractionCue: ((InteractionCue) -> Void)?

    public init(pets: [PetRuntimeState], visibleFrameProvider: @escaping VisibleFrameProvider) {
        self.visibleFrameProvider = visibleFrameProvider
        self.pets = Dictionary(uniqueKeysWithValues: pets.map { pet in
            var pet = pet
            pet.position = WorldMath.constrainedPoint(
                pet.position,
                to: visibleFrameProvider(pet.position)
            )
            return (pet.id, pet)
        })
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
        explicitMovementPets.remove(id)
        pet.position = WorldMath.constrainedPoint(
            position,
            to: visibleFrameProvider(position)
        )
        pet.activity = .idle
        pet.emotion = .content
        pets[id] = pet
        publish()
    }

    public func setVisiblePet(_ state: PetRuntimeState?, for id: PetID) {
        precondition(state == nil || state?.id == id, "Visible pet identity must match its slot")
        targets[id] = nil
        explicitMovementPets.remove(id)
        hoveredPets.remove(id)
        waitingForRemoteAgentPets.remove(id)

        if var state {
            state.position = WorldMath.constrainedPoint(
                state.position,
                to: visibleFrameProvider(state.position)
            )
            pets[id] = state
        } else {
            pets[id] = nil
        }

        if pets[.mine] == nil || pets[.partner] == nil {
            activeInteraction = nil
        }
        publish()
        stopMotionTimerIfNothingCanMove()
    }

    public func setPetHovering(_ id: PetID, isHovering: Bool) {
        guard pets[id] != nil else {
            hoveredPets.remove(id)
            return
        }

        if isHovering {
            guard hoveredPets.insert(id).inserted else { return }
            if targets[id] != nil, !explicitMovementPets.contains(id) {
                updatePet(id) { $0.activity = .idle }
            }
        } else {
            guard hoveredPets.remove(id) != nil else { return }
            if targets[id] != nil {
                updatePet(id) {
                    $0.activity = waitingForRemoteAgentPets.contains(id) ? .idle : .walking
                }
            }
            if activeInteraction != nil
                || (targets[id] != nil && !waitingForRemoteAgentPets.contains(id)) {
                ensureMotionTimer()
            }
        }

        publish()
        stopMotionTimerIfNothingCanMove()
    }

    /// Pauses only ambient movement while the owning client's Agent is offline
    /// or has not answered yet. Explicit interactions remain independent.
    public func setWaitingForRemoteAgent(_ id: PetID, isWaiting: Bool) {
        guard pets[id] != nil else {
            waitingForRemoteAgentPets.remove(id)
            return
        }
        if isWaiting {
            guard waitingForRemoteAgentPets.insert(id).inserted else { return }
            if targets[id] != nil {
                updatePet(id) { $0.activity = .idle }
            }
        } else {
            guard waitingForRemoteAgentPets.remove(id) != nil else { return }
            if targets[id] != nil {
                updatePet(id) { $0.activity = .walking }
                ensureMotionTimer()
            }
        }
        publish()
        stopMotionTimerIfNothingCanMove()
    }

    public func setPetEmotion(_ id: PetID, emotion: PetEmotion) {
        guard pets[id] != nil else { return }
        updatePet(id) { $0.emotion = emotion }
        publish()
    }

    public func walkAll() {
        guard activeInteraction == nil else { return }
        for id in PetID.allCases {
            scheduleWalk(for: id, isExplicit: true)
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
        explicitMovementPets.removeAll()
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
        explicitMovementPets.removeAll()
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
        explicitMovementPets.removeAll()
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
        scheduleWalk(
            for: .mine,
            to: CGPoint(x: centerX - 180, y: mine.position.y),
            isExplicit: true
        )
        scheduleWalk(
            for: .partner,
            to: CGPoint(x: centerX + 180, y: partner.position.y),
            isExplicit: true
        )
    }

    public func restorePetsToVisibleScreens() {
        targets.removeAll()
        explicitMovementPets.removeAll()
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
        switch partner.avatar.species {
        case .bunny:
            partner.avatar = partner.avatar == .partner ? .partnerAlternate : .partner
        case .cat:
            if partner.avatar == .mine {
                partner.avatar.bodyColor = .blush
                partner.avatar.eyeStyle = .happy
                partner.avatar.hat = .beanie
                partner.avatar.accessory = .scarf
            } else {
                partner.avatar = .mine
            }
        }
        pets[.partner] = partner
        publish()
    }

    private func scheduleAmbientWalks() {
        guard targets.isEmpty, activeInteraction == nil else { return }
        for id in PetID.allCases
        where !isAmbientMovementPaused(id) && Double.random(in: 0...1) < 0.45 {
            scheduleWalk(for: id, isExplicit: false)
        }
    }

    private func scheduleWalk(for id: PetID, isExplicit: Bool) {
        guard let pet = pets[id], pet.activity == .idle else { return }
        let frame = visibleFrameProvider(pet.position).insetBy(dx: 90, dy: 90)
        guard frame.width > 0, frame.height > 0 else { return }

        let target = CGPoint(
            x: CGFloat.random(in: frame.minX...frame.maxX),
            y: CGFloat.random(in: frame.minY...(frame.minY + min(120, frame.height)))
        )
        scheduleWalk(for: id, to: target, isExplicit: isExplicit)
    }

    private func scheduleWalk(for id: PetID, to target: CGPoint, isExplicit: Bool = false) {
        guard var pet = pets[id], pet.activity == .idle else { return }
        let constrainedTarget = WorldMath.constrainedPoint(
            target,
            to: visibleFrameProvider(pet.position),
            horizontalInset: 90,
            verticalInset: 90
        )
        targets[id] = constrainedTarget
        if isExplicit {
            explicitMovementPets.insert(id)
        } else {
            explicitMovementPets.remove(id)
        }
        pet.facing = constrainedTarget.x >= pet.position.x ? .right : .left
        pet.activity = isMovementPaused(id) ? .idle : .walking
        pet.emotion = .content
        pets[id] = pet
        publish()
        if !isMovementPaused(id) {
            ensureMotionTimer()
        }
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
        } else if activeInteraction == nil {
            tickAutonomousMotion(deltaTime: deltaTime)
        }

        publish()
        stopMotionTimerIfNothingCanMove()
    }

    private func tickAutonomousMotion(deltaTime: TimeInterval) {
        for (id, target) in targets {
            guard !isMovementPaused(id) else { continue }
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
                explicitMovementPets.remove(id)
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

    private func stopMotionTimerIfNothingCanMove() {
        let hasRunnableTarget = targets.keys.contains { !isMovementPaused($0) }
        let hasRunnableInteraction = activeInteraction != nil
        guard !hasRunnableTarget, !hasRunnableInteraction else { return }
        motionTimer?.invalidate()
        motionTimer = nil
    }

    private func publish() {
        onStateChange?(pets)
    }

    private func isAmbientMovementPaused(_ id: PetID) -> Bool {
        hoveredPets.contains(id) || waitingForRemoteAgentPets.contains(id)
    }

    private func isMovementPaused(_ id: PetID) -> Bool {
        waitingForRemoteAgentPets.contains(id)
            || (hoveredPets.contains(id) && !explicitMovementPets.contains(id))
    }
}
