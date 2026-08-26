import CoreGraphics
import MinoDomain
import Testing

@testable import MinoRuntime

@Test
func screenEdgePointsStayOnTheSelectedScreenAndOutsideItsVisibleBounds() {
    let secondScreen = CGRect(x: 1_000, y: 40, width: 900, height: 700)
    let reference = CGPoint(x: 1_240, y: 80)

    #expect(
        WorldMath.screenEdgePoint(
            .left,
            nearestTo: reference,
            in: secondScreen
        ) == CGPoint(x: 910, y: 135)
    )
    #expect(
        WorldMath.screenEdgePoint(
            .right,
            nearestTo: reference,
            in: secondScreen
        ) == CGPoint(x: 1_990, y: 135)
    )
}

@Test
func companionPointUsesTheSideWithRoomAndRemainsFullyVisible() {
    let frame = CGRect(x: 1_000, y: 40, width: 900, height: 700)

    #expect(
        WorldMath.companionPoint(
            beside: CGPoint(x: 1_650, y: 145),
            in: frame
        ) == CGPoint(x: 1_460, y: 145)
    )
    #expect(
        WorldMath.companionPoint(
            beside: CGPoint(x: 1_200, y: 145),
            in: frame
        ) == CGPoint(x: 1_390, y: 145)
    )
}

@MainActor
@Test
func realEntranceWalksFromTheEdgeAndCompletesBesideTheHost() {
    let frame = CGRect(x: 0, y: 0, width: 800, height: 600)
    let mine = runtimePet(.mine, position: CGPoint(x: 300, y: 120))
    let visitor = runtimePet(.partner, position: .zero)
    let world = PetWorld(pets: [mine]) { _ in frame }
    defer { world.stop() }
    var completed = false

    world.animatePetEntering(visitor, beside: .mine, from: .left) {
        completed = true
    }

    #expect(world.pets[.partner]?.position == CGPoint(x: -90, y: 120))
    #expect(world.pets[.partner]?.activity == .walking)
    #expect(!completed)

    world.advanceMotionForTesting(deltaTime: 10)

    #expect(completed)
    #expect(world.pets[.partner]?.position == CGPoint(x: 490, y: 120))
    #expect(world.pets[.partner]?.activity == .idle)
    #expect(world.pets[.mine]?.facing == .right)
    #expect(world.pets[.partner]?.facing == .left)
}

@MainActor
@Test
func realExitKeepsStateUntilTheAuthoritativeOwnerRemovesIt() {
    let frame = CGRect(x: 0, y: 0, width: 800, height: 600)
    let visitor = runtimePet(.partner, position: CGPoint(x: 500, y: 120))
    let world = PetWorld(pets: [visitor]) { _ in frame }
    defer { world.stop() }
    var completed = false

    world.animatePetExiting(.partner, toward: .right) {
        completed = true
    }
    #expect(world.pets[.partner]?.activity == .walking)

    world.advanceMotionForTesting(deltaTime: 10)

    #expect(completed)
    #expect(world.pets[.partner]?.position == CGPoint(x: 890, y: 120))
    #expect(world.pets[.partner] != nil)

    world.walkAll()
    #expect(world.pets[.partner]?.position == CGPoint(x: 890, y: 120))

    world.setVisiblePet(nil, for: .partner)
    #expect(world.pets[.partner] == nil)
}

@MainActor
@Test
func reduceMotionEntranceUsesTheAnchorsScreenAndCompletesImmediately() {
    let firstScreen = CGRect(x: 0, y: 0, width: 900, height: 700)
    let secondScreen = CGRect(x: 1_000, y: 40, width: 900, height: 700)
    let mine = runtimePet(.mine, position: CGPoint(x: 1_250, y: 150))
    let visitor = runtimePet(.partner, position: .zero)
    let world = PetWorld(pets: [mine]) { point in
        point.x >= secondScreen.minX ? secondScreen : firstScreen
    }
    var completed = false

    world.animatePetEntering(visitor, beside: .mine, reduceMotion: true) {
        completed = true
    }

    #expect(completed)
    #expect(world.pets[.partner]?.position == CGPoint(x: 1_440, y: 150))
    #expect(world.pets[.partner]?.activity == .idle)
    #expect(secondScreen.contains(world.pets[.partner]?.position ?? .zero))
}

private func runtimePet(_ id: PetID, position: CGPoint) -> PetRuntimeState {
    PetRuntimeState(
        id: id,
        displayName: id == .mine ? "奶糖" : "团子",
        position: position,
        facing: id == .mine ? .right : .left,
        activity: .idle,
        emotion: .content,
        avatar: id == .mine ? .mine : .partner
    )
}
