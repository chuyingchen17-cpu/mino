import AppKit
import MinoDomain
import SwiftUI

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
                    // PetFrames share y=102 on a 120pt canvas, so the shadow
                    // stays on the same ground line at every presentation size.
                    .offset(y: size * 0.35)
                    .accessibilityHidden(true)
            }

            if let frame = frameResolution.image {
                Image(nsImage: frame)
                    .resizable()
                    .interpolation(.medium)
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
