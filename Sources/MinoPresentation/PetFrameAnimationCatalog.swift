import AppKit
import MinoDomain
import SpriteKit

public struct PetFrameCanvasManifest: Codable, Equatable, Sendable {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

public struct PetFrameGroundAnchorManifest: Codable, Equatable, Sendable {
    public let x: Int
    public let y: Int

    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }
}

public struct PetFrameClipManifest: Codable, Equatable, Sendable {
    public let id: PetMotionClipID
    public let framesPerSecond: Double
    public let loops: Bool
    public let reduceMotionFrameIndex: Int
    public let minimumFrames: Int

    public init(
        id: PetMotionClipID,
        framesPerSecond: Double,
        loops: Bool,
        reduceMotionFrameIndex: Int,
        minimumFrames: Int
    ) {
        self.id = id
        self.framesPerSecond = framesPerSecond
        self.loops = loops
        self.reduceMotionFrameIndex = reduceMotionFrameIndex
        self.minimumFrames = minimumFrames
    }
}

public struct PetFrameAnimationManifest: Codable, Equatable, Sendable {
    public let schema: Int
    public let canvas: PetFrameCanvasManifest
    public let groundAnchor: PetFrameGroundAnchorManifest
    public let clips: [PetFrameClipManifest]

    public init(
        schema: Int,
        canvas: PetFrameCanvasManifest,
        groundAnchor: PetFrameGroundAnchorManifest,
        clips: [PetFrameClipManifest]
    ) {
        self.schema = schema
        self.canvas = canvas
        self.groundAnchor = groundAnchor
        self.clips = clips
    }
}

/// A validated fixed-canvas frame clip. PNGs contain only the character and
/// effects; the runtime-owned shadow deliberately remains outside every frame.
@MainActor
public struct PetFrameAnimation {
    public let characterID: PetCharacterID
    public let clip: PetMotionClipID
    public let images: [NSImage]
    public let textures: [SKTexture]
    public let frameDuration: TimeInterval
    public let loops: Bool
    public let reduceMotionFrameIndex: Int
    public let canvasSize: CGSize
    public let groundAnchor: CGPoint

    public var reduceMotionImage: NSImage {
        images[reduceMotionFrameIndex]
    }

    public var reduceMotionTexture: SKTexture {
        textures[reduceMotionFrameIndex]
    }

    public func image(progress rawProgress: Double, reduceMotion: Bool = false) -> NSImage {
        images[frameIndex(progress: rawProgress, reduceMotion: reduceMotion)]
    }

    public func texture(progress rawProgress: Double, reduceMotion: Bool = false) -> SKTexture {
        textures[frameIndex(progress: rawProgress, reduceMotion: reduceMotion)]
    }

    public func frameIndex(progress rawProgress: Double, reduceMotion: Bool = false) -> Int {
        guard !reduceMotion else { return reduceMotionFrameIndex }
        let progress: Double
        if loops {
            progress = rawProgress - floor(rawProgress)
        } else {
            progress = min(1, max(0, rawProgress))
        }
        return min(images.count - 1, Int(progress * Double(images.count)))
    }
}

/// Loads the product frame assets once and rejects incomplete or off-canvas
/// clips. This is the default renderer catalog for SpriteKit and SwiftUI.
@MainActor
public final class PetFrameAnimationCatalog {
    public static let shared = PetFrameAnimationCatalog()

    public let manifest: PetFrameAnimationManifest?
    public let rootURL: URL?
    private var cache: [PetCharacterID: [PetMotionClipID: PetFrameAnimation]] = [:]
    private(set) public var validationFailures: [String] = []

    public convenience init() {
        // A signed macOS application may only seal resources inside Contents.
        // Prefer the assembled app's standard Resources/PetFrames location;
        // SwiftPM tests and direct `swift run` builds continue to use .module.
        let appFrames = Bundle.main.resourceURL?
            .appendingPathComponent("PetFrames", isDirectory: true)
        if let appFrames,
           FileManager.default.fileExists(
               atPath: appFrames.appendingPathComponent("manifest.json").path
           ) {
            self.init(rootURL: appFrames)
        } else {
            self.init(bundle: .module)
        }
    }

    public convenience init(bundle: Bundle) {
        let resourceRoot = bundle.resourceURL
        let nestedRoot = resourceRoot?.appendingPathComponent("PetFrames", isDirectory: true)
        let root = nestedRoot.flatMap {
            FileManager.default.fileExists(atPath: $0.path) ? $0 : nil
        } ?? resourceRoot
        self.init(rootURL: root)
    }

    public init(rootURL: URL?) {
        self.rootURL = rootURL
        guard
            let rootURL,
            let data = try? Data(contentsOf: rootURL.appendingPathComponent("manifest.json")),
            let decoded = try? JSONDecoder().decode(PetFrameAnimationManifest.self, from: data),
            decoded.schema == 1,
            decoded.canvas == PetFrameCanvasManifest(width: 120, height: 120)
        else {
            manifest = nil
            validationFailures.append("PetFrames/manifest.json is missing or invalid")
            return
        }
        manifest = decoded
        loadAllFrames(rootURL: rootURL, manifest: decoded)
    }

    public func animation(
        for characterID: PetCharacterID,
        clip: PetMotionClipID
    ) -> PetFrameAnimation? {
        cache[characterID]?[clip]
    }

    public func frame(
        for characterID: PetCharacterID,
        clip: PetMotionClipID,
        progress: Double,
        reduceMotion: Bool = false
    ) -> NSImage? {
        animation(for: characterID, clip: clip)?.image(
            progress: progress,
            reduceMotion: reduceMotion
        )
    }

    public func supports(_ clip: PetMotionClipID, for characterID: PetCharacterID) -> Bool {
        animation(for: characterID, clip: clip) != nil
    }

    public func missingClips(for characterID: PetCharacterID) -> [PetMotionClipID] {
        PetMotionClipID.allCases.filter { !supports($0, for: characterID) }
    }

    public func hasCompleteFrames(for characterID: PetCharacterID) -> Bool {
        missingClips(for: characterID).isEmpty
    }

    private func loadAllFrames(rootURL: URL, manifest: PetFrameAnimationManifest) {
        let clipManifests = Dictionary(
            uniqueKeysWithValues: manifest.clips.map { ($0.id, $0) }
        )
        for characterID in PetCharacterID.allCases {
            for clip in PetMotionClipID.allCases {
                guard let clipManifest = clipManifests[clip] else {
                    validationFailures.append("manifest has no metadata for \(clip.rawValue)")
                    continue
                }
                if let animation = loadAnimation(
                    rootURL: rootURL,
                    characterID: characterID,
                    clipManifest: clipManifest,
                    manifest: manifest
                ) {
                    cache[characterID, default: [:]][clip] = animation
                }
            }
        }
    }

    private func loadAnimation(
        rootURL: URL,
        characterID: PetCharacterID,
        clipManifest: PetFrameClipManifest,
        manifest: PetFrameAnimationManifest
    ) -> PetFrameAnimation? {
        let directory = rootURL
            .appendingPathComponent(characterID.rawValue, isDirectory: true)
            .appendingPathComponent(clipManifest.id.rawValue, isDirectory: true)
        guard let frameURLs = contiguousFrameURLs(in: directory) else {
            validationFailures.append(
                "\(characterID.rawValue)/\(clipManifest.id.rawValue) has non-contiguous frame names"
            )
            return nil
        }
        guard frameURLs.count >= clipManifest.minimumFrames else {
            validationFailures.append(
                "\(characterID.rawValue)/\(clipManifest.id.rawValue) needs at least \(clipManifest.minimumFrames) frames"
            )
            return nil
        }

        var images: [NSImage] = []
        images.reserveCapacity(frameURLs.count)
        for frameURL in frameURLs {
            guard
                let data = try? Data(contentsOf: frameURL),
                let bitmap = NSBitmapImageRep(data: data),
                bitmap.pixelsWide == manifest.canvas.width,
                bitmap.pixelsHigh == manifest.canvas.height,
                bitmap.hasAlpha,
                hasTransparentCanvasEdges(bitmap)
            else {
                validationFailures.append(
                    "\(frameURL.lastPathComponent) must be a transparent 120x120 PNG whose content stays inside the canvas"
                )
                return nil
            }
            let image = NSImage(
                size: CGSize(width: manifest.canvas.width, height: manifest.canvas.height)
            )
            image.addRepresentation(bitmap)
            images.append(image)
        }

        let textures = images.map { image -> SKTexture in
            let texture = SKTexture(image: image)
            texture.filteringMode = .nearest
            return texture
        }
        return PetFrameAnimation(
            characterID: characterID,
            clip: clipManifest.id,
            images: images,
            textures: textures,
            frameDuration: 1 / max(1, clipManifest.framesPerSecond),
            loops: clipManifest.loops,
            reduceMotionFrameIndex: min(
                max(0, clipManifest.reduceMotionFrameIndex),
                images.count - 1
            ),
            canvasSize: CGSize(width: manifest.canvas.width, height: manifest.canvas.height),
            groundAnchor: CGPoint(x: manifest.groundAnchor.x, y: manifest.groundAnchor.y)
        )
    }

    private func contiguousFrameURLs(in directory: URL) -> [URL]? {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        let pngs = urls
            .filter { $0.pathExtension.lowercased() == "png" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for (index, url) in pngs.enumerated() where url.lastPathComponent != frameName(index) {
            return nil
        }
        return pngs
    }

    private func frameName(_ index: Int) -> String {
        String(format: "frame-%03d.png", index)
    }

    private func hasTransparentCanvasEdges(_ bitmap: NSBitmapImageRep) -> Bool {
        let lastX = bitmap.pixelsWide - 1
        let lastY = bitmap.pixelsHigh - 1
        for x in 0...lastX {
            if (bitmap.colorAt(x: x, y: 0)?.alphaComponent ?? 0) > 0.01
                || (bitmap.colorAt(x: x, y: lastY)?.alphaComponent ?? 0) > 0.01 {
                return false
            }
        }
        for y in 0...lastY {
            if (bitmap.colorAt(x: 0, y: y)?.alphaComponent ?? 0) > 0.01
                || (bitmap.colorAt(x: lastX, y: y)?.alphaComponent ?? 0) > 0.01 {
                return false
            }
        }
        return true
    }
}
