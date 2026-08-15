import AppKit

struct AvatarColor: Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double = 1

    @MainActor
    var nsColor: NSColor {
        NSColor(
            calibratedRed: red,
            green: green,
            blue: blue,
            alpha: alpha
        )
    }

    static let cream = AvatarColor(red: 0.96, green: 0.83, blue: 0.67)
    static let blush = AvatarColor(red: 0.96, green: 0.48, blue: 0.58)
    static let mint = AvatarColor(red: 0.27, green: 0.78, blue: 0.72)
    static let lavender = AvatarColor(red: 0.62, green: 0.55, blue: 0.92)
}

enum AvatarSpecies: Sendable {
    case cat
    case bunny
}

enum AvatarEyeStyle: Sendable {
    case dots
    case happy
}

enum AvatarHatStyle: Sendable {
    case none
    case beanie
    case flower
}

enum AvatarAccessoryStyle: Sendable {
    case none
    case scarf
    case necklace
}

struct AvatarRecipe: Equatable, Sendable {
    var species: AvatarSpecies
    var bodyColor: AvatarColor
    var eyeStyle: AvatarEyeStyle
    var hat: AvatarHatStyle
    var accessory: AvatarAccessoryStyle

    static let mine = AvatarRecipe(
        species: .cat,
        bodyColor: .cream,
        eyeStyle: .dots,
        hat: .flower,
        accessory: .necklace
    )

    static let partner = AvatarRecipe(
        species: .bunny,
        bodyColor: .mint,
        eyeStyle: .happy,
        hat: .beanie,
        accessory: .scarf
    )

    static let partnerAlternate = AvatarRecipe(
        species: .bunny,
        bodyColor: .lavender,
        eyeStyle: .dots,
        hat: .flower,
        accessory: .necklace
    )
}

