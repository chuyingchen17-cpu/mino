import AppKit
import CoreGraphics
import Foundation
import Metal
import MinoDomain
@testable import MinoPresentation
import SpriteKit
import SwiftUI
import Testing

@MainActor
private final class FrameSceneHarness {
    let renderer: SKRenderer
    private var currentTime: TimeInterval = 100

    init(scene: SKScene) throws {
        renderer = SKRenderer(device: try #require(MTLCreateSystemDefaultDevice()))
        renderer.scene = scene
        // SKRenderer needs a clock tick before actions are attached. Actions
        // created before this first tick do not receive a usable start time.
        renderer.update(atTime: currentTime)
    }

    func establishActionStart() {
        renderer.update(atTime: currentTime)
    }

    func advance(by duration: TimeInterval) {
        currentTime += duration
        renderer.update(atTime: currentTime)
    }
}

@MainActor
private func frameTestState(
    clip: PetMotionClipID,
    playbackID: UUID? = nil,
    duration: TimeInterval? = nil
) -> PetRuntimeState {
    PetRuntimeState(
        id: .mine,
        displayName: "Mino",
        position: .zero,
        facing: .right,
        activity: .idle,
        emotion: .content,
        avatar: .mine,
        characterID: .malteseWhite,
        motionClipOverride: clip,
        motionDurationOverride: duration,
        motionPlaybackID: playbackID
    )
}

@MainActor
@Test
func officialCharacterPairSwiftUISurfaceRenders() throws {
    let preview = HStack(spacing: 20) {
        PetCharacterView(characterID: .malteseWhite, size: 180)
        PetCharacterView(characterID: .retrieverYellow, size: 180)
    }
    .padding(20)
    .background(Color.white)
    let renderer = ImageRenderer(content: preview)
    renderer.scale = 2
    let image = try #require(renderer.nsImage)
    #expect(image.size.width > 300)
    #expect(image.size.height > 150)

    if ProcessInfo.processInfo.environment["MINO_WRITE_CHARACTER_QA"] == "1",
       let tiff = image.tiffRepresentation,
       let bitmap = NSBitmapImageRep(data: tiff),
       let png = bitmap.representation(using: .png, properties: [:]) {
        try png.write(
            to: URL(fileURLWithPath: "/private/tmp/mino-character-rework.png"),
            options: .atomic
        )
    }
}

@MainActor
@Test
func everyClickRestartsPetReceiveWithoutMovingAnchorOrShadow() {
    let scene = PetScene(size: CGSize(width: 170, height: 180))
    let state = PetRuntimeState(
        id: .mine,
        displayName: "Mino",
        position: .zero,
        facing: .right,
        activity: .idle,
        emotion: .content,
        avatar: .mine,
        characterID: .malteseWhite
    )
    scene.render(state, reduceMotion: false)
    let initialStarts = scene.motionStartCountForTesting
    let anchor = scene.worldAnchorPositionForTesting
    let shadow = scene.shadowPositionForTesting
    let bodyContainer = scene.bodyContainerPositionForTesting

    scene.reactToClick(reduceMotion: false)
    let firstPlaybackID = scene.playbackIDForTesting
    scene.reactToClick(reduceMotion: false)

    #expect(scene.renderedClipForTesting == .petReceive)
    #expect(scene.motionStartCountForTesting == initialStarts + 2)
    #expect(scene.playbackIDForTesting != firstPlaybackID)
    #expect(scene.lastMotionDurationForTesting == 0.72)
    #expect(scene.worldAnchorPositionForTesting == anchor)
    #expect(scene.shadowPositionForTesting == shadow)
    #expect(scene.bodyContainerPositionForTesting == bodyContainer)
}

@MainActor
@Test
func reducedMotionClickStillPresentsStaticPetReceiveFeedback() {
    let scene = PetScene(size: CGSize(width: 170, height: 180))
    let state = PetRuntimeState(
        id: .mine,
        displayName: "Mino",
        position: .zero,
        facing: .right,
        activity: .idle,
        emotion: .content,
        avatar: .mine,
        characterID: .malteseWhite
    )
    scene.render(state, reduceMotion: true)
    let initialStarts = scene.motionStartCountForTesting

    scene.reactToClick(reduceMotion: true)

    #expect(scene.renderedClipForTesting == .petReceive)
    #expect(scene.motionStartCountForTesting == initialStarts + 1)
    #expect(scene.lastMotionDurationForTesting == nil)
}

@MainActor
@Test
func sceneDoesNotRestartSameWalkClipAndHonorsReactionDuration() {
    let scene = PetScene(size: CGSize(width: 170, height: 180))
    var state = PetRuntimeState(
        id: .mine,
        displayName: "Mino",
        position: .zero,
        facing: .right,
        activity: .walking,
        emotion: .content,
        avatar: .mine,
        characterID: .malteseWhite
    )
    let plan = PetReactionPlan(
        speech: "走走",
        activity: .walking,
        emotion: .content,
        motionClip: .walk,
        duration: 3.4
    )
    scene.render(state, reactionPlan: plan)
    let initialStarts = scene.motionStartCountForTesting
    let worldAnchor = scene.worldAnchorPositionForTesting
    let shadow = scene.shadowPositionForTesting
    let bodyContainer = scene.bodyContainerPositionForTesting

    state.emotion = .happy
    scene.render(state, reactionPlan: plan)

    #expect(scene.renderedClipForTesting == .walk)
    #expect(scene.motionStartCountForTesting == initialStarts)
    #expect(scene.lastMotionDurationForTesting == 3.4)
    #expect(scene.worldAnchorPositionForTesting == worldAnchor)
    #expect(scene.shadowPositionForTesting == shadow)
    #expect(scene.bodyContainerPositionForTesting == bodyContainer)

    state.motionClipOverride = .happy
    state.motionDurationOverride = 4.2
    scene.render(state)
    #expect(scene.renderedClipForTesting == .happy)
    #expect(scene.lastMotionDurationForTesting == 4.2)
}

@MainActor
@Test
func aNewPlaybackIDRestartsTheSameSemanticClip() {
    let scene = PetScene(size: CGSize(width: 170, height: 180))
    var state = PetRuntimeState(
        id: .mine,
        displayName: "Mino",
        position: .zero,
        facing: .right,
        activity: .petting,
        emotion: .happy,
        avatar: .mine,
        characterID: .malteseWhite,
        motionClipOverride: .petReceive,
        motionDurationOverride: 2.4,
        motionPlaybackID: UUID()
    )
    scene.render(state, reduceMotion: false)
    let firstStarts = scene.motionStartCountForTesting

    state.emotion = .content
    scene.render(state, reduceMotion: false)
    #expect(scene.motionStartCountForTesting == firstStarts)

    state.motionPlaybackID = UUID()
    scene.render(state, reduceMotion: false)
    #expect(scene.motionStartCountForTesting == firstStarts + 1)
    #expect(scene.lastMotionDurationForTesting == 2.4)
}

@MainActor
@Test
func realScenePlaybackAdvancesAllRuntimePathsWithoutMovingAnchors() throws {
    let scene = PetScene(size: CGSize(width: 170, height: 180))
    let harness = try FrameSceneHarness(scene: scene)
    scene.render(frameTestState(clip: .idle), reduceMotion: false)
    harness.establishActionStart()
    let worldAnchor = scene.worldAnchorPositionForTesting
    let bodyContainer = scene.bodyContainerPositionForTesting
    let shadow = scene.shadowPositionForTesting
    let sprite = scene.frameSpritePositionForTesting

    for clip in [PetMotionClipID.idle, .walk] {
        let animation = try #require(
            PetFrameAnimationCatalog.shared.animation(for: .malteseWhite, clip: clip)
        )
        scene.render(frameTestState(clip: clip), reduceMotion: false)
        harness.establishActionStart()
        let initialTexture = try #require(scene.currentTextureForTesting)
        #expect(initialTexture === animation.textures[0])
        #expect(scene.hasActiveFrameMotionForTesting)
        harness.advance(by: animation.frameDuration * 1.25)
        let advancedTexture = try #require(scene.currentTextureForTesting)
        #expect(advancedTexture !== initialTexture)
        #expect(animation.textures.dropFirst().contains { $0 === advancedTexture })
    }

    let petAnimation = try #require(
        PetFrameAnimationCatalog.shared.animation(for: .malteseWhite, clip: .petReceive)
    )
    for _ in 0..<2 {
        scene.reactToClick(reduceMotion: false)
        harness.establishActionStart()
        #expect(scene.currentTextureForTesting === petAnimation.textures[0])
        #expect(scene.hasActiveFrameMotionForTesting)
        harness.advance(by: 0.72 / Double(petAnimation.textures.count) * 1.25)
        let advancedTexture = try #require(scene.currentTextureForTesting)
        #expect(petAnimation.textures.dropFirst().contains { $0 === advancedTexture })
    }

    let petState = frameTestState(clip: .petReceive)
    scene.render(petState, reduceMotion: true)
    harness.establishActionStart()
    let reducedTexture = try #require(scene.currentTextureForTesting)
    #expect(reducedTexture === petAnimation.reduceMotionTexture)
    #expect(!scene.hasActiveFrameMotionForTesting)
    harness.advance(by: 0.35)
    #expect(scene.currentTextureForTesting === reducedTexture)

    scene.render(petState, reduceMotion: false, motionProgress: 0)
    #expect(scene.currentTextureForTesting === petAnimation.textures[0])
    #expect(!scene.hasActiveFrameMotionForTesting)
    scene.render(petState, reduceMotion: false, motionProgress: 0.63)
    #expect(scene.currentTextureForTesting === petAnimation.textures[2])
    #expect(!scene.hasActiveFrameMotionForTesting)

    #expect(scene.worldAnchorPositionForTesting == worldAnchor)
    #expect(scene.bodyContainerPositionForTesting == bodyContainer)
    #expect(scene.shadowPositionForTesting == shadow)
    #expect(scene.frameSpritePositionForTesting == sprite)
}
