import AppKit
import MinoDomain
import SwiftUI
import UniformTypeIdentifiers

private enum SharedSpaceDestination: String, CaseIterable, Identifiable {
    case friends
    case timeline
    case chat
    case interactions
    case avatar

    var id: String { rawValue }

    var title: String {
        switch self {
        case .friends: "好友"
        case .timeline: "事件线"
        case .chat: "聊天"
        case .interactions: "互动"
        case .avatar: "形象"
        }
    }

    var symbol: String {
        switch self {
        case .friends: "person.2.fill"
        case .timeline: "clock.arrow.circlepath"
        case .chat: "message"
        case .interactions: "hands.clap"
        case .avatar: "person.crop.circle"
        }
    }
}

private enum SharedSpaceAssets {
    static let friendAvatar = load("partner-avatar")

    private static func load(_ name: String) -> NSImage {
        let url = Bundle.main.url(forResource: name, withExtension: "png")
            ?? Bundle.module.url(forResource: name, withExtension: "png")
        guard let url, let image = NSImage(contentsOf: url) else {
            fatalError("Missing required Mino asset: \(name).png")
        }
        return image
    }
}

private extension Color {
    static let minoCanvas = Color(red: 1.000, green: 0.985, blue: 0.964)
    static let minoSidebar = Color(red: 0.992, green: 0.965, blue: 0.935)
    static let minoInk = Color(red: 0.235, green: 0.190, blue: 0.155)
    static let minoMuted = Color(red: 0.430, green: 0.390, blue: 0.350)
    static let minoCoral = Color(red: 1.000, green: 0.355, blue: 0.350)
    static let minoCoralSoft = Color(red: 1.000, green: 0.905, blue: 0.865)
    static let minoMint = Color(red: 0.200, green: 0.760, blue: 0.660)
    static let minoLine = Color(red: 0.890, green: 0.850, blue: 0.805)
}

struct SharedSpaceView: View {
    @ObservedObject var model: SharedSpaceModel
    let debugIdentityLabel: String?
    let identity: SharedSpaceIdentity
    let onInteraction: (SharedSpaceAction) -> Void
    let onFriendAction: (FriendDirectoryAction) -> Void
    let onSendChatMessage: (String) -> Void
    let onOpenLetter: (LetterID) -> Void

    @State private var destination: SharedSpaceDestination = .friends
    @State private var toastMessage: String?

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 212)
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
                        selectedFriendshipID: model.selectedFriendshipID,
                        activeVisitFriendshipID: model.activeVisitFriendshipID,
                        visitState: model.visitState,
                        operationInProgress: model.friendOperationInProgress,
                        errorMessage: model.friendErrorMessage ?? model.visitErrorMessage,
                        perform: onFriendAction
                    )
                case .timeline:
                    TimelineFoundationView(
                        events: Array(model.timelineEvents.reversed()),
                        friends: model.friends,
                        identity: identity,
                        onOpenLetter: onOpenLetter
                    )
                case .chat:
                    ChatFoundationView(
                        friendPetName: selectedFriendPetName,
                        onSend: onSendChatMessage
                    )
                case .interactions:
                    InteractionFoundationView(
                        friendPetName: selectedFriendPetName,
                        perform: perform
                    )
                case .avatar:
                    AvatarFoundationView(petName: identity.localPetName)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .top) {
                if let toastMessage {
                    toast(message: toastMessage)
                        .padding(.top, 24)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .background(Color.minoCanvas)
        .ignoresSafeArea()
        .frame(minWidth: 980, idealWidth: 1_260, minHeight: 680, idealHeight: 860)
        .animation(.easeOut(duration: 0.2), value: toastMessage)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Mino")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.minoCoral)
                .padding(.leading, 34)
                .padding(.top, 68)
                .padding(.bottom, 34)

            if let debugIdentityLabel {
                Label(debugIdentityLabel, systemImage: "ladybug.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.minoCoral)
                    .lineLimit(1)
                    .padding(.horizontal, 11)
                    .frame(height: 28)
                    .background(Color.minoCoralSoft, in: Capsule())
                    .padding(.horizontal, 28)
                    .padding(.top, -20)
                    .padding(.bottom, 22)
                    .accessibilityLabel("Debug 当前实例 \(debugIdentityLabel)")
            }

            VStack(spacing: 10) {
                ForEach(SharedSpaceDestination.allCases) { item in
                    SidebarItem(
                        destination: item,
                        isSelected: destination == item,
                        action: { destination = item }
                    )
                }
            }
            .padding(.horizontal, 20)

            Spacer()

            HStack(spacing: 10) {
                Image(systemName: "pawprint.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.minoCoral)
                    .frame(width: 34, height: 34)
                    .background(Color.minoCoralSoft, in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(identity.localPetName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.minoInk)
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color.minoMint)
                            .frame(width: 7, height: 7)
                        Text(model.eventSyncStatusText)
                            .font(.system(size: 10))
                            .foregroundStyle(Color.minoMuted)
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 28)
        }
        .frame(maxHeight: .infinity)
        .background(Color.minoSidebar)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.minoLine.opacity(0.55))
                .frame(width: 1)
        }
    }

    private var selectedFriendPetName: String {
        model.friends.first(where: { $0.friendshipID == model.selectedFriendshipID })?.petName
            ?? model.friends.first?.petName
            ?? identity.fallbackFriendPetName
    }

    private func perform(_ action: SharedSpaceAction) {
        onInteraction(action)
        let message: String
        switch action {
        case .kiss: message = "亲亲已经送到\(selectedFriendPetName)身边"
        case .flower: message = "小花已经送出"
        case .walk: message = "\(identity.localPetName)和\(selectedFriendPetName)去散步啦"
        }
        toastMessage = message
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.2))
            if toastMessage == message {
                toastMessage = nil
            }
        }
    }

    private func toast(message: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "heart.fill")
                .foregroundStyle(Color.minoCoral)
            Text(message)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.minoInk)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.8), lineWidth: 1))
        .shadow(color: Color.minoInk.opacity(0.12), radius: 16, y: 6)
    }
}

private struct FriendDirectoryView: View {
    let friends: [FriendProfile]
    let requests: [FriendRequest]
    let localAccountID: AccountID?
    let selectedFriendshipID: FriendshipID?
    let activeVisitFriendshipID: FriendshipID?
    let visitState: FriendVisitState
    let operationInProgress: Bool
    let errorMessage: String?
    let perform: (FriendDirectoryAction) -> Void

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

    var body: some View {
        VStack(spacing: 0) {
            FeatureHeader(
                title: "好友",
                subtitle: "管理好友申请，并选择宠物要联系或串门的对象"
            ) {
                HStack(spacing: 10) {
                    Button {
                        perform(.refresh)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.minoInk)
                            .frame(width: 42, height: 42)
                            .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .disabled(operationInProgress)
                    .opacity(operationInProgress ? 0.5 : 1)
                    .help("刷新好友与申请")
                    .accessibilityLabel("刷新好友与申请")

                    Button {
                        addFriendPresented = true
                    } label: {
                        Label("添加好友", systemImage: "person.badge.plus")
                    }
                    .buttonStyle(MinoCompactButtonStyle())
                    .disabled(operationInProgress)
                }
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.minoCoral)
                    .frame(maxWidth: 760, alignment: .leading)
                    .padding(.horizontal, 62)
                    .padding(.bottom, 14)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    if !incomingRequests.isEmpty {
                        friendSection(title: "待处理申请", count: incomingRequests.count) {
                            ForEach(incomingRequests) { request in
                                FriendRequestRow(
                                    request: request,
                                    operationInProgress: operationInProgress,
                                    accept: {
                                        perform(.respondToRequest(request.id, .accept))
                                    },
                                    decline: {
                                        perform(.respondToRequest(request.id, .decline))
                                    }
                                )
                            }
                        }
                    }

                    if !outgoingRequests.isEmpty {
                        friendSection(title: "已发出的申请", count: outgoingRequests.count) {
                            ForEach(outgoingRequests) { request in
                                OutgoingFriendRequestRow(request: request)
                            }
                        }
                    }

                    friendSection(title: "我的好友", count: friends.count) {
                        if friends.isEmpty {
                            FriendEmptyState {
                                addFriendPresented = true
                            }
                        } else {
                            ForEach(friends) { friend in
                                FriendRow(
                                    friend: friend,
                                    isSelected: friend.friendshipID == selectedFriendshipID,
                                    visitState: visitState,
                                    isActiveVisitFriend: friend.friendshipID == activeVisitFriendshipID,
                                    operationInProgress: operationInProgress,
                                    select: { perform(.selectFriend(friend.friendshipID)) },
                                    visit: {
                                        if friend.friendshipID == activeVisitFriendshipID,
                                           visitState == .visiting || visitState == .ownPetVisiting {
                                            perform(.endVisit)
                                        } else {
                                            perform(.inviteFriend(friend.friendshipID))
                                        }
                                    }
                                )
                            }
                        }
                    }
                }
                .frame(maxWidth: 760, alignment: .leading)
                .padding(.horizontal, 62)
                .padding(.bottom, 52)
            }
        }
        .background(Color.minoCanvas)
        .sheet(isPresented: $addFriendPresented) {
            AddFriendSheet(
                operationInProgress: operationInProgress,
                submit: { accountID in
                    perform(.addFriend(accountID))
                    addFriendPresented = false
                },
                cancel: { addFriendPresented = false }
            )
        }
    }

    private func friendSection<Content: View>(
        title: String,
        count: Int,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.minoInk)
                Text("\(count)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.minoMuted)
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(Color.minoSidebar, in: Capsule())
            }
            content()
        }
    }
}

private struct FriendRow: View {
    let friend: FriendProfile
    let isSelected: Bool
    let visitState: FriendVisitState
    let isActiveVisitFriend: Bool
    let operationInProgress: Bool
    let select: () -> Void
    let visit: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: select) {
                HStack(spacing: 14) {
                    FriendAvatar(petName: friend.petName, isSelected: isSelected)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(friend.petName)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color.minoInk)
                        Text(friend.accountName)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.minoMuted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Label(statusText, systemImage: statusSymbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isActiveVisitFriend ? Color.minoCoral : Color.minoMuted)
                .frame(width: 126, alignment: .leading)

            Button(action: visit) {
                Label(visitTitle, systemImage: visitSymbol)
                    .frame(minWidth: 92)
            }
            .buttonStyle(MinoRowButtonStyle(isEmphasized: isActiveVisitFriend))
            .disabled(operationInProgress || visitDisabled)
        }
        .padding(.horizontal, 16)
        .frame(height: 70)
        .background(
            isSelected ? Color.minoCoralSoft.opacity(0.72) : Color.white.opacity(0.56),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
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
        case .consideringInvitation: "对方正在决定"
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
}

private struct FriendRequestRow: View {
    let request: FriendRequest
    let operationInProgress: Bool
    let accept: () -> Void
    let decline: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            FriendAvatar(petName: request.friendPetName, isSelected: false)
            VStack(alignment: .leading, spacing: 3) {
                Text(request.friendPetName)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.minoInk)
                Text("\(request.friendName) 想加你为好友")
                    .font(.system(size: 12))
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
        .padding(.horizontal, 16)
        .frame(height: 70)
        .background(Color.white.opacity(0.58), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct OutgoingFriendRequestRow: View {
    let request: FriendRequest

    var body: some View {
        HStack(spacing: 14) {
            FriendAvatar(petName: request.friendPetName, isSelected: false)
            VStack(alignment: .leading, spacing: 3) {
                Text(request.friendPetName)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.minoInk)
                Text(request.friendName)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.minoMuted)
            }
            Spacer()
            Label("等待接受", systemImage: "clock.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.minoMuted)
        }
        .padding(.horizontal, 16)
        .frame(height: 62)
        .background(Color.white.opacity(0.42), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct FriendAvatar: View {
    let petName: String
    let isSelected: Bool

    var body: some View {
        Image(nsImage: SharedSpaceAssets.friendAvatar)
            .resizable()
            .scaledToFill()
            .frame(width: 42, height: 42)
            .clipShape(Circle())
            .overlay(
                Circle().stroke(isSelected ? Color.minoCoral : .white, lineWidth: 2)
            )
            .accessibilityLabel("\(petName)的头像")
    }
}

private struct FriendEmptyState: View {
    let add: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.2")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(Color.minoCoral)
            Text("还没有好友")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color.minoInk)
            Button("添加第一位好友", action: add)
                .buttonStyle(MinoRowButtonStyle(isEmphasized: true))
        }
        .frame(maxWidth: .infinity, minHeight: 180)
    }
}

private struct AddFriendSheet: View {
    let operationInProgress: Bool
    let submit: (AccountID) -> Void
    let cancel: () -> Void

    @State private var accountID = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("添加好友")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color.minoInk)
            TextField("好友账号 ID", text: $accountID)
                .textFieldStyle(.roundedBorder)
                .frame(height: 36)
                .onSubmit(submitIfPossible)
            HStack {
                Spacer()
                Button("取消", action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button("发送申请", action: submitIfPossible)
                    .buttonStyle(MinoRowButtonStyle(isEmphasized: true))
                    .keyboardShortcut(.defaultAction)
                    .disabled(normalizedAccountID.isEmpty || operationInProgress)
            }
        }
        .padding(28)
        .frame(width: 420)
        .background(Color.minoCanvas)
    }

    private var normalizedAccountID: String {
        accountID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func submitIfPossible() {
        guard !normalizedAccountID.isEmpty else { return }
        submit(AccountID(rawValue: normalizedAccountID))
    }
}

private struct TimelineFoundationView: View {
    let events: [PersonalTimelineEvent]
    let friends: [FriendProfile]
    let identity: SharedSpaceIdentity
    let onOpenLetter: (LetterID) -> Void

    var body: some View {
        VStack(spacing: 0) {
            FeatureHeader(
                title: "个人事件线",
                subtitle: "好友来访、互动和带回来的小心意，都会按时间留在这里"
            )
            if events.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(Color.minoCoral.opacity(0.75))
                    Text("故事还没开始")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color.minoInk)
                    Text("和好友宠物发生互动后，事件会出现在这里")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.minoMuted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
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
                    .frame(maxWidth: 720, alignment: .leading)
                    .padding(.horizontal, 62)
                    .padding(.bottom, 48)
                }
            }
        }
        .background(Color.minoCanvas)
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
        HStack(alignment: .top, spacing: 18) {
            VStack(spacing: 0) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.minoCoral)
                    .frame(width: 38, height: 38)
                    .background(Color.minoCoralSoft, in: Circle())

                if continuesBelow {
                    Rectangle()
                        .fill(Color.minoLine)
                        .frame(width: 1)
                        .frame(minHeight: 68)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.minoInk)
                    Spacer()
                    Label(friendPetName, systemImage: "person.crop.circle")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.minoMuted)
                        .lineLimit(1)
                }

                Text(detail)
                    .font(.system(size: 13))
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
                            .font(.system(size: 11, weight: .semibold))
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
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Color.minoInk)
                            if let message = postcard.message {
                                Text(message)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.minoMuted)
                                    .lineLimit(2)
                            }
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.minoSidebar, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .padding(.bottom, continuesBelow ? 24 : 0)
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
        case .visitInvited: "串门提议已经送达，宠物会自行决定是否接受。"
        case .visitArrived: "\(subjectPetName)来到桌面，开始这次来访。"
        case .visitReturned: "这次来访结束了，\(subjectPetName)已经回到自己的家。"
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
            HStack(spacing: 15) {
                Image(systemName: destination.symbol)
                    .font(.system(size: 19, weight: .medium))
                    .frame(width: 25)
                Text(destination.title)
                    .font(.system(size: 17, weight: isSelected ? .semibold : .medium))
                Spacer()
            }
            .foregroundStyle(isSelected ? Color.minoCoral : Color.minoInk.opacity(0.78))
            .padding(.horizontal, 18)
            .frame(height: 58)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Color.minoCoralSoft : Color.white.opacity(isHovering ? 0.42 : 0))
            )
            .contentShape(Rectangle())
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

private struct InteractionPopover: View {
    let friendPetName: String
    let perform: (SharedSpaceAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("发个互动")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.minoInk)
                Text("让\(friendPetName)马上感受到你")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.minoMuted)
            }

            HStack(spacing: 10) {
                InteractionChoice(title: "亲亲", symbol: "heart.fill", action: { perform(.kiss) })
                InteractionChoice(title: "送花", symbol: "camera.macro", action: { perform(.flower) })
                InteractionChoice(title: "散步", symbol: "figure.walk", action: { perform(.walk) })
            }
        }
        .padding(20)
        .frame(width: 354)
        .background(Color.minoCanvas)
    }
}

private struct InteractionChoice: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 19, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(Color.minoCoral)
            .frame(maxWidth: .infinity)
            .frame(height: 72)
            .background(Color.minoCoralSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct ChatFoundationView: View {
    let friendPetName: String
    let onSend: (String) -> Void
    @State private var draft = ""
    @State private var sentMessages: [String] = []

    var body: some View {
        VStack(spacing: 0) {
            FeatureHeader(
                title: "和\(friendPetName)说句话",
                subtitle: "真人消息会清楚标记身份，并交给对应的好友宠物"
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if sentMessages.isEmpty {
                        Text("这里不会伪造宠物消息。发出的真人消息会明确以主人身份参与。")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.minoMuted)
                            .frame(maxWidth: .infinity, minHeight: 180)
                    }
                    ForEach(Array(sentMessages.enumerated()), id: \.offset) { _, message in
                        HStack {
                            Spacer(minLength: 120)
                            Text(message)
                                .font(.system(size: 15))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 12)
                                .background(Color.minoCoral, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 62)
                .padding(.top, 26)
            }

            HStack(spacing: 12) {
                TextField("说点什么…", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .padding(.horizontal, 18)
                    .frame(height: 50)
                    .background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.minoLine.opacity(0.7), lineWidth: 1))
                    .onSubmit(send)

                Button("发送", action: send)
                    .buttonStyle(MinoCompactButtonStyle())
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 62)
            .padding(.bottom, 48)
        }
        .background(Color.minoCanvas)
    }

    private func send() {
        let message = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        sentMessages.append(message)
        onSend(message)
        draft = ""
    }
}

private struct IncomingMessage: View {
    let text: String

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Image(nsImage: SharedSpaceAssets.friendAvatar)
                .resizable()
                .scaledToFill()
                .frame(width: 34, height: 34)
                .clipShape(Circle())
            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(Color.minoInk)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

private struct InteractionFoundationView: View {
    let friendPetName: String
    let perform: (SharedSpaceAction) -> Void

    var body: some View {
        VStack(spacing: 0) {
            FeatureHeader(title: "今天想怎么互动？", subtitle: "选择好友后，互动会发送到对应的来访宠物")

            HStack(spacing: 18) {
                LargeInteractionButton(title: "亲亲", detail: "给\(friendPetName)一个抱抱般的亲亲", symbol: "heart.fill", action: { perform(.kiss) })
                LargeInteractionButton(title: "送花", detail: "送出一朵今天的小花", symbol: "camera.macro", action: { perform(.flower) })
                LargeInteractionButton(title: "一起散步", detail: "让两只小家伙走一走", symbol: "figure.walk", action: { perform(.walk) })
            }
            .padding(.horizontal, 62)

            Spacer()
        }
        .background(Color.minoCanvas)
    }
}

private struct LargeInteractionButton: View {
    let title: String
    let detail: String
    let symbol: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(Color.minoCoral)
                    .frame(width: 52, height: 52)
                    .background(Color.minoCoralSoft, in: Circle())

                Text(title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.minoInk)
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.minoMuted)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 170, alignment: .topLeading)
            .padding(22)
            .background(.white.opacity(isHovering ? 0.92 : 0.72), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.minoLine.opacity(0.65), lineWidth: 1))
            .shadow(color: Color.minoInk.opacity(isHovering ? 0.09 : 0.04), radius: 18, y: 8)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

private struct AvatarFoundationView: View {
    let petName: String
    @State private var importedFileName: String?
    @State private var importerVisible = false

    var body: some View {
        VStack(spacing: 0) {
            FeatureHeader(title: "宠物形象", subtitle: "这里管理你自己的宠物在桌面和好友设备上的外观")

            HStack(spacing: 34) {
                Image(nsImage: SharedSpaceAssets.friendAvatar)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 290, height: 290)
                    .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 34).stroke(.white, lineWidth: 4))
                    .shadow(color: Color.minoInk.opacity(0.09), radius: 24, y: 10)

                VStack(alignment: .leading, spacing: 18) {
                    Text("\(petName)的形象")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Color.minoInk)
                    Text("先以当前的薄荷兔形象作为设计基线。后续可以在这里增加形象选择、部件编辑和完整素材导入流程。")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.minoMuted)
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)

                    if let importedFileName {
                        Label(importedFileName, systemImage: "checkmark.circle.fill")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.minoMint)
                    }

                    Button("导入形象素材") {
                        importerVisible = true
                    }
                    .buttonStyle(MinoCompactButtonStyle())
                }
                .frame(maxWidth: 360, alignment: .leading)
            }
            .padding(.horizontal, 62)

            Spacer()
        }
        .background(Color.minoCanvas)
        .fileImporter(
            isPresented: $importerVisible,
            allowedContentTypes: [.png, .jpeg],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result {
                importedFileName = urls.first?.lastPathComponent
            }
        }
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
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(Color.minoInk)
                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.minoMuted)
            }
            Spacer()
            trailing
        }
        .padding(.top, 64)
        .padding(.horizontal, 62)
        .padding(.bottom, 34)
    }
}

private extension FeatureHeader where Trailing == EmptyView {
    init(title: String, subtitle: String) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = EmptyView()
    }
}

private struct MinoPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 206, height: 58)
            .background(Color.minoCoral.opacity(configuration.isPressed ? 0.82 : 1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: Color.minoCoral.opacity(0.18), radius: 14, y: 7)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

private struct MinoCompactButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(.white.opacity(isEnabled ? 1 : 0.72))
            .padding(.horizontal, 24)
            .frame(height: 46)
            .background(
                Color.minoCoral.opacity(isEnabled ? (configuration.isPressed ? 0.82 : 1) : 0.48),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
    }
}

private struct MinoTextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Color.minoInk.opacity(configuration.isPressed ? 0.55 : 0.82))
            .padding(.horizontal, 14)
            .frame(height: 52)
    }
}

private struct MinoRowButtonStyle: ButtonStyle {
    let isEmphasized: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(isEmphasized ? Color.white : Color.minoInk)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(
                isEmphasized
                    ? Color.minoCoral.opacity(configuration.isPressed ? 0.78 : 1)
                    : Color.minoSidebar.opacity(configuration.isPressed ? 0.62 : 1),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
    }
}
