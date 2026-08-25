import MinoDomain
import Testing

@Test
func catalogTwoAppearanceRoundTripsAndLegacyRemainsUnselected() {
    for character in PetCharacterID.allCases {
        #expect(PetCharacterID(appearance: character.appearance) == character)
        #expect(character.appearance["rigID"] == "maltese-pair-v1")
        #expect(character.appearance["body"] == character.rawValue)
    }
    #expect(PetCharacterID(appearance: ["rigID": "mino-default", "body": "default"]) == nil)
    #expect(PetCharacterID.appearanceSchema == 1)
    #expect(PetCharacterID.appearanceCatalog == 2)
}

@Test
func rigManifestDefinesOneCanvasGroundAndEveryReduceMotionPose() {
    let manifest = PetRigManifest.maltesePairV1
    #expect(manifest.canvas == PetRigSize(width: 120, height: 120))
    #expect(manifest.groundAnchor == PetRigPoint(x: 60, y: 102))
    #expect(Set(manifest.parts.map(\.id)) == Set(PetRigPartID.allCases))
    #expect(Set(manifest.reduceMotionPose.keys) == Set(PetMotionClipID.allCases))
    #expect(manifest.mirrorStrategy == .bodyContainer)
}

@Test
func motionResolverKeepsEveryInteractionAndVisitSemanticDistinct() {
    #expect(PetMotionResolver.resolve(
        activity: .playing,
        emotion: .playful,
        interaction: .cuddle,
        role: .giver
    ) == .cuddleGive)
    #expect(PetMotionResolver.resolve(
        activity: .playing,
        emotion: .playful,
        interaction: .cuddle,
        role: .receiver
    ) == .cuddleReceive)
    #expect(PetMotionResolver.resolve(
        activity: .offeringGift,
        emotion: .grateful,
        interaction: .flower,
        role: .giver
    ) == .flowerGive)
    #expect(PetMotionResolver.resolve(
        activity: .offeringGift,
        emotion: .grateful,
        interaction: .flower,
        role: .receiver
    ) == .flowerReceive)
    #expect(PetMotionResolver.resolve(
        activity: .eating,
        emotion: .content,
        interaction: .feed,
        outcome: .tooFull
    ) == .fullRefuse)
    #expect(PetMotionResolver.resolve(
        activity: .playing,
        emotion: .content,
        interaction: .walk,
        outcome: .tooTired
    ) == .tiredRefuse)
    #expect(PetMotionResolver.resolve(
        activity: .walking,
        emotion: .happy,
        interaction: .walk
    ) == .walk)
    #expect(PetMotionResolver.resolve(
        activity: .idle,
        emotion: .content,
        visitPhase: .walkingIn
    ) == .walk)
    #expect(PetMotionResolver.resolve(
        activity: .idle,
        emotion: .content,
        visitPhase: .welcome
    ) == .welcome)
    #expect(PetMotionResolver.resolve(
        activity: .idle,
        emotion: .content,
        visitPhase: .waveGoodbye
    ) == .wave)
    #expect(PetMotionResolver.resolve(
        activity: .idle,
        emotion: .content,
        semanticAction: .letter
    ) == .letterGive)
}
