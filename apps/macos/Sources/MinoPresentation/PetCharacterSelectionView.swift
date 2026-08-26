import MinoDomain
import SwiftUI

package struct PetCharacterSelectionPresentation: Equatable, Sendable {
    package let state: PetCharacterSelectionState

    package init(state: PetCharacterSelectionState) {
        self.state = state
    }

    package var selectedCharacterID: PetCharacterID? {
        switch state {
        case .hidden:
            nil
        case .required(let preselected), .failed(let preselected, _):
            preselected
        case .saving(let characterID),
             .pendingSync(let characterID),
             .confirmed(let characterID),
             .conflict(let characterID):
            characterID
        }
    }

    package var locksChoice: Bool {
        switch state {
        case .saving, .pendingSync, .confirmed, .conflict:
            true
        case .failed(let preselected, _):
            preselected != nil
        case .hidden, .required:
            false
        }
    }

    package var isWorking: Bool {
        if case .saving = state { return true }
        return false
    }

    package var status: (symbol: String, title: String, detail: String)? {
        switch state {
        case .hidden, .required:
            nil
        case .saving:
            ("arrow.triangle.2.circlepath", "正在确认角色", "先保存到这台 Mac，再同步到你的账号。")
        case .pendingSync:
            ("clock.arrow.circlepath", "角色已在本机生效", "网络恢复后会自动同步，不需要重新选择。")
        case .confirmed:
            ("checkmark.seal.fill", "角色已确认", "它现在会出现在桌面、好友页和每一次串门里。")
        case .conflict(let authoritative):
            (
                "macbook.and.iphone",
                "已采用另一台设备的选择",
                "你的账号已先确认\(PetCharacterOption(authoritative).displayName)，本机已同步这一结果。"
            )
        case .failed(_, let message):
            ("exclamationmark.circle.fill", "暂时没有同步成功", message)
        }
    }

    package var completionButtonTitle: String? {
        switch state {
        case .pendingSync, .confirmed:
            "完成"
        case .conflict:
            "知道了"
        case .hidden, .required, .saving, .failed:
            nil
        }
    }
}

/// One-time character choice shown after account bootstrap.
/// There is deliberately no dismiss or back affordance: the choice is permanent.
package struct PetCharacterSelectionView: View {
    package let state: PetCharacterSelectionState
    package let onSelect: (PetCharacterID) -> Void
    package let onAcknowledge: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedCharacterID: PetCharacterID?

    package init(
        state: PetCharacterSelectionState,
        onSelect: @escaping (PetCharacterID) -> Void,
        onAcknowledge: @escaping () -> Void
    ) {
        self.state = state
        self.onSelect = onSelect
        self.onAcknowledge = onAcknowledge
        _selectedCharacterID = State(
            initialValue: PetCharacterSelectionPresentation(state: state).selectedCharacterID
        )
    }

    package var body: some View {
        let presentation = PetCharacterSelectionPresentation(state: state)

        VStack(alignment: .leading, spacing: MinoDesign.Spacing.lg) {
            VStack(alignment: .leading, spacing: MinoDesign.Spacing.xs) {
                Text("选择你的 Mino")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.minoInk)
                Text("从今天起，它会一直陪着你。确认后角色永久固定，名字仍然可以修改。")
                    .font(MinoDesign.Typography.body)
                    .foregroundStyle(Color.minoMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(alignment: .top, spacing: MinoDesign.Spacing.md) {
                ForEach(PetCharacterOption.all, id: \.stableID) { option in
                    characterButton(
                        option,
                        isSelected: selectedCharacterID == option.id,
                        isDisabled: presentation.locksChoice
                    )
                }
            }

            if let status = presentation.status {
                HStack(alignment: .top, spacing: MinoDesign.Spacing.sm) {
                    if presentation.isWorking {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 20, height: 20)
                            .accessibilityHidden(true)
                    } else {
                        Image(systemName: status.symbol)
                            .font(.system(size: MinoDesign.Size.icon, weight: .semibold))
                            .foregroundStyle(statusTint)
                            .frame(width: 20, height: 20)
                            .accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: MinoDesign.Spacing.xxs) {
                        Text(status.title)
                            .font(MinoDesign.Typography.bodyStrong)
                            .foregroundStyle(Color.minoInk)
                        Text(status.detail)
                            .font(MinoDesign.Typography.caption)
                            .foregroundStyle(Color.minoMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(MinoDesign.Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(statusTint.opacity(0.09), in: RoundedRectangle(
                    cornerRadius: MinoDesign.Radius.control,
                    style: .continuous
                ))
                .accessibilityElement(children: .combine)
            }

            HStack(spacing: MinoDesign.Spacing.sm) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.minoFaint)
                Text("角色会绑定到你的账号，无法在个人页中切换。")
                    .font(MinoDesign.Typography.caption)
                    .foregroundStyle(Color.minoFaint)
                Spacer()

                if let title = presentation.completionButtonTitle {
                    Button(title, action: onAcknowledge)
                        .buttonStyle(PetCharacterSelectionPrimaryButtonStyle())
                        .frame(minHeight: MinoDesign.Size.primaryControl)
                } else {
                    Button {
                        guard let selectedCharacterID else { return }
                        onSelect(selectedCharacterID)
                    } label: {
                        if presentation.isWorking {
                            HStack(spacing: MinoDesign.Spacing.xs) {
                                ProgressView().controlSize(.small)
                                Text("正在确认")
                            }
                        } else {
                            Label(
                                state.isRetry ? "重新同步这个角色" : "确认这个角色",
                                systemImage: "checkmark"
                            )
                        }
                    }
                    .buttonStyle(PetCharacterSelectionPrimaryButtonStyle())
                    .disabled(selectedCharacterID == nil || presentation.isWorking)
                    .frame(minHeight: MinoDesign.Size.primaryControl)
                    .accessibilityHint("确认后不能更换角色")
                }
            }
        }
        .padding(MinoDesign.Spacing.xl)
        .frame(width: 650)
        .background(Color.minoCanvas)
        .onChange(of: state) { _, newState in
            if let authoritative = PetCharacterSelectionPresentation(state: newState).selectedCharacterID {
                selectedCharacterID = authoritative
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("选择你的 Mino，角色确认后永久固定")
    }

    private func characterButton(
        _ option: PetCharacterOption,
        isSelected: Bool,
        isDisabled: Bool
    ) -> some View {
        Button {
            selectedCharacterID = option.id
        } label: {
            VStack(spacing: MinoDesign.Spacing.sm) {
                ZStack(alignment: .topTrailing) {
                    PetCharacterView(
                        characterID: option.id,
                        size: 148,
                        clip: .welcome,
                        progress: 0.5,
                        reduceMotion: reduceMotion,
                        showsShadow: true
                    )
                    .frame(maxWidth: .infinity, minHeight: 156)

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.minoCoral : Color.minoFaint)
                        .accessibilityHidden(true)
                }
                Text(option.displayName)
                    .font(MinoDesign.Typography.sectionTitle)
                    .foregroundStyle(Color.minoInk)
                Text(option.detail)
                    .font(MinoDesign.Typography.caption)
                    .foregroundStyle(Color.minoMuted)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .padding(MinoDesign.Spacing.md)
            .frame(maxWidth: .infinity, minHeight: 248)
            .background(
                isSelected ? Color.minoCoralSoft : Color.minoSurface,
                in: RoundedRectangle(cornerRadius: MinoDesign.Radius.prominent, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: MinoDesign.Radius.prominent, style: .continuous)
                    .stroke(
                        isSelected ? Color.minoCoral : Color.minoLine.opacity(0.72),
                        lineWidth: isSelected ? 2 : 1
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: MinoDesign.Radius.prominent, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled && !isSelected ? 0.48 : 1)
        .animation(reduceMotion ? nil : .easeOut(duration: MinoDesign.Motion.quick), value: isSelected)
        .accessibilityLabel("选择(option.displayName)")
        .accessibilityValue(isSelected ? "已选择" : "未选择")
        .accessibilityHint("角色确认后不能更换")
        .frame(minWidth: 44, minHeight: 44)
    }

    private var statusTint: Color {
        switch state {
        case .failed:
            .minoDanger
        case .pendingSync:
            .minoWarning
        case .saving, .required, .hidden:
            .minoCoral
        case .confirmed, .conflict:
            .minoMint
        }
    }
}

/// Compact, reusable character representation for avatars and invite surfaces.
package struct PetCharacterAvatar: View {
    package let characterID: PetCharacterID
    package let petName: String
    package var size: CGFloat
    package var isSelected: Bool
    package var clip: PetMotionClipID

    package init(
        characterID: PetCharacterID,
        petName: String,
        size: CGFloat = 44,
        isSelected: Bool = false,
        clip: PetMotionClipID = .idle
    ) {
        self.characterID = characterID
        self.petName = petName
        self.size = size
        self.isSelected = isSelected
        self.clip = clip
    }

    package var body: some View {
        PetCharacterView(
            characterID: characterID,
            size: size * 0.88,
            clip: clip,
            progress: clip == .welcome ? 0.5 : 0,
            showsShadow: false
        )
            .frame(width: size, height: size)
            .background(Color.minoCoralSoft.opacity(0.62), in: Circle())
            .overlay {
                Circle().stroke(isSelected ? Color.minoCoral : Color.minoLine.opacity(0.5), lineWidth: 2)
            }
            .accessibilityLabel("\(petName)的角色头像，\(PetCharacterOption(characterID).displayName)")
    }
}

/// Read-only identity card used by profile, friend detail and empty-state surfaces.
package struct ReadOnlyPetCharacterCard: View {
    package let characterID: PetCharacterID
    package let petName: String
    package let detail: String
    package var characterSize: CGFloat

    package init(
        characterID: PetCharacterID,
        petName: String,
        detail: String,
        characterSize: CGFloat = 92
    ) {
        self.characterID = characterID
        self.petName = petName
        self.detail = detail
        self.characterSize = characterSize
    }

    package var body: some View {
        HStack(spacing: MinoDesign.Spacing.md) {
            PetCharacterView(characterID: characterID, size: characterSize)
                .frame(width: characterSize + 8, height: characterSize)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: MinoDesign.Spacing.xxs) {
                Text(petName)
                    .font(MinoDesign.Typography.sectionTitle)
                    .foregroundStyle(Color.minoInk)
                Text(PetCharacterOption(characterID).displayName)
                    .font(MinoDesign.Typography.label)
                    .foregroundStyle(Color.minoCoral)
                Text(detail)
                    .font(MinoDesign.Typography.caption)
                    .foregroundStyle(Color.minoMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(MinoDesign.Spacing.md)
        .background(Color.minoCanvas, in: RoundedRectangle(
            cornerRadius: MinoDesign.Radius.card,
            style: .continuous
        ))
        .overlay {
            RoundedRectangle(cornerRadius: MinoDesign.Radius.card, style: .continuous)
                .stroke(Color.minoLine.opacity(0.62), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(petName)，\(PetCharacterOption(characterID).displayName)，\(detail)")
    }
}

package struct PetCharacterPairView: View {
    package var size: CGFloat = 78

    package var body: some View {
        HStack(spacing: -size * 0.15) {
            PetCharacterView(
                characterID: .malteseWhite,
                size: size,
                clip: .welcome,
                progress: 0.5,
                showsShadow: false
            )
            PetCharacterView(
                characterID: .retrieverYellow,
                size: size,
                clip: .welcome,
                facing: .left,
                progress: 0.5,
                showsShadow: false
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("白色马尔济斯和黄色小金毛")
    }
}

private struct PetCharacterOption: Sendable {
    let id: PetCharacterID
    let displayName: String
    let detail: String
    var stableID: String { id.rawValue }

    init(_ id: PetCharacterID) {
        self.id = id
        switch id {
        case .malteseWhite:
            displayName = "白色马尔济斯"
            detail = "软乎乎的小白团，安静又亲人"
        case .retrieverYellow:
            displayName = "黄色小金毛"
            detail = "暖呼呼的小太阳，活泼又坦率"
        }
    }

    static let all: [Self] = [
        Self(.malteseWhite),
        Self(.retrieverYellow)
    ]
}

private extension PetCharacterSelectionState {
    var isRetry: Bool {
        if case .failed = self { return true }
        return false
    }
}

private struct PetCharacterSelectionPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(MinoDesign.Typography.bodyStrong)
            .foregroundStyle(Color.white.opacity(isEnabled ? 1 : 0.72))
            .padding(.horizontal, MinoDesign.Spacing.md)
            .frame(minWidth: 118, minHeight: MinoDesign.Size.primaryControl)
            .background(
                isEnabled
                    ? (configuration.isPressed ? Color.minoCoralPressed : Color.minoCoral)
                    : Color.minoCoral.opacity(0.42),
                in: RoundedRectangle(cornerRadius: MinoDesign.Radius.control, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: MinoDesign.Radius.control, style: .continuous))
    }
}
