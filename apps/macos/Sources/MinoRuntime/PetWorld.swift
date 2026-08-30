import AppKit
import CoreGraphics
import Foundation
import MinoDomain
import QuartzCore

public enum PetWorldScreenEdge: Equatable, Sendable {
    case nearest
    case left
    case right
}

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

    public static func screenEdgePoint(
        _ edge: PetWorldScreenEdge,
        nearestTo reference: CGPoint,
        in frame: CGRect,
        outsideOffset: CGFloat = 90,
        verticalInset: CGFloat = 95
    ) -> CGPoint {
        let resolvedEdge: PetWorldScreenEdge
        switch edge {
        case .nearest:
            resolvedEdge = reference.x - frame.minX <= frame.maxX - reference.x ? .left : .right
        case .left, .right:
            resolvedEdge = edge
        }

        let safeReference = constrainedPoint(
            reference,
            to: frame,
            horizontalInset: 0,
            verticalInset: verticalInset
        )
        let offset = max(outsideOffset, 0)
        let x = resolvedEdge == .left ? frame.minX - offset : frame.maxX + offset
        return CGPoint(x: x, y: safeReference.y)
    }

    public static func companionPoint(
        beside anchor: CGPoint,
        in frame: CGRect,
        separation: CGFloat = 190,
        horizontalInset: CGFloat = 90,
        verticalInset: CGFloat = 95
    ) -> CGPoint {
        let safeAnchor = constrainedPoint(
            anchor,
            to: frame,
            horizontalInset: horizontalInset,
            verticalInset: verticalInset
        )
        let safeHorizontalInset = min(max(horizontalInset, 0), max(frame.width / 2, 0))
        let bounds = frame.insetBy(dx: safeHorizontalInset, dy: 0)
        let spacing = max(separation, 0)
        let rightRoom = max(bounds.maxX - safeAnchor.x, 0)
        let leftRoom = max(safeAnchor.x - bounds.minX, 0)
        let x: CGFloat
        if rightRoom >= spacing || rightRoom >= leftRoom {
            x = min(safeAnchor.x + spacing, bounds.maxX)
        } else {
            x = max(safeAnchor.x - spacing, bounds.minX)
        }
        return CGPoint(x: x, y: safeAnchor.y)
    }
}

@MainActor
public final class PetWorld: NSObject {
    public typealias VisibleFrameProvider = (CGPoint) -> CGRect

    public private(set) var pets: [PetID: PetRuntimeState]
    public var onStateChange: (([PetID: PetRuntimeState]) -> Void)?

    private let visibleFrameProvider: VisibleFrameProvider
    private var targets: [PetID: CGPoint] = [:]
    private var explicitMovementPets: Set<PetID> = []
    private var hoveredPets: Set<PetID> = []
    private var waitingForRemoteAgentPets: Set<PetID> = []
    private var transientActivityTokens: [PetID: UUID] = [:]
    private var movementTransitions: [PetID: MovementTransition] = [:]
    private var parkedOffscreenPets: Set<PetID> = []
    private var activeInteraction: ActivePairedInteraction?
    private var motionDisplayLink: CADisplayLink?
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
        super.init()
    }

    /// 宠物只在被交互时才动，不会自己在桌面上漫游，所以这里没有环境定时器：
    /// 位置完全由拖拽和显式动作决定，静止时连运动 display link 都不会启动。
    public func start() {
        publish()
    }

    public func stop() {
        motionDisplayLink?.invalidate()
        motionDisplayLink = nil
    }

    public func movePet(_ id: PetID, to position: CGPoint) {
        guard activeInteraction == nil, var pet = pets[id] else { return }
        cancelMovement(for: id)
        parkedOffscreenPets.remove(id)
        pet.position = WorldMath.constrainedPoint(
            position,
            to: visibleFrameProvider(position)
        )
        pet.activity = .idle
        pet.emotion = .content
        pets[id] = pet
        publish()
    }

    public func setDisplayName(_ name: String, for id: PetID) {
        guard var pet = pets[id] else { return }
        pet.displayName = name
        pets[id] = pet
        publish()
    }

    public func setCharacter(_ characterID: PetCharacterID, for id: PetID) {
        guard var pet = pets[id], pet.characterID != characterID else { return }
        pet.characterID = characterID
        pets[id] = pet
        publish()
    }

    public func setVisiblePet(_ state: PetRuntimeState?, for id: PetID) {
        precondition(state == nil || state?.id == id, "Visible pet identity must match its slot")
        cancelMovement(for: id)
        hoveredPets.remove(id)
        waitingForRemoteAgentPets.remove(id)
        parkedOffscreenPets.remove(id)

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

    /// Adds a pet at the edge of the screen containing `destination`, then moves
    /// it into the visible region. The pet remains in the authoritative world
    /// state for the entire transition.
    public func animatePetEntering(
        _ state: PetRuntimeState,
        toward destination: CGPoint,
        from edge: PetWorldScreenEdge = .nearest,
        facing companionID: PetID? = nil,
        reduceMotion: Bool = false,
        completion: (() -> Void)? = nil
    ) {
        let frame = visibleFrameProvider(destination)
        let target = WorldMath.constrainedPoint(destination, to: frame)
        beginPetEntrance(
            state,
            target: target,
            frame: frame,
            edge: edge,
            companionID: companionID,
            reduceMotion: reduceMotion,
            completion: completion
        )
    }

    /// Places an arriving pet beside an existing pet and leaves both pets facing
    /// one another after the walk-in completes.
    public func animatePetEntering(
        _ state: PetRuntimeState,
        beside anchorID: PetID,
        separation: CGFloat = 190,
        from edge: PetWorldScreenEdge = .nearest,
        reduceMotion: Bool = false,
        completion: (() -> Void)? = nil
    ) {
        guard let anchor = pets[anchorID] else {
            animatePetEntering(
                state,
                toward: state.position,
                from: edge,
                reduceMotion: reduceMotion,
                completion: completion
            )
            return
        }
        let frame = visibleFrameProvider(anchor.position)
        let target = WorldMath.companionPoint(
            beside: anchor.position,
            in: frame,
            separation: separation
        )
        beginPetEntrance(
            state,
            target: target,
            frame: frame,
            edge: edge,
            companionID: anchorID,
            reduceMotion: reduceMotion,
            completion: completion
        )
    }

    /// Moves a pet fully beyond its current screen edge. The state is retained
    /// after completion so the caller can reconcile visibility with server state.
    public func animatePetExiting(
        _ id: PetID,
        toward edge: PetWorldScreenEdge = .nearest,
        reduceMotion: Bool = false,
        completion: (() -> Void)? = nil
    ) {
        guard var pet = pets[id] else {
            completion?()
            return
        }
        activeInteraction = nil
        cancelMovement(for: id)
        waitingForRemoteAgentPets.remove(id)
        parkedOffscreenPets.remove(id)
        let frame = visibleFrameProvider(pet.position)
        let target = WorldMath.screenEdgePoint(edge, nearestTo: pet.position, in: frame)
        pet.facing = target.x >= pet.position.x ? .right : .left
        pet.activity = reduceMotion ? .idle : .walking
        pet.emotion = .content

        if reduceMotion {
            pet.position = target
            pets[id] = pet
            parkedOffscreenPets.insert(id)
            publish()
            completion?()
            return
        }

        pets[id] = pet
        targets[id] = target
        explicitMovementPets.insert(id)
        movementTransitions[id] = MovementTransition(
            companionID: nil,
            parksOffscreen: true,
            completion: completion
        )
        publish()
        ensureMotionTimer()
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
                updatePet(id) { pet in
                    if waitingForRemoteAgentPets.contains(id) {
                        pet.activity = .sleeping
                        pet.emotion = .sleepy
                    } else {
                        pet.activity = .walking
                    }
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
            transientActivityTokens[id] = nil
            return
        }
        if isWaiting {
            guard waitingForRemoteAgentPets.insert(id).inserted else { return }
            transientActivityTokens[id] = nil
            if targets[id] != nil {
                updatePet(id) {
                    $0.activity = .sleeping
                    $0.emotion = .sleepy
                }
            } else {
                updatePet(id) {
                    $0.activity = .sleeping
                    $0.emotion = .sleepy
                }
            }
        } else {
            guard waitingForRemoteAgentPets.remove(id) != nil else { return }
            if targets[id] != nil {
                updatePet(id) {
                    $0.activity = .walking
                    $0.emotion = .content
                }
                ensureMotionTimer()
            } else {
                updatePet(id) {
                    $0.activity = .idle
                    $0.emotion = .content
                }
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

    public func performLocalActivity(
        _ id: PetID,
        activity: PetActivity,
        emotion: PetEmotion? = nil,
        duration: TimeInterval = 1.2,
        motionClip: PetMotionClipID? = nil
    ) {
        guard
            activeInteraction == nil,
            var pet = pets[id],
            !waitingForRemoteAgentPets.contains(id),
            !parkedOffscreenPets.contains(id)
        else {
            return
        }
        cancelMovement(for: id)
        let token = UUID()
        transientActivityTokens[id] = token
        pet.activity = activity
        pet.motionClipOverride = motionClip
        pet.motionDurationOverride = duration
        pet.motionPlaybackID = token
        if let emotion {
            pet.emotion = emotion
        }
        pets[id] = pet
        publish()

        Task { @MainActor [weak self] in
            do {
                let nanoseconds = UInt64((max(0, duration) * 1_000_000_000).rounded())
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                return
            }
            self?.finishTransientActivity(for: id, token: token, activity: activity)
        }
    }

    public func walkAll() {
        guard activeInteraction == nil else { return }
        for id in PetID.allCases {
            scheduleWalk(for: id, isExplicit: true)
        }
    }

    public func performPairedInteraction(
        _ choreography: PairedPetChoreography,
        giver: PetID = .mine,
        receiver: PetID = .partner
    ) {
        guard
            activeInteraction == nil,
            giver != receiver,
            let giverState = pets[giver],
            let receiverState = pets[receiver],
            !parkedOffscreenPets.contains(giver),
            !parkedOffscreenPets.contains(receiver)
        else {
            return
        }

        targets.removeAll()
        explicitMovementPets.removeAll()
        transientActivityTokens.removeAll()
        movementTransitions.removeAll()
        let visibleFrame = visibleFrameProvider(giverState.position)
        activeInteraction = ActivePairedInteraction(
            giverID: giver,
            receiverID: receiver,
            session: PairedPetInteractionSession(
                choreography: choreography,
                giver: giverState,
                receiver: receiverState,
                visibleFrame: visibleFrame
            )
        )
        ensureMotionTimer()
    }

    public func triggerKiss() {
        performPairedInteraction(.kissHeart)
    }

    public func triggerFlowerGift() {
        performPairedInteraction(.flowerGift)
    }

    public func resetPetPositions() {
        guard let anchor = pets[.mine]?.position else { return }
        let frame = visibleFrameProvider(anchor).insetBy(dx: 120, dy: 105)
        guard frame.width > 0, frame.height > 0 else { return }

        targets.removeAll()
        explicitMovementPets.removeAll()
        transientActivityTokens.removeAll()
        movementTransitions.removeAll()
        parkedOffscreenPets.removeAll()
        activeInteraction = nil
        let center = CGPoint(x: frame.midX, y: frame.minY + min(35, frame.height / 2))
        updatePet(.mine) { pet in
            pet.position = CGPoint(x: center.x - 150, y: center.y)
            pet.facing = .right
            pet.activity = .idle
            pet.emotion = .content
            pet.motionClipOverride = nil
            pet.motionDurationOverride = nil
            pet.motionPlaybackID = nil
        }
        updatePet(.partner) { pet in
            pet.position = CGPoint(x: center.x + 150, y: center.y)
            pet.facing = .left
            pet.activity = .idle
            pet.emotion = .content
            pet.motionClipOverride = nil
            pet.motionDurationOverride = nil
            pet.motionPlaybackID = nil
        }
        publish()
    }

    public func restorePetsToVisibleScreens() {
        targets.removeAll()
        explicitMovementPets.removeAll()
        transientActivityTokens.removeAll()
        movementTransitions.removeAll()
        parkedOffscreenPets.removeAll()
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
                pet.motionClipOverride = nil
                pet.motionDurationOverride = nil
                pet.motionPlaybackID = nil
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

    private func scheduleWalk(for id: PetID, isExplicit: Bool) {
        guard let pet = pets[id] else { return }
        guard !parkedOffscreenPets.contains(id) else { return }
        guard pet.activity == .idle || (pet.activity == .sleeping && waitingForRemoteAgentPets.contains(id)) else {
            return
        }
        let frame = visibleFrameProvider(pet.position).insetBy(dx: 90, dy: 90)
        guard frame.width > 0, frame.height > 0 else { return }

        // 只在当前高度上左右走。桌面上没有可见地面，一旦纵向移动就会被看成
        // 悬空起跳，而 walk 动画本身也只画了侧向迈步。
        let target = CGPoint(
            x: CGFloat.random(in: frame.minX...frame.maxX),
            y: pet.position.y
        )
        scheduleWalk(for: id, to: target, isExplicit: isExplicit)
    }

    private func scheduleWalk(for id: PetID, to target: CGPoint, isExplicit: Bool = false) {
        guard var pet = pets[id] else { return }
        guard !parkedOffscreenPets.contains(id) else { return }
        guard pet.activity == .idle || (pet.activity == .sleeping && waitingForRemoteAgentPets.contains(id)) else {
            return
        }
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
        if isMovementPaused(id) {
            if waitingForRemoteAgentPets.contains(id) {
                pet.activity = .sleeping
                pet.emotion = .sleepy
            }
        } else {
            pet.activity = .walking
            pet.emotion = .content
        }
        pets[id] = pet
        publish()
        if !isMovementPaused(id) {
            ensureMotionTimer()
        }
    }

    private func beginPetEntrance(
        _ state: PetRuntimeState,
        target: CGPoint,
        frame: CGRect,
        edge: PetWorldScreenEdge,
        companionID: PetID?,
        reduceMotion: Bool,
        completion: (() -> Void)?
    ) {
        activeInteraction = nil
        cancelMovement(for: state.id)
        hoveredPets.remove(state.id)
        waitingForRemoteAgentPets.remove(state.id)
        parkedOffscreenPets.remove(state.id)
        if let companionID, companionID != state.id {
            cancelMovement(for: companionID)
            updatePet(companionID) {
                $0.activity = .idle
                $0.emotion = .happy
            }
        }

        var entering = state
        entering.position = reduceMotion
            ? target
            : WorldMath.screenEdgePoint(edge, nearestTo: target, in: frame)
        entering.facing = target.x >= entering.position.x ? .right : .left
        entering.activity = reduceMotion ? .idle : .walking
        entering.emotion = .excited
        pets[state.id] = entering

        if reduceMotion {
            facePets(state.id, and: companionID)
            publish()
            completion?()
            return
        }

        targets[state.id] = target
        explicitMovementPets.insert(state.id)
        movementTransitions[state.id] = MovementTransition(
            companionID: companionID,
            parksOffscreen: false,
            completion: completion
        )
        publish()
        ensureMotionTimer()
    }

    private func cancelMovement(for id: PetID) {
        targets[id] = nil
        explicitMovementPets.remove(id)
        transientActivityTokens[id] = nil
        movementTransitions[id] = nil
        updatePet(id) {
            $0.motionClipOverride = nil
            $0.motionDurationOverride = nil
            $0.motionPlaybackID = nil
        }
    }

    private func facePets(_ firstID: PetID, and secondID: PetID?) {
        guard
            let secondID,
            firstID != secondID,
            var first = pets[firstID],
            var second = pets[secondID]
        else {
            return
        }
        first.facing = second.position.x >= first.position.x ? .right : .left
        second.facing = first.position.x >= second.position.x ? .right : .left
        first.activity = .idle
        second.activity = .idle
        first.emotion = .happy
        second.emotion = .happy
        first.motionClipOverride = nil
        second.motionClipOverride = nil
        first.motionDurationOverride = nil
        second.motionDurationOverride = nil
        first.motionPlaybackID = nil
        second.motionPlaybackID = nil
        pets[firstID] = first
        pets[secondID] = second
    }

    private func updatePet(_ id: PetID, update: (inout PetRuntimeState) -> Void) {
        guard var pet = pets[id] else { return }
        update(&pet)
        pets[id] = pet
    }

    private func finishTransientActivity(
        for id: PetID,
        token: UUID,
        activity: PetActivity
    ) {
        guard transientActivityTokens[id] == token else { return }
        transientActivityTokens[id] = nil
        guard
            !waitingForRemoteAgentPets.contains(id),
            pets[id]?.activity == activity
        else {
            return
        }
        updatePet(id) {
            $0.activity = .idle
            $0.emotion = .content
            $0.motionClipOverride = nil
            $0.motionDurationOverride = nil
            $0.motionPlaybackID = nil
        }
        publish()
    }

    private func ensureMotionTimer() {
        guard motionDisplayLink == nil else { return }
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        lastMotionTime = ProcessInfo.processInfo.systemUptime
        let displayLink = screen.displayLink(
            target: self,
            selector: #selector(displayLinkDidFire(_:))
        )
        displayLink.preferredFrameRateRange = CAFrameRateRange(
            minimum: 60,
            maximum: 60,
            preferred: 60
        )
        displayLink.add(to: .main, forMode: .common)
        motionDisplayLink = displayLink
    }

    @objc
    private func displayLinkDidFire(_ displayLink: CADisplayLink) {
        let now = displayLink.timestamp
        let deltaTime = min(0.1, now - lastMotionTime)
        lastMotionTime = now

        if deltaTime > 0 {
            advanceMotion(deltaTime: deltaTime)
        }
    }

    private func advanceMotion(deltaTime: TimeInterval) {
        var completions: [() -> Void] = []
        if activeInteraction != nil {
            tickInteraction(deltaTime: deltaTime)
        } else if activeInteraction == nil {
            completions = tickAutonomousMotion(deltaTime: deltaTime)
        }

        publish()
        stopMotionTimerIfNothingCanMove()
        completions.forEach { $0() }
    }

    private func tickAutonomousMotion(deltaTime: TimeInterval) -> [() -> Void] {
        var completions: [() -> Void] = []
        for (id, target) in targets {
            guard !isMovementPaused(id) else { continue }
            guard var pet = pets[id] else { continue }
            let result = WorldMath.movedPoint(
                from: pet.position,
                toward: target,
                speed: movementTransitions[id] == nil ? 85 : 240,
                deltaTime: deltaTime
            )
            pet.position = result.point
            var arrivedCompanionID: PetID?
            if result.arrived {
                pet.activity = .idle
                targets[id] = nil
                explicitMovementPets.remove(id)
                transientActivityTokens[id] = nil
                if let transition = movementTransitions.removeValue(forKey: id) {
                    arrivedCompanionID = transition.companionID
                    if transition.parksOffscreen {
                        parkedOffscreenPets.insert(id)
                    }
                    if let completion = transition.completion {
                        completions.append(completion)
                    }
                }
            }
            pets[id] = pet
            if result.arrived {
                facePets(id, and: arrivedCompanionID)
            }
        }
        return completions
    }

    private func tickInteraction(deltaTime: TimeInterval) {
        guard
            var interaction = activeInteraction,
            var giver = pets[interaction.giverID],
            var receiver = pets[interaction.receiverID]
        else {
            activeInteraction = nil
            return
        }

        let advance = interaction.session.advance(
            giver: &giver,
            receiver: &receiver,
            deltaTime: deltaTime
        )
        pets[interaction.giverID] = giver
        pets[interaction.receiverID] = receiver

        if let cue = advance.cue {
            onInteractionCue?(cue)
        }
        activeInteraction = advance.completed ? nil : interaction
    }

    private func stopMotionTimerIfNothingCanMove() {
        let hasRunnableTarget = targets.keys.contains { !isMovementPaused($0) }
        let hasRunnableInteraction = activeInteraction != nil
        guard !hasRunnableTarget, !hasRunnableInteraction else { return }
        motionDisplayLink?.invalidate()
        motionDisplayLink = nil
    }

    private func publish() {
        onStateChange?(pets)
    }

    private func isMovementPaused(_ id: PetID) -> Bool {
        waitingForRemoteAgentPets.contains(id)
            || (hoveredPets.contains(id) && !explicitMovementPets.contains(id))
    }

    package func advanceMotionForTesting(deltaTime: TimeInterval) {
        motionDisplayLink?.invalidate()
        motionDisplayLink = nil
        advanceMotion(deltaTime: deltaTime)
    }

    private struct MovementTransition {
        let companionID: PetID?
        let parksOffscreen: Bool
        let completion: (() -> Void)?
    }
}
