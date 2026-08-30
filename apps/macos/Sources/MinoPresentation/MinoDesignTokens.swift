import AppKit
import SwiftUI

/// Semantic design tokens for the macOS product surface.
///
/// Views consume roles such as `surface` and `textSecondary`; raw RGB values
/// stay in this file so light/dark behavior and contrast can evolve together.
enum MinoDesign {
    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 40
        static let xxxl: CGFloat = 48
    }

    enum Radius {
        static let control: CGFloat = 10
        static let card: CGFloat = 16
        static let prominent: CGFloat = 20
        static let capsule: CGFloat = 999
        static let petAccessory: CGFloat = 14
        static let speechBubble: CGFloat = 18
    }

    enum Size {
        static let iconSmall: CGFloat = 14
        static let icon: CGFloat = 17
        static let iconLarge: CGFloat = 22
        static let control: CGFloat = 40
        static let primaryControl: CGFloat = 44
        static let sidebar: CGFloat = 224
        static let contentMax: CGFloat = 720
        static let formMax: CGFloat = 560
        static let petActionBar = CGSize(width: 252, height: 42)
        /// 说话气泡按文字量伸缩，只约束上下限：太窄会把短句拆行，太宽会横穿桌面。
        static let petSpeechMinWidth: CGFloat = 92
        static let petSpeechMaxWidth: CGFloat = 264
    }

    enum Typography {
        static let brand = Font.system(size: 28, weight: .heavy, design: .rounded)
        static let pageTitle = Font.system(size: 28, weight: .bold, design: .rounded)
        static let pageSubtitle = Font.system(size: 13, weight: .regular)
        static let sectionTitle = Font.system(size: 16, weight: .bold)
        static let body = Font.system(size: 13, weight: .regular)
        static let bodyStrong = Font.system(size: 13, weight: .semibold)
        static let label = Font.system(size: 12, weight: .semibold)
        static let caption = Font.system(size: 11, weight: .regular)
        static let code = Font.system(size: 16, weight: .bold, design: .monospaced)
    }

    enum Motion {
        static let quick = 0.16
        static let standard = 0.24
        static let petHoverDelay = 0.20
        static let petFeedbackDuration = 2.40
    }
}

extension Color {
    static let minoCanvas = minoAdaptive(light: 0xFBF7F2, dark: 0x1D1816)
    static let minoSidebar = minoAdaptive(light: 0xF3EBE3, dark: 0x241E1B)
    static let minoSurface = minoAdaptive(light: 0xFFFDFC, dark: 0x2B2420)
    static let minoSurfaceRaised = minoAdaptive(light: 0xFFFFFF, dark: 0x342A26)
    static let minoInk = minoAdaptive(light: 0x302824, dark: 0xF7F0EB)
    static let minoMuted = minoAdaptive(light: 0x6D625C, dark: 0xC5B8B0)
    static let minoFaint = minoAdaptive(light: 0x948983, dark: 0x9F928B)
    static let minoCoral = minoAdaptive(light: 0xE8545B, dark: 0xFF7C82)
    static let minoCoralPressed = minoAdaptive(light: 0xCD424A, dark: 0xE9646B)
    static let minoCoralSoft = minoAdaptive(light: 0xFBE7E5, dark: 0x48292B)
    static let minoMint = minoAdaptive(light: 0x197A68, dark: 0x58C9AE)
    static let minoMintSoft = minoAdaptive(light: 0xE4F3EE, dark: 0x203D36)
    static let minoWarning = minoAdaptive(light: 0xA96713, dark: 0xF0B861)
    static let minoDanger = minoAdaptive(light: 0xB83E45, dark: 0xFF8589)
    static let minoLine = minoAdaptive(light: 0xDED4CC, dark: 0x493E38)
    static let minoFocus = minoAdaptive(light: 0xB8333C, dark: 0xFF9BA0)

    private static func minoAdaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(minoRGB: isDark ? dark : light)
        })
    }
}

private extension NSColor {
    convenience init(minoRGB value: UInt32) {
        self.init(
            calibratedRed: CGFloat((value >> 16) & 0xff) / 255,
            green: CGFloat((value >> 8) & 0xff) / 255,
            blue: CGFloat(value & 0xff) / 255,
            alpha: 1
        )
    }
}

struct MinoCardModifier: ViewModifier {
    let padding: CGFloat

    init(padding: CGFloat = MinoDesign.Spacing.lg) {
        self.padding = padding
    }

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Color.minoSurface, in: RoundedRectangle(
                cornerRadius: MinoDesign.Radius.card,
                style: .continuous
            ))
            .overlay {
                RoundedRectangle(cornerRadius: MinoDesign.Radius.card, style: .continuous)
                    .stroke(Color.minoLine.opacity(0.72), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.035), radius: 12, y: 4)
    }
}

extension View {
    func minoCard(padding: CGFloat = MinoDesign.Spacing.lg) -> some View {
        modifier(MinoCardModifier(padding: padding))
    }
}
