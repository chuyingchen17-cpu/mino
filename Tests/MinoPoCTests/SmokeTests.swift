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
