import AppKit
import MinoDomain
import SpriteKit
import SwiftUI

public struct PetPartPose: Equatable, Sendable {
    public var offset: CGPoint
    public var rotation: CGFloat
    public var scaleX: CGFloat
    public var scaleY: CGFloat
    public var opacity: CGFloat

    public init(
        offset: CGPoint = .zero,
        rotation: CGFloat = 0,
        scaleX: CGFloat = 1,
        scaleY: CGFloat = 1,
        opacity: CGFloat = 1
    ) {
        self.offset = offset
        self.rotation = rotation
        self.scaleX = scaleX
        self.scaleY = scaleY
        self.opacity = opacity
    }

    public static let identity = PetPartPose()
}

public struct PetMotionPose: Equatable, Sendable {
    public let parts: [PetRigPartID: PetPartPose]

    public init(parts: [PetRigPartID: PetPartPose] = [:]) {
        self.parts = parts
    }

    public subscript(_ part: PetRigPartID) -> PetPartPose {
        parts[part] ?? .identity
    }
}

/// Deterministic key-pose sampler shared by the SpriteKit and SwiftUI surfaces.
/// The walk clip never transforms the torso, its container, or the shadow.
public enum PetMotionPoseSampler {
    public static func pose(
        for clip: PetMotionClipID,
        progress rawProgress: Double,
        reduceMotion: Bool = false
    ) -> PetMotionPose {
        let progress = reduceMotion ? 0.25 : rawProgress - floor(rawProgress)
        let wave = CGFloat(sin(progress * .pi * 2))
        let pulse = CGFloat((1 - cos(progress * .pi * 2)) / 2)

        func headGroup(
            offset: CGPoint = .zero,
            rotation: CGFloat = 0,
            scaleX: CGFloat = 1,
            scaleY: CGFloat = 1
        ) -> [PetRigPartID: PetPartPose] {
            let pose = PetPartPose(
                offset: offset,
                rotation: rotation,
                scaleX: scaleX,
                scaleY: scaleY
            )
            return [.head: pose, .leftEar: pose, .rightEar: pose, .face: pose]
        }

        var parts: [PetRigPartID: PetPartPose] = [
            .heartEffect: PetPartPose(opacity: 0),
            .flowerEffect: PetPartPose(opacity: 0),
            .letterEffect: PetPartPose(opacity: 0)
        ]
        switch clip {
        case .idle:
            if !reduceMotion {
                parts.merge(headGroup(offset: CGPoint(x: 0, y: wave * 0.7))) { _, new in new }
                parts[.tail] = PetPartPose(rotation: wave * 0.10)
                parts[.leftEar] = PetPartPose(offset: CGPoint(x: 0, y: wave * 0.7), rotation: wave * 0.025)
                parts[.rightEar] = PetPartPose(offset: CGPoint(x: 0, y: wave * 0.7), rotation: -wave * 0.025)
            }

        case .walk:
            // No body/head translation or scale: the visible torso baseline is invariant.
            // Legs slide on the common ground line instead of rotating/lifting it.
            parts[.frontLeg] = PetPartPose(offset: CGPoint(x: wave * 3.5, y: 0))
            parts[.backLeg] = PetPartPose(offset: CGPoint(x: -wave * 3.5, y: 0))
            parts[.tail] = PetPartPose(rotation: -wave * 0.16)
            parts[.leftEar] = PetPartPose(rotation: wave * 0.035)
            parts[.rightEar] = PetPartPose(rotation: -wave * 0.035)

        case .petReceive:
            // A pet lands on the head: the head settles, both ears relax, the
            // eyes soften and the tail answers twice. The torso and ground
            // anchors remain identity, so the feedback is visible without
            // introducing the old whole-character hop/jitter.
            let petOffset = CGPoint(x: -0.8 * pulse, y: -4.2 * pulse)
            let petTilt = -0.13 * pulse
            parts.merge(
                headGroup(
                    offset: petOffset,
                    rotation: petTilt,
                    scaleX: 1 + 0.018 * pulse,
                    scaleY: 1 - 0.045 * pulse
                )
            ) { _, new in new }
            parts[.leftEar] = PetPartPose(
                offset: petOffset,
                rotation: petTilt - 0.20 * pulse,
                scaleY: 1 - 0.05 * pulse
            )
            parts[.rightEar] = PetPartPose(
                offset: petOffset,
                rotation: petTilt + 0.17 * pulse,
                scaleY: 1 - 0.05 * pulse
            )
            parts[.face] = PetPartPose(
                offset: petOffset,
                rotation: petTilt,
                scaleY: 1 - 0.13 * pulse
            )
            parts[.frontLeg] = PetPartPose(rotation: -0.11 * pulse)
            parts[.tail] = PetPartPose(
                rotation: CGFloat(sin(progress * .pi * 4)) * 0.34
            )
            parts[.heartEffect] = PetPartPose(
                offset: CGPoint(x: 0, y: 7 * pulse),
                scaleX: 0.68 + 0.32 * pulse,
                scaleY: 0.68 + 0.32 * pulse,
                opacity: min(1, pulse * 1.8)
            )

        case .eat:
            parts.merge(headGroup(offset: CGPoint(x: -2, y: -7 - pulse * 2), rotation: -0.10)) { _, new in new }
            parts[.frontLeg] = PetPartPose(offset: CGPoint(x: pulse * 1.5, y: 0))

        case .play:
            parts.merge(headGroup(rotation: wave * 0.10)) { _, new in new }
            parts[.frontLeg] = PetPartPose(rotation: -0.22 + wave * 0.08)
            parts[.backLeg] = PetPartPose(rotation: 0.16 - wave * 0.08)
            parts[.tail] = PetPartPose(rotation: wave * 0.28)

        case .sleep:
            parts[.body] = PetPartPose(scaleX: 1.07, scaleY: 0.86)
            parts.merge(headGroup(offset: CGPoint(x: 12, y: -12), rotation: -0.16, scaleY: 0.94)) { _, new in new }
            parts[.frontLeg] = PetPartPose(offset: CGPoint(x: 4, y: 0), rotation: -0.10)
            parts[.tail] = PetPartPose(rotation: -0.16)

        case .shy:
            parts.merge(headGroup(offset: CGPoint(x: -2, y: -2), rotation: -0.08)) { _, new in new }
            parts[.leftEar] = PetPartPose(offset: CGPoint(x: -2, y: -2), rotation: -0.13)
            parts[.rightEar] = PetPartPose(offset: CGPoint(x: -2, y: -2), rotation: 0.13)
            parts[.tail] = PetPartPose(rotation: -0.08)

        case .happy:
            parts.merge(headGroup(offset: CGPoint(x: 0, y: reduceMotion ? 0 : pulse * 1.5), rotation: wave * 0.035)) { _, new in new }
            parts[.tail] = PetPartPose(rotation: wave * 0.30)
            parts[.heartEffect] = PetPartPose(offset: CGPoint(x: 0, y: reduceMotion ? 0 : pulse * 3), opacity: 0.75 + pulse * 0.25)

        case .tiredRefuse:
            parts.merge(headGroup(offset: CGPoint(x: 4, y: -4), rotation: 0.11)) { _, new in new }
            parts[.leftEar] = PetPartPose(offset: CGPoint(x: 4, y: -4), rotation: -0.17)
            parts[.rightEar] = PetPartPose(offset: CGPoint(x: 4, y: -4), rotation: 0.17)
            parts[.tail] = PetPartPose(rotation: -0.20)

        case .fullRefuse:
            parts.merge(headGroup(offset: CGPoint(x: 2 + wave, y: 0), rotation: -wave * 0.12)) { _, new in new }
            parts[.tail] = PetPartPose(rotation: -0.12)

        case .cuddleGive:
            parts.merge(headGroup(offset: CGPoint(x: 6 + pulse, y: -1), rotation: 0.12)) { _, new in new }
            parts[.frontLeg] = PetPartPose(rotation: 0.58)
            parts[.heartEffect] = PetPartPose(opacity: 0.8)

        case .cuddleReceive:
            parts.merge(headGroup(offset: CGPoint(x: -3, y: -2), rotation: -0.10)) { _, new in new }
            parts[.tail] = PetPartPose(rotation: wave * 0.20)
            parts[.heartEffect] = PetPartPose(opacity: 0.8)

        case .flowerGive:
            parts.merge(headGroup(rotation: -0.04)) { _, new in new }
            parts[.frontLeg] = PetPartPose(offset: CGPoint(x: 1, y: 2), rotation: 0.62)
            parts[.flowerEffect] = PetPartPose(offset: CGPoint(x: -8, y: 14), rotation: wave * 0.06, opacity: 1)

        case .flowerReceive:
            parts.merge(headGroup(offset: CGPoint(x: 0, y: -1), rotation: -0.05)) { _, new in new }
            parts[.tail] = PetPartPose(rotation: wave * 0.26)
            parts[.flowerEffect] = PetPartPose(offset: CGPoint(x: -2, y: 1), opacity: 1)

        case .letterGive:
            parts[.frontLeg] = PetPartPose(offset: CGPoint(x: 1, y: 2), rotation: 0.56)
            parts[.letterEffect] = PetPartPose(offset: CGPoint(x: -7, y: 11), opacity: 1)

        case .wave:
            parts[.frontLeg] = PetPartPose(offset: CGPoint(x: 1, y: 2), rotation: 0.98 + wave * 0.22)
            parts.merge(headGroup(rotation: -0.035)) { _, new in new }
            parts[.tail] = PetPartPose(rotation: wave * 0.18)

        case .welcome:
            parts.merge(headGroup(offset: CGPoint(x: 0, y: reduceMotion ? 0 : pulse), rotation: -0.05 + wave * 0.025)) { _, new in new }
            parts[.frontLeg] = PetPartPose(rotation: 0.34)
            parts[.tail] = PetPartPose(rotation: wave * 0.26)
            parts[.heartEffect] = PetPartPose(opacity: 0.8)
        }
        return PetMotionPose(parts: parts)
    }
}

enum PetVectorFill: Equatable {
    case body
    case ear
    case muzzle
    case blush
    case ink
    case accent
    case none
}

struct PetVectorElement {
    let part: PetRigPartID
    let path: CGPath
    let fill: PetVectorFill
    let hasStroke: Bool
    let lineWidth: CGFloat
    let zIndex: Int
}

public struct PetCharacterContentBounds: Equatable, Sendable {
    public let minX: CGFloat
    public let minY: CGFloat
    public let maxX: CGFloat
    public let maxY: CGFloat

    public init(minX: CGFloat, minY: CGFloat, maxX: CGFloat, maxY: CGFloat) {
        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
    }

    public var width: CGFloat { maxX - minX }
    public var height: CGFloat { maxY - minY }
}

/// Vector asset catalog. The geometry is authored in one 120×120 canvas and is
/// code-reconstructed; no downloaded bitmap is included or sampled at runtime.
public enum PetCharacterAssetCatalog {
    public static let manifest = PetRigManifest.maltesePairV1
    private static let clipsByCharacter: [PetCharacterID: Set<PetMotionClipID>] = [
        .malteseWhite: Set(PetMotionClipID.allCases),
        .retrieverYellow: Set(PetMotionClipID.allCases)
    ]

    public static func supports(_ clip: PetMotionClipID, for character: PetCharacterID) -> Bool {
        clipsByCharacter[character]?.contains(clip) == true
    }

    public static func hasCompleteRig(for character: PetCharacterID) -> Bool {
        PetMotionClipID.allCases.allSatisfy { supports($0, for: character) }
            && Set(manifest.parts.map(\.id)).isSuperset(of: Set(PetRigPartID.allCases))
    }

    public static func contentBounds(for character: PetCharacterID) -> PetCharacterContentBounds {
        let bounds = PetVectorGeometry.elements(for: character)
            .map(\.path.boundingBoxOfPath)
            .reduce(CGRect.null) { $0.union($1) }
        return PetCharacterContentBounds(
            minX: bounds.minX,
            minY: bounds.minY,
            maxX: bounds.maxX,
            maxY: bounds.maxY
        )
    }
}

enum PetVectorGeometry {
    static let pivots: [PetRigPartID: CGPoint] = [
        .tail: CGPoint(x: -29, y: -15),
        .backLeg: CGPoint(x: -3, y: -1),
        .body: .zero,
        .frontLeg: CGPoint(x: 20, y: 1),
        .head: CGPoint(x: 0, y: 32),
        .leftEar: CGPoint(x: -24, y: 34),
        .rightEar: CGPoint(x: 23, y: 34),
        .face: CGPoint(x: 0, y: 16),
        .heartEffect: CGPoint(x: 36, y: 34),
        .flowerEffect: CGPoint(x: 36, y: 34),
        .letterEffect: CGPoint(x: 36, y: 34)
    ]

    static func elements(for character: PetCharacterID) -> [PetVectorElement] {
        let isRetriever = character == .retrieverYellow
        var elements: [PetVectorElement] = []

        // Tail sits behind the one-piece body and keeps the tiny hand-drawn tip
        // that distinguishes both official characters from a generic puppy.
        elements.append(element(.tail, tailPath(retriever: isRetriever), .body, true, 2.6, 0))
        if isRetriever {
            for stripe in retrieverTailStripes() {
                elements.append(element(.tail, stripe, .none, true, 2.0, 1))
            }
        }

        // The official silhouette is one uninterrupted front-facing soft blob.
        // Fill and contour are separate so the crown/ears/arms can move without
        // drawing a fake neck seam.
        elements.append(element(.body, bodySilhouettePath(retriever: isRetriever), .body, false, 0, 20))
        elements.append(element(.body, bodySideAndFeetOutline(retriever: isRetriever), .none, true, 2.6, 22))
        elements.append(element(.head, crownOutline(retriever: isRetriever), .none, true, 2.6, 40))

        let armFill = frontArmFill(retriever: isRetriever)
        elements.append(element(.frontLeg, armFill, .body, false, 0, 30))
        elements.append(element(.frontLeg, frontArmOutline(retriever: isRetriever), .none, true, 2.6, 32))
        elements.append(element(.backLeg, chestArmPath(retriever: isRetriever), .none, true, 2.0, 34))

        for isLeft in [true, false] {
            let part: PetRigPartID = isLeft ? .leftEar : .rightEar
            let ear = earPath(left: isLeft, retriever: isRetriever)
            elements.append(element(part, ear, .ear, false, 0, 42))
            elements.append(element(part, earOutlinePath(left: isLeft, retriever: isRetriever), .none, true, 2.6, 44))
        }

        // Tiny dot eyes and a T/omega mouth are the identity anchor. Large oval
        // eyes, a muzzle patch and cheek circles made the previous rig generic.
        let eyeY: CGFloat = isRetriever ? 17 : 16
        let eyeSpacing: CGFloat = isRetriever ? 6.8 : 6.5
        for eyeX in [-eyeSpacing, eyeSpacing] {
            let eye = CGPath(ellipseIn: CGRect(x: eyeX - 1.35, y: eyeY - 1.35, width: 2.7, height: 2.7), transform: nil)
            elements.append(element(.face, eye, .ink, false, 0, 50))
        }
        let noseY: CGFloat = isRetriever ? 12.5 : 11.5
        let nose = CGPath(ellipseIn: CGRect(x: -1.9, y: noseY - 1.4, width: 3.8, height: 2.8), transform: nil)
        elements.append(element(.face, nose, .ink, false, 0, 51))
        elements.append(element(.face, mouthPath(noseY: noseY), .none, true, 1.9, 51))
        let tongue = tonguePath(noseY: noseY)
        elements.append(element(.face, tongue, .accent, true, 1.2, 50))

        if isRetriever {
            elements.append(element(.body, collarPath(), .accent, false, 0, 47))
        }
        elements.append(element(.heartEffect, heartPath(), .accent, true, 2.2, 60))
        elements.append(contentsOf: flowerElements())
        elements.append(contentsOf: letterElements())
        return elements.sorted { $0.zIndex < $1.zIndex }
    }

    private static func element(
        _ part: PetRigPartID,
        _ path: CGPath,
        _ fill: PetVectorFill,
        _ hasStroke: Bool,
        _ lineWidth: CGFloat,
        _ zIndex: Int
    ) -> PetVectorElement {
        PetVectorElement(part: part, path: path, fill: fill, hasStroke: hasStroke, lineWidth: lineWidth, zIndex: zIndex)
    }

    private static func bodySilhouettePath(retriever: Bool) -> CGPath {
        retriever ? retrieverBodySilhouette() : malteseBodySilhouette()
    }

    private static func malteseBodySilhouette() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -24, y: 32))
        path.addCurve(to: CGPoint(x: -8, y: 38), control1: CGPoint(x: -18, y: 35), control2: CGPoint(x: -13, y: 38))
        path.addCurve(to: CGPoint(x: 5, y: 38), control1: CGPoint(x: -3, y: 35), control2: CGPoint(x: 1, y: 41))
        path.addCurve(to: CGPoint(x: 23, y: 31), control1: CGPoint(x: 11, y: 35), control2: CGPoint(x: 18, y: 36))
        path.addCurve(to: CGPoint(x: 29, y: 19), control1: CGPoint(x: 29, y: 29), control2: CGPoint(x: 31, y: 24))
        path.addCurve(to: CGPoint(x: 27, y: 8), control1: CGPoint(x: 33, y: 14), control2: CGPoint(x: 31, y: 10))
        path.addCurve(to: CGPoint(x: 30, y: -2), control1: CGPoint(x: 33, y: 4), control2: CGPoint(x: 33, y: 0))
        path.addCurve(to: CGPoint(x: 26, y: -13), control1: CGPoint(x: 31, y: -7), control2: CGPoint(x: 29, y: -10))
        path.addCurve(to: CGPoint(x: 28, y: -23), control1: CGPoint(x: 31, y: -18), control2: CGPoint(x: 31, y: -21))
        path.addCurve(to: CGPoint(x: 21, y: -31), control1: CGPoint(x: 29, y: -28), control2: CGPoint(x: 26, y: -31))
        path.addCurve(to: CGPoint(x: 17, y: -42), control1: CGPoint(x: 20, y: -38), control2: CGPoint(x: 20, y: -41))
        path.addLine(to: CGPoint(x: 6, y: -42))
        path.addCurve(to: CGPoint(x: 0, y: -36), control1: CGPoint(x: 4, y: -42), control2: CGPoint(x: 2, y: -37))
        path.addCurve(to: CGPoint(x: -7, y: -42), control1: CGPoint(x: -2, y: -37), control2: CGPoint(x: -4, y: -42))
        path.addLine(to: CGPoint(x: -19, y: -41))
        path.addCurve(to: CGPoint(x: -23, y: -30), control1: CGPoint(x: -23, y: -41), control2: CGPoint(x: -24, y: -37))
        path.addCurve(to: CGPoint(x: -29, y: -24), control1: CGPoint(x: -28, y: -30), control2: CGPoint(x: -30, y: -27))
        path.addCurve(to: CGPoint(x: -27, y: -14), control1: CGPoint(x: -32, y: -20), control2: CGPoint(x: -30, y: -16))
        path.addCurve(to: CGPoint(x: -31, y: -5), control1: CGPoint(x: -31, y: -11), control2: CGPoint(x: -33, y: -8))
        path.addCurve(to: CGPoint(x: -28, y: 4), control1: CGPoint(x: -33, y: -1), control2: CGPoint(x: -31, y: 2))
        path.addCurve(to: CGPoint(x: -31, y: 13), control1: CGPoint(x: -32, y: 7), control2: CGPoint(x: -33, y: 10))
        path.addCurve(to: CGPoint(x: -27, y: 22), control1: CGPoint(x: -32, y: 17), control2: CGPoint(x: -30, y: 20))
        path.addCurve(to: CGPoint(x: -24, y: 32), control1: CGPoint(x: -31, y: 27), control2: CGPoint(x: -28, y: 31))
        path.closeSubpath()
        return path
    }

    private static func retrieverBodySilhouette() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -22, y: 31))
        path.addCurve(to: CGPoint(x: 21, y: 31), control1: CGPoint(x: -10, y: 39), control2: CGPoint(x: 10, y: 39))
        path.addCurve(to: CGPoint(x: 28, y: 17), control1: CGPoint(x: 28, y: 29), control2: CGPoint(x: 30, y: 23))
        path.addCurve(to: CGPoint(x: 26, y: 1), control1: CGPoint(x: 31, y: 11), control2: CGPoint(x: 30, y: 5))
        path.addCurve(to: CGPoint(x: 27, y: -17), control1: CGPoint(x: 29, y: -6), control2: CGPoint(x: 30, y: -12))
        path.addCurve(to: CGPoint(x: 20, y: -31), control1: CGPoint(x: 27, y: -24), control2: CGPoint(x: 25, y: -29))
        path.addCurve(to: CGPoint(x: 17, y: -42), control1: CGPoint(x: 20, y: -38), control2: CGPoint(x: 20, y: -41))
        path.addLine(to: CGPoint(x: 6, y: -42))
        path.addCurve(to: CGPoint(x: 0, y: -36), control1: CGPoint(x: 4, y: -42), control2: CGPoint(x: 2, y: -37))
        path.addCurve(to: CGPoint(x: -7, y: -42), control1: CGPoint(x: -2, y: -37), control2: CGPoint(x: -4, y: -42))
        path.addLine(to: CGPoint(x: -18, y: -41))
        path.addCurve(to: CGPoint(x: -22, y: -30), control1: CGPoint(x: -21, y: -41), control2: CGPoint(x: -22, y: -38))
        path.addCurve(to: CGPoint(x: -27, y: -18), control1: CGPoint(x: -26, y: -27), control2: CGPoint(x: -28, y: -23))
        path.addCurve(to: CGPoint(x: -25, y: 0), control1: CGPoint(x: -29, y: -11), control2: CGPoint(x: -28, y: -5))
        path.addCurve(to: CGPoint(x: -28, y: 15), control1: CGPoint(x: -29, y: 6), control2: CGPoint(x: -30, y: 11))
        path.addCurve(to: CGPoint(x: -22, y: 31), control1: CGPoint(x: -29, y: 23), control2: CGPoint(x: -27, y: 28))
        path.closeSubpath()
        return path
    }

    private static func bodySideAndFeetOutline(retriever: Bool) -> CGPath {
        retriever ? retrieverSideAndFeetOutline() : malteseSideAndFeetOutline()
    }

    private static func malteseSideAndFeetOutline() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 23, y: 31))
        path.addCurve(to: CGPoint(x: 29, y: 19), control1: CGPoint(x: 29, y: 29), control2: CGPoint(x: 31, y: 24))
        path.addCurve(to: CGPoint(x: 27, y: 8), control1: CGPoint(x: 33, y: 14), control2: CGPoint(x: 31, y: 10))
        path.addCurve(to: CGPoint(x: 30, y: -2), control1: CGPoint(x: 33, y: 4), control2: CGPoint(x: 33, y: 0))
        path.addCurve(to: CGPoint(x: 26, y: -13), control1: CGPoint(x: 31, y: -7), control2: CGPoint(x: 29, y: -10))
        path.addCurve(to: CGPoint(x: 28, y: -23), control1: CGPoint(x: 31, y: -18), control2: CGPoint(x: 31, y: -21))
        path.addCurve(to: CGPoint(x: 21, y: -31), control1: CGPoint(x: 29, y: -28), control2: CGPoint(x: 26, y: -31))
        path.addCurve(to: CGPoint(x: 17, y: -42), control1: CGPoint(x: 20, y: -38), control2: CGPoint(x: 20, y: -41))
        path.addLine(to: CGPoint(x: 6, y: -42))
        path.addCurve(to: CGPoint(x: 0, y: -36), control1: CGPoint(x: 4, y: -42), control2: CGPoint(x: 2, y: -37))
        path.addCurve(to: CGPoint(x: -7, y: -42), control1: CGPoint(x: -2, y: -37), control2: CGPoint(x: -4, y: -42))
        path.addLine(to: CGPoint(x: -19, y: -41))
        path.addCurve(to: CGPoint(x: -23, y: -30), control1: CGPoint(x: -23, y: -41), control2: CGPoint(x: -24, y: -37))
        path.addCurve(to: CGPoint(x: -29, y: -24), control1: CGPoint(x: -28, y: -30), control2: CGPoint(x: -30, y: -27))
        path.addCurve(to: CGPoint(x: -27, y: -14), control1: CGPoint(x: -32, y: -20), control2: CGPoint(x: -30, y: -16))
        path.addCurve(to: CGPoint(x: -31, y: -5), control1: CGPoint(x: -31, y: -11), control2: CGPoint(x: -33, y: -8))
        path.addCurve(to: CGPoint(x: -28, y: 4), control1: CGPoint(x: -33, y: -1), control2: CGPoint(x: -31, y: 2))
        path.addCurve(to: CGPoint(x: -31, y: 13), control1: CGPoint(x: -32, y: 7), control2: CGPoint(x: -33, y: 10))
        path.addCurve(to: CGPoint(x: -27, y: 22), control1: CGPoint(x: -32, y: 17), control2: CGPoint(x: -30, y: 20))
        path.addCurve(to: CGPoint(x: -24, y: 32), control1: CGPoint(x: -31, y: 27), control2: CGPoint(x: -28, y: 31))
        return path
    }

    private static func retrieverSideAndFeetOutline() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 21, y: 31))
        path.addCurve(to: CGPoint(x: 28, y: 17), control1: CGPoint(x: 28, y: 29), control2: CGPoint(x: 30, y: 23))
        path.addCurve(to: CGPoint(x: 26, y: 1), control1: CGPoint(x: 31, y: 11), control2: CGPoint(x: 30, y: 5))
        path.addCurve(to: CGPoint(x: 27, y: -17), control1: CGPoint(x: 29, y: -6), control2: CGPoint(x: 30, y: -12))
        path.addCurve(to: CGPoint(x: 20, y: -31), control1: CGPoint(x: 27, y: -24), control2: CGPoint(x: 25, y: -29))
        path.addCurve(to: CGPoint(x: 17, y: -42), control1: CGPoint(x: 20, y: -38), control2: CGPoint(x: 20, y: -41))
        path.addLine(to: CGPoint(x: 6, y: -42))
        path.addCurve(to: CGPoint(x: 0, y: -36), control1: CGPoint(x: 4, y: -42), control2: CGPoint(x: 2, y: -37))
        path.addCurve(to: CGPoint(x: -7, y: -42), control1: CGPoint(x: -2, y: -37), control2: CGPoint(x: -4, y: -42))
        path.addLine(to: CGPoint(x: -18, y: -41))
        path.addCurve(to: CGPoint(x: -22, y: -30), control1: CGPoint(x: -21, y: -41), control2: CGPoint(x: -22, y: -38))
        path.addCurve(to: CGPoint(x: -27, y: -18), control1: CGPoint(x: -26, y: -27), control2: CGPoint(x: -28, y: -23))
        path.addCurve(to: CGPoint(x: -25, y: 0), control1: CGPoint(x: -29, y: -11), control2: CGPoint(x: -28, y: -5))
        path.addCurve(to: CGPoint(x: -28, y: 15), control1: CGPoint(x: -29, y: 6), control2: CGPoint(x: -30, y: 11))
        path.addCurve(to: CGPoint(x: -22, y: 31), control1: CGPoint(x: -29, y: 23), control2: CGPoint(x: -27, y: 28))
        return path
    }

    private static func crownOutline(retriever: Bool) -> CGPath {
        let path = CGMutablePath()
        if retriever {
            path.move(to: CGPoint(x: -22, y: 31))
            path.addCurve(to: CGPoint(x: 21, y: 31), control1: CGPoint(x: -10, y: 39), control2: CGPoint(x: 10, y: 39))
        } else {
            path.move(to: CGPoint(x: -24, y: 32))
            path.addCurve(to: CGPoint(x: -8, y: 38), control1: CGPoint(x: -18, y: 35), control2: CGPoint(x: -13, y: 38))
            path.addCurve(to: CGPoint(x: 5, y: 38), control1: CGPoint(x: -3, y: 35), control2: CGPoint(x: 1, y: 41))
            path.addCurve(to: CGPoint(x: 23, y: 31), control1: CGPoint(x: 11, y: 35), control2: CGPoint(x: 18, y: 36))
        }
        return path
    }

    private static func earPath(left: Bool, retriever: Bool) -> CGPath {
        let path = CGMutablePath()
        if retriever, left {
            path.move(to: CGPoint(x: -21, y: 32))
            path.addCurve(to: CGPoint(x: -34, y: 33), control1: CGPoint(x: -27, y: 37), control2: CGPoint(x: -31, y: 37))
            path.addCurve(to: CGPoint(x: -37, y: 38), control1: CGPoint(x: -38, y: 34), control2: CGPoint(x: -39, y: 37))
            path.addCurve(to: CGPoint(x: -31, y: 43), control1: CGPoint(x: -35, y: 42), control2: CGPoint(x: -33, y: 43))
            path.addCurve(to: CGPoint(x: -21, y: 37), control1: CGPoint(x: -26, y: 43), control2: CGPoint(x: -22, y: 40))
        } else if retriever {
            path.move(to: CGPoint(x: 20, y: 32))
            path.addCurve(to: CGPoint(x: 26, y: 43), control1: CGPoint(x: 22, y: 39), control2: CGPoint(x: 23, y: 43))
            path.addCurve(to: CGPoint(x: 34, y: 41), control1: CGPoint(x: 29, y: 45), control2: CGPoint(x: 33, y: 44))
            path.addCurve(to: CGPoint(x: 32, y: 34), control1: CGPoint(x: 37, y: 38), control2: CGPoint(x: 36, y: 35))
            path.addCurve(to: CGPoint(x: 20, y: 32), control1: CGPoint(x: 28, y: 30), control2: CGPoint(x: 24, y: 30))
        } else if left {
            path.move(to: CGPoint(x: -22, y: 31))
            path.addCurve(to: CGPoint(x: -32, y: 34), control1: CGPoint(x: -27, y: 35), control2: CGPoint(x: -30, y: 35))
            path.addCurve(to: CGPoint(x: -38, y: 32), control1: CGPoint(x: -35, y: 30), control2: CGPoint(x: -38, y: 29))
            path.addCurve(to: CGPoint(x: -37, y: 37), control1: CGPoint(x: -40, y: 34), control2: CGPoint(x: -39, y: 37))
            path.addCurve(to: CGPoint(x: -29, y: 40), control1: CGPoint(x: -34, y: 40), control2: CGPoint(x: -31, y: 41))
            path.addCurve(to: CGPoint(x: -22, y: 31), control1: CGPoint(x: -24, y: 40), control2: CGPoint(x: -21, y: 35))
        } else {
            path.move(to: CGPoint(x: 19, y: 31))
            path.addCurve(to: CGPoint(x: 27, y: 39), control1: CGPoint(x: 22, y: 37), control2: CGPoint(x: 24, y: 40))
            path.addCurve(to: CGPoint(x: 34, y: 36), control1: CGPoint(x: 31, y: 41), control2: CGPoint(x: 34, y: 39))
            path.addCurve(to: CGPoint(x: 32, y: 31), control1: CGPoint(x: 36, y: 33), control2: CGPoint(x: 35, y: 31))
            path.addCurve(to: CGPoint(x: 19, y: 31), control1: CGPoint(x: 28, y: 28), control2: CGPoint(x: 23, y: 29))
        }
        path.closeSubpath()
        return path
    }

    private static func earOutlinePath(left: Bool, retriever: Bool) -> CGPath {
        let path = CGMutablePath()
        if retriever, left {
            path.move(to: CGPoint(x: -21, y: 32))
            path.addCurve(to: CGPoint(x: -34, y: 33), control1: CGPoint(x: -27, y: 37), control2: CGPoint(x: -31, y: 37))
            path.addCurve(to: CGPoint(x: -37, y: 38), control1: CGPoint(x: -38, y: 34), control2: CGPoint(x: -39, y: 37))
            path.addCurve(to: CGPoint(x: -31, y: 43), control1: CGPoint(x: -35, y: 42), control2: CGPoint(x: -33, y: 43))
            path.addCurve(to: CGPoint(x: -22, y: 37), control1: CGPoint(x: -26, y: 43), control2: CGPoint(x: -23, y: 40))
        } else if retriever {
            path.move(to: CGPoint(x: 20, y: 32))
            path.addCurve(to: CGPoint(x: 26, y: 43), control1: CGPoint(x: 22, y: 39), control2: CGPoint(x: 23, y: 43))
            path.addCurve(to: CGPoint(x: 34, y: 41), control1: CGPoint(x: 29, y: 45), control2: CGPoint(x: 33, y: 44))
            path.addCurve(to: CGPoint(x: 32, y: 34), control1: CGPoint(x: 37, y: 38), control2: CGPoint(x: 36, y: 35))
            path.addCurve(to: CGPoint(x: 22, y: 32), control1: CGPoint(x: 28, y: 30), control2: CGPoint(x: 25, y: 30))
        } else if left {
            path.move(to: CGPoint(x: -22, y: 31))
            path.addCurve(to: CGPoint(x: -32, y: 34), control1: CGPoint(x: -27, y: 35), control2: CGPoint(x: -30, y: 35))
            path.addCurve(to: CGPoint(x: -38, y: 32), control1: CGPoint(x: -35, y: 30), control2: CGPoint(x: -38, y: 29))
            path.addCurve(to: CGPoint(x: -37, y: 37), control1: CGPoint(x: -40, y: 34), control2: CGPoint(x: -39, y: 37))
            path.addCurve(to: CGPoint(x: -29, y: 40), control1: CGPoint(x: -34, y: 40), control2: CGPoint(x: -31, y: 41))
            path.addCurve(to: CGPoint(x: -23, y: 35), control1: CGPoint(x: -25, y: 40), control2: CGPoint(x: -22, y: 37))
        } else {
            path.move(to: CGPoint(x: 19, y: 31))
            path.addCurve(to: CGPoint(x: 27, y: 39), control1: CGPoint(x: 22, y: 37), control2: CGPoint(x: 24, y: 40))
            path.addCurve(to: CGPoint(x: 34, y: 36), control1: CGPoint(x: 31, y: 41), control2: CGPoint(x: 34, y: 39))
            path.addCurve(to: CGPoint(x: 32, y: 31), control1: CGPoint(x: 36, y: 33), control2: CGPoint(x: 35, y: 31))
            path.addCurve(to: CGPoint(x: 21, y: 32), control1: CGPoint(x: 28, y: 28), control2: CGPoint(x: 24, y: 29))
        }
        return path
    }

    private static func tailPath(retriever: Bool) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -27, y: -13))
        path.addCurve(to: CGPoint(x: -37, y: -12), control1: CGPoint(x: -31, y: -11), control2: CGPoint(x: -35, y: -10))
        path.addCurve(to: CGPoint(x: -39, y: -16), control1: CGPoint(x: -40, y: -13), control2: CGPoint(x: -41, y: -15))
        path.addCurve(to: CGPoint(x: -32, y: -19), control1: CGPoint(x: -37, y: -18), control2: CGPoint(x: -34, y: -19))
        path.addCurve(to: CGPoint(x: -27, y: -13), control1: CGPoint(x: -28, y: -19), control2: CGPoint(x: -26, y: -16))
        path.closeSubpath()
        return path
    }

    private static func retrieverTailStripes() -> [CGPath] {
        [-36.5, -33.5].map { x in
            let path = CGMutablePath()
            path.move(to: CGPoint(x: x, y: -12))
            path.addLine(to: CGPoint(x: x - 1.2, y: -17.5))
            return path
        }
    }

    private static func frontArmFill(retriever: Bool) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 18, y: 2))
        path.addCurve(to: CGPoint(x: 29, y: -2), control1: CGPoint(x: 23, y: 1), control2: CGPoint(x: 27, y: 0))
        path.addCurve(to: CGPoint(x: 31, y: -9), control1: CGPoint(x: 33, y: -4), control2: CGPoint(x: 34, y: -7))
        path.addCurve(to: CGPoint(x: 27, y: -14), control1: CGPoint(x: 31, y: -12), control2: CGPoint(x: 29, y: -14))
        path.addCurve(to: CGPoint(x: 18, y: -7), control1: CGPoint(x: 23, y: -13), control2: CGPoint(x: 20, y: -10))
        path.closeSubpath()
        return path
    }

    private static func frontArmOutline(retriever: Bool) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 18, y: 2))
        path.addCurve(to: CGPoint(x: 29, y: -2), control1: CGPoint(x: 23, y: 1), control2: CGPoint(x: 27, y: 0))
        path.addCurve(to: CGPoint(x: 31, y: -9), control1: CGPoint(x: 33, y: -4), control2: CGPoint(x: 34, y: -7))
        path.addCurve(to: CGPoint(x: 27, y: -14), control1: CGPoint(x: 31, y: -12), control2: CGPoint(x: 29, y: -14))
        path.addCurve(to: CGPoint(x: 18, y: -7), control1: CGPoint(x: 23, y: -13), control2: CGPoint(x: 20, y: -10))
        return path
    }

    private static func chestArmPath(retriever: Bool) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -8, y: 2))
        path.addCurve(to: CGPoint(x: 9, y: -2), control1: CGPoint(x: -3, y: 0), control2: CGPoint(x: 4, y: 1))
        path.addCurve(to: CGPoint(x: 5, y: -10), control1: CGPoint(x: 14, y: -5), control2: CGPoint(x: 11, y: -10))
        path.addCurve(to: CGPoint(x: -4, y: -11), control1: CGPoint(x: 1, y: -11), control2: CGPoint(x: -2, y: -11))
        return path
    }

    private static func mouthPath(noseY: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: noseY))
        path.addLine(to: CGPoint(x: 0, y: noseY - 4))
        path.addQuadCurve(to: CGPoint(x: -5.2, y: noseY - 4), control: CGPoint(x: -2.6, y: noseY - 7.3))
        path.move(to: CGPoint(x: 0, y: noseY - 4))
        path.addQuadCurve(to: CGPoint(x: 5.2, y: noseY - 4), control: CGPoint(x: 2.6, y: noseY - 7.3))
        return path
    }

    private static func tonguePath(noseY: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.addRoundedRect(
            in: CGRect(x: -2, y: noseY - 7.5, width: 4, height: 3.7),
            cornerWidth: 1.8,
            cornerHeight: 1.8
        )
        return path
    }

    private static func collarPath() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -26, y: 4))
        path.addQuadCurve(to: CGPoint(x: 26, y: 4), control: CGPoint(x: 0, y: -1))
        path.addQuadCurve(to: CGPoint(x: -26, y: 4), control: CGPoint(x: 0, y: 2))
        path.closeSubpath()
        return path
    }

    private static func heartPath() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 31, y: 26))
        path.addCurve(to: CGPoint(x: 21, y: 36), control1: CGPoint(x: 24, y: 32), control2: CGPoint(x: 20, y: 31))
        path.addCurve(to: CGPoint(x: 31, y: 49), control1: CGPoint(x: 20, y: 43), control2: CGPoint(x: 27, y: 47))
        path.addCurve(to: CGPoint(x: 41, y: 36), control1: CGPoint(x: 35, y: 47), control2: CGPoint(x: 42, y: 43))
        path.addCurve(to: CGPoint(x: 31, y: 26), control1: CGPoint(x: 42, y: 31), control2: CGPoint(x: 37, y: 32))
        path.closeSubpath()
        return path
    }

    private static func flowerElements() -> [PetVectorElement] {
        var result: [PetVectorElement] = []
        let centers = [
            CGPoint(x: 31, y: 43), CGPoint(x: 24, y: 38),
            CGPoint(x: 26, y: 30), CGPoint(x: 36, y: 30),
            CGPoint(x: 38, y: 38)
        ]
        for center in centers {
            let petal = CGPath(
                ellipseIn: CGRect(x: center.x - 5, y: center.y - 6, width: 10, height: 12),
                transform: nil
            )
            result.append(element(.flowerEffect, petal, .accent, true, 1.7, 60))
        }
        let center = CGPath(ellipseIn: CGRect(x: 27, y: 34, width: 8, height: 8), transform: nil)
        result.append(element(.flowerEffect, center, .muzzle, true, 1.7, 61))
        let stem = CGMutablePath()
        stem.move(to: CGPoint(x: 31, y: 34))
        stem.addQuadCurve(to: CGPoint(x: 28, y: 20), control: CGPoint(x: 35, y: 26))
        result.append(element(.flowerEffect, stem, .none, true, 2.2, 59))
        return result
    }

    private static func letterElements() -> [PetVectorElement] {
        let envelope = CGMutablePath()
        envelope.addRoundedRect(
            in: CGRect(x: 20, y: 25, width: 25, height: 18),
            cornerWidth: 3,
            cornerHeight: 3
        )
        let flap = CGMutablePath()
        flap.move(to: CGPoint(x: 21, y: 41))
        flap.addLine(to: CGPoint(x: 32.5, y: 32))
        flap.addLine(to: CGPoint(x: 44, y: 41))
        return [
            element(.letterEffect, envelope, .muzzle, true, 2, 60),
            element(.letterEffect, flap, .none, true, 1.7, 61)
        ]
    }

    private static func capsule(_ rect: CGRect, radius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.addRoundedRect(in: rect, cornerWidth: radius, cornerHeight: radius)
        return path
    }
}

struct PetCharacterPalette {
    let body: NSColor
    let ear: NSColor
    let muzzle: NSColor
    let blush: NSColor
    let ink: NSColor
    let accent: NSColor

    static func palette(for character: PetCharacterID) -> PetCharacterPalette {
        switch character {
        case .malteseWhite:
            return PetCharacterPalette(
                body: NSColor(calibratedRed: 1, green: 0.995, blue: 0.98, alpha: 1),
                ear: NSColor(calibratedRed: 1, green: 0.995, blue: 0.98, alpha: 1),
                muzzle: NSColor(calibratedRed: 1, green: 0.99, blue: 0.97, alpha: 1),
                blush: NSColor(calibratedRed: 1, green: 0.48, blue: 0.50, alpha: 0.42),
                ink: NSColor(calibratedWhite: 0.08, alpha: 1),
                accent: NSColor(calibratedRed: 1, green: 0.36, blue: 0.38, alpha: 1)
            )
        case .retrieverYellow:
            return PetCharacterPalette(
                body: NSColor(calibratedRed: 0.94, green: 0.84, blue: 0.67, alpha: 1),
                ear: NSColor(calibratedRed: 0.94, green: 0.84, blue: 0.67, alpha: 1),
                muzzle: NSColor(calibratedRed: 0.97, green: 0.88, blue: 0.70, alpha: 1),
                blush: NSColor(calibratedRed: 1, green: 0.46, blue: 0.45, alpha: 0.36),
                ink: NSColor(calibratedRed: 0.19, green: 0.16, blue: 0.16, alpha: 1),
                accent: NSColor(calibratedRed: 1, green: 0.38, blue: 0.40, alpha: 1)
            )
        }
    }

    func color(for fill: PetVectorFill) -> NSColor {
        switch fill {
        case .body: body
        case .ear: ear
        case .muzzle: muzzle
        case .blush: blush
        case .ink: ink
        case .accent: accent
        case .none: .clear
        }
    }
}

/// Shared raster-frame renderer for avatars, profile, invitations, companion
/// rooms and empty states. Product surfaces never fall back to the legacy
/// procedural vector rig: an unavailable semantic clip is shown as an explicit
/// degraded idle frame, or as a visible missing-asset placeholder.
public struct PetCharacterView: View {
    private let characterID: PetCharacterID
    private let size: CGFloat
    private let clip: PetMotionClipID
    private let facing: PetFacing
    private let progress: Double
    private let reduceMotionOverride: Bool?
    private let showsShadow: Bool

    @Environment(\.accessibilityReduceMotion) private var environmentReduceMotion

    public init(
        characterID: PetCharacterID,
        size: CGFloat = 96,
        clip: PetMotionClipID = .idle,
        facing: PetFacing = .right,
        progress: Double = 0,
        reduceMotion: Bool? = nil,
        showsShadow: Bool = true
    ) {
        self.characterID = characterID
        self.size = max(24, size)
        self.clip = clip
        self.facing = facing
        self.progress = progress
        self.reduceMotionOverride = reduceMotion
        self.showsShadow = showsShadow
    }

    public var body: some View {
        let reduceMotion = reduceMotionOverride ?? environmentReduceMotion
        let frameResolution = PetCharacterFrameResolver.resolve(
            for: characterID,
            clip: clip,
            progress: progress,
            reduceMotion: reduceMotion
        )

        ZStack {
            if showsShadow {
                Ellipse()
                    .fill(Color.black.opacity(0.10))
                    .frame(width: size * 0.48, height: max(2, size * 0.065))
                    // PetFrames share y=102 on a 120px canvas, so the shadow
                    // stays on the same ground line at every presentation size.
                    .offset(y: size * 0.35)
                    .accessibilityHidden(true)
            }

            if let frame = frameResolution.image {
                Image(nsImage: frame)
                    .resizable()
                    .interpolation(.none)
                    .aspectRatio(1, contentMode: .fit)
                    .scaleEffect(x: facing == .right ? 1 : -1, y: 1)
                    .accessibilityHidden(true)

                if frameResolution.kind == .idleFallback {
                    PetMissingFrameBadge(containerSize: size)
                        .accessibilityLabel("动作帧缺失，正在显示静止角色")
                }
            } else {
                PetMissingCharacterFrame(characterID: characterID, size: size)
                    .accessibilityLabel("角色帧资源缺失")
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .contain)
        .accessibilityHidden(frameResolution.kind == .exact)
    }
}

package enum PetCharacterFrameResolutionKind: Equatable, Sendable {
    case exact
    case idleFallback
    case missing
}

package struct PetCharacterFrameResolution {
    package let image: NSImage?
    package let frameIndex: Int?
    package let kind: PetCharacterFrameResolutionKind
}

/// Testable product-surface boundary. It deliberately knows only about raster
/// frames, so a missing package resource can never re-enable the vector rig.
@MainActor
package enum PetCharacterFrameResolver {
    package static func resolve(
        for characterID: PetCharacterID,
        clip: PetMotionClipID,
        progress: Double,
        reduceMotion: Bool
    ) -> PetCharacterFrameResolution {
        if let animation = PetFrameAnimationCatalog.shared.animation(
            for: characterID,
            clip: clip
        ) {
            let frameIndex = animation.frameIndex(
                progress: progress,
                reduceMotion: reduceMotion
            )
            return PetCharacterFrameResolution(
                image: animation.images[frameIndex],
                frameIndex: frameIndex,
                kind: .exact
            )
        }
        if clip != .idle,
           let animation = PetFrameAnimationCatalog.shared.animation(
               for: characterID,
               clip: .idle
           ) {
            let frameIndex = animation.frameIndex(progress: 0, reduceMotion: true)
            return PetCharacterFrameResolution(
                image: animation.images[frameIndex],
                frameIndex: frameIndex,
                kind: .idleFallback
            )
        }
        return PetCharacterFrameResolution(image: nil, frameIndex: nil, kind: .missing)
    }
}

private struct PetMissingFrameBadge: View {
    let containerSize: CGFloat

    var body: some View {
        let badgeSize = min(17, max(10, containerSize * 0.17))
        VStack {
            HStack {
                Spacer()
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: badgeSize * 0.52, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: badgeSize, height: badgeSize)
                    .background(Color.orange, in: Circle())
            }
            Spacer()
        }
        .padding(max(1, containerSize * 0.02))
    }
}

private struct PetMissingCharacterFrame: View {
    let characterID: PetCharacterID
    let size: CGFloat

    var body: some View {
        let cornerRadius = min(16, max(6, size * 0.14))
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(fallbackTint.opacity(0.12))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(
                            fallbackTint.opacity(0.62),
                            style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
                        )
                }
            Image(systemName: "pawprint.fill")
                .font(.system(size: min(26, max(10, size * 0.27)), weight: .medium))
                .foregroundStyle(fallbackTint)
            PetMissingFrameBadge(containerSize: size)
        }
        .padding(max(2, size * 0.04))
    }

    private var fallbackTint: Color {
        switch characterID {
        case .malteseWhite:
            Color(red: 0.42, green: 0.39, blue: 0.37)
        case .retrieverYellow:
            Color(red: 0.78, green: 0.52, blue: 0.24)
        }
    }
}
