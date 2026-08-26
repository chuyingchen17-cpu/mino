import MinoDomain
import SwiftUI

private enum SharedSpaceDestination: String, CaseIterable, Identifiable {
    case friends
    case timeline
    case friendDetail
    case profile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .friends: "好友"
        case .timeline: "事件线"
        case .friendDetail: "好友详情"
        case .profile: "个人页"
        }
    }

    var symbol: String {
        switch self {
        case .friends: "person.2.fill"
        case .timeline: "clock.arrow.circlepath"
        case .friendDetail: "person.crop.circle"
        case .profile: "person.crop.circle"
        }
    }

    static var sidebarCases: [Self] { [.friends, .timeline] }
}

struct SharedSpaceView: View {
    @Bindable var model: SharedSpaceModel
    let debugIdentityLabel: String?
    let identity: SharedSpaceIdentity
    let onFriendAction: (FriendDirectoryAction) -> Void
    let onProfileAction: (ProfileAction) -> Void
    let onOpenLetter: (LetterID) -> Void

    @State private var destination: SharedSpaceDestination = .friends

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: MinoDesign.Size.sidebar)
                // Keep navigation above full-bleed content so page swaps cannot
                // leave a stale content hit region covering the sidebar.
                .zIndex(1)

            Group {
                switch destination {
                case .friends:
                    FriendDirectoryView(
                        friends: model.friends,
                        requests: model.friendRequests,
                        localAccountID: model.localAccountID,
                        authenticationState: model.authenticationState,
                        cloudSyncState: model.cloudSyncState,
                        selectedFriendshipID: model.selectedFriendshipID,
                        activeVisitFriendshipID: model.activeVisitFriendshipID,
                        visitState: model.visitState,
                        operationInProgress: model.friendOperationInProgress,
                        friendErrorMessage: model.friendErrorMessage,
                        visitErrorMessage: model.visitErrorMessage,
                        characterIDs: model.friendCharacterIDs,
                        perform: onFriendAction,
                        openFriend: { friendshipID in
                            onFriendAction(.selectFriend(friendshipID))
                            destination = .friendDetail
                        },
                        openProfile: { destination = .profile }
                    )
                case .timeline:
                    TimelineFoundationView(
                        events: model.reversedTimelineEvents,
                        friends: model.friends,
                        identity: model.identity(fallingBackTo: identity),
                        authenticationState: model.authenticationState,
                        cloudSyncState: model.cloudSyncState,
                        onOpenLetter: onOpenLetter,
                        openFriends: { destination = .friends },
                        openProfile: { destination = .profile },
                        retry: { onFriendAction(.refresh) }
                    )
                case .friendDetail:
                    FriendDetailView(
                        friend: model.selectedFriend,
                        events: model.selectedFriendEvents,
                        identity: model.identity(fallingBackTo: identity),
                        isLoading: model.selectedFriend.map {
                            model.isFriendTimelineLoading($0.friendshipID)
                        } ?? false,
                        errorMessage: model.selectedFriend.flatMap {
                            model.friendTimelineError[$0.friendshipID]
                        },
                        visitState: model.visitState,
                        activeVisitFriendshipID: model.activeVisitFriendshipID,
                        operationInProgress: model.friendOperationInProgress,
                        characterID: model.selectedFriend.map(model.characterID(for:)) ?? .retrieverYellow,
                        perform: onFriendAction,
                        onOpenLetter: onOpenLetter,
                        back: { destination = .friends }
                    )
                case .profile:
                    ProfileView(
                        profile: model.currentProfile,
                        identity: identity,
                        careState: model.ownPetCare,
                        cloudSyncState: model.cloudSyncState,
                        authenticationState: model.authenticationState,
                        githubDeviceCodeWasAutoCopied: model.githubDeviceCodeWasAutoCopied,
                        authenticationOperationInProgress: model.authenticationOperationInProgress,
                        authenticationErrorMessage: model.authenticationErrorMessage,
                        profileOperationInProgress: model.profileOperationInProgress,
                        profileErrorMessage: model.profileErrorMessage,
                        profileSuccessMessage: model.profileSuccessMessage,
                        characterID: model.ownPetCharacterID,
                        perform: onProfileAction
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.minoCanvas)
        .ignoresSafeArea()
        .frame(minWidth: 900, idealWidth: 1_080, minHeight: 640, idealHeight: 760)
        .sheet(isPresented: characterSelectionPresented) {
            PetCharacterSelectionView(
                state: model.petCharacterSelectionState,
                onSelect: { onProfileAction(.selectPetCharacter($0)) },
                onAcknowledge: { onProfileAction(.acknowledgePetCharacterSelection) }
            )
            .interactiveDismissDisabled()
        }
        .onChange(of: model.authenticationState) { _, state in
            if destination == .friendDetail {
                switch state {
                case .signedOut, .waitingForGitHub:
                    destination = .friends
                case .offline, .signedIn:
                    break
                }
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Mino")
                .font(MinoDesign.Typography.brand)
                .foregroundStyle(Color.minoCoral)
                .padding(.horizontal, MinoDesign.Spacing.lg)
                .padding(.top, 54)
                .padding(.bottom, MinoDesign.Spacing.lg)

            if let debugIdentityLabel {
                Label(debugIdentityLabel, systemImage: "ladybug.fill")
                    .font(MinoDesign.Typography.caption.weight(.semibold))
                    .foregroundStyle(Color.minoCoral)
                    .lineLimit(1)
                    .padding(.horizontal, 11)
                    .frame(height: 28)
                    .background(Color.minoCoralSoft, in: Capsule())
                    .padding(.horizontal, MinoDesign.Spacing.lg)
                    .padding(.top, -16)
                    .padding(.bottom, MinoDesign.Spacing.md)
                    .accessibilityLabel("Debug 当前实例 \(debugIdentityLabel)")
            }

            VStack(spacing: MinoDesign.Spacing.xs) {
                ForEach(SharedSpaceDestination.sidebarCases) { item in
                    SidebarItem(
                        destination: item,
                        isSelected: destination == item,
                        action: { destination = item }
                    )
                }
            }
            .padding(.horizontal, MinoDesign.Spacing.md)

            Spacer()

            Button {
                destination = .profile
            } label: {
                HStack(spacing: MinoDesign.Spacing.sm) {
                PetCharacterAvatar(
                    characterID: model.ownPetCharacterID ?? .malteseWhite,
                    petName: model.currentProfile?.petName ?? identity.localPetName,
                    size: 38,
                    isSelected: destination == .profile
                )

                VStack(alignment: .leading, spacing: MinoDesign.Spacing.xxs) {
                    Text(model.currentProfile?.accountName ?? "我的 Mino")
                        .font(MinoDesign.Typography.bodyStrong)
                        .foregroundStyle(Color.minoInk)
                    Text(model.currentProfile?.petName ?? identity.localPetName)
                        .font(MinoDesign.Typography.caption)
                        .foregroundStyle(Color.minoMuted)
                    HStack(spacing: MinoDesign.Spacing.xxs) {
                        Circle()
                            .fill(profileSyncTint)
                            .frame(width: 7, height: 7)
                        Text(profileSyncStatus)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.minoMuted)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.minoFaint)
                }
                .padding(MinoDesign.Spacing.sm)
                .background(
                    destination == .profile ? Color.minoSurface : Color.clear,
                    in: RoundedRectangle(cornerRadius: MinoDesign.Radius.card, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .help("打开个人页")
            .accessibilityLabel("打开个人页")
            .padding(.horizontal, MinoDesign.Spacing.md)
            .padding(.bottom, MinoDesign.Spacing.md)
        }
        .frame(maxHeight: .infinity)
        .background(Color.minoSidebar)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.minoLine.opacity(0.72))
                .frame(width: 1)
        }
        .frame(width: MinoDesign.Size.sidebar)
    }

    private var profileSyncStatus: String {
        switch model.authenticationState {
        case .offline: "仅保存在此 Mac"
        case .signedOut: "等待登录"
        case .waitingForGitHub: "正在登录"
        case .signedIn: model.cloudSyncState.statusText
        }
    }

    private var profileSyncTint: Color {
        switch model.authenticationState {
        case .offline: .minoWarning
        case .signedOut: .minoFaint
        case .waitingForGitHub: .minoCoral
        case .signedIn:
            switch model.cloudSyncState {
            case .localOnly, .pending: .minoWarning
            case .connecting: .minoCoral
            case .synced: .minoMint
            case .unavailable: .minoDanger
            }
        }
    }

    private var characterSelectionPresented: Binding<Bool> {
        Binding(
            get: { model.petCharacterSelectionState.isPresented },
            set: { _ in }
        )
    }
}

private struct SidebarItem: View {
    let destination: SharedSpaceDestination
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: MinoDesign.Spacing.sm) {
                Image(systemName: destination.symbol)
                    .font(.system(size: MinoDesign.Size.icon, weight: .semibold))
                    .frame(width: 22)
                Text(destination.title)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                Spacer()
            }
            .foregroundStyle(isSelected ? Color.minoCoral : Color.minoInk.opacity(0.82))
            .padding(.horizontal, MinoDesign.Spacing.sm)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: MinoDesign.Radius.control, style: .continuous)
                    .fill(isSelected ? Color.minoCoralSoft : Color.minoSurface.opacity(isHovering ? 0.72 : 0))
            )
            .contentShape(Rectangle())
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: MinoDesign.Motion.quick), value: isHovering)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
