import MinoDomain
import SwiftUI

struct SocialEmptyState: View {
    let symbol: String
    let title: String
    let detail: String
    var actionTitle: String?
    var action: (() -> Void)?

    init(
        symbol: String,
        title: String,
        detail: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.symbol = symbol
        self.title = title
        self.detail = detail
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(spacing: MinoDesign.Spacing.sm) {
            ZStack(alignment: .topTrailing) {
                PetCharacterPairView(size: 58)
                Image(systemName: symbol)
                    .font(.system(size: MinoDesign.Size.iconSmall, weight: .semibold))
                    .foregroundStyle(Color.minoCoral)
                    .frame(width: 30, height: 30)
                    .background(Color.minoSurfaceRaised, in: Circle())
                    .overlay { Circle().stroke(Color.minoLine.opacity(0.6), lineWidth: 1) }
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(MinoDesign.Typography.sectionTitle)
                .foregroundStyle(Color.minoInk)
                .multilineTextAlignment(.center)
            Text(detail)
                .font(MinoDesign.Typography.body)
                .foregroundStyle(Color.minoMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(MinoRowButtonStyle(isEmphasized: true))
                    .padding(.top, MinoDesign.Spacing.xs)
            }
        }
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(MinoDesign.Spacing.xl)
        .accessibilityElement(children: .contain)
    }
}

struct SocialLoadingState: View {
    let title: String

    var body: some View {
        ProgressView(title)
            .controlSize(.small)
            .font(MinoDesign.Typography.body)
            .foregroundStyle(Color.minoMuted)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct CloudSyncNotice: View {
    let state: CloudSyncState
    let hasCachedContent: Bool
    let retry: () -> Void

    var body: some View {
        HStack(spacing: MinoDesign.Spacing.sm) {
            if state == .connecting {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: state.systemImage)
                    .font(.system(size: MinoDesign.Size.iconSmall, weight: .semibold))
                    .foregroundStyle(tint)
            }
            Text(message)
                .font(MinoDesign.Typography.caption.weight(.medium))
                .foregroundStyle(Color.minoMuted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: MinoDesign.Spacing.sm)
            if state == .unavailable {
                Button("重试", action: retry)
                    .buttonStyle(MinoTextButtonStyle())
            }
        }
        .padding(.horizontal, MinoDesign.Spacing.md)
        .frame(maxWidth: MinoDesign.Size.contentMax, minHeight: 44, alignment: .leading)
        .background(Color.minoSurface, in: RoundedRectangle(
            cornerRadius: MinoDesign.Radius.control,
            style: .continuous
        ))
        .overlay {
            RoundedRectangle(cornerRadius: MinoDesign.Radius.control, style: .continuous)
                .stroke(Color.minoLine.opacity(0.72), lineWidth: 1)
        }
        .padding(.horizontal, MinoDesign.Spacing.xxxl)
        .padding(.bottom, MinoDesign.Spacing.sm)
    }

    private var message: String {
        switch state {
        case .localOnly: "当前内容仅保存在此 Mac。"
        case .connecting: hasCachedContent ? "正在同步账号状态，先显示上次内容。" : "正在同步账号状态。"
        case .synced: "账号内容已同步。"
        case .pending: "本地更改已经生效，将在网络恢复后自动同步。"
        case .unavailable: hasCachedContent ? "云端暂不可用，当前展示上次内容。" : "云端暂不可用。"
        }
    }

    private var tint: Color {
        switch state {
        case .localOnly, .pending: .minoWarning
        case .connecting: .minoCoral
        case .synced: .minoMint
        case .unavailable: .minoDanger
        }
    }
}

struct MinoFeedbackRow: View {
    let message: String
    let symbol: String
    let tint: Color

    var body: some View {
        Label(message, systemImage: symbol)
            .font(MinoDesign.Typography.label)
            .foregroundStyle(tint)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct FeatureHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    let trailing: Trailing

    init(
        title: String,
        subtitle: String,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: MinoDesign.Spacing.lg) {
            VStack(alignment: .leading, spacing: MinoDesign.Spacing.xxs) {
                Text(title)
                    .font(MinoDesign.Typography.pageTitle)
                    .foregroundStyle(Color.minoInk)
                Text(subtitle)
                    .font(MinoDesign.Typography.pageSubtitle)
                    .foregroundStyle(Color.minoMuted)
            }
            Spacer()
            trailing
        }
        .padding(.top, 52)
        .padding(.horizontal, MinoDesign.Spacing.xxxl)
        .padding(.bottom, MinoDesign.Spacing.lg)
    }
}

extension FeatureHeader where Trailing == EmptyView {
    init(title: String, subtitle: String) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = EmptyView()
    }
}

struct MinoCompactButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(MinoDesign.Typography.bodyStrong)
            .foregroundStyle(Color.white.opacity(isEnabled ? 1 : 0.76))
            .padding(.horizontal, MinoDesign.Spacing.md)
            .frame(height: MinoDesign.Size.control)
            .background(
                isEnabled
                    ? (configuration.isPressed ? Color.minoCoralPressed : Color.minoCoral)
                    : Color.minoCoral.opacity(0.42),
                in: RoundedRectangle(cornerRadius: MinoDesign.Radius.control, style: .continuous)
            )
            .animation(.easeOut(duration: MinoDesign.Motion.quick), value: configuration.isPressed)
    }
}

struct MinoSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(MinoDesign.Typography.bodyStrong)
            .foregroundStyle(Color.minoInk.opacity(isEnabled ? 1 : 0.46))
            .padding(.horizontal, MinoDesign.Spacing.sm)
            .frame(height: MinoDesign.Size.control)
            .background(
                Color.minoSurfaceRaised.opacity(configuration.isPressed ? 0.62 : 1),
                in: RoundedRectangle(cornerRadius: MinoDesign.Radius.control, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: MinoDesign.Radius.control, style: .continuous)
                    .stroke(Color.minoLine, lineWidth: 1)
            }
            .animation(.easeOut(duration: MinoDesign.Motion.quick), value: configuration.isPressed)
    }
}

struct MinoTextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(MinoDesign.Typography.bodyStrong)
            .foregroundStyle(Color.minoInk.opacity(configuration.isPressed ? 0.54 : 0.82))
            .padding(.horizontal, MinoDesign.Spacing.sm)
            .frame(height: MinoDesign.Size.control)
    }
}

struct MinoDangerTextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(MinoDesign.Typography.bodyStrong)
            .foregroundStyle(Color.minoDanger.opacity(configuration.isPressed ? 0.58 : 1))
            .padding(.horizontal, MinoDesign.Spacing.sm)
            .frame(height: MinoDesign.Size.control)
    }
}

struct MinoRowButtonStyle: ButtonStyle {
    let isEmphasized: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(MinoDesign.Typography.label)
            .foregroundStyle(isEmphasized ? Color.white : Color.minoInk)
            .padding(.horizontal, MinoDesign.Spacing.sm)
            .frame(height: 36)
            .background(
                isEmphasized
                    ? (configuration.isPressed ? Color.minoCoralPressed : Color.minoCoral)
                    : Color.minoSurface.opacity(configuration.isPressed ? 0.62 : 1),
                in: RoundedRectangle(cornerRadius: MinoDesign.Radius.control, style: .continuous)
            )
            .overlay {
                if !isEmphasized {
                    RoundedRectangle(cornerRadius: MinoDesign.Radius.control, style: .continuous)
                        .stroke(Color.minoLine, lineWidth: 1)
                }
            }
    }
}

