import AppKit
import Foundation
import MinoDomain
@testable import MinoPresentation
import SpriteKit
import Testing

private struct SourceFrame: Equatable {
    let index: Int
    let url: URL
}

private struct VisiblePixelBounds {
    let minX: Int
    let minY: Int
    let maxX: Int
    let maxY: Int

    var width: Int { maxX - minX + 1 }
    var height: Int { maxY - minY + 1 }
}

private enum PetFrameSourceTree {
    static let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    static let root = repositoryRoot
        .appendingPathComponent("Sources/MinoPresentation/Resources/PetFrames", isDirectory: true)

    static func frames(
        character: PetCharacterID,
        clip: PetMotionClipID
    ) throws -> [SourceFrame] {
        let directory = root
            .appendingPathComponent(character.rawValue, isDirectory: true)
            .appendingPathComponent(clip.rawValue, isDirectory: true)
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        return try urls.map { url in
            let name = url.lastPathComponent
            guard name.hasPrefix("frame-"), name.hasSuffix(".png") else {
                throw FrameSourceError.invalidFilename(name)
            }
            let start = name.index(name.startIndex, offsetBy: 6)
            let end = name.index(name.endIndex, offsetBy: -4)
            let digits = String(name[start..<end])
            guard digits.count == 3, let index = Int(digits) else {
                throw FrameSourceError.invalidFilename(name)
            }
            return SourceFrame(index: index, url: url)
        }
        .sorted { $0.index < $1.index }
    }

    static func directoryNames(at url: URL) throws -> Set<String> {
        let urls = try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        return try Set(urls.compactMap { child in
            let values = try child.resourceValues(forKeys: [.isDirectoryKey])
            return values.isDirectory == true ? child.lastPathComponent : nil
        })
    }

    static func visibleBounds(in bitmap: NSBitmapImageRep) -> VisiblePixelBounds? {
        var minX = bitmap.pixelsWide
        var minY = bitmap.pixelsHigh
        var maxX = -1
        var maxY = -1
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide
                where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.10 {
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return VisiblePixelBounds(minX: minX, minY: minY, maxX: maxX, maxY: maxY)
    }

    enum FrameSourceError: Error, CustomStringConvertible {
        case invalidFilename(String)

        var description: String {
            switch self {
            case .invalidFilename(let name):
                "Unexpected file in PetFrames tree: \(name)"
            }
        }
    }
}

@Test
func idleFramesKeepACompleteBodyAndSeparatedFeetAtTheSharedAnchor() throws {
    for character in PetCharacterID.allCases {
        for frame in try PetFrameSourceTree.frames(character: character, clip: .idle) {
            let bitmap = try #require(NSBitmapImageRep(
                data: Data(contentsOf: frame.url)
            ))
            let bounds = try #require(PetFrameSourceTree.visibleBounds(in: bitmap))
            #expect(
                bounds.height >= 60 && Double(bounds.height) / Double(bounds.width) >= 0.85,
                "Idle silhouette must include the torso and legs, not only a head: \(frame.url.path)"
            )
            #expect(
                (99...102).contains(bounds.maxY),
                "Idle feet must finish at the shared y=102 ground band: \(frame.url.path)"
            )

            let footRows = max(bounds.minY, bounds.maxY - 5)...bounds.maxY
            let hasSeparatedFeet = footRows.contains { y in
                let leftFoot = (bounds.minX..<56).contains {
                    (bitmap.colorAt(x: $0, y: y)?.alphaComponent ?? 0) > 0.10
                }
                let rightFoot = (65...bounds.maxX).contains {
                    (bitmap.colorAt(x: $0, y: y)?.alphaComponent ?? 0) > 0.10
                }
                let centerGap = (56...64).allSatisfy {
                    (bitmap.colorAt(x: $0, y: y)?.alphaComponent ?? 0) <= 0.10
                }
                return leftFoot && rightFoot && centerGap
            }
            #expect(
                hasSeparatedFeet,
                "Idle ground contact must show two feet instead of a cropped head edge: \(frame.url.path)"
            )
        }
    }
}

@Test
func petFrameSourceTreeContainsEveryCharacterAndClipWithContiguousIndices() throws {
    var isDirectory: ObjCBool = false
    #expect(FileManager.default.fileExists(
        atPath: PetFrameSourceTree.root.path,
        isDirectory: &isDirectory
    ))
    #expect(isDirectory.boolValue)

    let manifest = try JSONDecoder().decode(
        PetFrameAnimationManifest.self,
        from: Data(contentsOf: PetFrameSourceTree.root.appendingPathComponent("manifest.json"))
    )
    let minimumFrames = Dictionary(uniqueKeysWithValues: manifest.clips.map { ($0.id, $0.minimumFrames) })

    #expect(
        try PetFrameSourceTree.directoryNames(at: PetFrameSourceTree.root)
            == Set(PetCharacterID.allCases.map(\.rawValue)),
        "PetFrames must not contain undeclared character directories"
    )

    for character in PetCharacterID.allCases {
        let characterDirectory = PetFrameSourceTree.root
            .appendingPathComponent(character.rawValue, isDirectory: true)
        #expect(
            try PetFrameSourceTree.directoryNames(at: characterDirectory)
                == Set(PetMotionClipID.allCases.map(\.rawValue)),
            "Unexpected or missing clip directories for \(character.rawValue)"
        )
        for clip in PetMotionClipID.allCases {
            let frames = try PetFrameSourceTree.frames(character: character, clip: clip)
            #expect(!frames.isEmpty, "Missing \(character.rawValue)/\(clip.rawValue) frames")
            #expect(
                frames.count >= (minimumFrames[clip] ?? .max),
                "Too few frames for \(character.rawValue)/\(clip.rawValue)"
            )
            #expect(
                frames.map(\.index) == Array(0..<frames.count),
                "Frame numbers must be contiguous from frame-000 for \(character.rawValue)/\(clip.rawValue)"
            )
            let encodedFrames = try frames.map { try Data(contentsOf: $0.url) }
            #expect(
                Set(encodedFrames).count >= 2,
                "Clip must contain visible frame progression, not duplicated stills: \(character.rawValue)/\(clip.rawValue)"
            )
        }
    }
}

@Test
func frameManifestDefinesEveryClipExactlyOnceAndValidStaticFrameIndices() throws {
    let manifestURL = PetFrameSourceTree.root.appendingPathComponent("manifest.json")
    let manifest = try JSONDecoder().decode(
        PetFrameAnimationManifest.self,
        from: Data(contentsOf: manifestURL)
    )
    #expect(manifest.schema == 1)
    #expect(manifest.canvas == PetFrameCanvasManifest(width: 120, height: 120))
    #expect(manifest.groundAnchor == PetFrameGroundAnchorManifest(x: 60, y: 102))
    #expect(manifest.clips.count == PetMotionClipID.allCases.count)
    #expect(Set(manifest.clips.map(\.id)) == Set(PetMotionClipID.allCases))

    for clip in manifest.clips {
        #expect(clip.framesPerSecond > 0)
        #expect(clip.minimumFrames > 0)
        #expect(clip.reduceMotionFrameIndex >= 0)
        #expect(clip.reduceMotionFrameIndex < clip.minimumFrames)
    }
}

@Test
func everySourceFrameIsTransparentPNGOnTheSharedCanvasAndDoesNotTouchEdges() throws {
    let pngSignature = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    let groundAnchorY = 102

    for character in PetCharacterID.allCases {
        for clip in PetMotionClipID.allCases {
            for frame in try PetFrameSourceTree.frames(character: character, clip: clip) {
                let data = try Data(contentsOf: frame.url)
                #expect(data.prefix(pngSignature.count) == pngSignature[...])
                let bitmap = try #require(NSBitmapImageRep(data: data))
                #expect(bitmap.pixelsWide == 120, "Wrong width: \(frame.url.path)")
                #expect(bitmap.pixelsHigh == 120, "Wrong height: \(frame.url.path)")
                #expect(bitmap.hasAlpha, "Frame must preserve an alpha channel: \(frame.url.path)")

                let edgePixels = (0..<120).flatMap { coordinate in
                    [
                        bitmap.colorAt(x: coordinate, y: 0),
                        bitmap.colorAt(x: coordinate, y: 119),
                        bitmap.colorAt(x: 0, y: coordinate),
                        bitmap.colorAt(x: 119, y: coordinate)
                    ]
                }
                #expect(
                    edgePixels.allSatisfy { ($0?.alphaComponent ?? 0) <= 0.01 },
                    "Non-transparent content touches the fixed canvas edge: \(frame.url.path)"
                )

                // Props and tails can live outside the body's horizontal span,
                // but the central character mass/feet must never sink below
                // the manifest's shared ground anchor.
                let belowGroundPixels = ((groundAnchorY + 1)..<120).flatMap { y in
                    (24..<96).map { x in bitmap.colorAt(x: x, y: y) }
                }
                #expect(
                    belowGroundPixels.allSatisfy { ($0?.alphaComponent ?? 0) <= 0.01 },
                    "Character body extends below the shared y=102 ground anchor: \(frame.url.path)"
                )

                let footContactBand = ((groundAnchorY - 4)...groundAnchorY).flatMap { y in
                    (24..<96).map { x in bitmap.colorAt(x: x, y: y) }
                }
                #expect(
                    footContactBand.contains { ($0?.alphaComponent ?? 0) > 0.10 },
                    "Character has no central foot contact near the shared ground anchor: \(frame.url.path)"
                )
            }
        }
    }
}

@MainActor
@Test
func packagedFrameCatalogCoversEveryClipAndUsesOneCanvasAndGroundAnchor() throws {
    let catalog = PetFrameAnimationCatalog.shared

    for character in PetCharacterID.allCases {
        #expect(catalog.hasCompleteFrames(for: character))
        #expect(catalog.missingClips(for: character).isEmpty)
        for clip in PetMotionClipID.allCases {
            let animation = try #require(catalog.animation(for: character, clip: clip))
            #expect(!animation.textures.isEmpty)
            #expect(animation.canvasSize == CGSize(width: 120, height: 120))
            #expect(animation.groundAnchor == CGPoint(x: 60, y: 102))
            #expect(animation.frameDuration > 0)
            #expect(animation.reduceMotionFrameIndex >= 0)
            #expect(animation.reduceMotionFrameIndex < animation.textures.count)
            #expect(animation.textures.allSatisfy { $0.filteringMode == .nearest })
        }
    }
}

@MainActor
@Test
func reduceMotionResolvesTheClipSpecificStaticFrame() throws {
    for character in PetCharacterID.allCases {
        for clip in PetMotionClipID.allCases {
            let animation = try #require(
                PetFrameAnimationCatalog.shared.animation(for: character, clip: clip)
            )
            let first = PetCharacterFrameResolver.resolve(
                for: character,
                clip: clip,
                progress: 0,
                reduceMotion: true
            )
            let later = PetCharacterFrameResolver.resolve(
                for: character,
                clip: clip,
                progress: 0.91,
                reduceMotion: true
            )
            #expect(first.kind == .exact)
            #expect(later.kind == .exact)
            #expect(first.frameIndex == animation.reduceMotionFrameIndex)
            #expect(later.frameIndex == animation.reduceMotionFrameIndex)
            let firstImage = try #require(first.image)
            let laterImage = try #require(later.image)
            #expect(firstImage === laterImage)
        }
    }
}

@MainActor
@Test
func defaultSpriteKitRendererUsesRasterFramesAndNeverBuildsVectorBodyShapes() throws {
    let node = PetAvatarNode()

    for character in PetCharacterID.allCases {
        for clip in PetMotionClipID.allCases {
            node.apply(
                characterID: character,
                clip: clip,
                facing: .right,
                playbackID: UUID(),
                reduceMotion: false
            )

            let sprites = node.bodyContainer.children.compactMap { $0 as? SKSpriteNode }
            let vectorShapes = node.bodyContainer.children.compactMap { $0 as? SKShapeNode }
            #expect(node.renderingBackend == .rasterFrames)
            #expect(sprites.count == 1)
            #expect(vectorShapes.isEmpty)
            #expect(sprites.allSatisfy { $0.texture?.filteringMode == .nearest })
            let sprite = try #require(sprites.first)
            #expect(sprite.size == CGSize(width: 120, height: 120))
            #expect(sprite.anchorPoint == CGPoint(x: 0.5, y: 0.5))
            #expect(sprite.position == .zero)

            let animation = try #require(
                PetFrameAnimationCatalog.shared.animation(for: character, clip: clip)
            )
            let renderedGroundY = sprite.position.y
                + animation.canvasSize.height / 2
                - animation.groundAnchor.y
            #expect(renderedGroundY == -42)
        }
    }
}

@Test
func productRendererEntryPointsDoNotReferenceTheLegacyVectorRig() throws {
    let presentationRoot = PetFrameSourceTree.repositoryRoot
        .appendingPathComponent("Sources/MinoPresentation", isDirectory: true)
    let avatarNodeSource = try String(
        contentsOf: presentationRoot.appendingPathComponent("PetAvatarNode.swift"),
        encoding: .utf8
    )
    #expect(!avatarNodeSource.contains("PetVectorGeometry"))
    #expect(!avatarNodeSource.contains("PetCharacterVectorCatalog"))
    #expect(!avatarNodeSource.contains("ensureVectorCompatibilityRenderer"))

    let characterSystemSource = try String(
        contentsOf: presentationRoot.appendingPathComponent("PetCharacterSystem.swift"),
        encoding: .utf8
    )
    let viewStart = try #require(characterSystemSource.range(of: "public struct PetCharacterView"))
    let resolverStart = try #require(
        characterSystemSource.range(
            of: "package enum PetCharacterFrameResolutionKind",
            range: viewStart.upperBound..<characterSystemSource.endIndex
        )
    )
    let productViewSource = characterSystemSource[viewStart.lowerBound..<resolverStart.lowerBound]
    #expect(!productViewSource.contains("PetVector"))
}
