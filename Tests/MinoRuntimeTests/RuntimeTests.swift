import Testing
import CoreGraphics
import MinoDomain

@testable import MinoRuntime

@Test
func movementStopsExactlyAtTarget() {
    let result = WorldMath.movedPoint(
        from: .zero,
        toward: CGPoint(x: 3, y: 4),
        speed: 10,
        deltaTime: 1
    )

    #expect(result.point == CGPoint(x: 3, y: 4))
    #expect(result.arrived)
}

@Test
func movementUsesDeltaTime() {
    let result = WorldMath.movedPoint(
        from: .zero,
        toward: CGPoint(x: 100, y: 0),
        speed: 20,
        deltaTime: 0.5
    )

    #expect(result.point == CGPoint(x: 10, y: 0))
    #expect(!result.arrived)
}

@Test
func constrainedPointKeepsTheWholePetInsideItsAssignedRegion() {
    let frame = CGRect(x: 100, y: 50, width: 600, height: 400)

    #expect(
        WorldMath.constrainedPoint(
            CGPoint(x: -500, y: 900),
            to: frame
        ) == CGPoint(x: 190, y: 355)
    )
}

@MainActor
@Test
func worldConstrainsInitialIncomingAndDraggedPetsToItsVisibleFrame() {
    let assignedFrame = CGRect(x: 0, y: 0, width: 500, height: 500)
    let mine = PetRuntimeState(
        id: .mine,
        displayName: "奶糖",
        position: CGPoint(x: -200, y: -200),
        facing: .right,
        activity: .idle,
        emotion: .content,
        avatar: .mine
    )
    let world = PetWorld(pets: [mine]) { _ in assignedFrame }

    #expect(world.pets[.mine]?.position == CGPoint(x: 90, y: 95))

    world.movePet(.mine, to: CGPoint(x: 2_000, y: 2_000))
    #expect(world.pets[.mine]?.position == CGPoint(x: 410, y: 405))

    world.setVisiblePet(
        PetRuntimeState(
            id: .partner,
            displayName: "团子",
            position: CGPoint(x: -1_000, y: 2_000),
            facing: .left,
            activity: .idle,
            emotion: .content,
            avatar: .partner
        ),
        for: .partner
    )
    #expect(world.pets[.partner]?.position == CGPoint(x: 90, y: 405))
}

@MainActor
@Test
func visiblePetSetFollowsVisitPresence() {
    let mine = PetRuntimeState(
        id: .mine,
        displayName: "奶糖",
        position: CGPoint(x: 100, y: 100),
        facing: .right,
        activity: .idle,
        emotion: .content,
        avatar: .mine
    )
    let partner = PetRuntimeState(
        id: .partner,
        displayName: "团子",
        position: CGPoint(x: 300, y: 100),
        facing: .left,
        activity: .idle,
        emotion: .content,
        avatar: .partner
    )
    let world = PetWorld(pets: [mine]) { _ in
        CGRect(x: 0, y: 0, width: 800, height: 600)
    }

    #expect(world.pets[.mine] != nil)
    #expect(world.pets[.partner] == nil)

    world.setVisiblePet(partner, for: .partner)
    #expect(world.pets[.mine] != nil)
    #expect(world.pets[.partner]?.displayName == "团子")

    world.setVisiblePet(nil, for: .mine)
    #expect(world.pets[.mine] == nil)
    #expect(world.pets[.partner]?.displayName == "团子")

    world.setVisiblePet(nil, for: .partner)
    #expect(world.pets.isEmpty)
}

@MainActor
@Test
func partnerAppearanceTogglePreservesTheVisitingPetsSpecies() {
    let visitingCat = PetRuntimeState(
        id: .partner,
        displayName: "奶糖",
        position: CGPoint(x: 300, y: 100),
        facing: .left,
        activity: .idle,
        emotion: .content,
        avatar: .mine
    )
    let world = PetWorld(pets: [visitingCat]) { _ in
        CGRect(x: 0, y: 0, width: 800, height: 600)
    }

    world.togglePartnerAppearance()

    #expect(world.pets[.partner]?.avatar.species == .cat)
    #expect(world.pets[.partner]?.avatar != .mine)
}

@MainActor
@Test
func hoveringDoesNotPauseAnExplicitQueuedWalk() {
    let mine = PetRuntimeState(
        id: .mine,
        displayName: "奶糖",
        position: CGPoint(x: 100, y: 100),
        facing: .right,
        activity: .idle,
        emotion: .content,
        avatar: .mine
    )
    let world = PetWorld(pets: [mine]) { _ in
        CGRect(x: 0, y: 0, width: 800, height: 600)
    }
    defer { world.stop() }

    world.walkAll()
    #expect(world.pets[.mine]?.activity == .walking)

    world.setPetHovering(.mine, isHovering: true)
    #expect(world.pets[.mine]?.activity == .walking)

    world.setPetHovering(.mine, isHovering: false)
    #expect(world.pets[.mine]?.activity == .walking)
}

@MainActor
@Test
func visitingPetNapsUntilItsRemoteAgentResponds() {
    let visitor = PetRuntimeState(
        id: .partner,
        displayName: "团子",
        position: CGPoint(x: 300, y: 100),
        facing: .left,
        activity: .idle,
        emotion: .content,
        avatar: .partner
    )
    let world = PetWorld(pets: [visitor]) { _ in
        CGRect(x: 0, y: 0, width: 800, height: 600)
    }
    defer { world.stop() }

    world.setWaitingForRemoteAgent(.partner, isWaiting: true)
    world.walkAll()
    #expect(world.pets[.partner]?.activity == .idle)

    world.setPetHovering(.partner, isHovering: true)
    world.setPetHovering(.partner, isHovering: false)
    #expect(world.pets[.partner]?.activity == .idle)

    world.setWaitingForRemoteAgent(.partner, isWaiting: false)
    #expect(world.pets[.partner]?.activity == .walking)
}

@MainActor
@Test
func explicitInteractionKeepsRunningWhilePetIsHovered() async throws {
    let mine = PetRuntimeState(
        id: .mine,
        displayName: "奶糖",
        position: CGPoint(x: 100, y: 100),
        facing: .right,
        activity: .idle,
        emotion: .content,
        avatar: .mine
    )
    let partner = PetRuntimeState(
        id: .partner,
        displayName: "团子",
        position: CGPoint(x: 500, y: 100),
        facing: .left,
        activity: .idle,
        emotion: .content,
        avatar: .partner
    )
    let world = PetWorld(pets: [mine, partner]) { _ in
        CGRect(x: 0, y: 0, width: 800, height: 600)
    }
    defer { world.stop() }

    world.setPetHovering(.mine, isHovering: true)
    world.triggerKiss()
    try await Task.sleep(for: .milliseconds(120))

    #expect(world.pets[.mine]?.position != mine.position)
    #expect(world.pets[.partner]?.position != partner.position)
}

@MainActor
@Test
func explicitWalkKeepsRunningWhilePetIsHovered() async throws {
    let mine = PetRuntimeState(
        id: .mine,
        displayName: "奶糖",
        position: CGPoint(x: 100, y: 100),
        facing: .right,
        activity: .idle,
        emotion: .content,
        avatar: .mine
    )
    let world = PetWorld(pets: [mine]) { _ in
        CGRect(x: 0, y: 0, width: 800, height: 600)
    }
    defer { world.stop() }

    world.setPetHovering(.mine, isHovering: true)
    world.walkAll()
    try await Task.sleep(for: .milliseconds(120))

    #expect(world.pets[.mine]?.activity == .walking)
    #expect(world.pets[.mine]?.position != mine.position)
}

@Test
func kissInteractionApproachesThenEmitsEffectAndCompletes() {
    var mine = PetRuntimeState(
        id: .mine,
        displayName: "奶糖",
        position: CGPoint(x: 100, y: 100),
        facing: .left,
        activity: .idle,
        emotion: .content,
        avatar: .mine
    )
    var partner = PetRuntimeState(
        id: .partner,
        displayName: "团子",
        position: CGPoint(x: 500, y: 100),
        facing: .right,
        activity: .idle,
        emotion: .content,
        avatar: .partner
    )
    var interaction = KissInteractionSession(
        mine: mine,
        partner: partner,
        visibleFrame: CGRect(x: 0, y: 0, width: 800, height: 600)
    )

    var cue: InteractionCue?
    for _ in 0..<200 where cue == nil {
        cue = interaction.advance(mine: &mine, partner: &partner, deltaTime: 1.0 / 30.0).cue
    }

    #expect(cue != nil)
    #expect(mine.facing == .right)
    #expect(partner.facing == .left)
    #expect(mine.activity == .interacting)
    #expect(partner.activity == .interacting)
    #expect(mine.emotion == .shy)
    #expect(partner.emotion == .happy)

    let completion = interaction.advance(mine: &mine, partner: &partner, deltaTime: 2)
    #expect(completion.completed)
    #expect(mine.activity == .idle)
    #expect(partner.activity == .idle)
    #expect(mine.emotion == .content)
    #expect(partner.emotion == .content)
}

@Test
func flowerInteractionHasDistinctOfferPoseAndCompletionEmotion() {
    var mine = PetRuntimeState(
        id: .mine,
        displayName: "奶糖",
        position: CGPoint(x: 100, y: 100),
        facing: .left,
        activity: .idle,
        emotion: .content,
        avatar: .mine
    )
    var partner = PetRuntimeState(
        id: .partner,
        displayName: "团子",
        position: CGPoint(x: 500, y: 100),
        facing: .right,
        activity: .idle,
        emotion: .content,
        avatar: .partner
    )
    var interaction = FlowerInteractionSession(
        mine: mine,
        partner: partner,
        visibleFrame: CGRect(x: 0, y: 0, width: 800, height: 600)
    )

    var cue: InteractionCue?
    for _ in 0..<200 where cue == nil {
        cue = interaction.advance(mine: &mine, partner: &partner, deltaTime: 1.0 / 30.0).cue
    }

    guard case .flowerGift = cue else {
        Issue.record("Expected the flower gift cue")
        return
    }
    #expect(mine.emotion == .happy)
    #expect(partner.emotion == .shy)

    let completion = interaction.advance(mine: &mine, partner: &partner, deltaTime: 3)
    #expect(completion.completed)
    #expect(mine.emotion == .content)
    #expect(partner.emotion == .happy)
}
