import Foundation

public struct AvatarColor: Codable, Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public static let cream = AvatarColor(red: 0.96, green: 0.83, blue: 0.67)
    public static let blush = AvatarColor(red: 0.96, green: 0.48, blue: 0.58)
    public static let mint = AvatarColor(red: 0.27, green: 0.78, blue: 0.72)
    public static let lavender = AvatarColor(red: 0.62, green: 0.55, blue: 0.92)
}

public enum AvatarSpecies: String, Codable, Sendable {
    case cat
    case bunny
}

public enum AvatarEyeStyle: String, Codable, Sendable {
    case dots
    case happy
}

public enum AvatarHatStyle: String, Codable, Sendable {
    case none
    case beanie
    case flower
}

public enum AvatarAccessoryStyle: String, Codable, Sendable {
    case none
    case scarf
    case necklace
}

public struct AvatarRecipe: Codable, Equatable, Sendable {
    public var species: AvatarSpecies
    public var bodyColor: AvatarColor
    public var eyeStyle: AvatarEyeStyle
    public var hat: AvatarHatStyle
    public var accessory: AvatarAccessoryStyle

    public init(
        species: AvatarSpecies,
        bodyColor: AvatarColor,
        eyeStyle: AvatarEyeStyle,
        hat: AvatarHatStyle,
        accessory: AvatarAccessoryStyle
    ) {
        self.species = species
        self.bodyColor = bodyColor
        self.eyeStyle = eyeStyle
        self.hat = hat
        self.accessory = accessory
    }

    public static let mine = AvatarRecipe(
        species: .cat,
        bodyColor: .cream,
        eyeStyle: .dots,
        hat: .flower,
        accessory: .necklace
    )

    public static let partner = AvatarRecipe(
        species: .bunny,
        bodyColor: .mint,
        eyeStyle: .happy,
        hat: .beanie,
        accessory: .scarf
    )

    public static let partnerAlternate = AvatarRecipe(
        species: .bunny,
        bodyColor: .lavender,
        eyeStyle: .dots,
        hat: .flower,
        accessory: .necklace
    )
}
