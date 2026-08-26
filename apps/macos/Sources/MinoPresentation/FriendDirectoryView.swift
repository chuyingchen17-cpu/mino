import MinoDomain
import SwiftUI

struct FriendDirectoryView: View {
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

struct FriendRow: View {
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

struct FriendRequestRow: View {
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

struct OutgoingFriendRequestRow: View {
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

struct FriendAvatar: View {
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

struct FriendEmptyState: View {
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

struct AddFriendSheet: View {
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

