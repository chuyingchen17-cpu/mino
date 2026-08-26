import Foundation

/// The two licensed characters in the Mino character catalog.
///
/// Raw values intentionally match the appearance wire format (`body`).
public enum PetCharacterID: String, Codable, CaseIterable, Equatable, Sendable {
    case malteseWhite = "maltese-white"
    case retrieverYellow = "retriever-yellow"

    public static let appearanceSchema = 1
    public static let appearanceCatalog = 2
    public static let rigID = "maltese-pair-v1"

    /// The schema-1/catalog-2 appearance dictionary sent to the account API.
    public var appearance: [String: String] {
        [
            "rigID": Self.rigID,
            "body": rawValue
        ]
    }

    /// Resolves only the catalog-2 characters. Legacy `mino-default` values
    /// deliberately return nil so onboarding can ask for a permanent choice.
    public init?(appearance: [String: String]) {
        guard
            appearance["rigID"] == Self.rigID,
            let body = appearance["body"],
            let character = Self(rawValue: body)
        else {
            return nil
        }
        self = character
    }

    /// Compatibility mapping for local state created by older clients. New
    /// persisted appearances must use `init(appearance:)` instead.
    public init(legacyAvatar: AvatarRecipe) {
        self = legacyAvatar.species == .cat ? .malteseWhite : .retrieverYellow
    }
}

public enum PetRigPartID: String, Codable, CaseIterable, Sendable {
    case tail
    case backLeg
    case body
    case frontLeg
    case head
    case leftEar
    case rightEar
    case face
    case heartEffect = "heart_effect"
    case flowerEffect = "flower_effect"
    case letterEffect = "letter_effect"
}

public struct PetRigPoint: Codable, Equatable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct PetRigSize: Codable, Equatable, Sendable {
    public let width: Double
    public let height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

public struct PetRigLineStyle: Codable, Equatable, Sendable {
    public let width: Double
    public let lineCap: String
    public let lineJoin: String

    public init(width: Double, lineCap: String = "round", lineJoin: String = "round") {
        self.width = width
        self.lineCap = lineCap
        self.lineJoin = lineJoin
    }
}

public enum PetRigMirrorStrategy: String, Codable, Sendable {
    /// Mirror the body container while keeping the world anchor and shadow fixed.
    case bodyContainer = "body_container"
}

public struct PetRigPartManifest: Codable, Equatable, Sendable {
    public let id: PetRigPartID
    public let pivot: PetRigPoint
    public let zIndex: Int

    public init(id: PetRigPartID, pivot: PetRigPoint, zIndex: Int) {
        self.id = id
        self.pivot = pivot
        self.zIndex = zIndex
    }
}

/// Stable geometry contract shared by SpriteKit and SwiftUI renderers.
public struct PetRigManifest: Codable, Equatable, Sendable {
    public let rigID: String
    public let canvas: PetRigSize
    public let groundAnchor: PetRigPoint
    public let parts: [PetRigPartManifest]
    public let lineStyle: PetRigLineStyle
    public let mirrorStrategy: PetRigMirrorStrategy
    public let reduceMotionPose: [PetMotionClipID: PetMotionClipID]

    public init(
        rigID: String,
        canvas: PetRigSize,
        groundAnchor: PetRigPoint,
        parts: [PetRigPartManifest],
        lineStyle: PetRigLineStyle,
        mirrorStrategy: PetRigMirrorStrategy,
        reduceMotionPose: [PetMotionClipID: PetMotionClipID]
    ) {
        self.rigID = rigID
        self.canvas = canvas
        self.groundAnchor = groundAnchor
        self.parts = parts
        self.lineStyle = lineStyle
        self.mirrorStrategy = mirrorStrategy
        self.reduceMotionPose = reduceMotionPose
    }

    public static let maltesePairV1 = PetRigManifest(
        rigID: PetCharacterID.rigID,
        canvas: PetRigSize(width: 120, height: 120),
        groundAnchor: PetRigPoint(x: 60, y: 102),
        parts: [
            PetRigPartManifest(id: .tail, pivot: PetRigPoint(x: 31, y: 75), zIndex: 0),
            PetRigPartManifest(id: .backLeg, pivot: PetRigPoint(x: 57, y: 61), zIndex: 10),
            PetRigPartManifest(id: .body, pivot: PetRigPoint(x: 60, y: 60), zIndex: 20),
            PetRigPartManifest(id: .frontLeg, pivot: PetRigPoint(x: 80, y: 59), zIndex: 30),
            PetRigPartManifest(id: .head, pivot: PetRigPoint(x: 60, y: 28), zIndex: 40),
            PetRigPartManifest(id: .leftEar, pivot: PetRigPoint(x: 36, y: 26), zIndex: 45),
            PetRigPartManifest(id: .rightEar, pivot: PetRigPoint(x: 83, y: 26), zIndex: 45),
            PetRigPartManifest(id: .face, pivot: PetRigPoint(x: 60, y: 44), zIndex: 50),
            PetRigPartManifest(id: .heartEffect, pivot: PetRigPoint(x: 96, y: 26), zIndex: 60),
            PetRigPartManifest(id: .flowerEffect, pivot: PetRigPoint(x: 96, y: 26), zIndex: 60),
            PetRigPartManifest(id: .letterEffect, pivot: PetRigPoint(x: 96, y: 26), zIndex: 60)
        ],
        lineStyle: PetRigLineStyle(width: 2.6),
        mirrorStrategy: .bodyContainer,
        reduceMotionPose: Dictionary(
            uniqueKeysWithValues: PetMotionClipID.allCases.map { ($0, $0) }
        )
    )
}

public enum PetMotionClipID: String, Codable, CaseIterable, Sendable {
    case idle
    case walk
    case petReceive = "pet_receive"
    case eat
    case play
    case sleep
    case shy
    case happy
    case tiredRefuse = "tired_refuse"
    case fullRefuse = "full_refuse"
    case cuddleGive = "cuddle_give"
    case cuddleReceive = "cuddle_receive"
    case flowerGive = "flower_give"
    case flowerReceive = "flower_receive"
    case letterGive = "letter_give"
    case wave
    case welcome
}

public enum PetMotionRole: String, Codable, Sendable {
    case single
    case giver
    case receiver
}

public enum PetVisitMotionPhase: String, Codable, Sendable {
    case none
    case walkingIn = "walking_in"
    case welcome
    case active
    case waveGoodbye = "wave_goodbye"
    case walkingOut = "walking_out"
}

public enum PetMotionSemanticAction: String, Codable, Sendable {
    case letter
    case welcome
    case wave
}

/// A single deterministic mapping point for runtime state, care outcomes and
/// visit choreography. Presentation code never substitutes a generic gift clip.
public enum PetMotionResolver {
    public static func resolve(
        activity: PetActivity,
        emotion: PetEmotion,
        interaction: PetCareInteractionKind? = nil,
        outcome: PetInteractionOutcome = .applied,
        role: PetMotionRole = .single,
        visitPhase: PetVisitMotionPhase = .none,
        semanticAction: PetMotionSemanticAction? = nil
    ) -> PetMotionClipID {
        if let phaseClip = clip(for: visitPhase) {
            return phaseClip
        }
        if let semanticAction {
            switch semanticAction {
            case .letter: return .letterGive
            case .welcome: return .welcome
            case .wave: return .wave
            }
        }
        switch outcome {
        case .tooFull:
            return .fullRefuse
        case .tooTired, .restingCooldown:
            return .tiredRefuse
        case .applied, .cosmeticOnly:
            break
        }
        if let interaction {
            switch interaction {
            case .pet: return .petReceive
            case .feed: return .eat
            case .play: return .play
            case .walk: return .walk
            case .rest: return .sleep
            case .cuddle: return role == .giver ? .cuddleGive : .cuddleReceive
            case .flower: return role == .receiver ? .flowerReceive : .flowerGive
            }
        }
        switch activity {
        case .idle:
            switch emotion {
            case .sleepy: return .sleep
            case .shy: return .shy
            case .happy, .excited, .grateful, .playful: return .happy
            case .content: return .idle
            }
        case .walking: return .walk
        case .interacting, .petting: return .petReceive
        case .eating: return .eat
        case .playing: return .play
        case .sleeping: return .sleep
        case .celebrating: return .happy
        case .offeringGift:
            return role == .receiver ? .flowerReceive : .flowerGive
        }
    }

    private static func clip(for phase: PetVisitMotionPhase) -> PetMotionClipID? {
        switch phase {
        case .none, .active: return nil
        case .walkingIn, .walkingOut: return .walk
        case .welcome: return .welcome
        case .waveGoodbye: return .wave
        }
    }
}
