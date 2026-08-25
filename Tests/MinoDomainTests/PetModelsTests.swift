import Foundation
import MinoDomain
import Testing

@Test
func petActivityAndEmotionRoundTripThroughJSON() throws {
    let activity = try JSONEncoder().encode(PetActivity.offeringGift)
    #expect(try JSONDecoder().decode(PetActivity.self, from: activity) == .offeringGift)

    let emotion = try JSONEncoder().encode(PetEmotion.sleepy)
    #expect(try JSONDecoder().decode(PetEmotion.self, from: emotion) == .sleepy)
}
