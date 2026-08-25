import AppKit
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
    @ObservedObject var model: SharedSpaceModel
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
                        events: Array(model.timelineEvents.reversed()),
                        friends: model.friends,
                        identity: currentIdentity,
                        authenticationState: model.authenticationState,
                        cloudSyncState: model.cloudSyncState,
                        onOpenLetter: onOpenLetter,
                        openFriends: { destination = .friends },
                        openProfile: { destination = .profile },
                        retry: { onFriendAction(.refresh) }
                    )
                case .friendDetail:
                    FriendDetailView(
                        friend: selectedFriend,
                        events: selectedFriendEvents,
                        identity: currentIdentity,
                        isLoading: selectedFriend.map { model.friendTimelineLoading.contains($0.friendshipID) } ?? false,
                        errorMessage: selectedFriend.flatMap { model.friendTimelineError[$0.friendshipID] },
                        visitState: model.visitState,
                        activeVisitFriendshipID: model.activeVisitFriendshipID,
                        operationInProgress: model.friendOperationInProgress,
                        characterID: selectedFriend.map(characterID(for:)) ?? .retrieverYellow,
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

    private var activeVisitFriend: FriendProfile? {
        guard let id = model.activeVisitFriendshipID else { return nil }
        return model.friends.first { $0.friendshipID == id }
    }

    private var selectedFriend: FriendProfile? {
        guard let selectedFriendshipID = model.selectedFriendshipID else { return nil }
        return model.friends.first { $0.friendshipID == selectedFriendshipID }
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

    private var currentIdentity: SharedSpaceIdentity {
        SharedSpaceIdentity(
            localPetName: model.currentProfile?.petName ?? identity.localPetName,
            fallbackFriendPetName: identity.fallbackFriendPetName
        )
    }

    private var selectedFriendEvents: [PersonalTimelineEvent] {
        guard let friendshipID = selectedFriend?.friendshipID else { return [] }
        return (model.friendTimelineEvents[friendshipID] ?? [])
            .sorted { $0.occurredAt > $1.occurredAt }
    }

    private var characterSelectionPresented: Binding<Bool> {
        Binding(
            get: { model.petCharacterSelectionState.isPresented },
            set: { _ in }
        )
    }

    private func characterID(for friend: FriendProfile) -> PetCharacterID {
        model.friendCharacterIDs[friend.petID] ?? friend.characterID ?? .retrieverYellow
    }

}

private struct FriendDirectoryView: View {
    let friends: [FriendProfile]
    let requests: [FriendRequest]
    let localAccountID: AccountID?
    let authenticationState: SharedSpaceAuthenticationState
    let cloudSyncState: CloudSyncState
    let selectedFriendshipID: FriendshipID?
    let activeVisitFriendshipID: FriendshipID?
    let visitState: FriendVisitState
    let operationInProgress: Bool
    let friendErrorMessage: String?
    let visitErrorMessage: String?
    let characterIDs: [PetProfileID: PetCharacterID]
    let perform: (FriendDirectoryAction) -> Void
    let openFriend: (FriendshipID) -> Void
    let openProfile: () -> Void

    @State private var addFriendPresented = false

    private var incomingRequests: [FriendRequest] {
        requests.filter {
            $0.status == .pending && $0.addresseeAccountID == localAccountID
        }
    }

    private var outgoingRequests: [FriendRequest] {
        requests.filter {
            $0.status == .pending && $0.requesterAccountID == localAccountID
        }
    }

    private var hasCachedDirectory: Bool {
        !friends.isEmpty || !requests.isEmpty
    }

    private var allowsSocialMutations: Bool {
        guard authenticationState == .signedIn else { return false }
        return cloudSyncState == .synced || cloudSyncState == .pending
    }

    private var errorMessage: String? {
        friendErrorMessage ?? visitErrorMessage
    }

    var body: some View {
        VStack(spacing: 0) {
            FeatureHeader(
                title: "好友",
                subtitle: "管理好友申请，邀请熟悉的小家伙互相串门"
            ) {
                switch authenticationState {
                case .signedIn:
                    HStack(spacing: 10) {
                        refreshButton
                        Button {
                            addFriendPresented = true
                        } label: {
                            Label("添加好友", systemImage: "person.badge.plus")
                        }
                        .buttonStyle(MinoCompactButtonStyle())
                        .disabled(operationInProgress || !allowsSocialMutations)
                    }
                case .signedOut:
                    Button("前往登录", action: openProfile)
                        .buttonStyle(MinoCompactButtonStyle())
                case .waitingForGitHub:
                    Button("查看登录进度", action: openProfile)
                        .buttonStyle(MinoSecondaryButtonStyle())
                case .offline:
                    EmptyView()
                }
            }

            switch authenticationState {
            case .signedOut:
                SocialEmptyState(
                    symbol: "person.crop.circle.badge.plus",
                    title: "登录后管理好友",
                    detail: "使用 GitHub 登录后，才能添加好友、处理申请和发起串门。",
                    actionTitle: "前往个人页",
                    action: openProfile
                )
            case .waitingForGitHub:
                SocialEmptyState(
                    symbol: "key.fill",
                    title: "正在完成 GitHub 登录",
                    detail: "完成浏览器中的授权后，好友列表会自动恢复。",
                    actionTitle: "查看登录进度",
                    action: openProfile
                )
            case .offline, .signedIn:
                directoryContent
            }
        }
        .background(Color.minoCanvas)
        .sheet(isPresented: $addFriendPresented) {
            AddFriendSheet(
                localAccountID: localAccountID,
                operationInProgress: operationInProgress,
                serverErrorMessage: friendErrorMessage,
                submit: { accountID in
                    perform(.addFriend(accountID))
                },
                complete: { addFriendPresented = false },
                cancel: { addFriendPresented = false }
            )
        }
    }

    @ViewBuilder
    private var directoryContent: some View {
        if authenticationState == .signedIn {
            if cloudSyncState == .connecting, !hasCachedDirectory {
                SocialLoadingState(title: "正在恢复好友列表")
            } else if cloudSyncState == .unavailable, !hasCachedDirectory {
                SocialEmptyState(
                    symbol: "wifi.slash",
                    title: "暂时无法载入好友",
                    detail: "云端连接暂时不可用，请稍后重试。",
                    actionTitle: "重新连接",
                    action: { perform(.refresh) }
                )
            } else {
                directoryScrollView
            }
        } else if hasCachedDirectory {
            directoryScrollView
        } else {
            SocialEmptyState(
                symbol: "wifi.slash",
                title: "好友服务暂不可用",
                detail: "当前未连接 Mino 云服务，本机互动仍可继续。"
            )
        }
    }

    private var directoryScrollView: some View {
        VStack(spacing: 0) {
            if authenticationState == .signedIn,
               cloudSyncState == .connecting || cloudSyncState == .pending || cloudSyncState == .unavailable {
                CloudSyncNotice(
                    state: cloudSyncState,
                    hasCachedContent: hasCachedDirectory,
                    retry: { perform(.refresh) }
                )
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                    .font(MinoDesign.Typography.caption.weight(.medium))
                    .foregroundStyle(Color.minoDanger)
                    .frame(maxWidth: MinoDesign.Size.contentMax, alignment: .leading)
                    .padding(.horizontal, MinoDesign.Spacing.xxxl)
                    .padding(.bottom, MinoDesign.Spacing.sm)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: MinoDesign.Spacing.lg) {
                    if !incomingRequests.isEmpty {
                        friendSection(title: "待处理申请", count: incomingRequests.count) {
                            ForEach(incomingRequests) { request in
                                FriendRequestRow(
                                    request: request,
                                    characterID: characterIDs[request.friendPetID] ?? .retrieverYellow,
                                    operationInProgress: operationInProgress || !allowsSocialMutations,
                                    accept: { perform(.respondToRequest(request.id, .accept)) },
                                    decline: { perform(.respondToRequest(request.id, .decline)) }
                                )
                            }
                        }
                    }

                    if !outgoingRequests.isEmpty {
                        friendSection(title: "已发出的申请", count: outgoingRequests.count) {
                            ForEach(outgoingRequests) { request in
                                OutgoingFriendRequestRow(
                                    request: request,
                                    characterID: characterIDs[request.friendPetID] ?? .retrieverYellow
                                )
                            }
                        }
                    }

                    friendSection(title: "我的好友", count: friends.count) {
                        if friends.isEmpty {
                            FriendEmptyState(addEnabled: allowsSocialMutations) {
                                addFriendPresented = true
                            }
                        } else {
                            ForEach(friends) { friend in
                                FriendRow(
                                    friend: friend,
                                    characterID: characterIDs[friend.petID] ?? friend.characterID ?? .retrieverYellow,
                                    isSelected: friend.friendshipID == selectedFriendshipID,
                                    visitState: visitState,
                                    isActiveVisitFriend: friend.friendshipID == activeVisitFriendshipID,
                                    operationInProgress: operationInProgress || !allowsSocialMutations,
                                    select: { openFriend(friend.friendshipID) },
                                    respond: { perform(.respondToVisit($0)) },
                                    endVisit: {
                                        if friend.friendshipID == activeVisitFriendshipID,
                                           visitState == .visiting || visitState == .ownPetVisiting {
                                            perform(.endVisit)
                                        }
                                    },
                                    inviteFriendPet: { perform(.inviteFriendPet(friend.friendshipID)) },
                                    sendOwnPet: { perform(.sendOwnPet(friend.friendshipID)) }
                                )
                            }
                        }
                    }
                }
                .frame(maxWidth: MinoDesign.Size.contentMax, alignment: .leading)
                .padding(.horizontal, MinoDesign.Spacing.xxxl)
                .padding(.bottom, MinoDesign.Spacing.xxxl)
            }
        }
    }

    private var refreshButton: some View {
        Button {
            perform(.refresh)
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: MinoDesign.Size.iconSmall, weight: .semibold))
                .foregroundStyle(Color.minoInk)
                .frame(width: MinoDesign.Size.control, height: MinoDesign.Size.control)
                .background(Color.minoSurface, in: RoundedRectangle(
                    cornerRadius: MinoDesign.Radius.control,
                    style: .continuous
                ))
                .overlay {
                    RoundedRectangle(cornerRadius: MinoDesign.Radius.control, style: .continuous)
                        .stroke(Color.minoLine, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .disabled(operationInProgress)
        .opacity(operationInProgress ? 0.5 : 1)
        .help("刷新好友与申请")
        .accessibilityLabel("刷新好友与申请")
    }

    private func friendSection<Content: View>(
        title: String,
        count: Int,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: MinoDesign.Spacing.sm) {
            HStack(spacing: MinoDesign.Spacing.xs) {
                Text(title)
                    .font(MinoDesign.Typography.sectionTitle)
                    .foregroundStyle(Color.minoInk)
                Text("\(count)")
                    .font(MinoDesign.Typography.caption.weight(.semibold))
                    .foregroundStyle(Color.minoMuted)
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(Color.minoSurface, in: Capsule())
            }
            content()
        }
    }
}

private struct FriendRow: View {
    let friend: FriendProfile
    let characterID: PetCharacterID
    let isSelected: Bool
    let visitState: FriendVisitState
    let isActiveVisitFriend: Bool
    let operationInProgress: Bool
    let select: () -> Void
    let respond: (VisitResponse) -> Void
    let endVisit: () -> Void
    let inviteFriendPet: () -> Void
    let sendOwnPet: () -> Void

    var body: some View {
        HStack(spacing: MinoDesign.Spacing.sm) {
            Button(action: select) {
                HStack(spacing: MinoDesign.Spacing.sm) {
                    FriendAvatar(
                        characterID: characterID,
                        petName: friend.petName,
                        isSelected: isSelected
                    )
                    VStack(alignment: .leading, spacing: 3) {
                        Text(friend.petName)
                            .font(MinoDesign.Typography.bodyStrong)
                            .foregroundStyle(Color.minoInk)
                        Text(friend.accountName)
                            .font(MinoDesign.Typography.caption)
                            .foregroundStyle(Color.minoMuted)
                        Text(friendCareText)
                            .font(MinoDesign.Typography.caption)
                            .foregroundStyle(Color.minoFaint)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Label(statusText, systemImage: statusSymbol)
                .font(MinoDesign.Typography.caption.weight(.medium))
                .foregroundStyle(isActiveVisitFriend ? Color.minoCoral : Color.minoMuted)
                .frame(width: 126, alignment: .leading)

            if isActiveVisitFriend && visitState == .consideringInvitation {
                Button("拒绝") {
                    respond(.decline)
                }
                .buttonStyle(MinoTextButtonStyle())
                .disabled(operationInProgress)

                Button("接受") {
                    respond(.accept)
                }
                .buttonStyle(MinoRowButtonStyle(isEmphasized: true))
                .disabled(operationInProgress)
            } else {
                if isActiveVisitFriend && (visitState == .visiting || visitState == .ownPetVisiting) {
                    Button(action: endVisit) {
                        Label("结束串门", systemImage: "house.fill")
                            .frame(minWidth: 92)
                    }
                    .buttonStyle(MinoRowButtonStyle(isEmphasized: true))
                    .disabled(operationInProgress)
                } else {
                    Menu {
                        Button("邀请 \(friend.petName) 来我桌面", action: inviteFriendPet)
                        Button("让我的 Mino 去 \(friend.accountName) 家", action: sendOwnPet)
                    } label: {
                        Label("串门", systemImage: "paperplane.fill")
                            .frame(minWidth: 92)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .disabled(operationInProgress || visitDisabled)
                }
            }
        }
        .padding(.horizontal, MinoDesign.Spacing.md)
        .frame(minHeight: 72)
        .background(
            isSelected ? Color.minoCoralSoft : Color.minoSurface,
            in: RoundedRectangle(cornerRadius: MinoDesign.Radius.card, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: MinoDesign.Radius.card, style: .continuous)
                .stroke(isSelected ? Color.minoCoral.opacity(0.35) : Color.minoLine.opacity(0.72), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private var visitDisabled: Bool {
        visitState != .away && !isActiveVisitFriend
    }

    private var statusText: String {
        guard isActiveVisitFriend else { return "可以联系" }
        return switch visitState {
        case .away: "可以联系"
        case .sendingInvitation: "正在发送邀请"
        case .invitationSent: "等待回应"
        case .consideringInvitation: "等待你的决定"
        case .visiting: "正在你这里"
        case .ownPetVisiting: "正在好友家"
        case .returning: "正在回家"
        }
    }

    private var statusSymbol: String {
        isActiveVisitFriend ? "pawprint.fill" : "circle.fill"
    }

    private var visitTitle: String {
        guard isActiveVisitFriend else { return "邀请串门" }
        return switch visitState {
        case .visiting, .ownPetVisiting: "结束串门"
        case .sendingInvitation: "正在发送"
        case .invitationSent, .consideringInvitation: "等待回应"
        case .returning: "正在回家"
        case .away: "邀请串门"
        }
    }

    private var visitSymbol: String {
        isActiveVisitFriend && (visitState == .visiting || visitState == .ownPetVisiting)
            ? "house.fill"
            : "paperplane.fill"
    }

    private var friendCareText: String {
        let familiarity = friend.familiarity?.tier.displayName ?? "初见"
        guard let care = friend.publicCare else { return familiarity }
        return "\(moodText(care.mood)) · \(energyText(care.energy)) · \(familiarity)"
    }

    private func moodText(_ band: PetCareBand) -> String {
        switch band {
        case .low: "有点低落"
        case .steady: "心情平稳"
        case .high: "心情很好"
        }
    }

    private func energyText(_ band: PetCareBand) -> String {
        switch band {
        case .low: "有点累"
        case .steady: "精神还好"
        case .high: "精神很好"
        }
    }
}

private struct FriendRequestRow: View {
    let request: FriendRequest
    let characterID: PetCharacterID
    let operationInProgress: Bool
    let accept: () -> Void
    let decline: () -> Void

    var body: some View {
        HStack(spacing: MinoDesign.Spacing.sm) {
            FriendAvatar(
                characterID: characterID,
                petName: request.friendPetName,
                isSelected: false
            )
            VStack(alignment: .leading, spacing: 3) {
                Text(request.friendPetName)
                    .font(MinoDesign.Typography.bodyStrong)
                    .foregroundStyle(Color.minoInk)
                Text("\(request.friendName) 想加你为好友")
                    .font(MinoDesign.Typography.caption)
                    .foregroundStyle(Color.minoMuted)
            }
            Spacer()
            Button("拒绝", action: decline)
                .buttonStyle(MinoTextButtonStyle())
                .disabled(operationInProgress)
            Button("接受", action: accept)
                .buttonStyle(MinoRowButtonStyle(isEmphasized: true))
                .disabled(operationInProgress)
        }
        .padding(.horizontal, MinoDesign.Spacing.md)
        .frame(minHeight: 72)
        .background(Color.minoSurface, in: RoundedRectangle(cornerRadius: MinoDesign.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: MinoDesign.Radius.card, style: .continuous)
                .stroke(Color.minoLine.opacity(0.72), lineWidth: 1)
        }
    }
}

private struct OutgoingFriendRequestRow: View {
    let request: FriendRequest
    let characterID: PetCharacterID

    var body: some View {
        HStack(spacing: MinoDesign.Spacing.sm) {
            FriendAvatar(
                characterID: characterID,
                petName: request.friendPetName,
                isSelected: false
            )
            VStack(alignment: .leading, spacing: 3) {
                Text(request.friendPetName)
                    .font(MinoDesign.Typography.bodyStrong)
                    .foregroundStyle(Color.minoInk)
                Text(request.friendName)
                    .font(MinoDesign.Typography.caption)
                    .foregroundStyle(Color.minoMuted)
            }
            Spacer()
            Label("等待接受", systemImage: "clock.fill")
                .font(MinoDesign.Typography.caption.weight(.medium))
                .foregroundStyle(Color.minoMuted)
        }
        .padding(.horizontal, MinoDesign.Spacing.md)
        .frame(minHeight: 64)
        .background(Color.minoSurface.opacity(0.76), in: RoundedRectangle(cornerRadius: MinoDesign.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: MinoDesign.Radius.card, style: .continuous)
                .stroke(Color.minoLine.opacity(0.62), lineWidth: 1)
        }
    }
}

private struct FriendAvatar: View {
    let characterID: PetCharacterID
    let petName: String
    let isSelected: Bool

    var body: some View {
        PetCharacterAvatar(
            characterID: characterID,
            petName: petName,
            size: 42,
            isSelected: isSelected
        )
    }
}

private struct FriendEmptyState: View {
    let addEnabled: Bool
    let add: () -> Void

    var body: some View {
        VStack(spacing: MinoDesign.Spacing.sm) {
            PetCharacterPairView(size: 68)
            Text("还没有好友")
                .font(MinoDesign.Typography.sectionTitle)
                .foregroundStyle(Color.minoInk)
            Button("添加第一位好友", action: add)
                .buttonStyle(MinoRowButtonStyle(isEmphasized: true))
                .disabled(!addEnabled)
        }
        .frame(maxWidth: .infinity, minHeight: 168)
        .background(Color.minoSurface, in: RoundedRectangle(cornerRadius: MinoDesign.Radius.prominent, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: MinoDesign.Radius.prominent, style: .continuous)
                .stroke(Color.minoLine.opacity(0.72), lineWidth: 1)
        }
    }
}

private struct AddFriendSheet: View {
    let localAccountID: AccountID?
    let operationInProgress: Bool
    let serverErrorMessage: String?
    let submit: (AccountID) -> Void
    let complete: () -> Void
    let cancel: () -> Void

    @State private var accountID = ""
    @State private var validationError: AddFriendAccountIDValidationError?
    @State private var didSubmit = false
    @State private var observedSubmissionInProgress = false
    @State private var hidesPreviousServerError = false

    var body: some View {
        VStack(alignment: .leading, spacing: MinoDesign.Spacing.lg) {
            Text("添加好友")
                .font(MinoDesign.Typography.pageTitle)
                .foregroundStyle(Color.minoInk)
            VStack(alignment: .leading, spacing: MinoDesign.Spacing.xs) {
                Text("好友账号 ID")
                    .font(MinoDesign.Typography.label)
                    .foregroundStyle(Color.minoInk)
                TextField("粘贴好友的账号 ID", text: $accountID)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
                    .disabled(operationInProgress)
                    .onSubmit(submitIfPossible)
                    .onChange(of: accountID) { _, _ in
                        validationError = nil
                        hidesPreviousServerError = true
                    }
                Text("请让好友在个人页复制账号 ID 发给你。")
                    .font(MinoDesign.Typography.caption)
                    .foregroundStyle(Color.minoFaint)
                if let validationError {
                    MinoFeedbackRow(
                        message: validationError.message,
                        symbol: "exclamationmark.circle.fill",
                        tint: .minoDanger
                    )
                } else if didSubmit, !hidesPreviousServerError, let serverErrorMessage {
                    MinoFeedbackRow(
                        message: serverErrorMessage,
                        symbol: "exclamationmark.circle.fill",
                        tint: .minoDanger
                    )
                }
            }
            HStack {
                Spacer()
                Button("取消", action: cancel)
                    .buttonStyle(MinoSecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button("发送申请", action: submitIfPossible)
                    .buttonStyle(MinoCompactButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(accountID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || operationInProgress)
            }
        }
        .padding(MinoDesign.Spacing.xl)
        .frame(width: 440)
        .background(Color.minoCanvas)
        .interactiveDismissDisabled(operationInProgress)
        .onChange(of: operationInProgress) { _, isInProgress in
            if isInProgress, didSubmit {
                observedSubmissionInProgress = true
            } else if !isInProgress, observedSubmissionInProgress {
                observedSubmissionInProgress = false
                if serverErrorMessage == nil {
                    complete()
                }
            }
        }
    }

    private func submitIfPossible() {
        switch AddFriendAccountIDValidator.validate(accountID, localAccountID: localAccountID) {
        case .success(let validatedAccountID):
            validationError = nil
            didSubmit = true
            hidesPreviousServerError = false
            submit(validatedAccountID)
        case .failure(let error):
            validationError = error
        }
    }
}

private struct SocialEmptyState: View {
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

private struct SocialLoadingState: View {
    let title: String

    var body: some View {
        ProgressView(title)
            .controlSize(.small)
            .font(MinoDesign.Typography.body)
            .foregroundStyle(Color.minoMuted)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct CloudSyncNotice: View {
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

private struct TimelineFoundationView: View {
    let events: [PersonalTimelineEvent]
    let friends: [FriendProfile]
    let identity: SharedSpaceIdentity
    let authenticationState: SharedSpaceAuthenticationState
    let cloudSyncState: CloudSyncState
    let onOpenLetter: (LetterID) -> Void
    let openFriends: () -> Void
    let openProfile: () -> Void
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            FeatureHeader(
                title: "个人事件线",
                subtitle: "每次串门结束后，互动和带回的小心意会汇成一条摘要"
            )
            switch authenticationState {
            case .signedOut:
                SocialEmptyState(
                    symbol: "person.crop.circle.badge.plus",
                    title: "登录后查看事件线",
                    detail: "登录后，串门结束时生成的互动摘要会保存在这里。",
                    actionTitle: "前往个人页",
                    action: openProfile
                )
            case .waitingForGitHub:
                SocialEmptyState(
                    symbol: "key.fill",
                    title: "正在完成 GitHub 登录",
                    detail: "完成授权后，Mino 会自动恢复你的事件线。",
                    actionTitle: "查看登录进度",
                    action: openProfile
                )
            case .offline, .signedIn:
                timelineContent
            }
        }
        .background(Color.minoCanvas)
    }

    @ViewBuilder
    private var timelineContent: some View {
        if authenticationState == .signedIn, cloudSyncState == .connecting, events.isEmpty {
            SocialLoadingState(title: "正在恢复事件线")
        } else if authenticationState == .signedIn, cloudSyncState == .unavailable, events.isEmpty {
            SocialEmptyState(
                symbol: "wifi.slash",
                title: "暂时无法载入事件线",
                detail: "云端连接暂时不可用，已有记录不会丢失。",
                actionTitle: "重新连接",
                action: retry
            )
        } else if events.isEmpty {
            SocialEmptyState(
                symbol: "clock.arrow.circlepath",
                title: "还没有串门记录",
                detail: friends.isEmpty
                    ? "添加好友并完成一次串门后，这里会留下互动摘要。"
                    : "邀请好友的 Mino 串门，结束后这里会留下互动摘要。",
                actionTitle: authenticationState == .signedIn
                    ? (friends.isEmpty ? "去添加好友" : "发起串门")
                    : nil,
                action: authenticationState == .signedIn ? openFriends : nil
            )
        } else {
            VStack(spacing: 0) {
                if authenticationState == .signedIn,
                   cloudSyncState == .connecting || cloudSyncState == .pending || cloudSyncState == .unavailable {
                    CloudSyncNotice(
                        state: cloudSyncState,
                        hasCachedContent: true,
                        retry: retry
                    )
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                            TimelineEventRow(
                                event: event,
                                friend: friend(for: event),
                                identity: identity,
                                onOpenLetter: onOpenLetter,
                                continuesBelow: index < events.count - 1
                            )
                        }
                    }
                    .frame(maxWidth: MinoDesign.Size.contentMax, alignment: .leading)
                    .padding(.horizontal, MinoDesign.Spacing.xxxl)
                    .padding(.bottom, MinoDesign.Spacing.xxxl)
                }
            }
        }
    }

    private func friend(for event: PersonalTimelineEvent) -> FriendProfile? {
        guard let friendshipID = event.friendshipID else { return nil }
        return friends.first { $0.friendshipID == friendshipID }
    }
}

private struct TimelineEventRow: View {
    let event: PersonalTimelineEvent
    let friend: FriendProfile?
    let identity: SharedSpaceIdentity
    let onOpenLetter: (LetterID) -> Void
    let continuesBelow: Bool

    var body: some View {
        HStack(alignment: .top, spacing: MinoDesign.Spacing.md) {
            VStack(spacing: 0) {
                Image(systemName: symbol)
                    .font(.system(size: MinoDesign.Size.iconSmall, weight: .bold))
                    .foregroundStyle(Color.minoCoral)
                    .frame(width: 38, height: 38)
                    .background(Color.minoCoralSoft, in: Circle())

                if continuesBelow {
                    Rectangle()
                        .fill(Color.minoLine)
                        .frame(width: 1)
                        .frame(minHeight: 64)
                }
            }

            VStack(alignment: .leading, spacing: MinoDesign.Spacing.xs) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(MinoDesign.Typography.sectionTitle)
                        .foregroundStyle(Color.minoInk)
                    Spacer()
                    Label(friendPetName, systemImage: "person.crop.circle")
                        .font(MinoDesign.Typography.caption.weight(.medium))
                        .foregroundStyle(Color.minoMuted)
                        .lineLimit(1)
                }

                Text(detail)
                    .font(MinoDesign.Typography.body)
                    .foregroundStyle(Color.minoMuted)

                if let letterID = event.letterID {
                    Button("打开信件") {
                        onOpenLetter(letterID)
                    }
                    .buttonStyle(MinoTextButtonStyle())
                }

                if !event.cargoItems.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(event.cargoItems, id: \.itemID) { item in
                            Label(
                                item.quantity > 1 ? "\(item.displayName) ×\(item.quantity)" : item.displayName,
                                systemImage: "shippingbox.fill"
                            )
                            .font(MinoDesign.Typography.caption.weight(.semibold))
                            .foregroundStyle(Color.minoInk)
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                            .background(Color.minoCoralSoft, in: Capsule())
                        }
                    }
                }

                if let postcard = event.postcard {
                    HStack(spacing: 12) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 19, weight: .medium))
                            .foregroundStyle(Color.minoCoral)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(postcard.title)
                                .font(MinoDesign.Typography.label)
                                .foregroundStyle(Color.minoInk)
                            if let message = postcard.message {
                                Text(message)
                                    .font(MinoDesign.Typography.caption)
                                    .foregroundStyle(Color.minoMuted)
                                    .lineLimit(2)
                            }
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.minoSurface, in: RoundedRectangle(cornerRadius: MinoDesign.Radius.control, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: MinoDesign.Radius.control, style: .continuous)
                            .stroke(Color.minoLine.opacity(0.72), lineWidth: 1)
                    }
                }
            }
            .padding(.bottom, continuesBelow ? MinoDesign.Spacing.lg : 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var title: String {
        switch event.kind {
        case .visitInvited:
            event.actorAccountID == friend?.accountID
                ? "\(friendPetName)发来串门提议"
                : "向\(friendPetName)发起串门提议"
        case .visitArrived: "\(subjectPetName)过来玩了"
        case .visitReturned: "\(subjectPetName)回家了"
        case .invitationDeclined: "这次串门提议被婉拒了"
        case .interaction: "发生了一次互动"
        case .visitInteraction:
            switch event.visitInteractionKind {
            case .feed: "\(subjectPetName)被投喂了"
            case .play: "\(subjectPetName)和主人玩了一会儿"
            case .message: "主人给\(subjectPetName)留了句话"
            case .pet: "\(subjectPetName)被轻轻摸了摸"
            case .hug: "\(subjectPetName)收到了一个拥抱"
            case .kiss: "\(subjectPetName)被亲了一下"
            case .flower: "\(subjectPetName)收到了一朵花"
            case .walk: "\(subjectPetName)出去散了会儿步"
            case .reaction, .activity, .speech, .acknowledgement: "来访宠物回应了互动"
            case nil: "串门时发生了一次互动"
            }
        case .conversationSummary: "两只小家伙聊了聊天"
        case .letterReceived: "宠物带回了一封信"
        case .cargoReceived: "好友宠物带来了东西"
        case .postcardReceived: "收到一张明信片"
        }
    }

    private var detail: String {
        switch event.kind {
        case .visitInvited: "串门邀请已经送达，等待好友明确接受或拒绝。"
        case .visitArrived: "\(subjectPetName)来到桌面，开始这次来访。"
        case .visitReturned:
            visitSummaryText
                ?? "这次来访结束了，\(subjectPetName)已经回到自己的家。"
        case .invitationDeclined: "邀请仍然留作记录，下次再约也可以。"
        case .interaction:
            switch event.interactionKind {
            case .kiss: "\(identity.localPetName)和\(friendPetName)贴贴了一下。"
            case .flowerGift: "一朵小花被送到了\(friendPetName)身边。"
            case .walk: "\(identity.localPetName)和\(friendPetName)一起散了会儿步。"
            case nil: "\(identity.localPetName)和\(friendPetName)留下了一个小瞬间。"
            }
        case .visitInteraction:
            switch event.visitInteractionKind {
            case .feed: "接待主人给来访的小家伙准备了食物。"
            case .play: "来访的小家伙被好好陪着玩了一会儿。"
            case .message: "一句话已经交给来访的小家伙。"
            case .pet: "接待主人轻轻摸了摸来访的小家伙。"
            case .hug: "接待主人抱了抱来访的小家伙。"
            case .kiss: "接待主人亲了亲来访的小家伙。"
            case .flower: "接待主人送给来访的小家伙一朵花。"
            case .walk: "来访的小家伙出去散了会儿步。"
            case .reaction, .activity, .speech, .acknowledgement: "来访宠物回应了这次互动。"
            case nil: "串门期间留下了一个小瞬间。"
            }
        case .conversationSummary:
            event.summary ?? "它们悄悄联络了一下感情。"
        case .letterReceived: "信封完好地随宠物回到了家，正文只对收件人可见。"
        case .cargoReceived: "来访时携带的小东西已经收好。"
        case .postcardReceived: "一段值得留下来的远方记忆。"
        }
    }

    private var friendPetName: String {
        friend?.petName ?? "好友宠物"
    }

    private var visitSummaryText: String? {
        guard let summary = event.visitInteractionSummary, !summary.isEmpty else { return nil }
        let names: [PetCareInteractionKind: String] = [
            .pet: "摸摸", .feed: "投喂", .play: "陪玩", .walk: "散步",
            .rest: "休息", .cuddle: "贴贴", .flower: "送花"
        ]
        let actions = PetCareInteractionKind.allCases.compactMap { kind -> String? in
            guard let count = summary.counts[kind], count > 0 else { return nil }
            return "\(names[kind] ?? kind.rawValue) \(count) 次"
        }.joined(separator: "、")
        var parts: [String] = []
        if !actions.isEmpty { parts.append(actions) }
        if summary.familiarityGained > 0 {
            parts.append("熟悉度 +\(summary.familiarityGained)")
        }
        if summary.letterAttached { parts.append("带回一封文字信") }
        return "这次串门留下了：\(parts.joined(separator: "，"))。"
    }

    private var subjectPetName: String {
        guard let petID = event.petID else { return friendPetName }
        return petID == friend?.petID ? friendPetName : identity.localPetName
    }

    private var symbol: String {
        switch event.kind {
        case .visitInvited: "paperplane.fill"
        case .visitArrived: "sparkles"
        case .visitReturned: "house.fill"
        case .invitationDeclined: "moon.zzz.fill"
        case .interaction: "heart.fill"
        case .visitInteraction: "pawprint.fill"
        case .conversationSummary: "bubble.left.and.bubble.right.fill"
        case .letterReceived: "envelope.fill"
        case .cargoReceived: "shippingbox.fill"
        case .postcardReceived: "photo.fill"
        }
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

private struct VisitInvitationBanner: View {
    let friendName: String
    let petName: String
    let operationInProgress: Bool
    let accept: () -> Void
    let decline: () -> Void

    var body: some View {
        HStack(spacing: MinoDesign.Spacing.md) {
            PetCharacterPairView(size: 36)
                .frame(width: 58, height: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text("收到串门邀请")
                    .font(MinoDesign.Typography.bodyStrong)
                    .foregroundStyle(Color.minoInk)
                Text("\(friendName) 想让 \(petName) 和你的 Mino 见面")
                    .font(MinoDesign.Typography.caption)
                    .foregroundStyle(Color.minoMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: MinoDesign.Spacing.lg)
            Button("拒绝", action: decline)
                .buttonStyle(MinoTextButtonStyle())
                .disabled(operationInProgress)
            Button("接受", action: accept)
                .buttonStyle(MinoCompactButtonStyle())
                .disabled(operationInProgress)
        }
        .padding(.horizontal, MinoDesign.Spacing.md)
        .frame(maxWidth: 680, minHeight: 64)
        .background(Color.minoSurfaceRaised, in: RoundedRectangle(
            cornerRadius: MinoDesign.Radius.prominent,
            style: .continuous
        ))
        .overlay {
            RoundedRectangle(cornerRadius: MinoDesign.Radius.prominent, style: .continuous)
                .stroke(Color.minoCoral.opacity(0.24), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.1), radius: 18, y: 8)
        .accessibilityElement(children: .contain)
    }
}

private struct FriendDetailView: View {
    let friend: FriendProfile?
    let events: [PersonalTimelineEvent]
    let identity: SharedSpaceIdentity
    let isLoading: Bool
    let errorMessage: String?
    let visitState: FriendVisitState
    let activeVisitFriendshipID: FriendshipID?
    let operationInProgress: Bool
    let characterID: PetCharacterID
    let perform: (FriendDirectoryAction) -> Void
    let onOpenLetter: (LetterID) -> Void
    let back: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if let friend {
                FeatureHeader(title: friend.petName, subtitle: "\(friend.accountName) · 自 \(friend.friendsSince.formatted(date: .abbreviated, time: .omitted)) 成为好友") {
                    HStack(spacing: 10) {
                        Button {
                            back()
                        } label: {
                            Label("返回好友", systemImage: "chevron.left")
                        }
                        .buttonStyle(MinoTextButtonStyle())

                        if isActiveVisitFriend && visitState == .consideringInvitation {
                            Button("拒绝") {
                                perform(.respondToVisit(.decline))
                            }
                            .buttonStyle(MinoTextButtonStyle())
                            .disabled(operationInProgress)

                            Button("接受") {
                                perform(.respondToVisit(.accept))
                            }
                            .buttonStyle(MinoCompactButtonStyle())
                            .disabled(operationInProgress)
                        } else {
                            if isActiveVisitFriend,
                               visitState == .visiting || visitState == .ownPetVisiting {
                                Button {
                                    perform(.endVisit)
                                } label: {
                                    Label("结束串门", systemImage: "house.fill")
                                }
                                .buttonStyle(MinoCompactButtonStyle())
                                .disabled(operationInProgress)
                            } else {
                                Menu {
                                    Button("邀请 \(friend.petName) 来我桌面") {
                                        perform(.inviteFriendPet(friend.friendshipID))
                                    }
                                    Button("让我的 Mino 去 \(friend.accountName) 家") {
                                        perform(.sendOwnPet(friend.friendshipID))
                                    }
                                } label: {
                                    Label("串门", systemImage: "paperplane.fill")
                                }
                                .menuStyle(.borderlessButton)
                                .disabled(operationInProgress || visitDisabled)
                            }
                        }
                    }
                }

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.minoCoral)
                        .frame(maxWidth: MinoDesign.Size.contentMax, alignment: .leading)
                        .padding(.horizontal, MinoDesign.Spacing.xxxl)
                }

                HStack(alignment: .center, spacing: MinoDesign.Spacing.md) {
                    ReadOnlyPetCharacterCard(
                        characterID: characterID,
                        petName: friend.petName,
                        detail: "\(friend.accountName) 的 Mino · 角色由好友永久选定",
                        characterSize: 76
                    )
                    .frame(maxWidth: 310)
                    FriendPublicCareSummary(friend: friend)
                }
                .frame(maxWidth: MinoDesign.Size.contentMax, alignment: .leading)
                .padding(.horizontal, MinoDesign.Spacing.xxxl)
                .padding(.bottom, MinoDesign.Spacing.md)

                if isLoading && events.isEmpty {
                    ProgressView("正在同步事件")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if events.isEmpty {
                    VStack(spacing: MinoDesign.Spacing.sm) {
                        PetCharacterPairView(size: 70)
                        Text("还没有共享事件")
                            .font(MinoDesign.Typography.sectionTitle)
                            .foregroundStyle(Color.minoInk)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                                TimelineEventRow(
                                    event: event,
                                    friend: friend,
                                    identity: identity,
                                    onOpenLetter: onOpenLetter,
                                    continuesBelow: index < events.count - 1
                                )
                            }
                        }
                        .frame(maxWidth: MinoDesign.Size.contentMax, alignment: .leading)
                        .padding(.horizontal, MinoDesign.Spacing.xxxl)
                        .padding(.bottom, MinoDesign.Spacing.xxxl)
                    }
                }
            } else {
                Text("请选择一位好友")
                    .foregroundStyle(Color.minoMuted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.minoCanvas)
    }

    private var isActiveVisitFriend: Bool {
        friend?.friendshipID == activeVisitFriendshipID
    }

    private var visitDisabled: Bool {
        friend == nil || (visitState != .away && !isActiveVisitFriend)
    }

    private var visitTitle: String {
        guard isActiveVisitFriend else { return "邀请串门" }
        return switch visitState {
        case .visiting, .ownPetVisiting: "结束串门"
        case .sendingInvitation: "正在发送"
        case .invitationSent, .consideringInvitation: "等待回应"
        case .returning: "正在回家"
        case .away: "邀请串门"
        }
    }

    private var visitSymbol: String {
        isActiveVisitFriend && (visitState == .visiting || visitState == .ownPetVisiting)
            ? "house.fill"
            : "paperplane.fill"
    }
}

private struct FriendPublicCareSummary: View {
    let friend: FriendProfile

    var body: some View {
        HStack(spacing: MinoDesign.Spacing.sm) {
            qualitativePill(symbol: "fork.knife", text: fullnessText)
            qualitativePill(symbol: "bolt.fill", text: energyText)
            qualitativePill(symbol: "face.smiling.fill", text: moodText)
            Spacer()
            Label(friend.familiarity?.tier.displayName ?? "初见", systemImage: "heart.circle.fill")
                .font(MinoDesign.Typography.caption.weight(.semibold))
                .foregroundStyle(Color.minoCoral)
        }
        .padding(.horizontal, MinoDesign.Spacing.md)
        .frame(minHeight: 54)
        .background(Color.minoSurface, in: RoundedRectangle(
            cornerRadius: MinoDesign.Radius.card,
            style: .continuous
        ))
        .overlay {
            RoundedRectangle(cornerRadius: MinoDesign.Radius.card, style: .continuous)
                .stroke(Color.minoLine.opacity(0.72), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func qualitativePill(symbol: String, text: String) -> some View {
        Label(text, systemImage: symbol)
            .font(MinoDesign.Typography.caption)
            .foregroundStyle(Color.minoMuted)
            .padding(.horizontal, MinoDesign.Spacing.sm)
            .frame(height: 30)
            .background(Color.minoCanvas, in: Capsule())
    }

    private var fullnessText: String {
        switch friend.publicCare?.fullness ?? .steady {
        case .low: "有点饿"
        case .steady: "吃得正好"
        case .high: "肚子饱饱"
        }
    }

    private var energyText: String {
        switch friend.publicCare?.energy ?? .steady {
        case .low: "有点累"
        case .steady: "精神还好"
        case .high: "精神很好"
        }
    }

    private var moodText: String {
        switch friend.publicCare?.mood ?? .steady {
        case .low: "有点低落"
        case .steady: "心情平稳"
        case .high: "心情很好"
        }
    }
}

private struct ProfileView: View {
    let profile: CurrentProfile?
    let identity: SharedSpaceIdentity
    let careState: PetCareState
    let cloudSyncState: CloudSyncState
    let authenticationState: SharedSpaceAuthenticationState
    let githubDeviceCodeWasAutoCopied: Bool
    let authenticationOperationInProgress: Bool
    let authenticationErrorMessage: String?
    let profileOperationInProgress: Bool
    let profileErrorMessage: String?
    let profileSuccessMessage: String?
    let characterID: PetCharacterID?
    let perform: (ProfileAction) -> Void

    @State private var accountName = ""
    @State private var petName = ""
    @State private var manuallyCopiedGitHubCode: String?

    init(
        profile: CurrentProfile?,
        identity: SharedSpaceIdentity,
        careState: PetCareState,
        cloudSyncState: CloudSyncState,
        authenticationState: SharedSpaceAuthenticationState,
        githubDeviceCodeWasAutoCopied: Bool,
        authenticationOperationInProgress: Bool,
        authenticationErrorMessage: String?,
        profileOperationInProgress: Bool,
        profileErrorMessage: String?,
        profileSuccessMessage: String?,
        characterID: PetCharacterID?,
        perform: @escaping (ProfileAction) -> Void
    ) {
        self.profile = profile
        self.identity = identity
        self.careState = careState
        self.cloudSyncState = cloudSyncState
        self.authenticationState = authenticationState
        self.githubDeviceCodeWasAutoCopied = githubDeviceCodeWasAutoCopied
        self.authenticationOperationInProgress = authenticationOperationInProgress
        self.authenticationErrorMessage = authenticationErrorMessage
        self.profileOperationInProgress = profileOperationInProgress
        self.profileErrorMessage = profileErrorMessage
        self.profileSuccessMessage = profileSuccessMessage
        self.characterID = characterID
        self.perform = perform
        _accountName = State(initialValue: profile?.accountName ?? "")
        _petName = State(initialValue: profile?.petName ?? identity.localPetName)
    }

    var body: some View {
        VStack(spacing: 0) {
            FeatureHeader(title: "你的 Mino", subtitle: "账号、身份和宠物资料")
            ScrollView {
                VStack(alignment: .leading, spacing: MinoDesign.Spacing.md) {
                    authenticationSection
                    careSection
                    profileSection
                }
                .frame(maxWidth: MinoDesign.Size.contentMax, alignment: .leading)
                .padding(.horizontal, MinoDesign.Spacing.xxxl)
                .padding(.bottom, MinoDesign.Spacing.xxxl)
            }
        }
        .background(Color.minoCanvas)
        .onChange(of: profile?.accountName) { _, value in
            if let value { accountName = value }
        }
        .onChange(of: profile?.petName) { _, value in
            if let value { petName = value }
        }
    }

    private var authenticationSection: some View {
        VStack(alignment: .leading, spacing: MinoDesign.Spacing.md) {
            switch authenticationState {
            case .offline:
                accountStatus(
                    symbol: "wifi.slash",
                    tint: .minoWarning,
                    title: "账号服务暂不可用",
                    detail: "当前未连接 Mino 云服务。本机互动仍可继续，好友和事件暂时无法同步。"
                )
            case .signedOut:
                HStack(alignment: .center, spacing: MinoDesign.Spacing.md) {
                    accountStatus(
                        symbol: "person.crop.circle.badge.plus",
                        tint: .minoCoral,
                        title: "登录你的 Mino",
                        detail: "用 GitHub 建立账号，在多台 Mac 上同步好友、串门和事件线。"
                    )
                    Spacer(minLength: MinoDesign.Spacing.md)
                    Button {
                        perform(.signInWithGitHub)
                    } label: {
                        Label("使用 GitHub 登录", systemImage: "person.badge.key.fill")
                    }
                    .buttonStyle(MinoCompactButtonStyle())
                    .disabled(authenticationOperationInProgress)
                }
            case .waitingForGitHub(let userCode, let verificationURL):
                accountStatus(
                    symbol: "key.fill",
                    tint: .minoCoral,
                    title: "在 GitHub 完成授权",
                    detail: githubDeviceCodeWasAutoCopied
                        ? "完整匹配码已复制。GitHub 会把它显示成 8 格；点第一格后按 ⌘V，会一次填满。"
                        : "请复制下面的完整匹配码，再到 GitHub 点第一格并按 ⌘V，一次填满 8 格。"
                )
                HStack(spacing: MinoDesign.Spacing.sm) {
                    Text(userCode)
                        .font(MinoDesign.Typography.code)
                        .textSelection(.enabled)
                        .accessibilityLabel("GitHub 匹配码 \(userCode)")
                        .foregroundStyle(Color.minoInk)
                        .padding(.horizontal, MinoDesign.Spacing.md)
                        .frame(height: MinoDesign.Size.primaryControl)
                        .background(Color.minoCoralSoft, in: RoundedRectangle(
                            cornerRadius: MinoDesign.Radius.control,
                            style: .continuous
                        ))
                    Button {
                        if GitHubDeviceCodeClipboard.copy(userCode) {
                            manuallyCopiedGitHubCode = GitHubDeviceCodeClipboard.normalizedCode(userCode)
                        }
                    } label: {
                        Label(
                            manuallyCopiedGitHubCode == GitHubDeviceCodeClipboard.normalizedCode(userCode)
                                ? "已复制"
                                : (githubDeviceCodeWasAutoCopied ? "再次复制" : "复制匹配码"),
                            systemImage: manuallyCopiedGitHubCode == GitHubDeviceCodeClipboard.normalizedCode(userCode)
                                ? "checkmark"
                                : "doc.on.doc"
                        )
                    }
                    .buttonStyle(MinoSecondaryButtonStyle())
                    .help("复制完整 GitHub 匹配码")
                    Button {
                        NSWorkspace.shared.open(verificationURL)
                    } label: {
                        Label("打开 GitHub", systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(MinoCompactButtonStyle())
                }
                Button("取消登录") {
                    perform(.cancelSignIn)
                }
                .buttonStyle(MinoTextButtonStyle())
            case .signedIn:
                HStack(alignment: .center, spacing: MinoDesign.Spacing.md) {
                    accountStatus(
                        symbol: signedInAccountStatus.symbol,
                        tint: signedInAccountStatus.tint,
                        title: signedInAccountStatus.title,
                        detail: signedInAccountStatus.detail
                    )
                    Spacer(minLength: MinoDesign.Spacing.md)
                    Button("退出登录") {
                        perform(.signOut)
                    }
                    .buttonStyle(MinoDangerTextButtonStyle())
                    .disabled(authenticationOperationInProgress)
                }
            }

            if authenticationOperationInProgress {
                ProgressView("正在连接 GitHub…")
                    .controlSize(.small)
                    .font(MinoDesign.Typography.caption)
            }
            if let authenticationErrorMessage {
                MinoFeedbackRow(
                    message: authenticationErrorMessage,
                    symbol: "exclamationmark.circle.fill",
                    tint: .minoDanger
                )
            }
        }
        .minoCard()
    }

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: MinoDesign.Spacing.lg) {
            HStack(alignment: .firstTextBaseline) {
                Text("个人资料")
                    .font(MinoDesign.Typography.sectionTitle)
                    .foregroundStyle(Color.minoInk)
                Spacer()
                if let joinedDateText {
                    Text("加入于 \(joinedDateText)")
                        .font(MinoDesign.Typography.caption)
                        .foregroundStyle(Color.minoFaint)
                }
            }

            if let characterID {
                ReadOnlyPetCharacterCard(
                    characterID: characterID,
                    petName: petName.isEmpty ? identity.localPetName : petName,
                    detail: "这是你的固定角色。角色无法更换，宠物名字可以继续修改。",
                    characterSize: 88
                )
            } else {
                HStack(spacing: MinoDesign.Spacing.md) {
                    PetCharacterPairView(size: 62)
                    VStack(alignment: .leading, spacing: MinoDesign.Spacing.xxs) {
                        Text("角色尚未确认")
                            .font(MinoDesign.Typography.sectionTitle)
                            .foregroundStyle(Color.minoInk)
                        Text("GitHub 登录完成并恢复账号后，你会从两个角色中永久选择一个。")
                            .font(MinoDesign.Typography.caption)
                            .foregroundStyle(Color.minoMuted)
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
            }

            if let accountID = visibleAccountID {
                VStack(alignment: .leading, spacing: MinoDesign.Spacing.xs) {
                    Text("账号 ID")
                        .font(MinoDesign.Typography.label)
                        .foregroundStyle(Color.minoMuted)
                    HStack(spacing: MinoDesign.Spacing.sm) {
                        Text(accountID)
                            .font(MinoDesign.Typography.caption.monospaced())
                            .foregroundStyle(Color.minoInk)
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: MinoDesign.Spacing.sm)
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(accountID, forType: .string)
                        } label: {
                            Label("复制", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(MinoSecondaryButtonStyle())
                    }
                }
                .padding(MinoDesign.Spacing.sm)
                .background(Color.minoCanvas, in: RoundedRectangle(
                    cornerRadius: MinoDesign.Radius.control,
                    style: .continuous
                ))
            }

            VStack(alignment: .leading, spacing: MinoDesign.Spacing.md) {
                profileField(
                    title: "账号昵称",
                    hint: "好友会看到这个名字",
                    text: $accountName
                )
                profileField(
                    title: "宠物名字",
                    hint: "显示在桌面、好友列表和事件线中",
                    text: $petName
                )
            }
            .frame(maxWidth: MinoDesign.Size.formMax, alignment: .leading)

            HStack(spacing: MinoDesign.Spacing.sm) {
                Button {
                    perform(.saveProfile(accountName: accountName, petName: petName))
                } label: {
                    if profileOperationInProgress {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("保存资料", systemImage: "checkmark")
                    }
                }
                .buttonStyle(MinoCompactButtonStyle())
                .disabled(profileOperationInProgress || accountName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || petName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let profileErrorMessage {
                MinoFeedbackRow(
                    message: profileErrorMessage,
                    symbol: "exclamationmark.circle.fill",
                    tint: .minoDanger
                )
            }
            if let profileSuccessMessage {
                MinoFeedbackRow(
                    message: profileSuccessMessage,
                    symbol: "checkmark.circle.fill",
                    tint: .minoMint
                )
            }
        }
        .minoCard()
    }

    private var careSection: some View {
        VStack(alignment: .leading, spacing: MinoDesign.Spacing.lg) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: MinoDesign.Spacing.xxs) {
                    Text("今日状态")
                        .font(MinoDesign.Typography.sectionTitle)
                        .foregroundStyle(Color.minoInk)
                    Text(careSyncDetail)
                        .font(MinoDesign.Typography.caption)
                        .foregroundStyle(Color.minoMuted)
                }
                Spacer()
                Label(
                    cloudSyncState.statusText,
                    systemImage: cloudSyncState.systemImage
                )
                .font(MinoDesign.Typography.caption.weight(.semibold))
                .foregroundStyle(syncTint)
            }

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                alignment: .leading,
                spacing: MinoDesign.Spacing.md
            ) {
                CareMetric(title: "饱腹", symbol: "fork.knife", value: careState.fullness, tint: .minoCoral)
                CareMetric(title: "精力", symbol: "bolt.fill", value: careState.energy, tint: .minoWarning)
                CareMetric(title: "心情", symbol: "face.smiling.fill", value: careState.mood, tint: .minoMint)
                CareMetric(title: "亲密", symbol: "heart.fill", value: careState.bond, tint: .minoCoral)
            }
        }
        .minoCard()
    }

    private var signedInAccountStatus: (symbol: String, tint: Color, title: String, detail: String) {
        switch cloudSyncState {
        case .localOnly:
            ("macbook", .minoWarning, "当前仅保存在此 Mac", "本地互动照常可用；登录会话恢复后再同步好友和事件。")
        case .connecting:
            ("arrow.triangle.2.circlepath", .minoCoral, "正在恢复账号", "正在连接 Mino 云服务，当前显示本地状态。")
        case .synced:
            ("checkmark.seal.fill", .minoMint, "GitHub 已连接", "好友、串门与事件已同步到你的账号。")
        case .pending:
            ("clock.arrow.circlepath", .minoWarning, "GitHub 已连接", "本地更改已经生效，会在网络恢复后自动同步。")
        case .unavailable:
            ("wifi.slash", .minoDanger, "GitHub 已连接，云端暂不可用", "继续显示上次同步内容；本地互动会稍后同步。")
        }
    }

    private var syncTint: Color {
        switch cloudSyncState {
        case .localOnly, .pending: .minoWarning
        case .connecting: .minoCoral
        case .synced: .minoMint
        case .unavailable: .minoDanger
        }
    }

    private var careSyncDetail: String {
        switch cloudSyncState {
        case .localOnly: "状态只保存在这台 Mac"
        case .connecting: "正在连接云端，当前显示本地状态"
        case .synced: "互动先在本机生效，再与云端安静校正"
        case .pending: "互动已在本机生效，等待网络恢复后同步"
        case .unavailable: "云端暂不可用，当前显示本机与上次同步状态"
        }
    }

    private var visibleAccountID: String? {
        guard hasEstablishedProfile else { return nil }
        return profile?.accountID.rawValue
    }

    private var joinedDateText: String? {
        guard let profile, hasEstablishedProfile else { return nil }
        return profile.createdAt.formatted(
            .dateTime
                .year()
                .month()
                .day()
                .locale(Locale(identifier: "zh_CN"))
        )
    }

    private var hasEstablishedProfile: Bool {
        switch authenticationState {
        case .offline, .signedIn: true
        case .signedOut, .waitingForGitHub: false
        }
    }

    @ViewBuilder
    private func accountStatus(
        symbol: String,
        tint: Color,
        title: String,
        detail: String
    ) -> some View {
        HStack(alignment: .top, spacing: MinoDesign.Spacing.sm) {
            Image(systemName: symbol)
                .font(.system(size: MinoDesign.Size.icon, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: MinoDesign.Spacing.xxs) {
                Text(title)
                    .font(MinoDesign.Typography.sectionTitle)
                    .foregroundStyle(Color.minoInk)
                Text(detail)
                    .font(MinoDesign.Typography.body)
                    .foregroundStyle(Color.minoMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func profileField(
        title: String,
        hint: String,
        text: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: MinoDesign.Spacing.xs) {
            Text(title)
                .font(MinoDesign.Typography.label)
                .foregroundStyle(Color.minoInk)
            TextField(title, text: text)
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)
            Text(hint)
                .font(MinoDesign.Typography.caption)
                .foregroundStyle(Color.minoFaint)
        }
    }
}

private struct CareMetric: View {
    let title: String
    let symbol: String
    let value: Int
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: MinoDesign.Spacing.xs) {
            HStack(spacing: MinoDesign.Spacing.xs) {
                Image(systemName: symbol)
                    .foregroundStyle(tint)
                Text(title)
                    .font(MinoDesign.Typography.label)
                    .foregroundStyle(Color.minoInk)
                Spacer()
                Text("\(value)")
                    .font(MinoDesign.Typography.bodyStrong.monospacedDigit())
                    .foregroundStyle(Color.minoInk)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.minoLine.opacity(0.62))
                    Capsule()
                        .fill(tint)
                        .frame(width: proxy.size.width * CGFloat(min(max(value, 0), 100)) / 100)
                }
            }
            .frame(height: 8)
            Text(careDescription)
                .font(MinoDesign.Typography.caption)
                .foregroundStyle(Color.minoMuted)
        }
        .padding(MinoDesign.Spacing.sm)
        .background(Color.minoCanvas, in: RoundedRectangle(
            cornerRadius: MinoDesign.Radius.control,
            style: .continuous
        ))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(value)，\(careDescription)")
    }

    private var careDescription: String {
        switch PetCareBand(value: value) {
        case .low: "需要照顾"
        case .steady: "状态平稳"
        case .high: "状态很好"
        }
    }
}

private struct MinoFeedbackRow: View {
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

private struct FeatureHeader<Trailing: View>: View {
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

private extension FeatureHeader where Trailing == EmptyView {
    init(title: String, subtitle: String) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = EmptyView()
    }
}

private struct MinoCompactButtonStyle: ButtonStyle {
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

private struct MinoSecondaryButtonStyle: ButtonStyle {
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

private struct MinoTextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(MinoDesign.Typography.bodyStrong)
            .foregroundStyle(Color.minoInk.opacity(configuration.isPressed ? 0.54 : 0.82))
            .padding(.horizontal, MinoDesign.Spacing.sm)
            .frame(height: MinoDesign.Size.control)
    }
}

private struct MinoDangerTextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(MinoDesign.Typography.bodyStrong)
            .foregroundStyle(Color.minoDanger.opacity(configuration.isPressed ? 0.58 : 1))
            .padding(.horizontal, MinoDesign.Spacing.sm)
            .frame(height: MinoDesign.Size.control)
    }
}

private struct MinoRowButtonStyle: ButtonStyle {
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
