import Testing
import CoreGraphics

@testable import MinoPoC

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
func alternateAvatarChangesIndependentParts() {
    #expect(AvatarRecipe.partner.bodyColor != AvatarRecipe.partnerAlternate.bodyColor)
    #expect(AvatarRecipe.partner.eyeStyle != AvatarRecipe.partnerAlternate.eyeStyle)
    #expect(AvatarRecipe.partner.hat != AvatarRecipe.partnerAlternate.hat)
    #expect(AvatarRecipe.partner.accessory != AvatarRecipe.partnerAlternate.accessory)
}

@Test
func kissInteractionApproachesThenEmitsEffectAndCompletes() {
    var mine = PetRuntimeState(
        id: .mine,
        position: CGPoint(x: 100, y: 100),
        facing: .left,
        activity: .idle,
        avatar: .mine
    )
    var partner = PetRuntimeState(
        id: .partner,
        position: CGPoint(x: 500, y: 100),
        facing: .right,
        activity: .idle,
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

    let completion = interaction.advance(mine: &mine, partner: &partner, deltaTime: 2)
    #expect(completion.completed)
    #expect(mine.activity == .idle)
    #expect(partner.activity == .idle)
}
