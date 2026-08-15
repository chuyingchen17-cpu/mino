import Foundation
import Testing

@testable import MinoDomain

@Test
func alternateAvatarChangesIndependentParts() {
    #expect(AvatarRecipe.partner.bodyColor != AvatarRecipe.partnerAlternate.bodyColor)
    #expect(AvatarRecipe.partner.eyeStyle != AvatarRecipe.partnerAlternate.eyeStyle)
    #expect(AvatarRecipe.partner.hat != AvatarRecipe.partnerAlternate.hat)
    #expect(AvatarRecipe.partner.accessory != AvatarRecipe.partnerAlternate.accessory)
}

@Test
func avatarRecipeRoundTripsThroughJSON() throws {
    let data = try JSONEncoder().encode(AvatarRecipe.partner)
    let decoded = try JSONDecoder().decode(AvatarRecipe.self, from: data)

    #expect(decoded == .partner)
}
